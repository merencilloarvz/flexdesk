import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/providers/pos_providers.dart';

/// Deliberately its own provider, separate from analytics_providers.dart
/// — a failure here must never affect the sales card or anything else on
/// Home (Stage 8, Part D). Reuses PosRepository rather than duplicating
/// the HTTP call, since it's the same /inventory/alerts/ endpoint the
/// Inventory screen already calls.
final lowStockAlertsProvider = FutureProvider.autoDispose<InventoryAlerts>((
  ref,
) {
  return ref.read(posRepositoryProvider).fetchInventoryAlerts();
});
