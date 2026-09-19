import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../providers/members_providers.dart';

/// Full membership history for a single member — the same data the
/// "Membership History" card on Member Details shows a preview of, just
/// unbounded (every entry, not just what fits in the card).
class MembershipHistoryScreen extends ConsumerWidget {
  const MembershipHistoryScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(membershipHistoryProvider(memberId));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                  ),
                  const Text(
                    'Membership History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: historyAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const Center(
                        child: Text(
                          'No membership history yet.',
                          style: TextStyle(color: AppColors.subtle),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _HistoryCard(json: entries[index]),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text(
                      'History unavailable offline',
                      style: TextStyle(color: AppColors.subtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.json});

  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final planName =
        json['plan_name'] as String? ??
        (json['plan'] is Map ? json['plan']['name'] as String? : null) ??
        'Plan';
    final startDate = DateTime.tryParse(json['start_date'] as String? ?? '');
    final endDate = DateTime.tryParse(json['end_date'] as String? ?? '');
    final dateRange = startDate != null && endDate != null
        ? '${DateFormat('MMM d, yyyy').format(startDate)} – '
              '${DateFormat('MMM d, yyyy').format(endDate)}'
        : '';
    final pricePaid = double.tryParse(json['price_paid']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentTealBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.card_membership_outlined,
              size: 16,
              color: AppColors.accentTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (dateRange.isNotEmpty)
                  Text(
                    dateRange,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (pricePaid != null)
            Text(
              '₱${pricePaid.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accentTeal,
              ),
            ),
        ],
      ),
    );
  }
}
