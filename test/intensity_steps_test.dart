import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/deload_cycle.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reps = PlanItem(
    exerciseId: 'squat',
    sets: 3,
    reps: 10,
    durationSec: 0,
    note: 'Seria główna',
    suggestedWeightKg: 60);

const _timed = PlanItem(
    exerciseId: 'plank', sets: 3, reps: 0, durationSec: 40, note: 'Core');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kroki intensywności — domena', () {
    test('mnożnik ciężaru rośnie/maleje po ~5% na krok i jest ograniczony', () {
      expect(intensityStepFactor(0), closeTo(1.0, 0.001));
      expect(intensityStepFactor(2), closeTo(1.10, 0.001));
      expect(intensityStepFactor(-2), closeTo(0.90, 0.001));
      // Poza dozwolonym zakresem nic już nie rośnie.
      expect(intensityStepFactor(99),
          closeTo(intensityStepFactor(kMaxCombinedIntensitySteps), 0.001));
      expect(intensityStepFactor(-99),
          closeTo(intensityStepFactor(-kMaxCombinedIntensitySteps), 0.001));
    });

    test('etykiety', () {
      expect(intensityStepLabel(0), 'standard');
      expect(intensityStepLabel(2), '+2');
      expect(intensityStepLabel(-1), '−1');
    });

    test('krok +1: powtórzenia rosną, serie jeszcze nie', () {
      final up = applyIntensityStepToItem(_reps, 1);
      expect(up.reps, 11);
      expect(up.sets, _reps.sets, reason: 'seria dochodzi co drugi krok');
    });

    test('krok +2: powtórzenia i jedna seria więcej', () {
      final up = applyIntensityStepToItem(_reps, 2);
      expect(up.reps, 12);
      expect(up.sets, 4);
    });

    test('zejście o 2 kroki zdejmuje powtórzenia i serię', () {
      final down = applyIntensityStepToItem(_reps, -2);
      expect(down.reps, 8);
      expect(down.sets, 2);
    });

    test('ciężar w pozycji planu zostaje nietknięty (skaluje go coach)', () {
      expect(applyIntensityStepToItem(_reps, 3).suggestedWeightKg,
          _reps.suggestedWeightKg);
    });

    test('pozycja czasowa wydłuża się zamiast dokładać powtórzeń', () {
      final up = applyIntensityStepToItem(_timed, 2);
      expect(up.durationSec, greaterThan(_timed.durationSec));
      expect(up.reps, 0);
    });

    test('krok 0 nie zmienia dnia', () {
      const day = WorkoutDay(weekday: 1, title: 'Dzień', items: [_reps]);
      expect(applyIntensityStep(day, 0).items.single.reps, _reps.reps);
    });
  });

  group('Kroki intensywności — zapis i UI', () {
    test('intensitySteps przeżywa zapis i odczyt planu', () {
      const plan = WorkoutPlan(
          id: 'p', name: 'P', note: '', days: [], intensitySteps: 2);
      expect(WorkoutPlan.fromJson(plan.toJson()).intensitySteps, 2);
      // Wartości spoza zakresu są przycinane.
      final wild = WorkoutPlan.fromJson({
        'id': 'p',
        'name': 'P',
        'note': '',
        'days': <dynamic>[],
        'intensitySteps': 99,
      });
      expect(wild.intensitySteps, kMaxIntensitySteps);
    });

    testWidgets('przyciski +/- zmieniają i zapisują intensywność',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'intensity-plan',
        name: 'Program testowy',
        note: '',
        goal: 'Masa',
        isActive: true,
        level: 'Średniozaawansowany',
        days: [
          WorkoutDay(weekday: 1, title: 'Trening A', items: [_reps]),
        ],
      ));

      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const WorkoutDayDetailsPage(
              planId: 'intensity-plan', dayIndex: 0),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Intensywność dnia: standard'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('intensity_step_up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('intensity_step_up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('intensity_step_up')));
      await tester.pumpAndSettle();

      WorkoutPlan saved() =>
          store.plans.firstWhere((p) => p.id == 'intensity-plan');
      expect(saved().days.first.intensitySteps, 2);
      expect(saved().intensitySteps, 0, reason: 'program zostaje nietknięty');
      expect(find.text('Intensywność dnia: +2'), findsOneWidget);

      // Zejście wraca w drugą stronę.
      await tester.tap(find.byKey(const Key('intensity_step_down')));
      await tester.pumpAndSettle();
      expect(saved().days.first.intensitySteps, 1);
      expect(tester.takeException(), isNull);
    });

    test('korekta dnia sumuje się z korektą programu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'combo-plan',
        name: 'P',
        note: '',
        isActive: true,
        intensitySteps: 1,
        days: [
          WorkoutDay(
              weekday: 1, title: 'A', items: [_reps], intensitySteps: 1),
          WorkoutDay(
              weekday: 2, title: 'B', items: [_reps], intensitySteps: -2),
        ],
      ));
      final plan = store.plans.firstWhere((p) => p.id == 'combo-plan');
      expect(store.effectiveIntensitySteps(plan, plan.days[0]), 2);
      expect(store.effectiveIntensitySteps(plan, plan.days[1]), -1);

      // Dzień MOŻE podbić ponad ustawienie programu — obie gałki się sumują.
      const hot = WorkoutPlan(
          id: 'x',
          name: 'x',
          note: '',
          intensitySteps: kMaxIntensitySteps,
          days: [
            WorkoutDay(
                weekday: 1,
                title: 'A',
                items: [],
                intensitySteps: kMaxIntensitySteps)
          ]);
      expect(store.effectiveIntensitySteps(hot, hot.days.first),
          kMaxCombinedIntensitySteps,
          reason: '+6 programu i +6 dnia daje +12');
    });

    test('intensitySteps dnia przeżywa zapis i odczyt', () {
      const day =
          WorkoutDay(weekday: 1, title: 'A', items: [], intensitySteps: -2);
      expect(WorkoutDay.fromJson(day.toJson()).intensitySteps, -2);
    });
  });
}
