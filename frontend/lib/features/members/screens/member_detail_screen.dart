import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cCardBg = Colors.white;
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cAccentTeal = Color(0xFF0F6E56);
const Color _cErrorText = Color(0xFF9E3125);
const Color _cErrorBg = Color(0xFFFCEBE8);
const Color _cDisabledBg = Color(0xFFE2E5E3);

const Color _cActiveBg = Color(0xFF0F6E56);
const Color _cActiveIcon = Color(0xFFE1F5EE);
const Color _cExpiringBg = Color(0xFF92600B);
const Color _cExpiringIcon = Color(0xFFFBEEDC);
const Color _cExpiredBg = Color(0xFF9E3125);
const Color _cExpiredIcon = Color(0xFFFCEBE8);
const Color _cNoMembershipBg = Color(0xFF5F6462);
const Color _cNoMembershipIcon = Colors.white;

class MemberDetailScreen extends ConsumerStatefulWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  bool _isArchiving = false;
  String? _archiveError;

  Future<void> _confirmAndArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this member?'),
        content: const Text(
          "This can't be undone — there is no un-archive action.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isArchiving = true;
      _archiveError = null;
    });

    try {
      await ref.read(membersRepositoryProvider).archiveMember(widget.memberId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isArchiving = false;
          _archiveError = "Couldn't archive — check your connection.";
        });
      }
    }
  }

  Future<void> _openRenewSheet(String gymId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cPageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _RenewSheet(memberId: widget.memberId, gymId: gymId),
      ),
    );
    // The sheet already refreshes the member on success; the history
    // section is a separate one-shot fetch that doesn't know a new
    // Membership was just created, so it needs an explicit nudge.
    ref.invalidate(membershipHistoryProvider(widget.memberId));
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(memberByIdProvider(widget.memberId));
    final authState = ref.watch(authControllerProvider);
    final isOwner =
        authState is AuthAuthenticated && authState.user.role == UserRole.owner;
    final gymId = authState is AuthAuthenticated ? authState.user.gym.id : '';

    return Scaffold(
      backgroundColor: _cPageBg,
      appBar: AppBar(
        backgroundColor: _cPageBg,
        elevation: 0,
        title: const Text(
          'Member',
          style: TextStyle(color: _cInk, fontWeight: FontWeight.w500),
        ),
        iconTheme: const IconThemeData(color: _cInk),
      ),
      body: memberAsync.when(
        data: (member) {
          if (member == null) {
            return const Center(
              child: Text(
                'Member not found',
                style: TextStyle(color: _cSubtle),
              ),
            );
          }
          return _MemberDetailBody(
            member: member,
            isOwner: isOwner,
            isArchiving: _isArchiving,
            archiveError: _archiveError,
            onArchive: _confirmAndArchive,
            onRenew: () => _openRenewSheet(gymId),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
      ),
    );
  }
}

class _MemberDetailBody extends StatelessWidget {
  const _MemberDetailBody({
    required this.member,
    required this.isOwner,
    required this.isArchiving,
    required this.archiveError,
    required this.onArchive,
    required this.onRenew,
  });

  final Member member;
  final bool isOwner;
  final bool isArchiving;
  final String? archiveError;
  final VoidCallback onArchive;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();
    final status = statusFor(member.currentEndDate, today);
    final remaining = daysRemaining(member.currentEndDate, today);
    final fullName = '${member.firstName} ${member.lastName}'.trim();

