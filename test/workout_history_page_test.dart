import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('workout history lists completed sessions, filters by name and stays overflow-safe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.logs
      ..clear()
      ..addAll([
        _sessionLog(
          id: 'push-log',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'pushup',
          date: DateTime(2026, 6, 22, 18),
        ),
        _sessionLog(
          id: 'pull-log',
          sessionId: 'pull-session',
          sessionName: 'Plan Pull · Plecy',
          exerciseId: 'deadlift',
          date: DateTime(2026, 6, 21, 18),
        ),
      ]);
    await store.saveLogs();

    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHistory(tester, store);

    expect(find.text('Historia treningów'), findsOneWidget);
    expect(find.text('Plan Push · Góra'), findsOneWidget);
    expect(find.text('Plan Pull · Plecy'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('history_plan_filter')), 'Pull');
    await tester.pumpAndSettle();

    expect(find.text('Plan Push · Góra'), findsNothing);
    expect(find.text('Plan Pull · Plecy'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout history details edit a set and persist it locally', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.logs
      ..clear()
      ..add(
        _sessionLog(
          id: 'push-log',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'pushup',
          date: DateTime(2026, 6, 22, 18),
          note: 'Pilnuj łopatek',
          sets: const [
            WorkoutSet(
              id: 'set-1',
              order: 1,
              repetitions: 10,
              weightKg: 40,
              durationSec: 0,
              rpe: 8,
              isCompleted: true,
            ),
            WorkoutSet(
              id: 'set-2',
              order: 2,
              repetitions: 10,
              weightKg: 40,
              durationSec: 0,
              rpe: 8,
              isCompleted: true,
            ),
          ],
        ),
      );
    await store.saveLogs();

    await _pumpHistory(tester, store);
    await tester.tap(find.text('Plan Push · Góra'));
    await tester.pumpAndSettle();

    expect(find.text('Szczegóły treningu'), findsOneWidget);
    expect(find.text('Seria 1'), findsOneWidget);
    expect(find.text('Pilnuj łopatek'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_set_push-log_set-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit_set_weight')), '42.5');
    await tester.enterText(find.byKey(const Key('edit_set_repetitions')), '11');
    await tester.enterText(find.byKey(const Key('edit_set_note')), 'Poprawiona seria');
    await tester.tap(find.byKey(const Key('save_edited_set')));
    await tester.pumpAndSettle();

    expect(find.text('42.5 kg'), findsOneWidget);
    expect(find.text('11 powt.'), findsOneWidget);
    expect(find.text('Poprawiona seria'), findsOneWidget);

    final restored = AppStore();
    await restored.load();
    final updatedLog = restored.logs.single;
    expect(updatedLog.workoutSets.first.weightKg, 42.5);
    expect(updatedLog.workoutSets.first.repetitions, 11);
    expect(updatedLog.workoutSets.first.note, 'Poprawiona seria');
    expect(updatedLog.sets, 2);
    expect(updatedLog.reps, 11);
    expect(updatedLog.volume, 867.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout history deletes a session only after confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.logs
      ..clear()
      ..add(
        _sessionLog(
          id: 'push-log',
          sessionId: 'push-session',
          sessionName: 'Plan Push · Góra',
          exerciseId: 'pushup',
          date: DateTime(2026, 6, 22, 18),
        ),
      );
    await store.saveLogs();

    await _pumpHistory(tester, store);
    await tester.tap(find.text('Plan Push · Góra'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Usuń trening'));
    await tester.pumpAndSettle();

    expect(find.text('Usunąć trening?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pumpAndSettle();

    expect(store.logs, isEmpty);
    final restored = AppStore();
    await restored.load();
    expect(restored.logs, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHistory(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(
    AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: const Scaffold(body: HistoryPage()),
      ),
    ),
  );
  await tester.pump();
}

WorkoutLog _sessionLog({
  required String id,
  required String sessionId,
  required String sessionName,
  required String exerciseId,
  required DateTime date,
  String note = '',
  List<WorkoutSet> sets = const [
    WorkoutSet(
      id: 'set-1',
      order: 1,
      repetitions: 10,
      weightKg: 40,
      durationSec: 0,
      rpe: 8,
      isCompleted: true,
    ),
  ],
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
    durationSec: 1800,
    rpe: averageRpe,
    calories: 120,
    note: note,
    aiConfidence: 0,
    workoutSets: sets,
    sessionId: sessionId,
    sessionName: sessionName,
    sessionStartedAt: date.subtract(const Duration(minutes: 30)),
    sessionEndedAt: date,
    sessionNote: 'Dobra sesja',
  );
}
