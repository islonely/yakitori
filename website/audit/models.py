import uuid

from django.conf import settings
from django.db import models


class AuditEvent(models.Model):
    """An append-only record of security- and commerce-relevant actions.

    Events are never updated or deleted through the application. Metadata must
    never contain secrets, tokens, payment-card data, or manuscript content.
    """

    class Type(models.TextChoices):
        LOGIN_SUCCEEDED = "login.succeeded", "Login succeeded"
        LOGIN_FAILED = "login.failed", "Login failed"
        LOGOUT = "logout", "Logout"
        ACCOUNT_CREATED = "account.created", "Account created"
        ACCOUNT_SUSPENDED = "account.suspended", "Account suspended"
        ACCOUNT_DELETION_REQUESTED = "account.deletion_requested", "Account deletion requested"
        ACCOUNT_DELETED = "account.deleted", "Account deleted"
        TOKEN_CREATED = "token.created", "API token created"
        TOKEN_REVOKED = "token.revoked", "API token revoked"
        DEVICE_APPROVED = "device.approved", "Device approved"
        DEVICE_DENIED = "device.denied", "Device denied"
        USERNAME_CHANGED = "username.changed", "Username changed"
        PURCHASE_ASSOCIATED = "purchase.associated", "Purchase associated"
        LICENSE_CREATED = "license.created", "License created"
        LICENSE_VALIDATED = "license.validated", "License validated"
        LICENSE_REVOKED = "license.revoked", "License revoked"
        LICENSE_RESTORED = "license.restored", "License restored"
        TRIAL_STARTED = "trial.started", "Free trial started"
        INSTALLATION_REGISTERED = "installation.registered", "Installation registered"
        INSTALLATION_REVOKED = "installation.revoked", "Installation revoked"
        REFUND_RECORDED = "refund.recorded", "Refund recorded"
        DISPUTE_OPENED = "dispute.opened", "Dispute opened"
        DISPUTE_RESOLVED = "dispute.resolved", "Dispute resolved"
        ADMIN_ACTION = "admin.action", "Administrative action"
        SECURITY_EVENT = "security.event", "Security event"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    actor_user_id = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="audit_events_actor",
    )
    target_user_id = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="audit_events_target",
    )

    event_type = models.CharField(max_length=60, db_index=True)
    source = models.CharField(max_length=60, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["event_type", "created_at"]),
            models.Index(fields=["target_user_id", "created_at"]),
        ]

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ValueError("Audit events are append-only and cannot be modified.")
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.event_type} at {self.created_at:%Y-%m-%d %H:%M}"
