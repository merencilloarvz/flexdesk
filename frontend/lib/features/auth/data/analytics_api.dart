import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to /analytics/. Same shared-Dio-interceptor pattern as
/// CheckInsApi/PlansApi. Single GET, no pagination — the endpoint
/// returns one aggregated snapshot per range, not a list.
class AnalyticsApi {
  AnalyticsApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> fetchAnalytics(String range) async {
    try {
      final response = await _dio.get(
        '/analytics/',
        queryParameters: {'range': range},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
