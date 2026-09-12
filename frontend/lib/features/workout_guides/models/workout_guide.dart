class WorkoutGuide {
  final String slug;
  final String name;
  final String muscleGroup;
  final String equipment;
  final String difficulty;
  final List<String> frames; // asset filenames, e.g. "push-up-1.svg"
  final List<String> steps;
  final List<String> tips;

  const WorkoutGuide({
    required this.slug,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.difficulty,
    required this.frames,
    required this.steps,
    required this.tips,
  });

  /// First frame — used as the grid-card thumbnail.
  String get thumbnailAsset => framePath(frames.first);

  String framePath(String filename) => 'assets/workout_guides/$filename';

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
    );
  }
}
