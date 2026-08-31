import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_api.dart';
import '../data/staff_models.dart';
import '../data/staff_repository.dart';

// ⚠️ ASSUMPTION: I don't have your dio_client.dart / api provider file,
// so I'm guessing the provider that hands out your shared Dio instance
// is called `dioProvider`, from core/api/dio_client.dart — that's the
// standard name/location for it in this kind of setup. If your app
// doesn't compile on this line, open dio_client.dart, find the actual
// provider name, and swap it in here.
import '../../../core/api/dio_client.dart';

final staffApiProvider = Provider<StaffApi>((ref) {
  return StaffApi(ref.watch(dioProvider));
});

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(staffApiProvider));
});

/// Fetches the staff list from the network whenever this is watched.
/// After create/deactivate, call `ref.invalidate(staffListProvider)`
/// to make the list screen refetch and show the change.
final staffListProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).fetchStaff();
});
