import math
import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


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

    # Set the first time this installation starts a free trial. A second trial
    # is refused on an installation that has already consumed one, even for a
    # different account.
    trial_consumed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-last_seen_at",)

    def __str__(self):
        return f"install:{self.installation_id}"

    @property
    def is_active(self):
        return self.revoked_at is None


class Trial(models.Model):
    """A one-time 14-day free trial, tied to an account.

    Tying the trial to an account is what makes it non-repeatable: the server
    already knows whether the account has used its trial, so signing out and
    back in (or reinstalling) cannot restart it. The installation that consumed
    a trial is recorded as a secondary guard against creating a new account to
    get a fresh trial on the same Mac.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="trial",
    )

    started_at = models.DateTimeField(auto_now_add=True)
    ends_at = models.DateTimeField()
    installation_uuid = models.UUIDField(null=True, blank=True)

    class Meta:
        ordering = ("-started_at",)

    def __str__(self):
        return f"trial:{self.user_id}"

    @property
    def is_active(self):
        return timezone.now() < self.ends_at

    @property
    def days_remaining(self):
        seconds = (self.ends_at - timezone.now()).total_seconds()
        return max(0, math.ceil(seconds / 86400))


class MachineTrial(models.Model):
    """Records that a physical Mac has consumed a free trial.

    The value stored is a **device-computed** SHA-256 digest of the machine's
    hardware UUID. The app hashes the UUID on the Mac, so the raw value never
    reaches the server at all; this table holds the minimum data needed to stop
    a second trial on the same machine.

    This is a deliberate, trial-only exception to the "no hardware
    fingerprinting" rule that governs *licensing*: licenses remain tied to the
    account, not to a device.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    machine_hash = models.CharField(max_length=64, unique=True, db_index=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="machine_trials",
    )
    trial = models.ForeignKey(
        Trial,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="machines",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return self.machine_hash[:12]
