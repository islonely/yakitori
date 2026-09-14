"""A validation interface for submitted aggregates.

This is deliberately a *plausibility* filter, not a proof of truth. It exists so
the interface and schema are ready before competitive leaderboards are enabled.
Client-reported statistics are never claimed to be cryptographically truthful.
"""

from datetime import date

from .models import Metric, Period
from .periods import ALL_TIME_START, normalize_period_start, period_days

MAX_ABS_VALUE = 100_000_000
MAX_SECONDS_PER_DAY = 86_400
MAX_WORDS_PER_DAY = 1_000_000

SECONDS_METRICS = {Metric.ACTIVE_SECONDS, Metric.FOCUS_SECONDS}
WORD_METRICS = {Metric.NET_WORDS, Metric.WORDS_ADDED, Metric.WORDS_REMOVED}


class ValidationResult:
    def __init__(self):
        self.errors = []
        self.cleaned = []

    @property
    def ok(self):
        return not self.errors

    def add_error(self, index, message):
        self.errors.append({"index": index, "error": message})


def _parse_date(value):
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError:
            return None
    return None


def validate_items(items, *, today=None):
    """Validate a list of aggregate items.

    Each item: ``{metric, period, period_start, value}``.
    """
    result = ValidationResult()
    today = today or date.today()

    if not isinstance(items, list):
        result.add_error(0, "Payload must be a list of aggregates.")
        return result

    if len(items) > 500:
        result.add_error(0, "Too many aggregates in one submission.")
        return result

    for index, item in enumerate(items):
        if not isinstance(item, dict):
            result.add_error(index, "Each aggregate must be an object.")
            continue

        metric = item.get("metric")
        period = item.get("period")

        if metric not in set(Metric.values):
            result.add_error(index, "Unknown metric.")
            continue
        if period not in set(Period.values):
            result.add_error(index, "Unknown period.")
            continue

        start = _parse_date(item.get("period_start"))
        if start is None:
            if period == Period.ALL_TIME:
                start = ALL_TIME_START
            else:
                result.add_error(index, "period_start must be an ISO date.")
                continue
        if start > today:
            result.add_error(index, "period_start cannot be in the future.")
            continue

        value = item.get("value")
        if not isinstance(value, int) or isinstance(value, bool):
            result.add_error(index, "value must be an integer.")
            continue

        if abs(value) > MAX_ABS_VALUE:
            result.add_error(index, "value is implausibly large.")
            continue

        days = period_days(period)
        if metric in SECONDS_METRICS and value > MAX_SECONDS_PER_DAY * days:
            result.add_error(index, "duration exceeds the number of seconds in the period.")
            continue
        if metric in WORD_METRICS and abs(value) > MAX_WORDS_PER_DAY * days:
            result.add_error(index, "word count exceeds a plausible maximum for the period.")
            continue

        result.cleaned.append(
            {
                "metric": metric,
                "period": period,
                "period_start": normalize_period_start(period, start),
                "value": value,
            }
        )

    return result
