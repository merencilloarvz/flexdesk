import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/pos_api.dart';
import '../data/pos_repository.dart';

final posApiProvider = Provider<PosApi>((ref) {
  return PosApi(ref.watch(dioProvider));
});

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository(ref.watch(posApiProvider));
});
