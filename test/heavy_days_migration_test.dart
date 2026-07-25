import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('każdy zestaw partii ma SAME dni ciężkie — bez odpoczynku i mobilności',
      () {
    Exercise resolve(String id) => ExerciseRepo.byId(id, const []);
    for (final meta in kWorkoutProgramCatalog) {
      for (final level in const [
        'Początkujący',
        'Średniozaawansowany',
        'Zaawansowany'
      ]) {
        final plan = buildWorkoutProgram(meta.id,
            resolveExercise: resolve, level: level);
        expect(plan.days, hasLength(30));
        for (final day in plan.days) {
          expect(day.kind, WorkoutDayKind.strength,
              reason: '${meta.id} ($level) — „${day.title}" nie jest ciężki');
          expect(plan.isRestDay(day), isFalse,
              reason: '${meta.id} ($level) — „${day.title}" wypada jako '
                  'dzień odpoczynku');
          expect(day.items, isNotEmpty);
        }
        expect(AppStore.planHasLightDays(plan), isFalse);
      }
    }
  });

  test('zapisany program ze starymi dniami lekkimi jest przebudowany, '
      'a postęp zostaje', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    // Zestaw „sprzed zmiany rytmu": dzień odpoczynkowy i mobilnościowy.
    const legacy = WorkoutPlan(
      id: 'program_legs_Średniozaawansowany',
      name: 'Nogi',
      note: 'stary',
      goal: 'Masa',
      isActive: true,
      level: 'Średniozaawansowany',
      completedDays: {0, 1},
      intensitySteps: 2,
      days: [
        WorkoutDay(
            weekday: 1,
            title: 'Dzień 1 · Siła A — ciężka',
            kind: WorkoutDayKind.strength,
            items: [
              PlanItem(
                  exerciseId: 'goblet_squat',
                  sets: 3,
                  reps: 8,
                  durationSec: 0,
                  note: '')
            ]),
        WorkoutDay(
            weekday: 2,
            title: 'Dzień 2 · Odpoczynek / aktywna regeneracja',
            kind: WorkoutDayKind.rest,
            items: [
              PlanItem(
                  exerciseId: 'cat_cow',
                  sets: 1,
                  reps: 0,
                  durationSec: 40,
                  note: 'Rozciąganie')
            ]),
        WorkoutDay(
            weekday: 3,
            title: 'Dzień 3 · Mobilność i rozciąganie',
            kind: WorkoutDayKind.mobility,
            items: [
              PlanItem(
                  exerciseId: 'child_pose',
                  sets: 1,
                  reps: 0,
                  durationSec: 40,
                  note: 'Rozciąganie')
            ]),
      ],
    );
    await store.addWorkoutPlan(legacy);
    expect(AppStore.planHasLightDays(store.plans.first), isTrue);

    final changed = store.rebuildLightCatalogPlanDays();
    expect(changed, isTrue);

    final rebuilt = store.plans.firstWhere((plan) => plan.id == legacy.id);
    expect(AppStore.planHasLightDays(rebuilt), isFalse,
        reason: 'po migracji zostają same dni ciężkie');
    expect(rebuilt.days, hasLength(30));
    // Tożsamość i POSTĘP nietknięte.
    expect(rebuilt.id, legacy.id);
    expect(rebuilt.completedDays, legacy.completedDays);
    expect(rebuilt.isActive, isTrue);
    expect(rebuilt.intensitySteps, 2);
  });

  test('program już zgodny z rytmem nie jest ruszany', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.addWorkoutPlan(buildWorkoutProgram(
      'program_chest',
      resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
    ).copyWith(isActive: true));

    expect(store.rebuildLightCatalogPlanDays(), isFalse);
  });
}
