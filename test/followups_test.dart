import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanItem _item(String id, {String note = ''}) =>
    PlanItem(exerciseId: id, sets: 3, reps: 10, durationSec: 0, note: note);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Równowaga zestawu po edycji', () {
    test('same rozciąganie → ostrzeżenie o braku części głównej', () {
      const day = WorkoutDay(weekday: 1, title: 'Dzień', items: [
        PlanItem(
            exerciseId: 'child_pose',
            sets: 1,
            reps: 0,
            durationSec: 40,
            note: 'Rozciąganie'),
      ]);
      final warnings = planDayBalanceWarnings(day, const []);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('części głównej'));
    });

    test('dzień z notatkami, ale bez serii głównej → ostrzeżenie', () {
      final day = WorkoutDay(weekday: 1, title: 'Dzień', items: [
        _item('squat', note: 'Ćwiczenie pomocnicze'),
      ]);
      expect(planDayBalanceWarnings(day, const []).first,
          contains('serię główną'));
    });

    test('plan własny (puste notatki) nie jest fałszywie oznaczany', () {
      final day = WorkoutDay(weekday: 1, title: 'Dzień', items: [
        _item('squat'),
        _item('pushup'),
      ]);
      expect(planDayBalanceWarnings(day, const []), isEmpty);
    });

    test('zestaw z serią główną jest w porządku', () {
      final day = WorkoutDay(weekday: 1, title: 'Dzień', items: [
        _item('squat', note: 'Seria główna'),
        _item('pushup', note: 'Ćwiczenie pomocnicze'),
      ]);
      expect(planDayBalanceWarnings(day, const []), isEmpty);
    });
  });

  group('Rampa cyklu w rekomendacjach coacha', () {
    SetRecommendation rec(double intensity) => recommendSet(
          exercise: ExerciseRepo.byId('bench_press'),
          plannedSets: 3,
          plannedReps: 8,
          plannedWeightKg: 60,
          plannedDurationSec: 0,
          plannedRestSeconds: 120,
          ctx: CoachContext(
              level: 'Średniozaawansowany',
              goal: 'Masa',
              bodyWeightKg: 90,
              cycleIntensity: intensity),
        );

    test('deload obniża proponowany ciężar, pełna faza go nie rusza', () {
      final full = rec(1.0);
      final deload = rec(0.55);
      expect(full.weightKg, greaterThan(0));
      expect(deload.weightKg, lessThan(full.weightKg));
      expect(deload.reasons.join(' ').toLowerCase(), contains('deload'));
    });

    test('koniec bloku tnie ciężar delikatnie', () {
      final full = rec(1.0);
      final late = rec(0.85);
      expect(late.weightKg, lessThan(full.weightKg));
      expect(late.weightKg, greaterThan(rec(0.55).weightKg));
    });
  });

  group('Niezgodność poziomu programu', () {
    testWidgets('wykrywa i naprawia poziom bez utraty postępu', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateSettings(
          store.settings.copyWith(level: 'Średniozaawansowany'));
      await store.addWorkoutPlan(WorkoutPlan(
        id: 'program_chest_Zaawansowany',
        name: 'Klatka piersiowa — 30 dni',
        note: '',
        goal: 'Masa',
        isActive: true,
        level: 'Zaawansowany',
        completedDays: const {0, 1},
        days: [
          for (var i = 0; i < 30; i++)
            WorkoutDay(
                weekday: (i % 7) + 1,
                title: 'Dzień ${i + 1}',
                items: [_item('pushup', note: 'Seria główna')]),
        ],
      ));

      expect(store.activePlanLevelMismatch, isTrue);

      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: ProgramLevelCard()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_level_mismatch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_level_repair')));
      await tester.pumpAndSettle();

      final plan = store.plans
          .firstWhere((p) => p.id == 'program_chest_Zaawansowany');
      expect(plan.level, 'Średniozaawansowany');
      expect(plan.completedDays, const {0, 1}, reason: 'postęp zachowany');
      expect(store.activePlanLevelMismatch, isFalse);
    });

    testWidgets('bez rozjazdu „Przelicz" nadal jest dostępny', (tester) async {
      // Realny skutek starego błędu: profil I plan mówią zgodnie „Zaawansowany",
      // więc rozjazdu NIE MA — a mimo to trzeba móc wymusić przeliczenie.
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store
          .updateSettings(store.settings.copyWith(level: 'Zaawansowany'));
      await store.addWorkoutPlan(WorkoutPlan(
        id: 'program_legs_Zaawansowany',
        name: 'Nogi — 30 dni',
        note: '',
        goal: 'Masa',
        isActive: true,
        level: 'Zaawansowany',
        days: [
          WorkoutDay(
              weekday: 1, title: 'Dzień 1', items: [_item('squat')]),
        ],
      ));
      expect(store.activePlanLevelMismatch, isFalse);

      await tester.pumpWidget(AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: ProgramLevelCard()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_level_mismatch')), findsNothing);
      expect(find.byKey(const Key('plan_level_ok')), findsOneWidget);
      expect(find.byKey(const Key('plan_level_repair')), findsOneWidget);
      expect(find.textContaining('Poziom programu: Zaawansowany'),
          findsOneWidget);
    });
  });
}
