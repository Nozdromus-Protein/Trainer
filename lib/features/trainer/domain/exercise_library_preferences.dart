class ExerciseLibraryPreferences {
  const ExerciseLibraryPreferences({
    this.favoriteExerciseIds = const {},
    this.hiddenExerciseIds = const {},
  });

  final Set<String> favoriteExerciseIds;
  final Set<String> hiddenExerciseIds;

  bool isFavorite(String exerciseId) =>
      favoriteExerciseIds.contains(exerciseId);

  bool isHidden(String exerciseId) => hiddenExerciseIds.contains(exerciseId);

  ExerciseLibraryPreferences copyWith({
    Set<String>? favoriteExerciseIds,
    Set<String>? hiddenExerciseIds,
  }) {
    return ExerciseLibraryPreferences(
      favoriteExerciseIds: favoriteExerciseIds ?? this.favoriteExerciseIds,
      hiddenExerciseIds: hiddenExerciseIds ?? this.hiddenExerciseIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'favoriteExerciseIds': favoriteExerciseIds.toList()..sort(),
        'hiddenExerciseIds': hiddenExerciseIds.toList()..sort(),
      };

  factory ExerciseLibraryPreferences.fromJson(
    Map<String, dynamic> json,
  ) {
    return ExerciseLibraryPreferences(
      favoriteExerciseIds: _stringSet(json['favoriteExerciseIds']),
      hiddenExerciseIds: _stringSet(json['hiddenExerciseIds']),
    );
  }
}

Set<String> _stringSet(Object? value) {
  if (value is! List) return <String>{};
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}
