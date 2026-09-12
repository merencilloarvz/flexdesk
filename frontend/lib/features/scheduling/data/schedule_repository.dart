import '../../../core/api/api_exception.dart';
import 'schedule_api.dart';

class TimeSlot {
  TimeSlot({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.daysOfWeek,
    required this.isActive,
    this.bookedCount,
    this.coachName = '',
  });

  final String id;
  final String label;
  final String startTime;
  final String endTime;
  final int capacity;
  final String daysOfWeek;
  final bool isActive;
  final int? bookedCount;
  final String coachName;

  Set<int> get days => daysOfWeek.isEmpty
      ? <int>{}
      : daysOfWeek.split(',').map(int.parse).toSet();

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    id: json['id'] as String,
    label: json['label'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    capacity: json['capacity'] as int,
    daysOfWeek: json['days_of_week'] as String,
    isActive: json['is_active'] as bool,
    bookedCount: json['booked_count'] as int?,
    coachName: json['coach_name'] as String? ?? '',
  );
}

class SlotBooking {
  SlotBooking({
    required this.id,
    required this.memberName,
    required this.memberCode,
  });

  final String id;
  final String memberName;
  final String memberCode;

  factory SlotBooking.fromJson(Map<String, dynamic> json) => SlotBooking(
    id: json['id'] as String,
    memberName: json['member_name'] as String,
    memberCode: json['member_code'] as String,
  );
}

class ScheduleSlot {
  ScheduleSlot({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.bookedCount,
    required this.spotsLeft,
    required this.myBookingId,
    this.coachName = '',
  });

  final String id;
  final String label;
  final String startTime;
  final String endTime;
  final int capacity;
  final int bookedCount;
  final int spotsLeft;
  final String? myBookingId;
  final String coachName;

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) => ScheduleSlot(
    id: json['id'] as String,
    label: json['label'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    capacity: json['capacity'] as int,
    bookedCount: json['booked_count'] as int,
    spotsLeft: json['spots_left'] as int,
    myBookingId: json['my_booking_id'] as String?,
    coachName: json['coach_name'] as String? ?? '',
  );
}

class MyBooking {
  MyBooking({
    required this.id,
    required this.timeSlotId,
    required this.timeSlotLabel,
    required this.date,
    required this.canceledAt,
  });

  final String id;
  final String timeSlotId;
  final String timeSlotLabel;
  final DateTime date;
  final DateTime? canceledAt;

  factory MyBooking.fromJson(Map<String, dynamic> json) => MyBooking(
    id: json['id'] as String,
    timeSlotId: json['time_slot'] as String,
    timeSlotLabel: json['time_slot_label'] as String,
    date: DateTime.parse(json['date'] as String),
    canceledAt: json['canceled_at'] != null
        ? DateTime.parse(json['canceled_at'] as String)
        : null,
  );
}

enum BookingActionOutcome { success, rejected, offline }

class BookingActionResult {
  const BookingActionResult({
    required this.outcome,
    this.booking,
    this.message,
  });

  final BookingActionOutcome outcome;
  final MyBooking? booking;
  final String? message;
}

/// Deliberately online-only: no Drift table, no cache, no sync queue.
/// spots_left is contended state, and a cached copy of it is a lie —
/// every read here hits the server fresh.
class ScheduleRepository {
  ScheduleRepository(this._api);

  final ScheduleApi _api;

  // ---- Owner ----

  Future<List<TimeSlot>> fetchTimeSlots({DateTime? date}) async {
    final raw = await _api.fetchTimeSlots(
      date: date != null ? _fmt(date) : null,
    );
    return raw.map(TimeSlot.fromJson).toList();
  }

  Future<TimeSlot> createTimeSlot({
    required String label,
    required String startTime,
    required String endTime,
    required int capacity,
    required String daysOfWeek,
    String coachName = '',
  }) async {
    final json = await _api.createTimeSlot({
      'label': label,
      'start_time': startTime,
      'end_time': endTime,
      'capacity': capacity,
      'days_of_week': daysOfWeek,
      'coach_name': coachName,
    });
    return TimeSlot.fromJson(json);
  }

  /// On the Part A over-subscription rejection, throws an ApiException
  /// with fieldErrors['capacity'] set — the caller shows that on the
  /// capacity field, not as a generic error.
  Future<TimeSlot> updateTimeSlot(
    String id,
    Map<String, dynamic> changes,
  ) async {
    final json = await _api.updateTimeSlot(id, changes);
    return TimeSlot.fromJson(json);
  }

  Future<List<SlotBooking>> fetchSlotBookings(
    String slotId,
    DateTime date,
  ) async {
    final raw = await _api.fetchSlotBookings(slotId, date: _fmt(date));
    return raw.map(SlotBooking.fromJson).toList();
  }

  // ---- Member ----

  Future<List<ScheduleSlot>> fetchSchedule(DateTime date) async {
    final raw = await _api.fetchSchedule(_fmt(date));
    return raw.map(ScheduleSlot.fromJson).toList();
  }

  Future<BookingActionResult> book(String timeSlotId, DateTime date) async {
    try {
      final json = await _api.createBooking(
        timeSlotId: timeSlotId,
        date: _fmt(date),
      );
      return BookingActionResult(
        outcome: BookingActionOutcome.success,
        booking: MyBooking.fromJson(json),
      );
    } on ApiException catch (e) {
      return BookingActionResult(
        outcome: e.kind == ApiExceptionKind.network
            ? BookingActionOutcome.offline
            : BookingActionOutcome.rejected,
        message: _messageFor(e, forBooking: true),
      );
    }
  }

  Future<BookingActionResult> cancel(String bookingId) async {
    try {
      final json = await _api.cancelBooking(bookingId);
      return BookingActionResult(
        outcome: BookingActionOutcome.success,
        booking: MyBooking.fromJson(json),
      );
    } on ApiException catch (e) {
      return BookingActionResult(
        outcome: e.kind == ApiExceptionKind.network
            ? BookingActionOutcome.offline
            : BookingActionOutcome.rejected,
        message: _messageFor(e, forBooking: false),
      );
    }
  }

  Future<({List<MyBooking> bookings, bool hasMore})> fetchMyBookings({
    bool upcoming = false,
    int page = 1,
  }) async {
    final body = await _api.fetchMyBookingsPage(upcoming: upcoming, page: page);
    final results = (body['results'] as List).cast<Map<String, dynamic>>();
    return (
      bookings: results.map(MyBooking.fromJson).toList(),
      hasMore: body['next'] != null,
    );
  }

  /// Maps generic server 400/404 text onto the exact copy the spec's
  /// error table asks for. Coupled to the wording create_booking() and
  /// BookingCancelView use server-side — if that wording changes, this
  /// falls back to showing the raw server message rather than breaking.
  String _messageFor(ApiException e, {required bool forBooking}) {
    if (e.kind == ApiExceptionKind.network) {
      return forBooking
          ? 'You need an internet connection to book.'
          : 'You need an internet connection to cancel a booking.';
    }
    if (e.kind == ApiExceptionKind.notFound) {
      return forBooking
          ? 'That slot is no longer available.'
          : "That booking couldn't be found.";
    }
    final msg = e.message;
    if (msg.contains('fully booked')) {
      return 'This slot just filled up.';
    }
    if (msg.contains('already have a booking')) {
      return "You've already booked this slot.";
    }
    if (msg.contains('active membership')) {
      return '$msg Visit the front desk to renew.';
    }
    return msg;
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
