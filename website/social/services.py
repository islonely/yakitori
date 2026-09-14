"""Social graph services: follows, blocks, and reports.

Privacy and blocking are enforced here so both the HTML and JSON surfaces share
the same rules.
"""

from django.db.models import Q

from audit.models import AuditEvent
from audit.services import record

from .models import Block, Follow, Report


class SocialError(Exception):
    pass


def _authenticated(user):
    return user is not None and getattr(user, "is_authenticated", False)


def blocks_between(user_a, user_b):
    if not _authenticated(user_a) or not _authenticated(user_b):
        return False
    return Block.objects.filter(
        Q(blocker=user_a, blocked=user_b) | Q(blocker=user_b, blocked=user_a)
    ).exists()


def is_following(follower, followed_user):
    if not _authenticated(follower):
        return False
    return Follow.objects.filter(follower=follower, followed=followed_user).exists()


def follow(follower, target_user):
    from profiles.models import Profile

    if follower.pk == target_user.pk:
        raise SocialError("You cannot follow yourself.")

    # Read the flag from the database so a stale related-object cache can never
    # let a follow through after the target disabled following.
    allow_following = (
        Profile.objects
        .filter(user=target_user)
        .values_list("allow_following", flat=True)
        .first()
    )
    if allow_following is False:
        raise SocialError("This writer is not accepting new followers.")
    if blocks_between(follower, target_user):
        raise SocialError("Unable to follow this writer.")

    edge, created = Follow.objects.get_or_create(
        follower=follower, followed=target_user
    )
    return edge, created


def unfollow(follower, target_user):
    deleted, _ = Follow.objects.filter(
        follower=follower, followed=target_user
    ).delete()
    return deleted > 0


def followers_queryset(user):
    return (
        Follow.objects
        .filter(followed=user)
        .select_related("follower", "follower__profile")
        .order_by("-created_at")
    )


def following_queryset(user):
    return (
        Follow.objects
        .filter(follower=user)
        .select_related("followed", "followed__profile")
        .order_by("-created_at")
    )


def counts(user):
    """Return ``(followers, following)`` counts."""
    return (
        Follow.objects.filter(followed=user).count(),
        Follow.objects.filter(follower=user).count(),
    )


def can_view_profile(profile, viewer):
    """Visibility rules.

    Order matters: owners always see their own profile, blocks hide everything,
    public profiles are open, and followers may see a private profile.
    """
    owner = profile.user

    if _authenticated(viewer) and viewer.pk == owner.pk:
        return True
    if _authenticated(viewer) and blocks_between(viewer, owner):
        return False
    if profile.is_public:
        return True
    if _authenticated(viewer):
        return Follow.objects.filter(follower=viewer, followed=owner).exists()
    return False


def block(blocker, target_user):
    if blocker.pk == target_user.pk:
        raise SocialError("You cannot block yourself.")

    Block.objects.get_or_create(blocker=blocker, blocked=target_user)
    # A block ends any follow relationship in either direction.
    Follow.objects.filter(follower=blocker, followed=target_user).delete()
    Follow.objects.filter(follower=target_user, followed=blocker).delete()

    record(
        AuditEvent.Type.SECURITY_EVENT,
        actor=blocker,
        target=target_user,
        source="social",
        action="block",
    )


def unblock(blocker, target_user):
    deleted, _ = Block.objects.filter(
        blocker=blocker, blocked=target_user
    ).delete()
    return deleted > 0


def report(reporter, target_user, category, details=""):
    if reporter.pk == target_user.pk:
        raise SocialError("You cannot report yourself.")

    report_obj = Report.objects.create(
        reporter=reporter,
        target=target_user,
        category=category,
        details=(details or "")[:2000],
    )
    record(
        AuditEvent.Type.SECURITY_EVENT,
        actor=reporter,
        target=target_user,
        source="social",
        action="report",
        category=category,
    )
    return report_obj
