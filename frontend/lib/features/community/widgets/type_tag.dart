import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// The small ANNOUNCEMENT / EVENT pill shown on feed cards and on the
/// announcement detail screen, so both places tag a post the same way.
class TypeTag extends StatelessWidget {
  const TypeTag({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  /// Announcements run on the app's teal.
  const TypeTag.announcement({super.key})
    : label = 'ANNOUNCEMENT',
      icon = Icons.campaign_rounded,
      color = AppColors.accentTeal,
      bgColor = AppColors.accentTealBg;

  /// Events use the warm amber from the palette, so the two kinds read
  /// apart at a glance.
  const TypeTag.event({super.key})
    : label = 'EVENT',
      icon = Icons.emoji_events_outlined,
      color = AppColors.expiringBg,
      bgColor = AppColors.expiringIcon;

  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
