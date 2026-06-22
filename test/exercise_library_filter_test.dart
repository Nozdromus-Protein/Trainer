import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/exercise_library_filter.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

void main() {
  const squat = Exercise(
    id: 'squat',
    name: 'Przysiad',
    category: 'Nogi',
    muscles: ['czworogłowe uda', 'pośladki'],
    equipment: 'sztanga',
    level: 'Początkujący',
    illustrationType: 'squat',
    description: 'Technika przysiadu',
    tips: [],
    commonMistakes: [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: 5,
    trainingGoals: ['Siła'],
  );
  const run = Exercise(
    id: 'run',
    name: 'Bieganie',
    category: 'Kardio',
    muscles: ['wydolność', 'nogi'],
    equipment: 'bieżnia',
    level: 'Średniozaawansowany',
    illustrationType: 'run',
    description: 'Spokojny bieg',
    tips: [],
    commonMistakes: [],
    defaultSets: 1,
    defaultReps: 0,
    defaultDurationSec: 1200,
    met: 8,
    trainingGoals: ['Kondycja', 'Redukcja'],
  );

  test('search matches exercise name and filters typed metadata', () {
    const filter = ExerciseLibraryFilter(
      query: 'przy',
      muscleGroup: MuscleGroup.quadriceps,
      equipmentType: EquipmentType.barbell,
      level: 'Początkujący',
      trainingGoal: TrainingGoal.strength,
    );

    final result = filter.apply(
      exercises: const [squat, run],
      preferences: const ExerciseLibraryPreferences(),
    );

    expect(result.map((exercise) => exercise.id), ['squat']);
  });

  test('hidden and favorite views use persisted preferences', () {
    const preferences = ExerciseLibraryPreferences(
      favoriteExerciseIds: {'run'},
      hiddenExerciseIds: {'squat'},
    );

    final visibleFavorites = const ExerciseLibraryFilter(
      onlyFavorites: true,
    ).apply(
      exercises: const [squat, run],
      preferences: preferences,
    );
    final hidden = const ExerciseLibraryFilter(showHidden: true).apply(
      exercises: const [squat, run],
      preferences: preferences,
    );

    expect(visibleFavorites.map((exercise) => exercise.id), ['run']);
    expect(hidden.map((exercise) => exercise.id), ['squat']);
  });
}
