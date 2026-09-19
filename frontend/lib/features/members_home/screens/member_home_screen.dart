import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/last_visit_label.dart';
import '../../../core/utils/member_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../../community/data/community_repository.dart';
import '../../community/providers/community_providers.dart';
import '../../community/screens/member/member_event_detail_screen.dart';
import '../../community/widgets/event_card.dart';
import '../../shell/app_shell.dart';
import '../providers/member_stats_provider.dart';
import '../widgets/member_pass_style.dart';
import '../widgets/membership_status_badge.dart';

/// The next few events worth showing on the home screen: not cancelled,
/// not already past (today still counts), soonest first, at most [limit].
List<Event> upcomingEvents(List<Event> all, DateTime today, {int limit = 2}) {
  final day = DateTime(today.year, today.month, today.day);
  final upcoming = all
      .where((e) => !e.isCanceled && !e.eventDate.isBefore(day))
      .toList()
    ..sort((a, b) {
      final byDate = a.eventDate.compareTo(b.eventDate);
      if (byDate != 0) return byDate;
      // Same day: earlier start first; no start time sorts last.
      return (a.startTime ?? '99').compareTo(b.startTime ?? '99');
    });
  return upcoming.take(limit).toList();
}

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen>
    with WidgetsBindingObserver {
  List<Event>? _upcoming;
  bool _eventsFailed = false;
  DateTime? _lastResumeRefresh;

  // Same reasoning and cooldown as HomeScreen's resume refresh — this is
  // the fix for a member never learning their gym turned Classes on
  // (or off) until they log out and back in. Only throttles the
  // automatic resume trigger, never an explicit pull-to-refresh.
  static const _resumeRefreshCooldown = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchEvents();
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
    _refreshSession();
  }

  Future<void> _refreshSession() async {
    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
    } catch (_) {
      // Swallow — a stale session is better than a logged-out one.
      // Network failures and malformed responses both just mean this
      // device keeps whatever it already had until the next chance.
    }
  }

  Future<void> _fetchEvents() async {
    try {
      final events = await ref.read(communityRepositoryProvider).fetchEvents();
      if (!mounted) return;
      setState(() {
        _upcoming = upcomingEvents(events, GymTime.today());
        _eventsFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _eventsFailed = true);
    }
  }

  void _patchEventLikes(String id, LikeState like) {
    final list = _upcoming;
    if (!mounted || list == null) return;
    setState(() {
      _upcoming = [
        for (final e in list)
          e.id == id
              ? e.withEngagement(
                  likeCount: like.likeCount,
                  likedByMe: like.likedByMe,
                )
              : e,
      ];
    });
  }

  Future<void> _openEvent(Event event) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEventDetailScreen(eventId: event.id),
      ),
    );
    // Registration, likes and comments may have changed over there.
    _fetchEvents();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (authState is! AuthAuthenticated) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentTeal),
        ),
      );
    }
    final user = authState.user;
    final classesEnabled = user.gym?.classesEnabled ?? false;
    final statsAsync = ref.watch(memberStatsProvider);
    final today = GymTime.today();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: statsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentTeal),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.errorText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load member info: $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.subtle),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(memberStatsProvider),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentTeal,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (stats) {
            final status = statusFor(stats.currentEndDate, today);
            final daysLeft = daysRemaining(stats.currentEndDate, today);
            final userFirst = user.fullName.split(' ').first;
            final firstName = stats.firstName.isNotEmpty
                ? stats.firstName
                : (userFirst.isNotEmpty ? userFirst : 'Member');
            final fullName = stats.fullName.isNotEmpty
                ? stats.fullName
                : (user.fullName.isNotEmpty ? user.fullName : 'Member');

            return RefreshIndicator(
              color: AppColors.accentTeal,
              onRefresh: () async {
                await _refreshSession();
                ref.invalidate(memberStatsProvider);
                await _fetchEvents();
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  AppShell.reservedNavHeight + 24,
                ),
                children: [
                  _Header(
                    firstName: firstName,
                    gymName: user.gym?.name ?? '',
                    onProfileTap: () => context.go('/member-settings'),
                  ),
                  const SizedBox(height: 16),

                  // Phase 5 Part C — membership renewal banner, above the
                  // card per S3. Derived from the same stats; only ever
                  // shows for an expiring or expired membership.
                  _MembershipBanner(status: status, daysLeft: daysLeft),

                  _MemberPassCard(
                    gymName: user.gym?.name ?? '',
                    planName: stats.planCategory,
                    fullName: fullName,
                    memberCode: stats.memberCode,
                    validThru: stats.currentEndDate,
                  ),
                  const SizedBox(height: 14),

                  _QuickEntryCard(onTap: () => context.push('/me/card')),
                  const SizedBox(height: 14),

                  _StatsRow(
                    status: status,
                    daysLeft: daysLeft,
                    endDate: stats.currentEndDate,
                    visitsThisMonth: stats.checkInsThisMonth,
                    lastVisit: lastVisitLabel(stats.lastCheckInAt, today),
                    onPassTap: () => context.push('/me/membership'),
                  ),
                  const SizedBox(height: 14),

                  _ActionButtons(
                    // Classes are off by default and the Schedule tab
                    // doesn't exist then, so the button goes away entirely
                    // (History takes the whole row) rather than leading to
                    // a feature this gym doesn't use.
                    showBookClass: classesEnabled,
                    onBookClass: () => context.go('/member-schedule'),
                    onHistory: () => context.push('/me/attendance'),
                  ),
                  const SizedBox(height: 24),

                  _UpcomingEventsSection(
                    events: _upcoming,
                    failed: _eventsFailed,
                    onRetry: _fetchEvents,
                    onViewAll: () => context.go('/member-community'),
                    onOpenEvent: _openEvent,
                    onToggleLike: (e) => ref
                        .read(communityRepositoryProvider)
                        .toggleLike(CommunityItemType.event, e.id),
                    onLikeChanged: _patchEventLikes,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.cardBg,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.firstName,
    required this.gymName,
    required this.onProfileTap,
  });

  final String firstName;
  final String gymName;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.15,
                ),
              ),
              if (gymName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  gymName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.subtle,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          container: true,
          button: true,
          excludeSemantics: true,
          label: 'Profile and settings',
          child: InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accentTealBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBg, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentTeal,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 5 Part C — membership renewal banner
// ---------------------------------------------------------------------------

/// C3's tone requirement is the whole point of this widget: plain,
/// factual, no urgency language, no countdown, no red — a neutral gray
/// card that reads like information, not a warning. Dismissible for
/// the session only (C2) — in-memory State, never persisted, so it
/// comes back next time the screen mounts because the situation is
/// still true.
class _MembershipBanner extends StatefulWidget {
  const _MembershipBanner({required this.status, required this.daysLeft});

  final MembershipStatus status;
  final int? daysLeft;

  @override
  State<_MembershipBanner> createState() => _MembershipBannerState();
}

class _MembershipBannerState extends State<_MembershipBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (widget.status != MembershipStatus.expiring &&
        widget.status != MembershipStatus.expired) {
      return const SizedBox.shrink();
    }

    final String message;
    if (widget.status == MembershipStatus.expired) {
      message = 'Your membership has expired — talk to the front desk';
    } else if (widget.daysLeft == 0) {
      message = 'Your membership ends today';
    } else {
      final d = widget.daysLeft ?? 0;
      message =
          'Your membership ends in $d ${d == 1 ? 'day' : 'days'} — talk '
          'to the front desk to renew';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.fieldBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.subtle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => _dismissed = true),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member pass (hero card)
// ---------------------------------------------------------------------------

class _MemberPassCard extends StatelessWidget {
  const _MemberPassCard({
    required this.gymName,
    required this.planName,
    required this.fullName,
    required this.memberCode,
    required this.validThru,
  });

  final String gymName;
  final String? planName;
  final String fullName;
  final String memberCode;
  final DateTime? validThru;

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.accentTealBg.withValues(alpha: 0.7),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: memberPassGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: MemberPassRingsPainter())),
          Padding(
            padding: const EdgeInsets.all(20),
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
                          Text(
                            gymName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                              color: Colors.white,
                            ),
                          ),
                          if (planName != null && planName!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              planName!.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppColors.accentGreen,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Text(
                        'MEMBER PASS',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  fullName.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: memberCode.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('MEMBER ID', style: label),
                                const SizedBox(height: 2),
                                Text(
                                  memberCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('VALID THRU', style: label),
                        const SizedBox(height: 2),
                        Text(
                          validThru != null
                              ? DateFormat('MM/yy').format(validThru!)
                              : 'NO ACTIVE PLAN',
                          style: TextStyle(
                            fontSize: validThru != null ? 15 : 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick entry
// ---------------------------------------------------------------------------

/// Opens the member's digital check-in card (`/me/card`): the rotating QR
/// code that front-desk staff scan to check them in. The member doesn't
/// scan anything themselves — the scanner lives on the staff side — so
/// this says what actually happens.
class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  size: 28,
                  color: AppColors.accentTeal,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Show QR to Check In',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Your code refreshes automatically — staff scan it at '
                      'the front desk.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.subtle,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.fieldBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.subtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats row
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.status,
    required this.daysLeft,
    required this.endDate,
    required this.visitsThisMonth,
    required this.lastVisit,
    required this.onPassTap,
  });

  final MembershipStatus status;
  final int? daysLeft;
  final DateTime? endDate;
  final int visitsThisMonth;
  final String lastVisit;
  final VoidCallback onPassTap;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');

    // Big number + unit, and the line under it, per state. Days come from
    // daysRemaining() (0 = the last valid day, still active).
    final String value;
    final String unit;
    final String detail;
    switch (status) {
      case MembershipStatus.noMembership:
        value = '—';
        unit = '';
        detail = 'No active plan';
      case MembershipStatus.expired:
        value = 'Expired';
        unit = '';
        detail = 'Ended ${dateFmt.format(endDate!)}';
      case MembershipStatus.active:
      case MembershipStatus.expiring:
        final d = daysLeft ?? 0;
        value = d == 0 ? 'Last day' : '$d';
        unit = d == 0 ? '' : (d == 1 ? 'day left' : 'days left');
        detail = 'Valid until ${dateFmt.format(endDate!)}';
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: 'PASS VALIDITY',
              trailing: MembershipStatusBadge(status: status),
              value: value,
              unit: unit,
              detail: detail,
              onTap: onPassTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'VISITS',
              trailing: const Icon(
                Icons.check_circle_outline_rounded,
                size: 15,
                color: AppColors.accentTeal,
              ),
              value: '$visitsThisMonth',
              unit: 'this month',
              detail: 'Last visit: $lastVisit',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.trailing,
    required this.value,
    required this.unit,
    required this.detail,
    this.onTap,
  });

  final String label;
  final Widget trailing;
  final String value;
  final String unit;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  trailing,
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.subtle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action buttons
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.showBookClass,
    required this.onBookClass,
    required this.onHistory,
  });

  final bool showBookClass;
  final VoidCallback onBookClass;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Row(
      children: [
        if (showBookClass) ...[
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onBookClass,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text(
                  'Book Class',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  shape: shape,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SizedBox(
            height: 48,
            // With Book Class it's the quieter partner; alone it's the
            // row's one action, so it gets the filled treatment.
            child: showBookClass
                ? OutlinedButton.icon(
                    onPressed: onHistory,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text(
                      'History',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      backgroundColor: AppColors.cardBg,
                      side: const BorderSide(color: AppColors.border),
                      shape: shape,
                    ),
                  )
                : FilledButton.icon(
                    onPressed: onHistory,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text(
                      'History',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentTeal,
                      foregroundColor: Colors.white,
                      shape: shape,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming events
// ---------------------------------------------------------------------------

class _UpcomingEventsSection extends StatelessWidget {
  const _UpcomingEventsSection({
    required this.events,
    required this.failed,
    required this.onRetry,
    required this.onViewAll,
    required this.onOpenEvent,
    required this.onToggleLike,
    required this.onLikeChanged,
  });

  final List<Event>? events;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onViewAll;
  final ValueChanged<Event> onOpenEvent;
  final Future<LikeState> Function(Event) onToggleLike;
  final void Function(String id, LikeState like) onLikeChanged;

  @override
  Widget build(BuildContext context) {
    final list = events;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Upcoming Events',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            InkWell(
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentTeal,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.accentTeal,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (list != null && list.isNotEmpty)
          for (final e in list) ...[
            EventCard(
              key: ValueKey('home-event-${e.id}'),
              event: e,
              onOpen: () => onOpenEvent(e),
              onToggleLike: () => onToggleLike(e),
              onLikeChanged: (s) => onLikeChanged(e.id, s),
            ),
            const SizedBox(height: 12),
          ]
        else if (list != null)
          const _EventsNote(
            icon: Icons.event_available_outlined,
            text: 'No upcoming events right now.',
          )
        else if (failed)
          _EventsNote(
            icon: Icons.cloud_off_outlined,
            text: "Couldn't load events.",
            action: TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.accentTeal),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }
}

class _EventsNote extends StatelessWidget {
  const _EventsNote({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
