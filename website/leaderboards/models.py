import uuid

from django.conf import settings
from django.db import models


class Metric(models.TextChoices):
    """The metric definitions mirror Yakitori's local statistics exactly.

    These are the only values leaderboards may use. No new, ad-hoc metric is
    invented here.
    """

    NET_WORDS = "net_words", "Net words"
    WORDS_ADDED = "words_added", "Words added"
    WORDS_REMOVED = "words_removed", "Words removed"
    ACTIVE_SECONDS = "active_seconds", "Active time"
    FOCUS_SECONDS = "focus_seconds", "Focus time"
    SESSION_COUNT = "session_count", "Sessions"


# Documented definitions, surfaced by the API and the docs.
METRIC_DEFINITIONS = {
    Metric.NET_WORDS: "Net manuscript change (words added minus words removed).",
    Metric.WORDS_ADDED: "Words added to the manuscript.",
    Metric.WORDS_REMOVED: "Words removed from the manuscript.",
    Metric.ACTIVE_SECONDS: "Active writing time in seconds.",
    Metric.FOCUS_SECONDS: "Focus time in seconds.",
    Metric.SESSION_COUNT: "Number of recorded sessions.",
}


class Period(models.TextChoices):
    DAY = "day", "Day"
    WEEK = "week", "Week"
    MONTH = "month", "Month"
    ALL_TIME = "all_time", "All time"


class LeaderboardAggregate(models.Model):
    """A validated aggregate for one user, metric, and period.

    Leaderboards never query raw writing sessions; they read these rows.
    """

    class Source(models.TextChoices):
        SYNC = "sync", "Client sync"
        ADMIN = "admin", "Administrative"
        IMPORT = "import", "Import"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="leaderboard_aggregates",
    )

    metric = models.CharField(max_length=40, choices=Metric.choices)
    period = models.CharField(max_length=20, choices=Period.choices)
    period_start = models.DateField(db_index=True)
    period_end = models.DateField(null=True, blank=True)

    value = models.BigIntegerField(default=0)
    source = models.CharField(
        max_length=20, choices=Source.choices, default=Source.SYNC
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-value", "id")
        constraints = [
            models.UniqueConstraint(
                fields=["user", "metric", "period", "period_start"],
                name="unique_aggregate_slot",
            ),
        ]
        indexes = [
            models.Index(fields=["metric", "period", "period_start", "-value"]),
            models.Index(fields=["user", "metric", "period"]),
        ]

    def __str__(self):
        return f"{self.user_id}:{self.metric}:{self.period}:{self.period_start}"


class StatisticSubmission(models.Model):
    """An inbound batch of aggregates.

    Stored whether accepted or rejected so abuse and anomalies can be reviewed.
    A submission is **not** cryptographically trustworthy; see
    docs/leaderboard-architecture.md.
    """

    class Status(models.TextChoices):
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="statistic_submissions",
    )
    installation = models.ForeignKey(
        "licensing.Installation",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="statistic_submissions",
    )

    payload = models.JSONField(default=list, blank=True)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ACCEPTED
    )
    validation_error = models.TextField(blank=True)
    app_version = models.CharField(max_length=40, blank=True)

    submitted_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-submitted_at",)

    def __str__(self):
        return f"submission:{self.user_id}:{self.status}"
