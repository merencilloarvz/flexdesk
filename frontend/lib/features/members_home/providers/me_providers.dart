import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/me_api.dart';
import '../data/me_repository.dart';

final meApiProvider = Provider<MeApi>((ref) => MeApi(ref.watch(dioProvider)));

final meRepositoryProvider = Provider<MeRepository>(
  (ref) => MeRepository(ref.watch(meApiProvider)),
);
