import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/device_token_api.dart';
import '../api/dio_client.dart';
import '../theme/colors.dart';

/// Must match the `channel_id` the backend sets on every
/// AndroidNotification (backend/core/notifications.py) and the
/// `com.google.firebase.messaging.default_notification_channel_id`
/// meta-data in AndroidManifest.xml — all three have to agree for a
/// backgrounded/terminated app to show the notification at HIGH
/// importance (sound + heads-up banner) instead of falling back to a
/// silent default channel.
const String pushNotificationChannelId = 'high_importance_channel';
const String _pushNotificationChannelName = 'Important notifications';
const String _pushNotificationChannelDescription =
    'Announcements, renewal reminders, and stock alerts';

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

  /// Attached to MaterialApp.router so a foreground message can show a
  /// banner without any widget needing to hand this service a
  /// BuildContext.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _listening = false;

  /// Creates the Android notification channel every push in this app is
  /// sent on (see [pushNotificationChannelId]), at HIGH importance so
  /// Android shows a heads-up pop-up with sound rather than a silent
  /// tray entry. Must run before any notification using this channel_id
  /// can arrive, so it's called once from main() at app start — a
  /// channel only needs to be created once per app install; recreating
  /// it with the same id is a harmless no-op.
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
              importance: Importance.high,
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
  ///
  /// Never at app launch — see main.dart, which never calls this from
  /// restore().
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

  /// Wires up foreground banners and tap routing. Safe to call more
  /// than once — only the first call attaches listeners.
  ///
  /// Background and terminated notifications are drawn by the OS tray
  /// automatically and need no listener here; this only covers the
  /// foreground case (FCM never shows a tray notification while the
  /// app is open) and routing a tap once the user acts on any of the
  /// three states.
  void initMessageHandling({
    required void Function(Map<String, dynamic> data) onMessageTap,
  }) {
    if (_listening) return;
    _listening = true;

    FirebaseMessaging.onMessage.listen(_showForegroundBanner);

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

  void _showForegroundBanner(RemoteMessage message) {
    final title = message.notification?.title;
    final body = message.notification?.body;
    final text = [
      title,
      body,
    ].where((s) => s != null && s.isNotEmpty).join(' — ');
    if (text.isEmpty) return;

    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: AppColors.fieldBg,
          leading: Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          content: Text(text, style: const TextStyle(color: AppColors.ink)),
          actions: [
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );

    // MaterialBanner doesn't auto-dismiss like SnackBar — hide it after a
    // few seconds so it doesn't sit at the top of the screen forever.
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
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
