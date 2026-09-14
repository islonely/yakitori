from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class EventKind(str, Enum):
    """Normalized, provider-independent event kinds."""

    PURCHASE_COMPLETED = "purchase_completed"
    REFUND_ISSUED = "refund_issued"
    DISPUTE_OPENED = "dispute_opened"
    DISPUTE_RESOLVED = "dispute_resolved"
    PURCHASE_RESTORED = "purchase_restored"
    OTHER = "other"


@dataclass
class NormalizedEvent:
    kind: EventKind
    external_id: str
    event_type: str = ""
    provider_purchase_id: str = ""
    provider_customer_id: str = ""
    provider_checkout_id: str = ""
    amount: int = 0
    currency: str = ""
    occurred_at: datetime | None = None
    raw: dict = field(default_factory=dict)


@dataclass
class Checkout:
    provider_checkout_id: str
    url: str


class ProviderError(Exception):
    pass


class SignatureError(ProviderError):
    """Raised when a webhook signature cannot be verified."""


class PaymentProvider:
    """The narrow commerce seam described in the platform specification."""

    name = ""

    def create_checkout(self, purchase) -> Checkout:
        raise NotImplementedError

    def verify_webhook(self, request) -> NormalizedEvent:
        raise NotImplementedError

    def normalize_event(self, event_type, data, *, event_id, payload) -> NormalizedEvent:
        raise NotImplementedError

    def build_event(self, kind, purchase, amount=None) -> NormalizedEvent:
        """Build a synthetic event (development/test providers only)."""
        raise NotImplementedError

    def supports_mock_completion(self) -> bool:
        return False
