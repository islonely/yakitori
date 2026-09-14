from django.shortcuts import redirect, render
from django.urls import reverse
from django.views.decorators.http import require_GET

from . import services
from .models import METRIC_DEFINITIONS, Metric, Period


@require_GET
def index(request):
    return render(
        request,
        "leaderboards/index.html",
        {"metrics": [(metric, METRIC_DEFINITIONS.get(metric, "")) for metric in Metric]},
    )


@require_GET
def board(request, metric):
    if metric not in set(Metric.values):
        return redirect("leaderboards:index")

    period = request.GET.get("period", Period.WEEK)
    if period not in set(Period.values):
        period = Period.WEEK

    period_start = None
    if period != Period.ALL_TIME:
        from datetime import date

        period_start = date.today()

    entries, _next = services.leaderboard(metric, period, period_start, limit=100)

    return render(
        request,
        "leaderboards/board.html",
        {
            "metric": metric,
            "metric_label": Metric(metric).label,
            "definition": METRIC_DEFINITIONS.get(metric, ""),
            "period": period,
            "entries": entries,
        },
    )
