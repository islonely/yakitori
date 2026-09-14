from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import redirect, render
from django.views.decorators.http import require_http_methods

from social.services import can_view_profile, counts, is_following

from .models import Profile
from .services import (
    UsernameError,
    change_cooldown_remaining,
    normalize_username,
    set_username,
    update_privacy,
    update_profile,
)


def public_profile(request, username):
    profile = (
        Profile.objects
        .select_related("user")
        .filter(username_normalized=normalize_username(username))
        .first()
    )
    if profile is None or not can_view_profile(profile, request.user):
        raise Http404("No such user.")

    followers, following = counts(profile.user)
    return render(
        request,
        "profiles/public_profile.html",
        {
            "profile": profile,
            "is_owner": request.user == profile.user,
            "followers": followers,
            "following": following,
            "viewer_following": is_following(request.user, profile.user),
        },
    )


@login_required
@require_http_methods(["GET", "POST"])
def edit_profile(request):
    profile = request.user.profile

    if request.method == "POST":
        update_profile(
            profile,
            display_name=request.POST.get("display_name", ""),
            bio=request.POST.get("bio", ""),
            avatar_url=request.POST.get("avatar_url", ""),
        )
        messages.success(request, "Profile updated.")
        return redirect("profiles:edit")

    return render(request, "profiles/edit_profile.html", {"profile": profile})


@login_required
@require_http_methods(["GET", "POST"])
def change_username(request):
    profile = request.user.profile
    error = None

    if request.method == "POST":
        try:
            set_username(profile, request.POST.get("username", ""), actor=request.user)
        except UsernameError as exc:
            error = str(exc)
        else:
            messages.success(request, "Username updated.")
            return redirect("profiles:change-username")

    remaining = change_cooldown_remaining(profile)
    return render(
        request,
        "profiles/change_username.html",
        {
            "profile": profile,
            "error": error,
            "cooldown_days": (remaining + 86399) // 86400 if remaining else 0,
        },
    )


@login_required
@require_http_methods(["GET", "POST"])
def privacy_settings(request):
    profile = request.user.profile

    if request.method == "POST":
        update_privacy(
            profile,
            profile_visibility=request.POST.get("profile_visibility"),
            stats_visibility=request.POST.get("stats_visibility"),
            leaderboard_visibility=request.POST.get("leaderboard_visibility"),
            allow_following=request.POST.get("allow_following") == "on",
        )
        messages.success(request, "Privacy settings updated.")
        return redirect("profiles:privacy")

    return render(request, "profiles/privacy.html", {"profile": profile})
