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

  Future<AuthUser> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    await _api.changePassword(oldPassword, newPassword);
    final user = await _api.me();
    await _tokenStorage.updateCachedUser(jsonEncode(user.toJson()));
    return user;
  }

  Future<AuthUser?> restoreSession() async {
    final refresh = await _tokenStorage.readRefresh();
    if (refresh == null) return null;

    final cachedJson = await _tokenStorage.readCachedUserJson();
    if (cachedJson != null) {
      try {
        return AuthUser.fromJson(
          jsonDecode(cachedJson) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    return _api.me();
  }

  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}
