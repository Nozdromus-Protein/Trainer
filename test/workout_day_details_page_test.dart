import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _exercisePool = [
  'squat',
  'goblet_squat',
  'front_squat',
  'lunge',
  'reverse_lunge',
  'pushup',
  'incline_pushup',
  'plank',
  'side_plank',
  'crunch',
  'mountain_climber',
  'burpee',
];

List<PlanItem> _buildItems(int count) => [
      for (var i = 0; i < count; i++)
        PlanItem(
          exerciseId: _exercisePool[i % _exercisePool.length],
          sets: 3,
          reps: 12,
          durationSec: 0,
          note: '',
        ),
    ];

Future<AppStore> _storeWithDay(List<PlanItem> items,
    {String title = 'Trening A'}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  final plan = WorkoutPlan(
    id: 'day-test-plan',
    name: 'Program testowy',
    note: 'Opis',
    goal: 'Sylwetka',
    isActive: true,
    level: 'Zaawansowany',
    days: [WorkoutDay(weekday: 1, title: title, items: items)],
  );
  await store.addWorkoutPlan(plan);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final count in [5, 15, 30]) {
    testWidgets('day details renders $count exercises without overflow',
        (tester) async {
      final store = await _storeWithDay(_buildItems(count));
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: AppScope(
            store: store,
            child: const WorkoutDayDetailsPage(
                planId: 'day-test-plan', dayIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dzień 1'), findsOneWidget);
      expect(find.text('$count ćwiczeń'), findsOneWidget);
      expect(find.text('START'), findsOneWidget);
      // Osobny kafelek „Przewodnik / Instrukcja ćwiczeń" został usunięty —
      // instrukcja otwiera się dotknięciem konkretnego ćwiczenia na liście.
      expect(find.text('Przewodnik'), findsNothing);
      // Sprzęt i partie trenowane są ZWINIĘTE w jeden wiersz szczegółów.
      expect(find.byKey(const Key('day_facts_toggle')), findsOneWidget);
      expect(find.text('Sprzęt potrzebny'), findsNothing);
      expect(find.text('Partie trenowane'), findsNothing);
      // Sugestie progresji żyją pod ikoną przy statusie dnia.
      expect(
          find.byKey(const Key('progression_suggestion_icon')), findsWidgets);
      // Nawigacja stoi w prawdziwym AppBarze nad grafiką nagłówka.
      expect(find.byType(AppBar), findsOneWidget);
      // Przełącznik widoku Lista/Kompakt jest dostępny.
      expect(find.text('Lista'), findsOneWidget);
      expect(find.text('Kompakt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('day details works without multimedia (fallback thumbnails)',
      (tester) async {
    // „lunge"/„crunch" nie mają multimediów — powinien pojawić się fallback bez crasha.
    final store = await _storeWithDay(_buildItems(6));
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), false),
        home: AppScope(
          store: store,
          child:
              const WorkoutDayDetailsPage(planId: 'day-test-plan', dayIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExercisePlaceholder), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rest day shows recovery screen instead of exercises',
      (tester) async {
    final store = await _storeWithDay(const [], title: 'Dzień odpoczynku');
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child:
              const WorkoutDayDetailsPage(planId: 'day-test-plan', dayIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dziś odpoczywasz'), findsOneWidget);
    expect(find.text('Zalicz dzień odpoczynku'), findsOneWidget);
    expect(find.text('Nawodnienie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
