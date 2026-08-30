import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cCardBg = Colors.white;
const Color _cBorder = Color(0xFFD8DAD5);

// Teal is the app's accent — used for the gym-name label, selected tab,
// and (below) the active-status color. Amber/red stay as distinct warm
// colors for warning/danger, so status is still readable at a glance
// rather than three shades of the same hue.
const Color _cAccentTeal = Color(0xFF0F6E56);

const Color _cActiveBg = Color(0xFF0F6E56);
const Color _cActiveIcon = Color(0xFFE1F5EE);
const Color _cExpiringBg = Color(0xFF92600B);
const Color _cExpiringIcon = Color(0xFFFBEEDC);
const Color _cExpiredBg = Color(0xFF9E3125);
const Color _cExpiredIcon = Color(0xFFFCEBE8);
const Color _cNoMembershipBg = Color(0xFF5F6462);
const Color _cNoMembershipIcon = Colors.white;

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
      backgroundColor: _cPageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TODO: gym name is hardcoded — wire to the real gym name
              // from AuthUser.gym once threaded through to this screen.
              const Text(
                'IRON WORKS CEBU',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _cAccentTeal,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Members',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: _cInk,
                ),
              ),
              const SizedBox(height: 14),

              Container(
                decoration: BoxDecoration(
                  color: _cCardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by name',
                    hintStyle: TextStyle(color: _cMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: _cMuted, size: 20),
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
                    bottom: BorderSide(color: _cBorder, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    _TabLabel(
                      label: 'All',
                      selected: _filter == _StatusFilter.all,
                      onTap: () => setState(() => _filter = _StatusFilter.all),
                    ),
                    const SizedBox(width: 16),
                    _TabLabel(
                      label: 'Active',
                      selected: _filter == _StatusFilter.active,
                      onTap: () =>
                          setState(() => _filter = _StatusFilter.active),
                    ),
                    const SizedBox(width: 16),
                    _TabLabel(
                      label: 'Expiring',
                      selected: _filter == _StatusFilter.expiring,
                      onTap: () =>
                          setState(() => _filter = _StatusFilter.expiring),
                    ),
                    const SizedBox(width: 16),
                    _TabLabel(
                      label: 'Expired',
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
                          style: TextStyle(color: _cSubtle),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _MemberTile(member: filtered[index], today: today),
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

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push('/members/create'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cInk,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    'Add Member',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
                  bottom: BorderSide(color: _cAccentTeal, width: 2),
                ),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? _cInk : _cSubtle,
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
      MembershipStatus.active => (_cActiveBg, _cActiveIcon),
      MembershipStatus.expiring => (_cExpiringBg, _cExpiringIcon),
      MembershipStatus.expired => (_cExpiredBg, _cExpiredIcon),
      MembershipStatus.noMembership => (_cNoMembershipBg, _cNoMembershipIcon),
    };
    final labelColor = switch (status) {
      MembershipStatus.active => _cActiveBg,
      MembershipStatus.expiring => _cExpiringBg,
      MembershipStatus.expired => _cExpiredBg,
      MembershipStatus.noMembership => _cNoMembershipBg,
    };

    return Material(
      color: _cCardBg,
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
                        color: _cInk,
                      ),
                    ),
                    if (member.currentPlanCategory != null &&
                        member.currentPlanCategory!.isNotEmpty)
                      Text(
                        member.currentPlanCategory!,
                        style: const TextStyle(fontSize: 12, color: _cMuted),
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
                    style: const TextStyle(fontSize: 11, color: _cMuted),
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
      child: Text('No members yet', style: TextStyle(color: _cSubtle)),
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
        color: const Color(0xFFFCEBE8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        "Couldn't refresh — showing cached list",
        style: TextStyle(color: Color(0xFF9E3125), fontSize: 13),
      ),
    );
  }
}
