"""
The one place anything in FlexDesk sends a push notification. See A3 in
FLEXDESK_PHASE4_PUSH_NOTIFICATIONS.md.
"""
import json
import logging

import firebase_admin
from django.conf import settings
from firebase_admin import credentials, exceptions, messaging

from .models import DeviceToken

logger = logging.getLogger(__name__)

# FCM's multicast endpoint accepts at most 500 tokens per call.
_TOKENS_PER_BATCH = 500

# Errors that mean the token itself is dead — the app was uninstalled,
# or the token is malformed/expired — so the row is pruned rather than
# retried on the next send.
_PRUNE_ON = (messaging.UnregisteredError, exceptions.InvalidArgumentError)

# Must match pushNotificationChannelId in
# frontend/lib/core/notifications/push_notification_service.dart and the
# default_notification_channel_id meta-data in AndroidManifest.xml — all
# three have to agree for a backgrounded/terminated app to show the
# notification at HIGH importance (sound + heads-up banner) rather than
# falling back to a silent default channel.
_ANDROID_CHANNEL_ID = "high_importance_channel"


def _get_app():
    """
    Lazily initialises the default Firebase app from
    FIREBASE_SERVICE_ACCOUNT_JSON. Safe to call repeatedly — once per
    Gunicorn worker process, or a hundred times a second from one —
    since firebase_admin's app registry is itself idempotent per
    process; the two ValueError catches below just cover the two ways
    "already initialised" can show up (already there when we check, or
    another thread won the race to create it after we checked).
    """
    raw = settings.FIREBASE_SERVICE_ACCOUNT_JSON
    if not raw:
        return None
    try:
        return firebase_admin.get_app()
    except ValueError:
        pass
    cred = credentials.Certificate(json.loads(raw))
    try:
        return firebase_admin.initialize_app(cred)
    except ValueError:
        return firebase_admin.get_app()


def _chunks(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i:i + size]


def send_to_users(users, title, body, data=None):
    """
    Pushes `title`/`body` to every device registered to any of `users`.
    Returns (sent_count, pruned_count). Never raises — FCM being down or
    misconfigured must never fail the caller (posting an announcement, a
    sale hitting zero stock, the daily command).
    """
    try:
        app = _get_app()
    except Exception:
        logger.exception("Failed to initialise Firebase app")
        return (0, 0)
    if app is None:
        return (0, 0)

    tokens = list(
        DeviceToken.objects.filter(user__in=users).values_list("token", flat=True)
    )
    if not tokens:
        return (0, 0)

    string_data = {str(k): ("" if v is None else str(v)) for k, v in (data or {}).items()}

    sent_count = 0
    dead_tokens = []

    for batch in _chunks(tokens, _TOKENS_PER_BATCH):
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=string_data,
            tokens=batch,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id=_ANDROID_CHANNEL_ID,
                ),
            ),
        )
        try:
            response = messaging.send_each_for_multicast(message, app=app)
        except Exception:
            logger.exception("FCM send failed")
            continue

        for token, result in zip(batch, response.responses):
            if result.success:
                sent_count += 1
            elif isinstance(result.exception, _PRUNE_ON):
                dead_tokens.append(token)

    pruned_count = 0
    if dead_tokens:
        pruned_count, _ = DeviceToken.objects.filter(token__in=dead_tokens).delete()

    return (sent_count, pruned_count)
