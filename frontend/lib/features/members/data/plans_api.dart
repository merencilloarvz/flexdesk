import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to `/plans/`. Auth headers come from the shared Dio interceptor,
/// same as every other authenticated endpoint.
class PlansApi {
  PlansApi(this._dio);

  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchAllPlans() async {
    var page = 1;
    final all = <Map<String, dynamic>>[];

    try {
      while (true) {
        final response = await _dio.get(
          '/plans/',
          queryParameters: {'page': page},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());

        if (body['next'] == null) break;
        page++;

        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message: 'Plan list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    return all;
  }

  /// Creates a plan. `id` is not sent — MembershipPlanSerializer's `id` is
  /// the model's primary key, which DRF treats as read-only by default, so
  /// the server generates it and returns it in the response. Unlike
  /// members, there's no client-side UUID/idempotency guard here — this
  /// screen is expected to be used online, by an owner, not at a busy
  /// front desk on flaky wifi, so that complexity isn't built in for v1.
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/plans/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Partial update — only the fields present in [body] are changed.
  Future<Map<String, dynamic>> updatePlan(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.patch('/plans/$id/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Genuine delete — `MembershipPlanViewSet` is a plain ModelViewSet with
  /// no destroy() override, unlike members (which block DELETE entirely).
  Future<void> deletePlan(String id) async {
    try {
      await _dio.delete('/plans/$id/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
