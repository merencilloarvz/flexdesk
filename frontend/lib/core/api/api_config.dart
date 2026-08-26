import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Central place for API base URL + timeout configuration.
///
/// Deliberately does NOT import `dart:io` — `Platform.isAndroid` throws on
/// web, and Chrome is the primary dev target for this project. Use
/// `defaultTargetPlatform` / `kIsWeb` from `flutter/foundation.dart` instead.
class ApiConfig {
  ApiConfig._();

  /// Optional compile-time override, e.g. for a physical tablet on the LAN:
  ///
  ///   flutter run --dart-define=FLEXDESK_API_BASE_URL=http://192.168.1.x:8000/api/v1
  ///
  /// A non-empty override always wins over the platform-based resolution
  /// below. Normalized in [baseUrl] — don't read this raw value directly,
  /// since a trailing slash here (easy to paste in by accident on the
  /// physical-tablet path, where it's hardest to debug) would otherwise
  /// produce double slashes like `//auth/login/`.
  static const String _override = String.fromEnvironment(
    'FLEXDESK_API_BASE_URL',
  );

  /// Resolves the API base URL:
  /// - Non-empty `FLEXDESK_API_BASE_URL` override -> used as-is, trailing
  ///   slashes stripped.
  /// - Web -> 127.0.0.1 (runserver on the same machine as Chrome).
  /// - Android -> 10.0.2.2 (emulator's alias for the host loopback).
  /// - Everything else (iOS sim, desktop) -> 127.0.0.1.
  ///
  /// No trailing slash.
  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _override.replaceAll(RegExp(r'/+$'), '');
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000/api/v1';
      default:
        return 'http://127.0.0.1:8000/api/v1';
    }
  }

  /// Fail fast: offline-first means a hung request is worse than a quick
  /// error the sync layer can react to.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);
}
