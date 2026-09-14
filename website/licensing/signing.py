"""Ed25519 signing for license authorizations.

The server holds the private key; the macOS app embeds only the public key and
verifies authorizations offline. Standard primitives only (`cryptography`).
"""

import base64
import json
import time

from django.conf import settings
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


class SigningError(Exception):
    pass


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64url_decode(value: str) -> bytes:
    padded = value + "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def load_private_key():
    pem_or_b64 = settings.LICENSE_SIGNING_PRIVATE_KEY or ""
    key_file = settings.LICENSE_SIGNING_PRIVATE_KEY_FILE or ""

    if key_file:
        try:
            with open(key_file, "rb") as handle:
                return serialization.load_pem_private_key(handle.read(), password=None)
        except OSError as exc:
            raise SigningError("Could not read LICENSE_SIGNING_PRIVATE_KEY_FILE.") from exc

    if not pem_or_b64:
        raise SigningError(
            "No license signing key configured. Run `manage.py generate_signing_key`."
        )

    if "BEGIN" in pem_or_b64:
        return serialization.load_pem_private_key(
            pem_or_b64.encode("utf-8"), password=None
        )

    try:
        seed = b64url_decode(pem_or_b64)
    except Exception as exc:  # noqa: BLE001
        raise SigningError("LICENSE_SIGNING_PRIVATE_KEY is not valid base64.") from exc

    return Ed25519PrivateKey.from_private_bytes(seed)


def public_key_base64():
    """The raw public key (32 bytes) as base64url. Embedded in the app."""
    key = load_private_key()
    raw = key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return b64url(raw)


def sign_authorization(payload: dict) -> str:
    """Return a compact, signed token: ``base64url(header).payload.signature``."""
    key = load_private_key()
    header = {"alg": "Ed25519", "kid": settings.LICENSE_SIGNING_KEY_ID}
    signing_input = (
        f"{b64url(json.dumps(header, separators=(',', ':')).encode('utf-8'))}."
        f"{b64url(json.dumps(payload, separators=(',', ':')).encode('utf-8'))}"
    ).encode("ascii")

    signature = key.sign(signing_input)
    return f"{signing_input.decode('ascii')}.{b64url(signature)}"


def verify_authorization(token: str, public_key_b64: str) -> dict:
    """Verify a token against a raw base64url public key. Used by tests and the
    macOS-side verification logic is implemented equivalently in Swift."""
    try:
        header_b64, payload_b64, signature_b64 = token.split(".")
    except ValueError as exc:
        raise SigningError("Malformed authorization token.") from exc

    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    try:
        public_key = Ed25519PublicKey.from_public_bytes(b64url_decode(public_key_b64))
        public_key.verify(b64url_decode(signature_b64), signing_input)
    except Exception as exc:  # noqa: BLE001
        raise SigningError("Authorization signature is invalid.") from exc

    return json.loads(b64url_decode(payload_b64).decode("utf-8"))


def build_authorization_payload(license_obj, installation):
    """The claims the app verifies offline.

    `exp` is the offline grace deadline, not the license expiry: a lifetime
    license has no expiry. `revalidate_after` nudges the app to check in.
    """
    now = int(time.time())
    grace_until = now + settings.LICENSE_OFFLINE_GRACE_DAYS * 86400
    return {
        "v": 1,
        "key": settings.LICENSE_SIGNING_KEY_ID,
        "sub": str(license_obj.user_id),
        "lic": str(license_obj.id),
        "product": license_obj.product,
        "type": license_obj.license_type,
        "status": license_obj.status,
        "inst": str(installation.installation_id),
        "iat": now,
        "revalidate_after": now + 86400,
        # `exp` is the offline validity deadline; a lifetime license has no
        # entitlement expiry (`ent_exp` is null).
        "exp": grace_until,
        "ent_exp": None,
    }


def build_trial_authorization_payload(user, installation, trial):
    """Claims for a trial grant.

    `ent_exp` is the hard trial end: the app locks when it passes, even offline.
    `exp` equals it so cached authorization cannot outlive the trial.
    """
    now = int(time.time())
    trial_end = int(trial.ends_at.timestamp())
    return {
        "v": 1,
        "key": settings.LICENSE_SIGNING_KEY_ID,
        "sub": str(user.pk),
        "lic": "",
        "product": settings.PRODUCT_NAME,
        "type": "trial",
        "status": "active",
        "inst": str(installation.installation_id),
        "iat": now,
        "revalidate_after": min(now + 86400, trial_end),
        "exp": trial_end,
        "ent_exp": trial_end,
    }
