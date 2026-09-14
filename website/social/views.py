from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import redirect, render
from django.views.decorators.http import require_POST

from profiles.models import Profile
from profiles.services import normalize_username

from . import services


def _profile_or_404(username):
    profile = (
        Profile.objects
        .select_related("user")
        .filter(username_normalized=normalize_username(username))
        .first()
    )
    if profile is None:
        raise Http404("No such user.")
    return profile


def _visible_or_404(profile, request):
    if not services.can_view_profile(profile, request.user):
        raise Http404("No such user.")


def followers_page(request, username):
    profile = _profile_or_404(username)
    _visible_or_404(profile, request)
    members = [edge.follower for edge in services.followers_queryset(profile.user)[:200]]
    return render(
        request,
        "profiles/followers.html",
        {"profile": profile, "members": members, "mode": "followers"},
    )


def following_page(request, username):
    profile = _profile_or_404(username)
    _visible_or_404(profile, request)
    members = [edge.followed for edge in services.following_queryset(profile.user)[:200]]
    return render(
        request,
        "profiles/followers.html",
        {"profile": profile, "members": members, "mode": "following"},
    )


@login_required
@require_POST
def follow_toggle(request, username):
    profile = _profile_or_404(username)
    _visible_or_404(profile, request)

    is_htmx = request.headers.get("HX-Request") == "true"

    def _render(following, error=None):
        return render(
            request,
            "profiles/_follow_button.html",
            {"profile": profile, "following": following, "error": error},
        )

    try:
        if services.is_following(request.user, profile.user):
            services.unfollow(request.user, profile.user)
            following = False
        else:
            services.follow(request.user, profile.user)
            following = True
    except services.SocialError as exc:
        if is_htmx:
            return _render(False, str(exc))
        messages.error(request, str(exc))
        return redirect("profiles:public-profile", username=profile.username)

    if is_htmx:
        return _render(following)

    return redirect("profiles:public-profile", username=profile.username)
