import 'package:flutter/material.dart';

/// Central palette. Values below are PLACEHOLDERS — finalize the real
/// hex codes once screens are done, then update only this file. Nothing
/// elsewhere should define its own Color(0x...) for these roles again;
/// import and reference these instead.
class AppColors {
  AppColors._();

  // Bottom nav active-icon highlight (currently an eyeballed lime/yellow
  // match to the reference design — not a confirmed brand color).
  static const navActiveHighlight = Color(0xFFD4FA3D);

  // Icon/text color shown ON TOP of navActiveHighlight (must stay
  // readable against it — black works for a light lime, revisit if the
  // final highlight color is darker).
  static const navActiveForeground = Colors.black;

  // Inactive nav icon color.
  static const navInactiveForeground = Colors.white70;
}
