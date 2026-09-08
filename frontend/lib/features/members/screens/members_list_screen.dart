import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../shell/app_shell.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';

// Local override for THIS screen only — "Active" renders blue here
// instead of the shared AppColors.activeBg green. Deliberately not
// touching the shared token, which still drives Active everywhere else
// (member creation, search results, etc.) unless asked to change it
// app-wide.
const _activeColorOverride = AppColors.accentBlue;

enum _StatusFilter { all, active, expiring, expired }

class MembersListScreen extends ConsumerStatefulWidget {
  const MembersListScreen({super.key, required this.gymId});

  final String gymId;

  @override
  ConsumerState<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  bool _refreshFailed = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await Future.wait([
        ref.read(membersRepositoryProvider).refreshMembers(widget.gymId),
        ref.read(plansRepositoryProvider).refreshPlans(widget.gymId),
      ]);
      if (mounted) setState(() => _refreshFailed = false);
    } catch (_) {
      if (mounted) setState(() => _refreshFailed = true);
    }
  }

  List<Member> _filtered(List<Member> members, DateTime today) {
    var result = members;

    if (_filter != _StatusFilter.all) {
      result = result.where((m) {
        final status = statusFor(m.currentEndDate, today);
        return switch (_filter) {
          _StatusFilter.active => status == MembershipStatus.active,
          _StatusFilter.expiring => status == MembershipStatus.expiring,
          _StatusFilter.expired => status == MembershipStatus.expired,
          _StatusFilter.all => true,
        };
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result.where((m) {
        return '${m.firstName} ${m.lastName}'.toLowerCase().contains(
          _searchQuery,
        );
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(visibleMembersProvider(widget.gymId));
    final today = GymTime.today();
    final allMembers = membersAsync.asData?.value ?? const <Member>[];

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Members',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.accentBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${allMembers.length} total members listed',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accentBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by name',
                        hintStyle: TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                        ),
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
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.border, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        _TabLabel(
                          label: 'All',
                          dotColor: AppColors.accentBlue,
                          selected: _filter == _StatusFilter.all,
                          onTap: () =>
                              setState(() => _filter = _StatusFilter.all),
                        ),
                        const SizedBox(width: 16),
                        _TabLabel(
                          label: 'Active',
                          // Blue override — see _activeColorOverride.
                          dotColor: _activeColorOverride,
                          selected: _filter == _StatusFilter.active,
                          onTap: () =>
                              setState(() => _filter = _StatusFilter.active),
                        ),
                        const SizedBox(width: 16),
                        _TabLabel(
                          label: 'Expiring',
                          // Light brown — unchanged.
                          dotColor: AppColors.expiringBg,
                          selected: _filter == _StatusFilter.expiring,
                          onTap: () =>
                              setState(() => _filter = _StatusFilter.expiring),
                        ),
                        const SizedBox(width: 16),
                        _TabLabel(
                          label: 'Expired',
                          // Red — unchanged.
                          dotColor: AppColors.expiredBg,
                          selected: _filter == _StatusFilter.expired,
                          onTap: () =>
                              setState(() => _filter = _StatusFilter.expired),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: membersAsync.when(
                      data: (members) {
                        if (members.isEmpty) {
                          return const _EmptyMembersList();
                        }
                        final filtered = _filtered(members, today);
                        if (filtered.isEmpty) {
                          return const Center(
                            child: Text(
                              'No members match',
                              style: TextStyle(color: AppColors.subtle),
                            ),
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: _refresh,
                          color: AppColors.accentBlue,
                          child: ListView.separated(
                            padding: EdgeInsets.only(
                              bottom: AppShell.reservedNavHeight + 72,
                            ),
                            cacheExtent: 600,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final member = filtered[index];
                              return RepaintBoundary(
                                key: ValueKey(member.id),
                                child: _MemberTile(
                                  member: member,
                                  today: today,
                                ),
                              );
                            },
                          ),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) =>
                          Center(child: Text('Something went wrong: $error')),
                    ),
                  ),

                  if (_refreshFailed) ...[
                    const SizedBox(height: 8),
                    const _RefreshFailedBanner(),
                  ],
                ],
              ),
            ),

            _ActionMenu(
              bottomInset: AppShell.reservedNavHeight,
              onNewMember: () => context.push('/members/create'),
              onManagePlans: () => context.push('/plans/manage'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: selected
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.accentBlue, width: 2),
                ),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.ink : AppColors.subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.today});

  final Member member;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final fullName = '${member.firstName} ${member.lastName}'.trim();
    final status = statusFor(member.currentEndDate, today);
    final remaining = daysRemaining(member.currentEndDate, today);

    // Expiring (light brown) and Expired (red) stay exactly as they've
    // always been. Active uses the local blue override for this screen.
    final (avatarBg, avatarIcon) = switch (status) {
      MembershipStatus.active => (_activeColorOverride, AppColors.activeIcon),
      MembershipStatus.expiring => (
        AppColors.expiringBg,
        AppColors.expiringIcon,
      ),
      MembershipStatus.expired => (AppColors.expiredBg, AppColors.expiredIcon),
      MembershipStatus.noMembership => (
        AppColors.noMembershipBg,
        AppColors.noMembershipIcon,
      ),
    };
    final labelColor = switch (status) {
      MembershipStatus.active => _activeColorOverride,
      MembershipStatus.expiring => AppColors.expiringBg,
      MembershipStatus.expired => AppColors.expiredBg,
      MembershipStatus.noMembership => AppColors.noMembershipBg,
    };

    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/members/${member.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, size: 18, color: avatarIcon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    if (member.currentPlanCategory != null &&
                        member.currentPlanCategory!.isNotEmpty)
                      Text(
                        member.currentPlanCategory!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _statusLabel(status, remaining),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                  Text(
                    _detailLabel(status, remaining),
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

  String _statusLabel(MembershipStatus status, int? remaining) {
    if (remaining == 0) return 'Expires today';
    switch (status) {
      case MembershipStatus.active:
        return 'Active';
      case MembershipStatus.expiring:
        return 'Expiring';
      case MembershipStatus.expired:
        return 'Expired';
      case MembershipStatus.noMembership:
        return 'No membership';
    }
  }

  String _detailLabel(MembershipStatus status, int? remaining) {
    if (remaining == null) return '';
    if (remaining == 0) return '';
    if (remaining > 0) return '$remaining days left';
    return '${remaining.abs()} days ago';
  }
}

class _EmptyMembersList extends StatelessWidget {
  const _EmptyMembersList();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No members yet', style: TextStyle(color: AppColors.subtle)),
    );
  }
}

class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        "Couldn't refresh — showing cached list",
        style: TextStyle(color: AppColors.errorText, fontSize: 13),
      ),
    );
  }
}

