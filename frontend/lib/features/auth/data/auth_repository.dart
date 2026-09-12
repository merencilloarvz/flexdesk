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
    return _establishSession(tokens, user, rawUserJson);
  }

  Future<AuthUser> signup({
    required String gymName,
    String? locationName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final (tokens, user, rawUserJson) = await _api.signup(
      gymName: gymName,
      locationName: locationName,
      fullName: fullName,
      email: email,
      password: password,
    );
    return _establishSession(tokens, user, rawUserJson);
  }

  /// Redeems a one-time staff-issued code into a real member login.
  /// Deliberately NOT queueable offline — see AuthApi.claim() for why.
  Future<AuthUser> claim({
    required String email,
    required String claimCode,
    required String password,
  }) async {
    final (tokens, user, rawUserJson) = await _api.claim(
      email: email,
      claimCode: claimCode,
      password: password,
    );
    return _establishSession(tokens, user, rawUserJson);
  }

  /// Shared by login() and claim() — both endpoints return an identical
  /// {access, refresh, user} shape, so both establish a session the same
  /// way. Never duplicate this logic at a call site.
  Future<AuthUser> _establishSession(
    AuthTokens tokens,
    AuthUser user,
    String rawUserJson,
  ) async {
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

  /// Always tries the server first so a returning user's needs_setup,
  /// classes_enabled, and mustChangePassword are current — not whatever
  /// was true the last time this device happened to fetch them. Cached
  /// JSON is the fallback for genuinely offline restore, not the default
  /// path: the previous version returned the cache whenever it existed
  /// and never reached _api.me() at all for a returning user, which is
  /// exactly the staleness bug behind the /setup dead-end and the stuck
  /// classes_enabled/needs_setup flags — the fallback existed but the
  /// primary path it was meant to fall back FROM was never being taken.
  Future<AuthUser?> restoreSession() async {
    final refresh = await _tokenStorage.readRefresh();
    if (refresh == null) return null;

    try {
      final user = await _api.me();
      await _tokenStorage.updateCachedUser(jsonEncode(user.toJson()));
      return user;
    } on ApiException catch (e) {
      // Only a genuine network failure falls back to cache — a real
      // rejection (expired/invalid session) must propagate up so
      // AuthController.restore() marks the session unauthenticated
      // instead of silently trusting stale local data as if it were
      // still a valid session.
      if (e.kind != ApiExceptionKind.network) rethrow;

      final cachedJson = await _tokenStorage.readCachedUserJson();
      if (cachedJson != null) {
        try {
          return AuthUser.fromJson(
            jsonDecode(cachedJson) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
      // No usable cache either — let AuthController.restore() see the
      // network ApiException and land on AuthUnknown(restoreFailed: true)
      // rather than silently returning null (which would read as "no
      // session" instead of "couldn't reach the server").
      rethrow;
    }
  }

  /// Clears the local session immediately, unconditionally. The
  /// server-side logout call is fired alongside it but never awaited —
  /// per spec, logout must never fail or hang because of a dead
  /// connection. If the API call never reaches the server, the refresh
  /// token stays valid there until it naturally expires; that's an
  /// accepted trade for a logout that always works locally, offline or
  /// not. Errors from the fire-and-forget call are deliberately
  /// swallowed — there's no UI left by the time it might complete, and
  /// nothing meaningful to do with the result either way.
  Future<void> logout() async {
    final refresh = await _tokenStorage.readRefresh();
    if (refresh != null) {
      // ignore: unawaited_futures
      _api.logout(refresh).catchError((_) {});
    }
    await _tokenStorage.clear();
  }
}
