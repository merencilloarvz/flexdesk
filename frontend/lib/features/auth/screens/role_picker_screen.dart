import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/fade_slide_in.dart';

/// The very first screen an unauthenticated person sees. Deliberately
/// forces a choice before showing any form — the most likely user error
/// in the member-accounts feature is a member tapping "create account"
/// and accidentally creating an empty gym with themselves as owner. That
/// produces a dead account and a confused person, and this screen exists
/// specifically to prevent it.
class RolePickerScreen extends StatefulWidget {
  const RolePickerScreen({super.key});

  @override
  State<RolePickerScreen> createState() => _RolePickerScreenState();
}

enum _Portal { owner, member }

class _RolePickerScreenState extends State<RolePickerScreen> {
  // Defaults to owner to mirror the reference design; adjust if you'd
  // rather start with nothing selected.
  _Portal _selected = _Portal.owner;

  void _continue() {
    switch (_selected) {
      case _Portal.owner:
        context.push('/login/owner');
      case _Portal.member:
        context.push('/login/member');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                // At least the full viewport height — this is what makes
                // Center below actually center short content instead of
                // pinning it to the top with a dead gap underneath, while
                // still scrolling normally if content ever grows taller
                // than the screen (a small phone, a long help message).
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: FadeSlideIn(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 32),
                            const Center(child: AppLogo(size: 88)),
                            const SizedBox(height: 18),
                            Text(
                              'Welcome to FlexDesk',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'How will you be using the app?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _PortalCard(
                              icon: Icons.storefront_outlined,
                              title: 'I run a gym',
                              subtitle:
                                  'Check members in, sell at the counter, track '
                                  'sales and stock.',
                              selected: _selected == _Portal.owner,
                              onTap: () =>
                                  setState(() => _selected = _Portal.owner),
                            ),
                            const SizedBox(height: 12),
                            _PortalCard(
                              icon: Icons.person_outline,
                              title: "I'm a gym member",
                              subtitle:
                                  'Show your pass, see your visits, join events.',
                              selected: _selected == _Portal.member,
                              onTap: () =>
                                  setState(() => _selected = _Portal.member),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accentTeal,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                ),
                                onPressed: _continue,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Continue',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: TextButton(
                                onPressed: () => context.push('/help'),
                                child: Text(
                                  'Need help?',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTealBg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accentTeal : const Color(0xFFE3E8E6),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AppColors.accentTeal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accentTeal : Colors.grey.shade400,
          width: 1.6,
        ),
        color: Colors.white,
      ),
      child: selected
          ? const Center(
              child: SizedBox(
                width: 11,
                height: 11,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentTeal,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
