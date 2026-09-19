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
    required this.likeCount,
    required this.likedByMe,
    required this.commentCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final bool isPinned;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final DateTime createdAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    isPinned: json['is_pinned'] as bool,
    likeCount: json['like_count'] as int? ?? 0,
    likedByMe: json['liked_by_me'] as bool? ?? false,
    commentCount: json['comment_count'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  /// Same announcement with updated like/comment numbers — lets a list
  /// reflect a like or comment made on a card without a refetch.
  Announcement withEngagement({
    int? likeCount,
    bool? likedByMe,
    int? commentCount,
  }) => Announcement(
    id: id,
    title: title,
    body: body,
    isPinned: isPinned,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    commentCount: commentCount ?? this.commentCount,
    createdAt: createdAt,
  );
}

/// What a like or comment can be attached to. [path] is the server's URL
/// segment for that kind of item.
enum CommunityItemType {
  announcement('announcements'),
  event('events');

  const CommunityItemType(this.path);
  final String path;
}

/// Result of toggling a like: the item's new state, as the server sees it.
class LikeState {
  const LikeState({required this.likeCount, required this.likedByMe});

  final int likeCount;
  final bool likedByMe;

  factory LikeState.fromJson(Map<String, dynamic> json) => LikeState(
    likeCount: json['like_count'] as int,
    likedByMe: json['liked_by_me'] as bool,
  );
}

class Comment {
  Comment({
    required this.id,
    required this.body,
    required this.authorName,
    required this.authorRole,
    required this.isMine,
    required this.canDelete,
    required this.createdAt,
  });

  final String id;
  final String body;
  final String authorName;
  final String authorRole; // 'owner' | 'staff' | 'member'
  final bool isMine;

  /// Own comment, or the viewer is staff (moderation). Server-computed so
  /// the UI never has to re-derive it.
  final bool canDelete;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    body: json['body'] as String,
    authorName: json['author_name'] as String,
    authorRole: json['author_role'] as String,
    isMine: json['is_mine'] as bool,
    canDelete: json['can_delete'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// One page of comments. [totalCount] is the server's count across all
/// pages, so a header can say "Comments (12)" with only 5 loaded.
class CommentPage {
  const CommentPage({
    required this.items,
    required this.hasMore,
    required this.totalCount,
  });

  final List<Comment> items;
  final bool hasMore;
  final int totalCount;
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
    required this.guidelines,
    required this.capacity,
    required this.registrationClosesOn,
    required this.canceledAt,
    required this.registrationCount,
    required this.spotsLeft,
    required this.myRegistration,
    required this.resultsVerified,
    required this.resultsVerifiedAt,
    required this.likeCount,
    required this.likedByMe,
    required this.commentCount,
  });

  final String id;
  final String title;
  final String description;
  final DateTime eventDate;
  final String? startTime; // "HH:MM:SS" or null
  final String locationText;
  final int feeCentavos;
  final String prizeDescription;
  final String? guidelines;
  final int? capacity;
  final DateTime? registrationClosesOn;
  final DateTime? canceledAt;
  final int registrationCount;
  final int? spotsLeft;
  final MyEventRegistration? myRegistration;
  final bool resultsVerified;
  final DateTime? resultsVerifiedAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;

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
    guidelines: json['guidelines'] as String?,
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
    resultsVerified: json['results_verified'] as bool? ?? false,
    resultsVerifiedAt: json['results_verified_at'] != null
        ? DateTime.parse(json['results_verified_at'] as String)
        : null,
    likeCount: json['like_count'] as int? ?? 0,
    likedByMe: json['liked_by_me'] as bool? ?? false,
    commentCount: json['comment_count'] as int? ?? 0,
  );

  /// Same event with updated like/comment numbers — see
  /// [Announcement.withEngagement].
  Event withEngagement({int? likeCount, bool? likedByMe, int? commentCount}) =>
      Event(
        id: id,
        title: title,
        description: description,
        eventDate: eventDate,
        startTime: startTime,
        locationText: locationText,
        feeCentavos: feeCentavos,
        prizeDescription: prizeDescription,
        guidelines: guidelines,
        capacity: capacity,
        registrationClosesOn: registrationClosesOn,
        canceledAt: canceledAt,
        registrationCount: registrationCount,
        spotsLeft: spotsLeft,
        myRegistration: myRegistration,
        resultsVerified: resultsVerified,
        resultsVerifiedAt: resultsVerifiedAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        commentCount: commentCount ?? this.commentCount,
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

  Future<Announcement> fetchAnnouncement(String id) async =>
      Announcement.fromJson(await _api.fetchAnnouncement(id));

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
    String? guidelines,
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
      'guidelines': ?guidelines,
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

  Future<Event> verifyResults(String eventId) async =>
      Event.fromJson(await _api.verifyResults(eventId));

  Future<Event> unverifyResults(String eventId) async =>
      Event.fromJson(await _api.unverifyResults(eventId));

  // ---- Likes & comments (announcements and events) ----

  /// Toggles the caller's like and returns the item's new state — the
  /// caller should render from this, not flip its own copy.
  Future<LikeState> toggleLike(CommunityItemType itemType, String itemId) async =>
      LikeState.fromJson(await _api.toggleLike(itemType.path, itemId));

  Future<List<Comment>> fetchComments(
    CommunityItemType itemType,
    String itemId,
  ) async {
    final raw = await _api.fetchComments(itemType.path, itemId);
    return raw.map(Comment.fromJson).toList();
  }

  /// One page of comments (1-based), newest first. Prefer this over
  /// [fetchComments] for anything a person scrolls — that one walks every
  /// page.
  Future<CommentPage> fetchCommentsPage(
    CommunityItemType itemType,
    String itemId,
    int page,
  ) async {
    final body = await _api.fetchCommentsPage(itemType.path, itemId, page);
    return CommentPage(
      items: (body['results'] as List)
          .cast<Map<String, dynamic>>()
          .map(Comment.fromJson)
          .toList(),
      hasMore: body['next'] != null,
      totalCount: body['count'] as int,
    );
  }

  Future<Comment> postComment(
    CommunityItemType itemType,
    String itemId,
    String body,
  ) async => Comment.fromJson(
    await _api.postComment(itemType.path, itemId, {'body': body}),
  );

  Future<void> deleteComment(
    CommunityItemType itemType,
    String itemId,
    String commentId,
  ) => _api.deleteComment(itemType.path, itemId, commentId);

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
