import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';

/// Persistent shell wrapping the main tabs. Every future top-level screen
/// should be added as a tab here rather than getting its own one-off route.
///
/// Color values live in core/theme/colors.dart (currently placeholders —
/// see that file's doc comment).
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/home', icon: Icons.home_outlined, label: 'Home'),
    (path: '/members', icon: Icons.people_outline, label: 'Members'),
    (path: '/checkin', icon: Icons.qr_code_scanner_outlined, label: 'Check-In'),
    (path: '/pos', icon: Icons.point_of_sale_outlined, label: 'POS'),
    (path: '/inventory', icon: Icons.inventory_2_outlined, label: 'Inventory'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      extendBody: true, // lets content scroll behind the floating pill nav
      body: Stack(
        children: [
          child,

          // Persistent settings gear — floats above every screen in the
          // shell, so logout/settings is always one tap away regardless
          // of which tab is active. Uses push (not go) so the back
          // button returns to whichever tab you came from.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _GlassIconButton(
              icon: Icons.settings_outlined,
              onTap: () => context.push('/settings'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      _NavIcon(
                        icon: _tabs[i].icon,
                        active: i == currentIndex,
                        activeColor: AppColors.navActiveHighlight,
                        onTap: () {
                          if (i != currentIndex) context.go(_tabs[i].path);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? activeColor : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: active
              ? AppColors.navActiveForeground
              : AppColors.navInactiveForeground,
          size: 22,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 20),
            onPressed: onTap,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
