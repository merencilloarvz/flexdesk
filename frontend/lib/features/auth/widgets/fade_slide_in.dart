import 'package:flutter/material.dart';

/// A gentle, one-shot entrance for a whole screen's content — fades in
/// while sliding up a few percent of its own height. Deliberately short
/// (220ms) and small (3% slide) so it reads as "the screen settled in"
/// rather than a slow or flashy animation.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child});
  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.03),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
