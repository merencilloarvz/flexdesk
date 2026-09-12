import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(title: Text(guide.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: GuideFrame(
                      key: ValueKey(_frameIndex),
                      assetPath: guide.framePath(guide.frames[_frameIndex]),
                    ),
                  ),
                  if (guide.frames.length > 1)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: FloatingActionButton.small(
                        heroTag: 'guide_play_pause',
                        onPressed: _togglePlay,
                        child: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          ...guide.steps.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.key + 1}. ',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(entry.value)),
                    ],
                  ),
                ),
              ),
          if (guide.tips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tips', style: Theme.of(context).textTheme.titleSmall),
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
    );
  }
}
