import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../shell/app_shell.dart';
import '../providers/workout_guides_providers.dart';
import '../widgets/guide_frame.dart';

class GuideDetailScreen extends ConsumerStatefulWidget {
  const GuideDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<GuideDetailScreen> createState() => _GuideDetailScreenState();
}

class _GuideDetailScreenState extends ConsumerState<GuideDetailScreen> {
  static const _frameInterval = Duration(milliseconds: 900);

  Timer? _timer;
  int _frameIndex = 0;
  bool _playing = true;
  int _frameCount = 1;

  @override
  void initState() {
    super.initState();
    // Read (not watch) — we only need the frame count once, to know
    // whether it's even worth starting the timer.
    final guide = ref.read(workoutGuideBySlugProvider(widget.slug));
    _frameCount = guide?.frames.length ?? 1;
    if (_frameCount > 1) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_frameInterval, (_) {
      setState(() => _frameIndex = (_frameIndex + 1) % _frameCount);
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    // A leaked periodic timer here is a real leak: this screen gets
    // opened and closed repeatedly as people browse guides.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guide = ref.watch(workoutGuideBySlugProvider(widget.slug));

    if (guide == null) {
      return const Scaffold(body: Center(child: Text('Guide not found')));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          // The nav bar floats over the shell body (AppShell.extendBody),
          // so anything scrollable here has to reserve room for it or the
          // last section ends up underneath it.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            AppShell.reservedNavHeight + 24,
          ),
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: GuideFrame(
                          key: ValueKey(_frameIndex),
                          assetPath: guide.framePath(
                            guide.frames[_frameIndex],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _RoundIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).pop(),
                        background: Colors.white.withValues(alpha: 0.9),
                        foreground: AppColors.ink,
                      ),
                    ),
                    if (guide.frames.length > 1)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: _RoundIconButton(
                          icon: _playing ? Icons.pause : Icons.play_arrow,
                          onTap: _togglePlay,
                          background: AppColors.accentTeal,
                          foreground: Colors.white,
                          size: 44,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(guide.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(guide.muscleGroup)),
                Chip(label: Text(guide.equipment)),
                Chip(label: Text(guide.difficulty)),
              ],
            ),
            const SizedBox(height: 24),
            Text('Steps', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...guide.steps.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accentTeal,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          entry.value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (guide.tips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          size: 18,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tips',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final tip in guide.tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $tip'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small circular overlay button used both for the back arrow and the
/// play/pause control on the illustration — same shape, different colors.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.size = 36,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.55, color: foreground),
        ),
      ),
    );
  }
}
