import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to `/check-ins/`. Auth headers come from the shared Dio
/// interceptor, same as every other authenticated endpoint.
class CheckInsApi {
  CheckInsApi(this._dio);

  final Dio _dio;

  /// Fetches every check-in for [date] (YYYY-MM-DD, gym-local) or today
  /// if omitted, paging through every page the same way fetchAllMembers
  /// does. A quiet gym only ever needs one page — the loop exits
  /// immediately once `next` is null — but a busy gym can pass 50
  /// check-ins in a single day, and stopping at page 1 would silently
  /// drop the rest from the "Checked In Today" list.
  Future<List<Map<String, dynamic>>> fetchCheckIns({String? date}) async {
    var page = 1;
    final all = <Map<String, dynamic>>[];

    try {
      while (true) {
        final response = await _dio.get(
          '/check-ins/',
          queryParameters: {'page': page, if (date != null) 'date': date},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());

        if (body['next'] == null) break;
        page++;

        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message:
                'Check-in list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    return all;
  }

  Future<Map<String, dynamic>> createCheckIn(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/check-ins/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> voidCheckIn(String checkInId) async {
    try {
      await _dio.post('/check-ins/$checkInId/void/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
