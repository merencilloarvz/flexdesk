import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

class CommunityApi {
  CommunityApi(this._dio);

  final Dio _dio;

  Future<List<Map<String, dynamic>>> _fetchAllPages(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    var page = 1;
    final all = <Map<String, dynamic>>[];
    try {
      while (true) {
        final response = await _dio.get(
          path,
          queryParameters: {'page': page, ...?query},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());
        if (body['next'] == null) break;
        page++;
        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message: 'List is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
    return all;
  }

  // ---- Announcements ----

  Future<List<Map<String, dynamic>>> fetchAnnouncements() =>
      _fetchAllPages('/announcements/');

  Future<Map<String, dynamic>> createAnnouncement(
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await _dio.post('/announcements/', data: body);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> updateAnnouncement(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await _dio.patch('/announcements/$id/', data: body);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    try {
      await _dio.delete('/announcements/$id/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  // ---- Events ----

  Future<List<Map<String, dynamic>>> fetchEvents() =>
      _fetchAllPages('/events/');

  Future<Map<String, dynamic>> fetchEvent(String id) async {
    try {
      final r = await _dio.get('/events/$id/');
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async {
    try {
      final r = await _dio.post('/events/', data: body);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> updateEvent(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await _dio.patch('/events/$id/', data: body);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> register(String eventId) async {
    try {
      final r = await _dio.post('/events/$eventId/register/');
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> unregister(String eventId) async {
    try {
      final r = await _dio.post('/events/$eventId/unregister/');
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchResults(String eventId) async {
    try {
      final r = await _dio.get('/events/$eventId/results/');
      return (r.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Map<String, dynamic>>> submitResults(
    String eventId,
    List<Map<String, dynamic>> entries,
  ) async {
    try {
      final r = await _dio.post('/events/$eventId/results/', data: entries);
      return (r.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchRegistrants(String eventId) =>
      _fetchAllPages('/event-registrations/', query: {'event': eventId});

  Future<Map<String, dynamic>> markPaid(String registrationId) async {
    try {
      final r = await _dio.post(
        '/event-registrations/$registrationId/mark-paid/',
      );
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> markUnpaid(String registrationId) async {
    try {
      final r = await _dio.post(
        '/event-registrations/$registrationId/mark-unpaid/',
      );
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
