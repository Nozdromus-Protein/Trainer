import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy recepty sesji (rekomendacja PRZED wykonaniem), walidacji danych
/// czasowych, źródła RPE i progresji zależnej od typu ćwiczenia.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final plank = ExerciseRepo.byId('plank'); // bodyweight_time, baza 45 s?
  final bench = ExerciseRepo.byId('bench_press'); // reps_weight
  final pushup = ExerciseRepo.byId('pushup'); // bodyweight_reps

  const ctx = CoachContext(
    level: 'Średniozaawansowany',
    goal: 'Masa',
    bodyWeightKg: 80,
    heightCm: 180,
    age: 30,
    sex: 'Mężczyzna',
  );

  CoachHistorySample timedSample({
    required int duration,
    bool done = true,
    bool verified = true,
    int daysAgo = 1,
  }) =>
      CoachHistorySample(
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        weightKg: 0,
        reps: 0,
        durationSec: duration,
        plannedReps: 0,
        allSetsCompleted: done,
        estimatedRpe: 7,
        timeVerified: verified,
      );

  WorkoutSet setOf({
    int reps = 10,
    double weight = 40,
    int duration = 0,
    int rpe = 7,
    String rpeSource = '',
    String outcome = '',
    double estimatedRpe = 0,
    double confidence = 0,
    int activeSeconds = 0,
  }) =>
      WorkoutSet(
        id: 's',
        order: 1,
        repetitions: reps,
        weightKg: weight,
        durationSec: duration,
        rpe: rpe,
        isCompleted: true,
        outcome: outcome,
        estimatedRpe: estimatedRpe,
        exertionConfidence: confidence,
        activeSeconds: activeSeconds,
        rpeSource: rpeSource,
      );

  WorkoutLog logOf({
    required String exerciseId,
    required List<WorkoutSet> sets,
    int reps = 10,
    double weight = 40,
    int rpe = 7,
    int durationSec = 0,
    int daysAgo = 1,
  }) =>
      WorkoutLog(
        id: 'log_$daysAgo',
        exerciseId: exerciseId,
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        sets: sets.length,
        reps: reps,
        weightKg: weight,
        durationSec: durationSec,
        rpe: rpe,
        calories: 50,
        note: '',
        aiConfidence: 0,
        workoutSets: sets,
      );

  // ===========================================================================
  // 1. Deska 45 s + poprawne wykonanie + progresja = 50 s (NIE 308 s)
  // ===========================================================================

  group('Rekomendacja czasu ćwiczenia czasowego', () {
    test('plan bazowy 45 s + stabilne wykonanie → rekomendacja 50 s', () {
      final rec = recommendSet(
        exercise: plank,
        plannedSets: 2,
        plannedReps: 0,
        plannedWeightKg: 0,
        plannedDurationSec: 45,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: [
          timedSample(duration: 45, daysAgo: 5),
          timedSample(duration: 45, daysAgo: 3),
          timedSample(duration: 45, daysAgo: 1),
        ],
      );
      expect(rec.durationSec, 50);
      expect(rec.weightKg, 0);
      expect(rec.reasons.join(' '), contains('dokładamy 5 s'));
    });

    test('REGRESJA: uszkodzony czas z historii (303 s) NIE daje 308 s', () {
      // 303 s to artefakt: czas całej sesji podzielony przez liczbę ćwiczeń.
      final rec = recommendSet(
        exercise: plank,
        plannedSets: 2,
        plannedReps: 0,
        plannedWeightKg: 0,
        plannedDurationSec: 45,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: [
          timedSample(duration: 303, daysAgo: 5),
          timedSample(duration: 303, daysAgo: 3),
          timedSample(duration: 303, daysAgo: 1),
        ],
      );
      expect(rec.durationSec, isNot(308));
      // Brak wiarygodnego czasu → plan bazowy.
      expect(rec.durationSec, 45);
      expect(rec.reasons.join(' '), contains('Brak wiarygodnego czasu'));
    });

    test('walidacja czasu historycznego odsiewa wartości poza zakresem', () {
      expect(isPlausibleHistoricalDuration(45, 50), isTrue);
      expect(isPlausibleHistoricalDuration(45, 45), isTrue);
      expect(isPlausibleHistoricalDuration(45, 303), isFalse); // artefakt sesji
      expect(isPlausibleHistoricalDuration(45, 0), isFalse);
      expect(isPlausibleHistoricalDuration(45, 5000), isFalse);
      expect(isPlausibleHistoricalDuration(45, 1), isFalse);
    });

    test('mieszana historia: bierzemy ostatni WIARYGODNY czas, nie uszkodzony',
        () {
      final rec = recommendSet(
        exercise: plank,
        plannedSets: 2,
        plannedReps: 0,
        plannedWeightKg: 0,
        plannedDurationSec: 45,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: [
          timedSample(duration: 50, daysAgo: 5),
          timedSample(duration: 50, daysAgo: 3),
          timedSample(duration: 999, daysAgo: 1), // uszkodzony — pomijany
        ],
      );
      expect(rec.durationSec, 55); // 50 (ostatni wiarygodny) + 5
    });
  });

  // ===========================================================================
  // 10. Brak poprawnej historii → plan bazowy
  // ===========================================================================

  group('Brak historii → plan bazowy', () {
    test('brak historii = kalibracja, czas z planu bazowego', () {
      final rec = recommendSet(
        exercise: plank,
        plannedSets: 2,
        plannedReps: 0,
        plannedWeightKg: 0,
        plannedDurationSec: 45,
        plannedRestSeconds: 60,
        ctx: ctx,
        history: const [],
      );
      expect(rec.durationSec, 45);
      expect(rec.isCalibrating, isTrue);
    });

    test('recepta sesji bez historii używa wartości bazowych', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      final rx = store.buildSessionPrescription(
        plank,
        baseSets: 2,
        baseReps: 0,
        baseWeightKg: 0,
        baseRestSeconds: 60,
      );
      expect(rx.hasEnoughHistory, isFalse);
      expect(rx.dataSource, 'calibration');
      expect(rx.recommended.durationSec, rx.base.durationSec);
      expect(rx.recommendationApplied, isFalse); // nic nie zmieniono
    });
  });

  // ===========================================================================
  // 12. Model recepty: baza vs rekomendacja vs wartości efektywne
  // ===========================================================================

  group('Model recepty sesji', () {
    const base = Prescription(
        sets: 2, reps: 0, weightKg: 0, durationSec: 45, restSeconds: 60);
    const recommended = Prescription(
        sets: 2, reps: 0, weightKg: 0, durationSec: 50, restSeconds: 60);

    test('rozróżnia bazę, rekomendację i wartość efektywną', () {
      const rx = SessionPrescription(
        base: base,
        recommended: recommended,
        reason: 'Stabilnie — +5 s.',
        dataSource: 'history',
        hasEnoughHistory: true,
      );
      expect(rx.base.durationSec, 45);
      expect(rx.recommended.durationSec, 50);
      expect(rx.effectiveDurationSec, 50); // efektywny = rekomendacja
      expect(rx.durationChanged, isTrue);
      expect(rx.recommendationApplied, isTrue);
      expect(rx.manuallyOverridden, isFalse);
    });

    test('ręczne nadpisanie ma pierwszeństwo, baza zostaje nietknięta', () {
      const rx = SessionPrescription(
        base: base,
        recommended: recommended,
        reason: '',
        manualDurationSec: 70,
      );
      expect(rx.effectiveDurationSec, 70);
      expect(rx.manuallyOverridden, isTrue);
      expect(rx.base.durationSec, 45); // baza NIE nadpisana
      expect(rx.recommended.durationSec, 50); // rekomendacja NIE nadpisana
    });

    test('round-trip JSON zachowuje bazę, rekomendację i nadpisanie', () {
      const rx = SessionPrescription(
        base: base,
        recommended: recommended,
        reason: 'powód',
        dataSource: 'history',
        hasEnoughHistory: true,
        manualDurationSec: 70,
      );
      final restored = SessionPrescription.fromJson(rx.toJson());
      expect(restored.base.durationSec, 45);
      expect(restored.recommended.durationSec, 50);
      expect(restored.manualDurationSec, 70);
      expect(restored.reason, 'powód');
      expect(restored.dataSource, 'history');
    });
  });

  // ===========================================================================
  // 2, 3, 4. Timer: start z rekomendacji, zmiana przed startem, zapis wykonania
  // ===========================================================================

  group('Timer ćwiczenia czasowego i recepta w sesji', () {
    final program = WorkoutPlan(
      id: 'p_timed',
      name: 'Program',
      note: '',
      goal: 'Sylwetka',
      isActive: true,
      days: [
        WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
          PlanItem(
            exerciseId: 'plank',
            sets: 2,
            reps: 0,
            durationSec: plank.defaultDurationSec,
            note: '',
          ),
        ]),
      ],
    );

    Future<AppStore> startedStore() async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.addWorkoutPlan(program);
      final plan = store.plans.firstWhere((p) => p.id == 'p_timed');
      await store.startActiveWorkout(
          plan: plan, day: plan.days[0], dayIndex: 0);
      return store;
    }

    test('start treningu tworzy receptę dla każdego ćwiczenia', () async {
      final store = await startedStore();
      final active = store.activeWorkoutSession!.currentExercise!;
      expect(active.prescription, isNotNull);
      expect(active.prescription!.generatedAtIso, isNotEmpty);
      expect(active.prescription!.base.durationSec, plank.defaultDurationSec);
    });

    test('timer startuje od efektywnego czasu z recepty (nie z bazy)',
        () async {
      final store = await startedStore();
      var active = store.activeWorkoutSession!.currentExercise!;
      // Bez historii efektywny = bazowy.
      expect(active.effectiveDurationSec(plank.defaultDurationSec),
          plank.defaultDurationSec);

      // Po ręcznej zmianie timer musi startować od nowej wartości.
      await store.setActiveExerciseDuration(50);
      active = store.activeWorkoutSession!.currentExercise!;
      expect(active.effectiveDurationSec(plank.defaultDurationSec), 50);
    });

    test('użytkownik może zmienić rekomendowany czas przed startem serii',
        () async {
      final store = await startedStore();
      await store.setActiveExerciseDuration(70);
      final rx = store.activeWorkoutSession!.currentExercise!.prescription!;
      expect(rx.manuallyOverridden, isTrue);
      expect(rx.effectiveDurationSec, 70);
      // Rekomendacja użyta w sesji uwzględnia nadpisanie.
      expect(store.recommendationForActiveExercise()!.durationSec, 70);
    });

    test('rzeczywisty czas serii zapisuje się w historii, RPE jest szacowane',
        () async {
      final store = await startedStore();
      await store.setActiveExerciseDuration(50);
      final saved = await store.logTimedSetCompleted(performedSec: 50);
      expect(saved, isTrue);

      final set =
          store.activeWorkoutSession!.currentExercise!.completedSets.single;
      expect(set.durationSec, 50); // rzeczywisty czas serii
      expect(set.activeSeconds, 50);
      // RPE nie jest sztywną siódemką — pochodzi z oszacowania.
      expect(set.rpeSource, 'estimated');
      expect(set.rpeIsEstimated, isTrue);
      expect(set.rpeWasUserEntered, isFalse);
    });

    test('zapisany czas serii wraca do trenera jako czas JEDNEJ serii',
        () async {
      final store = await startedStore();
      await store.setActiveExerciseDuration(50);
      await store.logTimedSetCompleted(performedSec: 50);
      await store.logTimedSetCompleted(performedSec: 50);
      await store.finishActiveWorkout();

      final history = store.coachHistoryForExercise('plank');
      expect(history, isNotEmpty);
      // Czas w historii trenera = czas serii (50 s), NIE suma ani czas sesji.
      expect(history.last.durationSec, 50);
    });

    test('E2E: pętla timer → zapis → historia → rekomendacja nie puchnie',
        () async {
      // Pełny przepływ, który wcześniej dawał „2 × 308 s": trening z KILKOMA
      // ćwiczeniami (czas sesji był dzielony po równo na ćwiczenia i wracał do
      // trenera jako czas serii deski).
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      final multi = WorkoutPlan(
        id: 'p_multi',
        name: 'Program',
        note: '',
        goal: 'Sylwetka',
        isActive: true,
        days: [
          WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
            PlanItem(
                exerciseId: 'plank',
                sets: 2,
                reps: 0,
                durationSec: 45,
                note: ''),
            PlanItem(
                exerciseId: 'bench_press',
                sets: 2,
                reps: 10,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'pushup',
                sets: 2,
                reps: 12,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      await store.addWorkoutPlan(multi);

      // Trzy sesje deski po 45 s — tyle, ile trzeba do wyjścia z kalibracji.
      for (var session = 0; session < 3; session++) {
        final plan = store.plans.firstWhere((p) => p.id == 'p_multi');
        await store.startActiveWorkout(
            plan: plan, day: plan.days[0], dayIndex: 0);
        await store.setActiveExerciseDuration(45);
        await store.logTimedSetCompleted(performedSec: 45);
        await store.logTimedSetCompleted(performedSec: 45);
        await store.moveToNextActiveExercise();
        await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 7);
        await store.finishActiveWorkout();
      }

      // Czas ćwiczenia w logu wynika z JEGO WŁASNYCH serii (praca + przerwy
      // między seriami), a nie z czasu sesji podzielonego przez liczbę ćwiczeń.
      final plankLog = store.logs.firstWhere((l) => l.exerciseId == 'plank');
      final benchLog =
          store.logs.firstWhere((l) => l.exerciseId == 'bench_press');
      const plankWork = 2 * 45; // dwie serie po 45 s
      // Praca deski musi być w całości uwzględniona (+ przerwa między seriami).
      expect(plankLog.durationSec, greaterThanOrEqualTo(plankWork));
      // …i różne ćwiczenia NIE mogą mieć identycznego duration_sec
      // (to był objaw „duration_sec: 64 dla wszystkiego").
      expect(plankLog.durationSec, isNot(benchLog.durationSec));

      // Czas dla trenera to czas JEDNEJ serii (45 s), a nie agregat z logu.
      final history = store.coachHistoryForExercise('plank');
      expect(history.last.durationSec, 45);

      // Rekomendacja na kolejną sesję trzyma się realnego czasu serii: 45 s
      // (utrzymanie — brzuch jest po trzech sesjach jeszcze w regeneracji)
      // albo 50 s (+5 s). NIGDY 308 s ani innej napompowanej wartości.
      final rx = store.buildSessionPrescription(
        plank,
        baseSets: 2,
        baseReps: 0,
        baseWeightKg: 0,
        baseRestSeconds: 60,
        baseDurationSec: 45,
      );
      expect(rx.recommended.durationSec, anyOf(45, 50));
      expect(rx.recommended.durationSec, lessThanOrEqualTo(50));
      expect(rx.base.durationSec, 45); // plan bazowy nietknięty
    });

    test('plan bazowy czasu pochodzi z programu, nie z domyślnej wartości',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      // Program narzuca 30 s, mimo że deska domyślnie ma 45 s.
      final rx = store.buildSessionPrescription(
        plank,
        baseSets: 2,
        baseReps: 0,
        baseWeightKg: 0,
        baseRestSeconds: 60,
        baseDurationSec: 30,
      );
      expect(rx.base.durationSec, 30);
      expect(rx.recommended.durationSec, 30); // brak historii → plan bazowy
    });
  });

  // ===========================================================================
  // Wiarygodność RPE i pewność analizy w SILNIKU (nie tylko w podsumowaniu)
  // ===========================================================================

  group('RPE i pewność analizy w silniku trenera', () {
    CoachHistorySample liftSample({
      double weight = 40,
      int reps = 12,
      bool done = true,
      double rpe = 7,
      bool rpeReliable = true,
      double confidence = 1.0,
      int daysAgo = 1,
    }) =>
        CoachHistorySample(
          date: DateTime.now().subtract(Duration(days: daysAgo)),
          weightKg: weight,
          reps: reps,
          durationSec: 0,
          plannedReps: 12,
          allSetsCompleted: done,
          estimatedRpe: rpe,
          rpeReliable: rpeReliable,
          confidence: confidence,
        );

    List<CoachHistorySample> streak({
      bool rpeReliable = true,
      double rpe = 7,
      double lastConfidence = 1.0,
    }) =>
        [
          liftSample(daysAgo: 5, rpeReliable: rpeReliable, rpe: rpe),
          liftSample(daysAgo: 3, rpeReliable: rpeReliable, rpe: rpe),
          liftSample(
              daysAgo: 1,
              rpeReliable: rpeReliable,
              rpe: rpe,
              confidence: lastConfidence),
        ];

    double recommendedWeight(List<CoachHistorySample> history) => recommendSet(
          exercise: bench,
          plannedSets: 3,
          plannedReps: 12,
          plannedWeightKg: 40,
          plannedDurationSec: 0,
          plannedRestSeconds: 90,
          ctx: ctx,
          history: history,
        ).weightKg;

    test('REGRESJA: niska pewność analizy realnie wstrzymuje progresję', () {
      // Bezpiecznik był udokumentowany i przetestowany, ale recommendSet nie
      // przekazywał lastConfidence — więc w aplikacji nigdy nie działał.
      expect(recommendedWeight(streak(lastConfidence: 1.0)), greaterThan(40),
          reason: 'przy pewnej analizie progresja ma działać');
      expect(recommendedWeight(streak(lastConfidence: 0.3)), 40,
          reason: 'przy niepewnej analizie ciężar ma zostać bez zmian');

      final rec = recommendSet(
        exercise: bench,
        plannedSets: 3,
        plannedReps: 12,
        plannedWeightKg: 40,
        plannedDurationSec: 0,
        plannedRestSeconds: 90,
        ctx: ctx,
        history: streak(lastConfidence: 0.3),
      );
      expect(rec.reasons.join(' '), contains('Niska pewność analizy'));
    });

    test('wiarygodne, wysokie RPE przerywa serię sukcesów', () {
      final hard = streak(rpe: 9);
      expect(recommendedWeight(hard), 40); // bez podbicia ciężaru
      expect(
        decideProgression(exercise: bench, ctx: ctx, history: hard).action,
        isNot(CoachProgressionAction.increaseWeight),
      );
    });

    test('nieznane RPE nie udaje lekkiej sesji ani nie blokuje progresji', () {
      // Brak wiarygodnego RPE: decydują sygnały obiektywne (ukończone serie,
      // powtórzenia w górnym zakresie) — a nie zmyślona „7".
      final unknown = streak(rpeReliable: false, rpe: 0);
      expect(
        decideProgression(exercise: bench, ctx: ctx, history: unknown).action,
        CoachProgressionAction.increaseWeight,
      );
      // Ale „nieznane" nie może udawać wysokiego wysiłku i blokować streaka.
      expect(recommendedWeight(unknown), greaterThan(40));
    });

    test('historia z domyślnym RPE nie wstawia zmyślonej siódemki', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      // Log bez serii z wiarygodnym RPE (starszy zapis: rpe=7 z domyślnej).
      store.logs.add(logOf(
        exerciseId: 'bench_press',
        reps: 12,
        weight: 40,
        rpe: 7,
        sets: [setOf(reps: 12, weight: 40, rpe: 7, rpeSource: 'default')],
      ));
      final history = store.coachHistoryForExercise('bench_press');
      expect(history.single.rpeReliable, isFalse);
      expect(history.single.estimatedRpe, 0,
          reason: 'brak sygnału ≠ RPE 7 — nie zmyślamy pomiaru');
    });

    test('przerwana seria obniża pewność sesji w historii trenera', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.logs.add(logOf(
        exerciseId: 'bench_press',
        reps: 6,
        weight: 40,
        sets: [
          setOf(
            reps: 6,
            weight: 40,
            rpe: 6,
            rpeSource: 'estimated',
            outcome: 'interrupted',
            estimatedRpe: 6,
            confidence: 0.3, // przerwana seria = niepewna analiza
          ),
        ],
      ));
      final history = store.coachHistoryForExercise('bench_press');
      expect(history.single.confidence, lessThan(0.5));
    });

    test('ręcznie wpisane RPE daje pełną pewność (brak powodów do nieufności)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.logs.add(logOf(
        exerciseId: 'bench_press',
        reps: 12,
        weight: 40,
        rpe: 8,
        sets: [setOf(reps: 12, weight: 40, rpe: 8, rpeSource: 'user')],
      ));
      final history = store.coachHistoryForExercise('bench_press');
      expect(history.single.rpeReliable, isTrue);
      expect(history.single.estimatedRpe, 8);
      expect(history.single.confidence, 1.0);
    });
  });

  // ===========================================================================
  // Przerwa: recepta i timer odpoczynku muszą pokazywać TĘ SAMĄ wartość
  // ===========================================================================

  group('Przerwa — jedno źródło prawdy', () {
    WorkoutPlan planWith(String exerciseId, {int reps = 10, int rest = 90}) =>
        WorkoutPlan(
          id: 'p_rest',
          name: 'Program',
          note: '',
          goal: 'Sylwetka',
          isActive: true,
          days: [
            WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
              PlanItem(
                exerciseId: exerciseId,
                sets: 3,
                reps: reps,
                durationSec: 0,
                note: '',
                restSeconds: rest,
              ),
            ]),
          ],
        );

    Future<AppStore> startWith(WorkoutPlan program) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.addWorkoutPlan(program);
      final plan = store.plans.firstWhere((p) => p.id == 'p_rest');
      await store.startActiveWorkout(
          plan: plan, day: plan.days[0], dayIndex: 0);
      return store;
    }

    test('przerwa bazowa jest dobierana do typu ćwiczenia, gdy plan jej nie ma',
        () {
      // 90 s = zastana wartość „program nic nie ustawił" → dobierz do typu.
      expect(
        baseRestFor(bench,
                plannedReps: 10, plannedRestSeconds: kUnsetRestSeconds)
            .seconds,
        120, // wielostawowe
      );
      expect(
        baseRestFor(bench,
                plannedReps: 5, plannedRestSeconds: kUnsetRestSeconds)
            .seconds,
        180, // siłowe (≤6 powt.)
      );
      expect(
        baseRestFor(ExerciseRepo.byId('bicep_curl'),
                plannedReps: 12, plannedRestSeconds: kUnsetRestSeconds)
            .seconds,
        60, // izolowane
      );
      // Jawna przerwa z programu ma pierwszeństwo.
      final explicit =
          baseRestFor(bench, plannedReps: 10, plannedRestSeconds: 45);
      expect(explicit.seconds, 45);
      expect(explicit.label, 'Przerwa ustawiona w planie');
    });

    test('ćwiczenie czasowe NIE jest traktowane jak siłowe (0 powtórzeń)', () {
      // Stara heurystyka: `plannedReps <= 6` przy 0 powtórzeń → deska dostawała
      // 180 s przerwy z etykietą „Ćwiczenie siłowe".
      final rest = baseRestFor(plank,
          plannedReps: 0, plannedRestSeconds: kUnsetRestSeconds);
      expect(rest.seconds, 60);
      expect(rest.label, 'Ćwiczenie czasowe');
    });

    test('rozciąganie dostaje krótką przerwę, nie kilkuminutową', () {
      final stretch = ExerciseRepo.combined(const []).firstWhere(
        (e) => e.entryType == ExerciseEntryType.mobility,
        orElse: () => plank,
      );
      expect(stretch.entryType, ExerciseEntryType.mobility);
      final rest = baseRestFor(stretch,
          plannedReps: 0, plannedRestSeconds: kUnsetRestSeconds);
      expect(rest.seconds, 30);
      expect(rest.label, 'Mobilność / rozciąganie');
    });

    test('REGRESJA: plan i timer odpoczynku pokazują tę samą przerwę',
        () async {
      // Wcześniej: linia planu mówiła „przerwa 90 s" (z recepty), a timer
      // odliczał 120/180 s (własna heurystyka) — dwa źródła prawdy.
      final store = await startWith(planWith('bench_press'));
      final active = store.activeWorkoutSession!.currentExercise!;
      final rx = active.prescription!;

      // Recepta zna prawdziwą przerwę, nie surowe 90 z planu.
      expect(rx.base.restSeconds, 120);
      expect(rx.effective.restSeconds, 120);
      expect(active.restSeconds, 120);
      expect(rx.restChanged, isFalse); // sam dobór domyślnej ≠ „zmiana"

      // To, co pokazuje plan…
      expect(store.recommendationForActiveExercise()!.restSeconds, 120);
      // …jest tym, co odlicza timer.
      expect(workoutRestRecommendation(bench, active).seconds, 120);

      // I tym, co realnie ustawia się po zapisaniu serii.
      await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 7);
      expect(store.activeWorkoutSession!.restTimerTotalSeconds, 120);
    });

    test('etykieta przerwy opisuje jej prawdziwe źródło', () async {
      // Przerwa dobrana przez typ ćwiczenia NIE może udawać „ustawionej w planie".
      final store = await startWith(planWith('bench_press'));
      final active = store.activeWorkoutSession!.currentExercise!;
      expect(workoutRestRecommendation(bench, active).label,
          'Ćwiczenie wielostawowe');

      // Jawna przerwa z programu jest opisana jako pochodząca z planu.
      final explicit = await startWith(planWith('bench_press', rest: 45));
      final explicitActive = explicit.activeWorkoutSession!.currentExercise!;
      expect(workoutRestRecommendation(bench, explicitActive).label,
          'Przerwa ustawiona w planie');

      // Wydłużenie przy słabej regeneracji jest nazwane wprost.
      expect(
        restLabelFor(bench,
            plannedReps: 10, baseRestSeconds: 120, effectiveRestSeconds: 140),
        'Wydłużona — słabsza regeneracja',
      );
    });

    test('jawna przerwa z programu trafia do recepty i do timera', () async {
      final store = await startWith(planWith('bench_press', rest: 45));
      final active = store.activeWorkoutSession!.currentExercise!;
      expect(active.prescription!.effective.restSeconds, 45);
      expect(workoutRestRecommendation(bench, active).seconds, 45);
      await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 7);
      expect(store.activeWorkoutSession!.restTimerTotalSeconds, 45);
    });

    test('sesja bez recepty (starszy zapis) działa jak dotychczas', () {
      const legacy = ActiveWorkoutExercise(
        exerciseId: 'bench_press',
        plannedSets: 3,
        plannedReps: 10,
        suggestedWeightKg: 40,
        restSeconds: kUnsetRestSeconds,
        note: '',
        // brak prescription
      );
      expect(workoutRestRecommendation(bench, legacy).seconds, 120);
      expect(workoutRestRecommendation(bench, legacy).label,
          'Ćwiczenie wielostawowe');
    });

    test('zamiana ćwiczenia buduje NOWĄ receptę, nie dziedziczy poprzedniej',
        () async {
      final store = await startWith(planWith('bench_press'));
      expect(store.activeWorkoutSession!.currentExercise!.restSeconds, 120);

      // Podmiana na ćwiczenie izolowane — przerwa i recepta muszą się przeliczyć.
      final curl = ExerciseRepo.byId('bicep_curl');
      await store.replaceActiveWorkoutExercise(curl);

      final active = store.activeWorkoutSession!.currentExercise!;
      expect(active.exerciseId, 'bicep_curl');
      final rx = active.prescription!;
      expect(rx.base.restSeconds, 60); // izolowane, nie 120 po wyciskaniu
      expect(active.restSeconds, 60);
      expect(workoutRestRecommendation(curl, active).seconds, 60);
    });
  });

  // ===========================================================================
  // 5, 6, 7, 8, 9. Progresja zależna od typu ćwiczenia i źródła RPE
  // ===========================================================================

  group('Metadane progresji wg typu wpisu', () {
    test('typy deklarują dozwolone sposoby progresji', () {
      expect(ExerciseEntryType.repsWeight.supportsWeightProgression, isTrue);
      expect(
          ExerciseEntryType.bodyweightReps.supportsWeightProgression, isFalse);
      expect(
          ExerciseEntryType.bodyweightTime.supportsWeightProgression, isFalse);
      expect(ExerciseEntryType.mobility.supportsWeightProgression, isFalse);
      expect(ExerciseEntryType.mobility.supportsDurationProgression, isTrue);
      expect(
          ExerciseEntryType.bodyweightTime.supportsDurationProgression, isTrue);
      expect(ExerciseEntryType.repsWeight.supportsDurationProgression, isFalse);
      expect(ExerciseEntryType.bodyweightReps.supportsHarderVariation, isTrue);
      expect(ExerciseEntryType.cardioDistanceTime.supportsDistanceProgression,
          isTrue);
      expect(ExerciseEntryType.repsWeight.progressionMode, 'ciężar');
      expect(ExerciseEntryType.mobility.progressionMode, 'jakość ruchu');
    });
  });

  group('Sugestie progresji w podsumowaniu', () {
    List<WorkoutLog> weightedHistory({
      required String rpeSource,
      int rpe = 7,
      double estimatedRpe = 0,
      double confidence = 0,
    }) =>
        [
          for (var i = 1; i <= 3; i++)
            logOf(
              exerciseId: 'bench_press',
              daysAgo: i,
              reps: 12,
              weight: 40,
              rpe: rpe,
              sets: [
                setOf(
                  reps: 12,
                  weight: 40,
                  rpe: rpe,
                  rpeSource: rpeSource,
                  estimatedRpe: estimatedRpe,
                  confidence: confidence,
                ),
              ],
            ),
        ];

    test('5. ćwiczenie rozciągające NIE dostaje progresji ciężaru', () {
      // Ćwiczenie mobilności z lokalnej bazy.
      final stretch = ExerciseRepo.combined(const []).firstWhere(
        (e) => e.entryType == ExerciseEntryType.mobility,
        orElse: () => plank,
      );
      expect(stretch.entryType, ExerciseEntryType.mobility,
          reason: 'Test wymaga ćwiczenia mobilności w bazie');

      final logs = [
        for (var i = 1; i <= 3; i++)
          logOf(
            exerciseId: stretch.id,
            daysAgo: i,
            reps: 0,
            weight: 0,
            sets: [setOf(reps: 0, weight: 0, duration: 40, rpeSource: 'user')],
          ),
      ];
      final s = progressionSuggestionForExercise(
        exerciseId: stretch.id,
        allLogs: logs,
        plannedReps: 0,
        plannedWeightKg: 0,
        exercise: stretch,
      );
      expect(s, isNotNull);
      expect(s!.action, isNot(ProgressionAction.increaseWeight));
      expect(s.action, isNot(ProgressionAction.decreaseWeight));
      expect(s.label.toLowerCase(), isNot(contains('ciężar')));
      expect(s.reason.toLowerCase(), contains('zakres'));
      expect(s.suggestedWeightKg, s.currentWeightKg); // ciężar nietknięty
    });

    test('5b. ćwiczenie czasowe (deska) dostaje progresję CZASU, nie ciężaru',
        () {
      final logs = [
        for (var i = 1; i <= 3; i++)
          logOf(
            exerciseId: 'plank',
            daysAgo: i,
            reps: 0,
            weight: 0,
            sets: [setOf(reps: 0, weight: 0, duration: 45, rpeSource: 'user')],
          ),
      ];
      final s = progressionSuggestionForExercise(
        exerciseId: 'plank',
        allLogs: logs,
        plannedReps: 0,
        plannedWeightKg: 0,
        exercise: plank,
      );
      expect(s, isNotNull);
      expect(s!.action, isNot(ProgressionAction.increaseWeight));
      expect(s.label, 'Dodaj 5 s');
      expect(s.reason, contains('50 s')); // 45 + 5
    });

    test('6. masa ciała bez obciążenia zewnętrznego → brak progresji ciężaru',
        () {
      expect(pushup.entryType.supportsWeightProgression, isFalse);
      final logs = [
        for (var i = 1; i <= 3; i++)
          logOf(
            exerciseId: 'pushup',
            daysAgo: i,
            reps: 12,
            weight: 0,
            sets: [setOf(reps: 12, weight: 0, rpeSource: 'user')],
          ),
      ];
      final s = progressionSuggestionForExercise(
        exerciseId: 'pushup',
        allLogs: logs,
        plannedReps: 12,
        plannedWeightKg: 0,
        exercise: pushup,
      );
      expect(s, isNotNull);
      expect(s!.action, isNot(ProgressionAction.increaseWeight));
      expect(s.action, ProgressionAction.increaseReps);
      expect(s.suggestedWeightKg, 0);
    });

    test('7. ćwiczenie z ciężarem MOŻE dostać progresję ciężaru', () {
      final s = progressionSuggestionForExercise(
        exerciseId: 'bench_press',
        allLogs: weightedHistory(rpeSource: 'user', rpe: 7),
        plannedReps: 12,
        plannedWeightKg: 40,
        exercise: bench,
      );
      expect(s, isNotNull);
      expect(s!.action, ProgressionAction.increaseWeight);
      expect(s.suggestedWeightKg, greaterThan(40));
    });

    test('8. domyślne RPE 7 NIE powoduje automatycznej progresji ciężaru', () {
      // rpeSource: 'default' = techniczna wartość domyślna, nie dowód wysiłku.
      final s = progressionSuggestionForExercise(
        exerciseId: 'bench_press',
        allLogs: weightedHistory(rpeSource: 'default', rpe: 7),
        plannedReps: 12,
        plannedWeightKg: 40,
        exercise: bench,
      );
      expect(s, isNotNull);
      expect(s!.action, isNot(ProgressionAction.increaseWeight));
      expect(s.action, ProgressionAction.maintain);
      expect(s.reason.toLowerCase(), contains('zbiera dane'));
    });

    test('9. RPE świadomie wpisane przez użytkownika jest wykorzystywane', () {
      final logs = weightedHistory(rpeSource: 'user', rpe: 7);
      expect(logs.first.workoutSets.single.rpeWasUserEntered, isTrue);
      expect(logs.first.workoutSets.single.hasReliableRpe, isTrue);

      final s = progressionSuggestionForExercise(
        exerciseId: 'bench_press',
        allLogs: logs,
        plannedReps: 12,
        plannedWeightKg: 40,
        exercise: bench,
      );
      expect(s!.action, ProgressionAction.increaseWeight);
      expect(s.reason, contains('RPE 7.0'));
    });

    test('9b. pewne oszacowanie systemu też jest wiarygodnym dowodem', () {
      final s = progressionSuggestionForExercise(
        exerciseId: 'bench_press',
        allLogs: weightedHistory(
          rpeSource: 'estimated',
          rpe: 7,
          estimatedRpe: 7,
          confidence: 0.8,
        ),
        plannedReps: 12,
        plannedWeightKg: 40,
        exercise: bench,
      );
      expect(s!.action, ProgressionAction.increaseWeight);
    });

    test('9c. niepewne oszacowanie NIE wystarcza do zwiększenia ciężaru', () {
      final s = progressionSuggestionForExercise(
        exerciseId: 'bench_press',
        allLogs: weightedHistory(
          rpeSource: 'estimated',
          rpe: 7,
          estimatedRpe: 7,
          confidence: 0.2, // niska pewność
        ),
        plannedReps: 12,
        plannedWeightKg: 40,
        exercise: bench,
      );
      expect(s!.action, isNot(ProgressionAction.increaseWeight));
    });
  });

  // ===========================================================================
  // 5. Źródło RPE — model danych
  // ===========================================================================

  group('Źródło RPE (rpeSource)', () {
    test('rozróżnia wpis użytkownika, oszacowanie i wartość domyślną', () {
      expect(setOf(rpeSource: 'user').rpeWasUserEntered, isTrue);
      expect(setOf(rpeSource: 'user').rpeIsDefault, isFalse);

      final estimated =
          setOf(rpeSource: 'estimated', estimatedRpe: 7, confidence: 0.7);
      expect(estimated.rpeIsEstimated, isTrue);
      expect(estimated.rpeWasUserEntered, isFalse);
      expect(estimated.hasReliableRpe, isTrue);

      final technical = setOf(rpeSource: 'default');
      expect(technical.rpeIsDefault, isTrue);
      expect(technical.hasReliableRpe, isFalse);
    });

    test('zgodność wsteczna: starszy zapis bez rpeSource', () {
      // Ręczny wpis (bez outcome i bez szacunku) → traktowany jak użytkownika.
      expect(setOf(rpe: 8).rpeWasUserEntered, isTrue);
      // Zapis z trybu prowadzenia → oszacowanie.
      final guided = setOf(rpe: 7, outcome: 'as_planned', estimatedRpe: 7);
      expect(guided.rpeIsEstimated, isTrue);
      expect(guided.rpeWasUserEntered, isFalse);
    });

    test('round-trip JSON zachowuje rpeSource', () {
      final restored = WorkoutSet.fromJson(setOf(rpeSource: 'user').toJson());
      expect(restored.rpeSource, 'user');
      expect(restored.rpeWasUserEntered, isTrue);
    });
  });

  // ===========================================================================
  // 12. Frontend wysyła sensowny opis treningu (pole `description`)
  // ===========================================================================

  group('Opis treningu dla analizy AI', () {
    test('opis zawiera nazwę, czas, liczby i najważniejsze wyniki', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      final summary = CompletedWorkoutSummary(
        sessionId: 's1',
        name: 'Plan · Dzień 1',
        startedAt: DateTime(2026, 7, 16, 18),
        endedAt: DateTime(2026, 7, 16, 18, 45),
        exerciseCount: 2,
        setCount: 5,
        volume: 1200,
        averageRpe: 7.5,
      );
      final description = store.buildWorkoutDescription(summary, [
        logOf(
          exerciseId: 'bench_press',
          reps: 10,
          weight: 40,
          sets: [setOf(reps: 10, weight: 40)],
        ),
        logOf(
          exerciseId: 'plank',
          reps: 0,
          weight: 0,
          durationSec: 50,
          sets: [setOf(reps: 0, weight: 0, duration: 50)],
        ),
      ]);

      expect(description, isNotEmpty);
      expect(description, contains('Plan · Dzień 1'));
      expect(description, contains('45 min'));
      expect(description, contains('serii: 5'));
      expect(description, contains('1200 kg'));
      expect(description, contains('RPE 7.5'));
      expect(description, contains('40 kg')); // ciężar dla ćwiczenia siłowego
      expect(description, contains('50 s')); // czas dla ćwiczenia czasowego
    });
  });

  // ===========================================================================
  // 13. Błąd analizy AI nie pokazuje użytkownikowi pełnego wyjątku
  // ===========================================================================

  group('Komunikat błędu analizy AI', () {
    test('jest krótki, po polsku i bez technicznych szczegółów', () {
      expect(kWorkoutAnalysisFailedMessage, contains('Nie udało się'));
      expect(kWorkoutAnalysisFailedMessage, contains('ponowić analizę'));
      // Żadnych śladów wyjątku/JSON-a/stack trace'u.
      expect(kWorkoutAnalysisFailedMessage.toLowerCase(),
          isNot(contains('exception')));
      expect(kWorkoutAnalysisFailedMessage, isNot(contains('422')));
      expect(kWorkoutAnalysisFailedMessage, isNot(contains('{')));
      expect(kWorkoutAnalysisFailedMessage, isNot(contains('#0')));
    });
  });
}
