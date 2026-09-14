"""Transactional email.

`EmailProvider` is the seam described in the platform specification. The
development default is the console provider; production uses a hosted
transactional provider so no SMTP server is self-hosted.
"""

import json
import logging
import urllib.error
import urllib.request

from django.conf import settings
from django.core.mail import send_mail

logger = logging.getLogger(__name__)


class EmailProvider:
    def send(self, *, to, subject, body, html=None):
        raise NotImplementedError


class ConsoleEmailProvider(EmailProvider):
    """Development transport: uses Django's console email backend."""

    def send(self, *, to, subject, body, html=None):
        send_mail(
            subject,
            body,
            settings.DEFAULT_FROM_EMAIL,
            [to],
            html_message=html,
            fail_silently=False,
        )


class SMTPEmailProvider(EmailProvider):
    """Hosted SMTP transport configured through EMAIL_* settings."""

    def send(self, *, to, subject, body, html=None):
        send_mail(
            subject,
            body,
            settings.DEFAULT_FROM_EMAIL,
            [to],
            html_message=html,
            fail_silently=False,
        )


class ResendEmailProvider(EmailProvider):
    """Resend HTTP API. Free tier is sufficient to start; no self-hosting."""

    ENDPOINT = "https://api.resend.com/emails"

    def send(self, *, to, subject, body, html=None):
        api_key = settings.EMAIL_PROVIDER_API_KEY
        if not api_key:
            raise RuntimeError("EMAIL_PROVIDER_API_KEY is not configured.")

        payload = {
            "from": settings.DEFAULT_FROM_EMAIL,
            "to": [to],
            "subject": subject,
            "text": body,
        }
        if html:
            payload["html"] = html

        request = urllib.request.Request(
            self.ENDPOINT,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                response.read()
        except urllib.error.HTTPError as exc:
            # Never include the message body or API key in logs.
            logger.error("resend_send_failed status=%s", exc.code)
            raise


def get_email_provider():
    name = (settings.EMAIL_PROVIDER or "console").lower()

    if name == "console":
        if not settings.DEBUG:
            logger.error(
                "EMAIL_PROVIDER=console is not allowed in production; "
                "falling back to SMTP"
            )
            return SMTPEmailProvider()
        return ConsoleEmailProvider()

    if name == "resend":
        return ResendEmailProvider()

    return SMTPEmailProvider()


def send_email(*, to, subject, body, html=None):
    return get_email_provider().send(
        to=to, subject=subject, body=body, html=html
    )
