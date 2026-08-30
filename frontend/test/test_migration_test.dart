import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdesk/core/db/app_database.dart';
import 'package:drift/drift.dart';

void main() {
  test('v1 -> v2 upgrade preserves rows, including dirty ones', () async {
    final executor = NativeDatabase.memory();

    // Build a raw "v1" database by hand — no current_plan_category column.
    final rawDb = executor;
    await rawDb.ensureOpen(_TestUser());
    await rawDb.runCustom('''
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
    ''', []);
    await rawDb.runCustom('''
      CREATE TABLE membership_plans (
        id TEXT NOT NULL PRIMARY KEY,
        gym_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        duration_value INTEGER NOT NULL,
        duration_unit TEXT NOT NULL,
        price_centavos INTEGER NOT NULL,
        is_day_pass INTEGER NOT NULL,
        is_active INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0
      );
    ''', []);
    await rawDb.runCustom(
      "INSERT INTO members (id, gym_id, home_location_id, first_name, member_type, created_at, updated_at, is_dirty) "
      "VALUES ('synced1', 'gym1', 'loc1', 'Juan', 'MEMBER', 0, 0, 0);",
      [],
    );
    await rawDb.runCustom(
      "INSERT INTO members (id, gym_id, home_location_id, first_name, member_type, created_at, updated_at, is_dirty) "
      "VALUES ('dirty1', 'gym1', 'loc1', 'Maria', 'MEMBER', 0, 0, 1);",
      [],
    );
    await rawDb.runCustom('PRAGMA user_version = 1;', []);

    // Now open it with the real app code — this triggers onUpgrade for real.
    final db = AppDatabase.forTesting(executor);
    final allMembers = await db.select(db.members).get();

    expect(allMembers.length, 2, reason: 'both rows must survive the upgrade');
    expect(
      allMembers.any((m) => m.id == 'dirty1'),
      isTrue,
      reason: 'the unsynced offline-created member must not be lost',
    );

    await db.close();
  });
}

class _TestUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
