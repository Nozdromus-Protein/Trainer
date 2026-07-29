import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

// Mechanizm wychwytywania RPE: „Zrobiłem zgodnie z planem" NIE może dawać
// zawsze tej samej wartości. Wysiłek wynika z realnych sygnałów — numeru serii,
// faktycznej przerwy, czasu pracy, ciężaru względem historii i zmęczenia sesją.

void main() {
  final bench = ExerciseRepo.byId('bench_press');

  ExertionEstimate asPlanned({
    int setIndex = 0,
    int plannedSets = 3,
    int plannedRest = 0,
    int actualRest = 0,
    bool restVerified = false,
    int activeSeconds = 0,
    bool timeVerified = true,
    double weight = 40,
    double reference = 0,
    double recovery = 100,
    int sessionSets = 0,
    int? hr,
  }) =>
      estimateExertion(
        outcome: SetOutcome.asPlanned,
        exercise: bench,
        plannedReps: 10,
        actualReps: 10,
        weightKg: weight,
        setIndex: setIndex,
        plannedSets: plannedSets,
        plannedRestSeconds: plannedRest,
        actualRestSeconds: actualRest,
        restVerified: restVerified,
        activeSeconds: activeSeconds,
        timeVerified: timeVerified,
        referenceWeightKg: reference,
        recoveryPercent: recovery,
        sessionCompletedSets: sessionSets,
        heartRateBpm: hr,
      );

  group('RPE nie jest już stałą', () {
    test('kolejne serie tego samego ciężaru kosztują coraz więcej', () {
      final first = asPlanned(setIndex: 0);
      final third = asPlanned(setIndex: 2);
      final fifth = asPlanned(setIndex: 4, plannedSets: 5);
      expect(third.rpe, greaterThan(first.rpe));
      expect(fifth.rpe, greaterThan(third.rpe));
      // Żadna z nich nie jest „magiczną siódemką" dla wszystkich przypadków.
      expect({first.rpe, third.rpe, fifth.rpe}, hasLength(3));
    });

    test('skrócony odpoczynek podnosi wysiłek tej samej pracy', () {
      final full = asPlanned(setIndex: 1, plannedRest: 90, actualRest: 90);
      final short = asPlanned(setIndex: 1, plannedRest: 90, actualRest: 45);
      expect(short.rpe, greaterThan(full.rpe));
      expect(short.factors.join(' '), contains('Przerwa skrócona'));
    });

    test('wydłużony odpoczynek obniża wysiłek', () {
      final full = asPlanned(setIndex: 1, plannedRest: 90, actualRest: 90);
      final long = asPlanned(setIndex: 1, plannedRest: 90, actualRest: 180);
      expect(long.rpe, lessThan(full.rpe));
    });

    test('ciężar wyższy niż dotąd podnosi, niższy obniża wysiłek', () {
      final record = asPlanned(weight: 60, reference: 55);
      final light = asPlanned(weight: 40, reference: 55);
      expect(record.rpe, greaterThan(light.rpe));
      expect(record.factors.join(' '), contains('wyższy niż dotąd'));
    });

    test('wolniejsza seria = grind, szybsza = zapas', () {
      // Typowy czas serii 10 powtórzeń ≈ 35 s.
      final slow = asPlanned(activeSeconds: 60);
      final fast = asPlanned(activeSeconds: 20);
      expect(slow.rpe, greaterThan(fast.rpe));
    });

    test('końcówka długiego treningu kosztuje więcej', () {
      final fresh = asPlanned(sessionSets: 2);
      final late = asPlanned(sessionSets: 22);
      expect(late.rpe, greaterThan(fresh.rpe));
    });

    test('słabsza regeneracja partii podnosi wysiłek', () {
      expect(asPlanned(recovery: 35).rpe,
          greaterThan(asPlanned(recovery: 90).rpe));
    });
  });

  group('Pewność oceny zależy od liczby realnych sygnałów', () {
    test('bez żadnego pomiaru pewność jest niska', () {
      final blind = asPlanned();
      expect(blind.confidence, lessThan(0.6));
    });

    test('zmierzona przerwa, czas i historia podnoszą pewność', () {
      final blind = asPlanned();
      final measured = asPlanned(
        plannedRest: 90,
        actualRest: 85,
        restVerified: true,
        activeSeconds: 34,
        reference: 45,
      );
      expect(measured.confidence, greaterThan(blind.confidence));
      expect(measured.confidence, greaterThan(0.5));
      expect(measured.levelLabel, isNot('niepewny'));
    });

    test('pomiar odtworzony (niepewny) daje mniej pewności niż zdarzenie', () {
      final verified = asPlanned(
          plannedRest: 90, actualRest: 85, restVerified: true);
      final guessed = asPlanned(plannedRest: 90, actualRest: 85);
      expect(guessed.confidence, lessThan(verified.confidence));
    });

    test('nieukończona seria nadal daje wysokie RPE', () {
      final e = estimateExertion(
        outcome: SetOutcome.notCompleted,
        exercise: bench,
        plannedReps: 10,
        actualReps: 6,
        weightKg: 45,
      );
      expect(e.rpe, greaterThanOrEqualTo(8.5));
    });

    test('przerwana seria zostaje niepewna', () {
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
  });
}
