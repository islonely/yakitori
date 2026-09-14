from django.dispatch import Signal

# Sent after a purchase record is updated by a verified provider event.
# Licensing connects to this so commerce never imports licensing directly.
# kwargs: purchase, event
purchase_event = Signal()
