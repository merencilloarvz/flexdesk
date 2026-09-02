import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/utils/gym_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/dashboard_providers.dart';
import '../../members/providers/check_ins_provider.dart';
import '../../members/providers/members_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final authState = ref.read(authControllerProvider);
    if (authState is! AuthAuthenticated) return;
    final gymId = authState.user.gym.id;

    try {
      await ref.read(membersRepositoryProvider).refreshMembers(gymId);
      await ref
          .read(checkInsRepositoryProvider)
          .refreshCheckIns(gymId, day: GymTime.today());
      if (mounted) setState(() => _offline = false);
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        if (mounted) setState(() => _offline = true);
      }
      // Non-network errors are swallowed too, same as the offline case —
      // this is the landing screen, and the cached numbers underneath
      // are still correct and worth showing either way.
    } catch (_) {
      // Defensive: never let a refresh failure break the home tab.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = authState.user;
    final gymId = user.gym.id;
    final symbol = currencySymbol(user.gym.currency);
    final statsAsync = ref.watch(dashboardStatsProvider(gymId));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(user.gym.name)),
      body: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Something went wrong: $error')),
          data: (stats) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_offline) ...[
                  const Text(
                    'Offline — showing saved data',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                ],

                // Today's activity card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's activity",
                        style: TextStyle(fontSize: 13, color: AppColors.subtle),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${stats.checkInsToday}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const Text(
                        'checked in',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${stats.walkInsToday} walk-ins · '
                        '$symbol${centavosToDecimalString(stats.walkInCentavosToday)} collected',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Membership status row
                Row(
                  children: [
                    Expanded(
                      child: _StatusStat(
                        label: 'Active',
                        value: stats.activeMembers,
                        color: AppColors.activeBg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatusStat(
                        label: 'Expiring soon',
                        value: stats.expiringSoon,
                        color: AppColors.expiringBg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatusStat(
                        label: 'Expired',
                        value: stats.expiredMembers,
                        color: AppColors.expiredBg,
                      ),
                    ),
                  ],
                ),

                if (stats.pendingSync > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${stats.pendingSync} record${stats.pendingSync == 1 ? '' : 's'} '
                    'waiting to sync',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Quick actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.go('/checkin'),
                        child: const Text('Check In'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.go('/members'),
                        child: const Text('Members'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  const _StatusStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
