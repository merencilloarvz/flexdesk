import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
}
