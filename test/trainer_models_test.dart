import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

void main() {
  group('Trainer domain models', () {
    test('Exercise preserves JSON and exposes typed classifications', () {
      const exercise = Exercise(
        id: 'squat',
        name: 'Przysiad',
        category: 'Nogi',
        muscles: ['czworogłowe uda', 'pośladki', 'core'],
        equipment: 'masa ciała / hantle',
        level: 'Początkujący',
        illustrationType: 'squat',
        description: 'Opis',
        tips: ['Wskazówka'],
        commonMistakes: ['Błąd'],
        defaultSets: 3,
        defaultReps: 10,
        defaultDurationSec: 0,
        met: 5,
        trainingGoals: ['Siła', 'Masa mięśniowa'],
        avoidWhen: ['Ostry ból kolana'],
        alternatives: ['Przysiad do ławki'],
        executionSteps: ['Ustaw stopy.', 'Wykonaj przysiad.'],
        breathing: 'Wdech w dół, wydech w górę.',
        tempo: '3–1–1',
        easierVersion: 'Przysiad do ławki.',
        harderVersion: 'Przysiad z obciążeniem.',
      );

      final restored = Exercise.fromJson(exercise.toJson());

      expect(restored.id, exercise.id);
      expect(restored.muscleGroups, contains(MuscleGroup.quadriceps));
      expect(restored.muscleGroups, contains(MuscleGroup.glutes));
      expect(restored.equipmentTypes, contains(EquipmentType.bodyweight));
      expect(restored.equipmentTypes, contains(EquipmentType.dumbbell));
      expect(restored.primaryMuscle, 'czworogłowe uda');
      expect(restored.supportingMuscles, contains('pośladki'));
      expect(restored.typedTrainingGoals, contains(TrainingGoal.strength));
      expect(restored.avoidWhen, contains('Ostry ból kolana'));
      expect(restored.alternatives, contains('Przysiad do ławki'));
      expect(restored.executionSteps, hasLength(2));
      expect(restored.breathing, contains('wydech'));
      expect(restored.tempo, '3–1–1');
      expect(restored.easierVersion, 'Przysiad do ławki.');
      expect(restored.harderVersion, 'Przysiad z obciążeniem.');
    });

    test('ExerciseMedia round-trips through JSON', () {
      final media = ExerciseMedia(
        id: 'media-1',
        exerciseId: 'pushup',
        type: MediaType.gif,
        localPath: 'assets/exercises/pushup.gif',
        thumbnailPath: 'assets/exercises/pushup_thumb.png',
        title: 'Animacja pompki',
        description: 'Pełny zakres ruchu.',
        isPrimary: true,
        createdAt: DateTime(2026, 6, 27, 12),
      );

      final restored = ExerciseMedia.fromJson(media.toJson());

      expect(restored.id, 'media-1');
      expect(restored.exerciseId, 'pushup');
      expect(restored.type, MediaType.gif);
      expect(restored.effectivePath, 'assets/exercises/pushup.gif');
      expect(restored.thumbnail, 'assets/exercises/pushup_thumb.png');
      expect(restored.isPrimary, isTrue);
      expect(restored.isRemote, isFalse);
      expect(restored.createdAt, DateTime(2026, 6, 27, 12));
    });

    test('MediaType.fromKey is crash-safe for unknown values', () {
      expect(MediaType.fromKey('gif'), MediaType.gif);
      expect(MediaType.fromKey('youtube'), MediaType.url);
      expect(MediaType.fromKey(null), MediaType.none);
      expect(MediaType.fromKey('totally-unknown'), MediaType.none);
    });

    test('Exercise resolves primary media for thumbnail and animation', () {
      const exercise = Exercise(
        id: 'pushup',
        name: 'Pompka',
        category: 'Klatka i ręce',
        muscles: ['klatka piersiowa', 'triceps'],
        equipment: 'masa ciała',
        level: 'Początkujący',
        illustrationType: 'pushup',
        description: 'Opis',
        tips: [],
        commonMistakes: [],
        defaultSets: 4,
        defaultReps: 12,
        defaultDurationSec: 0,
        met: 4,
        mediaItems: [
          ExerciseMedia(
            id: 'photo',
            exerciseId: 'pushup',
            type: MediaType.image,
            localPath: 'assets/exercises/pushup_bottom.png',
          ),
          ExerciseMedia(
            id: 'gif',
            exerciseId: 'pushup',
            type: MediaType.gif,
            localPath: 'assets/exercises/pushup.gif',
            thumbnailPath: 'assets/exercises/pushup_thumb.png',
            isPrimary: true,
          ),
          ExerciseMedia(
            id: 'video',
            exerciseId: 'pushup',
            type: MediaType.url,
            remoteUrl: 'https://example.com/pushup',
          ),
        ],
      );

      final restored = Exercise.fromJson(exercise.toJson());

      expect(restored.mediaItems, hasLength(3));
      expect(restored.primaryMedia?.id, 'gif');
      expect(restored.animatedMediaPath, 'assets/exercises/pushup.gif');
      expect(restored.staticMediaPath, 'assets/exercises/pushup_bottom.png');
      expect(restored.thumbnailMediaPath, 'assets/exercises/pushup_thumb.png');
      expect(restored.videoMediaPath, 'https://example.com/pushup');
      expect(restored.hasMedia, isTrue);
      expect(restored.hasVideo, isTrue);
    });

    test('Exercise without media exposes no paths and never crashes', () {
      const exercise = Exercise(
        id: 'rest',
        name: 'Bez mediów',
        category: 'Inne',
        muscles: ['całe ciało'],
        equipment: 'masa ciała',
        level: 'Początkujący',
        illustrationType: 'generic',
        description: '',
        tips: [],
        commonMistakes: [],
        defaultSets: 1,
        defaultReps: 1,
        defaultDurationSec: 0,
        met: 3,
      );

      expect(exercise.hasMedia, isFalse);
      expect(exercise.hasVideo, isFalse);
      expect(exercise.primaryMedia, isNull);
      expect(exercise.animatedMediaPath, isNull);
      expect(exercise.thumbnailMediaPath, isNull);
    });

    test('WorkoutSession calculates volume from explicit sets', () {
      final session = WorkoutSession(
        id: 'session-1',
        exerciseId: 'squat',
        date: DateTime(2026, 6, 22),
        sets: 2,
        reps: 10,
        weightKg: 50,
        durationSec: 300,
        rpe: 8,
        calories: 80,
        note: '',
        aiConfidence: 0,
        workoutSets: const [
          WorkoutSet(
            id: 'set-1',
            order: 1,
            repetitions: 10,
            weightKg: 50,
            durationSec: 0,
            rpe: 8,
            isCompleted: true,
          ),
          WorkoutSet(
            id: 'set-2',
            order: 2,
            repetitions: 8,
            weightKg: 55,
            durationSec: 0,
            rpe: 9,
            isCompleted: true,
          ),
        ],
      );

      final restored = WorkoutSession.fromJson(session.toJson());

      expect(restored.workoutSets, hasLength(2));
      expect(restored.volume, 940);
    });

    test('WorkoutPlan restores WorkoutDay and plan items', () {
      const plan = WorkoutPlan(
        id: 'plan-1',
        name: 'Plan testowy',
        note: 'Lokalny',
        goal: 'Siła',
        isActive: true,
        days: [
          WorkoutDay(
            weekday: DateTime.monday,
            title: 'Góra',
            items: [
              PlanItem(
                exerciseId: 'pushup',
                sets: 3,
                reps: 12,
                durationSec: 0,
                note: '',
                suggestedWeightKg: 42.5,
                restSeconds: 120,
              ),
            ],
          ),
        ],
      );

      final restored = WorkoutPlan.fromJson(plan.toJson());

      expect(restored.days, hasLength(1));
      expect(restored.days.single.items.single.exerciseId, 'pushup');
      expect(restored.goal, 'Siła');
      expect(restored.isActive, isTrue);
      expect(restored.days.single.items.single.suggestedWeightKg, 42.5);
      expect(restored.days.single.items.single.restSeconds, 120);
    });

    test('WorkoutPlan progression: lock, complete, rest and JSON round-trip', () {
      const trainingItem = PlanItem(
        exerciseId: 'pushup',
        sets: 3,
        reps: 12,
        durationSec: 0,
        note: '',
      );
      const plan = WorkoutPlan(
        id: 'program-1',
        name: 'Pogromca brzucha',
        note: 'Opis',
        goal: 'Sylwetka',
        isActive: true,
        level: 'Zaawansowany',
        imageAsset: 'assets/programs/abs.png',
        completedDays: {0},
        days: [
          WorkoutDay(weekday: 1, title: 'Dzień 1', items: [trainingItem]),
          WorkoutDay(weekday: 2, title: 'Dzień 2', items: [trainingItem]),
          WorkoutDay(weekday: 3, title: 'Dzień odpoczynku', items: []),
          WorkoutDay(weekday: 4, title: 'Dzień 4', items: [trainingItem]),
        ],
      );

      // Dzień 0 ukończony, 1 aktywny, 2 (rest)/3 zablokowane w trybie liniowym.
      expect(plan.completedCount, 1);
      expect(plan.currentDayIndex, 1);
      expect(plan.statusForDay(0), WorkoutDayStatus.completed);
      expect(plan.statusForDay(1), WorkoutDayStatus.active);
      expect(plan.statusForDay(2), WorkoutDayStatus.locked);
      expect(plan.statusForDay(3), WorkoutDayStatus.locked);
      expect(plan.isRestDay(plan.days[2]), isTrue);
      expect(plan.progress, closeTo(0.25, 0.001));

      // Tryb „dowolny dzień" odblokowuje wszystko (rest pozostaje osobnym statusem).
      final anyDay = plan.copyWith(allowAnyDay: true);
      expect(anyDay.statusForDay(3), WorkoutDayStatus.available);
      expect(anyDay.statusForDay(2), WorkoutDayStatus.rest);

      // JSON round-trip zachowuje nowe pola programu.
      final restored = WorkoutPlan.fromJson(plan.toJson());
      expect(restored.level, 'Zaawansowany');
      expect(restored.imageAsset, 'assets/programs/abs.png');
      expect(restored.completedDays, {0});
      expect(restored.allowAnyDay, isFalse);
      expect(restored.statusForDay(1), WorkoutDayStatus.active);
    });

    test('ActiveWorkoutSession restores completed sets and progress', () {
      final session = ActiveWorkoutSession(
        id: 'active-1',
        planId: 'plan-1',
        planName: 'Plan testowy',
        weekday: DateTime.monday,
        dayTitle: 'Góra',
        dayIndex: 2,
        startedAt: DateTime(2026, 6, 23, 18),
        currentExerciseIndex: 0,
        note: 'Dobra energia',
        restTimerRemainingSeconds: 90,
        restTimerTotalSeconds: 120,
        isRestTimerPaused: true,
        exercises: const [
          ActiveWorkoutExercise(
            exerciseId: 'pushup',
            plannedSets: 3,
            plannedReps: 12,
            suggestedWeightKg: 10,
            restSeconds: 90,
            note: '',
            completedSets: [
              WorkoutSet(
                id: 'set-1',
                order: 1,
                repetitions: 12,
                weightKg: 10,
                durationSec: 0,
                rpe: 8,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );

      final restored = ActiveWorkoutSession.fromJson(session.toJson());

      expect(restored.dayIndex, 2);
      expect(restored.completedSetCount, 1);
      expect(restored.completedExerciseCount, 1);
      expect(restored.volume, 120);
      expect(restored.averageRpe, 8);
      expect(restored.note, 'Dobra energia');
      expect(restored.restTimerRemainingSeconds, 90);
      expect(restored.restTimerTotalSeconds, 120);
      expect(restored.isRestTimerPaused, isTrue);
    });

    test(
        'BodyMeasurement preserves body metrics and progress photo placeholders',
        () {
      final measurement = BodyMeasurement(
        id: 'measurement-1',
        date: DateTime(2026, 6, 24),
        weightKg: 98.4,
        waistCm: 92,
        chestCm: 112,
        armCm: 39.5,
        thighCm: 64,
        hipsCm: 105,
        calfCm: 41,
        shouldersCm: 128,
        note: 'Pomiar rano',
        progressPhotoPaths: const ['front-placeholder.jpg'],
      );

      final restored = BodyMeasurement.fromJson(measurement.toJson());

      expect(restored.hasAnyMeasurement, isTrue);
      expect(restored.weightKg, 98.4);
      expect(restored.waistCm, 92);
      expect(restored.chestCm, 112);
      expect(restored.armCm, 39.5);
      expect(restored.thighCm, 64);
      expect(restored.hipsCm, 105);
      expect(restored.calfCm, 41);
      expect(restored.shouldersCm, 128);
      expect(restored.note, 'Pomiar rano');
      expect(restored.progressPhotoPaths, contains('front-placeholder.jpg'));
    });

    test('TrainingImpact exposes calorie bridge payload and deduplication key',
        () {
      final impact = TrainingImpact(
        id: 'impact-session-1',
        sessionId: 'session-1',
        sessionName: 'Plan · Góra',
        date: DateTime(2026, 6, 24, 18),
        isTrainingDay: true,
        estimatedBurnedKcal: 340,
        suggestedCalorieAdjustmentKcal: 170,
        suggestedExtraWaterMl: 700,
        suggestedExtraProteinG: 32,
        postWorkoutMealSuggestion: 'Białko + węgle',
        durationMin: 50,
        exerciseCount: 5,
        setCount: 15,
        volumeKg: 9200,
        averageRpe: 8.2,
        createdAt: DateTime(2026, 6, 24, 19),
      );

      final restored = TrainingImpact.fromJson(impact.toJson());
      final bridgePayload = restored.toCalorieBridgeJson();

      expect(restored.dateKey, '2026-06-24');
      expect(restored.deduplicationKey, 'Trainer:session-1:2026-06-24');
      expect(bridgePayload['schema'], TrainingImpact.schema);
      expect(bridgePayload['activityType'], 'strength_training');
      expect(bridgePayload['estimatedBurnedKcal'], 340);
      expect(bridgePayload['suggestedExtraWaterMl'], 700);
      expect(bridgePayload['suggestedExtraProteinG'], 32);
    });

    test('activity crediting keeps ordinary steps separate from measured walk',
        () {
      final steps = TrainerActivityEntry(
        id: 'steps-1',
        date: DateTime(2026, 6, 24, 9),
        source: TrainerActivitySource.steps,
        type: TrainerActivityType.ordinaryStepsWalk,
        estimatedKcal: 180,
        sourceActivityId: 'daily-steps',
        durationMin: 180,
        steps: 9000,
      );
      final walk = TrainerActivityEntry(
        id: 'walk-1',
        date: DateTime(2026, 6, 24, 10),
        source: TrainerActivitySource.watch,
        type: TrainerActivityType.measuredWalk,
        estimatedKcal: 140,
        sourceActivityId: 'measured-walk',
        startedAt: DateTime(2026, 6, 24, 10),
        endedAt: DateTime(2026, 6, 24, 10, 40),
        durationMin: 40,
        distanceKm: 3.2,
      );

      final decisions = resolveActivityCredits([steps, walk]);

      expect(decisions.where((decision) => decision.includedInCalories),
          hasLength(2));
      expect(totalCreditedActivityKcal(decisions), 320);
    });

    test(
        'activity crediting skips measured walk when the same interval is a run',
        () {
      final measuredWalk = TrainerActivityEntry(
        id: 'walk-1',
        date: DateTime(2026, 6, 24, 10),
        source: TrainerActivitySource.watch,
        type: TrainerActivityType.measuredWalk,
        estimatedKcal: 120,
        sourceActivityId: 'same-window-walk',
        startedAt: DateTime(2026, 6, 24, 10),
        endedAt: DateTime(2026, 6, 24, 10, 35),
        durationMin: 35,
        distanceKm: 4,
      );
      final run = TrainerActivityEntry(
        id: 'run-1',
        date: DateTime(2026, 6, 24, 10),
        source: TrainerActivitySource.run,
        type: TrainerActivityType.run,
        estimatedKcal: 360,
        sourceActivityId: 'same-window-run',
        startedAt: DateTime(2026, 6, 24, 10, 5),
        endedAt: DateTime(2026, 6, 24, 10, 38),
        durationMin: 33,
        distanceKm: 5.1,
      );

      final decisions = resolveActivityCredits([measuredWalk, run]);
      final runDecision = decisions.singleWhere(
          (decision) => decision.entry.type == TrainerActivityType.run);
      final walkDecision = decisions.singleWhere((decision) =>
          decision.entry.type == TrainerActivityType.measuredWalk);

      expect(runDecision.includedInCalories, isTrue);
      expect(walkDecision.skippedAsDuplicate, isTrue);
      expect(totalCreditedActivityKcal(decisions), 360);
    });

    test(
        'activity crediting skips the same external activity from another source',
        () {
      final healthRun = TrainerActivityEntry(
        id: 'run-health',
        date: DateTime(2026, 6, 24, 18),
        source: TrainerActivitySource.healthConnect,
        type: TrainerActivityType.run,
        estimatedKcal: 310,
        sourceActivityId: 'external-run-42',
        durationMin: 30,
      );
      final watchRun = healthRun.copyWith(
        id: 'run-watch',
        source: TrainerActivitySource.watch,
        estimatedKcal: 305,
      );

      final decisions = resolveActivityCredits([healthRun, watchRun]);

      expect(decisions.where((decision) => decision.includedInCalories),
          hasLength(1));
      expect(decisions.where((decision) => decision.skippedAsDuplicate),
          hasLength(1));
    });

    test('Health Connect snapshot preserves diagnostics in JSON', () {
      final snapshot = TrainerHealthConnectSnapshot(
        id: 'health_connect_2026_6_24',
        date: DateTime(2026, 6, 24),
        checkedAt: DateTime(2026, 6, 24, 12, 30),
        sdkStatus: 'sdkAvailable',
        isAvailable: true,
        permissionsGranted: false,
        grantedPermissions: const ['Kroki', 'Dystans'],
        missingPermissions: const ['Tętno', 'Sen'],
        steps: 8420,
        distanceKm: 5.7,
        activeKcal: 320,
        workoutSessions: 1,
        workoutMinutes: 46,
        averageHeartRate: 122,
        heartRateSamples: 18,
        sleepMinutes: 420,
        availableData: const ['Kroki', 'Dystans', 'Aktywne kcal'],
        missingData: const ['Sen'],
        errorMessage: 'Częściowy brak uprawnień',
      );

      final restored = TrainerHealthConnectSnapshot.fromJson(snapshot.toJson());

      expect(snapshot.toJson()['schema'], TrainerHealthConnectSnapshot.schema);
      expect(restored.dateKey, '2026-06-24');
      expect(restored.steps, 8420);
      expect(restored.distanceKm, 5.7);
      expect(restored.hasAnyDailyData, isTrue);
      expect(restored.missingPermissions, contains('Sen'));
      expect(restored.errorMessage, contains('uprawnień'));
    });
  });
}
