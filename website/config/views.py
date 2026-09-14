from django.conf import settings
from django.db import connection
from django.http import JsonResponse
from django.shortcuts import render
from django.views.decorators.cache import never_cache


@never_cache
def healthz(request):
    """Liveness/readiness probe used by the host and uptime monitoring.

    Returns 200 when the application is up and the database answers, 503
    otherwise. The body is intentionally minimal and contains no secrets.
    """
    database_ok = True
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except Exception:
        database_ok = False

    payload = {
        "status": "ok" if database_ok else "degraded",
        "service": "yakitori-platform",
        "version": getattr(settings, "PLATFORM_VERSION", "1"),
        "database": "ok" if database_ok else "unavailable",
    }
    return JsonResponse(payload, status=200 if database_ok else 503)


def _wants_json(request):
    return request.path.startswith("/v1/")


def not_found(request, exception=None):
    if _wants_json(request):
        return JsonResponse({"error": "not_found"}, status=404)
    return render(request, "404.html", status=404)


def server_error(request):
    if _wants_json(request):
        return JsonResponse({"error": "server_error"}, status=500)
    return render(request, "500.html", status=500)
