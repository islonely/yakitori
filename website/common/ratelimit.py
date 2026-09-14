"""Server-side rate limiting.

Limits are configured in ``settings.RATE_LIMIT_DEFAULTS`` as
``action -> (limit, window_seconds)``. Counters live in the database so they are
shared across processes. Client-side limits are never relied upon.
"""

from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from accounts.models import RateLimitEntry


def client_ip(request):
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR", "unknown")


def _record(key, limit, window_seconds, cost):
    now = timezone.now()
    with transaction.atomic():
        entry = RateLimitEntry.objects.select_for_update().filter(key=key).first()
        if entry is None or entry.reset_at <= now:
            RateLimitEntry.objects.update_or_create(
                key=key,
                defaults={
                    "attempts": 0,
                    "reset_at": now + timedelta(seconds=window_seconds),
                },
            )
            entry = RateLimitEntry.objects.select_for_update().get(key=key)

        entry.attempts += cost
        entry.save(update_fields=["attempts"])
        return entry.attempts <= limit


def check(request, action, scope=None, cost=1):
    """Record an attempt and return True when the caller is still under limit.

    ``scope`` should identify the subject of the action (email, user id,
    username). When omitted, the client IP is used.
    """
    limit, window = settings.RATE_LIMIT_DEFAULTS.get(action, (60, 60 * 60))
    identity = scope if scope else f"ip:{client_ip(request)}"
    key = f"{action}:{identity}"
    return _record(key, limit, window, cost)


def enforce(request, action, scope=None, cost=1):
    """Raise ApiError(429) when the caller is over the limit."""
    from common.jsonapi import ApiError

    if not check(request, action, scope=scope, cost=cost):
        raise ApiError(
            429,
            "rate_limited",
            "Too many requests. Please wait and try again.",
        )


def retry_after(action, scope):
    """Seconds until the counter for this action/scope resets, or 0."""
    key = f"{action}:{scope}"
    entry = RateLimitEntry.objects.filter(key=key).first()
    if entry is None:
        return 0
    return max(0, int((entry.reset_at - timezone.now()).total_seconds()))


def reset(action=None, scope=None):
    """Clear counters. With no arguments, clear everything.

    Used when a sign-in succeeds (so a legitimate user is not locked out by
    their own earlier typos) and by the `clear_rate_limits` management command.
    """
    queryset = RateLimitEntry.objects.all()
    if action is not None:
        queryset = queryset.filter(key__startswith=f"{action}:")
    if scope is not None:
        queryset = queryset.filter(key__endswith=f":{scope}")
    deleted, _ = queryset.delete()
    return deleted
