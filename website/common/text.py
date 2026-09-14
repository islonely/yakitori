"""Token, code, and normalization helpers."""

import hashlib
import secrets


def normalize_email(email):
    return (email or "").strip().lower()


def sha256_hex(value):
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()


def generate_url_token(bytes_length=32):
    """A high-entropy token for email links. Returned once, stored hashed."""
    return secrets.token_urlsafe(bytes_length)


def generate_numeric_code(digits=6):
    """A short numeric code for manual entry. Returned once, stored hashed."""
    upper = 10 ** digits
    return str(secrets.randbelow(upper)).zfill(digits)


def generate_device_code():
    return secrets.token_urlsafe(32)


def constant_time_equals(a, b):
    return secrets.compare_digest(a or "", b or "")
