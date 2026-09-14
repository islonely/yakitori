from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from common.emails import get_email_provider


class Command(BaseCommand):
    help = (
        "Send a test email to verify the configured provider "
        "(console, smtp, or resend)."
    )

    def add_arguments(self, parser):
        parser.add_argument("email", help="Recipient address to test.")

    def handle(self, *args, **options):
        recipient = options["email"]
        provider = get_email_provider()

        self.stdout.write(f"Provider: {settings.EMAIL_PROVIDER} ({type(provider).__name__})")
        self.stdout.write(f"From:     {settings.DEFAULT_FROM_EMAIL}")
        self.stdout.write(f"To:       {recipient}")

        try:
            provider.send(
                to=recipient,
                subject="Yakitori test email",
                body=(
                    "If you can read this, Yakitori's transactional email is "
                    "configured correctly."
                ),
            )
        except Exception as exc:  # noqa: BLE001 - surfaced to the operator
            raise CommandError(f"Sending failed: {exc}") from exc

        if settings.EMAIL_PROVIDER == "console":
            self.stdout.write(
                self.style.WARNING(
                    "The console provider prints the email to this terminal "
                    "instead of delivering it. Set EMAIL_PROVIDER to 'smtp' or "
                    "'resend' for real delivery (see .env.example)."
                )
            )
        else:
            self.stdout.write(self.style.SUCCESS(f"Sent to {recipient}"))
