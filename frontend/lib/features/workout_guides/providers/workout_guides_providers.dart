import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workout_guide.dart';

/// Loads assets/workout_guides/guides.json once. Riverpod caches the
/// result after the first read — no network call, and no per-card
/// re-read, matching the same "load once, hold in memory" rule the
/// spec asked for, just via FutureProvider's built-in caching instead
/// of a hand-rolled ChangeNotifier.
final workoutGuidesProvider = FutureProvider<List<WorkoutGuide>>((ref) async {
  final raw = await rootBundle.loadString('assets/workout_guides/guides.json');
  final list = jsonDecode(raw) as List;
  return list
      .map((e) => WorkoutGuide.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Currently selected muscle-group filter chip. "All" shows everything.
final selectedMuscleGroupProvider = StateProvider<String>((ref) => 'All');

/// Muscle groups present in the data, plus "All", sorted, for the chip row.
final muscleGroupFiltersProvider = Provider<List<String>>((ref) {
  final guidesAsync = ref.watch(workoutGuidesProvider);
  final guides = guidesAsync.asData?.value ?? const <WorkoutGuide>[];
  final groups = guides.map((g) => g.muscleGroup).toSet().toList()..sort();
  return ['All', ...groups];
});

/// Guides filtered by the selected muscle group.
final filteredWorkoutGuidesProvider = Provider<List<WorkoutGuide>>((ref) {
  final guidesAsync = ref.watch(workoutGuidesProvider);
  final guides = guidesAsync.asData?.value ?? const <WorkoutGuide>[];
  final selected = ref.watch(selectedMuscleGroupProvider);
  if (selected == 'All') return guides;
  return guides.where((g) => g.muscleGroup == selected).toList();
});

/// Look up one guide by slug — used by the detail screen.
final workoutGuideBySlugProvider = Provider.family<WorkoutGuide?, String>(
  (ref, slug) {
    final guidesAsync = ref.watch(workoutGuidesProvider);
    final guides = guidesAsync.asData?.value ?? const <WorkoutGuide>[];
    for (final g in guides) {
      if (g.slug == slug) return g;
    }
    return null;
  },
);
