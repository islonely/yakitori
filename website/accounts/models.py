import uuid

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    """Email-first user manager.

    The email address is the login identifier. `email_normalized` is a unique,
    lowercase copy used for lookups so that case differences cannot create
    duplicate accounts. It is never shown publicly.
    """

    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError("An email address is required.")
        email = email.strip()
        user = self.model(email=email, **extra_fields)
        if password:
            user.set_password(password)
        else:
            # Ordinary accounts are passwordless. Only staff need a password.
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("status", User.Status.ACTIVE)
        extra_fields.setdefault("email_verified_at", timezone.now())
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self._create_user(email, password, **extra_fields)


class User(AbstractUser):
    """The stable identity that ties every platform domain together."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        SUSPENDED = "suspended", "Suspended"
        PENDING_DELETION = "pending_deletion", "Pending deletion"
        DELETED = "deleted", "Deleted"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    username = None
    first_name = None
    last_name = None

    email = models.EmailField(unique=True)
    email_normalized = models.CharField(
        max_length=254,
        unique=True,
        editable=False,
        db_index=True,
    )
    email_verified_at = models.DateTimeField(null=True, blank=True)

    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE,
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = UserManager()

    class Meta:
        ordering = ("-created_at",)

    def save(self, *args, **kwargs):
        self.email = (self.email or "").strip()
        self.email_normalized = self.email.lower()
        # `status` is the platform's source of truth; Django's authentication
        # backend checks the boolean `is_active` field, so keep it in sync.
        # Writing it here guarantees suspension/deletion always blocks sign-in,
        # regardless of which code path changed the status.
        self.is_active = (
            self.status == self.Status.ACTIVE and self.deleted_at is None
        )
        super().save(*args, **kwargs)

    def __str__(self):
        return self.email

    @property
    def can_sign_in(self):
        return self.is_active

    def mark_email_verified(self):
        if self.email_verified_at is None:
            self.email_verified_at = timezone.now()
            self.save(update_fields=["email_verified_at", "updated_at"])


class LoginChallenge(models.Model):
    """A single-use, short-lived passwordless login attempt.

    Only hashes of the token and code are stored. A challenge proves ownership
    of an email address; it does not itself grant access.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email_normalized = models.CharField(max_length=254, db_index=True)

    token_hash = models.CharField(max_length=64, unique=True)
    code_hash = models.CharField(max_length=64)

    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    consumed_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveIntegerField(default=0)
    request_ip = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["email_normalized", "expires_at"])]

    def __str__(self):
        return f"login:{self.email_normalized}"

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at

    @property
    def is_usable(self):
        return self.consumed_at is None and not self.is_expired


class ApiToken(models.Model):
    """A long-lived credential for a native installation.

    Stored hashed; the plaintext is shown once at creation and kept only in the
    macOS Keychain. Installation is referenced by UUID rather than a foreign key
    so identity does not depend on the licensing app.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="api_tokens",
    )
    label = models.CharField(max_length=120, blank=True)
    installation_uuid = models.UUIDField(null=True, blank=True, db_index=True)

    token_hash = models.CharField(max_length=64, unique=True)

    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "revoked_at"])]

    def __str__(self):
        return self.label or f"token:{self.pk}"

    @property
    def is_valid(self):
        if self.revoked_at is not None:
            return False
        if self.expires_at is not None and timezone.now() >= self.expires_at:
            return False
        return True


class RateLimitEntry(models.Model):
    """A DB-backed fixed-window counter.

    Rate limiting must be server-side; this table is shared by all actions and
    is intentionally simple. Keys are namespaced (for example `login-request:ip:1.2.3.4`).
    """

    key = models.CharField(max_length=255, unique=True)
    attempts = models.PositiveIntegerField(default=0)
    reset_at = models.DateTimeField()

    class Meta:
        indexes = [models.Index(fields=["reset_at"])]

    def __str__(self):
        return f"{self.key}: {self.attempts}"


class DeviceAuthorization(models.Model):
    """RFC-8628-style device authorization for the macOS app.

    The app shows a short `user_code`; the user approves it in the browser. The
    app polls with its private `device_code` and, once approved, exchanges it
    for an `ApiToken` stored in the Keychain.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        DENIED = "denied", "Denied"
        CONSUMED = "consumed", "Consumed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    device_code_hash = models.CharField(max_length=64, unique=True)
    user_code = models.CharField(max_length=16, unique=True, db_index=True)

    client_name = models.CharField(max_length=120, blank=True)

    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
    )

    user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="device_authorizations",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    approved_at = models.DateTimeField(null=True, blank=True)
    consumed_at = models.DateTimeField(null=True, blank=True)
    last_polled_at = models.DateTimeField(null=True, blank=True)
    poll_interval = models.PositiveIntegerField(default=5)

    def __str__(self):
        return self.user_code

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at
