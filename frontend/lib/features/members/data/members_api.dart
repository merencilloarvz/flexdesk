import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to `/members/`. Auth headers come from the shared Dio interceptor,
/// same as every other authenticated endpoint.
class MembersApi {
  MembersApi(this._dio);

  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchAllMembers() async {
    var page = 1;
    final all = <Map<String, dynamic>>[];

    try {
      while (true) {
        final response = await _dio.get(
          '/members/',
          queryParameters: {'page': page},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());

        if (body['next'] == null) break;
        page++;

        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message:
                'Member list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    return all;
  }

  Future<List<Map<String, dynamic>>> fetchMemberHistory(String memberId) async {
    try {
      final response = await _dio.get('/members/$memberId/memberships/');
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> archiveMember(String memberId) async {
    try {
      await _dio.post('/members/$memberId/archive/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Renews [memberId] onto [planId]. `POST /members/{id}/renew/` creates a
  /// fresh Membership row starting the day after the current one ends (or
  /// today, if there's no current one) — see `Membership.renew` on the
  /// backend. Returns the new Membership (MembershipSerializer shape), but
  /// callers should refresh the member afterward rather than parse this
  /// directly, same reasoning as member create: this response describes
  /// the Membership, not the Member's derived fields.
  Future<Map<String, dynamic>> renewMember(
    String memberId,
    String planId,
  ) async {
    try {
      final response = await _dio.post(
        '/members/$memberId/renew/',
        data: {'plan_id': planId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> createMember(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/members/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
