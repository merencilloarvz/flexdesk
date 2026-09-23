import 'dart:convert';
import 'dart:ui' show Color;

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/device_token_api.dart';
import '../api/dio_client.dart';

/// The pre-split fallback channel — kept for the
/// `default_notification_channel_id` meta-data in AndroidManifest.xml
/// (what FCM falls back to for a notification-only message whose
/// `channel_id` this build doesn't recognize) and for any notification
/// `type` missing from [_notificationTypeCatalog]. Every other channel id
/// below must match backend/core/notifications.py's CHANNEL_* constants
/// exactly, and must be created here and only here — Android fixes a
/// channel's importance at first creation and ignores later attempts to
/// change it, so a second creation site for the same id could silently
/// win or lose depending on start-up ordering.
const String pushNotificationChannelId = 'high_importance_channel';

const String channelAnnouncements = 'channel_announcements';
const String channelEvents = 'channel_events';
const String channelMembership = 'channel_membership';
const String channelCheckins = 'channel_checkins';
const String channelStore = 'channel_store';
const String channelCommunity = 'channel_community';
const String channelDailySummary = 'channel_daily_summary';

const Color _colorPrimary = Color(0xFF0F6E56); // AppColors.accentTeal
const Color _colorWarning = Color(0xFF92600B); // AppColors.expiringBg

// frontend/android/app/src/main/res/raw/flexdesk_chime.mp3 doesn't exist
// yet — flip to true once it's added. Only applied to high-importance
// channels; check-ins and the daily summary always use the system
// default sound regardless of this flag.
const bool _hasCustomChime = false;
const String _customChimeResource = 'flexdesk_chime';

class _ChannelSpec {
  const _ChannelSpec(this.id, this.name, this.description, this.importance);
  final String id;
  final String name;
  final String description;
  final Importance importance;
}

/// One entry per Android channel, each mutable independently from the
/// phone's own notification settings (Settings app, per app, per
/// channel) — this is what lets someone mute "Check-ins" without losing
/// "Announcements". Check-ins and the daily summary are normal
/// importance (sound, no heads-up pop-up); everything else is high
/// importance.
const List<_ChannelSpec> _channelSpecs = [
  _ChannelSpec(channelAnnouncements, 'Announcements',
      'New announcements from your gym', Importance.max),
  _ChannelSpec(channelEvents, 'Events',
      'New events and registration activity', Importance.max),
  _ChannelSpec(channelMembership, 'Membership',
      'Renewal reminders and subscription alerts', Importance.max),
  _ChannelSpec(channelCheckins, 'Check-ins',
      'Confirmation when you check in', Importance.defaultImportance),
  _ChannelSpec(channelStore, 'Store alerts',
      'Out-of-stock and low-stock alerts', Importance.max),
  _ChannelSpec(channelCommunity, 'Community',
      'Comments on announcements and events', Importance.max),
  _ChannelSpec(channelDailySummary, 'Daily summary',
      "Yesterday's sales, check-ins, and new members", Importance.defaultImportance),
  _ChannelSpec(pushNotificationChannelId, 'Important notifications',
      'Fallback channel for anything not covered above', Importance.max),
];

class _TypeSpec {
  const _TypeSpec(this.channelId, this.icon, this.color);
  final String channelId;
  final String icon;
  final Color color;
}

/// Mirrors backend/core/notifications.py's TYPE_CATALOG — which channel,
/// small icon, and accent color each notification `type` uses. Icon
/// names must match a vector drawable under
/// frontend/android/app/src/main/res/drawable/.
final Map<String, _TypeSpec> _notificationTypeCatalog = {
  'announcement': const _TypeSpec(channelAnnouncements, 'ic_notif_megaphone', _colorPrimary),
  'new_event': const _TypeSpec(channelEvents, 'ic_notif_calendar', _colorPrimary),
  'event_registration': const _TypeSpec(channelEvents, 'ic_notif_person_add', _colorPrimary),
  'comment': const _TypeSpec(channelCommunity, 'ic_notif_chat_bubble', _colorPrimary),
  'checkin': const _TypeSpec(channelCheckins, 'ic_notif_check_circle', _colorPrimary),
  'renewal': const _TypeSpec(channelMembership, 'ic_notif_clock_alert', _colorWarning),
  'trial_ending': const _TypeSpec(channelMembership, 'ic_notif_clock_alert', _colorWarning),
  'out_of_stock': const _TypeSpec(channelStore, 'ic_notif_package', _colorWarning),
  'inventory': const _TypeSpec(channelStore, 'ic_notif_package', _colorWarning),
  'daily_summary': const _TypeSpec(channelDailySummary, 'ic_notif_bar_chart', _colorPrimary),
};

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Must be a top-level (or static) function, not a method — Android
/// runs it in its own background isolate, separate from main()'s, when
/// FCM delivers a message while the app is backgrounded or terminated.
/// Registering it is what tells the platform channel to keep delivering
/// messages to the app in that state instead of dropping them.
///
/// The tray banner itself is drawn by Android automatically because
/// every message carries a `notification` block (see
/// backend/core/notifications.py) — this handler doesn't need to show
/// anything itself. It exists as the required registration point, and
/// as the place any future background data-processing would go.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

