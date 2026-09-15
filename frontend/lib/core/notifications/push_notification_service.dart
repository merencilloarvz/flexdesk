import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/device_token_api.dart';
import '../api/dio_client.dart';
import '../theme/colors.dart';

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
  }

  void _showForegroundBanner(RemoteMessage message) {
    final title = message.notification?.title;
    final body = message.notification?.body;
    final text = [
      title,
      body,
    ].where((s) => s != null && s.isNotEmpty).join(' — ');
    if (text.isEmpty) return;

    messengerKey.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(text, style: const TextStyle(color: Colors.white)),
      ),
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
