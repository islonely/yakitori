from django.dispatch import receiver

from commerce.providers import EventKind
from commerce.signals import purchase_event

from . import services


@receiver(purchase_event)
def on_purchase_event(sender, purchase, event, **kwargs):
    """Keep licenses in sync with verified purchase events.

    This is the only coupling between commerce and licensing, and it runs in
    the licensing direction so commerce has no licensing dependency.
    """
    if event.kind == EventKind.PURCHASE_COMPLETED:
        services.grant_lifetime_license(purchase)
    elif event.kind == EventKind.REFUND_ISSUED:
        services.revoke_license_for_purchase(purchase, reason="refund")
    elif event.kind == EventKind.DISPUTE_OPENED:
        services.disable_license_for_purchase(purchase, reason="dispute")
    elif event.kind in (EventKind.DISPUTE_RESOLVED, EventKind.PURCHASE_RESTORED):
        services.restore_license_for_purchase(purchase)
