import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TESTY PRZEPŁYWU: „regeneracja doradza, nie zamyka drzwi" (spec 12, 13, 14, 15).

Future<AppStore> _store({
  TrainingFocusArea primary = TrainingFocusArea.push,
  TrainingFocusArea? secondary = TrainingFocusArea.shoulders,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.setWeekdayPlan(
    DateTime.now().weekday,
    TrainingDayPlan(primary: primary, secondary: secondary),
  );
  return store;
}

Future<void> _log(
  AppStore store,
  String exerciseId, {
  int hoursAgo = 1,
  int sets = 5,
  int rpe = 9,
}) async {
  final at = DateTime.now().subtract(Duration(hours: hoursAgo));
  await store.addLog(WorkoutLog(
    id: 'log_${exerciseId}_$hoursAgo',
    exerciseId: exerciseId,
    date: DateTime(at.year, at.month, at.day),
    sets: sets,
    reps: 10,
    weightKg: 60,
    durationSec: 1800,
    rpe: rpe,
    calories: 250,
    note: '',
    aiConfidence: 0,
    sessionId: 'sess_${exerciseId}_$hoursAgo',
    sessionName: 'Trening',
    performedAt: at,
  ));
}

Widget _wrapPlan(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(store: store, child: const Scaffold(body: PlanPage())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // SPEC 12 — drugi zestaw dnia NIGDY nie jest blokowany ani skreślany
  // =========================================================================
  group('Regeneracja nie blokuje drugiego zestawu dnia', () {
    test('po wykonaniu Push zestaw Barki nadal jest w planie dnia', () async {
      final store = await _store();
      await _log(store, 'bench_press');

      final blocks = store.todayTrainingBlocks();
      expect(blocks.map((b) => b.area), contains(TrainingFocusArea.shoulders),
          reason: 'dodatek dnia nie może zniknąć z rozkładu');
      final shoulders =
          blocks.firstWhere((b) => b.area == TrainingFocusArea.shoulders);
      expect(shoulders.isDone, isFalse);
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.shoulders);
      expect(store.isTodayTrainingClosed(), isFalse);
    });

    test('po wykonaniu Barków zestaw Push nadal jest w planie dnia', () async {
      final store = await _store();
      await _log(store, 'shoulder_press');

      final blocks = store.todayTrainingBlocks();
      final push = blocks.firstWhere((b) => b.area == TrainingFocusArea.push);
      expect(push.isDone, isFalse);
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.push);
    });

    test('po Push barki dostają OSTRZEŻENIE o gotowości, nie blokadę',
        () async {
      final store = await _store();
      await _log(store, 'bench_press', sets: 6);

      final shoulders = store
          .todayTrainingBlocks()
          .firstWhere((b) => b.area == TrainingFocusArea.shoulders);
      expect(shoulders.hasReadinessWarning, isTrue,
          reason: 'przedni akton barków dostał już bodziec w pchaniu');
      expect(shoulders.readinessWarning.toLowerCase(),
          contains('możesz kontynuować'));
      expect(shoulders.fatiguedMuscles, isNotEmpty);
      expect(shoulders.readinessPercent, lessThan(60));
    });

    test('bez świeżego bodźca nie ma żadnego ostrzeżenia', () async {
      final store = await _store();
      final shoulders = store
          .todayTrainingBlocks()
          .firstWhere((b) => b.area == TrainingFocusArea.shoulders);
      expect(shoulders.hasReadinessWarning, isFalse);
    });

    testWidgets('kafelek zmęczonego zestawu jest KLIKALNY i ma trójkąt',
        (tester) async {
      final store = await _store();
      await _log(store, 'bench_press', sets: 6);
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapPlan(store));
      await tester.pumpAndSettle();

      // Oba tory widoczne — drugi nie zniknął.
      expect(find.byKey(const Key('today_block_1')), findsOneWidget);
      final secondBlock = find.byKey(const Key('today_block_2'));
      expect(secondBlock, findsOneWidget);

      // …i nadal da się w niego wejść (InkWell ma akcję).
      final inkWell = tester.widget<InkWell>(secondBlock);
      expect(inkWell.onTap, isNotNull,
          reason: 'regeneracja nie może odbierać możliwości treningu');

      // Trójkąt ostrzegawczy jest, a po kliknięciu tłumaczy sytuację.
      final badge = find.byKey(const Key('block_readiness_warning_2'));
      expect(badge, findsOneWidget);
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.text('Uwaga'), findsOneWidget);
      expect(find.textContaining('Możesz kontynuować trening'), findsOneWidget);
      expect(find.byKey(const Key('warning_start_anyway')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wykonany zestaw też pozostaje klikalny', (tester) async {
      final store = await _store();
      await _log(store, 'bench_press');
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapPlan(store));
      await tester.pumpAndSettle();

      final inkWell =
          tester.widget<InkWell>(find.byKey(const Key('today_block_1')));
      expect(inkWell.onTap, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // SPEC 28 — rekomendacja KOLEJNOŚCI (bez samodzielnego przestawiania)
  // =========================================================================
  group('Kolejność zestawów w dniu', () {
    test('Push + Barki dostaje rekomendację kolejności', () async {
      final store = await _store();
      final advice = store.todayOrderAdvice();
      expect(advice, isNotNull);
      expect(advice!.firstArea, TrainingFocusArea.push);
      expect(advice.secondArea, TrainingFocusArea.shoulders);
      expect(advice.sharedMuscles, contains(BodyMuscle.frontShoulders));
      expect(advice.message, contains('rekomenduje'));
    });

    test('gdy tory się nie zazębiają, nie ma żadnej rekomendacji', () async {
      final store = await _store(
          primary: TrainingFocusArea.legs, secondary: TrainingFocusArea.core);
      expect(store.todayOrderAdvice(), isNull);
    });
  });

  // =========================================================================
  // SPEC 13 — status dnia: NIEROZPOCZĘTY / CZĘŚCIOWY / WYKONANY
  // =========================================================================
  group('Status dnia — częściowe wykonanie', () {
    test('logika statusu działa dla dowolnej liczby zestawów', () {
      expect(scheduleStatusFor(done: 0, required: 2),
          ScheduleDayStatus.notStarted);
      expect(scheduleStatusFor(done: 1, required: 2),
          ScheduleDayStatus.partiallyCompleted);
      expect(
          scheduleStatusFor(done: 2, required: 2), ScheduleDayStatus.completed);

      expect(scheduleStatusFor(done: 1, required: 3),
          ScheduleDayStatus.partiallyCompleted);
      expect(scheduleStatusFor(done: 2, required: 3),
          ScheduleDayStatus.partiallyCompleted);
      expect(
          scheduleStatusFor(done: 3, required: 3), ScheduleDayStatus.completed);

      expect(scheduleStatusFor(done: 1, required: 4),
          ScheduleDayStatus.partiallyCompleted);
      expect(scheduleStatusFor(done: 3, required: 4),
          ScheduleDayStatus.partiallyCompleted);
      expect(
          scheduleStatusFor(done: 4, required: 4), ScheduleDayStatus.completed);

      // Dzień bez „odhaczalnych" zestawów (mobilność / cardio).
      expect(scheduleStatusFor(done: 0, required: 0, anyLogs: true),
          ScheduleDayStatus.completed);
      expect(scheduleStatusFor(done: 0, required: 0),
          ScheduleDayStatus.notStarted);
      // Zapisany trening bez domknięcia toru to postęp, nie pustka.
      expect(scheduleStatusFor(done: 0, required: 2, anyLogs: true),
          ScheduleDayStatus.partiallyCompleted);
    });

    test('1/2 zestawów dnia → CZĘŚCIOWY, 2/2 → WYKONANY', () async {
      final store = await _store();
      final today = store.resolvedDayFor(DateTime.now())!;
      expect(store.scheduleDayStatus(today), ScheduleDayStatus.notStarted);

      await _log(store, 'bench_press');
      final afterFirst = store.resolvedDayFor(DateTime.now())!;
      expect(store.scheduleDayStatus(afterFirst),
          ScheduleDayStatus.partiallyCompleted);
      expect(store.isScheduleDayDone(afterFirst), isFalse);

      await _log(store, 'shoulder_press', hoursAgo: 0);
      final afterSecond = store.resolvedDayFor(DateTime.now())!;
      expect(store.scheduleDayStatus(afterSecond), ScheduleDayStatus.completed);
      expect(store.isScheduleDayDone(afterSecond), isTrue);
    });

    test('dzień jednotorowy domyka się po jednym zestawie', () async {
      final store = await _store(
          primary: TrainingFocusArea.legs, secondary: null);
      await _log(store, 'squat');
      final today = store.resolvedDayFor(DateTime.now())!;
      expect(store.scheduleDayStatus(today), ScheduleDayStatus.completed);
    });

    testWidgets('kalendarz rysuje kółko z minusem dla dnia częściowego',
        (tester) async {
      final store = await _store();
      await _log(store, 'bench_press');
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: TrainingWeekCalendarCard()),
        ),
      ));
      await tester.pumpAndSettle();

      final index = DateTime.now().weekday - 1;
      expect(find.byKey(Key('calendar_day_partial_$index')), findsOneWidget);
      expect(find.byKey(Key('calendar_day_done_$index')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // SPEC 14 — komunikaty timera liczone z EFEKTYWNEGO czasu serii
  // =========================================================================
  group('Timer ćwiczenia czasowego — jedno źródło prawdy', () {
    test('baza 30 s, rekomendacja 50 s → połowa czasu przy 25 s', () {
      const base = Prescription(
          sets: 3, reps: 0, weightKg: 0, durationSec: 30, restSeconds: 60);
      const recommended = Prescription(
          sets: 3, reps: 0, weightKg: 0, durationSec: 50, restSeconds: 60);
      const rx = SessionPrescription(
          base: base, recommended: recommended, reason: '');
      const active = ActiveWorkoutExercise(
        exerciseId: 'plank',
        plannedSets: 3,
        plannedReps: 0,
        suggestedWeightKg: 0,
        restSeconds: 60,
        note: '',
        prescription: rx,
      );

      // Timer musi startować z 50 s, a nie z bazowych 30 s.
      final total = active.effectiveDurationSec(30);
      expect(total, 50);
      expect(halfwayMarkSeconds(total), 25);
      expect(
          timedCoachMessage(
              totalSeconds: total, secondsLeft: 25, running: true),
          'Połowa czasu');
      // Przy 15 s (połowa BAZY) nie może już padać ten komunikat.
      expect(
          timedCoachMessage(
              totalSeconds: total, secondsLeft: 15, running: true),
          isNot('Połowa czasu'));
    });

    test('rekomendacja 60 s → połowa czasu przy 30 s', () {
      expect(halfwayMarkSeconds(60), 30);
      expect(
          timedCoachMessage(totalSeconds: 60, secondsLeft: 30, running: true),
          'Połowa czasu');
    });

    test('progi końcowe liczą się od realnego czasu', () {
      expect(timedCoachMessage(totalSeconds: 50, secondsLeft: 50, running: true),
          'Start');
      expect(timedCoachMessage(totalSeconds: 50, secondsLeft: 10, running: true),
          'Ostatnie 10 sekund');
      expect(timedCoachMessage(totalSeconds: 50, secondsLeft: 4, running: true),
          'Ostatnie 5 sekund');
      expect(timedCoachMessage(totalSeconds: 50, secondsLeft: 0, running: true),
          'Koniec');
      expect(timedCoachMessage(totalSeconds: 50, secondsLeft: 25, running: false),
          'Przygotuj się');
    });

    test('ręczne nadpisanie czasu wygrywa z rekomendacją', () {
      const rx = SessionPrescription(
        base: Prescription(
            sets: 2, reps: 0, weightKg: 0, durationSec: 30, restSeconds: 60),
        recommended: Prescription(
            sets: 2, reps: 0, weightKg: 0, durationSec: 50, restSeconds: 60),
        reason: '',
        manualDurationSec: 80,
      );
      const active = ActiveWorkoutExercise(
        exerciseId: 'plank',
        plannedSets: 2,
        plannedReps: 0,
        suggestedWeightKg: 0,
        restSeconds: 60,
        note: '',
        prescription: rx,
      );
      expect(active.effectiveDurationSec(30), 80);
      expect(halfwayMarkSeconds(active.effectiveDurationSec(30)), 40);
    });
  });

  // =========================================================================
  // SPEC 15 — odliczanie 3–2–1 blokuje akcje zmieniające stan treningu
  // =========================================================================
  group('Odliczanie 3–2–1 blokuje podwójny start', () {
    testWidgets('w trakcie odliczania kontrolki są wyłączone',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      final plan = WorkoutPlan(
        id: 'p_count',
        name: 'Program',
        note: '',
        goal: 'Sylwetka',
        days: [
          WorkoutDay(weekday: 1, title: 'Dzień', items: [
            PlanItem(
                exerciseId: 'plank',
                sets: 3,
                reps: 0,
                durationSec: 45,
                note: ''),
          ]),
        ],
      );
      await store.startActiveWorkout(plan: plan, day: plan.days.first);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home:
            AppScope(store: store, child: const ActiveExercisePlayerPage()),
      ));
      await tester.pump();

      // Pierwsza seria zapisana → rusza odpoczynek.
      await store.logTimedSetCompleted(performedSec: 45);
      await tester.pump(const Duration(seconds: 1));
      expect(store.activeWorkoutSession!.hasActiveRestTimer, isTrue);

      // Pominięcie odpoczynku uruchamia odliczanie 3–2–1.
      await store.skipActiveRestTimer();
      await tester.pump(const Duration(seconds: 1));

      // Nakładka odliczania przechwytuje dotyk…
      expect(find.byType(AbsorbPointer), findsWidgets);
      // …a akcje zmieniające stan treningu są nieaktywne.
      final buttons = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((button) => button.onPressed == null)
          .toList();
      expect(buttons, isNotEmpty,
          reason: 'główna akcja musi być zablokowana w trakcie odliczania');

      // Po zakończeniu odliczania kontrolki wracają.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final activeButtons = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((button) => button.onPressed != null)
          .toList();
      expect(activeButtons, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
