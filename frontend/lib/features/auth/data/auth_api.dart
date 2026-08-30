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
        jsonEncode(userJson), // raw JSON — what saveSession actually caches
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
}
