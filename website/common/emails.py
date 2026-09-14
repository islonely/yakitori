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
from django.core.mail import EmailMultiAlternatives, get_connection, send_mail

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
    """Hosted SMTP transport configured through EMAIL_* settings.

    Builds its own SMTP connection rather than relying on `EMAIL_BACKEND`, so
    selecting `EMAIL_PROVIDER=smtp` always actually sends (a common
    misconfiguration is leaving `EMAIL_BACKEND` at the console backend).
    """

    def send(self, *, to, subject, body, html=None):
        if not settings.EMAIL_HOST:
            raise RuntimeError(
                "EMAIL_PROVIDER=smtp requires EMAIL_HOST (and usually "
                "EMAIL_HOST_USER / EMAIL_HOST_PASSWORD)."
            )

        connection = get_connection(
            backend="django.core.mail.backends.smtp.EmailBackend",
            host=settings.EMAIL_HOST,
            port=settings.EMAIL_PORT,
            username=settings.EMAIL_HOST_USER or None,
            password=settings.EMAIL_HOST_PASSWORD or None,
            use_tls=settings.EMAIL_USE_TLS,
            timeout=settings.EMAIL_TIMEOUT,
        )
        message = EmailMultiAlternatives(
            subject,
            body,
            settings.DEFAULT_FROM_EMAIL,
            [to],
            connection=connection,
        )
        if html:
            message.attach_alternative(html, "text/html")
        message.send(fail_silently=False)


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
    """Return the configured provider.

    - ``console`` uses Django's configured ``EMAIL_BACKEND`` (the console
      backend in development, or an alternate backend such as the in-memory one
      in tests).
    - ``smtp`` always sends over SMTP using the ``EMAIL_*`` settings.
    - ``resend`` posts to the Resend HTTP API.

    `accounts.checks` fails `manage.py check --deploy` when the console provider
    is selected in production, so mail cannot be silently dropped there.
    """
    name = (settings.EMAIL_PROVIDER or "console").lower()

    if name == "resend":
        return ResendEmailProvider()
    if name == "smtp":
        return SMTPEmailProvider()
    return ConsoleEmailProvider()


def send_email(*, to, subject, body, html=None):
    return get_email_provider().send(
        to=to, subject=subject, body=body, html=html
    )
