import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

      // Partial unique index — Drift's `uniqueKeys` can't express a
      // WHERE clause, so this mirrors `uniq_member_code_per_gym`
      // (gym_id, member_code) WHERE member_code != '' as raw SQL.
      await customStatement(
        'CREATE UNIQUE INDEX uniq_member_code_per_gym '
        'ON members (gym_id, member_code) '
        "WHERE member_code != '';",
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 -> v2: added Members.currentPlanCategory (the Student/Regular
      // badge). A fresh nullable column, so a plain addColumn is enough —
      // existing rows just get NULL until the next refreshMembers() call
      // fills it in from the server.
      if (from < 2) {
        await m.addColumn(members, members.currentPlanCategory);
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
