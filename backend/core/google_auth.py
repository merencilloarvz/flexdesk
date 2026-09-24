"""
Verifies a Google Sign-In ID token server-side. Never trust a token
without this: the client-side google_sign_in SDK can be bypassed or
spoofed, but a token that verifies against Google's own public keys and
this app's own OAuth client id cannot be forged.
"""
import logging

from django.conf import settings
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

logger = logging.getLogger(__name__)


class GoogleTokenError(Exception):
    """
    Raised for any reason an ID token can't be trusted — bad signature,
    wrong audience, expired, malformed, or GOOGLE_OAUTH_CLIENT_ID isn't
    configured on this server. The message is always safe to show the
    caller as-is.
    """


def verify_google_id_token(token):
    """
    Returns (google_sub, email, email_verified, full_name) for a
    genuinely valid token, straight from Google's own verified claims.
    Raises GoogleTokenError for anything else — including a transport
    failure reaching Google, which surfaces as the same "try again"
    style message rather than a stack trace.
    """
    if not settings.GOOGLE_OAUTH_CLIENT_ID:
        raise GoogleTokenError("Google sign-in isn't configured on this server.")

    try:
        payload = google_id_token.verify_oauth2_token(
            token, google_requests.Request(), settings.GOOGLE_OAUTH_CLIENT_ID,
        )
    except ValueError:
        # Covers every rejection reason the library raises this for:
        # bad signature, expired, wrong audience/issuer, malformed token.
        raise GoogleTokenError(
            "That Google sign-in couldn't be verified. Please try again.")
    except Exception:
        logger.exception("Unexpected error verifying Google ID token")
        raise GoogleTokenError(
            "Couldn't reach Google to verify your sign-in. Please try again.")

    sub = payload.get("sub")
    email = (payload.get("email") or "").strip().lower()
    email_verified = bool(payload.get("email_verified"))
    full_name = payload.get("name") or ""

    if not sub or not email:
        raise GoogleTokenError(
            "That Google sign-in couldn't be verified. Please try again.")

    return sub, email, email_verified, full_name
