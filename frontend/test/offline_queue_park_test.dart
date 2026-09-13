// Covers the "park vs. delete" rule for a queued write's first attempt:
// a validation rejection with field errors (the payload is genuinely
// wrong) deletes the local row, same as before; everything else — a
// transient 5xx, a blocked subscription (402), an auth blip — now keeps
// the row and parks it (syncError + syncFailedAt set, excluded from
// automatic retry) instead of destroying data over what might clear up
// on its own. See CheckInsRepository._parkCheckIn / MembersRepository._parkMember.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/core/db/app_database.dart';
import 'package:flexdesk/features/members/data/check_ins_api.dart';
import 'package:flexdesk/features/members/data/check_ins_repository.dart';
import 'package:flexdesk/features/members/data/members_api.dart';
import 'package:flexdesk/features/members/data/members_repository.dart';

// Adjust the `package:flexdesk/...` imports above if your pubspec's
// `name:` isn't `flexdesk` — same note as db_smoke_test.dart.

/// Throws [exception] from createCheckIn instead of making a real
/// network call, and counts how many times it was actually invoked —
/// that call count is what proves a parked row was excluded from a
/// later retry pass, rather than merely re-parked to the same value.
class _ThrowingCheckInsApi extends CheckInsApi {
  _ThrowingCheckInsApi(this._exception) : super(Dio());
  final ApiException _exception;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> createCheckIn(Map<String, dynamic> body) async {
    callCount++;
    throw _exception;
  }
}

class _ThrowingMembersApi extends MembersApi {
  _ThrowingMembersApi(this._exception) : super(Dio());
  final ApiException _exception;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> createMember(Map<String, dynamic> body) async {
    callCount++;
    throw _exception;
  }
}

const _subscriptionMessage =
    "Your gym's subscription has expired. Please subscribe to continue.";

