import '../../../core/api/api_exception.dart';
import 'community_api.dart';

/// Parses a server decimal-string amount (e.g. "200.00") into integer
/// centavos without ever going through a double — the whole point of
/// snapshotting amount_due server-side is defeated if the client then
/// rounds it through floating point on the way back in.
int decimalPesosToCentavos(String s) {
  final negative = s.startsWith('-');
  final clean = negative ? s.substring(1) : s;
  final parts = clean.split('.');
  final pesos = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  final fraction = parts.length > 1 ? parts[1] : '';
  final centavosStr = '${fraction}00'.substring(0, 2);
  final centavos = pesos * 100 + int.parse(centavosStr);
  return negative ? -centavos : centavos;
}

/// Whole-peso integer -> the decimal string the server expects.
String pesosToDecimalString(int pesos) => '$pesos.00';

class Announcement {
  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.isPinned,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final bool isPinned;
  final DateTime createdAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    isPinned: json['is_pinned'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

class MyEventRegistration {
  MyEventRegistration({
    required this.id,
    required this.paymentStatus,
    required this.amountDueCentavos,
  });

  final String id;
  final String paymentStatus; // 'unpaid' | 'paid'
  final int amountDueCentavos;

  factory MyEventRegistration.fromJson(Map<String, dynamic> json) =>
      MyEventRegistration(
        id: json['id'] as String,
        paymentStatus: json['payment_status'] as String,
        amountDueCentavos: decimalPesosToCentavos(json['amount_due'] as String),
      );
}

class Event {
  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.startTime,
    required this.locationText,
    required this.feeCentavos,
    required this.prizeDescription,
    required this.capacity,
    required this.registrationClosesOn,
    required this.canceledAt,
    required this.registrationCount,
    required this.spotsLeft,
    required this.myRegistration,
  });

  final String id;
  final String title;
  final String description;
  final DateTime eventDate;
  final String? startTime; // "HH:MM:SS" or null
  final String locationText;
  final int feeCentavos;
  final String prizeDescription;
  final int? capacity;
  final DateTime? registrationClosesOn;
  final DateTime? canceledAt;
  final int registrationCount;
  final int? spotsLeft;
  final MyEventRegistration? myRegistration;

  bool get isCanceled => canceledAt != null;

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    eventDate: DateTime.parse(json['event_date'] as String),
    startTime: json['start_time'] as String?,
    locationText: json['location_text'] as String? ?? '',
    feeCentavos: decimalPesosToCentavos(json['registration_fee'] as String),
    prizeDescription: json['prize_description'] as String? ?? '',
    capacity: json['capacity'] as int?,
    registrationClosesOn: json['registration_closes_on'] != null
        ? DateTime.parse(json['registration_closes_on'] as String)
        : null,
    canceledAt: json['canceled_at'] != null
        ? DateTime.parse(json['canceled_at'] as String)
        : null,
    registrationCount: json['registration_count'] as int? ?? 0,
    spotsLeft: json['spots_left'] as int?,
    myRegistration: json['my_registration'] != null
        ? MyEventRegistration.fromJson(
            json['my_registration'] as Map<String, dynamic>,
          )
        : null,
  );
}

class Registrant {
  Registrant({
    required this.id,
    required this.memberName,
    required this.memberCode,
    required this.paymentStatus,
    required this.amountDueCentavos,
  });

  final String id;
  final String memberName;
  final String memberCode;
  final String paymentStatus;
  final int amountDueCentavos;

  factory Registrant.fromJson(Map<String, dynamic> json) => Registrant(
    id: json['id'] as String,
    memberName: json['member_name'] as String,
    memberCode: json['member_code'] as String,
    paymentStatus: json['payment_status'] as String,
    amountDueCentavos: decimalPesosToCentavos(json['amount_due'] as String),
  );
}

class EventResultRow {
  EventResultRow({
    this.memberId,
    required this.displayName,
    required this.rank,
    this.scoreText = '',
    this.note = '',
  });

  final String? memberId;
  final String displayName;
  final int rank;
  final String scoreText;
  final String note;

  factory EventResultRow.fromJson(Map<String, dynamic> json) => EventResultRow(
    memberId: json['member'] as String?,
    displayName: json['display_name'] as String,
    rank: json['rank'] as int,
    scoreText: json['score_text'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    if (memberId != null) 'member': memberId,
    'display_name': displayName,
    'rank': rank,
    'score_text': scoreText,
    'note': note,
  };
}

enum EventActionOutcome { success, rejected, offline }

class EventActionResult {
  const EventActionResult({
    required this.outcome,
    this.message,
    this.registration,
  });

  final EventActionOutcome outcome;
  final String? message;
  final MyEventRegistration? registration;
}

/// Deliberately online-only, same reasoning as ScheduleRepository:
/// registration counts and payment status are contended/shared state,
/// and a cached copy is worse than none.
class CommunityRepository {
  CommunityRepository(this._api);
  final CommunityApi _api;

