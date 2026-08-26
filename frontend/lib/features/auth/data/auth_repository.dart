import 'dart:convert';
import '../../../core/api/token_storage.dart';
import 'auth_api.dart';
import 'auth_models.dart';

class AuthRepository {
  final AuthApi _api;
  final TokenStorage _tokenStorage;

  AuthRepository(this._api, this._tokenStorage);

  Future<AuthUser> login(String email, String password) async {
    final (tokens, user, rawUserJson) = await _api.login(email, password);
    await _tokenStorage.saveSession(
      access: tokens.access,
      refresh: tokens.refresh,
      userJson: rawUserJson,
    );
    return user;
  }

  /// Session-validity rule: the refresh token is the sole authority on
  /// "am I logged in." Its absence means unauthenticated, full stop —
  /// regardless of what else might still be cached.
  Future<AuthUser?> restoreSession() async {
    final refresh = await _tokenStorage.readRefresh();
    if (refresh == null) return null;

    final cachedJson = await _tokenStorage.readCachedUserJson();
    if (cachedJson != null) {
      try {
        return AuthUser.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);
      } catch (_) {
        // Cache present but unparseable (stale shape, corruption) —
        // fall through to a live fetch rather than treating this as
        // logged-out. The refresh token is still valid; only the
        // cache is bad.
      }
    }

    return _api.me();
  }

  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}