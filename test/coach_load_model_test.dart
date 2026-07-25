import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

Exercise _exercise({
  required String id,
  required String name,
  required String equipment,
  List<String> muscles = const ['czworogłowe uda'],
  int reps = 10,
  int durationSec = 0,
}) =>
    Exercise(
      id: id,
      name: name,
      category: 'Nogi',
      muscles: muscles,
      equipment: equipment,
      level: 'Średniozaawansowany',
      illustrationType: 'squat',
      description: '',
      tips: const [],
      commonMistakes: const [],
      defaultSets: 3,
      defaultReps: reps,
      defaultDurationSec: durationSec,
      met: 5,
    );

final _goblet = _exercise(
  id: 'goblet_squat',
  name: 'Goblet squat',
  equipment: 'hantel / kettlebell',
);

final _backSquat = _exercise(
  id: 'back_squat',
  name: 'Przysiad ze sztangą',
  equipment: 'sztanga',
);

const _ctx = CoachContext(
  level: 'Zaawansowany',
  goal: 'Masa',
  bodyWeightKg: 95,
  heightCm: 183,
  age: 34,
  sex: 'Mężczyzna',
);

void main() {
  group('Sposób obciążenia decyduje o ciężarze', () {
    test('goblet squat to JEDEN trzymany ciężar, nie przysiad ze sztangą', () {
      expect(loadStyleFor(_goblet), ExerciseLoadStyle.singleImplement);
      expect(loadStyleFor(_backSquat), ExerciseLoadStyle.barbell);
    });

    test('start goblet squata mieści się w realnym zakresie', () {
      final start = estimateInitialWeight(_goblet, _ctx);
      // Dawna formuła (0,75 × masy ciała jak dla przysiadu ze sztangą) dawała
      // ~75 kg trzymane przy mostku — fizycznie nieosiągalne.
      expect(start, greaterThan(0));
      expect(start, lessThanOrEqualTo(maxPracticalLoadKg(_goblet, _ctx)));
      expect(start, lessThan(35));
    });

    test('sztanga nadal dostaje solidny ciężar startowy', () {
      final start = estimateInitialWeight(_backSquat, _ctx);
      expect(start, greaterThan(50));
    });

    test('sufit implementu przycina ciężar także po progresji', () {
      final history = [
        for (var i = 0; i < 5; i++)
          CoachHistorySample(
            date: DateTime(2026, 7, 10 + i),
            weightKg: 60, // wartość z zepsutego zapisu
            reps: 12,
            durationSec: 0,
            plannedReps: 12,
            allSetsCompleted: true,
            estimatedRpe: 7,
          ),
      ];
      final rec = recommendSet(
        exercise: _goblet,
        plannedSets: 3,
        plannedReps: 10,
        plannedWeightKg: 0,
        plannedDurationSec: 0,
        plannedRestSeconds: kUnsetRestSeconds,
        ctx: _ctx,
        history: history,
      );
      expect(rec.weightKg, lessThanOrEqualTo(maxPracticalLoadKg(_goblet, _ctx)));
      expect(rec.weightKg, lessThanOrEqualTo(40));
    });

    test('deload skaluje ciężar w dół, a nie w górę', () {
      const deloadCtx = CoachContext(
        level: 'Zaawansowany',
        goal: 'Masa',
        bodyWeightKg: 95,
        sex: 'Mężczyzna',
        cycleIntensity: 0.55,
      );
      final normal = recommendSet(
        exercise: _goblet,
        plannedSets: 3,
        plannedReps: 10,
        plannedWeightKg: 0,
        plannedDurationSec: 0,
        plannedRestSeconds: kUnsetRestSeconds,
        ctx: _ctx,
      );
      final deload = recommendSet(
        exercise: _goblet,
        plannedSets: 3,
        plannedReps: 10,
        plannedWeightKg: 0,
        plannedDurationSec: 0,
        plannedRestSeconds: kUnsetRestSeconds,
        ctx: deloadCtx,
      );
      expect(deload.weightKg, lessThan(normal.weightKg));
    });

    test('przy suficie progresja idzie w wariant, nie w kolejne kilogramy', () {
      final atCeiling = maxPracticalLoadKg(_goblet, _ctx);
      final history = [
        for (var i = 0; i < 4; i++)
          CoachHistorySample(
            date: DateTime(2026, 7, 10 + i),
            weightKg: atCeiling,
            reps: 12,
            durationSec: 0,
            plannedReps: 12,
            allSetsCompleted: true,
            estimatedRpe: 7,
          ),
      ];
      final decision = decideProgression(
        exercise: _goblet,
        ctx: _ctx,
        history: history,
      );
      expect(decision.action, CoachProgressionAction.harderVariant);
    });
  });
}
