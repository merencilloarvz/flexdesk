import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import 'package:flexdesk/core/db/app_database.dart';
import 'package:flexdesk/core/db/ingest.dart';
import 'package:flexdesk/core/utils/money.dart';
import 'package:flexdesk/core/utils/member_status.dart';

// Adjust the `package:flexdesk/...` imports above if your pubspec's
// `name:` isn't `flexdesk`.

const _uuid = Uuid();

Map<String, dynamic> _planJson({
  required String id,
  String name = 'Monthly Regular',
  String category = 'regular',
  String price = '1200.00',
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'duration_value': 1,
    'duration_unit': 'MONTH',
    'price': price,
    'is_day_pass': false,
    'is_active': true,
    'sort_order': 0,
    'updated_at': DateTime.now().toIso8601String(),
  };
}

Map<String, dynamic> _memberJson({
  required String id,
  required String homeLocationId,
  String firstName = 'Juan',
}) {
  final now = DateTime.now().toIso8601String();
  return {
    'id': id,
    'home_location': homeLocationId,
    'member_code': '',
    'first_name': firstName,
    'last_name': 'Dela Cruz',
    'phone': '',
    'email': '',
    'date_of_birth': null,
    'member_type': 'MEMBER',
    'notes': '',
    'current_end_date': null,
    'created_at': now,
    'updated_at': now,
  };
}

// --- Migration-test helpers ---
// These build a raw v1-era sqlite file by hand, bypassing Drift entirely,
// so we can set PRAGMA user_version ourselves and force the real
// onUpgrade() path to run when AppDatabase opens it. This is the only way
// to exercise a v1 device's migration, since every real device in testing
// is already on v2 or v3.

void _createV1MembersTable(sqlite3.Database raw) {
  raw.execute('''
    CREATE TABLE members (
      id TEXT NOT NULL PRIMARY KEY,
      gym_id TEXT NOT NULL,
      home_location_id TEXT NOT NULL,
      member_code TEXT NOT NULL DEFAULT '',
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      email TEXT NOT NULL DEFAULT '',
      date_of_birth INTEGER,
      member_type TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      current_end_date INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      archived_at INTEGER,
      is_dirty INTEGER NOT NULL DEFAULT 0
    );
  ''');
  raw.execute('''
    CREATE UNIQUE INDEX uniq_member_code_per_gym
    ON members (gym_id, member_code)
    WHERE member_code != '';
  ''');
}

void _createV1PlansTable(sqlite3.Database raw) {
  raw.execute('''
    CREATE TABLE membership_plans (
      id TEXT NOT NULL PRIMARY KEY,
      gym_id TEXT NOT NULL,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT '',
      duration_value INTEGER NOT NULL DEFAULT 1,
      duration_unit TEXT NOT NULL DEFAULT 'MONTH',
      price INTEGER NOT NULL,
      is_day_pass INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      is_dirty INTEGER NOT NULL DEFAULT 0
    );
  ''');
}

