import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Trening tab shows the Intelligent Planner hero for an active program', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    final today = DateTime.now().weekday;
    final program = WorkoutPlan(
      id: 'program_hero_test',
      name: 'Siła 30 dni',
      note: 'Program testowy.',
      goal: 'Siła',
      isActive: true,
      level: 'Średniozaawansowany',
      days: [
        WorkoutDay(weekday: today, title: 'Klatka + triceps', items: const [
          PlanItem(exerciseId: 'pushup', sets: 3, reps: 10, durationSec: 0, note: ''),
          PlanItem(exerciseId: 'squat', sets: 3, reps: 8, durationSec: 0, note: ''),
        ]),
      ],
    );
    await store.addWorkoutPlan(program);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final isDark in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), isDark),
          home: AppScope(
            store: store,
            child: const Scaffold(body: PlanPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Planer na pierwszym planie: nagłówek dnia + akcja startu.
      expect(find.text('DZISIEJSZY TRENING'), findsOneWidget);
      // Zamiast startu „w ciemno" prowadzimy do dnia z planu.
      expect(find.byKey(const Key('continue_program_tile')), findsOneWidget);
      expect(find.text('Rozpocznij trening'), findsNothing);
      // Program 30-dniowy pozostaje niżej (nie usunięty).
      expect(find.text('Programy 30-dniowe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Czas i sprzęt są zwinięte, rozwijają się na żądanie', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    final today = DateTime.now().weekday;
    await store.addWorkoutPlan(WorkoutPlan(
      id: 'program_adjust_test',
      name: 'Siła 30 dni',
      note: '',
      goal: 'Siła',
      isActive: true,
      level: 'Średniozaawansowany',
      days: [
        WorkoutDay(weekday: today, title: 'Klatka', items: const [
          PlanItem(
              exerciseId: 'pushup', sets: 3, reps: 10, durationSec: 0, note: ''),
        ]),
      ],
    ));

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(store: store, child: const Scaffold(body: PlanPage())),
      ),
    );
    await tester.pumpAndSettle();

    // Zwinięte: widać tylko wiersz „Dopasuj na dziś".
    expect(find.text('Dopasuj na dziś — czas, sprzęt'), findsOneWidget);
    expect(find.text('Ile masz dziś czasu?'), findsNothing);
    expect(find.text('Nie mam dziś sprzętu'), findsNothing);

    // Rozwinięcie pokazuje opcje czasu i sprzętu.
    await tester.ensureVisible(find.byKey(const Key('planner_adjust_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner_adjust_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Ile masz dziś czasu?'), findsOneWidget);
    expect(find.text('Nie mam dziś sprzętu'), findsOneWidget);

    // Zwijanie działa w drugą stronę.
    await tester.ensureVisible(find.byKey(const Key('planner_adjust_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner_adjust_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Ile masz dziś czasu?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pre-workout analysis page renders planned exercises and forecast', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    final today = DateTime.now().weekday;
    final program = WorkoutPlan(
      id: 'program_pre_test',
      name: 'Masa 30 dni',
      note: '',
      goal: 'Masa',
      isActive: true,
      days: [
        WorkoutDay(weekday: today, title: 'Nogi', items: const [
          PlanItem(exerciseId: 'squat', sets: 4, reps: 8, durationSec: 0, note: '', suggestedWeightKg: 40),
        ]),
      ],
    );
    await store.addWorkoutPlan(program);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const PreWorkoutAnalysisPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Analiza przed treningiem'), findsOneWidget);
    expect(find.text('Przewidywane wartości'), findsOneWidget);
    expect(find.textContaining('g białka'), findsNothing,
        reason: 'białko jest częścią bazowego celu, nie korektą treningu');
    // Lista ćwiczeń bywa poniżej pierwszego ekranu (dzień ma teraz partię
    // główną i dodatek), więc doscrollujmy do nagłówka sekcji.
    await tester.scrollUntilVisible(
      find.text('Zaplanowane ćwiczenia'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Zaplanowane ćwiczenia'), findsOneWidget);
    expect(find.text('Rozpocznij trening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
