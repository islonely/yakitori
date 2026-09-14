from django.conf import settings
from django.core.checks import Error, Tags, register


# deploy=True: only runs for `manage.py check --deploy`, so it never blocks
# normal development or the test suite.
@register(Tags.security, deploy=True)
def email_provider_check(app_configs, **kwargs):
    """Fail deployment if the console email provider is selected in production.

    A console provider prints tokens instead of sending them, so in production
    it would silently break sign-in (and expose login codes in logs).
    """
    problems = []
    if not settings.DEBUG and settings.EMAIL_PROVIDER == "console":
        problems.append(
            Error(
                "EMAIL_PROVIDER=console is not allowed when DEBUG=false.",
                hint=(
                    "Set EMAIL_PROVIDER to 'resend' or 'smtp' and configure the "
                    "matching settings (see website/.env.example)."
                ),
                id="yakitori.E001",
            )
        )
    return problems
