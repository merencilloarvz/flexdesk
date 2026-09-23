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

# Every Android channel id here must exist client-side — created once at
# app start by PushNotificationService.ensureNotificationChannel in
# frontend/lib/core/notifications/push_notification_service.dart — and
# CHANNEL_DEFAULT must match the default_notification_channel_id
# meta-data in AndroidManifest.xml, the fallback FCM uses for a
# notification-only message delivered while the app is backgrounded or
# terminated. A channel's importance is fixed at first creation by
# Android, so this file, the manifest, and the Flutter channel-creation
# code all have to agree — nothing else must ever create a channel with
# one of these ids.
CHANNEL_DEFAULT = "high_importance_channel"
CHANNEL_ANNOUNCEMENTS = "channel_announcements"
CHANNEL_EVENTS = "channel_events"
CHANNEL_MEMBERSHIP = "channel_membership"
CHANNEL_CHECKINS = "channel_checkins"
CHANNEL_STORE = "channel_store"
CHANNEL_COMMUNITY = "channel_community"
CHANNEL_DAILY_SUMMARY = "channel_daily_summary"

# Channels created at NORMAL importance (sound, no heads-up pop-up) —
# every other channel is HIGH importance. Must match the Importance
# passed to each AndroidNotificationChannel in
# push_notification_service.dart.
_NORMAL_IMPORTANCE_CHANNELS = {CHANNEL_CHECKINS, CHANNEL_DAILY_SUMMARY}

_COLOR_PRIMARY = "#0F6E56"   # AppColors.accentTeal
_COLOR_WARNING = "#92600B"   # AppColors.expiringBg

# Optional custom sound: frontend/android/app/src/main/res/raw/
# flexdesk_chime.mp3 doesn't exist yet (nobody's dropped the file in) —
# flip this to True once it does. Referencing a raw resource that isn't
# bundled in the app would silently fail to play anything, so this stays
# False (falling back to each channel's default system sound) until the
# file is actually added.
_HAS_CUSTOM_CHIME = False
_CUSTOM_SOUND_NAME = "flexdesk_chime"

# One entry per notification `type` (the value the frontend switches on
# in main.dart's tap router) — the single source of truth for which
# channel, icon, and accent color a type uses, and which role normally
# receives it (used by the Settings "Send test notification" picker to
# show owners owner-facing types and members member-facing types).
# `icon` names a small-icon drawable that must exist under
# frontend/android/app/src/main/res/drawable/ — see
# ensureNotificationChannel's sibling icon set.
TYPE_CATALOG = {
    "announcement": {
        "channel": CHANNEL_ANNOUNCEMENTS, "icon": "ic_notif_megaphone",
        "color": _COLOR_PRIMARY, "audience": "member",
        "label": "Announcement",
        "sample_title": "New announcement: Gym closed Sunday",
        "sample_body": "We're closed this Sunday for maintenance.",
    },
    "new_event": {
        "channel": CHANNEL_EVENTS, "icon": "ic_notif_calendar",
        "color": _COLOR_PRIMARY, "audience": "member",
        "label": "New event",
        "sample_title": "New event: Summer Showdown",
        "sample_body": "Oct 12, 2026 · ₱200. Tap to register.",
    },
    "event_registration": {
        "channel": CHANNEL_EVENTS, "icon": "ic_notif_person_add",
        "color": _COLOR_PRIMARY, "audience": "owner",
        "label": "New event registration",
        "sample_title": "New registration",
        "sample_body": "Juan Dela Cruz joined Summer Showdown · 12 registered",
    },
    "comment": {
        "channel": CHANNEL_COMMUNITY, "icon": "ic_notif_chat_bubble",
        "color": _COLOR_PRIMARY, "audience": "owner",
        "label": "New comment",
        "sample_title": "Juan Dela Cruz commented on Gym closed Sunday",
        "sample_body": '"What time do you reopen on Monday?"',
    },
    "checkin": {
        "channel": CHANNEL_CHECKINS, "icon": "ic_notif_check_circle",
        "color": _COLOR_PRIMARY, "audience": "member",
        "label": "Check-in confirmation",
        "sample_title": "Checked in",
        "sample_body": "FlexDesk Gym · 6:45 PM. Have a good session.",
    },
    "renewal": {
        "channel": CHANNEL_MEMBERSHIP, "icon": "ic_notif_clock_alert",
        "color": _COLOR_WARNING, "audience": "member",
        "label": "Renewal reminder",
        "sample_title": "FlexDesk",
        "sample_body": "Your membership at FlexDesk Gym ends today.",
    },
    "trial_ending": {
        "channel": CHANNEL_MEMBERSHIP, "icon": "ic_notif_clock_alert",
        "color": _COLOR_WARNING, "audience": "owner",
        "label": "Trial/subscription ending",
        "sample_title": "FlexDesk",
        "sample_body": "Your free trial ends today. Subscribe to keep FlexDesk running.",
    },
    "out_of_stock": {
        "channel": CHANNEL_STORE, "icon": "ic_notif_package",
        "color": _COLOR_WARNING, "audience": "owner",
        "label": "Out of stock",
        "sample_title": "Out of stock",
        "sample_body": "Whey Protein 1kg is out of stock.",
    },
    "inventory": {
        "channel": CHANNEL_STORE, "icon": "ic_notif_package",
        "color": _COLOR_WARNING, "audience": "owner",
        "label": "Low stock digest",
        "sample_title": "FlexDesk",
        "sample_body": "3 products are running low.",
    },
    "daily_summary": {
        "channel": CHANNEL_DAILY_SUMMARY, "icon": "ic_notif_bar_chart",
        "color": _COLOR_PRIMARY, "audience": "owner",
        "label": "Daily sales summary",
        "sample_title": "Yesterday at FlexDesk Gym",
        "sample_body": "₱4,250 in sales · 18 check-ins · 2 new members",
    },
}


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


def send_to_users(users, title, body, data=None, notif_type=None):
    """
    Pushes `title`/`body` to every device registered to any of `users`.
    Returns (sent_count, pruned_count). Never raises — FCM being down or
    misconfigured must never fail the caller (posting an announcement, a
    sale hitting zero stock, the daily command).

    `notif_type` selects the Android channel/icon/color from
    TYPE_CATALOG and is also used as the notification `tag` — FCM/Android
    replaces a still-showing notification with the same tag from the
    same app rather than stacking a new one, which is what turns five
    quick comments into one tray entry instead of five. Falls back to
    CHANNEL_DEFAULT with no icon/color override if omitted or unknown,
    so a caller that forgets to pass it still sends, just without the
    polish.
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

    catalog_entry = TYPE_CATALOG.get(notif_type, {})
    channel_id = catalog_entry.get("channel", CHANNEL_DEFAULT)
    android_notification_kwargs = {"channel_id": channel_id}
    if catalog_entry.get("icon"):
        android_notification_kwargs["icon"] = catalog_entry["icon"]
    if catalog_entry.get("color"):
        android_notification_kwargs["color"] = catalog_entry["color"]
    if notif_type:
        android_notification_kwargs["tag"] = notif_type
    if _HAS_CUSTOM_CHIME and channel_id not in _NORMAL_IMPORTANCE_CHANNELS:
        android_notification_kwargs["sound"] = _CUSTOM_SOUND_NAME

    sent_count = 0
    dead_tokens = []

    for batch in _chunks(tokens, _TOKENS_PER_BATCH):
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=string_data,
            tokens=batch,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(**android_notification_kwargs),
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
