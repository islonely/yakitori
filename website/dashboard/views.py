from django.contrib import messages
from django.contrib.auth import logout
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect, render
from django.views.decorators.http import require_POST

from accounts.services import revoke_all_tokens, revoke_api_token


@login_required
def home(request):
    tokens = (
        request.user.api_tokens
        .filter(revoked_at__isnull=True)
        .order_by("-created_at")
    )
    return render(request, "dashboard/home.html", {"tokens": tokens})


@login_required
@require_POST
def revoke_token(request, token_id):
    if revoke_api_token(request.user, token_id):
        messages.success(request, "That device was revoked.")
    else:
        messages.error(request, "That device could not be found.")
    return redirect("dashboard:home")


@login_required
@require_POST
def revoke_all_tokens_view(request):
    count = revoke_all_tokens(request.user)
    logout(request)
    messages.success(
        request,
        f"Revoked {count} device credential{'s' if count != 1 else ''}. "
        "You have been signed out.",
    )
    return redirect("web:home")
