import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

// Testy silnika „inteligentnego trenera": rekomendacja, kalibracja, progresja,
// szacowanie wysiłku (ukryte RPE) z pewnością, bezpieczne limity.
void main() {
  final bench = ExerciseRepo.byId('bench_press'); // repsWeight, wielostawowe
  final curl = ExerciseRepo.byId('bicep_curl'); // repsWeight, izolacja
  final pushup = ExerciseRepo.byId('pushup'); // bodyweight_reps
  final plank = ExerciseRepo.byId('plank'); // bodyweight_time

  const ctx = CoachContext(
    level: 'Średniozaawansowany',
    goal: 'Masa',
    bodyWeightKg: 80,
    heightCm: 180,
    age: 30,
    sex: 'Mężczyzna',
  );

  CoachHistorySample sample({
    double weight = 40,
    int reps = 12,
    int plannedReps = 12,
    bool done = true,
    double rpe = 7,
    int duration = 0,
    bool verified = true,
    int daysAgo = 1,
  }) =>
      CoachHistorySample(
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        weightKg: weight,
        reps: reps,
        durationSec: duration,
        plannedReps: plannedReps,
        allSetsCompleted: done,
        estimatedRpe: rpe,
        timeVerified: verified,
      );

  group('Zakresy powtórzeń wg celu', () {
    test('siła / masa / redukcja', () {
      expect(targetRepRange('Siła').max, 6);
      expect(targetRepRange('Masa').min, 8);
      expect(targetRepRange('Redukcja').max, 18);
    });
  });

  group('Bezpieczne skoki ciężaru', () {
    test('izolacja mniejszy krok niż wielostawowe', () {
      expect(safeWeightStepKg(curl, 'Średniozaawansowany'),
          lessThan(safeWeightStepKg(bench, 'Średniozaawansowany')));
      expect(isIsolationExercise(curl), isTrue);
      expect(isIsolationExercise(bench), isFalse);
    });
  });

  group('Dobór początkowego ciężaru + kalibracja', () {
    test('brak historii = kalibracja + ostrożny, dodatni ciężar', () {
      final rec = recommendSet(
        exercise: bench,
        plannedSets: 3,
        plannedReps: 10,
        plannedWeightKg: 0,
        plannedDurationSec: 0,
        plannedRestSeconds: 90,
        ctx: ctx,
        history: const [],
      );
      expect(rec.isCalibrating, isTrue);
      expect(rec.calibrationNote, isNotEmpty);
      expect(rec.weightKg, greaterThan(0));
      expect(rec.weightKg, lessThan(ctx.bodyWeightKg)); // ostrożny start
      expect(rec.reasons.join(' '), contains('Ostrożny start'));
    });

    test('kobieta dostaje mniejszy start niż mężczyzna', () {
      final male = estimateInitialWeight(bench, ctx);
      final female = estimateInitialWeight(
          bench, const CoachContext(bodyWeightKg: 80, sex: 'Kobieta'));
      expect(female, lessThan(male));
    });

    test('ćwiczenie z masy ciała: dodatkowy ciężar 0 na start', () {
      final rec = recommendSet(
        exercise: pushup,
        plannedSets: 3,
        plannedReps: 12,
        plannedWeightKg: 0,
        plannedDurationSec: 0,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: const [],
      );
      expect(rec.weightKg, 0);
      expect(rec.isCalibrating, isTrue);
    });
  });

  group('Progresja', () {
    test('dwie udane sesje w górnym zakresie → +ciężar', () {
      final history = [
        sample(weight: 40, reps: 12, rpe: 7),
        sample(weight: 40, reps: 12, rpe: 7),
        sample(weight: 40, reps: 12, rpe: 7),
      ];
      final decision = decideProgression(
        exercise: bench,
        ctx: ctx,
        history: history,
      );
      expect(decision.action, CoachProgressionAction.increaseWeight);
      expect(decision.weightDeltaKg, greaterThan(0));

      final rec = recommendSet(
        exercise: bench,
        plannedSets: 3,
        plannedReps: 12,
        plannedWeightKg: 40,
        plannedDurationSec: 0,
        plannedRestSeconds: 90,
        ctx: ctx,
        history: history,
      );
      expect(rec.weightKg, greaterThan(40));
    });

    test('nieukończona seria → schodzimy z ciężaru', () {
      final history = [
        sample(weight: 40, reps: 12, done: true),
        sample(weight: 42.5, reps: 6, done: false, rpe: 9.5),
      ];
      final decision = decideProgression(
        exercise: bench,
        ctx: ctx,
        history: history,
      );
      expect(decision.action, CoachProgressionAction.decreaseWeight);
      expect(decision.weightDeltaKg, lessThan(0));
    });

    test('niska pewność analizy → hold (brak dużych zmian)', () {
      final history = [
        sample(reps: 12),
        sample(reps: 12),
        sample(reps: 12),
      ];
      final decision = decideProgression(
        exercise: bench,
        ctx: ctx,
        history: history,
        lastConfidence: 0.3,
      );
      expect(decision.action, CoachProgressionAction.hold);
    });

    test('słaba regeneracja → hold', () {
      final history = [sample(reps: 12), sample(reps: 12)];
      final decision = decideProgression(
        exercise: bench,
        ctx: ctx,
        history: history,
        recoveryPercent: 45,
      );
      expect(decision.action, CoachProgressionAction.hold);
    });

    test('masa ciała: górny zakres → trudniejszy wariant', () {
      // Redukcja = zakres 12–18; górny pułap (18) → trudniejszy wariant.
      final history = [
        sample(weight: 0, reps: 18, plannedReps: 18),
        sample(weight: 0, reps: 18, plannedReps: 18),
      ];
      final decision = decideProgression(
        exercise: pushup,
        ctx: const CoachContext(goal: 'Redukcja'),
        history: history,
      );
      expect(decision.action, CoachProgressionAction.harderVariant);
    });
  });

  group('Szacowanie wysiłku (ukryte RPE) + pewność', () {
    test('wykonane zgodnie z planem → umiarkowany/wysoki, sensowna pewność',
        () {
      final e = estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: 40,
        activeSeconds: 35,
        plannedRestSeconds: 90,
        actualRestSeconds: 90,
      );
      expect(e.rpe, inInclusiveRange(6.0, 8.0));
      expect(e.confidence, greaterThan(0.5));
      expect(e.levelLabel, isNot('niepewny'));
    });

    test('nieukończona → wysokie RPE', () {
      final e = estimateExertion(
        outcome: SetOutcome.notCompleted,
        exercise: bench,
        plannedReps: 10,
        actualReps: 6,
        weightKg: 45,
      );
      expect(e.rpe, greaterThanOrEqualTo(8.5));
    });

    test('przerwana → niska pewność (niepewny)', () {
      final e = estimateExertion(
        outcome: SetOutcome.interrupted,
        exercise: bench,
        plannedReps: 10,
        actualReps: 4,
        weightKg: 40,
      );
      expect(e.confidence, lessThan(0.5));
      expect(e.levelLabel, 'niepewny');
    });

    test('dane tętna podnoszą pewność i wysiłek', () {
      final withHr = estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: 40,
        heartRateBpm: 175,
        age: 30,
      );
      final noHr = estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: 40,
      );
      expect(withHr.confidence, greaterThan(noHr.confidence));
      expect(withHr.rpe, greaterThan(noHr.rpe));
    });

    test('czas niezweryfikowany obniża pewność, nie zawyża wysiłku', () {
      final verified = estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: 40,
        activeSeconds: 35,
        timeVerified: true,
      );
      final unverified = estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: 40,
        activeSeconds: 900,
        timeVerified: false,
      );
      expect(unverified.confidence, lessThan(verified.confidence));
      // Długi czas NIE zawyża RPE (czas nie decyduje o wysiłku).
      expect(unverified.rpe, verified.rpe);
    });
  });

  group('Nietypowo długi czas serii', () {
    test('wielokrotnie dłuższy niż typowy = podejrzany', () {
      expect(isSetDurationSuspicious(bench, 10, 900), isTrue);
      expect(isSetDurationSuspicious(bench, 10, 40), isFalse);
    });
  });

  group('Ćwiczenie czasowe (plank)', () {
    test('prowadzone czasem, bez ciężaru; progresja dokłada sekundy', () {
      final rec = recommendSet(
        exercise: plank,
        plannedSets: 3,
        plannedReps: 0,
        plannedWeightKg: 0,
        plannedDurationSec: 40,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: [
          sample(weight: 0, reps: 0, duration: 40),
          sample(weight: 0, reps: 0, duration: 40),
          sample(weight: 0, reps: 0, duration: 40),
        ],
      );
      expect(rec.durationSec, greaterThanOrEqualTo(40));
      expect(rec.weightKg, 0);
    });
  });
}
