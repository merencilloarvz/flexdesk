import 'package:flutter/material.dart';

/// Central palette. The teal/ink system below is FINAL — confirmed and in
/// use across screens. Only `navActiveHighlight` remains an open
/// placeholder (eyeballed, not a confirmed brand color).
///
/// Nothing elsewhere should define its own Color(0x...) for these roles;
/// import and reference these instead.
class AppColors {
  AppColors._();

  // ---- Backgrounds ----
  static const pageBg = Color(0xFFEDEFF0);
  static const cardBg = Colors.white;
  static const fieldBg = Color(0xFFF5F6F7);
  static const border = Color(0xFFD8DAD5);

  // ---- Text ----
  static const ink = Color(0xFF0E1A13); // primary text/headings
  static const subtle = Color(0xFF6B7570); // secondary text/labels
  static const muted = Color(0xFF8A938E); // tertiary/helper text

  // ---- Accent ----
  static const accentTeal = Color(0xFF0F6E56); // primary brand accent
  static const accentGreen = Color(0xFF39C77F); // small badge dot accent
  static const linkGreen = Color(0xFF1F7A4D); // success icon/link color

  // ---- Status: membership states (member list avatars/labels) ----
  static const activeBg = Color(0xFF0F6E56);
  static const activeIcon = Color(0xFFE1F5EE);
  static const expiringBg = Color(0xFF92600B);
  static const expiringIcon = Color(0xFFFBEEDC);
  static const expiredBg = Color(0xFF9E3125);
  static const expiredIcon = Color(0xFFFCEBE8);
  static const noMembershipBg = Color(0xFF5F6462);
  static const noMembershipIcon = Colors.white;

  // ---- Status: banners (error/success) ----
  static const errorBg = Color(0xFFFCEBE8);
  static const errorText = Color(0xFF9E3125);
  static const successBg = Color(0xFFE6F6ED);

  // ---- Disabled state ----
  static const disabledBg = Color(0xFFE2E5E3);
  static const disabledLabel = Color(0xFF9AA39E);

  // ---- Bottom nav ----
  // Currently an eyeballed lime/yellow match to the reference design —
  // not a confirmed brand color. The only genuinely open value here.
  static const navActiveHighlight = Color(0xFFD4FA3D);

  // Icon/text color shown ON TOP of navActiveHighlight (must stay
  // readable against it — black works for a light lime, revisit if the
  // final highlight color is darker).
  static const navActiveForeground = Colors.black;

  // Inactive nav icon color.
  static const navInactiveForeground = Colors.white70;
}
