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

    test('ActiveWorkoutSession restores completed sets and progress', () {
      final session = ActiveWorkoutSession(
        id: 'active-1',
        planId: 'plan-1',
        planName: 'Plan testowy',
        weekday: DateTime.monday,
        dayTitle: 'Góra',
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

      expect(restored.completedSetCount, 1);
      expect(restored.completedExerciseCount, 1);
      expect(restored.volume, 120);
      expect(restored.averageRpe, 8);
      expect(restored.note, 'Dobra energia');
      expect(restored.restTimerRemainingSeconds, 90);
      expect(restored.restTimerTotalSeconds, 120);
      expect(restored.isRestTimerPaused, isTrue);
    });

    test('BodyMeasurement preserves body metrics and progress photo placeholders', () {
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

    test('TrainingImpact exposes calorie bridge payload and deduplication key', () {
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
  });
}
