"""Licensing services.

Lifetime licenses, unlimited installations, and signed authorizations. Nothing
here requires manuscript data, and no license is ever tied to a device.
"""

import logging
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from audit.models import AuditEvent
from audit.services import record

from .models import Installation, License, Trial
from .signing import (
    build_authorization_payload,
    build_trial_authorization_payload,
    sign_authorization,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Licenses
# ---------------------------------------------------------------------------


def _product():
    return settings.PRODUCT_NAME


def grant_lifetime_license(purchase):
    """Idempotently create an active lifetime license for a completed purchase."""
    if purchase is None or purchase.user_id is None:
        return None

    with transaction.atomic():
        license_obj, created = License.objects.get_or_create(
            user_id=purchase.user_id,
            product=_product(),
            defaults={
                "license_type": License.Type.LIFETIME,
                "status": License.Status.ACTIVE,
                "purchased_at": purchase.purchased_at or timezone.now(),
                "payment_purchase": purchase,
            },
        )
        if not created and license_obj.payment_purchase_id is None:
            license_obj.payment_purchase = purchase
            license_obj.save(update_fields=["payment_purchase", "updated_at"])

    if created:
        record(
            AuditEvent.Type.LICENSE_CREATED,
            target=purchase.user,
            source="licensing",
            purchase=str(purchase.id),
        )
    return license_obj


def _set_status(purchase, status, reason, audit_type):
    if purchase is None or purchase.user_id is None:
        return None

    license_obj = License.objects.filter(
        user_id=purchase.user_id, product=_product()
    ).first()
    if license_obj is None:
        return None

    license_obj.status = status
    license_obj.revocation_reason = reason if status != License.Status.ACTIVE else ""
    license_obj.save(update_fields=["status", "revocation_reason", "updated_at"])

    record(
        audit_type,
        target=purchase.user,
        source="licensing",
        status=status,
        reason=reason,
        purchase=str(purchase.id),
    )
    return license_obj


def revoke_license_for_purchase(purchase, reason="refund"):
    return _set_status(
        purchase, License.Status.REVOKED, reason, AuditEvent.Type.LICENSE_REVOKED
    )


def disable_license_for_purchase(purchase, reason="dispute"):
    return _set_status(
        purchase, License.Status.DISABLED, reason, AuditEvent.Type.LICENSE_REVOKED
    )


def restore_license_for_purchase(purchase):
    return _set_status(
        purchase, License.Status.ACTIVE, "", AuditEvent.Type.LICENSE_RESTORED
    )


def set_license_status(license_obj, status, *, actor=None, reason="", source="admin"):
    license_obj.status = status
    license_obj.revocation_reason = reason if status != License.Status.ACTIVE else ""
    license_obj.save(update_fields=["status", "revocation_reason", "updated_at"])

    event_type = (
        AuditEvent.Type.LICENSE_RESTORED
        if status == License.Status.ACTIVE
        else AuditEvent.Type.LICENSE_REVOKED
    )
    record(
        event_type,
        actor=actor,
        target=license_obj.user,
        source=source,
        status=status,
        reason=reason,
    )
    return license_obj


def active_license(user):
    return License.objects.filter(
        user=user, product=_product(), status=License.Status.ACTIVE
    ).first()


def license_for(user):
    return License.objects.filter(user=user, product=_product()).first()


# ---------------------------------------------------------------------------
# Installations
# ---------------------------------------------------------------------------


def register_installation(user, installation_id, platform="macOS", app_version=""):
    """Register (or re-bind) an installation. Unlimited installations allowed."""
    with transaction.atomic():
        installation, created = (
            Installation.objects
            .select_for_update()
            .get_or_create(
                installation_id=installation_id,
                defaults={
                    "user": user,
                    "platform": platform or "macOS",
                    "app_version": app_version or "",
                },
            )
        )
        if not created:
            # Same Mac, possibly a different account, or a returning user.
            installation.user = user
            if platform:
                installation.platform = platform
            if app_version:
                installation.app_version = app_version
            installation.revoked_at = None
            installation.save(
                update_fields=[
                    "user",
                    "platform",
                    "app_version",
                    "revoked_at",
                    "last_seen_at",
                ]
            )

    record(
        AuditEvent.Type.INSTALLATION_REGISTERED,
        actor=user,
        target=user,
        source="licensing",
        installation=str(installation_id),
        app_version=app_version,
    )
    return installation, created


def revoke_installation(user, installation_id):
    updated = (
        Installation.objects
        .filter(user=user, installation_id=installation_id, revoked_at__isnull=True)
        .update(revoked_at=timezone.now())
    )
    if updated:
        record(
            AuditEvent.Type.INSTALLATION_REVOKED,
            actor=user,
            target=user,
            source="licensing",
            installation=str(installation_id),
        )
    return bool(updated)


def find_installation(user, installation_id):
    return Installation.objects.filter(
        user=user, installation_id=installation_id
    ).first()


# ---------------------------------------------------------------------------
# Validation and signed authorization
# ---------------------------------------------------------------------------


def trial_duration():
    """How long a new trial lasts. `TRIAL_SECONDS` overrides days for tests."""
    seconds = getattr(settings, "TRIAL_SECONDS", 0)
    if seconds:
        return timedelta(seconds=seconds)
    return timedelta(days=settings.TRIAL_DAYS)


def trial_for(user):
    return Trial.objects.filter(user=user).first()


def trial_status(user):
    trial = trial_for(user)
    if trial is None:
        return {
            "used": False,
            "active": False,
            "ends_at": None,
            "days_remaining": 0,
        }
    return {
        "used": True,
        "active": trial.is_active,
        "ends_at": trial.ends_at,
        "days_remaining": trial.days_remaining,
    }


def start_or_resume_trial(user, installation):
    """Start a trial once, or return the existing one.

    Returns ``None`` when the installation has already consumed a trial, which
    prevents restarting a trial by creating a new account on the same Mac.
    """
    existing = trial_for(user)
    if existing is not None:
        return existing

    if installation is not None and installation.trial_consumed_at is not None:
        record(
            AuditEvent.Type.TRIAL_STARTED,
            target=user,
            source="licensing",
            outcome="refused_installation_used",
        )
        return None

    trial = Trial.objects.create(
        user=user,
        ends_at=timezone.now() + trial_duration(),
        installation_uuid=installation.installation_id if installation else None,
    )
    if installation is not None:
        installation.trial_consumed_at = timezone.now()
        installation.save(update_fields=["trial_consumed_at", "last_seen_at"])

    record(
        AuditEvent.Type.TRIAL_STARTED,
        target=user,
        source="licensing",
        days=settings.TRIAL_DAYS,
    )
    return trial


def _installation_error(installation):
    if installation is None:
        return "installation_not_registered"
    if not installation.is_active:
        return "installation_revoked"
    return None


def validate_license(user, installation):
    """Return a validation result and, when valid, a signed authorization.

    Resolution order:

    1. An existing license wins. A revoked/disabled license yields an invalid
       result and **never** falls back to a trial.
    2. Otherwise a one-time trial is started (or resumed). Expired or
       already-consumed trials yield an invalid result.
    """
    license_obj = License.objects.filter(user=user, product=_product()).first()

    if license_obj is not None:
        if license_obj.status != License.Status.ACTIVE:
            return {"valid": False, "reason": license_obj.status, "kind": "license"}

        error = _installation_error(installation)
        if error:
            return {"valid": False, "reason": error}

        token = sign_authorization(
            build_authorization_payload(license_obj, installation)
        )
        record(
            AuditEvent.Type.LICENSE_VALIDATED,
            actor=user,
            target=user,
            source="licensing",
            kind="license",
            installation=str(installation.installation_id),
        )
        return {
            "valid": True,
            "kind": "license",
            "authorization": token,
            "offline_grace_days": settings.LICENSE_OFFLINE_GRACE_DAYS,
            "license": license_obj,
        }

    # No license: the trial path.
    error = _installation_error(installation)
    if error:
        return {"valid": False, "reason": error}

    trial = start_or_resume_trial(user, installation)
    if trial is None:
        return {"valid": False, "reason": "trial_unavailable", "kind": "trial"}
    if not trial.is_active:
        return {"valid": False, "reason": "trial_expired", "kind": "trial"}

    token = sign_authorization(
        build_trial_authorization_payload(user, installation, trial)
    )
    record(
        AuditEvent.Type.LICENSE_VALIDATED,
        actor=user,
        target=user,
        source="licensing",
        kind="trial",
        installation=str(installation.installation_id),
    )
    return {
        "valid": True,
        "kind": "trial",
        "authorization": token,
        "offline_grace_days": 0,
        "trial": trial,
    }
