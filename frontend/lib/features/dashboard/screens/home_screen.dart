import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/dashboard_providers.dart';
import '../../members/providers/check_ins_provider.dart';
import '../../members/providers/members_providers.dart';
import '../providers/analytics_providers.dart';
import '../widgets/sales_overview_card.dart';
import '../widgets/membership_mix_card.dart';
import '../widgets/low_stock_alert_card.dart';
import '../providers/low_stock_alerts_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _offline = false;
  DateTime? _lastResumeRefresh;

  // Someone alt-tabbing repeatedly must not hammer /auth/me/ — this only
  // throttles the automatic resume trigger below, never pull-to-refresh
  // or the initial load, both of which are an explicit ask for fresh data.
  static const _resumeRefreshCooldown = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final now = DateTime.now();
    if (_lastResumeRefresh != null &&
        now.difference(_lastResumeRefresh!) < _resumeRefreshCooldown) {
      return;
    }
    _lastResumeRefresh = now;
    _refresh();
  }

  Future<void> _refresh() async {
    final authState = ref.read(authControllerProvider);

    if (authState is! AuthAuthenticated) return;

    final gymId = authState.user.gym?.id ?? '';

    ref.invalidate(lowStockAlertsProvider);
    // Keyed by (gymId, range) and neither key changes on its own —
    // pull-to-refresh and resume are both an explicit ask for current
    // numbers, so both need to force it, same as after recording a
    // sale (see pos_screen.dart).
    ref.invalidate(analyticsProvider);

    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);

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
    final gymId = user.gym?.id ?? '';

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
            color: AppColors.accentTeal,
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
                      user.gym?.name ?? '',
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

                const _TrialCountdownBanner(),

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
                // SALES
                // ---------------------------------------------------------
                SalesOverviewCard(gymId: gymId),

                const SizedBox(height: 14),

                // ---------------------------------------------------------
                // TODAY'S CHECK-INS  +  SYNC STATUS
                // ---------------------------------------------------------
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _TodaysCheckInsCard(
                          totalToday: stats.checkInsToday,
                          walkInsToday: stats.walkInsToday,
                          onFastCheckIn: () => context.push('/checkin'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SyncStatusCard(
                          pendingCount: stats.pendingSync,
                          onSyncNow: _refresh,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ---------------------------------------------------------
                // LOW STOCK (Stage 8, Part D)
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

                _ManageGrid(
                  items: [
                    if (user.gym?.classesEnabled ?? false)
                      _ManageItem(
                        icon: Icons.calendar_month_outlined,
                        label: 'Schedule',
                        subtitle: 'Classes & bookings',
                        onTap: () => context.push('/schedule'),
                      ),
                    _ManageItem(
                      icon: Icons.campaign_outlined,
                      label: 'Announcements',
                      subtitle: 'Post updates',
                      onTap: () => context.push('/announcements'),
                    ),
                    _ManageItem(
                      icon: Icons.event_outlined,
                      label: 'Events',
                      subtitle: 'Competitions',
                      onTap: () => context.push('/events'),
                    ),
                    _ManageItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Manage Plans',
                      subtitle: 'Pricing & tiers',
                      onTap: () => context.push('/plans/manage'),
                    ),
                    _ManageItem(
                      icon: Icons.badge_outlined,
                      label: 'Staff',
                      subtitle: 'Accounts & roles',
                      onTap: () => context.push('/settings/staff'),
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

/// Neutral until it's actually urgent — hidden entirely outside the
/// trial, and outside the last 3 days of it. There's no need to also
/// watch for the blocked state here: once blocked, app_router redirects
/// away from /home altogether, so this card would never get the chance
/// to render for that case anyway.
class _TrialCountdownBanner extends ConsumerWidget {
  const _TrialCountdownBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    if (authState is! AuthAuthenticated) return const SizedBox.shrink();

    final gym = authState.user.gym;
    final trialEndsAt = gym?.trialEndsAt;
    if (gym == null || gym.subscriptionStatus != 'trialing' || trialEndsAt == null) {
      return const SizedBox.shrink();
    }

    final daysRemaining = trialEndsAt.difference(DateTime.now()).inDays;
    if (daysRemaining > 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: AppColors.expiringIcon,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/subscribe'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: AppColors.expiringBg,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    daysRemaining <= 0
                        ? 'Your free trial ends today — subscribe to keep going'
                        : 'Trial ends in $daysRemaining '
                              'day${daysRemaining == 1 ? '' : 's'} — subscribe to keep going',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.expiringBg,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.expiringBg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Left card — real today check-in counts, with a shortcut into
/// Check-In.
class _TodaysCheckInsCard extends StatelessWidget {
  const _TodaysCheckInsCard({
    required this.totalToday,
    required this.walkInsToday,
    required this.onFastCheckIn,
  });

  final int totalToday;
  final int walkInsToday;
  final VoidCallback onFastCheckIn;

  @override
  Widget build(BuildContext context) {
    final memberCheckIns = (totalToday - walkInsToday).clamp(0, totalToday);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accentTeal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.accentTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Today's Check-ins",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$totalToday',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1,
            ),
          ),
          const Text(
            'entries',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Members $memberCheckIns',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              Text(
                'Walk-ins $walkInsToday',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onFastCheckIn,
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text(
                'Fast Check-In',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Right card — button now shares the exact same FilledButton.icon
/// shape, padding, and solid-fill styling as Fast Check-In on the left,
/// instead of the lighter outlined/pill treatment it had before. Icon
/// and label swap between "Sync Now" (pending, enabled) and "Up to
/// date" (synced, disabled) — same button, same alignment either way.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.pendingCount, required this.onSyncNow});

  final int pendingCount;
  final Future<void> Function() onSyncNow;

  @override
  Widget build(BuildContext context) {
    final allSynced = pendingCount == 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  allSynced ? 'All synced' : '$pendingCount pending',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: allSynced ? AppColors.accentTeal : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                allSynced ? Icons.check_circle : Icons.cloud_sync_outlined,
                size: 17,
                color: allSynced ? AppColors.accentTeal : AppColors.subtle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            allSynced
                ? 'Every record is saved and verified on cloud.'
                : 'Records waiting for a connection.',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: allSynced ? null : onSyncNow,
              icon: Icon(allSynced ? Icons.check : Icons.sync, size: 16),
              label: Text(
                allSynced ? 'Up to date' : 'Sync Now',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.accentTeal,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
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
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
}

class _ManageGrid extends StatelessWidget {
  const _ManageGrid({required this.items});

  final List<_ManageItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                height: cardWidth / 1.55,
                child: _ManageCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({required this.item});

  final _ManageItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accentTealBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      item.icon,
                      size: 17,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
