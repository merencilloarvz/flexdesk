import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to the scheduling endpoints. Deliberately no local caching layer
/// underneath this — see the repository for why (spots_left is contended
/// state; a cached copy of it is a lie).
class ScheduleApi {
  ScheduleApi(this._dio);

  final Dio _dio;

  // ---- Owner: time slots ----

  /// Pages through every slot, same reasoning as CheckInsApi.fetchCheckIns
  /// — a quiet gym only has one page, but stopping at page 1 would
  /// silently drop slots for a gym that has more.
  Future<List<Map<String, dynamic>>> fetchTimeSlots({String? date}) async {
    var page = 1;
    final all = <Map<String, dynamic>>[];
    try {
      while (true) {
        final response = await _dio.get(
          '/time-slots/',
          queryParameters: {'page': page, if (date != null) 'date': date},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());
        if (body['next'] == null) break;
        page++;
        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message: 'Slot list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
    return all;
  }

  Future<Map<String, dynamic>> createTimeSlot(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/time-slots/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> updateTimeSlot(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.patch('/time-slots/$id/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchSlotBookings(
    String slotId, {
    String? date,
  }) async {
    try {
      final response = await _dio.get(
        '/time-slots/$slotId/bookings/',
        queryParameters: {if (date != null) 'date': date},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  // ---- Member: schedule & bookings ----

  Future<List<Map<String, dynamic>>> fetchSchedule(String date) async {
    try {
      final response = await _dio.get(
        '/schedule/',
        queryParameters: {'date': date},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> createBooking({
    required String timeSlotId,
    required String date,
  }) async {
    try {
      final response = await _dio.post(
        '/bookings/',
        data: {'time_slot': timeSlotId, 'date': date},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> cancelBooking(String bookingId) async {
    try {
      final response = await _dio.post('/bookings/$bookingId/cancel/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> fetchMyBookingsPage({
    bool upcoming = false,
    int page = 1,
  }) async {
    try {
      final response = await _dio.get(
        '/me/bookings/',
        queryParameters: {if (upcoming) 'upcoming': '1', 'page': page},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
