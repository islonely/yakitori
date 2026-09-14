from django.conf import settings
from django.db.models import Q
from django.utils.dateparse import parse_datetime

from accounts.auth import api_login_required, resolve_user
from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.pagination import clamp_limit, decode_cursor, encode_cursor
from common.ratelimit import enforce
from profiles.models import Profile
from profiles.services import normalize_username

from . import services
from .models import Report


def _profile_or_404(username):
    profile = (
        Profile.objects
        .select_related("user")
        .filter(username_normalized=normalize_username(username))
        .first()
    )
    if profile is None:
        raise ApiError(404, "not_found", "No such user.")
    return profile


def _require_visible(profile, viewer):
    if not services.can_view_profile(profile, viewer):
        raise ApiError(404, "not_found", "No such user.")


def serialize_member(user):
    profile = getattr(user, "profile", None)
    if profile is None or not profile.username:
        return None
    return {
        "username": profile.username,
        "display_name": profile.display_name or profile.username,
        "avatar_url": profile.avatar_url or None,
    }


def _paginated_edges(request, queryset, profile):
    cursor = decode_cursor(request.GET.get("cursor"))
    if cursor:
        created_at = parse_datetime(cursor.get("created_at", ""))
        edge_id = cursor.get("id")
        if created_at is not None and edge_id:
            queryset = queryset.filter(
                Q(created_at__lt=created_at)
                | Q(created_at=created_at, id__lt=edge_id)
            )

    limit = clamp_limit(request.GET.get("limit"), settings.FOLLOW_PAGE_SIZE)
    rows = list(queryset[: limit + 1])
    has_more = len(rows) > limit
    rows = rows[:limit]

    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor(
            created_at=last.created_at.isoformat(), id=str(last.id)
        )

    return rows, next_cursor


@api_endpoint(["POST", "DELETE"])
@api_login_required
def follow_user(request, username):
    profile = _profile_or_404(username)
    target = profile.user

    if request.method == "POST":
        enforce(request, "follow", scope=f"user:{request.api_user.pk}")
        try:
            _edge, created = services.follow(request.api_user, target)
        except services.SocialError as exc:
            raise ApiError(400, "cannot_follow", str(exc))
        return json_response(
            {"following": True, "created": created},
            status=201 if created else 200,
        )

    removed = services.unfollow(request.api_user, target)
    return json_response({"following": False, "removed": removed})


@api_endpoint(["GET"])
def followers(request, username):
    viewer, _token = resolve_user(request)
    profile = _profile_or_404(username)
    _require_visible(profile, viewer)

    rows, next_cursor = _paginated_edges(
        request, services.followers_queryset(profile.user), profile
    )
    members = [serialize_member(edge.follower) for edge in rows]
    return json_response(
        {"followers": [m for m in members if m], "next_cursor": next_cursor}
    )


@api_endpoint(["GET"])
def following(request, username):
    viewer, _token = resolve_user(request)
    profile = _profile_or_404(username)
    _require_visible(profile, viewer)

    rows, next_cursor = _paginated_edges(
        request, services.following_queryset(profile.user), profile
    )
    members = [serialize_member(edge.followed) for edge in rows]
    return json_response(
        {"following": [m for m in members if m], "next_cursor": next_cursor}
    )


@api_endpoint(["POST", "DELETE"])
@api_login_required
def block_user(request, username):
    profile = _profile_or_404(username)
    if request.method == "POST":
        try:
            services.block(request.api_user, profile.user)
        except services.SocialError as exc:
            raise ApiError(400, "cannot_block", str(exc))
        return json_response({"blocked": True})
    removed = services.unblock(request.api_user, profile.user)
    return json_response({"blocked": False, "removed": removed})


@api_endpoint(["POST"])
@api_login_required
def report_user(request, username):
    enforce(request, "profile-mutation", scope=f"user:{request.api_user.pk}")
    profile = _profile_or_404(username)
    body = json_body(request)
    category = body.get("category", Report.Category.OTHER)
    if category not in Report.Category.values:
        raise ApiError(400, "invalid_category", "Unknown report category.")
    try:
        services.report(request.api_user, profile.user, category, body.get("details", ""))
    except services.SocialError as exc:
        raise ApiError(400, "cannot_report", str(exc))
    return json_response({"reported": True}, status=201)
