import uuid

from django.conf import settings
from django.db import models


class License(models.Model):
    """A lifetime entitlement owned by an account.

    Licenses are never deleted. A refund or chargeback changes the status.
    A license is not tied to a device; installations are recorded separately.
    """

    class Type(models.TextChoices):
        LIFETIME = "lifetime", "Lifetime"

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        REVOKED = "revoked", "Revoked"
        DISABLED = "disabled", "Disabled"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="licenses",
    )

    product = models.CharField(max_length=100, default="Yakitori")
    license_type = models.CharField(
        max_length=40,
        choices=Type.choices,
        default=Type.LIFETIME,
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE,
    )

    purchased_at = models.DateTimeField(null=True, blank=True)
    # Lifetime licenses never expire. Kept for future non-lifetime products.
    expires_at = models.DateTimeField(null=True, blank=True)

    payment_purchase = models.ForeignKey(
        "commerce.PaymentPurchase",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="licenses",
    )

    revocation_reason = models.CharField(max_length=200, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["user", "product"],
                name="unique_license_per_product",
            ),
        ]

    def __str__(self):
        return f"license:{self.user_id}:{self.product}:{self.status}"

    @property
    def is_active(self):
        return self.status == self.Status.ACTIVE


class Installation(models.Model):
    """A registered app installation belonging to an account.

    There is no device limit. The installation id is a random value generated
    by the app and stored in the macOS Keychain; it is never derived from
    hardware identifiers.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="installations",
    )

    installation_id = models.UUIDField(unique=True, db_index=True)
    platform = models.CharField(max_length=40, default="macOS")
    app_version = models.CharField(max_length=40, blank=True)

    first_seen_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    revoked_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-last_seen_at",)

    def __str__(self):
        return f"install:{self.installation_id}"

    @property
    def is_active(self):
        return self.revoked_at is None
