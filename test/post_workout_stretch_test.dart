import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/deload_cycle.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _item = PlanItem(
    exerciseId: 'bench_press',
    sets: 4,
    reps: 6,
    durationSec: 0,
    note: 'Seria główna');

CompletedWorkoutSummary _summary({
  required int dayIndex,
  DateTime? startedAt,
  double averageRpe = 8,
}) =>
    CompletedWorkoutSummary(
      sessionId: 's1',
      name: 'Klatka piersiowa · Dzień 1',
      startedAt: startedAt ?? DateTime(2026, 7, 21, 18),
      endedAt: (startedAt ?? DateTime(2026, 7, 21, 18))
          .add(const Duration(hours: 1)),
      exerciseCount: 3,
      setCount: 9,
      volume: 2400,
      averageRpe: averageRpe,
      planId: 'program_chest_Średniozaawansowany',
      dayIndex: dayIndex,
    );

/// Plan z jednym dniem CIĘŻKIM (0) i jednym lekkim (1).
Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.addWorkoutPlan(const WorkoutPlan(
    id: 'program_chest_Średniozaawansowany',
    name: 'Klatka piersiowa',
    note: '',
    goal: 'Masa',
    isActive: true,
    days: [
      WorkoutDay(
          weekday: 1,
          title: 'Dzień 1 · Siła A — ciężka',
          items: [_item],
          kind: WorkoutDayKind.strength),
      WorkoutDay(
          weekday: 2,
          title: 'Dzień 2 · Technika',
          items: [_item],
          kind: WorkoutDayKind.technique),
    ],
  ));
  return store;
}

Widget _wrap(AppStore store, CompletedWorkoutSummary summary) => AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: WorkoutSummaryPage(summary: summary),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('po CIĘŻKIM dniu podpowiada zestaw rozciągania partii',
      (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store, _summary(dayIndex: 0)));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('post_workout_stretch'));
    expect(card, findsOneWidget);
    expect(find.text('To był ciężki dzień — rozciągnij się'), findsOneWidget);
    // Proponuje rozciąganie DOKŁADNIE tej partii.
    expect(find.textContaining('Rozciąganie — klatka'), findsOneWidget);
    expect(find.byKey(const Key('post_workout_stretch_start')), findsOneWidget);
  });

  testWidgets('po lekkim dniu nie zawraca głowy', (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store, _summary(dayIndex: 1)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post_workout_stretch')), findsNothing);
  });

  testWidgets('w tygodniu deloadu nie nazywa dnia ciężkim', (tester) async {
    final store = await _store();
    // Deload zaczyna się dziś — trening wypada w jego oknie.
    final today = DateTime.now();
    await store.updateDeloadCycle(
      reanchorDeloadStart(store.deloadCycle, today),
    );
    expect(store.deloadStatusToday.isDeload, isTrue,
        reason: 'test ma sens tylko w oknie deloadu');

    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      store,
      _summary(dayIndex: 0, startedAt: today, averageRpe: 6),
    ));
    await tester.pumpAndSettle();

    // Karta zostaje (rozciąganie po treningu ma sens), ale nie kłamie o wysiłku.
    expect(find.byKey(const Key('post_workout_stretch')), findsOneWidget);
    expect(find.text('To był ciężki dzień — rozciągnij się'), findsNothing);
    expect(find.text('Rozciągnij się po treningu'), findsOneWidget);
    expect(find.textContaining('tydzień odciążenia'), findsOneWidget);
  });

  testWidgets('deload z realnie wysokim wysiłkiem nadal jest ciężkim dniem',
      (tester) async {
    final store = await _store();
    final today = DateTime.now();
    await store.updateDeloadCycle(
      reanchorDeloadStart(store.deloadCycle, today),
    );

    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      store,
      _summary(dayIndex: 0, startedAt: today, averageRpe: 9),
    ));
    await tester.pumpAndSettle();

    expect(find.text('To był ciężki dzień — rozciągnij się'), findsOneWidget);
  });

  testWidgets('trening bez programu też nie pokazuje podpowiedzi',
      (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      store,
      CompletedWorkoutSummary(
        sessionId: 's2',
        name: 'Trening własny',
        startedAt: DateTime(2026, 7, 21, 18),
        endedAt: DateTime(2026, 7, 21, 19),
        exerciseCount: 2,
        setCount: 4,
        volume: 800,
        averageRpe: 6,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post_workout_stretch')), findsNothing);
  });
}
