from django.contrib import messages
from django.contrib.auth import login, logout
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect, render
from django.urls import reverse
from django.views.decorators.http import require_http_methods

from common.ratelimit import check, client_ip
from common.text import normalize_email

from . import services


def _next_url(request, default="dashboard:home"):
    target = request.POST.get("next") or request.GET.get("next")
    return target if target else reverse(default)


@require_http_methods(["GET", "POST"])
def sign_in(request):
    if request.user.is_authenticated:
        return redirect("dashboard:home")

    error = None
    if request.method == "POST":
        email = request.POST.get("email", "").strip()
        if not email:
            error = "Enter your email address."
        else:
            # Two independent limits: one per IP, one per address. Both record
            # an attempt. The response is identical either way so an attacker
            # cannot learn whether the address exists.
            allowed = check(
                request, "login-request", scope=f"ip:{client_ip(request)}"
            ) and check(
                request,
                "login-request",
                scope=f"email:{normalize_email(email)}",
            )
            if allowed:
                services.request_login(email, request_ip=client_ip(request))
                return redirect("accounts:sign-in-sent")
            error = (
                "Too many attempts. Please wait a few minutes and try again."
            )

    return render(request, "accounts/sign_in.html", {"error": error})


@require_http_methods(["GET", "POST"])
def sign_up(request):
    if request.user.is_authenticated:
        return redirect("dashboard:home")

    error = None
    if request.method == "POST":
        email = request.POST.get("email", "").strip()
        accepted = request.POST.get("accepted_terms") == "on"
        if not email:
            error = "Enter your email address."
        elif not accepted:
            error = "Please agree to the terms to create an account."
        else:
            allowed = check(
                request, "login-request", scope=f"ip:{client_ip(request)}"
            ) and check(
                request,
                "login-request",
                scope=f"email:{normalize_email(email)}",
            )
            if allowed:
                services.request_login(email, request_ip=client_ip(request))
                return redirect("accounts:sign-up-sent")
            error = (
                "Too many attempts. Please wait a few minutes and try again."
            )

    return render(request, "accounts/sign_up.html", {"error": error})


def sign_in_sent(request):
    return render(request, "accounts/sign_in_sent.html")


def sign_up_sent(request):
    return render(request, "accounts/sign_up_sent.html")


@require_http_methods(["GET", "POST"])
def verify_token(request, token):
    user, error = services.verify_token(token)
    if user is not None:
        login(request, user)
        messages.success(request, "You are signed in.")
        return redirect(_next_url(request))

    return render(
        request,
        "accounts/sign_in_failed.html",
        {"reason": error},
        status=400,
    )


@require_http_methods(["GET", "POST"])
def sign_in_code(request):
    if request.user.is_authenticated:
        return redirect("dashboard:home")

    email = request.POST.get("email", "").strip() or request.GET.get("email", "")
    error = None

    if request.method == "POST":
        code = request.POST.get("code", "").strip()
        allowed = check(
            request, "login-verify", scope=f"ip:{client_ip(request)}"
        )
        if not allowed:
            error = "Too many attempts. Please wait and try again."
        else:
            user, reason = services.verify_code(email, code)
            if user is not None:
                login(request, user)
                messages.success(request, "You are signed in.")
                return redirect(_next_url(request))
            error = (
                "That code is not valid."
                if reason == "invalid"
                else "That code has expired. Request a new one."
            )

    return render(
        request,
        "accounts/sign_in_code.html",
        {"email": email, "error": error},
    )


@require_http_methods(["POST"])
def sign_out(request):
    logout(request)
    messages.success(request, "You are signed out.")
    return redirect("web:home")


@login_required
@require_http_methods(["GET", "POST"])
def device_authorize(request):
    """Browser page the macOS app sends the user to."""

    user_code = request.POST.get("user_code", "").strip() or request.GET.get(
        "user_code", ""
    )
    error = None
    approved = None

    if request.method == "POST":
        action = request.POST.get("action", "")
        if action == "deny":
            authorization, error = services.deny_device(request.user, user_code)
            if authorization is not None:
                return render(
                    request,
                    "accounts/device_result.html",
                    {"approved": False, "user_code": authorization.user_code},
                )
        elif action == "approve":
            authorization, error = services.approve_device(request.user, user_code)
            if authorization is not None:
                return render(
                    request,
                    "accounts/device_result.html",
                    {"approved": True, "user_code": authorization.user_code},
                )
        else:
            error = "Unknown action."

    return render(
        request,
        "accounts/device_authorize.html",
        {"user_code": user_code, "error": error},
    )