    final (avatarBg, avatarIcon) = switch (status) {
      MembershipStatus.active => (_cActiveBg, _cActiveIcon),
      MembershipStatus.expiring => (_cExpiringBg, _cExpiringIcon),
      MembershipStatus.expired => (_cExpiredBg, _cExpiredIcon),
      MembershipStatus.noMembership => (_cNoMembershipBg, _cNoMembershipIcon),
    };
    final pillBg = avatarBg;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person, size: 28, color: avatarIcon),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: _cInk,
                      ),
                    ),
                    if (member.currentPlanCategory != null &&
                        member.currentPlanCategory!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        member.currentPlanCategory!,
                        style: const TextStyle(fontSize: 12, color: _cMuted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(status, remaining),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _cCardBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Member code',
                      value: member.memberCode.isEmpty
                          ? 'Not assigned'
                          : member.memberCode,
                    ),
                    const Divider(height: 1, color: _cFieldBg),
                    _InfoRow(
                      icon: Icons.call_outlined,
                      label: 'Phone',
                      value: member.phone,
                    ),
                    const Divider(height: 1, color: _cFieldBg),
                    _InfoRow(
                      icon: Icons.mail_outline,
                      label: 'Email',
                      value: member.email,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Membership history',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cInk,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _cCardBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _MembershipHistorySection(memberId: member.id),
              ),
            ],
          ),
        ),

        // Pinned below the scrolling content — however long the history
        // list gets, Renew and Archive stay reachable without scrolling.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: _cPageBg,
            border: Border(top: BorderSide(color: _cFieldBg, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onRenew,
                    style: FilledButton.styleFrom(
                      backgroundColor: _cAccentTeal,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Renew membership',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (isOwner && member.archivedAt == null) ...[
                  const SizedBox(height: 6),
                  if (archiveError != null) ...[
                    Text(
                      archiveError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _cErrorText, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                  ],
                  isArchiving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : InkWell(
                          onTap: onArchive,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.archive_outlined,
                                  size: 16,
                                  color: _cErrorText,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Archive',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _cErrorText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(MembershipStatus status, int? remaining) {
    if (remaining == 0) return 'Expires today';
    switch (status) {
      case MembershipStatus.active:
        return 'Active · $remaining days left';
      case MembershipStatus.expiring:
        return 'Expiring · $remaining days left';
      case MembershipStatus.expired:
        return 'Expired';
      case MembershipStatus.noMembership:
        return 'No membership';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _cMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: _cMuted),
            ),
          ),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13, color: _cInk),
          ),
        ],
      ),
    );
  }
}

class _MembershipHistorySection extends ConsumerWidget {
  const _MembershipHistorySection({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(membershipHistoryProvider(memberId));

    return historyAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No membership history yet.',
              style: TextStyle(color: _cMuted, fontSize: 13),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _cFieldBg),
              _HistoryTile(json: entries[i]),
            ],
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'History unavailable offline',
          style: TextStyle(color: _cMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.json});

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            planName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _cInk,
            ),
          ),
          if (dateRange.isNotEmpty)
            Text(
              dateRange,
              style: const TextStyle(fontSize: 12, color: _cMuted),
            ),
        ],
      ),
    );
  }
}

class _RenewSheet extends ConsumerStatefulWidget {
  const _RenewSheet({required this.memberId, required this.gymId});

  final String memberId;
  final String gymId;

  @override
  ConsumerState<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends ConsumerState<_RenewSheet> {
  String? _planId;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_planId == null) {
      setState(() => _error = 'Pick a plan first.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref
          .read(membersRepositoryProvider)
          .renewMembership(
            memberId: widget.memberId,
            gymId: widget.gymId,
            planId: _planId!,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = "Couldn't renew — check your connection.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(activePlansProvider(widget.gymId));

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
                color: _cDisabledBg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Renew membership',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _cInk,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Extends from the current end date using the plan you pick.',
            style: TextStyle(fontSize: 12, color: _cMuted),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cErrorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: _cErrorText, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _cFieldBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: plansAsync.when(
              data: (plans) {
                final items = (plans as List)
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p.id as String,
                        child: Text(
                          p.category.isEmpty
                              ? p.name as String
                              : '${p.name} (${p.category})',
                        ),
                      ),
                    )
                    .toList();
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _planId,
                    hint: const Text('Choose a plan'),
                    isExpanded: true,
                    items: items,
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _planId = v),
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => const Text(
                "Couldn't load plans",
                style: TextStyle(color: _cMuted, fontSize: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cAccentTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Confirm renewal'),
            ),
          ),
        ],
      ),
    );
  }
}
