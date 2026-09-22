import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/device_token_api.dart';
import '../api/dio_client.dart';

/// Must match the `channel_id` the backend sets on every
/// AndroidNotification (backend/core/notifications.py) and the
/// `com.google.firebase.messaging.default_notification_channel_id`
/// meta-data in AndroidManifest.xml — all three have to agree for a
/// backgrounded/terminated app to show the notification at HIGH
/// importance (sound + heads-up banner) instead of falling back to a
/// silent default channel. This is also the only place in the app that
/// creates an Android notification channel — a second channel created
/// anywhere else with this same id would silently win or lose depending
/// on creation order, since Android treats a channel's importance as
/// fixed at first creation and ignores later attempts to change it.
const String pushNotificationChannelId = 'high_importance_channel';
const String _pushNotificationChannelName = 'Important notifications';
const String _pushNotificationChannelDescription =
    'Announcements, renewal reminders, and stock alerts';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Local-notification ids just need to not collide with each other
/// within one app session — a monotonic counter is enough, since nothing
/// ever needs to look a shown notification back up by id.
int _notificationIdCounter = 0;

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

  /// Creates the Android notification channel every push in this app is
  /// sent on (see [pushNotificationChannelId]), at the highest importance
  /// so Android shows a heads-up pop-up with sound rather than a silent
  /// tray entry. Must run before any notification using this channel_id
  /// can arrive, so it's called once from main() at app start — a
  /// channel only needs to be created once per app install; recreating
  /// it with the same id is a harmless no-op (and cannot downgrade an
  /// already-created channel's importance even if this ever changed).
  Future<void> ensureNotificationChannel() async {
    try {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              pushNotificationChannelId,
              _pushNotificationChannelName,
              description: _pushNotificationChannelDescription,
              importance: Importance.max,
              playSound: true,
            ),
          );
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
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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

    _localNotifications.show(
      id: _notificationIdCounter++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          pushNotificationChannelId,
          _pushNotificationChannelName,
          channelDescription: _pushNotificationChannelDescription,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
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
