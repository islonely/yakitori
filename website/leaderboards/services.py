"""Leaderboard aggregation and query services.

Rankings read precomputed `LeaderboardAggregate` rows — never raw writing
sessions. Eligibility is always gated by privacy settings.
"""

from datetime import date

from django.db import transaction
from django.db.models import Q

from common.pagination import encode_cursor

from .models import LeaderboardAggregate, Metric, Period, StatisticSubmission
from .periods import ALL_TIME_START, normalize_period_start
from .validation import validate_items


def eligible_queryset(metric, period, period_start=None):
    """Aggregates that may appear on a public leaderboard.

    A user is eligible only when the account is active, the profile is public,
    and leaderboard visibility is set to global. A private user never appears.
    """
    queryset = (
        LeaderboardAggregate.objects
        .select_related("user", "user__profile")
        .filter(
            metric=metric,
            period=period,
            user__status="active",
            user__profile__profile_visibility="public",
            user__profile__leaderboard_visibility="global",
        )
    )

    if period == Period.ALL_TIME:
        queryset = queryset.filter(period_start=ALL_TIME_START)
    else:
        queryset = queryset.filter(
            period_start=normalize_period_start(period, period_start)
        )

    return queryset.order_by("-value", "id")


def _rank_of(metric, period, period_start, value, aggregate_id):
    return (
        eligible_queryset(metric, period, period_start)
        .filter(Q(value__gt=value) | Q(value=value, id__lt=aggregate_id))
        .count()
        + 1
    )


def leaderboard(metric, period, period_start=None, limit=100, cursor=None):
    """Return ``(entries, next_cursor)`` where entries are ``(rank, aggregate)``."""
    if metric not in set(Metric.values):
        raise ValueError("Unknown metric.")
    if period not in set(Period.values):
        raise ValueError("Unknown period.")
    if period != Period.ALL_TIME and period_start is None:
        raise ValueError("period_start is required for this period.")

    queryset = eligible_queryset(metric, period, period_start)

    start_rank = 1
    if cursor:
        cursor_value = cursor.get("value")
        cursor_id = cursor.get("id")
        if cursor_value is not None and cursor_id:
            queryset = queryset.filter(
                Q(value__lt=cursor_value)
                | Q(value=cursor_value, id__gt=cursor_id)
            )
            start_rank = _rank_of(metric, period, period_start, cursor_value, cursor_id)

    rows = list(queryset[: limit + 1])
    has_more = len(rows) > limit
    rows = rows[:limit]

    entries = [
        (start_rank + offset, row) for offset, row in enumerate(rows)
    ]
    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor(value=last.value, id=str(last.id))

    return entries, next_cursor


def is_eligible(user):
    profile = getattr(user, "profile", None)
    return bool(
        profile
        and user.status == "active"
        and profile.profile_visibility == "public"
        and profile.leaderboard_visibility == "global"
    )


def user_standing(user, metric, period, period_start=None):
    if period != Period.ALL_TIME and period_start is None:
        return None

    aggregate = LeaderboardAggregate.objects.filter(
        user=user,
        metric=metric,
        period=period,
        period_start=normalize_period_start(period, period_start),
    ).first()
    if aggregate is None:
        return None

    rank = (
        _rank_of(metric, period, period_start, aggregate.value, aggregate.id)
        if is_eligible(user)
        else None
    )
    return {"aggregate": aggregate, "rank": rank}


def record_aggregate(
    user,
    metric,
    period,
    period_start,
    value,
    source=LeaderboardAggregate.Source.SYNC,
    period_end=None,
):
    period_start = normalize_period_start(period, period_start)
    with transaction.atomic():
        aggregate, _created = LeaderboardAggregate.objects.update_or_create(
            user=user,
            metric=metric,
            period=period,
            period_start=period_start,
            defaults={
                "value": value,
                "source": source,
                "period_end": period_end,
            },
        )
    return aggregate


def submit_aggregates(user, items, installation=None, app_version=""):
    """Validate and store a batch. Returns ``(submission, validation_result)``."""
    result = validate_items(items, today=date.today())

    submission = StatisticSubmission.objects.create(
        user=user,
        installation=installation,
        payload=items,
        status=(
            StatisticSubmission.Status.ACCEPTED
            if result.ok
            else StatisticSubmission.Status.REJECTED
        ),
        validation_error="; ".join(
            error["error"] for error in result.errors
        )[:2000],
        app_version=app_version,
    )

    if result.ok:
        for item in result.cleaned:
            record_aggregate(
                user,
                item["metric"],
                item["period"],
                item["period_start"],
                item["value"],
                source=LeaderboardAggregate.Source.SYNC,
            )

    return submission, result
