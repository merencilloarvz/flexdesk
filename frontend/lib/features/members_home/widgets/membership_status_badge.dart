import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/member_status.dart';

/// Small filled pill naming a membership's state, colored the same way the
/// check-in screen and digital card color it. The state itself always comes
/// from [statusFor] — this only draws it.
class MembershipStatusBadge extends StatelessWidget {
  const MembershipStatusBadge({super.key, required this.status});

  final MembershipStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      MembershipStatus.active => (AppColors.activeBg, 'Active'),
      MembershipStatus.expiring => (AppColors.expiringBg, 'Expiring'),
      MembershipStatus.expired => (AppColors.expiredBg, 'Expired'),
      MembershipStatus.noMembership => (AppColors.noMembershipBg, 'No plan'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
    );
  }
}
