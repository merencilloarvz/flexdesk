import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/community_api.dart';
import '../data/community_repository.dart';

final communityApiProvider = Provider<CommunityApi>(
  (ref) => CommunityApi(ref.watch(dioProvider)),
);

final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => CommunityRepository(ref.watch(communityApiProvider)),
);
