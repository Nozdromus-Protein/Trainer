import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/data/trainer_calorie_adapter.dart';
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
    final impact = TrainingImpact(
      id: 'impact-session-1',
      sessionId: 'session-1',
      sessionName: 'Plan lokalny · Góra',
      date: DateTime(2026, 6, 24, 18),
      isTrainingDay: true,
      estimatedBurnedKcal: 320,
      suggestedCalorieAdjustmentKcal: 160,
      suggestedExtraWaterMl: 650,
      suggestedExtraProteinG: 30,
      postWorkoutMealSuggestion: 'Białko + węgle po treningu',
      durationMin: 45,
      exerciseCount: 4,
      setCount: 12,
      volumeKg: 7200,
      averageRpe: 8,
      createdAt: DateTime(2026, 6, 24, 19),
    );
    final activityEntry = TrainerActivityEntry(
      id: 'steps-1',
      date: DateTime(2026, 6, 24, 12),
      source: TrainerActivitySource.steps,
      type: TrainerActivityType.ordinaryStepsWalk,
      estimatedKcal: 180,
      sourceActivityId: 'steps-2026-06-24',
      durationMin: 120,
      steps: 8200,
      note: 'Kroki z wejścia lokalnego',
    );

    await repository.saveSessions([session]);
    await repository.savePlans([plan]);
    await repository.saveCustomExercises([exercise]);
    await repository.saveBodyMeasurements([bodyMeasurement]);
    await repository.saveTrainingImpacts([impact]);
    await repository.saveActivityEntries([activityEntry]);
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
    expect(restored.trainingImpacts.single.estimatedBurnedKcal, 320);
    expect(restored.trainingImpacts.single.deduplicationKey, 'Trainer:session-1:2026-06-24');
    expect(restored.activityEntries.single.steps, 8200);
    expect(restored.activityEntries.single.source, TrainerActivitySource.steps);
  });

  test('TrainerCalorieLocalAdapter publishes deduplicated bridge payload', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final adapter = TrainerCalorieLocalAdapter(preferences: preferences);
    final older = TrainingImpact(
      id: 'impact-session-1-old',
      sessionId: 'session-1',
      sessionName: 'Stary wpis',
      date: DateTime(2026, 6, 24, 18),
      isTrainingDay: true,
      estimatedBurnedKcal: 120,
      suggestedCalorieAdjustmentKcal: 60,
      suggestedExtraWaterMl: 500,
      suggestedExtraProteinG: 25,
      postWorkoutMealSuggestion: 'Stary wpis',
      durationMin: 20,
      exerciseCount: 2,
      setCount: 6,
      volumeKg: 3000,
      averageRpe: 7,
      createdAt: DateTime(2026, 6, 24, 18, 30),
    );
    final newer = TrainingImpact(
      id: 'impact-session-1-new',
      sessionId: 'session-1',
      sessionName: 'Nowy wpis',
      date: DateTime(2026, 6, 24, 19),
      isTrainingDay: true,
      estimatedBurnedKcal: 240,
      suggestedCalorieAdjustmentKcal: 120,
      suggestedExtraWaterMl: 650,
      suggestedExtraProteinG: 30,
      postWorkoutMealSuggestion: 'Nowy wpis',
      durationMin: 40,
      exerciseCount: 3,
      setCount: 9,
      volumeKg: 5200,
      averageRpe: 8,
      createdAt: DateTime(2026, 6, 24, 19, 30),
    );

    await adapter.publishTrainingImpacts([older, newer]);

    final payload = await adapter.loadBridgePayload();
    expect(payload, hasLength(1));
    expect(payload.single['schema'], TrainingImpact.schema);
    expect(payload.single['deduplicationKey'], 'Trainer:session-1:2026-06-24');
    expect(payload.single['estimatedBurnedKcal'], 240);
    expect(preferences.getString(TrainerCalorieLocalAdapter.latestImpactKey), isNotNull);
  });
}
