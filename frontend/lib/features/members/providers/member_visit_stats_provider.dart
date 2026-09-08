import 'package:drift/drift.dart'
    show OrderingTerm, OrderingMode, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/gym_time.dart';

class MemberVisitStats {
  const MemberVisitStats({
    required this.visitsThisMonth,
    required this.lastCheckInAt,
  });
  final int visitsThisMonth;
  final DateTime? lastCheckInAt;
}

/// Derives both numbers from ONE watch of the member's own non-voided
/// check-ins, so "visits this month" and "last in" are guaranteed to
/// come from the same underlying rows — same reasoning
/// dashboardStatsProvider already uses for its own numbers.
final memberVisitStatsProvider =
    StreamProvider.family<MemberVisitStats, String>((ref, memberId) {
      final db = ref.watch(dbProvider);

      final today = GymTime.today();
      final monthStart = DateTime(today.year, today.month, 1);
      final monthEndExclusive = today.month == 12
          ? DateTime(today.year + 1, 1, 1)
          : DateTime(today.year, today.month + 1, 1);
      final rangeStart = GymTime.startOfDay(monthStart);
      final rangeEnd = GymTime.startOfDay(monthEndExclusive);

      return (db.select(db.checkIns)
            ..where((c) => c.memberId.equals(memberId) & c.voidedAt.isNull())
            ..orderBy([
              (c) => OrderingTerm(
                expression: c.checkedInAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch()
          .map((rows) {
            final visitsThisMonth = rows
                .where(
                  (r) =>
                      !r.checkedInAt.isBefore(rangeStart) &&
                      r.checkedInAt.isBefore(rangeEnd),
                )
                .length;
            final lastCheckInAt = rows.isNotEmpty
                ? rows.first.checkedInAt
                : null;
            return MemberVisitStats(
              visitsThisMonth: visitsThisMonth,
              lastCheckInAt: lastCheckInAt,
            );
          });
    });
