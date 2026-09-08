import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to the member-facing `/me/` endpoints — /me/summary/,
/// /me/membership/, /me/check-ins/. Auth headers come from the shared
/// Dio interceptor, same as every other authenticated endpoint. Never
/// follows a returned `next` URL — it's absolute and breaks behind a
/// proxy — always requests the next page number explicitly instead.
class MeApi {
  MeApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> fetchSummary() async {
    try {
      final response = await _dio.get('/me/summary/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> fetchMembershipPage(int page) async {
    try {
      final response = await _dio.get(
        '/me/membership/',
        queryParameters: {'page': page},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> fetchCheckInsPage(int page) async {
    try {
      final response = await _dio.get(
        '/me/check-ins/',
        queryParameters: {'page': page},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
