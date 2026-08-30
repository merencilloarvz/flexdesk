import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/db/app_database.dart';
import '../data/plans_api.dart';
import '../data/plans_repository.dart';

final plansApiProvider = Provider<PlansApi>((ref) {
  return PlansApi(ref.watch(dioProvider));
});

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  return PlansRepository(ref.watch(plansApiProvider), ref.watch(dbProvider));
});

/// Live view of the cached, active plans for a given gym. Used by the
/// member-create and (future) renew pickers.
final activePlansProvider = StreamProvider.family<List<MembershipPlan>, String>(
  (ref, gymId) {
    return ref.watch(plansRepositoryProvider).watchActivePlans(gymId);
  },
);

/// Live view of every cached plan (active or not) for a given gym. Used
/// by the manage-plans screen.
final allPlansProvider = StreamProvider.family<List<MembershipPlan>, String>((
  ref,
  gymId,
) {
  return ref.watch(plansRepositoryProvider).watchAllPlans(gymId);
});