  // ---- Announcements ----

  Future<List<Announcement>> fetchAnnouncements() async {
    final raw = await _api.fetchAnnouncements();
    return raw.map(Announcement.fromJson).toList();
  }

  Future<Announcement> createAnnouncement({
    required String title,
    required String body,
    required bool isPinned,
  }) async {
    final json = await _api.createAnnouncement({
      'title': title,
      'body': body,
      'is_pinned': isPinned,
    });
    return Announcement.fromJson(json);
  }

  Future<Announcement> updateAnnouncement(
    String id, {
    String? title,
    String? body,
    bool? isPinned,
  }) async {
    final json = await _api.updateAnnouncement(id, {
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (isPinned != null) 'is_pinned': isPinned,
    });
    return Announcement.fromJson(json);
  }

  Future<void> deleteAnnouncement(String id) => _api.deleteAnnouncement(id);

  // ---- Events (owner) ----

  Future<List<Event>> fetchEvents() async {
    final raw = await _api.fetchEvents();
    return raw.map(Event.fromJson).toList();
  }

  Future<Event> fetchEvent(String id) async =>
      Event.fromJson(await _api.fetchEvent(id));

  Future<Event> createEvent({
    required String title,
    required String description,
    required DateTime eventDate,
    String? startTime,
    required String locationText,
    required int feeCentavos,
    required String prizeDescription,
    int? capacity,
    DateTime? registrationClosesOn,
  }) async {
    final json = await _api.createEvent({
      'title': title,
      'description': description,
      'event_date': _fmtDate(eventDate),
      if (startTime != null) 'start_time': startTime,
      'location_text': locationText,
      'registration_fee': pesosToDecimalString(feeCentavos ~/ 100),
      'prize_description': prizeDescription,
      if (capacity != null) 'capacity': capacity,
      if (registrationClosesOn != null)
        'registration_closes_on': _fmtDate(registrationClosesOn),
    });
    return Event.fromJson(json);
  }

  Future<Event> updateEvent(String id, Map<String, dynamic> changes) async {
    final json = await _api.updateEvent(id, changes);
    return Event.fromJson(json);
  }

  Future<Event> cancelEvent(String id) async {
    final json = await _api.updateEvent(id, {
      'canceled_at': DateTime.now().toUtc().toIso8601String(),
    });
    return Event.fromJson(json);
  }

  Future<List<Registrant>> fetchRegistrants(String eventId) async {
    final raw = await _api.fetchRegistrants(eventId);
    return raw.map(Registrant.fromJson).toList();
  }

  Future<Registrant> markPaid(String registrationId) async =>
      Registrant.fromJson(await _api.markPaid(registrationId));

  Future<Registrant> markUnpaid(String registrationId) async =>
      Registrant.fromJson(await _api.markUnpaid(registrationId));

  Future<List<EventResultRow>> fetchResults(String eventId) async {
    final raw = await _api.fetchResults(eventId);
    return raw.map(EventResultRow.fromJson).toList();
  }

  Future<List<EventResultRow>> submitResults(
    String eventId,
    List<EventResultRow> rows,
  ) async {
    final raw = await _api.submitResults(
      eventId,
      rows.map((r) => r.toJson()).toList(),
    );
    return raw.map(EventResultRow.fromJson).toList();
  }

  // ---- Events (member) ----

  Future<EventActionResult> register(String eventId) async {
    try {
      final json = await _api.register(eventId);
      return EventActionResult(
        outcome: EventActionOutcome.success,
        registration: MyEventRegistration.fromJson(json),
      );
    } on ApiException catch (e) {
      return EventActionResult(
        outcome: e.kind == ApiExceptionKind.network
            ? EventActionOutcome.offline
            : EventActionOutcome.rejected,
        message: _messageFor(e, forRegister: true),
      );
    }
  }

  Future<EventActionResult> unregister(String eventId) async {
    try {
      final json = await _api.unregister(eventId);
      return EventActionResult(
        outcome: EventActionOutcome.success,
        message: json['detail'] as String?,
      );
    } on ApiException catch (e) {
      return EventActionResult(
        outcome: e.kind == ApiExceptionKind.network
            ? EventActionOutcome.offline
            : EventActionOutcome.rejected,
        message: _messageFor(e, forRegister: false),
      );
    }
  }

  String _messageFor(ApiException e, {required bool forRegister}) {
    if (e.kind == ApiExceptionKind.network) {
      return forRegister
          ? 'You need an internet connection to register.'
          : 'You need an internet connection to unregister.';
    }
    if (e.kind == ApiExceptionKind.notFound) {
      return "That event couldn't be found.";
    }
    final msg = e.message;
    if (msg.contains('cancel')) {
      return 'This event has been cancelled.';
    }
    if (msg.contains('closed'))
      return 'Registration for this event has closed.';
    if (msg.contains('cancel')) return 'This event has been cancelled.';
    // Archived-member message is shown verbatim — it already points the
    // member at gym staff.
    return msg;
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
