import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/db/app_database.dart';
import '../data/members_api.dart';
import '../data/members_repository.dart';

final membersApiProvider = Provider<MembersApi>((ref) {
  return MembersApi(ref.watch(dioProvider));
});

final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  return MembersRepository(
    ref.watch(membersApiProvider),
    ref.watch(dbProvider),
  );
});

/// Live view of the cached member list for a given gym. The screen renders
/// from this instantly on open — including offline — while a refresh
/// (triggered directly from the screen via `membersRepositoryProvider`)
/// happens underneath.
final visibleMembersProvider = StreamProvider.family<List<Member>, String>((
  ref,
  gymId,
) {
  return ref.watch(membersRepositoryProvider).watchVisibleMembers(gymId);
});

/// Live view of a single member by id, from the local cache. The detail
/// screen watches this — same offline-first shape as visibleMembersProvider.
final memberByIdProvider = StreamProvider.family<Member?, String>((
  ref,
  memberId,
) {
  return ref.watch(membersRepositoryProvider).watchMemberById(memberId);
});

/// One-shot fetch of a member's membership history. This is a query, not
/// a command — unlike refreshMembers/archiveMember, a FutureProvider is
/// the right shape here, since .when() gives the detail screen its
/// loading/data/error states for free and there's no local isDirty
/// concern to manage by hand.
final membershipHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, memberId) {
      return ref.watch(membersRepositoryProvider).fetchMemberHistory(memberId);
    });
