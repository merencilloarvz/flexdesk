"""
TOTP-style check-in codes. This module is normative — the Dart side (Phase
3b Part B) re-implements the same algorithm against the same shared test
vectors, and the two must never diverge. Every choice below is pinned
deliberately; do not "simplify" without updating both sides and the
vectors in core/tests/test_qr.py.
"""
import base64
import hmac
import hashlib
import secrets

PERIOD_SECONDS = 60
DIGITS = 8
STEP_TOLERANCE = 1  # accept current_step - 1 .. current_step + 1

# QR payload prefixes (Phase 3b Part A8). Two shapes, never confused —
# CHECKIN_PREFIX carries a member id + code; CLAIM_PREFIX carries only a
# claim code (never the email) so a photographed claim card is harmless
# on its own.
CHECKIN_PREFIX = "FDCHK1"
CLAIM_PREFIX = "FDCLAIM1"


def generate_secret() -> str:
    """32 random bytes, base32-encoded (RFC 4648, uppercase, '=' kept)."""
    return base64.b32encode(secrets.token_bytes(32)).decode("ascii")


def time_step(unix_seconds: float) -> int:
    return int(unix_seconds // PERIOD_SECONDS)


def compute_code(secret_b32: str, step: int) -> str:
    """
    RFC 4226 dynamic truncation over HMAC-SHA256(key, step). `key` is the
    32 raw bytes the base32 secret decodes to — NOT the base32 text
    itself, which is the single most likely place a reimplementation
    disagrees with this one.
    """
    key = base64.b32decode(secret_b32)
    message = step.to_bytes(8, "big")
    digest = hmac.new(key, message, hashlib.sha256).digest()

    offset = digest[31] & 0x0F
    binary = (
        ((digest[offset] & 0x7F) << 24)
        | (digest[offset + 1] << 16)
        | (digest[offset + 2] << 8)
        | digest[offset + 3]
    )
    code = binary % (10 ** DIGITS)
    return str(code).zfill(DIGITS)


def accepted_steps(step: int) -> list[int]:
    """Steps a submitted code is checked against, for clock drift."""
    return [step + delta for delta in range(-STEP_TOLERANCE, STEP_TOLERANCE + 1)]
