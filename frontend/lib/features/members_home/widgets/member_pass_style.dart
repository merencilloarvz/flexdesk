import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// The member-pass look: a dark run built from the palette itself, the ink
/// green-black easing into the accent teal. Shared by the home screen's
/// pass card and the digital check-in card so the two read as one object.
final LinearGradient memberPassGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    AppColors.ink,
    Color.lerp(AppColors.ink, AppColors.accentTeal, 0.45)!,
    Color.lerp(AppColors.ink, AppColors.accentTeal, 0.85)!,
  ],
);

/// Faint concentric rings behind the right edge — pure texture.
class MemberPassRingsPainter extends CustomPainter {
  const MemberPassRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = AppColors.accentGreen.withValues(alpha: 0.1);

    final center = Offset(size.width * 0.92, size.height * 0.52);
    for (final r in const [50.0, 85.0, 120.0, 155.0, 190.0, 225.0]) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
