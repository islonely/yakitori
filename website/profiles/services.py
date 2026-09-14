"""Username policy and profile updates.

All username rules live here so the same validation is applied by the web forms,
the JSON API, and tests.
"""

import re
from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from audit.models import AuditEvent
from audit.services import record

from .models import Profile, ReservedUsername, UsernameChange

# Lowercase letters, digits, and single underscores; must begin and end with a
# letter or digit. This rejects whitespace and impersonation-sensitive
# characters such as '@' (which would look like an email address).
_USERNAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9_]*[a-z0-9])?$")


class UsernameError(Exception):
    pass


def normalize_username(value):
    return (value or "").strip().lower()


def validate_username(value):
    name = normalize_username(value)
    minimum = settings.USERNAME_MIN_LENGTH
    maximum = settings.USERNAME_MAX_LENGTH

    if len(name) < minimum:
        raise UsernameError(f"Usernames must be at least {minimum} characters.")
    if len(name) > maximum:
        raise UsernameError(f"Usernames must be at most {maximum} characters.")
    if not _USERNAME_RE.match(name):
        raise UsernameError(
            "Use lowercase letters, numbers, and underscores, starting and "
            "ending with a letter or number."
        )
    if "__" in name:
        raise UsernameError("Usernames cannot contain consecutive underscores.")
    if name in settings.RESERVED_USERNAMES or ReservedUsername.objects.filter(
        name=name
    ).exists():
        raise UsernameError("That username is reserved.")
    return name


def username_available(name, for_profile=None):
    """A name is available if unused and not recently released by someone else."""
    name = normalize_username(name)
    taken = Profile.objects.filter(username_normalized=name)
    if for_profile is not None:
        taken = taken.exclude(pk=for_profile.pk)
    if taken.exists():
        return False

    cooldown = settings.USERNAME_CHANGE_COOLDOWN_DAYS
    if cooldown > 0:
        cutoff = timezone.now() - timedelta(days=cooldown)
        if UsernameChange.objects.filter(
            old_username=name, created_at__gte=cutoff
        ).exists():
            return False
    return True


def change_cooldown_remaining(profile):
    """Seconds until the profile may change its username again, or 0."""
    cooldown = settings.USERNAME_CHANGE_COOLDOWN_DAYS
    if cooldown <= 0:
        return 0
    last = profile.username_changes.order_by("-created_at").first()
    if last is None:
        return 0
    ready_at = last.created_at + timedelta(days=cooldown)
    remaining = (ready_at - timezone.now()).total_seconds()
    return max(0, int(remaining))


def set_username(profile, new_username, actor=None, enforce_cooldown=True):
    """Validate and atomically assign a new username.

    A row lock plus the unique constraint protect against two accounts claiming
    the same name concurrently.
    """
    name = validate_username(new_username)

    if profile.username_normalized == name:
        return profile

    if not username_available(name, for_profile=profile):
        raise UsernameError("That username is already taken.")

    if enforce_cooldown and change_cooldown_remaining(profile) > 0:
        days = settings.USERNAME_CHANGE_COOLDOWN_DAYS
        raise UsernameError(
            f"You can change your username again after {days} days."
        )

    try:
        with transaction.atomic():
            locked = Profile.objects.select_for_update().get(pk=profile.pk)
            old = locked.username or ""
            locked.username = name
            locked.save(
                update_fields=["username", "username_normalized", "updated_at"]
            )
            # The first choice is not a "change" and does not start a cooldown.
            if old:
                UsernameChange.objects.create(
                    profile=locked,
                    old_username=old,
                    new_username=name,
                )
    except IntegrityError:
        raise UsernameError("That username is already taken.")

    record(
        AuditEvent.Type.USERNAME_CHANGED,
        actor=actor or profile.user,
        target=profile.user,
        source="profile",
    )
    return profile


def update_profile(profile, *, display_name=None, bio=None, avatar_url=None):
    fields = []
    if display_name is not None:
        profile.display_name = display_name.strip()[:100]
        fields.append("display_name")
    if bio is not None:
        profile.bio = bio.strip()[:500]
        fields.append("bio")
    if avatar_url is not None:
        profile.avatar_url = avatar_url.strip()[:500]
        fields.append("avatar_url")
    if fields:
        fields.append("updated_at")
        profile.save(update_fields=fields)
    return profile


def update_privacy(
    profile,
    *,
    profile_visibility=None,
    stats_visibility=None,
    leaderboard_visibility=None,
    allow_following=None,
):
    fields = []
    if profile_visibility is not None:
        profile.profile_visibility = profile_visibility
        fields.append("profile_visibility")
    if stats_visibility is not None:
        profile.stats_visibility = stats_visibility
        fields.append("stats_visibility")
    if leaderboard_visibility is not None:
        profile.leaderboard_visibility = leaderboard_visibility
        fields.append("leaderboard_visibility")
    if allow_following is not None:
        profile.allow_following = allow_following
        fields.append("allow_following")
    if fields:
        fields.append("updated_at")
        profile.save(update_fields=fields)
    return profile