void main() {
  const gymId = 'gym-iron-works-cebu';

  // --- Item 2: insert a plan and a member with uuid v4 ids, read back ---
  test('insert plan and member, read back, values match', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final planId = _uuid.v4();
    final memberId = _uuid.v4();
    final locationId = _uuid.v4();

    final planCompanion = membershipPlanFromJson(_planJson(id: planId), gymId);
    final memberCompanion = memberFromJson(
      _memberJson(id: memberId, homeLocationId: locationId),
      gymId,
    );

    await db.into(db.membershipPlans).insert(planCompanion);
    await db.into(db.members).insert(memberCompanion);

    final plans = await db.plansForGym(gymId);
    final storedMembers = await db.visibleMembers(gymId);

    expect(plans, hasLength(1));
    expect(plans.first.id, planId);
    expect(plans.first.priceCentavos, 120000); // "1200.00" -> 120000
    expect(plans.first.durationUnit, 'MONTH');

    expect(storedMembers, hasLength(1));
    expect(storedMembers.first.id, memberId);
    expect(storedMembers.first.firstName, 'Juan');
    expect(storedMembers.first.phone, ''); // never null
  });

  // --- Item 3: kill and relaunch, rows persist ---
  test('rows persist across close and reopen', () async {
    final dbFile = File(
      p.join(Directory.systemTemp.path, '${_uuid.v4()}.sqlite'),
    );
    addTearDown(() {
      if (dbFile.existsSync()) dbFile.deleteSync();
    });

    final planId = _uuid.v4();

    final db1 = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db1
        .into(db1.membershipPlans)
        .insert(membershipPlanFromJson(_planJson(id: planId), gymId));
    await db1.close(); // simulates app kill

    final db2 = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db2.close);
    final plans = await db2.plansForGym(gymId); // simulates relaunch

    expect(plans, hasLength(1));
    expect(plans.first.id, planId);
  });

  // --- Item 4: archived member excluded from default query ---
  test('archived member is excluded from visibleMembers', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final locationId = _uuid.v4();
    final activeId = _uuid.v4();
    final archivedId = _uuid.v4();

    await db
        .into(db.members)
        .insert(
          memberFromJson(
            _memberJson(id: activeId, homeLocationId: locationId),
            gymId,
          ),
        );
    await db
        .into(db.members)
        .insert(
          memberFromJson(
            _memberJson(id: archivedId, homeLocationId: locationId),
            gymId,
          ).copyWith(archivedAt: Value(DateTime.now())),
        );

    final visible = await db.visibleMembers(gymId);

    expect(visible, hasLength(1));
    expect(visible.first.id, activeId);
  });

  // --- Item 5: duplicate (gymId, name, category) fails the unique index ---
  test('duplicate plan name+category per gym is rejected', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.membershipPlans)
        .insert(membershipPlanFromJson(_planJson(id: _uuid.v4()), gymId));

    // Same gym, name, category — different id. Should violate uniqueKeys.
    expect(
      () => db
          .into(db.membershipPlans)
          .insert(membershipPlanFromJson(_planJson(id: _uuid.v4()), gymId)),
      throwsA(anything),
    );
  });

  // --- Item 6: parseCentavos ---
  test('parseCentavos matches acceptance cases', () {
    expect(parseCentavos('1500.00'), 150000);
    expect(parseCentavos('0.05'), 5);
    expect(
      parseCentavos('-10.50'),
      -1050,
    ); // not required, but worth locking in
  });

  // --- Item 7: statusFor ---
  test('statusFor boundary matches acceptance cases', () {
    final today = DateTime(2026, 8, 29);

    expect(
      statusFor(today.add(const Duration(days: 7)), today),
      MembershipStatus.expiring,
    );
    expect(
      statusFor(today.add(const Duration(days: 8)), today),
      MembershipStatus.active,
    );
    expect(
      statusFor(today.subtract(const Duration(days: 1)), today),
      MembershipStatus.expired,
    );
    expect(statusFor(null, today), MembershipStatus.noMembership);
  });

  // --- Regression: wall-clock time must not affect the result ---
  // The item-7 test above passes a midnight `today`, which hid a real bug:
  // without date normalization, a membership ending "today" showed as
  // expired the moment DateTime.now()'s clock time passed midnight.
  test('statusFor and daysRemaining ignore time-of-day', () {
    final endToday = DateTime(2026, 8, 29); // midnight, from DateTime.parse
    final nowLateInDay = DateTime(2026, 8, 29, 14, 30); // 2:30pm

    expect(
      statusFor(endToday, nowLateInDay),
      isNot(MembershipStatus.expired),
      reason:
          'a membership ending today is still active/expiring at 2:30pm, '
          'not expired',
    );

    final tomorrowMidnight = DateTime(2026, 8, 30);
    expect(daysRemaining(tomorrowMidnight, nowLateInDay), 1);
  });

  // --- centavosToDecimalString: inverse of parseCentavos, integer-only ---
  test('centavosToDecimalString matches parseCentavos round-trip', () {
    expect(centavosToDecimalString(150000), '1500.00');
    expect(centavosToDecimalString(5), '0.05');
    expect(centavosToDecimalString(-1050), '-10.50');
  });

  // --- Migration: v1 device jumps straight to v3 ---
  // Every real test device has been on v2 or v3 the whole time, so this
  // path — a v1 device that never saw the v2 release — was completely
  // untested until now. Confirms both addColumn steps run in sequence
  // (not skipped) and a dirty row survives the jump intact.
  test('v1 to v3 migration adds new columns, dirty row survives', () async {
    final dbFile = File(
      p.join(Directory.systemTemp.path, '${_uuid.v4()}_v1.sqlite'),
    );
    addTearDown(() {
      if (dbFile.existsSync()) dbFile.deleteSync();
    });

    final memberId = _uuid.v4();
    final locationId = _uuid.v4();
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final raw = sqlite3.sqlite3.open(dbFile.path);
    _createV1MembersTable(raw);
    _createV1PlansTable(raw);
    raw.execute('PRAGMA user_version = 1;');
    raw.execute(
      '''
      INSERT INTO members (
        id, gym_id, home_location_id, member_code, first_name, last_name,
        phone, email, date_of_birth, member_type, notes, current_end_date,
        created_at, updated_at, archived_at, is_dirty
      ) VALUES (?, ?, ?, '', 'Juan', 'Dela Cruz', '', '', NULL, 'MEMBER',
        '', NULL, ?, ?, NULL, 1);
      ''',
      [memberId, gymId, locationId, nowSeconds, nowSeconds],
    );
    raw.dispose();

    // Opening through the real AppDatabase triggers the actual onUpgrade
    // path — both `if (from < 2)` and `if (from < 3)` should fire in
    // sequence for a v1 device, not just one of them.
    final db = AppDatabase.forTesting(
      NativeDatabase(dbFile),
      rethrowMigrationErrors: true, // want the normal path, not recovery
    );
    addTearDown(db.close);

    final members = await db.visibleMembers(gymId);
    expect(members, hasLength(1));
    expect(members.first.id, memberId);
    expect(members.first.isDirty, true);
    // Both new columns exist and are queryable post-migration — a v1
    // device landing on v3 doesn't crash on either one.
    expect(members.first.currentPlanCategory, isNull);
    expect(members.first.pendingPayload, isNull);
  });

  // --- Recovery path: this is the exact bug the review caught ---
  // Forces the migration's catch/recovery branch to run (by pre-creating
  // a column addColumn will collide with), then checks that a dirty
  // row's pendingPayload and dateOfBirth survive the rescue. Before the
  // fix, the rescue companion omitted both fields — the row survived but
  // came back permanently unsyncable with the user's data silently gone.
  test(
    'recovery path preserves pendingPayload and dateOfBirth on a dirty row',
    () async {
      final dbFile = File(
        p.join(Directory.systemTemp.path, '${_uuid.v4()}_recovery.sqlite'),
      );
      addTearDown(() {
        if (dbFile.existsSync()) dbFile.deleteSync();
      });

      final memberId = _uuid.v4();
      final locationId = _uuid.v4();
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final dobSeconds = DateTime(2000, 5, 14).millisecondsSinceEpoch ~/ 1000;
      const payload = '{"first_name":"Juan","plan_id":"deleted-plan"}';

      // Table already has the v2/v3 columns, but user_version claims 1 —
      // so onUpgrade tries addColumn(currentPlanCategory) against a
      // column that already exists, which throws and triggers recovery.
      final raw = sqlite3.sqlite3.open(dbFile.path);
      raw.execute('''
        CREATE TABLE members (
          id TEXT NOT NULL PRIMARY KEY,
          gym_id TEXT NOT NULL,
          home_location_id TEXT NOT NULL,
          member_code TEXT NOT NULL DEFAULT '',
          first_name TEXT NOT NULL,
          last_name TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          date_of_birth INTEGER,
          member_type TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          current_end_date INTEGER,
          current_plan_category TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          archived_at INTEGER,
          is_dirty INTEGER NOT NULL DEFAULT 0,
          pending_payload TEXT
        );
      ''');
      _createV1PlansTable(raw);
      raw.execute('PRAGMA user_version = 1;');
      raw.execute(
        '''
        INSERT INTO members (
          id, gym_id, home_location_id, member_code, first_name, last_name,
          phone, email, date_of_birth, member_type, notes, current_end_date,
          current_plan_category, created_at, updated_at, archived_at,
          is_dirty, pending_payload
        ) VALUES (?, ?, ?, '', 'Juan', 'Dela Cruz', '', '', ?, 'MEMBER', '',
          NULL, NULL, ?, ?, NULL, 1, ?);
        ''',
        [
          memberId,
          gymId,
          locationId,
          dobSeconds,
          nowSeconds,
          nowSeconds,
          payload,
        ],
      );
      raw.dispose();

      final db = AppDatabase.forTesting(
        NativeDatabase(dbFile),
        rethrowMigrationErrors: false, // exercise the recovery branch
      );
      addTearDown(db.close);

      final members = await db.visibleMembers(gymId);
      expect(members, hasLength(1));
      expect(members.first.id, memberId);
      expect(members.first.isDirty, true);
      // This is the exact bug the recovery companion had before the fix:
      // pendingPayload and dateOfBirth were dropped during rescue,
      // leaving the row permanently stuck — isDirty forever, unsyncable,
      // since syncPendingMembers only retries rows where
      // pendingPayload.isNotNull().
      expect(members.first.pendingPayload, payload);
      expect(members.first.dateOfBirth, DateTime(2000, 5, 14));
    },
  );
}
