import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/session_pace.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

// Realne tempo treningu i OSTROŻNA progresja: krótszy odpoczynek oraz zmiany,
// które już się wydarzyły, mają TŁUMIĆ krok, a nie go podbijać.

WorkoutSet _set({
  int order = 1,
  int reps = 10,
  double weight = 40,
  int restBefore = 0,
  int plannedRest = 0,
  int activeSeconds = 0,
  bool restVerified = true,
}) =>
    WorkoutSet(
      id: 'set$order',
      order: order,
      repetitions: reps,
      weightKg: weight,
      durationSec: 0,
      rpe: 0,
      isCompleted: true,
      restBeforeSec: restBefore,
      plannedRestSec: plannedRest,
      isRestVerified: restVerified,
      activeSeconds: activeSeconds,
    );

ExerciseSessionEvidence _evidence({
  SessionPace pace = SessionPace.neutral,
  ManualSetChanges manual = ManualSetChanges.none,
  bool allSetsCompleted = true,
  double confidence = 0.8,
  int streak = 3,
  double avgRpe = 7,
  bool rpeReliable = true,
}) =>
    ExerciseSessionEvidence(
      exerciseId: 'bench_press',
      exerciseName: 'Wyciskanie',
      plannedSets: 3,
      completedSets: 3,
      allSetsCompleted: allSetsCompleted,
      pace: pace,
      manual: manual,
      avgRpe: avgRpe,
      rpeReliable: rpeReliable,
      confidence: confidence,
      successStreak: streak,
    );

