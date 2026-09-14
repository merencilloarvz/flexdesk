import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'members_providers.dart';
import '../data/renewals_repository.dart';

final renewalsRepositoryProvider = Provider<RenewalsRepository>(
  (ref) => RenewalsRepository(ref.watch(membersApiProvider)),
);
