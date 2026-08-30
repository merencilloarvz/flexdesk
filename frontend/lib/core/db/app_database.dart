import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Members, MembershipPlans])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Lets tests (and the smoke-test script) pass NativeDatabase.memory()
  // directly, bypassing path_provider — which needs Flutter bindings this
  // constructor's caller may not have set up.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX uniq_member_code_per_gym '
        'ON members (gym_id, member_code) '
        "WHERE member_code != '';",
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      try {
        // v1 -> v2: added Members.currentPlanCategory (the Student/Regular
        // badge). A fresh nullable column, so a plain addColumn is enough —
        // existing rows just get NULL until the next refreshMembers() call
        // fills it in from the server.
        if (from < 2) {
          await m.addColumn(members, members.currentPlanCategory);
        }
      } catch (e) {
        if (kDebugMode)
          rethrow; // fail loudly while building, never hide a real bug from yourself

        // Recovery path for release builds only. Not all local rows are a
        // re-downloadable cache — rows with isDirty:true (offline-created
        // members never synced to the server) are the ONLY copy that
        // exists. Rescue those before dropping anything.
        List<Map<String, dynamic>> rescued = [];
        try {
          final rows = await customSelect(
            'SELECT * FROM members WHERE is_dirty = 1',
          ).get();
          rescued = rows.map((r) => r.data).toList();
        } catch (_) {
          // If even reading failed, the table is too damaged to rescue from.
          // Fall through to the drop — losing dirty rows here is a last
          // resort, not the default path.
        }

        await m.deleteTable('members');
        await m.deleteTable('membership_plans');
        await m.createAll();
        await customStatement(
          'CREATE UNIQUE INDEX uniq_member_code_per_gym '
          'ON members (gym_id, member_code) '
          "WHERE member_code != '';",
        );

        // Best-effort re-insert. A row missing a field it used to have is
        // recoverable; a missing member is not — so one bad row must never
        // stop the rest from going back in.
        for (final row in rescued) {
          try {
            await into(members).insert(
              MembersCompanion.insert(
                id: row['id'] as String,
                gymId: row['gym_id'] as String,
                homeLocationId: row['home_location_id'] as String,
                firstName: row['first_name'] as String,
                memberType: row['member_type'] as String,
                createdAt: DateTime.fromMillisecondsSinceEpoch(
                  (row['created_at'] as int) * 1000,
                ),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  (row['updated_at'] as int) * 1000,
                ),
                memberCode: Value(row['member_code'] as String? ?? ''),
                lastName: Value(row['last_name'] as String? ?? ''),
                phone: Value(row['phone'] as String? ?? ''),
                email: Value(row['email'] as String? ?? ''),
                notes: Value(row['notes'] as String? ?? ''),
                isDirty: const Value(true), // still unsynced, keep flagged
              ),
              mode: InsertMode.insertOrReplace,
            );
          } catch (_) {
            // Skip this one row rather than aborting the whole recovery.
          }
        }
      }
    },
  );
  // Every query in this app should filter on gymId. A shared front-desk
  // tablet that has logged into two gyms will hold rows for both — the
  // gymId filter is the only thing keeping them apart locally.
  //
  // Ordered to match the backend (first_name, last_name) — otherwise row
  // order is whatever SQLite returns, which can reshuffle between reads
  // for no visible reason.
  Future<List<Member>> visibleMembers(String gymId) {
    return (select(members)
          ..where((m) => m.gymId.equals(gymId) & m.archivedAt.isNull())
          ..orderBy([
            (m) => OrderingTerm(expression: m.firstName),
            (m) => OrderingTerm(expression: m.lastName),
          ]))
        .get();
  }

  // Excludes inactive plans by default and orders like the backend
  // (sort_order, category, name) — a plan picker showing a deactivated
  // plan is a real front-desk error, not just a cosmetic mismatch. Pass
  // includeInactive: true for screens that manage plans themselves.
  Future<List<MembershipPlan>> plansForGym(
    String gymId, {
    bool includeInactive = false,
  }) {
    final query = select(membershipPlans)
      ..where((p) {
        final gymMatch = p.gymId.equals(gymId);
        return includeInactive ? gymMatch : gymMatch & p.isActive.equals(true);
      })
      ..orderBy([
        (p) => OrderingTerm(expression: p.sortOrder),
        (p) => OrderingTerm(expression: p.category),
        (p) => OrderingTerm(expression: p.name),
      ]);
    return query.get();
  }
}

LazyDatabase _openConnection() {
  // Background isolate so a large sync doesn't jank the UI.
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'flexdesk.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
