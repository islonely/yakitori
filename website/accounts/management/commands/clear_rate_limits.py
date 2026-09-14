from django.core.management.base import BaseCommand

from accounts.models import RateLimitEntry


class Command(BaseCommand):
    help = (
        "Clear rate-limit counters. Useful in development, or to unblock an IP "
        "after a burst of failed attempts."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--action",
            help="Only clear this action prefix (for example login-verify).",
        )
        parser.add_argument(
            "--contains",
            help="Only clear keys containing this substring (for example 127.0.0.1).",
        )

    def handle(self, *args, **options):
        queryset = RateLimitEntry.objects.all()
        if options.get("action"):
            queryset = queryset.filter(key__startswith=f"{options['action']}:")
        if options.get("contains"):
            queryset = queryset.filter(key__contains=options["contains"])

        count = queryset.count()
        queryset.delete()
        self.stdout.write(
            self.style.SUCCESS(f"Cleared {count} rate-limit counter(s).")
        )
