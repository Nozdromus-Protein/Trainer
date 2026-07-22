import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plan CRUD, day copying and item parameters persist locally', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    const plan = WorkoutPlan(
      id: 'manual-plan',
      name: 'Plan siłowy',
      goal: 'Siła',
      note: 'Plan utworzony ręcznie.',
      isActive: true,
      days: [
        WorkoutDay(
          weekday: DateTime.monday,
          title: 'Góra',
          items: [],
        ),
      ],
    );
    await store.addWorkoutPlan(plan);
    await store.upsertPlanItem(
      planId: plan.id,
      weekday: DateTime.monday,
      item: const PlanItem(
        exerciseId: 'pushup',
        sets: 4,
        reps: 8,
        durationSec: 0,
        note: 'Kontrola ruchu',
        suggestedWeightKg: 15.5,
        restSeconds: 120,
      ),
    );
    expect(
      await store.copyWorkoutDay(
        planId: plan.id,
        sourceWeekday: DateTime.monday,
        targetWeekday: DateTime.wednesday,
      ),
      isTrue,
    );
    final duplicated = await store.duplicateWorkoutPlan(plan.id);

    expect(store.activeWorkoutPlan?.id, plan.id);
    expect(duplicated, isNotNull);
    expect(duplicated!.isActive, isFalse);
    expect(duplicated.days, hasLength(2));

    final restored = AppStore();
    await restored.load();
    final saved = restored.plans.singleWhere((entry) => entry.id == plan.id);
    final copiedItem = saved.days
        .singleWhere((day) => day.weekday == DateTime.wednesday)
        .items
        .single;

    expect(saved.goal, 'Siła');
    expect(saved.isActive, isTrue);
    expect(copiedItem.suggestedWeightKg, 15.5);
    expect(copiedItem.restSeconds, 120);
    expect(restored.plans.any((entry) => entry.id == duplicated.id), isTrue);

    for (final savedPlan in List<WorkoutPlan>.from(restored.plans)) {
      await restored.deleteWorkoutPlan(savedPlan.id);
    }
    final afterDeletion = AppStore();
    await afterDeletion.load();
    expect(afterDeletion.plans, isEmpty);
  });

  testWidgets(
      'training tab shows 30-day programs and cardio tiles without overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: PlanPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nowa zakładka „Trening": programy 30-dniowe zamiast kafelka planu lokalnego.
    expect(find.text('Trening'), findsOneWidget);
    expect(find.text('Programy 30-dniowe'), findsOneWidget);
    expect(find.text('Brzuch i core'), findsOneWidget);
    // Usunięte elementy starego układu.
    expect(find.text('Dodaj plan'), findsNothing);
    expect(find.text('Narzędzia treningowe'), findsNothing);
    expect(tester.takeException(), isNull);

    // Sekcja cardio jest niżej — przewiń do kafelka.
    await tester.scrollUntilVisible(
      find.text('Cardio dla początkujących'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cardio dla początkujących'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout program page renders progress and days without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    const program = WorkoutPlan(
      id: 'prog-test',
      name: 'Pogromca mięśni brzucha',
      note: 'Program testowy z dniami i odpoczynkiem.',
      goal: 'Sylwetka',
      isActive: true,
      level: 'Zaawansowany',
      completedDays: {0},
      days: [
        WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
          PlanItem(exerciseId: 'pushup', sets: 3, reps: 12, durationSec: 0, note: ''),
        ]),
        WorkoutDay(weekday: 2, title: 'Dzień 2', items: [
          PlanItem(exerciseId: 'squat', sets: 3, reps: 10, durationSec: 0, note: ''),
        ]),
        WorkoutDay(weekday: 3, title: 'Dzień odpoczynku', items: []),
      ],
    );
    await store.addWorkoutPlan(program);

    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final isDark in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), isDark),
          home: AppScope(
            store: store,
            child: const WorkoutProgramPage(planId: 'prog-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DZISIAJ'), findsOneWidget);
      expect(find.text('Pogromca mięśni brzucha'), findsOneWidget);
      expect(find.textContaining('dni ukończono'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
