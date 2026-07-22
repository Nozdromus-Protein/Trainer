import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/data/trainer_local_repository.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bramka rozgrzewki — śledzenie ukończenia programów rozgrzewkowych.
// Ciężki dzień programu wymaga świeżo ukończonej rozgrzewki partii
// (okno kWarmupFreshness); przerwana rozgrzewka się nie liczy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ukończona rozgrzewka jest świeża przez kWarmupFreshness i trwała',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    final meta = kWarmupWorkoutCatalog.first;
    final plan = buildWarmupWorkout(meta, resolveExercise: ExerciseRepo.byId)
        .copyWith(isActive: true);
    await store.addWorkoutPlan(plan);
    expect(store.hasFreshWarmup(meta.id), isFalse);

    final started = await store.startActiveWorkout(
        plan: plan, day: plan.days.single, dayIndex: 0);
    expect(started, isTrue);
    await store.saveActiveWorkoutSet(
        weightKg: 0, repetitions: 0, rpe: 6, durationSec: 30);
    final summary = await store.finishActiveWorkout();
    expect(summary, isNotNull);

    expect(store.hasFreshWarmup(meta.id), isTrue);
    // Rozgrzewka innej partii nie jest przez to zaliczona.
    expect(store.hasFreshWarmup(kWarmupWorkoutCatalog.last.id), isFalse);
    // Po oknie świeżości wpis wygasa — ciało stygnie.
    final afterWindow =
        DateTime.now().add(kWarmupFreshness + const Duration(minutes: 1));
    expect(store.hasFreshWarmup(meta.id, now: afterWindow), isFalse);

    // Persystencja: nowa instancja sklepu widzi ukończenie.
    final reloaded = AppStore();
    await reloaded.load();
    expect(reloaded.hasFreshWarmup(meta.id), isTrue);
  });

  test('rozgrzewka zakończona jako częściowa nie liczy się do bramki',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    final meta = kWarmupWorkoutCatalog.first;
    final plan = buildWarmupWorkout(meta, resolveExercise: ExerciseRepo.byId)
        .copyWith(isActive: true);
    await store.addWorkoutPlan(plan);
    await store.startActiveWorkout(
        plan: plan, day: plan.days.single, dayIndex: 0);
    await store.saveActiveWorkoutSet(
        weightKg: 0, repetitions: 0, rpe: 6, durationSec: 30);
    final summary = await store.finishActiveWorkoutAsPartial();
    expect(summary, isNotNull);
    expect(store.hasFreshWarmup(meta.id), isFalse);
  });

  test('zwykły trening (nie-rozgrzewka) nie odnotowuje ukończenia rozgrzewki',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    const plan = WorkoutPlan(
      id: 'prog',
      name: 'Program testowy',
      note: '',
      goal: 'Sylwetka',
      isActive: true,
      days: [
        WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
          PlanItem(
              exerciseId: 'pushup',
              sets: 1,
              reps: 10,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );
    await store.addWorkoutPlan(plan);
    await store.startActiveWorkout(
        plan: plan, day: plan.days.single, dayIndex: 0);
    await store.saveActiveWorkoutSet(weightKg: 20, repetitions: 10, rpe: 7);
    final summary = await store.finishActiveWorkout();
    expect(summary, isNotNull);
    expect(store.warmupCompletions, isEmpty);
  });

  test('migracja planów wykonuje się raz (flaga plans_warmup_migration_v1)',
      () async {
    // Plan barków „sprzed bramki": kind unknown + ogólna rozgrzewka inline
    // (wymachy nóg!) w dniu ciężkim.
    const legacy = WorkoutPlan(
      id: 'program_shoulders_Średniozaawansowany',
      name: 'Barki — 30 dni',
      note: '',
      goal: 'Masa',
      isActive: true,
      completedDays: {0},
      days: [
        WorkoutDay(weekday: 1, title: 'Dzień 1 · Siła A', items: [
          PlanItem(
              exerciseId: 'leg_swings',
              sets: 1,
              reps: 0,
              durationSec: 30,
              note: 'Rozgrzewka'),
          PlanItem(
              exerciseId: 'db_shoulder_press',
              sets: 3,
              reps: 10,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );
    SharedPreferences.setMockInitialValues({
      TrainerLocalRepository.plansKey: jsonEncode([legacy.toJson()]),
    });

    final store = AppStore();
    await store.load();
    final migrated = store.plans.firstWhere((p) => p.id == legacy.id);
    expect(migrated.days.first.kind, WorkoutDayKind.strength);
    expect(migrated.days.first.items.map((i) => i.exerciseId),
        ['db_shoulder_press']);
    expect(migrated.completedDays, {0}, reason: 'postęp nietknięty');

    // Przywrócenie starego kształtu NIE uruchamia migracji ponownie — flaga
    // w prefs oznacza wykonaną migrację.
    await store.updateWorkoutPlan(legacy);
    final second = AppStore();
    await second.load();
    final untouched = second.plans.firstWhere((p) => p.id == legacy.id);
    expect(untouched.days.first.kind, WorkoutDayKind.unknown);
    expect(untouched.days.first.items.first.exerciseId, 'leg_swings');
  });
}
