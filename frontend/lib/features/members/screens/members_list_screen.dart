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

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // TODO: gym name is hardcoded — wire to the real gym
                      // name from AuthUser.gym once threaded through here.
                      const Text(
                        'IRON WORKS CEBU',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: AppColors.accentTeal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Members',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
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
                            bottom: BorderSide(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _TabLabel(
                              label: 'All',
                              selected: _filter == _StatusFilter.all,
                              onTap: () =>
                                  setState(() => _filter = _StatusFilter.all),
                            ),
                            const SizedBox(width: 16),
                            _TabLabel(
                              label: 'Active',
                              selected: _filter == _StatusFilter.active,
                              onTap: () => setState(
                                () => _filter = _StatusFilter.active,
                              ),
                            ),
                            const SizedBox(width: 16),
                            _TabLabel(
                              label: 'Expiring',
                              selected: _filter == _StatusFilter.expiring,
                              onTap: () => setState(
                                () => _filter = _StatusFilter.expiring,
                              ),
                            ),
                            const SizedBox(width: 16),
                            _TabLabel(
                              label: 'Expired',
                              selected: _filter == _StatusFilter.expired,
                              onTap: () => setState(
                                () => _filter = _StatusFilter.expired,
                              ),
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
                              child: ListView.separated(
                                padding: EdgeInsets.only(
                                  bottom: AppShell.reservedNavHeight + 72,
                                ),
                                // Pre-builds rows just off-screen so they're
                                // ready before they're scrolled into view —
                                // smooths out scroll jank on longer lists.
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
                          error: (error, _) => Center(
                            child: Text('Something went wrong: $error'),
                          ),
                        ),
                      ),

                      if (_refreshFailed) ...[
                        const SizedBox(height: 8),
                        const _RefreshFailedBanner(),
                      ],
                    ],
                  ),
                ),

                // Floating "Add Member" button — round, plus-only, starts
                // bottom-right above the pill nav, and can be dragged
                // anywhere on screen. Lives in its own widget/state so
                // dragging only repaints the button, not this whole screen.
                _DraggableAddButton(
                  constraints: constraints,
                  bottomInset: AppShell.reservedNavHeight,
                  onPressed: () => context.push('/members/create'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
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
        padding: const EdgeInsets.only(bottom: 8),
        decoration: selected
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.accentTeal, width: 2),
                ),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? AppColors.ink : AppColors.subtle,
          ),
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

    final (avatarBg, avatarIcon) = switch (status) {
      MembershipStatus.active => (AppColors.activeBg, AppColors.activeIcon),
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
      MembershipStatus.active => AppColors.activeBg,
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

class _DraggableAddButton extends StatefulWidget {
  const _DraggableAddButton({
    required this.constraints,
    required this.bottomInset,
    required this.onPressed,
  });

  final BoxConstraints constraints;
  final double bottomInset;
  final VoidCallback onPressed;

  @override
  State<_DraggableAddButton> createState() => _DraggableAddButtonState();
}

class _DraggableAddButtonState extends State<_DraggableAddButton> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final defaultOffset = Offset(
      widget.constraints.maxWidth - 16 - 56,
      widget.constraints.maxHeight - widget.bottomInset - 56,
    );
    final offset = _offset ?? defaultOffset;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final current = _offset ?? defaultOffset;
            final newX = (current.dx + details.delta.dx).clamp(
              0.0,
              widget.constraints.maxWidth - 56,
            );
            final newY = (current.dy + details.delta.dy).clamp(
              0.0,
              widget.constraints.maxHeight - 56,
            );
            _offset = Offset(newX, newY);
          });
        },
        child: FloatingActionButton(
          onPressed: widget.onPressed,
          backgroundColor: AppColors.ink,
          shape: const CircleBorder(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
