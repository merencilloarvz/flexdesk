import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/ingest.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/money.dart';
import '../../members/data/members_repository.dart';
import 'check_ins_api.dart';

enum CreateCheckInOutcome { synced, queuedOffline, rejected }

class CreateCheckInResult {
  const CreateCheckInResult({
    required this.outcome,
    this.fieldErrors,
    this.message,
  });

  final CreateCheckInOutcome outcome;
  final Map<String, List<String>>? fieldErrors;
  final String? message;
}

class CheckInsRepository {
  CheckInsRepository(this._api, this._db, this._membersRepository);

  final CheckInsApi _api;
  final AppDatabase _db;
  final MembersRepository _membersRepository;

  static const _uuid = Uuid();

  /// Refreshes local check-ins for [day] (gym-local calendar date,
  /// defaults to today) from the server. Deletes ONLY non-dirty rows
  /// within that day's range — never touches other days, or refreshing
  /// today would wipe local history for every other day.
  ///
  /// Syncs pending members FIRST, then pending check-ins. This order
  /// matters: staff can create a member offline and immediately check
  /// them in, queuing both. If the check-in synced before the member
  /// exists on the server, it would be wrongly rejected. Syncing members
  /// first means that's usually already resolved by the time check-ins
  /// try — syncPendingCheckIns's own dirty-member skip is the fallback
  /// for when this half-fails.
  Future<void> refreshCheckIns(String gymId, {DateTime? day}) async {
    final targetDay = day ?? GymTime.today();

    await _membersRepository.syncPendingMembers(gymId);
    await syncPendingCheckIns(gymId);

    final dateStr =
        '${targetDay.year.toString().padLeft(4, '0')}-'
        '${targetDay.month.toString().padLeft(2, '0')}-'
        '${targetDay.day.toString().padLeft(2, '0')}';

    final rawCheckIns = await _api.fetchCheckIns(date: dateStr);
    final rows = rawCheckIns
        .map((json) => checkInFromJson(json, gymId))
        .toList();
    final fetchedIds = rawCheckIns.map((json) => json['id'] as String).toSet();

    final dayStart = GymTime.startOfDay(targetDay);
    final dayEnd = GymTime.endOfDay(targetDay);

    await _db.transaction(() async {
      await _db.batch((b) => b.insertAllOnConflictUpdate(_db.checkIns, rows));

      await (_db.delete(_db.checkIns)..where(
            (c) =>
                c.gymId.equals(gymId) &
                c.isDirty.equals(false) &
                c.checkedInAt.isBiggerOrEqualValue(dayStart) &
                c.checkedInAt.isSmallerThanValue(dayEnd) &
                c.id.isNotIn(fetchedIds),
          ))
          .go();
    });
  }

