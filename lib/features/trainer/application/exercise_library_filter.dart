import '../domain/trainer_models.dart';

class ExerciseLibraryFilter {
  const ExerciseLibraryFilter({
    this.query = '',
    this.muscleGroup,
    this.equipmentType,
    this.level,
    this.trainingGoal,
    this.onlyFavorites = false,
    this.showHidden = false,
  });

  final String query;
  final MuscleGroup? muscleGroup;
  final EquipmentType? equipmentType;
  final String? level;
  final TrainingGoal? trainingGoal;
  final bool onlyFavorites;
  final bool showHidden;

  List<Exercise> apply({
    required Iterable<Exercise> exercises,
    required ExerciseLibraryPreferences preferences,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final results = exercises.where((exercise) {
      if (!showHidden && preferences.isHidden(exercise.id)) return false;
      if (showHidden && !preferences.isHidden(exercise.id)) return false;
      if (onlyFavorites && !preferences.isFavorite(exercise.id)) return false;
      if (normalizedQuery.isNotEmpty &&
          !exercise.name.toLowerCase().contains(normalizedQuery)) {
        return false;
      }
      if (muscleGroup != null && !exercise.muscleGroups.contains(muscleGroup)) {
        return false;
      }
      if (equipmentType != null &&
          !exercise.equipmentTypes.contains(equipmentType)) {
        return false;
      }
      if (level != null && normalizeTrainingLevel(exercise.level) != level) {
        return false;
      }
      if (trainingGoal != null &&
          !exercise.typedTrainingGoals.contains(trainingGoal)) {
        return false;
      }
      return true;
    }).toList();

    results.sort((left, right) {
      final favoriteComparison =
          (preferences.isFavorite(right.id) ? 1 : 0).compareTo(
        preferences.isFavorite(left.id) ? 1 : 0,
      );
      if (favoriteComparison != 0) return favoriteComparison;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return results;
  }
}