void main() {
  group('CheckInsRepository — first-attempt failure handling', () {
    late AppDatabase db;
    late MembersRepository membersRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      membersRepo = MembersRepository(MembersApi(Dio()), db);
    });

    tearDown(() async {
      await db.close();
    });

    test('a 500 on first attempt keeps the row and parks it', () async {
      final api = _ThrowingCheckInsApi(
        ApiException(
          kind: ApiExceptionKind.server,
          message: 'Something went wrong. Please try again.',
        ),
      );
      final repo = CheckInsRepository(api, db, membersRepo);

      final result = await repo.createWalkInCheckIn(
        gymId: 'gym-1',
        locationId: 'loc-1',
        visitorName: 'Test Walkin',
        category: 'regular',
        amountChargedCentavos: 10000,
      );

      expect(result.outcome, CreateCheckInOutcome.rejected);

      final rows = await db.select(db.checkIns).get();
      expect(rows, hasLength(1));
      expect(rows.single.isDirty, isTrue);
      expect(rows.single.syncError, 'Something went wrong. Please try again.');
      expect(rows.single.syncFailedAt, isNotNull);
    });

    test('a 400 with field errors still deletes the row', () async {
      final api = _ThrowingCheckInsApi(
        ApiException(
          kind: ApiExceptionKind.validation,
          message: 'Invalid data',
          fieldErrors: {
            'category': ['This field is required.'],
          },
        ),
      );
      final repo = CheckInsRepository(api, db, membersRepo);

      final result = await repo.createWalkInCheckIn(
        gymId: 'gym-1',
        locationId: 'loc-1',
        visitorName: 'Test Walkin',
        category: 'regular',
        amountChargedCentavos: 10000,
      );

      expect(result.outcome, CreateCheckInOutcome.rejected);

      final rows = await db.select(db.checkIns).get();
      expect(rows, isEmpty);
    });

    test(
      'a 402 parks the row with the neutral message and is excluded '
      'from automatic retry',
      () async {
        final api = _ThrowingCheckInsApi(
          ApiException(
            kind: ApiExceptionKind.subscriptionRequired,
            message: _subscriptionMessage,
          ),
        );
        final repo = CheckInsRepository(api, db, membersRepo);

        final result = await repo.createWalkInCheckIn(
          gymId: 'gym-1',
          locationId: 'loc-1',
          visitorName: 'Test Walkin',
          category: 'regular',
          amountChargedCentavos: 10000,
        );

        expect(result.outcome, CreateCheckInOutcome.rejected);
        // The immediate, in-context result to whoever just attempted
        // this can still carry the real reason — only the row that
        // might be seen later, out of context, gets the neutral text.
        expect(result.message, _subscriptionMessage);

        final rows = await db.select(db.checkIns).get();
        expect(rows, hasLength(1));
        expect(rows.single.isDirty, isTrue);
        expect(
          rows.single.syncError,
          "Couldn't sync — the gym's FlexDesk subscription needs attention",
        );
        expect(rows.single.syncError, isNot(contains('subscription has expired')));
        expect(api.callCount, 1);

        // Excluded from automatic retry: syncPendingCheckIns' own query
        // filters on syncError.isNull(), so this pass must not call the
        // API again for this row.
        await repo.syncPendingCheckIns('gym-1');
        expect(api.callCount, 1);

        final afterRetryPass = await db.select(db.checkIns).get();
        expect(afterRetryPass.single.syncError, isNotNull);
      },
    );
  });

  group('MembersRepository — first-attempt failure handling', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<CreateMemberResult> createTestMember(MembersRepository repo) {
      return repo.createMember(
        gymId: 'gym-1',
        firstName: 'Test',
        lastName: 'Member',
        phone: '',
        email: 'test@example.com',
        dateOfBirth: null,
        memberType: 'MEMBER',
        notes: '',
        homeLocationId: 'loc-1',
      );
    }

    test('a 500 on first attempt keeps the row and parks it', () async {
      final api = _ThrowingMembersApi(
        ApiException(
          kind: ApiExceptionKind.server,
          message: 'Something went wrong. Please try again.',
        ),
      );
      final repo = MembersRepository(api, db);

      final result = await createTestMember(repo);

      expect(result.outcome, CreateMemberOutcome.rejected);

      final rows = await db.select(db.members).get();
      expect(rows, hasLength(1));
      expect(rows.single.isDirty, isTrue);
      expect(rows.single.syncError, 'Something went wrong. Please try again.');
      expect(rows.single.syncFailedAt, isNotNull);
    });

    test('a 400 with field errors still deletes the row', () async {
      final api = _ThrowingMembersApi(
        ApiException(
          kind: ApiExceptionKind.validation,
          message: 'Invalid data',
          fieldErrors: {
            'email': ['This field is required.'],
          },
        ),
      );
      final repo = MembersRepository(api, db);

      final result = await createTestMember(repo);

      expect(result.outcome, CreateMemberOutcome.rejected);

      final rows = await db.select(db.members).get();
      expect(rows, isEmpty);
    });

    test(
      'a 402 parks the row with the neutral message and is excluded '
      'from automatic retry',
      () async {
        final api = _ThrowingMembersApi(
          ApiException(
            kind: ApiExceptionKind.subscriptionRequired,
            message: _subscriptionMessage,
          ),
        );
        final repo = MembersRepository(api, db);

        final result = await createTestMember(repo);

        expect(result.outcome, CreateMemberOutcome.rejected);
        expect(result.message, _subscriptionMessage);

        final rows = await db.select(db.members).get();
        expect(rows, hasLength(1));
        expect(rows.single.isDirty, isTrue);
        expect(
          rows.single.syncError,
          "Couldn't sync — the gym's FlexDesk subscription needs attention",
        );
        expect(rows.single.syncError, isNot(contains('subscription has expired')));
        expect(api.callCount, 1);

        await repo.syncPendingMembers('gym-1');
        expect(api.callCount, 1);

        final afterRetryPass = await db.select(db.members).get();
        expect(afterRetryPass.single.syncError, isNotNull);
      },
    );
  });
}
