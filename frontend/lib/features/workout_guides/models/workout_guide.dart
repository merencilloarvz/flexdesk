import 'package:workout_flutter_guide/workout_flutter_guide.dart'
    as guide_catalog;

class WorkoutGuide {
  final String slug;
  final String name;
  final String muscleGroup;
  final String equipment;
  final String difficulty;
  final List<String> frames; // asset filenames, e.g. "push-up-1.svg"
  final List<String> steps;
  final List<String> tips;

  /// Slug into the `workout_flutter_guide` catalog, set only when this guide
  /// was confidently matched to a catalog exercise. When present, [framePath]
  /// resolves frames from the catalog instead of the local bundle, so the
  /// illustration can never drift from [name].
  final String? illustrationSlug;

  const WorkoutGuide({
    required this.slug,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.difficulty,
    required this.frames,
    required this.steps,
    required this.tips,
    this.illustrationSlug,
  });

  /// First frame — used as the grid-card thumbnail.
  String get thumbnailAsset => framePath(frames.first);

  static final RegExp _frameNumber = RegExp(r'-(\d+)\.svg$');

  /// Resolves a frame filename (e.g. "push-up-2.svg") to an asset path.
  ///
  /// When [illustrationSlug] is set, the frame number embedded in [filename]
  /// is used to pull the matching frame straight out of the
  /// `workout_flutter_guide` catalog. Falls back to the local bundled SVG
  /// otherwise, or if the catalog has no such frame.
  String framePath(String filename) {
    final catalogSlug = illustrationSlug;
    if (catalogSlug != null) {
      final match = _frameNumber.firstMatch(filename);
      final frameIndex = match != null ? int.parse(match.group(1)!) : 1;
      final catalogPath = guide_catalog.WorkoutGuide.assetPath(
        catalogSlug,
        frameIndex,
      );
      if (catalogPath != null) return catalogPath;
    }
    return 'assets/workout_guides/$filename';
  }

  factory WorkoutGuide.fromJson(Map<String, dynamic> json) {
    return WorkoutGuide(
      slug: json['slug'] as String,
      name: json['name'] as String,
      muscleGroup: json['muscle_group'] as String,
      equipment: json['equipment'] as String,
      difficulty: json['difficulty'] as String,
      frames: (json['frames'] as List).cast<String>(),
      steps: (json['steps'] as List).cast<String>(),
      tips: (json['tips'] as List).cast<String>(),
      illustrationSlug: json['package_slug'] as String?,
    );
  }
}
