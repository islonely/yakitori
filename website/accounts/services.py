"""Identity services: passwordless login, API tokens, and device authorization.

Views stay thin; all rules live here so they can be unit-tested directly.
"""

import secrets
from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from audit.models import AuditEvent
from audit.services import record
from common.text import (
    constant_time_equals,
    generate_device_code,
    generate_numeric_code,
    generate_url_token,
    normalize_email,
    sha256_hex,
)

from .emails import send_login_email
from .models import ApiToken, DeviceAuthorization, LoginChallenge, User

USER_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


# ---------------------------------------------------------------------------
# Passwordless login
# ---------------------------------------------------------------------------


def request_login(email, request_ip=None):
    """Create a single-use challenge and email it. Returns the challenge.

    The response to the caller is always the same whether or not an account
    exists, which prevents account enumeration.
    """
    normalized = normalize_email(email)
    token = generate_url_token()
    code = generate_numeric_code()
    challenge = LoginChallenge.objects.create(
        email_normalized=normalized,
        token_hash=sha256_hex(token),
        code_hash=sha256_hex(code),
        expires_at=timezone.now()
        + timedelta(seconds=settings.LOGIN_CHALLENGE_TTL_SECONDS),
        request_ip=request_ip,
    )
    send_login_email(email.strip(), token, code)
    return challenge


def _get_or_create_user(normalized_email):
    user = User.objects.filter(email_normalized=normalized_email).first()
    if user is not None:
        return user, False

    user = User(email=normalized_email)
    user.set_unusable_password()
    user.status = User.Status.ACTIVE
    user.email_verified_at = timezone.now()
    try:
        user.save()
        created = True
    except IntegrityError:
        user = User.objects.get(email_normalized=normalized_email)
        created = False

    if created:
        record(
            AuditEvent.Type.ACCOUNT_CREATED,
            target=user,
            source="auth",
        )
    return user, created


def _complete_challenge(challenge):
    if challenge is None:
        return None, "invalid"
    if not challenge.is_usable:
        return None, "expired"

    with transaction.atomic():
        challenge = LoginChallenge.objects.select_for_update().get(pk=challenge.pk)
        if not challenge.is_usable:
            return None, "expired"
        challenge.consumed_at = timezone.now()
        challenge.save(update_fields=["consumed_at"])
        user, _created = _get_or_create_user(challenge.email_normalized)

    if not user.can_sign_in:
        record(
            AuditEvent.Type.LOGIN_FAILED,
            target=user,
            source="auth",
            reason="inactive",
        )
        return None, "inactive"

    if user.email_verified_at is None:
        user.mark_email_verified()

    record(AuditEvent.Type.LOGIN_SUCCEEDED, actor=user, target=user, source="auth")
    return user, None


def verify_token(token):
    challenge = (
        LoginChallenge.objects
        .filter(token_hash=sha256_hex(token))
        .first()
    )
    return _complete_challenge(challenge)


def verify_code(email, code):
    normalized = normalize_email(email)
    challenge = (
        LoginChallenge.objects
        .filter(email_normalized=normalized, consumed_at__isnull=True)
        .order_by("-created_at")
        .first()
    )
    if challenge is None or not challenge.is_usable:
        return None, "expired"

    if not constant_time_equals(sha256_hex(code), challenge.code_hash):
        challenge.attempts += 1
        challenge.save(update_fields=["attempts"])
        return None, "invalid"

    return _complete_challenge(challenge)


# ---------------------------------------------------------------------------
# API tokens
# ---------------------------------------------------------------------------


def issue_api_token(user, label="", installation_uuid=None, days=None):
    """Create a token, returning ``(plaintext, instance)``.

    The plaintext is shown once and stored by the client in the Keychain; only
    its hash is persisted.
    """
    raw = generate_url_token(32)
    if days is None:
        days = settings.API_TOKEN_TTL_DAYS
    expires_at = timezone.now() + timedelta(days=days) if days else None

    token = ApiToken.objects.create(
        user=user,
        label=label[:120],
        installation_uuid=installation_uuid,
        token_hash=sha256_hex(raw),
        expires_at=expires_at,
    )
    record(AuditEvent.Type.TOKEN_CREATED, actor=user, target=user, source="api")
    return raw, token


def revoke_api_token(user, token_id):
    updated = (
        ApiToken.objects
        .filter(pk=token_id, user=user, revoked_at__isnull=True)
        .update(revoked_at=timezone.now())
    )
    if updated:
        record(AuditEvent.Type.TOKEN_REVOKED, actor=user, target=user, source="api")
    return bool(updated)


