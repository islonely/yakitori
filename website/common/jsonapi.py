"""Small helpers for the versioned JSON API.

The API is hand-rolled rather than built on a framework: the surface is small,
the team is small, and avoiding a dependency keeps the security review short.
"""

import json
from functools import wraps

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt


class ApiError(Exception):
    """Raised inside an API endpoint to produce a structured error response."""

    def __init__(self, status, code, message="", fields=None):
        super().__init__(message or code)
        self.status = status
        self.code = code
        self.message = message or code
        self.fields = fields or None


def error_response(status, code, message="", fields=None):
    body = {"error": {"code": code, "message": message or code}}
    if fields:
        body["error"]["fields"] = fields
    return JsonResponse(body, status=status)


def json_response(data=None, status=200, headers=None):
    response = JsonResponse({} if data is None else data, status=status, safe=False)
    for key, value in (headers or {}).items():
        response[key] = value
    return response


def json_body(request):
    """Parse a JSON object body, raising ApiError for malformed input."""
    if not request.body:
        return {}
    try:
        payload = json.loads(request.body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise ApiError(400, "invalid_json", "Request body is not valid JSON.")
    if not isinstance(payload, dict):
        raise ApiError(400, "invalid_json", "Request body must be a JSON object.")
    return payload


def api_endpoint(methods):
    """Wrap an API view: enforce methods, make it CSRF-exempt, map errors.

    API requests authenticate with a bearer token, so cookie-based CSRF does not
    apply. Browser session views never use this decorator.
    """
    allowed = set(methods)

    def decorator(view):
        @csrf_exempt
        @wraps(view)
        def wrapper(request, *args, **kwargs):
            if request.method not in allowed:
                return error_response(
                    405,
                    "method_not_allowed",
                    f"{request.method} is not allowed here.",
                )
            try:
                return view(request, *args, **kwargs)
            except ApiError as exc:
                return error_response(
                    exc.status, exc.code, exc.message, exc.fields
                )

        return wrapper

    return decorator