  /// Retries every offline-created check-in still marked dirty and not
  /// yet judged (syncError null). Same idempotent-replay reasoning as
  /// MembersRepository.syncPendingMembers.
  Future<void> syncPendingCheckIns(String gymId) async {
    final pending =
        await (_db.select(_db.checkIns)..where(
              (c) =>
                  c.gymId.equals(gymId) &
                  c.isDirty.equals(true) &
                  c.pendingPayload.isNotNull() &
                  c.syncError.isNull(),
            ))
            .get();

    for (final checkIn in pending) {
      final payload = checkIn.pendingPayload;
      if (payload == null) continue;

      Map<String, dynamic> body;
      try {
        body = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        // Corrupt/unparseable stored payload — skip this row, don't take
        // down the rest of the batch.
        continue;
      }

      // Guard: a MEMBER check-in whose member hasn't reached the server
      // yet must not be posted — the server would 400 on an unknown
      // member id and this check-in would be marked permanently rejected,
      // even though it genuinely happened. refreshCheckIns() already
      // syncs members first, so this branch is normally a no-op; it only
      // fires when that member sync itself half-failed.
      if (body['visit_type'] == 'MEMBER' && body['member'] is String) {
        final memberId = body['member'] as String;
        final member = await (_db.select(
          _db.members,
        )..where((m) => m.id.equals(memberId))).getSingleOrNull();
        if (member != null && member.isDirty) {
          continue; // leave pending — not an error, just not ready yet
        }
      }

      try {
        await _api.createCheckIn(body);
        await (_db.update(
          _db.checkIns,
        )..where((c) => c.id.equals(checkIn.id))).write(
          const CheckInsCompanion(
            isDirty: Value(false),
            pendingPayload: Value(null),
          ),
        );
      } on ApiException catch (e) {
        if (e.kind == ApiExceptionKind.network) {
          return; // still offline — rest of the batch will fail too
        }
        final isIdempotentDuplicate =
            e.kind == ApiExceptionKind.validation &&
            (e.fieldErrors?.containsKey('id') ?? false);
        if (isIdempotentDuplicate) {
          await (_db.update(
            _db.checkIns,
          )..where((c) => c.id.equals(checkIn.id))).write(
            const CheckInsCompanion(
              isDirty: Value(false),
              pendingPayload: Value(null),
            ),
          );
        } else {
          await (_db.update(
            _db.checkIns,
          )..where((c) => c.id.equals(checkIn.id))).write(
            CheckInsCompanion(
              syncError: Value(e.message ?? 'Rejected by server.'),
              syncFailedAt: Value(DateTime.now()),
            ),
          );
        }
      }
    }
  }

  Future<void> retryPending(String checkInId) {
    return (_db.update(
      _db.checkIns,
    )..where((c) => c.id.equals(checkInId))).write(
      const CheckInsCompanion(
        syncError: Value(null),
        syncFailedAt: Value(null),
      ),
    );
  }

  Future<void> discardPending(String checkInId) {
    return (_db.delete(
      _db.checkIns,
    )..where((c) => c.id.equals(checkInId))).go();
  }

  /// Local, offline-capable check-ins list for [day], newest first.
  Stream<List<CheckIn>> watchCheckIns(String gymId, DateTime day) {
    final dayStart = GymTime.startOfDay(day);
    final dayEnd = GymTime.endOfDay(day);
    return (_db.select(_db.checkIns)
          ..where(
            (c) =>
                c.gymId.equals(gymId) &
                c.checkedInAt.isBiggerOrEqualValue(dayStart) &
                c.checkedInAt.isSmallerThanValue(dayEnd),
          )
          ..orderBy([(c) => OrderingTerm.desc(c.checkedInAt)]))
        .watch();
  }

  /// Checks in an existing member. [membershipStatus] and
  /// [membershipEndDate] must already be computed locally by the caller
  /// (from the cached member's currentEndDate and GymTime.today()) — both
  /// sides derive it identically, which is what makes an offline
  /// check-in produce the same record as an online one.
  Future<CreateCheckInResult> createMemberCheckIn({
    required String gymId,
    required String memberId,
    required String locationId,
    required String membershipStatus,
    required DateTime? membershipEndDate,
  }) {
    return _createCheckIn(
      gymId: gymId,
      locationId: locationId,
      visitType: 'MEMBER',
      memberId: memberId,
      membershipStatus: membershipStatus,
      membershipEndDate: membershipEndDate,
    );
  }

  /// Checks in a walk-in. No member record — a typed name, a category,
  /// and an optional custom price staff enters on the spot.
  Future<CreateCheckInResult> createWalkInCheckIn({
    required String gymId,
    required String locationId,
    required String visitorName,
    required String category,
    int? amountChargedCentavos,
  }) {
    return _createCheckIn(
      gymId: gymId,
      locationId: locationId,
      visitType: 'WALKIN',
      visitorName: visitorName,
      category: category,
      amountChargedCentavos: amountChargedCentavos,
    );
  }