void main() {
  group('Pomiar tempa', () {
    test('krótsze przerwy niż plan → rozpoznane skracanie odpoczynku', () {
      final pace = measurePace([
        SetTempoSample.fromSet(
            _set(order: 2, restBefore: 50, plannedRest: 90),
            typicalWorkSec: 35),
        SetTempoSample.fromSet(
            _set(order: 3, restBefore: 55, plannedRest: 90),
            typicalWorkSec: 35),
      ]);
      expect(pace.hasRestData, isTrue);
      expect(pace.shortensRest, isTrue);
      expect(pace.restPercent, lessThan(70));
      expect(pace.summary, contains('krócej'));
    });

    test('jedna próbka to za mało na wniosek', () {
      final pace = measurePace([
        SetTempoSample.fromSet(
            _set(order: 2, restBefore: 30, plannedRest: 90),
            typicalWorkSec: 35),
      ]);
      expect(pace.hasRestData, isFalse);
      expect(pace.shortensRest, isFalse);
    });

    test('szybsze serie rozpoznane z czasu pracy', () {
      final pace = measurePace([
        SetTempoSample.fromSet(_set(order: 1, activeSeconds: 20),
            typicalWorkSec: 35),
        SetTempoSample.fromSet(_set(order: 2, activeSeconds: 22),
            typicalWorkSec: 35),
      ]);
      expect(pace.fasterSets, isTrue);
    });

    test('pojedynczy błędny pomiar nie przestawia modelu (średnia przycięta)',
        () {
      final pace = measurePace([
        for (var i = 0; i < 4; i++)
          SetTempoSample.fromSet(
              _set(order: i + 1, restBefore: 90, plannedRest: 90),
              typicalWorkSec: 35),
        // Jedna sesja z „zapomnianym" timerem — wartość skrajna.
        SetTempoSample.fromSet(
            _set(order: 5, restBefore: 270, plannedRest: 90),
            typicalWorkSec: 35),
      ]);
      expect(pace.restRatio, closeTo(1.0, 0.25));
      expect(pace.extendsRest, isFalse);
    });
  });

  group('Szacowany czas ćwiczenia', () {
    test('krótsze przerwy skracają prognozę czasu', () {
      const fast = SessionPace(restRatio: 0.6, restSamples: 4);
      final planned = estimateExerciseSeconds(
          sets: 3, reps: 10, durationSec: 0, restSeconds: 90);
      final real = estimateExerciseSeconds(
          sets: 3, reps: 10, durationSec: 0, restSeconds: 90, pace: fast);
      expect(real, lessThan(planned));
    });

    test('podkręcona intensywność wydłuża prognozę czasu', () {
      final standard = estimateExerciseSeconds(
          sets: 3, reps: 10, durationSec: 0, restSeconds: 90);
      final harder = estimateExerciseSeconds(
        sets: 3,
        reps: 10,
        durationSec: 0,
        restSeconds: 90,
        intensityFactor: 1.3,
      );
      expect(harder, greaterThan(standard));
    });
  });

  group('Wykrywanie ręcznych zmian', () {
    test('cięższy ciężar i więcej powtórzeń niż w recepcie', () {
      final changes = detectManualChanges(
        planned: const Prescription(
            sets: 3, reps: 10, weightKg: 40, durationSec: 0, restSeconds: 90),
        completed: [
          _set(order: 1, reps: 12, weight: 45),
          _set(order: 2, reps: 11, weight: 45),
          _set(order: 3, reps: 10, weight: 45),
        ],
      );
      expect(changes.addedLoad, isTrue);
      expect(changes.weightDeltaKg, 5);
      expect(changes.repDelta, 2);
      expect(changes.labels, contains('+5 kg'));
    });

    test('wykonanie zgodne z receptą = brak zmian', () {
      final changes = detectManualChanges(
        planned: const Prescription(
            sets: 3, reps: 10, weightKg: 40, durationSec: 0, restSeconds: 90),
        completed: [
          _set(order: 1),
          _set(order: 2),
          _set(order: 3),
        ],
      );
      expect(changes.any, isFalse);
    });
  });

  group('Ostrożna progresja', () {
    test('pełny krok przy stabilnej historii i planowym tempie', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.weightDeltaKg, 2.5);
      expect(step.appliedFraction, 1.0);
      expect(step.isDampened, isFalse);
    });

    test('skrócony odpoczynek TŁUMI krok i doradza powrót do przerwy', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(
            pace: const SessionPace(restRatio: 0.6, restSamples: 4)),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.weightDeltaKg, lessThan(2.5));
      expect(step.isDampened, isTrue);
      expect(step.restAdviceSec, greaterThan(0));
      expect(step.reasons.join(' '), contains('krócej'));
    });

    test('ręcznie dołożony ciężar jest ZALICZANY, nie dokładany drugi raz', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(
            manual: const ManualSetChanges(weightDeltaKg: 2.5)),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.weightDeltaKg, 0);
      expect(step.reasons.join(' '), contains('ręcznie'));
    });

    test('pierwsza udana sesja z rzędu = pół kroku', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(streak: 1),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.weightDeltaKg, closeTo(1.25, 0.01));
      expect(step.appliedFraction, closeTo(0.5, 0.01));
    });

    test('nieukończone serie → żadnego dokładania', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(allSetsCompleted: false),
        fullStepKg: 2.5,
      );
      expect(step.changesAnything, isFalse);
      expect(step.appliedFraction, 0);
    });

    test('ręczne zmniejszenie ciężaru zatrzymuje progresję', () {
      final step = cautiousProgressionStep(
        evidence:
            _evidence(manual: const ManualSetChanges(weightDeltaKg: -5)),
        fullStepKg: 2.5,
      );
      expect(step.changesAnything, isFalse);
      expect(step.reasons.join(' '), contains('zmniejszony'));
    });

    test('szybsze serie przy PEŁNEJ przerwie mogą podbić krok', () {
      final normal = cautiousProgressionStep(
        evidence: _evidence(),
        fullStepKg: 2.0,
        roundToKg: 0.5,
      );
      final fast = cautiousProgressionStep(
        evidence: _evidence(
            pace: const SessionPace(workRatio: 0.7, workSamples: 4)),
        fullStepKg: 2.0,
        roundToKg: 0.5,
      );
      expect(fast.weightDeltaKg, greaterThanOrEqualTo(normal.weightDeltaKg));
    });

    test('szybsze serie przy SKRÓCONEJ przerwie nie są dowodem siły', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(
          pace: const SessionPace(
              restRatio: 0.6, restSamples: 4, workRatio: 0.7, workSamples: 4),
        ),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.weightDeltaKg, lessThan(2.5));
      expect(step.reasons.join(' '), contains('tempo'));
    });

    test('niska pewność analizy zmniejsza krok', () {
      final step = cautiousProgressionStep(
        evidence: _evidence(confidence: 0.4),
        fullStepKg: 2.5,
        roundToKg: 1.25,
      );
      expect(step.appliedFraction, lessThan(1.0));
    });
  });
}
