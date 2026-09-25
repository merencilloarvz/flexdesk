import 'dart:async';

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
import '../widgets/activity_log_card.dart';
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

  // Real instant of the last successful refresh. In-memory only: it
  // resets on a cold start, and the first refresh after launch sets it.
  DateTime? _lastSyncedAt;
  bool _syncing = false;

  // Re-renders the greeting clock and "Last synced X ago" once a minute;
  // both are derived from the wall clock and would otherwise go stale.
  Timer? _tick;

  // Someone alt-tabbing repeatedly must not hammer /auth/me/ — this only
  // throttles the automatic resume trigger below, never pull-to-refresh
  // or the initial load, both of which are an explicit ask for fresh data.
  static const _resumeRefreshCooldown = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      ref.invalidate(gymTodayProvider);
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // A backgrounded app can sleep through gym midnight.
    ref.invalidate(gymTodayProvider);

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

    if (mounted) setState(() => _syncing = true);

    ref.invalidate(lowStockAlertsProvider);
    // Keyed by (gymId, range) and neither key changes on its own —
    // pull-to-refresh and resume are both an explicit ask for current
    // numbers, so both need to force it, same as after recording a
    // sale (see pos_screen.dart).
    ref.invalidate(analyticsProvider);
    ref.invalidate(activityLogProvider);

    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);

      await ref.read(membersRepositoryProvider).refreshMembers(gymId);

      await ref
          .read(checkInsRepositoryProvider)
          .refreshCheckIns(gymId, day: ref.read(gymTodayProvider));

      if (mounted) {
        setState(() {
          _offline = false;
          _lastSyncedAt = DateTime.now();
        });
      }
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        if (mounted) {
          setState(() => _offline = true);
        }
      }
    } catch (_) {
      // Defensive: never let a refresh failure break the home tab.
    } finally {
      if (mounted) setState(() => _syncing = false);
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

    // New gym-local day: pull the new day's check-ins and analytics.
    ref.listen(gymTodayProvider, (prev, next) {
      if (prev != null && prev != next) _refresh();
    });

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
              // AppShell floats its nav bar over the body (extendBody), and the
              // Scaffold reports that bar's height in MediaQuery's bottom
              // padding, so this clears it on any screen or gesture-nav.
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              children: [
                // ---------------------------------------------------------
                // HEADER
                // ---------------------------------------------------------
                _GreetingHeader(
                  fullName: user.fullName,
                  now: GymTime.now(),
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
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ],

                const _TrialCountdownBanner(),
                _RenewalsBanner(count: stats.expiringSoon),

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
                // TODAY'S ACTIVITY LOG
                // ---------------------------------------------------------
                ActivityLogCard(gymId: gymId),

                const SizedBox(height: 14),

                // ---------------------------------------------------------
                // TODAY'S CHECK-INS  +  SYNC STATUS (one card)
                // ---------------------------------------------------------
                _CheckInSyncCard(
                  totalToday: stats.checkInsToday,
                  walkInsToday: stats.walkInsToday,
                  pendingCount: stats.pendingSync,
                  lastSyncedAt: _lastSyncedAt,
                  syncing: _syncing,
                  onFastCheckIn: () => context.push('/checkin'),
                  onSyncNow: _refresh,
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
    if (gym == null ||
        gym.subscriptionStatus != 'trialing' ||
        trialEndsAt == null) {
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

/// Phase 5 B3 — "the count belongs on Home ... so it's seen without
/// opening the screen." Derived from the same dashboardStatsProvider
/// the Membership Mix card already watches (statusFor() over the
/// locally-cached member list — see that provider's own doc comment
/// on why every "expiring" count in the app routes through one place)
/// rather than a fresh fetch of its own; hidden entirely when there's
/// nothing to chase, same as the trial banner above it.
class _RenewalsBanner extends StatelessWidget {
  const _RenewalsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/renewals'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Icon(
                  Icons.event_repeat_outlined,
                  size: 18,
                  color: AppColors.accentTeal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$count membership${count == 1 ? '' : 's'} expiring '
                    'this week',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.fullName, required this.now});

  final String fullName;

  /// Gym-local wall clock ([GymTime.now]) — never the device clock.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    final greeting = GymTime.greetingFor(now);

    return Text(
      first.isEmpty ? greeting : '$greeting, $first',
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: AppColors.ink,
      ),
    );
  }
}

/// "Last synced X ago" for a real instant; null means no refresh has
/// succeeded yet this session.
String lastSyncedLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Not synced yet';
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'Last synced just now';
  if (diff.inMinutes < 60) return 'Last synced ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Last synced ${diff.inHours} h ago';
  return 'Last synced ${diff.inDays} d ago';
}

/// Today's check-ins and sync status in one card: counts and sync pill on
/// top, Fast check-in, then a footer with last-synced time and Sync now.
class _CheckInSyncCard extends StatelessWidget {
  const _CheckInSyncCard({
    required this.totalToday,
    required this.walkInsToday,
    required this.pendingCount,
    required this.lastSyncedAt,
    required this.syncing,
    required this.onFastCheckIn,
    required this.onSyncNow,
  });

  final int totalToday;
  final int walkInsToday;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final bool syncing;
  final VoidCallback onFastCheckIn;
  final Future<void> Function() onSyncNow;

  @override
  Widget build(BuildContext context) {
    final memberCheckIns = (totalToday - walkInsToday).clamp(0, totalToday);
    final allSynced = pendingCount == 0;
    final pillColor = allSynced ? AppColors.accentTeal : AppColors.expiringBg;
    final synced = lastSyncedLabel(lastSyncedAt, DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Check-ins today',
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
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Members $memberCheckIns · Walk-ins $walkInsToday',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: pillColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      allSynced
                          ? Icons.check_circle
                          : Icons.cloud_sync_outlined,
                      size: 13,
                      color: pillColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      allSynced ? 'All synced' : '$pendingCount pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pillColor,
                      ),
                    ),
                  ],
                ),
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
                'Fast check-in',
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
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: AppColors.fieldBg),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  allSynced ? synced : '$synced · waiting for connection',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
              TextButton.icon(
                onPressed: syncing ? null : onSyncNow,
                icon: syncing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 14),
                label: const Text(
                  'Sync now',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentTeal,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
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

/// One card holding a compact row of icon buttons, four across. Extra
/// items wrap onto the next row starting at the left (like phone home
/// screen icons): every cell has the same fixed width, so nothing is
/// centered or stretched.
class _ManageGrid extends StatelessWidget {
  const _ManageGrid({required this.items});

  final List<_ManageItem> items;

  static const _perRow = 4;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth =
              (constraints.maxWidth - _gap * (_perRow - 1)) / _perRow;
          return Wrap(
            alignment: WrapAlignment.start,
            spacing: _gap,
            runSpacing: 12,
            children: [
              for (final item in items)
                SizedBox(
                  width: cellWidth,
                  child: _ManageButton(item: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.item});

  final _ManageItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${item.label}, ${item.subtitle}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, size: 26, color: AppColors.accentTeal),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
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
