import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// The card surface for a community post: white with the faintest wash of
/// its type's [accent] color, and a slim accent bar down the left edge.
/// Announcements (teal) and events (amber) share it, so they read as one
/// family but are distinguishable at a glance.
///
/// With an [onTap] the whole card is a tap target (inner buttons like the
/// like heart still win their own taps).
class AccentCard extends StatelessWidget {
  const AccentCard({
    super.key,
    required this.accent,
    required this.child,
    this.onTap,
  });

  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  static const double _barWidth = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.04), AppColors.cardBg),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16 + _barWidth, 16, 16, 12),
                child: child,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _barWidth,
            child: ColoredBox(color: accent),
          ),
        ],
      ),
    );
  }
}

/// "Pinned" marker for a pinned announcement.
class PinnedLabel extends StatelessWidget {
  const PinnedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.push_pin_outlined, size: 14, color: AppColors.muted),
        SizedBox(width: 3),
        Text(
          'Pinned',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}
