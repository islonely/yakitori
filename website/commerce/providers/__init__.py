from .base import (
    Checkout,
    EventKind,
    NormalizedEvent,
    PaymentProvider,
    ProviderError,
    SignatureError,
)
from .mock import MockPaymentProvider
from .stripe_provider import StripeManagedPaymentsProvider

__all__ = [
    "Checkout",
    "EventKind",
    "NormalizedEvent",
    "PaymentProvider",
    "ProviderError",
    "SignatureError",
    "MockPaymentProvider",
    "StripeManagedPaymentsProvider",
    "get_provider",
]


def get_provider(name=None):
    from django.conf import settings

    resolved = (name or settings.PAYMENT_PROVIDER or "mock").lower()
    if resolved == "stripe":
        return StripeManagedPaymentsProvider()
    if resolved == "mock":
        return MockPaymentProvider()
    raise ProviderError(f"Unknown payment provider: {resolved}")
