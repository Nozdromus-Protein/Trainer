import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _playerStore(List<PlanItem> items) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  final plan = WorkoutPlan(
    id: 'p',
    name: 'Program testowy',
    note: '',
    goal: 'Sylwetka',
    days: [WorkoutDay(weekday: 1, title: 'Dzień', items: items)],
  );
  await store.startActiveWorkout(plan: plan, day: plan.days.first);
  return store;
}

Widget _wrap(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(store: store, child: const ActiveExercisePlayerPage()),
    );

PlanItem _item(String id, {int sets = 3, int reps = 12}) =>
    PlanItem(exerciseId: id, sets: sets, reps: reps, durationSec: 0, note: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timed exercise shows countdown and pause/resume', (tester) async {
    // „plank" ma defaultDurationSec = 45 → ćwiczenie czasowe.
    final store = await _playerStore([_item('plank', sets: 2)]);
    await tester.binding.setSurfaceSize(const Size(400, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pump();

    expect(find.text('Ćwiczenie 1/1'), findsOneWidget);
    expect(find.text('00:45'), findsOneWidget);
    expect(find.text('Przygotuj się'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:43'), findsOneWidget);
    expect(find.text('Pauza'), findsOneWidget);

    await tester.tap(find.text('Pauza'));
    await tester.pump();
    expect(find.text('Wznów'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reps exercise shows set counter and strength action', (tester) async {
    final store = await _playerStore([_item('pushup', sets: 3, reps: 12)]);
    await tester.binding.setSurfaceSize(const Size(400, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pump();

    expect(find.text('Ćwiczenie 1/1'), findsOneWidget);
    expect(find.text('Seria 1/3'), findsOneWidget);
    expect(find.text('Zapisz serię'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exercise without media shows fallback placeholder', (tester) async {
    // „lunge" nie ma multimediów.
    final store = await _playerStore([_item('lunge')]);
    await tester.binding.setSurfaceSize(const Size(400, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pump();

    expect(find.byType(ExercisePlaceholder), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip and previous navigate between exercises', (tester) async {
    final store = await _playerStore([_item('pushup'), _item('squat')]);
    await tester.binding.setSurfaceSize(const Size(400, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pump();
    expect(find.text('Ćwiczenie 1/2'), findsOneWidget);

    await tester.tap(find.text('Pomiń'));
    await tester.pump();
    expect(find.text('Ćwiczenie 2/2'), findsOneWidget);

    await tester.tap(find.text('Poprzedni'));
    await tester.pump();
    expect(find.text('Ćwiczenie 1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
