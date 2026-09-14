from django.conf import settings
from django.db.models.signals import post_save
from django.dispatch import receiver

from accounts.models import User

from .models import Profile


@receiver(post_save, sender=User)
def ensure_profile(sender, instance, created, **kwargs):
    """Every account owns exactly one profile.

    The profile starts without a username; the writer chooses one from the
    dashboard. This keeps account creation fast and avoids inventing public
    identifiers from email addresses.
    """
    if created:
        Profile.objects.get_or_create(user=instance)
