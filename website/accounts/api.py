from django.conf import settings

from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.ratelimit import enforce

from . import services
from .auth import api_login_required
from .models import ApiToken


def serialize_user(user, include_email=True):
    payload = {
        "id": str(user.pk),
        "status": user.status,
        "email_verified": user.email_verified_at is not None,
        "created_at": user.created_at.isoformat(),
    }
    # The account's own email is returned only to the account itself.
    if include_email:
        payload["email"] = user.email
    return payload


def serialize_token(token):
    return {
        "id": str(token.pk),
        "label": token.label,
        "installation_uuid": str(token.installation_uuid)
        if token.installation_uuid
        else None,
        "created_at": token.created_at.isoformat(),
        "last_used_at": token.last_used_at.isoformat() if token.last_used_at else None,
        "expires_at": token.expires_at.isoformat() if token.expires_at else None,
    }


@api_endpoint(["POST"])
def device_start(request):
    enforce(request, "installation-register")
    body = json_body(request)
    authorization, device_code = services.start_device_authorization(
        client_name=body.get("client_name", "")
    )

    verification_uri = f"{settings.APP_BASE_URL}/device/"
    return json_response(
        {
            "device_code": device_code,
            "user_code": authorization.user_code,
            "verification_uri": verification_uri,
            "verification_uri_complete": (
                f"{verification_uri}?user_code={authorization.user_code}"
            ),
            "expires_in": settings.DEVICE_CODE_TTL_SECONDS,
            "interval": authorization.poll_interval,
        }
    )


@api_endpoint(["POST"])
def device_token(request):
    enforce(request, "login-verify")
    body = json_body(request)
    plaintext, error = services.exchange_device_code(
        body.get("device_code", ""),
        label=body.get("client_name", ""),
    )

    if error == "pending":
        raise ApiError(
            400,
            "authorization_pending",
            "The device has not been approved yet.",
        )
    if error == "denied":
        raise ApiError(400, "access_denied", "The request was denied.")
    if error == "expired":
        raise ApiError(400, "expired_token", "The device code expired.")
    if error == "invalid":
        raise ApiError(400, "invalid_grant", "The device code is invalid.")

    return json_response(
        {
            "token": plaintext,
            "token_type": "Bearer",
            "expires_in": settings.API_TOKEN_TTL_DAYS * 86400,
        }
    )


@api_endpoint(["GET"])
@api_login_required
def me(request):
    return json_response({"user": serialize_user(request.api_user)})


@api_endpoint(["DELETE"])
@api_login_required
def current_token(request):
    """Revoke the token that authenticated this request (sign out)."""
    token = request.api_token
    if token is None:
        raise ApiError(400, "no_token", "This request was not authenticated with a token.")
    services.revoke_api_token(request.api_user, token.pk)
    return json_response({"revoked": True})


@api_endpoint(["GET"])
@api_login_required
def tokens(request):
    items = (
        ApiToken.objects
        .filter(user=request.api_user, revoked_at__isnull=True)
        .order_by("-created_at")
    )
    return json_response({"tokens": [serialize_token(item) for item in items]})


@api_endpoint(["DELETE"])
@api_login_required
def token_detail(request, token_id):
    revoked = services.revoke_api_token(request.api_user, token_id)
    if not revoked:
        raise ApiError(404, "not_found", "No such token.")
    return json_response({"revoked": True})
