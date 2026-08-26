import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper over [FlutterSecureStorage] for the JWT session.
///
/// Pinned to `flutter_secure_storage: 11.0.0` (see pubspec.lock — confirmed
/// this is the upstream package, not the `_x` community fork). As of v10+,
/// `AndroidOptions(encryptedSharedPreferences: true)` is deprecated — the
/// Jetpack Security Crypto library it depended on was itself deprecated, so
/// the plugin now uses its own cipher implementation by default and
/// migrates any old EncryptedSharedPreferences data automatically
/// (`migrateOnAlgorithmChange`, on by default). So: no `AndroidOptions`
/// override needed here — the defaults already do the right thing.
/// `resetOnError` also now defaults to `true` — the plugin already wipes
/// its own storage on an unrecoverable decrypt failure. Re-check this note
/// if the version in pubspec.lock changes.
///
/// On web this is a `localStorage` wrapper backed by WebCrypto — not real
/// secure storage. That's fine for dev; irrelevant for the Play Store
/// target, where the app runs on Android.
///
/// **Session-validity rule (governs the 3.3 auth controller too):** the
/// refresh token is the sole authority on "am I logged in." On startup,
/// read `readRefresh()` first — if it's absent, treat the user as
/// unauthenticated regardless of what else is present. `readCachedUserJson`
/// is an optimization only; if it's missing or stale, fall back to
/// `/auth/me/` rather than treating its absence as logged-out.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'flexdesk.access';
  static const _refreshKey = 'flexdesk.refresh';
  static const _userKey = 'flexdesk.user';

  /// Persists a refreshed access token and its (possibly rotated)
  /// refresh token. Used by AuthInterceptor after a successful
  /// /auth/refresh/ call.
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  /// Persists a full session: access + refresh tokens and the raw user JSON
  /// string (not a serialized model — this goes straight into
  /// `AuthUser.fromJson(jsonDecode(...))` later and survives model changes).
  ///
  /// Writes are sequential, not atomic — an app kill mid-call can leave a
  /// partial session on disk. That's why the session-validity rule above
  /// keys off the refresh token specifically: it's written second, so an
  /// access-without-refresh partial state is already treated as logged-out
  /// by any caller that follows the rule.
  Future<void> saveSession({
    required String access,
    required String refresh,
    required String userJson,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    await _storage.write(key: _userKey, value: userJson);
  }

  Future<String?> readAccess() => _safeRead(_accessKey);

  Future<String?> readRefresh() => _safeRead(_refreshKey);

  Future<String?> readCachedUserJson() => _safeRead(_userKey);

  /// Deletes only the FlexDesk session keys — never `deleteAll()`, which
  /// would wipe the entire secure-storage namespace for the app, including
  /// anything unrelated added here later.
  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessKey),
        _storage.delete(key: _refreshKey),
        _storage.delete(key: _userKey),
      ]);
    } catch (_) {
      // Best-effort — if even delete fails, there's nothing further to do;
      // treating the session as logged out (via the null reads above) is
      // the safe fallback.
    }
  }

  /// Every read goes through here. Decrypt failures — most commonly after
  /// a reinstall or a backup restore onto a device that can't decrypt the
  /// old keystore entry — are already reset by the plugin's own
  /// `resetOnError: true` default, but this catch guarantees no exception
  /// ever reaches app launch even so. Any read failure clears the session
  /// and is treated as logged out, never rethrown.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await clear();
      return null;
    }
  }
}

/// Co-located here rather than in a core-level providers file that doesn't
/// exist yet in the tree — Riverpod convention allows this and it keeps the
/// file count honest.
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
