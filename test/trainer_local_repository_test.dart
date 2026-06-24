import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/data/trainer_local_repository.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TrainerLocalRepository saves and reloads trainer data', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = TrainerLocalRepository(preferences: preferences);

    final session = WorkoutLog(
      id: 'session-1',
      exerciseId: 'squat',
      date: DateTime(2026, 6, 22),
      sets: 3,
      reps: 10,
      weightKg: 40,
      durationSec: 600,
      rpe: 7,
      calories: 100,
      note: 'Test lokalnego zapisu',
      aiConfidence: 0,
    );
    const plan = WorkoutPlan(
      id: 'plan-1',
      name: 'Plan lokalny',
      days: [],
      note: '',
    );
    const exercise = Exercise(
      id: 'custom-1',
      name: 'Ćwiczenie testowe',
      category: 'Inne',
      muscles: ['całe ciało'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'generic',
      description: '',
      tips: [],
      commonMistakes: [],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 4,
      source: 'custom',
    );
    final bodyMeasurement = BodyMeasurement(
      id: 'measurement-1',
      date: DateTime(2026, 6, 24),
      weightKg: 98.4,
      waistCm: 92,
      chestCm: 112,
      armCm: 39,
      thighCm: 64,
      hipsCm: 105,
      calfCm: 41,
      shouldersCm: 128,
      note: 'Pomiar kontrolny',
    );

    await repository.saveSessions([session]);
    await repository.savePlans([plan]);
    await repository.saveCustomExercises([exercise]);
    await repository.saveBodyMeasurements([bodyMeasurement]);
    await repository.saveExerciseLibraryPreferences(
      const ExerciseLibraryPreferences(
        favoriteExerciseIds: {'custom-1'},
        hiddenExerciseIds: {'squat'},
      ),
    );
    await repository.saveActiveWorkoutSession(
      ActiveWorkoutSession(
        id: 'active-1',
        planId: 'plan-1',
        planName: 'Plan lokalny',
        weekday: DateTime.monday,
        dayTitle: 'Góra',
        startedAt: DateTime(2026, 6, 23, 18),
        currentExerciseIndex: 0,
        note: 'Notatka sesji',
        restTimerRemainingSeconds: 75,
        restTimerTotalSeconds: 120,
        isRestTimerPaused: true,
        exercises: const [
          ActiveWorkoutExercise(
            exerciseId: 'squat',
            plannedSets: 3,
            plannedReps: 10,
            suggestedWeightKg: 40,
            restSeconds: 90,
            note: '',
          ),
        ],
      ),
    );
    final restored = await repository.load();

    expect(restored.sessions.single.note, 'Test lokalnego zapisu');
    expect(restored.plans.single.name, 'Plan lokalny');
    expect(restored.customExercises.single.id, 'custom-1');
    expect(
      restored.exerciseLibraryPreferences.favoriteExerciseIds,
      contains('custom-1'),
    );
    expect(
      restored.exerciseLibraryPreferences.hiddenExerciseIds,
      contains('squat'),
    );
    expect(restored.activeWorkoutSession?.id, 'active-1');
    expect(
      restored.activeWorkoutSession?.exercises.single.suggestedWeightKg,
      40,
    );
    expect(restored.activeWorkoutSession?.note, 'Notatka sesji');
    expect(restored.activeWorkoutSession?.restTimerRemainingSeconds, 75);
    expect(restored.bodyMeasurements.single.weightKg, 98.4);
    expect(restored.bodyMeasurements.single.note, 'Pomiar kontrolny');
  });
}
