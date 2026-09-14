"""Append-only audit logging.

Call :func:`record` from services and views. It never raises for a logging
failure and never stores secrets.
"""

import logging

from .models import AuditEvent

logger = logging.getLogger(__name__)

# Keys that must never be written to audit metadata, even by mistake.
_FORBIDDEN = {
    "password", "password1", "password2", "token", "access_token",
    "refresh_token", "device_code", "code", "secret", "api_key",
    "card", "card_number", "cvc", "authorization", "private_key",
    "manuscript", "document_text",
}


def _sanitize(metadata):
    clean = {}
    for key, value in (metadata or {}).items():
        if key.lower() in _FORBIDDEN:
            clean[key] = "[redacted]"
            continue
        if isinstance(value, (str, int, float, bool)) or value is None:
            clean[key] = value[:500] if isinstance(value, str) else value
        else:
            clean[key] = str(value)[:500]
    return clean


def record(event_type, actor=None, target=None, source="", **metadata):
    try:
        return AuditEvent.objects.create(
            event_type=event_type,
            actor_user_id=actor if getattr(actor, "pk", None) else None,
            target_user_id=target if getattr(target, "pk", None) else None,
            source=source[:60],
            metadata=_sanitize(metadata),
        )
    except Exception:
        # Audit logging must never break the user-facing request.
        logger.exception("audit_record_failed event_type=%s", event_type)
        return None
