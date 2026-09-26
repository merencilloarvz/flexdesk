import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../providers/auth_providers.dart';

const _pageCount = 3;

/// Shown exactly once, right after a gym owner account is created —
/// password signup or Google, both land here the same way, since
/// app_router.dart's redirect gates on User.hasSeenOwnerWelcome, not on
/// which auth method produced the account. Replaces the old forced
/// /setup pricing step: nothing routes there automatically any more,
/// and this screen's own third slide covers the same "you can price
/// things later" ground without blocking anyone on it.
class OwnerWelcomeScreen extends ConsumerStatefulWidget {
  const OwnerWelcomeScreen({super.key});

  @override
  ConsumerState<OwnerWelcomeScreen> createState() => _OwnerWelcomeScreenState();
}

class _OwnerWelcomeScreenState extends ConsumerState<OwnerWelcomeScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  // One shared entrance animation, restarted on every page change —
  // simpler and cheaper than giving each of the 3 slides its own
  // controller, and the visual result (a gentle fade-and-rise "as each
  // slide arrives") is identical either way.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));

  @override
  void dispose() {
    _pageController.dispose();
    _entrance.dispose();
    super.dispose();
  }

  String get _firstName {
    final authState = ref.read(authControllerProvider);
    final full = authState is AuthAuthenticated
        ? authState.user.fullName.trim()
        : '';
    if (full.isNotEmpty) return full.split(RegExp(r'\s+')).first;
    // No name on the account: greet by gym name rather than "Welcome, !".
    final gymName = authState is AuthAuthenticated
        ? (authState.user.gym?.name ?? '').trim()
        : '';
    return gymName.isEmpty ? 'there' : gymName;
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _entrance.forward(from: 0);
  }

  void _onPrimaryButtonTap() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  // Skip and the final "Get started" both do exactly this — the only
  // difference between them is which slide the person was looking at
  // when they tapped. Never blocks on the network: a failed call here
  // just means this screen shows once more next launch, not that the
  // owner gets stuck looking at it now.
  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    try {
      await ref.read(authControllerProvider.notifier).markOwnerWelcomeSeen();
    } catch (_) {
      // Best-effort — see doc comment above.
    }
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _AnimatedSlide(
                        opacity: _opacity,
                        slide: _slide,
                        child: _CelebrationSlide(firstName: _firstName),
                      ),
                      _AnimatedSlide(
                        opacity: _opacity,
                        slide: _slide,
                        child: const _QuickTourSlide(),
                      ),
                      _AnimatedSlide(
                        opacity: _opacity,
                        slide: _slide,
                        child: const _SetupSlide(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pageCount; i++)
                            _Dot(active: i == _currentPage),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentTeal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          onPressed: _isFinishing ? null : _onPrimaryButtonTap,
                          child: _isFinishing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentPage < _pageCount - 1
                                          ? 'Next'
                                          : 'Get started',
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
                    ],
                  ),
                ),
              ],
            ),
            // Deliberately outside the fade/slide transition above and
            // on its own layer — must stay instantly tappable regardless
            // of where the entrance animation is, on every slide.
            Positioned(
              top: 4,
              right: 4,
              child: TextButton(
                onPressed: _isFinishing ? null : _finish,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSlide extends StatelessWidget {
  const _AnimatedSlide({
    required this.opacity,
    required this.slide,
    required this.child,
  });

  final Animation<double> opacity;
  final Animation<Offset> slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

class _CelebrationSlide extends StatelessWidget {
  const _CelebrationSlide({required this.firstName});
  final String firstName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _CelebrationBadge(),
            const SizedBox(height: 24),
            Text(
              'Welcome, $firstName!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentTealBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '14 days free',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentTeal,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Your gym is set up and your free trial has started. "
              "No card needed until it ends — we'll remind you.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.subtle,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one deliberately-flashier touch on this whole screen — everything
/// else uses the shared fade/rise, but slide 1 gets its own small
/// scale-in "pop" on the badge. Plays once: this widget lives inside a
/// plain (non-builder) PageView, so it's built once for the life of the
/// welcome screen and never remounts just from swiping back to it.
class _CelebrationBadge extends StatefulWidget {
  const _CelebrationBadge();

  @override
  State<_CelebrationBadge> createState() => _CelebrationBadgeState();
}

class _CelebrationBadgeState extends State<_CelebrationBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.elasticOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          color: AppColors.accentTeal,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.celebration, color: Colors.white, size: 40),
      ),
    );
  }
}

class _QuickTourSlide extends StatelessWidget {
  const _QuickTourSlide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A quick tour',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Three things you'll do most.",
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),
            const _TourItem(
              icon: Icons.person_add_alt_outlined,
              title: 'Add members',
              body:
                  'Create a member profile, then hand them a claim code '
                  'to set up their own login.',
            ),
            const SizedBox(height: 18),
            const _TourItem(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Check people in',
              body:
                  "Scan a member's pass, or log a walk-in from the "
                  'Check-In tab.',
            ),
            const SizedBox(height: 18),
            const _TourItem(
              icon: Icons.point_of_sale_outlined,
              title: 'Sell at the counter',
              body: 'Add products to the cart and check out from POS.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupSlide extends StatelessWidget {
  const _SetupSlide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A couple of things for later',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No rush — both can wait.',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),
            const _TourItem(
              icon: Icons.sell_outlined,
              title: 'Membership plans',
              body: "Set your pricing and tiers whenever you're ready.",
            ),
            const SizedBox(height: 18),
            const _TourItem(
              icon: Icons.inventory_2_outlined,
              title: 'Store items',
              body: 'Add products to sell at the counter.',
            ),
            const SizedBox(height: 24),
            Text(
              'You can set both of these up any time from Settings.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourItem extends StatelessWidget {
  const _TourItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.accentTealBg,
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
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.accentTeal : AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
