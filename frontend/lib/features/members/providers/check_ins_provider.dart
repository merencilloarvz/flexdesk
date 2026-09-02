import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/db/app_database.dart';
import '../../members/providers/members_providers.dart';
import '../data/check_ins_api.dart';
import '../data/check_ins_repository.dart';

final checkInsApiProvider = Provider<CheckInsApi>((ref) {
  return CheckInsApi(ref.watch(dioProvider));
});

final checkInsRepositoryProvider = Provider<CheckInsRepository>((ref) {
  return CheckInsRepository(
    ref.watch(checkInsApiProvider),
    ref.watch(dbProvider),
    ref.watch(membersRepositoryProvider),
  );
});

/// Family key for [checkInsForDayProvider] — equality is by calendar date
/// only (year/month/day), not the exact DateTime instant, so re-watching
/// with a DateTime that differs only in time-of-day doesn't spawn a
/// duplicate stream subscription.
class CheckInsDayArg {
  const CheckInsDayArg(this.gymId, this.day);
  final String gymId;
  final DateTime day;

  @override
  bool operator ==(Object other) =>
      other is CheckInsDayArg &&
      other.gymId == gymId &&
      other.day.year == day.year &&
      other.day.month == day.month &&
      other.day.day == day.day;

  @override
  int get hashCode => Object.hash(gymId, day.year, day.month, day.day);
}

/// Live view of a gym-local day's check-ins from the local cache. Renders
/// instantly, including offline, while a refresh (triggered directly from
/// the screen) happens underneath — same pattern as visibleMembersProvider.
final checkInsForDayProvider =
    StreamProvider.family<List<CheckIn>, CheckInsDayArg>((ref, arg) {
      return ref
          .watch(checkInsRepositoryProvider)
          .watchCheckIns(arg.gymId, arg.day);
    });
