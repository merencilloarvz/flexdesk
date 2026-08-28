import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessKey),
        _storage.delete(key: _refreshKey),
        _storage.delete(key: _userKey),
      ]);
    } catch (_) {}
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await clear();
      return null;
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
