"""Development payment provider.

It performs no network calls and makes the entire purchase -> license flow
testable locally. It also demonstrates that commerce is provider-agnostic.
"""

import hashlib
import hmac
import json
import uuid

from django.conf import settings
from django.urls import reverse

from .base import (
    Checkout,
    EventKind,
    NormalizedEvent,
    PaymentProvider,
    SignatureError,
)

_TYPE_MAP = {
    "purchase.completed": EventKind.PURCHASE_COMPLETED,
    "refund.issued": EventKind.REFUND_ISSUED,
    "dispute.opened": EventKind.DISPUTE_OPENED,
    "dispute.resolved": EventKind.DISPUTE_RESOLVED,
    "purchase.restored": EventKind.PURCHASE_RESTORED,
}


def _secret():
    return settings.STRIPE_WEBHOOK_SECRET or "mock-webhook-secret"


def sign_payload(body: bytes) -> str:
    return hmac.new(_secret().encode("utf-8"), body, hashlib.sha256).hexdigest()


def build_event(kind, purchase, *, amount=None):
    """Build a mock webhook payload for the given event kind."""
    type_name = {
        EventKind.PURCHASE_COMPLETED: "purchase.completed",
        EventKind.REFUND_ISSUED: "refund.issued",
        EventKind.DISPUTE_OPENED: "dispute.opened",
        EventKind.DISPUTE_RESOLVED: "dispute.resolved",
        EventKind.PURCHASE_RESTORED: "purchase.restored",
    }[kind]

    data = {
        "purchase_id": purchase.provider_purchase_id or str(purchase.id),
        "checkout_id": purchase.provider_checkout_id,
        "customer_id": purchase.provider_customer_id,
        "amount": amount if amount is not None else purchase.amount,
        "currency": purchase.currency,
    }
    return {
        "id": f"evt_{uuid.uuid4().hex}",
        "type": type_name,
        "data": data,
    }


class MockPaymentProvider(PaymentProvider):
    name = "mock"

    def create_checkout(self, purchase) -> Checkout:
        # The purchase id doubles as the provider purchase id in the mock.
        provider_purchase_id = str(purchase.id)
        return Checkout(
            provider_checkout_id=str(purchase.id),
            url=reverse("commerce:mock-checkout", args=[purchase.id]),
        )

    def verify_webhook(self, request) -> NormalizedEvent:
        signature = request.META.get("HTTP_X_MOCK_SIGNATURE", "")
        expected = sign_payload(request.body)
        if not hmac.compare_digest(signature, expected):
            raise SignatureError("Invalid mock webhook signature.")

        try:
            payload = json.loads(request.body.decode("utf-8") or "{}")
        except (ValueError, UnicodeDecodeError):
            raise SignatureError("Webhook body is not valid JSON.")

        return self.normalize_event(
            payload.get("type", ""),
            payload.get("data", {}),
            event_id=payload.get("id", ""),
            payload=payload,
        )

    def normalize_event(self, event_type, data, *, event_id, payload) -> NormalizedEvent:
        return NormalizedEvent(
            kind=_TYPE_MAP.get(event_type, EventKind.OTHER),
            external_id=event_id or uuid.uuid4().hex,
            event_type=event_type,
            provider_purchase_id=str(data.get("purchase_id", "")),
            provider_customer_id=str(data.get("customer_id", "")),
            provider_checkout_id=str(data.get("checkout_id", "")),
            amount=int(data.get("amount", 0) or 0),
            currency=str(data.get("currency", "")),
            raw=payload,
        )

    def build_event(self, kind, purchase, amount=None) -> NormalizedEvent:
        raw = build_event(kind, purchase, amount=amount)
        return self.normalize_event(
            raw["type"], raw["data"], event_id=raw["id"], payload=raw
        )

    def supports_mock_completion(self) -> bool:
        return True