def revoke_all_tokens(user):
    count = (
        ApiToken.objects
        .filter(user=user, revoked_at__isnull=True)
        .update(revoked_at=timezone.now())
    )
    if count:
        record(
            AuditEvent.Type.TOKEN_REVOKED,
            actor=user,
            target=user,
            source="api",
            count=count,
        )
    return count


def authenticate_token(raw_token):
    """Resolve a bearer token to an ApiToken, or None."""
    if not raw_token:
        return None
    token = (
        ApiToken.objects
        .select_related("user")
        .filter(token_hash=sha256_hex(raw_token))
        .first()
    )
    if token is None or not token.is_valid:
        return None
    if not token.user.can_sign_in:
        return None

    now = timezone.now()
    if token.last_used_at is None or (now - token.last_used_at) > timedelta(minutes=1):
        # Avoid a write on every request; one per minute is plenty for "last seen".
        ApiToken.objects.filter(pk=token.pk).update(last_used_at=now)
    return token


# ---------------------------------------------------------------------------
# Device authorization (macOS app)
# ---------------------------------------------------------------------------


def normalize_user_code(value):
    return "".join(ch for ch in (value or "").upper() if ch in USER_CODE_ALPHABET)


def _new_user_code():
    raw = "".join(secrets.choice(USER_CODE_ALPHABET) for _ in range(8))
    return f"{raw[:4]}-{raw[4:]}"


def start_device_authorization(client_name=""):
    device_code = generate_device_code()
    for _ in range(10):
        user_code = _new_user_code()
        if not DeviceAuthorization.objects.filter(user_code=user_code).exists():
            break

    authorization = DeviceAuthorization.objects.create(
        device_code_hash=sha256_hex(device_code),
        user_code=user_code,
        client_name=(client_name or "")[:120],
        expires_at=timezone.now()
        + timedelta(seconds=settings.DEVICE_CODE_TTL_SECONDS),
        poll_interval=settings.DEVICE_CODE_POLL_INTERVAL,
    )
    return authorization, device_code


def approve_device(user, user_code):
    code = normalize_user_code(user_code)
    authorization = (
        DeviceAuthorization.objects
        .filter(user_code__startswith=code[:4], status=DeviceAuthorization.Status.PENDING)
        .first()
    )
    if authorization is None or authorization.is_expired:
        return None, "invalid"

    authorization.status = DeviceAuthorization.Status.APPROVED
    authorization.user = user
    authorization.approved_at = timezone.now()
    authorization.save(update_fields=["status", "user", "approved_at"])
    record(AuditEvent.Type.DEVICE_APPROVED, actor=user, target=user, source="api")
    return authorization, None


def deny_device(user, user_code):
    code = normalize_user_code(user_code)
    authorization = (
        DeviceAuthorization.objects
        .filter(user_code__startswith=code[:4], status=DeviceAuthorization.Status.PENDING)
        .first()
    )
    if authorization is None or authorization.is_expired:
        return None, "invalid"

    authorization.status = DeviceAuthorization.Status.DENIED
    authorization.save(update_fields=["status"])
    record(AuditEvent.Type.DEVICE_DENIED, actor=user, target=user, source="api")
    return authorization, None


def exchange_device_code(device_code, label=""):
    """Exchange an approved device code for an API token.

    Returns ``(plaintext_or_None, error_code)`` where ``error_code`` is one of
    ``invalid``, ``expired``, ``pending``, ``denied``, or ``None`` on success.
    """
    authorization = (
        DeviceAuthorization.objects
        .select_related("user")
        .filter(device_code_hash=sha256_hex(device_code))
        .first()
    )
    if authorization is None:
        return None, "invalid"
    if authorization.is_expired:
        return None, "expired"

    if authorization.status == DeviceAuthorization.Status.PENDING:
        authorization.last_polled_at = timezone.now()
        authorization.save(update_fields=["last_polled_at"])
        return None, "pending"

    if authorization.status == DeviceAuthorization.Status.DENIED:
        return None, "denied"

    if authorization.status == DeviceAuthorization.Status.CONSUMED:
        return None, "expired"

    if authorization.user is None:
        return None, "invalid"

    plaintext, _token = issue_api_token(
        authorization.user,
        label=label or authorization.client_name or "Yakitori for Mac",
    )

    authorization.status = DeviceAuthorization.Status.CONSUMED
    authorization.consumed_at = timezone.now()
    authorization.save(update_fields=["status", "consumed_at"])
    return plaintext, None