  Future<CreateCheckInResult> _createCheckIn({
    required String gymId,
    required String locationId,
    required String visitType,
    String? memberId,
    String? membershipStatus,
    DateTime? membershipEndDate,
    String? visitorName,
    String? category,
    int? amountChargedCentavos,
  }) async {
    final id = _uuid.v4();
    // The real instant, not gym-local wall time — GymTime.today() is only
    // for date comparisons, never for timestamping an event.
    final checkedInAt = DateTime.now().toUtc();

    final body = <String, dynamic>{
      'id': id,
      'visit_type': visitType,
      'location': locationId,
      'checked_in_at': checkedInAt.toIso8601String(),
      if (memberId != null) 'member': memberId,
      if (membershipStatus != null) 'membership_status': membershipStatus,
      if (membershipEndDate != null)
        'membership_end_date': membershipEndDate
            .toIso8601String()
            .split('T')
            .first,
      if (visitorName != null) 'visitor_name': visitorName,
      if (category != null) 'category': category,
      if (amountChargedCentavos != null)
        'amount_charged': centavosToDecimalString(amountChargedCentavos),
    };

    await _db
        .into(_db.checkIns)
        .insertOnConflictUpdate(
          CheckInsCompanion.insert(
            id: id,
            gymId: gymId,
            visitType: visitType,
            memberId: Value(memberId),
            locationId: locationId,
            checkedInAt: checkedInAt,
            membershipStatus: Value(membershipStatus ?? ''),
            membershipEndDate: Value(membershipEndDate),
            visitorName: Value(visitorName ?? ''),
            category: Value(category ?? ''),
            amountChargedCentavos: Value(amountChargedCentavos),
            createdAt: checkedInAt,
            updatedAt: checkedInAt,
            isDirty: const Value(true),
            pendingPayload: Value(jsonEncode(body)),
          ),
        );

    try {
      await _api.createCheckIn(body);
      await (_db.update(_db.checkIns)..where((c) => c.id.equals(id))).write(
        const CheckInsCompanion(
          isDirty: Value(false),
          pendingPayload: Value(null),
        ),
      );
      // Re-fetch so the local row picks up the server's real created_at/
      // updated_at, matching the createMember pattern.
      await refreshCheckIns(gymId, day: GymTime.today());
      return const CreateCheckInResult(outcome: CreateCheckInOutcome.synced);
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        return const CreateCheckInResult(
          outcome: CreateCheckInOutcome.queuedOffline,
        );
      }

      final isIdempotentDuplicate =
          e.kind == ApiExceptionKind.validation &&
          (e.fieldErrors?.containsKey('id') ?? false);
      if (isIdempotentDuplicate) {
        await (_db.update(_db.checkIns)..where((c) => c.id.equals(id))).write(
          const CheckInsCompanion(
            isDirty: Value(false),
            pendingPayload: Value(null),
          ),
        );
        await refreshCheckIns(gymId, day: GymTime.today());
        return const CreateCheckInResult(outcome: CreateCheckInOutcome.synced);
      }

      // Rejected on the FIRST attempt (not a queued retry) — the row is
      // wrong from the start (e.g. bad member id), nothing worth keeping
      // dirty. Delete it, same as createMember does.
      await (_db.delete(_db.checkIns)..where((c) => c.id.equals(id))).go();
      return CreateCheckInResult(
        outcome: CreateCheckInOutcome.rejected,
        fieldErrors: e.fieldErrors,
        message: e.message,
      );
    }
  }

  Future<void> voidCheckIn(String checkInId) async {
    final row = await (_db.select(
      _db.checkIns,
    )..where((c) => c.id.equals(checkInId))).getSingleOrNull();
    if (row == null) return;

    // Never synced — there is nothing on the server to void. Drop it
    // locally. This is the only path that works offline, and it's the
    // one staff need most: a mistake made at the desk while wifi is down.
    if (row.isDirty) {
      await (_db.delete(
        _db.checkIns,
      )..where((c) => c.id.equals(checkInId))).go();
      return;
    }

    await _api.voidCheckIn(checkInId);
    await (_db.update(_db.checkIns)..where((c) => c.id.equals(checkInId)))
        .write(CheckInsCompanion(voidedAt: Value(DateTime.now())));
  }
}
