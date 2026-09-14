"""Metric and period abstractions shared by validation and queries."""

from datetime import date, timedelta

from .models import Period

ALL_TIME_START = date(1970, 1, 1)


def period_bounds(period, start):
    """Return ``(start, end_exclusive)`` for a period anchored at ``start``.

    All boundaries are calendar-based. The client decides which calendar day a
    session belongs to (using its configured timezone); the server stores the
    resulting date so aggregation is deterministic.
    """
    if period == Period.DAY:
        return start, start + timedelta(days=1)
    if period == Period.WEEK:
        week_start = start - timedelta(days=start.weekday())
        return week_start, week_start + timedelta(days=7)
    if period == Period.MONTH:
        month_start = start.replace(day=1)
        if month_start.month == 12:
            next_month = month_start.replace(year=month_start.year + 1, month=1)
        else:
            next_month = month_start.replace(month=month_start.month + 1)
        return month_start, next_month
    # All time has no meaningful end.
    return ALL_TIME_START, None


def normalize_period_start(period, start):
    if period == Period.ALL_TIME:
        return ALL_TIME_START
    if period == Period.WEEK:
        return start - timedelta(days=start.weekday())
    if period == Period.MONTH:
        return start.replace(day=1)
    return start


def period_days(period):
    return {
        Period.DAY: 1,
        Period.WEEK: 7,
        Period.MONTH: 31,
        Period.ALL_TIME: 366 * 100,
    }[period]
