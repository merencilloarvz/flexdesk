import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  static const _brandGreen = Color(0xFF0E5B44);
  static const _tealAccent = Color(0xFF14B89A);
  static const _bgTint = Color(0xFFF7F9F8);

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  // Logo mark
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _bgTint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE3E8E6)),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fitness_center,
                          color: _brandGreen,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'FlexDesk',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _brandGreen,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Smart club operations and athlete access\npass',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'SELECT PORTAL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PortalCard(
                    icon: Icons.storefront_outlined,
                    title: 'Gym Owner & Staff',
                    subtitle: 'Operations, floor POS & roster controls',
                    selected: _selected == _Portal.owner,
                    accent: _brandGreen,
                    onTap: () => setState(() => _selected = _Portal.owner),
                  ),
                  const SizedBox(height: 12),
                  _PortalCard(
                    icon: Icons.person_outline,
                    title: 'Gym Member & Athlete',
                    subtitle: 'Digital pass, workout streak & bookings',
                    selected: _selected == _Portal.member,
                    accent: _brandGreen,
                    onTap: () => setState(() => _selected = _Portal.member),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      onPressed: _continue,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _selected == _Portal.owner
                                ? 'Continue as Gym Owner'
                                : 'Continue as Gym Member',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () {},
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
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;
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
          color: selected ? accent.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE3E8E6),
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
              child: Icon(icon, size: 20, color: accent),
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
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RadioDot(selected: selected, color: accent),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : Colors.grey.shade400,
          width: 1.6,
        ),
        color: Colors.white,
      ),
      child: selected
          ? Center(
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            )
          : null,
    );
  }
}
