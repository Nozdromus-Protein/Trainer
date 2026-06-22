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
              ),
            ],
          ),
        ],
      );

      final restored = WorkoutPlan.fromJson(plan.toJson());

      expect(restored.days, hasLength(1));
      expect(restored.days.single.items.single.exerciseId, 'pushup');
    });
  });
}
