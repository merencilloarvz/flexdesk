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
import '../widgets/sales_overview_card.dart';
import '../widgets/membership_mix_card.dart';
import '../widgets/low_stock_alert_card.dart';
import '../providers/low_stock_alerts_provider.dart';

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

    // The low-stock card's provider is separate from everything else
    // refreshed here (own error boundary — see LowStockAlertCard's
    // docstring), so it's invalidated on its own rather than folded
    // into the try/catch below. Home stays alive in memory when you
    // switch tabs (it isn't rebuilt from scratch), so without this the
    // card would keep showing whatever it first loaded until the app
    // is fully restarted — pulling to refresh here is what picks up a
    // stock change made from Inventory.
    ref.invalidate(lowStockAlertsProvider);

    try {
      await ref.read(membersRepositoryProvider).refreshMembers(gymId);

      await ref
          .read(checkInsRepositoryProvider)
          .refreshCheckIns(gymId, day: GymTime.today());

      if (mounted) {
        setState(() => _offline = false);
      }
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        if (mounted) {
          setState(() => _offline = true);
        }
      }
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
      body: SafeArea(
        bottom: false,
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Something went wrong: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (stats) => RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.accentBlue,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
              children: [
                // ---------------------------------------------------------
                // HEADER
                // ---------------------------------------------------------
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GOOD MORNING',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppColors.subtle,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      user.gym.name,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColors.ink,
                      ),
                    ),

                    if (_offline) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            'Offline — showing saved data',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 20),

                // ---------------------------------------------------------
                // MEMBERSHIP MIX
                // ---------------------------------------------------------
                MembershipMixCard(
                  active: stats.activeMembers,
                  expiring: stats.expiringSoon,
                  expired: stats.expiredMembers,
                ),
                const SizedBox(height: 14),

                // ---------------------------------------------------------
                // TODAY'S ACTIVITY
                // ---------------------------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatCard(
                        icon: Icons.login_rounded,
                        value: '${stats.checkInsToday}',
                        label: 'Checked in today',
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _MiniStatCard(
                        icon: Icons.confirmation_number_outlined,
                        value: '${stats.walkInsToday}',
                        label:
                            'Day Pass · $symbol${centavosToDecimalString(stats.walkInCentavosToday)} collected',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ---------------------------------------------------------
                // SALES
                // ---------------------------------------------------------
                SalesOverviewCard(gymId: gymId),

                // ---------------------------------------------------------
                // SYNC
                // ---------------------------------------------------------
                if (stats.pendingSync > 0) ...[
                  const SizedBox(height: 14),
                  _SyncBanner(count: stats.pendingSync, onSyncNow: _refresh),
                ],

                const SizedBox(height: 24),

                // ---------------------------------------------------------
                // LOW STOCK (Stage 8, Part D)
                //
                // Replaces the old Check In / Members quick-action
                // buttons — both became redundant once 7.3 moved Check In
                // to the raised center FAB and Members to its own nav
                // tab, one tap away from anywhere. Renders nothing at
                // all when there's nothing low or out; see
                // LowStockAlertCard's docstring for the full reasoning.
                // ---------------------------------------------------------
                const LowStockAlertCard(),

                const SizedBox(height: 24),

                // ---------------------------------------------------------
                // MANAGE
                // ---------------------------------------------------------
                const Text(
                  'MANAGE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.subtle,
                  ),
                ),

                const SizedBox(height: 9),

                _ManageGroup(
                  items: [
                    if (user.gym.classesEnabled)
                      _ManageItem(
                        icon: Icons.calendar_month_outlined,
                        label: 'Schedule',
                        onTap: () => context.push('/schedule'),
                      ),
                    _ManageItem(
                      icon: Icons.campaign_outlined,
                      label: 'Announcements',
                      onTap: () => context.push('/announcements'),
                    ),
                    _ManageItem(
                      icon: Icons.event_outlined,
                      label: 'Events',
                      onTap: () => context.push('/events'),
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

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accentBlueBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: AppColors.accentBlue),
          ),

          const SizedBox(height: 10),

          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1,
              color: AppColors.ink,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1.25,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.count, required this.onSyncNow});

  final int count;
  final Future<void> Function() onSyncNow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentBlueBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync, size: 18, color: AppColors.accentBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count record${count == 1 ? '' : 's'} waiting to sync',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.accentBlue,
              ),
            ),
          ),
          Material(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onSyncNow,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.accentBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Sync now',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentBlue,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageItem {
  const _ManageItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ManageGroup extends StatelessWidget {
  const _ManageGroup({required this.items});

  final List<_ManageItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _ManageRow(item: items[i]),
            if (i != items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({required this.item});

  final _ManageItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentBlueBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 17, color: AppColors.accentBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accentBlue,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
