import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../providers/analytics_providers.dart';

String _formatPeso(double amount) {
  final formatter = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );
  return formatter.format(amount);
}

Color _activityColor(String type) {
  switch (type) {
    case 'member':
      return AppColors.accentTeal;
    case 'retail':
      return AppColors.categoryAmber;
    default:
      return AppColors.categoryTeal;
  }
}

IconData _activityIcon(String type) {
  switch (type) {
    case 'member':
      return Icons.card_membership_outlined;
    case 'retail':
      return Icons.shopping_bag_outlined;
    default:
      return Icons.directions_walk;
  }
}

/// "Today's Activity Log" — same graceful-degradation rule as
/// LowStockAlertCard: a loading/error state here must never disturb the
/// rest of the dashboard, so both collapse to nothing rather than show
/// a spinner or error banner. An empty-but-loaded feed still shows the
/// header with a plain "no activity yet" line, since that's a real
/// state (gym just opened), not a failure.
class ActivityLogCard extends ConsumerWidget {
  const ActivityLogCard({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activityLogProvider(gymId));

    return activitiesAsync.when(
      data: (activities) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Today's Activity Log",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fieldBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${activities.length} Latest',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.push('/sales-history'),
                  child: const Text(
                    'View All →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activities.isEmpty)
              const Text(
                'No activity recorded yet today.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              )
            else
              for (var i = 0; i < activities.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ActivityRow(activity: activities[i]),
              ],
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  final RecentActivity activity;

  @override
  Widget build(BuildContext context) {
    final color = _activityColor(activity.type);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_activityIcon(activity.type), size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              Text(
                activity.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatPeso(activity.amount),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
