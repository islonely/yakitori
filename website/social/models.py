import uuid

from django.conf import settings
from django.db import models
from django.db.models import F, Q


class Follow(models.Model):
    """A directed follow relationship between two accounts."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    follower = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="following_edges",
    )
    followed = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="follower_edges",
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["follower", "followed"],
                name="unique_follow_edge",
            ),
            models.CheckConstraint(
                condition=~Q(follower=F("followed")),
                name="no_self_follow",
            ),
        ]
        indexes = [
            models.Index(fields=["follower", "created_at"]),
            models.Index(fields=["followed", "created_at"]),
        ]

    def __str__(self):
        return f"{self.follower_id} → {self.followed_id}"


class Block(models.Model):
    """A block is one-directional but enforced mutually for visibility."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    blocker = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="block_edges",
    )
    blocked = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="blocked_by_edges",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["blocker", "blocked"],
                name="unique_block_edge",
            ),
            models.CheckConstraint(
                condition=~Q(blocker=F("blocked")),
                name="no_self_block",
            ),
        ]
        indexes = [
            models.Index(fields=["blocker"]),
            models.Index(fields=["blocked"]),
        ]

    def __str__(self):
        return f"{self.blocker_id} ⊘ {self.blocked_id}"


class Report(models.Model):
    """An abuse report. Moderation UI can be built on top of this."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        REVIEWING = "reviewing", "Reviewing"
        ACTIONED = "actioned", "Actioned"
        DISMISSED = "dismissed", "Dismissed"

    class Category(models.TextChoices):
        SPAM = "spam", "Spam"
        HARASSMENT = "harassment", "Harassment"
        IMPERSONATION = "impersonation", "Impersonation"
        CHEATING = "cheating", "Leaderboard cheating"
        OTHER = "other", "Other"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reports_made",
    )
    target = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reports_received",
    )

    category = models.CharField(
        max_length=30, choices=Category.choices, default=Category.OTHER
    )
    details = models.TextField(max_length=2000, blank=True)

    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reports_reviewed",
    )

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"report:{self.target_id}:{self.category}"
