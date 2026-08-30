import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:flexdesk/core/db/app_database.dart';

// Builds a raw "v1" sqlite database entirely OUTSIDE of Drift — no
// executor.ensureOpen() call — so that when AppDatabase.forTesting wraps
// it, Drift's own open cycle is the first and only one, and it genuinely
// sees user_version=1 vs its target schemaVersion=2 and runs onUpgrade.
sqlite3.Database _buildV1Database({required bool includeNewColumn}) {
  final raw = sqlite3.sqlite3.openInMemory();

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
      ${includeNewColumn ? 'current_plan_category TEXT,' : ''}
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      archived_at INTEGER,
      is_dirty INTEGER NOT NULL DEFAULT 0
    );
  ''');

  raw.execute('''
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
  ''');

  raw.execute(
    "INSERT INTO members (id, gym_id, home_location_id, first_name, member_type, created_at, updated_at, is_dirty) "
    "VALUES ('synced1', 'gym1', 'loc1', 'Juan', 'MEMBER', 0, 0, 0);",
  );
  raw.execute(
    "INSERT INTO members (id, gym_id, home_location_id, first_name, member_type, notes, created_at, updated_at, is_dirty) "
    "VALUES ('dirty1', 'gym1', 'loc1', 'Maria', 'MEMBER', 'walk-in signup', 0, 0, 1);",
  );

  raw.execute('PRAGMA user_version = 1;');
  return raw;
}

void main() {
  test('v1 -> v2 upgrade preserves rows, including dirty ones', () async {
    final raw = _buildV1Database(includeNewColumn: false);
    final executor = NativeDatabase.opened(raw);
    // Default rethrowMigrationErrors (true in test/debug) — this is the
    // happy path, addColumn should succeed and never hit the catch block.
    final db = AppDatabase.forTesting(executor);

    final allMembers = await db.select(db.members).get();

    expect(allMembers.length, 2, reason: 'both rows must survive the upgrade');
    final dirty = allMembers.firstWhere((m) => m.id == 'dirty1');
    expect(
      dirty.currentPlanCategory,
      isNull,
      reason: 'new column should exist and be null until next refresh',
    );

    await db.close();
  });

  test('recovery path rescues dirty rows when addColumn fails', () async {
    // v1 shape, but current_plan_category already present — this makes
    // the real addColumn in onUpgrade fail with "duplicate column",
    // forcing the catch block's rescue-and-recreate path to actually run.
    final raw = _buildV1Database(includeNewColumn: true);
    final executor = NativeDatabase.opened(raw);
    // rethrowMigrationErrors: false simulates release-build behavior —
    // flutter test always runs with kDebugMode true, so without this
    // override the error would rethrow before recovery ever executes.
    final db = AppDatabase.forTesting(executor, rethrowMigrationErrors: false);

    final allMembers = await db.select(db.members).get();

    // 1. The dirty row survived, with its fields intact.
    final dirty = allMembers.where((m) => m.id == 'dirty1').toList();
    expect(dirty.length, 1, reason: 'unsynced member must survive recovery');
    expect(dirty.first.notes, 'walk-in signup');
    expect(
      dirty.first.isDirty,
      isTrue,
      reason: 'must stay flagged dirty or the next refresh will delete it',
    );

    // 2. The synced row is gone — proves recovery actually ran (drop +
    // recreate), not that the migration quietly succeeded some other way.
    expect(
      allMembers.any((m) => m.id == 'synced1'),
      isFalse,
      reason: 'synced row loss confirms the drop-and-rescue path executed',
    );

    // 3. The partial unique index was rebuilt by the recovery path's
    // hand-written customStatement — a typo here wouldn't surface until
    // the first duplicate member_code insert, months later.
    final indexes = await executor.runSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index';",
      [],
    );
    final indexNames = indexes.map((row) => row['name'] as String).toList();
    expect(indexNames, contains('uniq_member_code_per_gym'));

    await db.close();
  });
}
