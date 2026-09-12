import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../pos/screens/inventory_screen.dart';
import '../providers/low_stock_alerts_provider.dart';

/// Low-stock block for the owner dashboard. Renders nothing at all —
/// not a spinner, not an error banner, not a "not available"
/// placeholder — in every case except "there's a specific item that
/// needs attention right now":
///
/// - Nothing low or out            -> empty slot, not a congratulatory
///   card. The dashboard is dense already.
/// - Still loading                 -> empty slot, no flicker of a
///   skeleton for a low-priority secondary card.
/// - Offline / fetch failed        -> empty slot, no error. This has
///   its own error boundary on purpose: a failure here must never
///   affect the sales card or anything else on Home.
///
/// Stage 9: restyled to be more minimal — the header dropped its own
/// tinted icon container (it now sits inline, plain), and each row
/// dropped its filled pill in favor of small colored text. Out-of-stock
/// vs low-stock is still distinguishable by the words themselves ("Out
/// of stock" vs "N left"), not just by color — that's unchanged.
class LowStockAlertCard extends ConsumerWidget {
  const LowStockAlertCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(lowStockAlertsProvider);

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.lowStockCount == 0 && alerts.outOfStockCount == 0) {
          return const SizedBox.shrink();
        }

        // Alerts.items already comes worst-first, capped at 5 by the
        // backend — this card only ever shows the top 3 of those.
        final worst = alerts.items.take(3).toList();

        return Material(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const InventoryScreen())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: AppColors.subtle,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Stock needs attention',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: AppColors.border),
                  for (final item in worst)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: item.state == 'critical'
                                  ? AppColors.expiredBg
                                  : AppColors.expiringBg,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            item.state == 'critical'
                                ? 'Out of stock'
                                : '${item.stockQuantity} left',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: item.state == 'critical'
                                  ? AppColors.expiredBg
                                  : AppColors.expiringBg,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
