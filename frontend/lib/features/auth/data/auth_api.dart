import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/api/api_exception.dart';
import 'package:flexdesk/features/auth/data/auth_models.dart';

class AuthApi {
  final Dio _dio;
  AuthApi(this._dio);

  Future<(AuthTokens, AuthUser, String)> login(
    String email,
    String password,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/login/',
        data: {'email': email, 'password': password},
      );
      final data = response.data as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;

      return (
        AuthTokens.fromJson(data),
        AuthUser.fromJson(userJson),
        jsonEncode(userJson),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<(AuthTokens, AuthUser, String)> signup({
    required String gymName,
    String? locationName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/signup/',
        data: {
          'gym_name': gymName,
          if (locationName != null) 'location_name': locationName,
          'full_name': fullName,
          'email': email,
          'password': password,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;

      return (
        AuthTokens.fromJson(data),
        AuthUser.fromJson(userJson),
        jsonEncode(userJson),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Redeems a staff-issued one-time code. Response shape is
  /// byte-identical to login()'s — {access, refresh, user}. Deliberately
  /// has no offline/retry handling: this creates a server-side account,
  /// and there's nothing sensible to do with a queued claim. Let a
  /// network failure surface as ApiExceptionKind.network and have the
  /// claim screen show its own message for that case.
  Future<(AuthTokens, AuthUser, String)> claim({
    required String email,
    required String claimCode,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/claim/',
        data: {'email': email, 'claim_code': claimCode, 'password': password},
      );
      final data = response.data as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;

      return (
        AuthTokens.fromJson(data),
        AuthUser.fromJson(userJson),
        jsonEncode(userJson),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AuthUser> me() async {
    try {
      final response = await _dio.get('/auth/me/');
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Owner-only toggle for gym-level settings. Currently just
  /// classes_enabled, but shaped to take more owner-set gym flags later
  /// without a new endpoint. Returns the full updated AuthUser (same
  /// shape as login/signup/me) so the caller can push it straight into
  /// session state.
  Future<AuthUser> updateGymSettings({bool? classesEnabled}) async {
    try {
      final response = await _dio.patch(
        '/gym/settings/',
        data: {if (classesEnabled != null) 'classes_enabled': classesEnabled},
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      await _dio.post(
        '/auth/change-password/',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Fire-and-forget from the caller's perspective — see
  /// AuthRepository.logout() for why this is never awaited there.
  /// Failures here are swallowed by the caller, not here, so this stays
  /// a plain pass-through rather than adding its own try/catch.
  Future<void> logout(String refresh) async {
    await _dio.post('/auth/logout/', data: {'refresh': refresh});
  }
}