/// Fixed bottom-right "+" button. Tapping it expands two labeled circular
/// options above itself — New Member and Manage Plans.
class _ActionMenu extends StatefulWidget {
  const _ActionMenu({
    required this.bottomInset,
    required this.onNewMember,
    required this.onManagePlans,
  });

  final double bottomInset;
  final VoidCallback onNewMember;
  final VoidCallback onManagePlans;

  @override
  State<_ActionMenu> createState() => _ActionMenuState();
}

class _ActionMenuState extends State<_ActionMenu> {
  bool _expanded = false;

  // Nudges the FAB a bit closer to the bottom (toward the nav bar) than
  // the full reserved clearance — small enough that it still clears the
  // nav bar/FAB overhang, just sits lower rather than floating high
  // above it.
  static const double _extraDrop = 14;

  void _toggle() => setState(() => _expanded = !_expanded);

  void _pick(VoidCallback action) {
    setState(() => _expanded = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = (widget.bottomInset - _extraDrop).clamp(
      0.0,
      widget.bottomInset,
    );

    return Positioned.fill(
      child: Stack(
        children: [
          if (_expanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: Container(color: Colors.black.withValues(alpha: 0.12)),
              ),
            ),
          Positioned(
            right: 16,
            bottom: bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_expanded) ...[
                  _CircleAction(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'New Member',
                    background: AppColors.accentBlue,
                    onTap: () => _pick(widget.onNewMember),
                  ),
                  const SizedBox(height: 16),
                  _CircleAction(
                    icon: Icons.receipt_long_outlined,
                    label: 'Manage Plans',
                    background: AppColors.categoryPurple,
                    onTap: () => _pick(widget.onManagePlans),
                  ),
                  const SizedBox(height: 16),
                ],
                FloatingActionButton(
                  onPressed: _toggle,
                  // FAB itself is now blue, not ink.
                  backgroundColor: AppColors.accentBlue,
                  shape: const CircleBorder(),
                  child: Icon(
                    _expanded ? Icons.close : Icons.add,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(999),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: background,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(icon, size: 24, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
