import uuid

from django.conf import settings
from django.db import models


class Profile(models.Model):
    """A writer's public presence.

    Kept separate from `accounts.User` so that commerce and identity data are
    never mistaken for public profile data. `user` is the stable link across all
    domains.
    """

    class Visibility(models.TextChoices):
        PUBLIC = "public", "Public"
        PRIVATE = "private", "Private"

    class StatsVisibility(models.TextChoices):
        PRIVATE = "private", "Private"
        FOLLOWERS = "followers", "Followers only"
        PUBLIC = "public", "Public"

    class LeaderboardVisibility(models.TextChoices):
        OFF = "off", "Not on leaderboards"
        FOLLOWERS = "followers", "Followers only"
        GLOBAL = "global", "Public leaderboards"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile",
    )

    # Null until the writer chooses one. Case-insensitive uniqueness is enforced
    # through `username_normalized`.
    username = models.CharField(max_length=30, null=True, blank=True, unique=True)
    username_normalized = models.CharField(
        max_length=30, null=True, blank=True, unique=True, editable=False
    )

    display_name = models.CharField(max_length=100, blank=True)
    bio = models.TextField(max_length=500, blank=True)
    avatar_url = models.URLField(max_length=500, blank=True)

    # Privacy is a set of independent choices, not one switch.
    profile_visibility = models.CharField(
        max_length=20,
        choices=Visibility.choices,
        default=Visibility.PUBLIC,
    )
    stats_visibility = models.CharField(
        max_length=20,
        choices=StatsVisibility.choices,
        default=StatsVisibility.PRIVATE,
    )
    leaderboard_visibility = models.CharField(
        max_length=20,
        choices=LeaderboardVisibility.choices,
        default=LeaderboardVisibility.OFF,
    )
    allow_following = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("username",)

    def __str__(self):
        return self.username or f"profile:{self.user_id}"

    def save(self, *args, **kwargs):
        self.username_normalized = (
            (self.username or "").lower() or None
        )
        self.username = self.username_normalized
        super().save(*args, **kwargs)

    @property
    def is_public(self):
        return self.profile_visibility == self.Visibility.PUBLIC

    @property
    def shows_stats_publicly(self):
        return self.stats_visibility == self.StatsVisibility.PUBLIC

    @property
    def on_public_leaderboard(self):
        return self.leaderboard_visibility == self.LeaderboardVisibility.GLOBAL


class UsernameChange(models.Model):
    """History of username changes, used for cooldown and abuse review."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.ForeignKey(
        Profile,
        on_delete=models.CASCADE,
        related_name="username_changes",
    )
    old_username = models.CharField(max_length=30, blank=True)
    new_username = models.CharField(max_length=30)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.old_username or '—'} → {self.new_username}"


class ReservedUsername(models.Model):
    """Configurable reserved names. Seeded from settings; extendable in admin."""

    name = models.CharField(max_length=30, unique=True)
    reason = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("name",)

    def save(self, *args, **kwargs):
        self.name = (self.name or "").lower()
        super().save(*args, **kwargs)

    def __str__(self):
        return self.name
