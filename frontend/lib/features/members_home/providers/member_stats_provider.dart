import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/gym_time.dart';
import '../providers/me_providers.dart';

class MemberStats {
  const MemberStats({
    required this.streakDays,
    required this.checkInsThisMonth,
    required this.lastCheckInAt,
    required this.firstName,
    required this.fullName,
    required this.memberCode,
    required this.currentEndDate,
    this.planCategory,
    this.membershipStatus,
  });
  final int streakDays;
  final int checkInsThisMonth;
  final DateTime? lastCheckInAt;
  final String firstName;
  final String fullName;
  final String memberCode;
  final DateTime? currentEndDate;
  final String? planCategory;
  final String? membershipStatus;
}

final memberStatsProvider = FutureProvider<MemberStats>((ref) async {
  final api = ref.watch(meApiProvider);

  final summary = await api.fetchSummary();

  final allCheckIns = <Map<String, dynamic>>[];
  var page = 1;
  while (true) {
    final body = await api.fetchCheckInsPage(page);
    allCheckIns.addAll((body['results'] as List).cast<Map<String, dynamic>>());
    if (body['next'] == null) break;
    page++;
    if (page > 200) break;
  }

  final validCheckIns = allCheckIns
      .where((c) => c['voided_at'] == null)
      .toList();

  final checkInDates = validCheckIns
      .map((c) => DateTime.parse(c['checked_in_at'] as String).toLocal())
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet();

  final today = GymTime.today();

  var streak = 0;
  var cursor = today;
  if (!checkInDates.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while (checkInDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final monthStart = DateTime(today.year, today.month, 1);
  final checkInsThisMonth = validCheckIns.where((c) {
    final d = DateTime.parse(c['checked_in_at'] as String).toLocal();
    return !d.isBefore(monthStart);
  }).length;

  DateTime? lastCheckInAt;
  for (final c in validCheckIns) {
    final d = DateTime.parse(c['checked_in_at'] as String);
    if (lastCheckInAt == null || d.isAfter(lastCheckInAt)) lastCheckInAt = d;
  }

  // Field names guessed from backend conventions seen elsewhere
  // (snake_case JSON) — verify against the real /me/summary/ response.
  final fullName = summary['full_name'] as String? ?? '';
  final firstName = fullName.isEmpty ? '' : fullName.split(' ').first;
  final memberCode = summary['member_code'] as String? ?? '';
  final endDateStr = summary['current_end_date'] as String?;
  final currentEndDate = endDateStr != null
      ? DateTime.tryParse(endDateStr)
      : null;

  return MemberStats(
    streakDays: streak,
    checkInsThisMonth: checkInsThisMonth,
    lastCheckInAt: lastCheckInAt,
    firstName: firstName,
    fullName: fullName,
    memberCode: memberCode,
    currentEndDate: currentEndDate,
    planCategory: summary['current_plan_category'] as String?,
    membershipStatus: summary['membership_status'] as String?,
  );
});
