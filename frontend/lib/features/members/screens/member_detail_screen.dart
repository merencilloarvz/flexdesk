import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';
import '../providers/member_visit_stats_provider.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cCardBg = Colors.white;
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cAccentBlue = Color(0xFF2F6FE4);
const Color _cAccentBlueBg = Color(0xFFEAF1FE);
const Color _cGradientEnd = Color(0xFF7C5CFC);
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

  bool? _hasAccount;
  bool _isCheckingAccount = true;
  bool _isIssuingCode = false;
  String? _claimError;
  Map<String, dynamic>? _issuedCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHasAccount());
  }

  Future<void> _checkHasAccount() async {
    try {
      final hasAccount = await ref
          .read(membersRepositoryProvider)
          .fetchHasAccount(widget.memberId);
      if (mounted) {
        setState(() {
          _hasAccount = hasAccount;
          _isCheckingAccount = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingAccount = false);
    }
  }

  void _refreshAll() {
    ref.invalidate(memberByIdProvider(widget.memberId));
    ref.invalidate(membershipHistoryProvider(widget.memberId));
    ref.invalidate(memberVisitStatsProvider(widget.memberId));
    setState(() => _isCheckingAccount = true);
    _checkHasAccount();
  }

  Future<void> _issueClaimCode() async {
    setState(() {
      _isIssuingCode = true;
      _claimError = null;
    });
    try {
      final result = await ref
          .read(membersRepositoryProvider)
          .issueClaimCode(widget.memberId);
      if (mounted) {
        setState(() {
          _issuedCode = result;
          _isIssuingCode = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isIssuingCode = false;
          _claimError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isIssuingCode = false;
          _claimError = "Couldn't reach the server. Check your connection.";
        });
      }
    }
  }

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
          'Member Details',
          style: TextStyle(color: _cInk, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: _cInk),
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 4),
        ],
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
            hasAccount: _hasAccount,
            isCheckingAccount: _isCheckingAccount,
            isIssuingCode: _isIssuingCode,
            claimError: _claimError,
            issuedCode: _issuedCode,
            onIssueCode: _issueClaimCode,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
      ),
    );
  }
}

class _MemberDetailBody extends ConsumerWidget {
  const _MemberDetailBody({
    required this.member,
    required this.isOwner,
    required this.isArchiving,
    required this.archiveError,
    required this.onArchive,
    required this.onRenew,
    required this.hasAccount,
    required this.isCheckingAccount,
    required this.isIssuingCode,
    required this.claimError,
    required this.issuedCode,
    required this.onIssueCode,
  });

  final Member member;
  final bool isOwner;
  final bool isArchiving;
  final String? archiveError;
  final VoidCallback onArchive;
  final VoidCallback onRenew;
  final bool? hasAccount;
  final bool isCheckingAccount;
  final bool isIssuingCode;
  final String? claimError;
  final Map<String, dynamic>? issuedCode;
  final VoidCallback onIssueCode;

  void _copyToClipboard(BuildContext context, String value, String label) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = GymTime.today();
    final status = statusFor(member.currentEndDate, today);
    final remaining = daysRemaining(member.currentEndDate, today);
    final fullName = '${member.firstName} ${member.lastName}'.trim();
    final statsAsync = ref.watch(memberVisitStatsProvider(member.id));

