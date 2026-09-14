"""Login and security email composition.

Templates are plain text plus a small HTML alternative. They contain a
single-use link and a short code. Neither is ever logged.
"""

from django.conf import settings
from django.urls import reverse

from common.emails import send_email


def _verify_url(token):
    path = reverse("accounts:sign-in-verify", args=[token])
    return f"{settings.APP_BASE_URL}{path}"


def send_login_email(email, token, code):
    url = _verify_url(token)
    subject = f"Sign in to {settings.PLATFORM_NAME}"
    body = "\n".join(
        [
            f"Use the link below to sign in to {settings.PLATFORM_NAME}.",
            "",
            url,
            "",
            f"Or enter this code: {code}",
            "",
            f"This link and code expire in {settings.LOGIN_CHALLENGE_TTL_SECONDS // 60} minutes.",
            "If you did not request this, you can ignore this email.",
        ]
    )
    html = (
        f"<p>Use the link below to sign in to {settings.PLATFORM_NAME}.</p>"
        f'<p><a href="{url}">Sign in</a></p>'
        f"<p>Or enter this code: <strong>{code}</strong></p>"
        f"<p>This link and code expire in "
        f"{settings.LOGIN_CHALLENGE_TTL_SECONDS // 60} minutes. If you did not "
        f"request this, you can ignore this email.</p>"
    )
    send_email(to=email, subject=subject, body=body, html=html)


def send_security_notice_email(email, subject, message):
    body = "\n".join([message, "", f"— {settings.PLATFORM_NAME}"])
    send_email(to=email, subject=subject, body=body)
