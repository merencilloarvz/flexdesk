import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/gym_time.dart';
import '../../core/utils/member_status.dart';
import '../shell/app_shell.dart';
import '../auth/providers/auth_providers.dart';
import '../members/data/check_ins_repository.dart';
import '../members/providers/check_ins_provider.dart';
import '../members/providers/members_providers.dart';
import '../members/providers/plans_provider.dart';
import '../checkin/widgets/edit_walkin_prices.dart';

String _backendStatus(MembershipStatus status) {
  switch (status) {
    case MembershipStatus.active:
      return 'active';
    case MembershipStatus.expiring:
      return 'expiring';
    case MembershipStatus.expired:
      return 'expired';
    case MembershipStatus.noMembership:
      return 'no_membership';
  }
}

// Deterministic avatar color per name — same person always renders the
// same color, without storing anything.
//
// Note: accentTeal (index 0) and categoryTeal (index 1) are both teal
// hues now that accentBlue is gone — two names can land on similarly-
// colored avatars where before accentBlue gave clearer separation from
// categoryTeal. Worth a look on real data; not fixed here since it's a
// palette-distinctiveness call, not a rename bug.
const _avatarPalette = [
  AppColors.accentTeal,
  AppColors.categoryTeal,
  AppColors.categoryPurple,
  Color(0xFFE07A5F),
  Color(0xFF8A5A44),
];

