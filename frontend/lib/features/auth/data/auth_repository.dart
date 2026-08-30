import 'dart:convert';
import '../../../core/api/api_exception.dart';
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
    String currentPassword,
    String newPassword,
  ) async {
    await _api.changePassword(currentPassword, newPassword);

    try {
      final user = await _api.me();
      await _tokenStorage.updateCachedUser(jsonEncode(user.toJson()));
      return user;
    } catch (_) {
      final cachedJson = await _tokenStorage.readCachedUserJson();
      if (cachedJson != null) {
        try {
          final cached = AuthUser.fromJson(
            jsonDecode(cachedJson) as Map<String, dynamic>,
          );
          final updated = cached.copyWith(mustChangePassword: false);
          await _tokenStorage.updateCachedUser(jsonEncode(updated.toJson()));
          return updated;
        } catch (_) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message:
                'Password was changed, but the local session could not '
                'be refreshed. Please log in again with your new password.',
          );
        }
      }
      throw ApiException(
        kind: ApiExceptionKind.unknown,
        message:
            'Password was changed, but the local session could not '
            'be refreshed. Please log in again with your new password.',
      );
    }
  }

  Future<AuthUser?> restoreSession() async {
    final refresh = await _tokenStorage.readRefresh();
    if (refresh == null) return null;

    final cachedJson = await _tokenStorage.readCachedUserJson();
    if (cachedJson != null) {
      try {
        final user = AuthUser.fromJson(
          jsonDecode(cachedJson) as Map<String, dynamic>,
        );
        return user;
      } catch (_) {}
    }

    final user = await _api.me();
    await _tokenStorage.updateCachedUser(jsonEncode(user.toJson()));
    return user;
  }

  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}