    final (avatarBg, avatarIcon) = switch (status) {
      MembershipStatus.active => (_cActiveBg, _cActiveIcon),
      MembershipStatus.expiring => (_cExpiringBg, _cExpiringIcon),
      MembershipStatus.expired => (_cExpiredBg, _cExpiredIcon),
      MembershipStatus.noMembership => (_cNoMembershipBg, _cNoMembershipIcon),
    };
    final (pillBg, pillText) = switch (status) {
      MembershipStatus.active => (_cActiveIcon, _cActiveBg),
      MembershipStatus.expiring => (_cExpiringIcon, _cExpiringBg),
      MembershipStatus.expired => (_cExpiredIcon, _cExpiredBg),
      MembershipStatus.noMembership => (
        const Color(0xFFEDEEEE),
        _cNoMembershipBg,
      ),
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: avatarBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 32,
                            color: avatarIcon,
                          ),
                        ),
                        if (hasAccount == true)
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _cActiveBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: _cCardBg, width: 2),
                              ),
                            ),
                          ),
                      ],
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
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(status, remaining),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pillText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.bolt,
                      label: 'Visits',
                      sublabel: 'This month',
                      value: statsAsync.when(
                        data: (s) => '${s.visitsThisMonth}',
                        loading: () => '—',
                        error: (_, _) => '—',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.access_time,
                      label: 'Last in',
                      sublabel: statsAsync.when(
                        data: (s) => s.lastCheckInAt == null
                            ? 'No visits yet'
                            : DateFormat(
                                'h:mm a',
                              ).format(s.lastCheckInAt!.toLocal()),
                        loading: () => '',
                        error: (_, _) => '',
                      ),
                      value: statsAsync.when(
                        data: (s) => s.lastCheckInAt == null
                            ? '—'
                            : _relativeDay(s.lastCheckInAt!.toLocal()),
                        loading: () => '—',
                        error: (_, _) => '—',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
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
                      icon: Icons.call_outlined,
                      label: 'Phone',
                      value: member.phone,
                      onCopy: member.phone.isEmpty
                          ? null
                          : () => _copyToClipboard(
                              context,
                              member.phone,
                              'Phone',
                            ),
                    ),
                    const Divider(height: 1, color: _cFieldBg),
                    _InfoRow(
                      icon: Icons.mail_outline,
                      label: 'Email',
                      value: member.email,
                      onCopy: member.email.isEmpty
                          ? null
                          : () => _copyToClipboard(
                              context,
                              member.email,
                              'Email',
                            ),
                    ),
                  ],
                ),
              ),

              if (isOwner) ...[
                const SizedBox(height: 20),
                const Text(
                  'App access',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cInk,
                  ),
                ),
                const SizedBox(height: 8),
                _ClaimAccessSection(
                  hasAccount: hasAccount,
                  isCheckingAccount: isCheckingAccount,
                  isIssuingCode: isIssuingCode,
                  claimError: claimError,
                  issuedCode: issuedCode,
                  onIssueCode: onIssueCode,
                ),
              ],

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
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_cAccentBlue, _cGradientEnd],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onRenew,
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.autorenew,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Renew membership',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                                  'Archive member',
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

  String _relativeDay(DateTime when) {
    final today = DateTime.now();
    final isToday =
        when.year == today.year &&
        when.month == today.month &&
        when.day == today.day;
    if (isToday) return 'Today';
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday =
        when.year == yesterday.year &&
        when.month == yesterday.month &&
        when.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    return DateFormat('MMM d').format(when);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: _cMuted)),
              Icon(icon, size: 15, color: _cAccentBlue),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _cInk,
            ),
          ),
          if (sublabel.isNotEmpty)
            Text(
              sublabel,
              style: const TextStyle(fontSize: 11, color: _cMuted),
            ),
        ],
      ),
    );
  }
}

class _ClaimAccessSection extends StatelessWidget {
  const _ClaimAccessSection({
    required this.hasAccount,
    required this.isCheckingAccount,
    required this.isIssuingCode,
    required this.claimError,
    required this.issuedCode,
    required this.onIssueCode,
  });

  final bool? hasAccount;
  final bool isCheckingAccount;
  final bool isIssuingCode;
  final String? claimError;
  final Map<String, dynamic>? issuedCode;
  final VoidCallback onIssueCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (isCheckingAccount) {
      return const Row(
        children: [
          SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Checking account status…',
            style: TextStyle(fontSize: 13, color: _cMuted),
          ),
        ],
      );
    }

    if (hasAccount == true) {
      return const Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: _cActiveBg),
          SizedBox(width: 8),
          Text(
            'This member has set up their account.',
            style: TextStyle(fontSize: 13, color: _cInk),
          ),
        ],
      );
    }

    if (issuedCode != null) {
      final code = issuedCode!['claim_code'] as String? ?? '';
      final expiresAt = DateTime.tryParse(
        issuedCode!['expires_at'] as String? ?? '',
      );
      final expiryText = expiresAt != null
          ? 'Expires ${DateFormat('MMM d, yyyy').format(expiresAt)}'
          : '';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Give this code to the member',
            style: TextStyle(fontSize: 13, color: _cMuted),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _cFieldBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: _cInk,
              ),
            ),
          ),
          if (expiryText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              expiryText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _cMuted),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'It\'s one-time use — the member sets their own password with it. '
            "This screen won't show it again once you leave.",
            style: const TextStyle(fontSize: 11, color: _cMuted),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "This member hasn't set up app access yet.",
          style: TextStyle(fontSize: 13, color: _cMuted),
        ),
        if (claimError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _cErrorBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              claimError!,
              style: const TextStyle(color: _cErrorText, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isIssuingCode ? null : onIssueCode,
            style: FilledButton.styleFrom(
              backgroundColor: _cAccentBlue,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: isIssuingCode
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Set up app access',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

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
          if (onCopy != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.copy_outlined, size: 14, color: _cAccentBlue),
              ),
            ),
          ],
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
                backgroundColor: _cAccentBlue,
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