Color _avatarColorFor(String name) {
  if (name.isEmpty) return AppColors.muted;
  return _avatarPalette[name.hashCode.abs() % _avatarPalette.length];
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

// Relative under an hour, clock time after — a 6am check-in should read
// as a time, not "11 hrs ago", once you're looking at it mid-afternoon.
String _formatCheckInTime(DateTime utcTime) {
  final local = utcTime.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final period = local.hour < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}

enum _CheckInTab { member, walkin }

enum _ListFilter { all, walkins }

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({
    super.key,
    required this.gymId,
    this.startOnWalkIn = false,
  });

  final String gymId;
  final bool startOnWalkIn;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  late _CheckInTab _tab;
  _ListFilter _filter = _ListFilter.all;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  final _walkInNameController = TextEditingController();
  String? _selectedPlanId;
  bool _walkInSubmitting = false;
  String? _walkInError;

  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.startOnWalkIn ? _CheckInTab.walkin : _CheckInTab.member;
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _walkInNameController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref
          .read(checkInsRepositoryProvider)
          .refreshCheckIns(widget.gymId, day: GymTime.today());
      // Plans aren't refreshed anywhere else on this screen — without
      // this, a device that's never opened Manage Plans has an empty
      // local cache and the walk-in pricing cards (and this edit sheet)
      // have nothing to show, even when online.
      await ref.read(plansRepositoryProvider).refreshPlans(widget.gymId);
      if (mounted) setState(() => _offline = false);
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        if (mounted) setState(() => _offline = true);
      }
    } catch (_) {
      // Defensive: never let a refresh failure break check-in.
    }
  }

  void _switchTab(_CheckInTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      // Switching tabs clears in-progress input in the other tab — a
      // half-typed walk-in name shouldn't survive behind a tab the user
      // has left.
      _searchController.clear();
      _searchQuery = '';
      _walkInNameController.clear();
      _selectedPlanId = null;
      _walkInError = null;
    });
  }

  List<Member> _matchingMembers(List<Member> members) {
    if (_searchQuery.isEmpty) return const [];
    return members.where((m) {
      final name = '${m.firstName} ${m.lastName}'.toLowerCase();
      final phone = m.phone.toLowerCase();
      final code = m.memberCode.toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          code.contains(_searchQuery);
    }).toList();
  }

  CheckIn? _todaysCheckInFor(String memberId, List<CheckIn> todaysCheckIns) {
    for (final c in todaysCheckIns) {
      if (c.visitType == 'MEMBER' &&
          c.memberId == memberId &&
          c.voidedAt == null) {
        return c;
      }
    }
    return null;
  }

  Future<void> _submitWalkIn(
    String? locationId,
    List<MembershipPlan> dayPassPlans,
  ) async {
    if (locationId == null) {
      setState(
        () => _walkInError = 'No location assigned — ask your gym owner.',
      );
      return;
    }
    final name = _walkInNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _walkInError = 'Enter a name first.');
      return;
    }
    if (_selectedPlanId == null) {
      setState(() => _walkInError = 'Pick a pricing option.');
      return;
    }

    MembershipPlan? plan;
    for (final p in dayPassPlans) {
      if (p.id == _selectedPlanId) plan = p;
    }
    if (plan == null || plan.priceCentavos <= 0) {
      // Shouldn't be reachable — tapping a zero-price card routes away
      // rather than selecting it — but guard anyway rather than send a
      // ₱0 charge silently.
      setState(() => _walkInError = 'Pick a pricing option.');
      return;
    }

    setState(() {
      _walkInSubmitting = true;
      _walkInError = null;
    });

    final result = await ref
        .read(checkInsRepositoryProvider)
        .createWalkInCheckIn(
          gymId: widget.gymId,
          locationId: locationId,
          visitorName: name,
          category: plan.category,
          amountChargedCentavos: plan.priceCentavos,
        );

    if (!mounted) return;

    if (result.outcome == CreateCheckInOutcome.rejected) {
      setState(() {
        _walkInSubmitting = false;
        _walkInError = result.message ?? "Couldn't check in.";
      });
      return;
    }

    setState(() {
      _walkInSubmitting = false;
      _selectedPlanId = null;
      _walkInNameController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.outcome == CreateCheckInOutcome.queuedOffline
                ? "$name checked in — will sync when you're back online."
                : '$name checked in.',
          ),
        ),
      );
    }
  }

  Future<void> _openMemberConfirmSheet(
    Member member,
    String? locationId,
    List<CheckIn> todaysCheckIns,
  ) async {
    final today = GymTime.today();
    final status = statusFor(member.currentEndDate, today);
    final remaining = daysRemaining(member.currentEndDate, today);
    final alreadyToday = todaysCheckIns.any(
      (c) =>
          c.visitType == 'MEMBER' &&
          c.memberId == member.id &&
          c.voidedAt == null,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        // AppShell's nav bar is a floating overlay from the OUTER Scaffold,
        // not a real bottomNavigationBar the branch reserves layout space
        // for. A modal sheet needs the exact same fix as the screen body.
        padding: EdgeInsets.only(
          bottom:
              AppShell.reservedNavHeight +
              MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _MemberConfirmSheet(
          member: member,
          status: status,
          remaining: remaining,
          alreadyToday: alreadyToday,
          onConfirm: locationId == null
              ? null
              : () async {
                  final result = await ref
                      .read(checkInsRepositoryProvider)
                      .createMemberCheckIn(
                        gymId: widget.gymId,
                        memberId: member.id,
                        locationId: locationId,
                        membershipStatus: _backendStatus(status),
                        membershipEndDate: member.currentEndDate,
                      );
                  return result;
                },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final locationId = authState is AuthAuthenticated
        ? authState.user.defaultLocationId
        : null;

    final membersAsync = ref.watch(visibleMembersProvider(widget.gymId));
    final today = GymTime.today();
    final checkInsAsync = ref.watch(
      checkInsForDayProvider(CheckInsDayArg(widget.gymId, today)),
    );
    final todaysCheckIns = checkInsAsync.asData?.value ?? const <CheckIn>[];
    final nonVoidedToday = todaysCheckIns
        .where((c) => c.voidedAt == null)
        .toList();
    final walkInsToday = nonVoidedToday
        .where((c) => c.visitType == 'WALKIN')
        .toList();

    final plansAsync = ref.watch(activePlansProvider(widget.gymId));
    final dayPassPlans =
        (plansAsync.asData?.value ?? const <MembershipPlan>[])
            .where((p) => p.isDayPass && p.isActive)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Front Desk Check-in',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Pill(
                    icon: Icons.groups_outlined,
                    // D1: honestly labeled "today", not a live occupancy
                    // count — there is no check-out, so the app cannot
                    // know who is still inside.
                    label: '${nonVoidedToday.length} today',
                  ),
                  const SizedBox(width: 8),
                  // Neutral styling always — offline must never read as
                  // an error. The app works offline by design; if this
                  // looks like a failure, staff stop trusting it on the
                  // exact bad-wifi days it exists for.
                  _Pill(
                    icon: _offline
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                    label: _offline ? 'Offline' : 'Online',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (locationId == null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'No location assigned — ask your gym owner.',
                    style: TextStyle(color: AppColors.errorText, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              _TabToggle(tab: _tab, onChanged: _switchTab),
              const SizedBox(height: 14),

              Expanded(
                child: _tab == _CheckInTab.member
                    ? _MemberTabContent(
                        searchController: _searchController,
                        searchQuery: _searchQuery,
                        membersAsync: membersAsync,
                        today: today,
                        todaysCheckIns: todaysCheckIns,
                        nonVoidedToday: nonVoidedToday,
                        walkInsToday: walkInsToday,
                        filter: _filter,
                        onFilterChanged: (f) => setState(() => _filter = f),
                        matchingMembers: _matchingMembers,
                        todaysCheckInFor: _todaysCheckInFor,
                        onMemberTap: (member) => _openMemberConfirmSheet(
                          member,
                          locationId,
                          todaysCheckIns,
                        ),
                      )
                    : _WalkInTabContent(
                        gymId: widget.gymId,
                        nameController: _walkInNameController,
                        dayPassPlansAsync: plansAsync,
                        dayPassPlans: dayPassPlans,
                        selectedPlanId: _selectedPlanId,
                        onSelectPlan: (id) =>
                            setState(() => _selectedPlanId = id),
                        error: _walkInError,
                        submitting: _walkInSubmitting,
                        onSubmit: () => _submitWalkIn(locationId, dayPassPlans),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.subtle),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }
}

class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.tab, required this.onChanged});
  final _CheckInTab tab;
  final ValueChanged<_CheckInTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Member Check-in',
              selected: tab == _CheckInTab.member,
              onTap: () => onChanged(_CheckInTab.member),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Walk-in Guest',
              selected: tab == _CheckInTab.walkin,
              onTap: () => onChanged(_CheckInTab.walkin),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentTeal : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _MemberTabContent extends StatelessWidget {
  const _MemberTabContent({
    required this.searchController,
    required this.searchQuery,
    required this.membersAsync,
    required this.today,
    required this.todaysCheckIns,
    required this.nonVoidedToday,
    required this.walkInsToday,
    required this.filter,
    required this.onFilterChanged,
    required this.matchingMembers,
    required this.todaysCheckInFor,
    required this.onMemberTap,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final AsyncValue<List<Member>> membersAsync;
  final DateTime today;
  final List<CheckIn> todaysCheckIns;
  final List<CheckIn> nonVoidedToday;
  final List<CheckIn> walkInsToday;
  final _ListFilter filter;
  final ValueChanged<_ListFilter> onFilterChanged;
  final List<Member> Function(List<Member>) matchingMembers;
  final CheckIn? Function(String, List<CheckIn>) todaysCheckInFor;
  final void Function(Member) onMemberTap;

  @override
  Widget build(BuildContext context) {
    // Voided rows still shown in the raw list below, but excluded from
    // every count — struck-through visibility, zero weight in numbers.
    final visibleRows = filter == _ListFilter.all
        ? todaysCheckIns
        : todaysCheckIns.where((c) => c.visitType == 'WALKIN').toList();

    return ListView(
      padding: EdgeInsets.only(bottom: AppShell.reservedNavHeight + 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Search Member Name or ID',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: "Enter member's name or ID",
                    hintStyle: TextStyle(color: AppColors.muted, fontSize: 14),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.muted,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (searchQuery.isNotEmpty) ...[
                const SizedBox(height: 10),
                membersAsync.when(
                  data: (members) {
                    final matches = matchingMembers(members);
                    if (matches.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No matching member — switch to Walk-in Guest instead.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final member in matches.take(6))
                          _SearchResultTile(
                            member: member,
                            today: today,
                            alreadyCheckedIn: todaysCheckInFor(
                              member.id,
                              todaysCheckIns,
                            ),
                            onTap: () => onMemberTap(member),
                          ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Checked In Today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            Row(
              children: [
                _FilterChip(
                  label: 'All (${nonVoidedToday.length})',
                  selected: filter == _ListFilter.all,
                  onTap: () => onFilterChanged(_ListFilter.all),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Walk-in (${walkInsToday.length})',
                  selected: filter == _ListFilter.walkins,
                  onTap: () => onFilterChanged(_ListFilter.walkins),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (visibleRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No check-ins yet today',
              style: TextStyle(color: AppColors.subtle),
            ),
          )
        else
          Column(
            children: [for (final c in visibleRows) _CheckInTile(checkIn: c)],
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTealBg : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentTeal : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _WalkInTabContent extends StatelessWidget {
  const _WalkInTabContent({
    required this.gymId,
    required this.nameController,
    required this.dayPassPlansAsync,
    required this.dayPassPlans,
    required this.selectedPlanId,
    required this.onSelectPlan,
    required this.error,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final AsyncValue<List<MembershipPlan>> dayPassPlansAsync;
  final List<MembershipPlan> dayPassPlans;
  final String? selectedPlanId;
  final ValueChanged<String> onSelectPlan;
  final String? error;
  final bool submitting;
  final VoidCallback onSubmit;
  final String gymId;

  bool get _canSubmit {
    if (selectedPlanId == null) return false;
    final plan = dayPassPlans.where((p) => p.id == selectedPlanId).firstOrNull;
    return plan != null &&
        plan.priceCentavos > 0 &&
        nameController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(bottom: AppShell.reservedNavHeight + 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Walk-in Guest Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: "Enter guest's name",
                    hintStyle: TextStyle(color: AppColors.muted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Walk-in Pricing',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => showEditWalkInPricesSheet(
                      context,
                      gymId: gymId,
                      dayPassPlans: dayPassPlans,
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: AppColors.accentTeal,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Edit prices',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.accentTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              dayPassPlansAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Text(
                  'Something went wrong: $e',
                  style: const TextStyle(
                    color: AppColors.errorText,
                    fontSize: 12,
                  ),
                ),
                data: (_) {
                  if (dayPassPlans.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No day-pass plans set up yet. Add one in Manage Plans.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final plan in dayPassPlans)
                        SizedBox(
                          width:
                              (MediaQuery.of(context).size.width -
                                  32 -
                                  32 -
                                  10) /
                              2,
                          child: _PlanPriceCard(
                            plan: plan,
                            selected: plan.id == selectedPlanId,
                            onTap: () {
                              if (plan.priceCentavos <= 0) {
                                context.push('/plans/manage');
                              } else {
                                onSelectPlan(plan.id);
                              }
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (error != null) ...[
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.errorText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: submitting || !_canSubmit ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Check In'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanPriceCard extends StatelessWidget {
  const _PlanPriceCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });
  final MembershipPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zeroPrice = plan.priceCentavos <= 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTealBg : AppColors.pageBg,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: AppColors.accentTeal, width: 1.5)
              : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    plan.category.isEmpty ? plan.name : plan.category,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.check_circle,
                    size: 15,
                    color: AppColors.accentTeal,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              zeroPrice
                  ? 'Set price'
                  : '₱${(plan.priceCentavos / 100).toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: zeroPrice ? AppColors.errorText : AppColors.muted,
                fontWeight: zeroPrice ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.member,
    required this.today,
    required this.alreadyCheckedIn,
    required this.onTap,
  });

  final Member member;
  final DateTime today;
  final CheckIn? alreadyCheckedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fullName = '${member.firstName} ${member.lastName}'.trim();
    final status = statusFor(member.currentEndDate, today);
    final (badgeBg, badgeLabel) = switch (status) {
      MembershipStatus.active => (AppColors.activeBg, 'Active'),
      MembershipStatus.expiring => (AppColors.expiringBg, 'Expiring'),
      MembershipStatus.expired => (AppColors.expiredBg, 'Expired'),
      MembershipStatus.noMembership => (
        AppColors.noMembershipBg,
        'No membership',
      ),
    };

    return Material(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              // Not a block — a member can legitimately return in the
              // evening — just a heads-up so the front desk doesn't
              // mis-tap a duplicate by accident.
              if (alreadyCheckedIn != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Checked in ${_formatCheckInTime(alreadyCheckedIn!.checkedInAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.accentTeal,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckInTile extends ConsumerWidget {
  const _CheckInTile({required this.checkIn});

  final CheckIn checkIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voided = checkIn.voidedAt != null;

    String name;
    String subtitle;

    if (checkIn.visitType == 'WALKIN') {
      final price = checkIn.amountChargedCentavos != null
          ? '₱${(checkIn.amountChargedCentavos! / 100).toStringAsFixed(0)}'
          : '';
      final label = checkIn.category.isEmpty
          ? 'Walk-in'
          : checkIn.category[0].toUpperCase() + checkIn.category.substring(1);
      name = checkIn.visitorName.isEmpty ? 'Guest' : checkIn.visitorName;
      subtitle = price.isEmpty ? label : '$label · $price';
    } else {
      final memberAsync = checkIn.memberId != null
          ? ref.watch(memberByIdProvider(checkIn.memberId!))
          : null;
      name = memberAsync?.asData?.value != null
          ? '${memberAsync!.asData!.value!.firstName} ${memberAsync.asData!.value!.lastName}'
                .trim()
          : 'Member';

      final endDate = checkIn.membershipEndDate;
      subtitle = endDate != null
          ? () {
              final remaining = daysRemaining(endDate, GymTime.today());
              if (remaining == null) return checkIn.membershipStatus;
              if (remaining < 0) return 'ACTIVE';
              return '$remaining DAYS LEFT';
            }()
          : checkIn.membershipStatus.toUpperCase();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: voided ? AppColors.disabledBg : _avatarColorFor(name),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initialsFor(name),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: voided ? AppColors.disabledLabel : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: voided ? AppColors.muted : AppColors.ink,
                    decoration: voided
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatCheckInTime(checkIn.checkedInAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                    // Neutral, not an error — a queued offline write is
                    // working as designed, not broken.
                    if (checkIn.isDirty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.fieldBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Not synced',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.subtle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MemberConfirmSheet extends StatefulWidget {
  const _MemberConfirmSheet({
    required this.member,
    required this.status,
    required this.remaining,
    required this.alreadyToday,
    required this.onConfirm,
  });

  final Member member;
  final MembershipStatus status;
  final int? remaining;
  final bool alreadyToday;
  final Future<CreateCheckInResult> Function()? onConfirm;

  @override
  State<_MemberConfirmSheet> createState() => _MemberConfirmSheetState();
}

class _MemberConfirmSheetState extends State<_MemberConfirmSheet> {
  // Was a local blue override for THIS sheet only, deliberately
  // different from AppColors.activeBg elsewhere. Now that accentTeal
  // and activeBg are the same hex, that distinction no longer exists —
  // this sheet's "Active" badge is visually identical to every other
  // screen's now. Flagged in the review note above; left as accentTeal
  // rather than picking a new color unasked.
  static const _sheetAccent = AppColors.accentTeal;

  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    final onConfirm = widget.onConfirm;
    if (onConfirm == null) {
      setState(() => _error = 'No location assigned — ask your gym owner.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await onConfirm();
    if (!mounted) return;
    if (result.outcome == CreateCheckInOutcome.rejected) {
      setState(() {
        _submitting = false;
        _error = result.message ?? "Couldn't check in.";
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '${widget.member.firstName} ${widget.member.lastName}'
        .trim();
    final (badgeBg, badgeLabel) = switch (widget.status) {
      MembershipStatus.active => (_sheetAccent, 'Active'),
      MembershipStatus.expiring => (AppColors.expiringBg, 'Expiring'),
      MembershipStatus.expired => (AppColors.expiredBg, 'Expired'),
      MembershipStatus.noMembership => (
        AppColors.noMembershipBg,
        'No membership',
      ),
    };
    final needsWarning =
        widget.status == MembershipStatus.expired ||
        widget.status == MembershipStatus.noMembership;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.remaining == null || widget.remaining! < 0
                    ? badgeLabel
                    : '$badgeLabel · ${widget.remaining} days left',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (widget.member.currentPlanCategory != null &&
              widget.member.currentPlanCategory!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.fieldBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PLAN TYPE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    widget.member.currentPlanCategory!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.alreadyToday) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Already checked in today.',
                style: TextStyle(color: AppColors.errorText, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (needsWarning) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.status == MembershipStatus.expired
                    ? 'This membership has expired. You can still check them in — the gym decides who gets in.'
                    : 'This person has no active membership. You can still check them in.',
                style: const TextStyle(
                  color: AppColors.errorText,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: AppColors.errorText, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: _sheetAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(needsWarning ? 'Check In Anyway' : 'Confirm Check In'),
            ),
          ),
        ],
      ),
    );
  }
}
