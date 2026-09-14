import uuid

from accounts.auth import api_login_required
from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.ratelimit import enforce

from . import services


def serialize_license(license_obj):
    return {
        "id": str(license_obj.id),
        "product": license_obj.product,
        "license_type": license_obj.license_type,
        "status": license_obj.status,
        "purchased_at": license_obj.purchased_at.isoformat()
        if license_obj.purchased_at
        else None,
        "expires_at": license_obj.expires_at.isoformat()
        if license_obj.expires_at
        else None,
    }


def serialize_trial(trial):
    return {
        "ends_at": trial.ends_at.isoformat(),
        "days_remaining": trial.days_remaining,
    }


def serialize_installation(installation):
    return {
        "installation_id": str(installation.installation_id),
        "platform": installation.platform,
        "app_version": installation.app_version,
        "first_seen_at": installation.first_seen_at.isoformat(),
        "last_seen_at": installation.last_seen_at.isoformat(),
        "revoked": installation.revoked_at is not None,
    }


@api_endpoint(["GET", "POST"])
@api_login_required
def installations(request):
    user = request.api_user

    if request.method == "GET":
        items = user.installations.order_by("-last_seen_at")
        return json_response(
            {"installations": [serialize_installation(i) for i in items]}
        )

    enforce(request, "installation-register", scope=f"user:{user.pk}")
    body = json_body(request)
    raw_id = body.get("installation_id")
    try:
        installation_id = uuid.UUID(str(raw_id))
    except (TypeError, ValueError, AttributeError):
        raise ApiError(
            400, "invalid_installation", "installation_id must be a UUID."
        )

    installation, created = services.register_installation(
        user,
        installation_id,
        platform=body.get("platform", "macOS"),
        app_version=body.get("app_version", ""),
    )
    return json_response(
        {"installation": serialize_installation(installation), "created": created},
        status=201 if created else 200,
    )


@api_endpoint(["DELETE"])
@api_login_required
def installation_detail(request, installation_id):
    revoked = services.revoke_installation(request.api_user, installation_id)
    if not revoked:
        raise ApiError(404, "not_found", "No such installation.")
    return json_response({"revoked": True})


@api_endpoint(["GET"])
@api_login_required
def license_detail(request):
    license_obj = services.license_for(request.api_user)
    if license_obj is None:
        raise ApiError(404, "no_license", "This account has no license.")
    return json_response({"license": serialize_license(license_obj)})


@api_endpoint(["POST"])
@api_login_required
def validate(request):
    enforce(request, "license-validate", scope=f"user:{request.api_user.pk}")
    body = json_body(request)

    installation = None
    raw_id = body.get("installation_id")
    if raw_id:
        try:
            installation = services.find_installation(
                request.api_user, uuid.UUID(str(raw_id))
            )
        except (TypeError, ValueError):
            raise ApiError(
                400, "invalid_installation", "installation_id must be a UUID."
            )

    result = services.validate_license(request.api_user, installation)
    if not result["valid"]:
        payload = {"valid": False, "reason": result["reason"]}
        if result.get("kind"):
            payload["kind"] = result["kind"]
        return json_response(payload)

    payload = {
        "valid": True,
        "kind": result.get("kind", "license"),
        "authorization": result["authorization"],
        "offline_grace_days": result["offline_grace_days"],
    }
    if result.get("license") is not None:
        payload["license"] = serialize_license(result["license"])
    if result.get("trial") is not None:
        payload["trial"] = serialize_trial(result["trial"])
    return json_response(payload)
