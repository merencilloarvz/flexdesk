import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/ingest.dart';
import '../../../core/utils/gym_time.dart';
import 'members_api.dart';

enum CreateMemberOutcome { synced, queuedOffline, rejected }

class CreateMemberResult {
  const CreateMemberResult({
    required this.outcome,
    this.fieldErrors,
    this.message,
  });

  final CreateMemberOutcome outcome;
  final Map<String, List<String>>? fieldErrors;
  final String? message;
}

class MembersRepository {
  MembersRepository(this._api, this._db);

  final MembersApi _api;
  final AppDatabase _db;

  static const _uuid = Uuid();
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  Future<void> refreshMembers(String gymId) async {
    await syncPendingMembers(gymId);

    final rawMembers = await _api.fetchAllMembers();
    final rows = rawMembers.map((json) => memberFromJson(json, gymId)).toList();
    final fetchedIds = rawMembers.map((json) => json['id'] as String).toSet();

    await _db.transaction(() async {
      await _db.batch((b) => b.insertAllOnConflictUpdate(_db.members, rows));

      await (_db.delete(_db.members)..where(
            (m) =>
                m.gymId.equals(gymId) &
                m.isDirty.equals(false) &
                m.id.isNotIn(fetchedIds),
          ))
          .go();
    });
  }

  /// Retries every offline-created member that's still marked dirty. Each
  /// one replays the exact request it tried to send originally (the plan
  /// choice included), since `createMember` is idempotent server-side on
  /// `id` — calling it again for an already-synced id is safe.
  Future<void> syncPendingMembers(String gymId) async {
    final pending =
        await (_db.select(_db.members)..where(
              (m) =>
                  m.gymId.equals(gymId) &
                  m.isDirty.equals(true) &
                  m.pendingPayload.isNotNull(),
            ))
            .get();

    for (final member in pending) {
      final payload = member.pendingPayload;
      if (payload == null) continue;

      try {
        final body = jsonDecode(payload) as Map<String, dynamic>;
        await _api.createMember(body);
        await (_db.update(
          _db.members,
        )..where((m) => m.id.equals(member.id))).write(
          const MembersCompanion(
            isDirty: Value(false),
            pendingPayload: Value(null),
          ),
        );
      } on ApiException catch (e) {
        if (e.kind == ApiExceptionKind.network) {
          // Still offline — stop trying the rest this round, they'll fail too.
          return;
        }
        final isIdempotentDuplicate =
            e.kind == ApiExceptionKind.validation &&
            (e.fieldErrors?.containsKey('id') ?? false);
        if (isIdempotentDuplicate) {
          await (_db.update(
            _db.members,
          )..where((m) => m.id.equals(member.id))).write(
            const MembersCompanion(
              isDirty: Value(false),
              pendingPayload: Value(null),
            ),
          );
        }
        // Any other rejection: leave it dirty. It'll show up in the
        // logout warning, which is the correct signal that it needs
        // manual attention.
      } catch (_) {
        // A corrupt/unparseable stored payload (e.g. jsonDecode failure)
        // must not take down the whole refresh — skip this row and let
        // the rest of the batch continue. It'll keep showing as dirty,
        // same as any other unresolved row.
        continue;
      }
    }
  }

  Stream<List<Member>> watchVisibleMembers(String gymId) =>
      (_db.select(_db.members)
            ..where((m) => m.gymId.equals(gymId) & m.archivedAt.isNull())
            ..orderBy([
              (m) => OrderingTerm(expression: m.firstName),
              (m) => OrderingTerm(expression: m.lastName),
            ]))
          .watch();

  Stream<Member?> watchMemberById(String id) => (_db.select(
    _db.members,
  )..where((m) => m.id.equals(id))).watchSingleOrNull();

  Future<List<Map<String, dynamic>>> fetchMemberHistory(String memberId) {
    return _api.fetchMemberHistory(memberId);
  }

  Future<void> archiveMember(String memberId) async {
    await _api.archiveMember(memberId);
    await (_db.update(_db.members)..where((m) => m.id.equals(memberId))).write(
      MembersCompanion(archivedAt: Value(DateTime.now())),
    );
  }

  /// Renews [memberId] onto [planId], then pulls the canonical member
  /// record — the renew response describes the new Membership, not the
  /// Member's derived fields (current_end_date, membership_status,
  /// current_plan_category), so a refresh is the only way to get those
  /// updated locally. Same reasoning as createMember's post-success
  /// refresh.
  ///
  /// No offline handling here, deliberately — renewing is done at the
  /// desk with the member present, same assumption as plan management,
  /// not the flaky-wifi-front-desk case createMember was built for.
  Future<void> renewMembership({
    required String memberId,
    required String gymId,
    required String planId,
  }) async {
    await _api.renewMember(memberId, planId);
    await refreshMembers(gymId);
  }

  Future<CreateMemberResult> createMember({
    required String gymId,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required DateTime? dateOfBirth,
    required String memberType,
    required String notes,
    required String homeLocationId,
    String? planId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final startDate = GymTime.today();

    final body = <String, dynamic>{
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'email': email,
      if (dateOfBirth != null) 'date_of_birth': _dateFormat.format(dateOfBirth),
      'member_type': memberType,
      'notes': notes,
      'home_location': homeLocationId,
      'start_date': _dateFormat.format(startDate),
      if (planId != null) 'plan_id': planId,
    };

    await _db
        .into(_db.members)
        .insertOnConflictUpdate(
          MembersCompanion.insert(
            id: id,
            gymId: gymId,
            homeLocationId: homeLocationId,
            firstName: firstName,
            lastName: Value(lastName),
            phone: Value(phone),
            email: Value(email),
            dateOfBirth: Value(dateOfBirth),
            memberType: memberType,
            notes: Value(notes),
            currentEndDate: const Value(null),
            createdAt: now,
            updatedAt: now,
            archivedAt: const Value(null),
            isDirty: const Value(true),
            pendingPayload: Value(jsonEncode(body)),
          ),
        );

    try {
      await _api.createMember(body);
      await _markSyncedAndRefresh(id, gymId);
      return const CreateMemberResult(outcome: CreateMemberOutcome.synced);
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        return const CreateMemberResult(
          outcome: CreateMemberOutcome.queuedOffline,
        );
      }

      final isIdempotentDuplicate =
          e.kind == ApiExceptionKind.validation &&
          (e.fieldErrors?.containsKey('id') ?? false);
      if (isIdempotentDuplicate) {
        await _markSyncedAndRefresh(id, gymId);
        return const CreateMemberResult(outcome: CreateMemberOutcome.synced);
      }

      await (_db.delete(_db.members)..where((m) => m.id.equals(id))).go();
      return CreateMemberResult(
        outcome: CreateMemberOutcome.rejected,
        fieldErrors: e.fieldErrors,
        message: e.message,
      );
    }
  }

  Future<void> _markSyncedAndRefresh(String id, String gymId) async {
    await (_db.update(_db.members)..where((m) => m.id.equals(id))).write(
      const MembersCompanion(
        isDirty: Value(false),
        pendingPayload: Value(null),
      ),
    );
    await refreshMembers(gymId);
  }
}
