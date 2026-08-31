import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to `/staff/`. Owner-only on the backend — every call here 403s
/// if the logged-in user isn't an owner. Auth headers come from the
/// shared Dio interceptor, same as every other authenticated endpoint.
class StaffApi {
  StaffApi(this._dio);

  final Dio _dio;

  /// GET /staff/ — paginated, same envelope shape as members.
  /// Realistically this is always one page (owners don't have hundreds
  /// of staff), but we still walk the `next` link properly because the
  /// envelope parsing is required regardless.
  Future<List<Map<String, dynamic>>> fetchAllStaff() async {
    var page = 1;
    final all = <Map<String, dynamic>>[];

    try {
      while (true) {
        final response = await _dio.get(
          '/staff/',
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
                'Staff list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    return all;
  }

  /// POST /staff/ — creates a staffer with a temporary password.
  ///
  /// Unlike member create, the 201 response body here IS the read shape
  /// (StaffMemberSerializer), because StaffViewSet.create() explicitly
  /// re-serializes it that way. So we can parse this response directly —
  /// no need to re-fetch afterward.
  Future<Map<String, dynamic>> createStaff(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/staff/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// PATCH /staff/{id}/ — note: {id} is the StaffProfile id, not the
  /// User id. No PUT exists on this endpoint (backend only allows
  /// get, post, patch).
  Future<Map<String, dynamic>> updateStaff(
    String staffProfileId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.patch('/staff/$staffProfileId/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /staff/{id}/deactivate/ — returns 204 with no body. If the
  /// caller tries to deactivate their own account, the backend responds
  /// with a 400 and a `detail` message ("You cannot deactivate your own
  /// account.") — that comes back as an ApiException the UI can show,
  /// but the list screen should hide the button on your own row anyway
  /// so this is a backstop, not the primary guard.
  Future<void> deactivateStaff(String staffProfileId) async {
    try {
      await _dio.post('/staff/$staffProfileId/deactivate/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
