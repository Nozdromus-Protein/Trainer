import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/daily_adjustment_calculator.dart';
import 'package:licznik_treningu/features/trainer/domain/activity_credit.dart';
import 'package:licznik_treningu/features/trainer/domain/daily_adjustment.dart';
import 'package:licznik_treningu/main.dart';

void main() {
  group('Test 5 — trening przez północ należy do dnia ROZPOCZĘCIA', () {
    test('sesja 23:40 → 00:20 trafia na dzień startu', () {
      // Europe/Amsterdam: 21 lipca 23:40 → 22 lipca 00:20.
      final startedAt = DateTime(2026, 7, 21, 23, 40);
      final endedAt = DateTime(2026, 7, 22, 0, 20);

      expect(workoutDayFor(startedAt, endedAt), DateTime(2026, 7, 21));
      expect(workoutDateKeyFor(startedAt, endedAt), '2026-07-21');
    });

    test('dzień NIE bierze się z zakończenia ani z kliknięcia „Zapisz"', () {
      final startedAt = DateTime(2026, 7, 21, 23, 40);
      // Użytkownik zapisał trening dopiero rano.
      final savedAt = DateTime(2026, 7, 22, 9, 15);
      expect(workoutDayFor(startedAt, savedAt), DateTime(2026, 7, 21));
    });

    test('sesja w środku dnia zostaje w swoim dniu', () {
      final startedAt = DateTime(2026, 7, 21, 17, 0);
      final endedAt = DateTime(2026, 7, 21, 18, 10);
      expect(workoutDayFor(startedAt, endedAt), DateTime(2026, 7, 21));
    });

    test('brak czasu startu nie wysypuje wyliczenia', () {
      final endedAt = DateTime(2026, 7, 22, 0, 20);
      expect(workoutDayFor(null, endedAt), DateTime(2026, 7, 22));
    });

    test('znacznik UTC jest sprowadzany do strefy lokalnej', () {
      final startedAt = DateTime.utc(2026, 7, 21, 21, 40);
      final endedAt = DateTime.utc(2026, 7, 21, 22, 20);
      final local = startedAt.toLocal();
      expect(
        workoutDayFor(startedAt, endedAt),
        DateTime(local.year, local.month, local.day),
      );
    });
  });

  group('Współczynniki zaufania dla sportu', () {
    test('trening siłowy liczy się w 60%', () {
      expect(creditedSportKcal(strengthKcal: 600), 360);
    });

    test('bieg liczy się w 70%', () {
      expect(creditedSportKcal(runKcal: 1000), 700);
    });

    test('cardio i chód mają własne współczynniki', () {
      expect(creditedSportKcal(otherCardioKcal: 500), 300);
      expect(creditedSportKcal(walkKcal: 200), 120);
    });

    test('współczynniki są konfigurowalne w jednym miejscu', () {
      expect(
        creditedSportKcal(
          strengthKcal: 600,
          factors: const SportCreditFactors(strength: 0.5),
        ),
        300,
      );
    });

    test('ujemne i puste wartości dają zero', () {
      expect(creditedSportKcal(), 0);
      expect(creditedSportKcal(strengthKcal: -100), 0);
    });
  });

  group('Pakiet dnia rozdziela sport od bazy', () {
    TrainerActivityEntry entry({
      required TrainerActivityType type,
      required int kcal,
      required String key,
      int steps = 0,
    }) => TrainerActivityEntry(
      id: key,
      type: type,
      date: DateTime(2026, 7, 22, 18),
      durationMin: 45,
      estimatedKcal: kcal,
      steps: steps,
      source: TrainerActivitySource.trainer,
      sourceActivityId: key,
    );

    test('praca zawodowa NIE trafia do sportu (zgłoszone +867 kcal)', () {
      // Odtworzenie zgłoszenia: 96 kg, 5 h umiarkowanej pracy, trening 195 kcal
      // i 1675 kroków. Stary model dawał korektę 195 + 672 = 867 kcal.
      final adjustment = buildTrainerDailyAdjustment(
        day: DateTime(2026, 7, 22),
        decisions: [
          ActivityCreditDecision(
            entry: entry(
              type: TrainerActivityType.strengthTraining,
              kcal: 195,
              key: 'workout-1',
            ),
            includedInCalories: true,
            skippedAsDuplicate: false,
            reason: 'test',
          ),
        ],
        impactsForDay: const [],
        bodyWeightKg: 96,
        workIntensity: 'moderate',
        workHoursPerDay: 5,
        workWeekdays: const [1, 2, 3, 4, 5, 6, 7],
        now: DateTime(2026, 7, 22, 19),
      );

      // Praca (2.4 − 1) × 96 × 5 = 672 kcal — należy do BAZY.
      expect(adjustment.baselineActivityKcal, 672);
      // Do celu idzie tylko trening: 195 × 0.60 = 117 kcal.
      expect(adjustment.sportKcal, 117);
      // Spalona energia dnia zostaje informacją, nie korektą celu.
      expect(adjustment.totalAdjustmentKcal, 867);
      expect(
        adjustment.sportKcal,
        lessThan(adjustment.totalAdjustmentKcal),
        reason: 'korekta celu nie może równać się całej spalonej energii',
      );
    });

    test('bieg wchodzi do sportu po 70%, kroki biegu nie dubluja', () {
      final adjustment = buildTrainerDailyAdjustment(
        day: DateTime(2026, 7, 22),
        decisions: [
          ActivityCreditDecision(
            entry: entry(
              type: TrainerActivityType.run,
              kcal: 1000,
              key: 'run-1',
              steps: 9000,
            ),
            includedInCalories: true,
            skippedAsDuplicate: false,
            reason: 'test',
          ),
        ],
        impactsForDay: const [],
        bodyWeightKg: 96,
        now: DateTime(2026, 7, 22, 19),
      );

      expect(adjustment.sportKcal, 700);
      // Kroki pokryte przez bieg są odjęte, więc nie tworzą osobnych kcal.
      expect(adjustment.stepsKcal, 0);
    });

    test('odrzucony duplikat sesji nie zwiększa sportu', () {
      final decisions = <ActivityCreditDecision>[
        ActivityCreditDecision(
          entry: entry(
            type: TrainerActivityType.strengthTraining,
            kcal: 600,
            key: 'workout-1',
          ),
          includedInCalories: true,
          skippedAsDuplicate: false,
          reason: 'pierwsze wystąpienie',
        ),
        ActivityCreditDecision(
          entry: entry(
            type: TrainerActivityType.strengthTraining,
            kcal: 600,
            key: 'workout-1',
          ),
          includedInCalories: false,
          skippedAsDuplicate: true,
          reason: 'duplikat po ponownej synchronizacji',
        ),
      ];

      final adjustment = buildTrainerDailyAdjustment(
        day: DateTime(2026, 7, 22),
        decisions: decisions,
        impactsForDay: const [],
        bodyWeightKg: 96,
        now: DateTime(2026, 7, 22, 19),
      );

      expect(adjustment.sportKcal, 360, reason: '600 × 0.60, liczone raz');
    });

    test('dzień bez pracy i bez sportu nie tworzy korekty', () {
      final adjustment = buildTrainerDailyAdjustment(
        day: DateTime(2026, 7, 22),
        decisions: const [],
        impactsForDay: const [],
        bodyWeightKg: 96,
        now: DateTime(2026, 7, 22, 19),
      );
      expect(adjustment.sportKcal, 0);
      expect(adjustment.baselineActivityKcal, 0);
    });

    test('pakiet przeżywa zapis i odczyt razem z nowymi polami', () {
      final adjustment = buildTrainerDailyAdjustment(
        day: DateTime(2026, 7, 22),
        decisions: [
          ActivityCreditDecision(
            entry: entry(
              type: TrainerActivityType.strengthTraining,
              kcal: 400,
              key: 'workout-1',
            ),
            includedInCalories: true,
            skippedAsDuplicate: false,
            reason: 'test',
          ),
        ],
        impactsForDay: const [],
        bodyWeightKg: 96,
        workIntensity: 'light',
        workHoursPerDay: 4,
        workWeekdays: const [1, 2, 3, 4, 5, 6, 7],
        now: DateTime(2026, 7, 22, 19),
      );

      final restored = TrainerDailyAdjustment.fromJson(adjustment.toJson());
      expect(restored.sportKcal, adjustment.sportKcal);
      expect(restored.baselineActivityKcal, adjustment.baselineActivityKcal);
      // Most do Kalorii niesie te same pola w pełnym JSON-ie pakietu.
      expect(adjustment.toCalorieBridgeJson()['sportKcal'], adjustment.sportKcal);
      expect(
        adjustment.toCalorieBridgeJson()['baselineActivityKcal'],
        adjustment.baselineActivityKcal,
      );
    });
  });
}
