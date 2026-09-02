import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/gym_time.dart';
import '../../core/utils/member_status.dart';
import '../shell/app_shell.dart';
import '../auth/providers/auth_providers.dart';
import '../members/data/check_ins_repository.dart';
import '../members/providers/check_ins_provider.dart';
import '../members/providers/members_providers.dart';

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

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.gymId});

  final String gymId;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Default walk-in rates. Local-only, per-device — not synced anywhere;
  // just pre-fills the price field so staff usually don't have to type
  // one. Actually charging a different amount for a given visit is done
  // by editing the price field on the confirm step itself, not here.
  int _studentDefaultCentavos = 8000;
  int _regularDefaultCentavos = 15000;

  String? _walkInCategory; // 'student' | 'regular' | null
  final _walkInNameController = TextEditingController();
  bool _walkInSubmitting = false;
  String? _walkInError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(checkInsRepositoryProvider)
          .refreshCheckIns(widget.gymId, day: GymTime.today());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _walkInNameController.dispose();
    super.dispose();
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

  Future<void> _editDefaultPrices() async {
    final studentCtrl = TextEditingController(
      text: (_studentDefaultCentavos / 100).toStringAsFixed(0),
    );
    final regularCtrl = TextEditingController(
      text: (_regularDefaultCentavos / 100).toStringAsFixed(0),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit walk-in prices'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: studentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Student (₱)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: regularCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Regular (₱)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _studentDefaultCentavos =
            (int.tryParse(studentCtrl.text) ?? _studentDefaultCentavos ~/ 100) *
            100;
        _regularDefaultCentavos =
            (int.tryParse(regularCtrl.text) ?? _regularDefaultCentavos ~/ 100) *
            100;
      });
    }
  }

  void _selectWalkInCategory(String category) {
    setState(() {
      _walkInCategory = category;
    });
  }

  Future<void> _submitWalkIn(String? locationId) async {
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
    if (_walkInCategory == null) {
      setState(() => _walkInError = 'Pick Student or Regular.');
      return;
    }

    final priceCentavos = _walkInCategory == 'student'
        ? _studentDefaultCentavos
        : _regularDefaultCentavos;

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
          category: _walkInCategory!,
          amountChargedCentavos: priceCentavos,
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
      _walkInCategory = null;
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
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
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

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Front Desk Check-in',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
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

              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: AppShell.reservedNavHeight + 24,
                  ),
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
                            'Member or Guest Name',
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
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: "Enter member's or guest's name",
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
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),

                          // Search results — tapping one always opens the
                          // confirm sheet, never checks in on a single tap.
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            membersAsync.when(
                              data: (members) {
                                final matches = _matchingMembers(members);
                                if (matches.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No matching member — check the '
                                      'category below to check in as a '
                                      'walk-in guest instead.',
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
                                        onTap: () => _openMemberConfirmSheet(
                                          member,
                                          locationId,
                                          todaysCheckIns,
                                        ),
                                      ),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                          ] else ...[
                            const SizedBox(height: 18),
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
                                controller: _walkInNameController,
                                decoration: const InputDecoration(
                                  hintText: "Enter guest's name",
                                  hintStyle: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 14,
                                  ),
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
                                  onTap: _editDefaultPrices,
                                  child: Row(
                                    children: const [
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
                            Row(
                              children: [
                                Expanded(
                                  child: _CategoryChip(
                                    label: 'Student',
                                    priceCentavos: _studentDefaultCentavos,
                                    selected: _walkInCategory == 'student',
                                    onTap: () =>
                                        _selectWalkInCategory('student'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CategoryChip(
                                    label: 'Regular',
                                    priceCentavos: _regularDefaultCentavos,
                                    selected: _walkInCategory == 'regular',
                                    onTap: () =>
                                        _selectWalkInCategory('regular'),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),
                            if (_walkInError != null) ...[
                              Text(
                                _walkInError!,
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
                                onPressed: _walkInSubmitting
                                    ? null
                                    : () => _submitWalkIn(locationId),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accentTeal,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _walkInSubmitting
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      'Checked In Today',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),

                    checkInsAsync.when(
                      data: (checkIns) {
                        if (checkIns.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No check-ins yet today',
                              style: TextStyle(color: AppColors.subtle),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final checkIn in checkIns)
                              _CheckInTile(checkIn: checkIn),
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (error, _) => Text('Something went wrong: $error'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.member,
    required this.today,
    required this.onTap,
  });

  final Member member;
  final DateTime today;
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
          child: Row(
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
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.priceCentavos,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int priceCentavos;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTeal : AppColors.pageBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '₱${(priceCentavos / 100).toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white70 : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInTile extends ConsumerWidget {
  const _CheckInTile({required this.checkIn});

  final CheckIn checkIn;

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voided = checkIn.voidedAt != null;

    Widget content(String name, String subtitle) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              voided ? Icons.remove_circle_outline : Icons.check_circle,
              color: voided ? AppColors.muted : AppColors.activeBg,
              size: 22,
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
                  Text(
                    _relativeTime(checkIn.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
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

    if (checkIn.visitType == 'WALKIN') {
      final price = checkIn.amountChargedCentavos != null
          ? '₱${(checkIn.amountChargedCentavos! / 100).toStringAsFixed(0)}'
          : '';
      final label = checkIn.category.isEmpty
          ? 'Walk-in'
          : checkIn.category[0].toUpperCase() + checkIn.category.substring(1);
      return content(
        checkIn.visitorName.isEmpty ? 'Guest' : checkIn.visitorName,
        price.isEmpty ? label : '$label · $price',
      );
    }

    final memberAsync = checkIn.memberId != null
        ? ref.watch(memberByIdProvider(checkIn.memberId!))
        : null;
    final name = memberAsync?.asData?.value != null
        ? '${memberAsync!.asData!.value!.firstName} '
                  '${memberAsync.asData!.value!.lastName}'
              .trim()
        : 'Member';

    final endDate = checkIn.membershipEndDate;
    final subtitle = endDate != null
        ? () {
            final remaining = daysRemaining(endDate, GymTime.today());
            if (remaining == null) return checkIn.membershipStatus;
            if (remaining < 0) return 'ACTIVE';
            return '$remaining DAYS LEFT';
          }()
        : checkIn.membershipStatus.toUpperCase();

    return content(name, subtitle);
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
      MembershipStatus.active => (AppColors.activeBg, 'Active'),
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
                    ? 'This membership has expired. You can still check '
                          'them in — the gym decides who gets in.'
                    : 'This person has no active membership. You can '
                          'still check them in.',
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
                backgroundColor: AppColors.accentTeal,
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
                  : const Text('Confirm Check In'),
            ),
          ),
        ],
      ),
    );
  }
}
