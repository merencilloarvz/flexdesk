import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session-validity rule: the refresh token is the sole authority on
/// "am I logged in." On startup, check it first — its absence means
/// unauthenticated regardless of what else is on disk. The cached user
/// JSON is an optimization only, with /auth/me/ as the fallback source
/// of truth.
///
/// Pinned to flutter_secure_storage: 11.0.0 (upstream, not the _x fork).
/// No AndroidOptions override is needed: v10+ deprecated
/// encryptedSharedPreferences because Jetpack Security Crypto was itself
/// deprecated, and the plugin now migrates automatically.
/// resetOnError defaults to true. Re-check this note if the lockfile
/// version changes.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'flexdesk.access';
  static const _refreshKey = 'flexdesk.refresh';
  static const _userKey = 'flexdesk.user';

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  // Writes are sequential, not atomic. An app kill mid-call can leave a
  // partial session on disk — that's why the validity rule above keys
  // off the refresh token specifically, not "all three keys present."
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

  Future<void> updateCachedUser(String userJson) async {
    await _storage.write(key: _userKey, value: userJson);
  }

  // Deletes only the three FlexDesk keys. Never deleteAll() — that would
  // wipe the whole secure-storage namespace for the app, not just our data.
  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessKey),
        _storage.delete(key: _refreshKey),
        _storage.delete(key: _userKey),
      ]);
    } catch (_) {}
  }

  // On failure, deletes only the failed key — so a corrupt access token
  // doesn't destroy a valid refresh token alongside it. Any read failure
  // is treated as logged out and never rethrown, so no exception from
  // here can reach app launch.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
