from accounts.auth import api_login_required, resolve_user
from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.ratelimit import enforce
from social.services import can_view_profile

from .models import Profile
from .serializers import own_profile, public_profile
from .services import (
    UsernameError,
    normalize_username,
    set_username,
    update_privacy,
    update_profile,
)


def _get_profile_or_404(username):
    profile = (
        Profile.objects
        .select_related("user")
        .filter(username_normalized=normalize_username(username))
        .first()
    )
    if profile is None:
        raise ApiError(404, "not_found", "No such user.")
    return profile


@api_endpoint(["GET"])
def user_detail(request, username):
    viewer, _token = resolve_user(request)
    profile = _get_profile_or_404(username)
    if not can_view_profile(profile, viewer):
        # Private profiles are indistinguishable from missing ones.
        raise ApiError(404, "not_found", "No such user.")
    return json_response({"profile": public_profile(profile, viewer)})


@api_endpoint(["GET", "PATCH"])
@api_login_required
def my_profile(request):
    profile = request.api_user.profile

    if request.method == "GET":
        return json_response({"profile": own_profile(profile)})

    body = json_body(request)
    allowed = {"display_name", "bio", "avatar_url"}
    unknown = set(body) - allowed - {
        "profile_visibility",
        "stats_visibility",
        "leaderboard_visibility",
        "allow_following",
    }
    if unknown:
        raise ApiError(
            400,
            "unknown_fields",
            "Unsupported fields.",
            fields={field: "unknown" for field in sorted(unknown)},
        )

    update_profile(
        profile,
        display_name=body.get("display_name"),
        bio=body.get("bio"),
        avatar_url=body.get("avatar_url"),
    )

    if any(
        key in body
        for key in (
            "profile_visibility",
            "stats_visibility",
            "leaderboard_visibility",
            "allow_following",
        )
    ):
        update_privacy(
            profile,
            profile_visibility=body.get("profile_visibility"),
            stats_visibility=body.get("stats_visibility"),
            leaderboard_visibility=body.get("leaderboard_visibility"),
            allow_following=body.get("allow_following"),
        )

    return json_response({"profile": own_profile(profile)})


@api_endpoint(["POST"])
@api_login_required
def change_my_username(request):
    enforce(request, "username-change", scope=f"user:{request.api_user.pk}")
    body = json_body(request)
    username = body.get("username", "")
    try:
        set_username(request.api_user.profile, username, actor=request.api_user)
    except UsernameError as exc:
        raise ApiError(400, "invalid_username", str(exc))

    return json_response({"profile": own_profile(request.api_user.profile)})
