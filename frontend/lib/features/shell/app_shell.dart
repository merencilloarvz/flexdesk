import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final List<({IconData icon, String label, int branchIndex})> tabs;

  // Which branch (if any) gets the raised circular center button. Pass
  // null for a flat, evenly-spaced bar with no raised button — see the
  // member shell in app_router.dart. branchIndex, not list position, is
  // what's compared against — that's what stays correct when `tabs` is a
  // shorter list than the shell's real branch count (e.g. the member
  // shell with Schedule hidden).
  final int? centerBranchIndex;

  const AppShell({
    super.key,
    required this.navigationShell,
    required this.tabs,
    this.centerBranchIndex,
  });

  // Bumped from 76 to accommodate the taller labeled bar + the raised
  // center button's overhang. Every screen that pads for the nav bar
  // reads this constant (never a hardcoded number), so raising it here
  // is enough — check_in_screen.dart and members_list_screen.dart pick
  // it up automatically.
  static const double _barHeight = 60;
  static const double _centerOverhang = 20;
  static const double reservedNavHeight = _barHeight + _centerOverhang + 12;

  @override
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;

    // Found by branchIndex, not list position — a shell with fewer tabs
    // visible than branches (member shell, Schedule hidden) must not
    // accidentally match centerBranchIndex against the wrong entry.
    ({IconData icon, String label, int branchIndex})? centerTab;
    if (centerBranchIndex != null) {
      for (final tab in tabs) {
        if (tab.branchIndex == centerBranchIndex) {
          centerTab = tab;
          break;
        }
      }
    }

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            height: _barHeight + _centerOverhang,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: _centerOverhang,
                  left: 0,
                  right: 0,
                  height: _barHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final tab in tabs)
                          if (tab.branchIndex == centerBranchIndex)
                            // Empty slot — the raised center button sits
                            // visually above this gap, positioned
                            // separately below.
                            const SizedBox(width: 56)
                          else
                            _NavItem(
                              icon: tab.icon,
                              label: tab.label,
                              active: tab.branchIndex == currentIndex,
                              onTap: () => navigationShell.goBranch(
                                tab.branchIndex,
                                initialLocation:
                                    tab.branchIndex ==
                                    navigationShell.currentIndex,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                if (centerTab != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _CenterButton(
                        icon: centerTab.icon,
                        active: currentIndex == centerTab.branchIndex,
                        onTap: () => navigationShell.goBranch(
                          centerTab!.branchIndex,
                          initialLocation:
                              centerTab.branchIndex ==
                              navigationShell.currentIndex,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentBlue : AppColors.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.accentBlue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentBlue.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 24, color: Colors.white),
      ),
    );
  }
}
