"""Cursor pagination for social and leaderboard collections.

Offset pagination degrades on large, high-growth tables, so ordering is always
by a stable key (created_at, id) and the client passes an opaque cursor.
"""

import base64
import binascii
import json

from common.jsonapi import ApiError


def encode_cursor(**values):
    raw = json.dumps(values, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_cursor(cursor):
    if not cursor:
        return {}
    padded = cursor + "=" * (-len(cursor) % 4)
    try:
        raw = base64.urlsafe_b64decode(padded.encode("ascii"))
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, binascii.Error):
        raise ApiError(400, "invalid_cursor", "The pagination cursor is invalid.")
    if not isinstance(data, dict):
        raise ApiError(400, "invalid_cursor", "The pagination cursor is invalid.")
    return data


def clamp_limit(value, default, maximum=200):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return max(1, min(number, maximum))
