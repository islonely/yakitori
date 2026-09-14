import uuid

from django.conf import settings
from django.db import models


class PaymentPurchase(models.Model):
    """A purchase record, kept separate from licensing.

    Provider-specific fields live here behind a narrow provider abstraction so
    the commerce provider can change without rewriting licensing.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        COMPLETED = "completed", "Completed"
        REFUNDED = "refunded", "Refunded"
        PARTIALLY_REFUNDED = "partially_refunded", "Partially refunded"
        DISPUTED = "disputed", "Disputed"
        CANCELLED = "cancelled", "Cancelled"
        FAILED = "failed", "Failed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="purchases",
    )

    provider = models.CharField(max_length=40)
    provider_customer_id = models.CharField(max_length=200, blank=True)
    provider_purchase_id = models.CharField(max_length=200, blank=True, db_index=True)
    provider_checkout_id = models.CharField(max_length=200, blank=True, db_index=True)
    provider_product_id = models.CharField(max_length=200, blank=True)
    provider_price_id = models.CharField(max_length=200, blank=True)

    amount = models.PositiveIntegerField(default=0)
    currency = models.CharField(max_length=10, default="usd")

    status = models.CharField(
        max_length=30,
        choices=Status.choices,
        default=Status.PENDING,
    )

    purchased_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "provider_purchase_id"],
                condition=~models.Q(provider_purchase_id=""),
                name="unique_provider_purchase",
            ),
        ]

    def __str__(self):
        return f"{self.provider}:{self.provider_purchase_id or self.id}"


class PurchaseClaim(models.Model):
    """A request to associate a purchase with an account.

    Claims are never auto-approved: ambiguous ownership goes to an
    administrator. This is what prevents "I know your email, therefore I own
    your purchase".
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="purchase_claims",
    )
    purchase = models.ForeignKey(
        PaymentPurchase,
        on_delete=models.CASCADE,
        related_name="claims",
    )

    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING
    )
    note = models.TextField(max_length=2000, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="purchase_claims_resolved",
    )

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["user", "purchase"],
                name="unique_purchase_claim",
            ),
        ]

    def __str__(self):
        return f"claim:{self.user_id}:{self.purchase_id}:{self.status}"


class WebhookEvent(models.Model):
    """Inbound provider event, stored for idempotency and debugging.

    `external_id` is unique, which is how duplicate deliveries are detected.
    Payloads may contain payment metadata but never card numbers.
    """

    class Status(models.TextChoices):
        RECEIVED = "received", "Received"
        PROCESSED = "processed", "Processed"
        IGNORED = "ignored", "Ignored"
        ERROR = "error", "Error"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    provider = models.CharField(max_length=40)
    external_id = models.CharField(max_length=200, unique=True)
    event_type = models.CharField(max_length=80)
    payload = models.JSONField(default=dict, blank=True)

    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.RECEIVED
    )
    error = models.TextField(blank=True)

    received_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-received_at",)

    def __str__(self):
        return f"{self.provider}:{self.event_type}:{self.external_id}"
