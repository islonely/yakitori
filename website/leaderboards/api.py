import uuid
from datetime import date

from django.conf import settings
from django.utils.dateparse import parse_date

from accounts.auth import api_login_required
from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.pagination import clamp_limit, decode_cursor
from common.ratelimit import enforce
from licensing.models import Installation

from . import services
from .models import METRIC_DEFINITIONS, Metric, Period
from .periods import normalize_period_start


def _resolve_period(request):
    period = request.GET.get("period", Period.WEEK)
    if period not in set(Period.values):
        raise ApiError(400, "invalid_period", "Unknown period.")
    if period == Period.ALL_TIME:
        return period, None

    raw = request.GET.get("period_start")
    start = parse_date(raw) if raw else date.today()
    if start is None:
        raise ApiError(400, "invalid_period_start", "period_start must be a date.")
    return period, normalize_period_start(period, start)


def serialize_entry(rank, aggregate):
    profile = aggregate.user.profile
    return {
        "rank": rank,
        "username": profile.username,
        "display_name": profile.display_name or profile.username,
        "avatar_url": profile.avatar_url or None,
        "value": aggregate.value,
    }


@api_endpoint(["GET"])
def leaderboard_view(request, metric):
    if metric not in set(Metric.values):
        raise ApiError(404, "unknown_metric", "Unknown metric.")

    period, period_start = _resolve_period(request)
    cursor = decode_cursor(request.GET.get("cursor"))
    limit = clamp_limit(
        request.GET.get("limit"), settings.LEADERBOARD_PAGE_SIZE, maximum=200
    )

    entries, next_cursor = services.leaderboard(
        metric, period, period_start, limit=limit, cursor=cursor
    )

    return json_response(
        {
            "metric": metric,
            "period": period,
            "period_start": period_start.isoformat() if period_start else None,
            "definition": METRIC_DEFINITIONS.get(metric, ""),
            "entries": [serialize_entry(rank, agg) for rank, agg in entries],
            "next_cursor": next_cursor,
        }
    )


@api_endpoint(["GET"])
@api_login_required
def my_standing(request, metric):
    if metric not in set(Metric.values):
        raise ApiError(404, "unknown_metric", "Unknown metric.")

    period, period_start = _resolve_period(request)
    standing = services.user_standing(
        request.api_user, metric, period, period_start
    )

    if standing is None:
        return json_response(
            {
                "metric": metric,
                "period": period,
                "value": None,
                "rank": None,
                "eligible": services.is_eligible(request.api_user),
            }
        )

    return json_response(
        {
            "metric": metric,
            "period": period,
            "value": standing["aggregate"].value,
            "rank": standing["rank"],
            "eligible": services.is_eligible(request.api_user),
        }
    )


@api_endpoint(["POST"])
@api_login_required
def submit_statistics(request):
    enforce(request, "statistics-submit", scope=f"user:{request.api_user.pk}")
    body = json_body(request)
    items = body.get("aggregates", [])
    if not isinstance(items, list):
        raise ApiError(400, "invalid_payload", "aggregates must be a list.")

    installation = None
    raw_installation = body.get("installation_id")
    if raw_installation:
        try:
            installation = Installation.objects.filter(
                installation_id=uuid.UUID(str(raw_installation)),
                user=request.api_user,
            ).first()
        except (TypeError, ValueError):
            installation = None

    submission, result = services.submit_aggregates(
        request.api_user,
        items,
        installation=installation,
        app_version=body.get("app_version", ""),
    )

    if not result.ok:
        return json_response(
            {
                "submission_id": str(submission.id),
                "accepted": False,
                "errors": result.errors,
            },
            status=422,
        )

    return json_response(
        {
            "submission_id": str(submission.id),
            "accepted": True,
            "count": len(result.cleaned),
        }
    )
