"""Stripe Managed Payments provider.

This is the production commerce path. It requires credentials and is only
constructed when `PAYMENT_PROVIDER=stripe` and `STRIPE_SECRET_KEY` is set, so
local development and tests never touch Stripe.

Only a verified server-side webhook is authoritative; the success-page redirect
is never trusted to grant a license.
"""

from django.conf import settings

from .base import (
    Checkout,
    EventKind,
    NormalizedEvent,
    PaymentProvider,
    ProviderError,
    SignatureError,
)

_STRIPE_EVENT_MAP = {
    "checkout.session.completed": EventKind.PURCHASE_COMPLETED,
    "checkout.session.async_payment_succeeded": EventKind.PURCHASE_COMPLETED,
    "payment_intent.succeeded": EventKind.PURCHASE_COMPLETED,
    "charge.succeeded": EventKind.PURCHASE_COMPLETED,
    "charge.refunded": EventKind.REFUND_ISSUED,
    "refund.created": EventKind.REFUND_ISSUED,
    "charge.dispute.created": EventKind.DISPUTE_OPENED,
    "charge.dispute.closed": EventKind.DISPUTE_RESOLVED,
    "charge.dispute.funds_reinstated": EventKind.PURCHASE_RESTORED,
}


class StripeManagedPaymentsProvider(PaymentProvider):
    name = "stripe"

    def __init__(self):
        if not settings.STRIPE_SECRET_KEY:
            raise ProviderError("Stripe is not configured (STRIPE_SECRET_KEY).")

        import stripe

        self.stripe = stripe
        stripe.api_key = settings.STRIPE_SECRET_KEY
        if settings.STRIPE_API_VERSION:
            stripe.api_version = settings.STRIPE_API_VERSION

    def create_checkout(self, purchase) -> Checkout:
        if not settings.STRIPE_PRICE_ID:
            raise ProviderError("STRIPE_PRICE_ID is not configured.")

        session = self.stripe.checkout.Session.create(
            mode="payment",
            line_items=[{"price": settings.STRIPE_PRICE_ID, "quantity": 1}],
            success_url=f"{settings.APP_BASE_URL}/buy/success/",
            cancel_url=f"{settings.APP_BASE_URL}/buy/cancel/",
            client_reference_id=str(purchase.id),
            metadata={
                "purchase_id": str(purchase.id),
                "user_id": str(purchase.user_id),
            },
        )
        return Checkout(provider_checkout_id=session.id, url=session.url)

    def verify_webhook(self, request) -> NormalizedEvent:
        signature = request.META.get("HTTP_STRIPE_SIGNATURE", "")
        try:
            event = self.stripe.Webhook.construct_event(
                request.body,
                signature,
                settings.STRIPE_WEBHOOK_SECRET,
            )
        except Exception as exc:  # noqa: BLE001 - normalize all verification failures
            raise SignatureError("Invalid Stripe webhook signature.") from exc

        payload = dict(event)
        return self.normalize_event(
            payload.get("type", ""),
            payload.get("data", {}).get("object", {}),
            event_id=payload.get("id", ""),
            payload=payload,
        )

    def normalize_event(self, event_type, data, *, event_id, payload) -> NormalizedEvent:
        amount = data.get("amount_total")
        if amount is None:
            amount = data.get("amount")
        if amount is None:
            amount = data.get("amount_refunded", 0)

        return NormalizedEvent(
            kind=_STRIPE_EVENT_MAP.get(event_type, EventKind.OTHER),
            external_id=event_id or "",
            event_type=event_type,
            provider_purchase_id=str(
                data.get("payment_intent")
                or data.get("id")
                or data.get("payment_intent_id")
                or ""
            ),
            provider_customer_id=str(data.get("customer") or data.get("customer_id") or ""),
            provider_checkout_id=str(data.get("id") or ""),
            amount=int(amount or 0),
            currency=str(data.get("currency") or ""),
            raw=payload,
        )
