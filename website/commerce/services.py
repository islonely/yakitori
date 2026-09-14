"""Commerce services.

The authoritative signal for ownership is a **verified server-side event**, not
a success-page redirect and not a client-supplied flag.
"""

import logging
import uuid

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from audit.models import AuditEvent
from audit.services import record

from .models import PaymentPurchase, WebhookEvent
from .providers import EventKind, ProviderError, get_provider
from .signals import purchase_event

logger = logging.getLogger(__name__)


def start_purchase(user):
    """Create a pending purchase and a provider checkout. Returns (purchase, checkout)."""
    provider = get_provider()
    purchase = PaymentPurchase.objects.create(
        user=user,
        provider=provider.name,
        provider_product_id=settings.STRIPE_PRODUCT_ID,
        provider_price_id=settings.STRIPE_PRICE_ID,
        amount=settings.PRODUCT_PRICE_AMOUNT,
        currency=settings.PRODUCT_PRICE_CURRENCY,
        status=PaymentPurchase.Status.PENDING,
    )
    checkout = provider.create_checkout(purchase)

    update_fields = ["provider_checkout_id", "updated_at"]
    purchase.provider_checkout_id = checkout.provider_checkout_id
    # The mock provider uses the purchase id as its provider purchase id so the
    # rest of the flow behaves exactly like a real provider's.
    if provider.name == "mock" and not purchase.provider_purchase_id:
        purchase.provider_purchase_id = str(purchase.id)
        update_fields.append("provider_purchase_id")
    purchase.save(update_fields=update_fields)

    return purchase, checkout


def locate_purchase(event):
    if event.provider_purchase_id:
        found = PaymentPurchase.objects.filter(
            provider_purchase_id=event.provider_purchase_id
        ).first()
        if found is not None:
            return found
    if event.provider_checkout_id:
        return PaymentPurchase.objects.filter(
            provider_checkout_id=event.provider_checkout_id
        ).first()
    return None


def _apply(purchase, event):
    """Update purchase state from a normalized event. Returns True if changed."""
    now = timezone.now()
    changed = False

    if event.kind == EventKind.PURCHASE_COMPLETED:
        if purchase.status != PaymentPurchase.Status.COMPLETED:
            purchase.status = PaymentPurchase.Status.COMPLETED
            purchase.purchased_at = purchase.purchased_at or now
            changed = True
        if event.provider_customer_id and (
            event.provider_customer_id != purchase.provider_customer_id
        ):
            purchase.provider_customer_id = event.provider_customer_id
            changed = True
        if event.provider_purchase_id and not purchase.provider_purchase_id:
            purchase.provider_purchase_id = event.provider_purchase_id
            changed = True

    elif event.kind == EventKind.REFUND_ISSUED:
        if event.amount and purchase.amount and event.amount < purchase.amount:
            purchase.status = PaymentPurchase.Status.PARTIALLY_REFUNDED
        else:
            purchase.status = PaymentPurchase.Status.REFUNDED
        changed = True

    elif event.kind == EventKind.DISPUTE_OPENED:
        purchase.status = PaymentPurchase.Status.DISPUTED
        changed = True

    elif event.kind in (EventKind.DISPUTE_RESOLVED, EventKind.PURCHASE_RESTORED):
        purchase.status = PaymentPurchase.Status.COMPLETED
        changed = True

    return changed


def _audit(purchase, event):
    if event.kind == EventKind.REFUND_ISSUED:
        record(
            AuditEvent.Type.REFUND_RECORDED,
            target=purchase.user,
            source="commerce",
            purchase=str(purchase.id),
            amount=event.amount,
        )
    elif event.kind == EventKind.DISPUTE_OPENED:
        record(
            AuditEvent.Type.DISPUTE_OPENED,
            target=purchase.user,
            source="commerce",
            purchase=str(purchase.id),
        )
    elif event.kind == EventKind.DISPUTE_RESOLVED:
        record(
            AuditEvent.Type.DISPUTE_RESOLVED,
            target=purchase.user,
            source="commerce",
            purchase=str(purchase.id),
        )


def apply_event(event):
    """Apply a normalized event idempotently and notify listeners."""
    purchase = locate_purchase(event)
    if purchase is None:
        logger.warning("commerce_event_no_purchase kind=%s", event.kind.value)
        return None

    with transaction.atomic():
        purchase = PaymentPurchase.objects.select_for_update().get(pk=purchase.pk)
        _apply(purchase, event)
        purchase.save()

    _audit(purchase, event)
    # Licensing reacts to this signal; commerce stays provider- and
    # license-agnostic.
    purchase_event.send(sender=PaymentPurchase, purchase=purchase, event=event)
    return purchase


def process_webhook(request, provider=None):
    """Verify, de-duplicate, and apply an inbound webhook.

    Returns ``(webhook_event, created)``. The caller maps ProviderError to a
    400 and success to a 200 so providers retry only on real failures.
    """
    provider = provider or get_provider()
    event = provider.verify_webhook(request)

    if not event.external_id:
        event.external_id = f"{provider.name}:{uuid.uuid4().hex}"

    webhook, created = WebhookEvent.objects.get_or_create(
        external_id=event.external_id,
        defaults={
            "provider": provider.name,
            "event_type": event.event_type,
            "payload": event.raw,
        },
    )
    if not created:
        # Duplicate delivery: acknowledge without reprocessing.
        return webhook, False

    try:
        apply_event(event)
    except Exception as exc:  # noqa: BLE001
        webhook.status = WebhookEvent.Status.ERROR
        webhook.error = str(exc)[:1000]
        webhook.save(update_fields=["status", "error"])
        raise

    webhook.status = WebhookEvent.Status.PROCESSED
    webhook.processed_at = timezone.now()
    webhook.save(update_fields=["status", "processed_at"])
    return webhook, True


def simulate_event(purchase, kind, amount=None):
    """Development helper: apply an event as if the provider delivered it."""
    provider = get_provider()
    if not provider.supports_mock_completion():
        raise ProviderError("This provider does not support simulated events.")

    event = provider.build_event(kind, purchase, amount=amount)
    webhook = WebhookEvent.objects.create(
        provider=provider.name,
        external_id=event.external_id,
        event_type=event.event_type,
        payload=event.raw,
        status=WebhookEvent.Status.PROCESSED,
        processed_at=timezone.now(),
    )
    apply_event(event)
    return webhook
