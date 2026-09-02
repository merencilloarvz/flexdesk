import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../members/providers/check_ins_provider.dart';
import '../../members/providers/members_providers.dart';

class DashboardStats {
  const DashboardStats({
    required this.activeMembers,
    required this.expiringSoon,
    required this.expiredMembers,
    required this.totalMembers,
    required this.checkInsToday,
    required this.walkInsToday,
    required this.walkInCentavosToday,
    required this.pendingSync,
  });

  final int activeMembers;
  final int expiringSoon;
  final int expiredMembers;
  final int totalMembers;
  final int checkInsToday;
  final int walkInsToday;
  final int walkInCentavosToday;
  final int pendingSync;
}

/// Derives every dashboard number from the same cached streams the
/// members list and check-in screen already watch — no separate SQL
/// aggregates. This is deliberate: two independent counts of "expiring"
/// (one here, one in the members list) would eventually disagree on a
/// boundary case, and an owner who catches that stops trusting either
/// number. Routing both through statusFor() makes disagreement
/// impossible instead of just unlikely.
final dashboardStatsProvider =
    Provider.family<AsyncValue<DashboardStats>, String>((ref, gymId) {
      final membersAsync = ref.watch(visibleMembersProvider(gymId));
      final checkInsAsync = ref.watch(
        checkInsForDayProvider(CheckInsDayArg(gymId, GymTime.today())),
      );

      if (membersAsync.hasError) {
        return AsyncValue.error(
          membersAsync.error!,
          membersAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (checkInsAsync.hasError) {
        return AsyncValue.error(
          checkInsAsync.error!,
          checkInsAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (!membersAsync.hasValue || !checkInsAsync.hasValue) {
        return const AsyncValue.loading();
      }

      final members = membersAsync.value!;
      final checkIns = checkInsAsync.value!;
      final today = GymTime.today();

      int activeMembers = 0;
      int expiringSoon = 0;
      int expiredMembers = 0;

      for (final m in members) {
        switch (statusFor(m.currentEndDate, today)) {
          case MembershipStatus.active:
            activeMembers++;
          case MembershipStatus.expiring:
            expiringSoon++;
          case MembershipStatus.expired:
            expiredMembers++;
          case MembershipStatus.noMembership:
            break; // counted in totalMembers only
        }
      }

      // Voided check-ins are excluded from every check-in number below —
      // filtered once, here, so all three numbers derive from the same
      // filtered list rather than each re-filtering separately.
      final nonVoided = checkIns.where((c) => c.voidedAt == null).toList();
      final walkIns = nonVoided.where((c) => c.visitType == 'WALKIN').toList();
      final walkInCentavosToday = walkIns.fold<int>(
        0,
        (sum, c) => sum + (c.amountChargedCentavos ?? 0),
      );

      // Dirty count across both lists. Note: checkIns here only covers today
      // (that's what checkInsForDayProvider watches), so a dirty check-in
      // from a previous day won't show up in this count. Acceptable for v1 —
      // that scenario means sync has been failing for over a day, which is a
      // bigger problem than an undercount here.
      final pendingSync =
          members.where((m) => m.isDirty).length +
          checkIns.where((c) => c.isDirty).length;

      return AsyncValue.data(
        DashboardStats(
          activeMembers: activeMembers,
          expiringSoon: expiringSoon,
          expiredMembers: expiredMembers,
          totalMembers: members.length,
          checkInsToday: nonVoided.length,
          walkInsToday: walkIns.length,
          walkInCentavosToday: walkInCentavosToday,
          pendingSync: pendingSync,
        ),
      );
    });