Map<String, dynamic>? _decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(payload) as Map);
  } catch (_) {
    return null;
  }
}

/// Phase 4 Part B — device token lifecycle, permission timing, and
/// message handling. See FLEXDESK_PHASE4_PART_B_SPEC.md.
///
/// Every public method here follows the same rule as the backend's
/// core/notifications.py: never raise into the caller. A person must
/// always be able to log in, claim an account, or log out even if push
/// notifications never get set up.
class PushNotificationService {
  PushNotificationService(this._deviceTokenApi);

  final DeviceTokenApi _deviceTokenApi;

  static const _askedPrefsPrefix = 'push_permission_asked_';

  bool _listening = false;

  /// Creates every Android notification channel in [_channelSpecs] — must
  /// run before any notification using one of these channel_ids can
  /// arrive, so it's called once from main() at app start. A channel
  /// only needs to be created once per app install; recreating it with
  /// the same id is a harmless no-op (and cannot downgrade an
  /// already-created channel's importance even if this ever changed).
  Future<void> ensureNotificationChannel() async {
    try {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notif_default'),
        ),
      );
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final spec in _channelSpecs) {
        final useCustomSound =
            _hasCustomChime && spec.importance == Importance.max;
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            spec.id,
            spec.name,
            description: spec.description,
            importance: spec.importance,
            playSound: true,
            sound: useCustomSound
                ? const RawResourceAndroidNotificationSound(_customChimeResource)
                : null,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Notification channel setup failed: $e');
    }
  }

  /// Registers this device's current FCM token — called on login, on
  /// claim, and on every app start while already authenticated (tokens
  /// can silently change between sessions). Idempotent server-side.
  Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _deviceTokenApi.register(token: token, platform: 'android');
    } catch (e) {
      if (kDebugMode) debugPrint('Push token registration failed: $e');
    }
  }

  /// Must be awaited by the caller and must complete BEFORE the stored
  /// auth tokens are cleared — a token deleted after logout has already
  /// invalidated the session would fail unauthenticated and leave the
  /// row behind for the next person on a shared device. See
  /// AuthController.logout().
  Future<void> deleteToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _deviceTokenApi.delete(token);
    } catch (e) {
      if (kDebugMode) debugPrint('Push token deletion failed: $e');
    }
  }

  /// Requests the notification permission at most once per user,
  /// ever, on this device. Called unconditionally right after a
  /// member's claim() succeeds, and after every login() — the
  /// SharedPreferences flag is what turns the second call site into
  /// "only on this user's first login": a member who already got asked
  /// at claim time is never asked again by login(), and staff get
  /// asked exactly once, on their first login.
  Future<void> requestPermissionOnce(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_askedPrefsPrefix$userId';
      if (prefs.getBool(key) == true) return;

      await FirebaseMessaging.instance.requestPermission();
      await prefs.setBool(key, true);
    } catch (e) {
      if (kDebugMode) debugPrint('Push permission request failed: $e');
    }
  }

  /// Checks the OS permission state directly (unlike
  /// [requestPermissionOnce], which only tracks "have we ever asked" and
  /// so never re-prompts someone who was already logged in before that
  /// flag existed, or who denied it and later wants back in from
  /// Settings). Called on every app start while authenticated — a no-op
  /// if the OS already shows notifications as authorized.
  Future<void> requestPermissionIfNotGranted() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        return;
      }
      await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      if (kDebugMode) debugPrint('Push permission check failed: $e');
    }
  }

  /// Read by the Settings screens to show an on/off status.
  Future<bool> notificationsEnabled() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      if (kDebugMode) debugPrint('Push permission read failed: $e');
      return false;
    }
  }

  /// Opens this app's page in the Android system notification settings —
  /// the only way back in once someone has denied the permission, since
  /// requestPermission() can't re-show the OS dialog after that.
  Future<void> openSystemNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (e) {
      if (kDebugMode) debugPrint('Opening notification settings failed: $e');
    }
  }

  /// Wires up tray notifications for the foreground case and tap routing
  /// for all three (foreground, background, terminated). Safe to call
  /// more than once — only the first call attaches listeners.
  void initMessageHandling({
    required void Function(Map<String, dynamic> data) onMessageTap,
  }) {
    if (_listening) return;
    _listening = true;

    _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notif_default'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final data = _decodeNotificationPayload(response.payload);
        if (data != null) onMessageTap(data);
      },
    );

    // Cold start via tapping a local notification this app drew itself
    // — only reachable if the app is killed after a foreground push was
    // shown but before it was tapped. Mirrors FCM's own
    // getInitialMessage() below, which covers the far more common case
    // of tapping an OS-drawn notification for a background/terminated
    // message.
    _localNotifications.getNotificationAppLaunchDetails().then((details) {
      if (details?.didNotificationLaunchApp != true) return;
      final data = _decodeNotificationPayload(
        details?.notificationResponse?.payload,
      );
      if (data != null) onMessageTap(data);
    });

    // FCM never draws a tray notification itself while the app is
    // foregrounded — this is what makes a foreground push behave the
    // same as backgrounded/terminated ones (sound, heads-up banner, tray
    // entry) instead of only showing an in-app widget.
    FirebaseMessaging.onMessage.listen(_showTrayNotification);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onMessageTap(message.data);
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) onMessageTap(message.data);
    });

    // FCM can rotate a device's token at any time, not just between
    // sessions (app restore already re-registers on every launch — see
    // AuthController.restore()). Without this, a token rotated mid-session
    // goes stale on the backend until the next login.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _deviceTokenApi
          .register(token: token, platform: 'android')
          .catchError((e) {
            if (kDebugMode) debugPrint('Push token refresh failed: $e');
          });
    });
  }

  void _showTrayNotification(RemoteMessage message) {
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title == null && body == null) return;

    final type = message.data['type'] as String?;
    final typeSpec = _notificationTypeCatalog[type];
    final channelSpec = _channelSpecs.firstWhere(
      (c) => c.id == (typeSpec?.channelId ?? pushNotificationChannelId),
      orElse: () => _channelSpecs.last,
    );

    // A stable id per type — not a counter — is what makes several
    // notifications of the same type collapse into one tray entry
    // instead of piling up as separate ones (matching the `tag` FCM
    // sends for the same case when the app is backgrounded/terminated):
    // showing a second notification with the same id replaces the
    // first rather than adding a new one.
    final id = (type ?? 'unknown').hashCode & 0x7fffffff;

    _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelSpec.id,
          channelSpec.name,
          channelDescription: channelSpec.description,
          importance: channelSpec.importance,
          priority: channelSpec.importance == Importance.max
              ? Priority.max
              : Priority.defaultPriority,
          playSound: true,
          tag: type,
          icon: typeSpec?.icon,
          color: typeSpec?.color,
          // Mirrors what Android's own FCM notification builder applies
          // automatically to an OS-drawn notification's body — without
          // this, a locally-drawn one would truncate at one line while
          // an OS-drawn one expands, instead of looking identical.
          styleInformation: BigTextStyleInformation(
            body ?? '',
            contentTitle: title,
          ),
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}

final deviceTokenApiProvider = Provider<DeviceTokenApi>((ref) {
  return DeviceTokenApi(ref.watch(dioProvider));
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationService(ref.watch(deviceTokenApiProvider));
});

/// Read by the Settings screens' "Notifications" row. autoDispose so
/// coming back to Settings (e.g. after visiting the system notification
/// settings screen to flip the permission) re-checks the real OS state
/// instead of showing a stale cached value.
final notificationsEnabledProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(pushNotificationServiceProvider).notificationsEnabled();
});
