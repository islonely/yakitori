"""Authentication helpers for the JSON API.

Native clients send ``Authorization: Bearer <token>``. Browser sessions are
handled by Django's normal session middleware and are only used by HTML views.
"""

from functools import wraps

from common.jsonapi import ApiError

from .services import authenticate_token


def bearer_token(request):
    header = request.META.get("HTTP_AUTHORIZATION", "")
    if header.lower().startswith("bearer "):
        return header[7:].strip()
    return None


def resolve_user(request):
    """Return ``(user, token)`` for the request, using a bearer token first.

    Session authentication is accepted so a signed-in browser can call the same
    endpoints, but tokens are the primary mechanism for native clients.
    """
    token = authenticate_token(bearer_token(request))
    if token is not None:
        return token.user, token
    if getattr(request, "user", None) is not None and request.user.is_authenticated:
        return request.user, None
    return None, None


def api_login_required(view):
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        user, token = resolve_user(request)
        if user is None:
            raise ApiError(401, "unauthorized", "Authentication required.")
        request.api_user = user
        request.api_token = token
        return view(request, *args, **kwargs)

    return wrapper


def api_admin_required(view):
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        user, token = resolve_user(request)
        if user is None:
            raise ApiError(401, "unauthorized", "Authentication required.")
        if not (user.is_staff or user.is_superuser):
            raise ApiError(403, "forbidden", "Administrator access required.")
        request.api_user = user
        request.api_token = token
        return view(request, *args, **kwargs)

    return wrapper
