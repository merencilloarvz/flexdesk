import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/qr_secret_storage.dart';
import '../data/qr_card_repository.dart';
import 'me_providers.dart';

final qrCardRepositoryProvider = Provider<QrCardRepository>(
  (ref) => QrCardRepository(
    ref.watch(meApiProvider),
    ref.watch(qrSecretStorageProvider),
  ),
);
