import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('basic progress counters group session logs as one workout', () {
    final now = DateTime(2026, 6, 23, 18);
    final logs = [
      _progressLog(
        id: 'push-1',
        sessionId: 'push-session',
        sessionName: 'Plan Push · Góra',
        exerciseId: 'pushup',
        date: now,
        sets: _sets(weight: 20, repetitions: 10, count: 2),
      ),
      _progressLog(
        id: 'push-2',
        sessionId: 'push-session',
        sessionName: 'Plan Push · Góra',
        exerciseId: 'squat',
        date: now,
        sets: _sets(weight: 50, repetitions: 8, count: 2),
      ),
      _progressLog(
        id: 'manual-1',
        sessionId: '',
        sessionName: '',
        exerciseId: 'bicep_curl',
        date: now,
        sets: _sets(weight: 12.5, repetitions: 12, count: 3),
      ),
    ];

    expect(workoutEntryCount(logs), 2);
    expect(completedWorkoutSetCount(logs), 7);
    expect(startOfTrainingWeek(now), DateTime(2026, 6, 22));
    expect(formatProgressVolume(12650), '12.7k kg');
  });

  testWidgets('progress page shows basic stats and a topic tile per value', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 18);
    final olderThisMonth = DateTime(now.year, now.month, now.day > 10 ? now.day - 10 : 1, 18);

    store.logs
      ..clear()
      ..addAll([
        _progressLog(
          id: 'push-1',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'pushup',
          date: today,
          sets: _sets(weight: 20, repetitions: 10, count: 2),
        ),
        _progressLog(
          id: 'push-2',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'squat',
          date: today,
          sets: _sets(weight: 50, repetitions: 8, count: 2),
        ),
        _progressLog(
          id: 'manual-1',
          sessionId: '',
          sessionName: '',
          exerciseId: 'bicep_curl',
          date: today,
          sets: _sets(weight: 12.5, repetitions: 12, count: 3),
        ),
        _progressLog(
          id: 'month-1',
          sessionId: 'month-session',
          sessionName: 'Plan Pull · Plecy',
          exerciseId: 'deadlift',
          date: olderThisMonth,
          sets: _sets(weight: 80, repetitions: 5, count: 2),
        ),
      ]);
    await store.saveLogs();

    final restored = AppStore();
    await restored.load();
    final weekLogs = restored.logsBetween(startOfTrainingWeek(now), now);
    final monthLogs = restored.logsBetween(DateTime(now.year, now.month), now);
    final expectedWeekWorkouts = workoutEntryCount(weekLogs);
    final expectedMonthWorkouts = workoutEntryCount(monthLogs);
    final expectedWeekVolume = formatProgressVolume(DayTotals.from(weekLogs).volume);
    final expectedMonthVolume = formatProgressVolume(DayTotals.from(monthLogs).volume);

    await tester.binding.setSurfaceSize(const Size(320, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        store: restored,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: ProgressPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Progres'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('progress_week_workouts')),
        matching: find.text('$expectedWeekWorkouts'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('progress_month_workouts')),
        matching: find.text('$expectedMonthWorkouts'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('progress_week_volume')),
        matching: find.text(expectedWeekVolume),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('progress_month_volume')),
        matching: find.text(expectedMonthVolume),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Zamiast jednej długiej listy wykresów zakładka jest siatką kafelków:
    // jedna wartość = jeden kafelek = jedna strona.
    await tester.scrollUntilVisible(
      find.byKey(const Key('progress_topic_volume')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('progress_topic_volume')), findsOneWidget);
    expect(find.text('Objętość tygodniowa'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('progress_topic_muscle_frequency')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Wykres częstotliwości partii NIE jest jeszcze zbudowany — leży na
    // stronie tematu, nie na zakładce.
    expect(find.text('Najrzadziej trenowane partie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic tile opens a page with the chart, description and tips', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final now = DateTime.now();
    store.logs
      ..clear()
      ..addAll([
        _progressLog(
          id: 'push-1',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'pushup',
          date: DateTime(now.year, now.month, now.day, 18),
          sets: _sets(weight: 20, repetitions: 10, count: 2),
        ),
      ]);

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: ProgressPage()),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('progress_topic_muscle_frequency')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('progress_topic_muscle_frequency')));
    await tester.pumpAndSettle();

    // Dopiero tu buduje się ciężka karta — razem z opisem i wskazówkami.
    expect(find.text('Najczęściej trenowane partie'), findsOneWidget);
    expect(find.text('Co to jest'), findsOneWidget);
    expect(find.text('Wskazówki'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

WorkoutLog _progressLog({
  required String id,
  required String sessionId,
  required String sessionName,
  required String exerciseId,
  required DateTime date,
  required List<WorkoutSet> sets,
}) {
  final averageReps = (sets.fold<int>(0, (sum, set) => sum + set.repetitions) / sets.length).round();
  final averageWeight = sets.fold<double>(0, (sum, set) => sum + set.weightKg) / sets.length;
  final averageRpe = (sets.fold<int>(0, (sum, set) => sum + set.rpe) / sets.length).round();
  return WorkoutLog(
    id: id,
    exerciseId: exerciseId,
    date: date,
    sets: sets.length,
    reps: averageReps,
    weightKg: averageWeight,
    durationSec: 900,
    rpe: averageRpe,
    calories: 80,
    note: '',
    aiConfidence: 0,
    workoutSets: sets,
    sessionId: sessionId,
    sessionName: sessionName,
    sessionStartedAt: sessionId.isEmpty ? null : date.subtract(const Duration(minutes: 30)),
    sessionEndedAt: sessionId.isEmpty ? null : date,
  );
}

List<WorkoutSet> _sets({
  required double weight,
  required int repetitions,
  required int count,
}) {
  return List.generate(
    count,
    (index) => WorkoutSet(
      id: 'set-${weight.toStringAsFixed(1)}-$repetitions-$index',
      order: index + 1,
      repetitions: repetitions,
      weightKg: weight,
      durationSec: 0,
      rpe: 8,
      isCompleted: true,
    ),
  );
}
