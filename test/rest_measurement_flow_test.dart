import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pomiar REALNEGO odpoczynku w trakcie treningu: skrócenie przerwy musi zostać
// zapisane przy serii, a nie zgubione. Na tym opiera się i korekta czasu,
// i wychwytywanie RPE, i ostrożna progresja.

const _program = WorkoutPlan(
  id: 'prog_rest',
  name: 'Program testowy',
  note: '',
  goal: 'Sylwetka',
  isActive: true,
  days: [
    WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
      PlanItem(
          exerciseId: 'bench_press',
          sets: 3,
          reps: 10,
          durationSec: 0,
          note: ''),
    ]),
  ],
);

Future<AppStore> _startedStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.addWorkoutPlan(_program);
  final plan = store.plans.firstWhere((p) => p.id == 'prog_rest');
  await store.startActiveWorkout(plan: plan, day: plan.days.first, dayIndex: 0);
  return store;
}

WorkoutSet _lastSet(AppStore store) =>
    store.activeWorkoutSession!.currentExercise!.completedSets.last;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pierwsza seria nie ma czego mierzyć, kolejna ma zapisaną przerwę',
      () async {
    final store = await _startedStore();

    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    expect(_lastSet(store).restBeforeSec, 0,
        reason: 'przed pierwszą serią nie ma odpoczynku do zmierzenia');
    expect(store.activeWorkoutSession!.lastSetCompletedAt, isNotNull);
    // Timer odpoczynku wystartował, a znacznik jego końca jest czysty.
    expect(store.activeWorkoutSession!.restEndedAt, isNull);
    expect(store.activeWorkoutSession!.restTimerTotalSeconds, greaterThan(0));

    // Użytkownik pomija odpoczynek — to PEWNY moment końca przerwy.
    await store.skipActiveRestTimer();
    expect(store.activeWorkoutSession!.restEndedAt, isNotNull);

    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    final second = _lastSet(store);
    expect(second.plannedRestSec, greaterThan(0));
    expect(second.isRestVerified, isTrue);
    expect(second.restWasShortened, isTrue,
        reason: 'pominięta przerwa to przerwa krótsza niż plan');
  });

  test('nowa przerwa kasuje znacznik z poprzedniej serii', () async {
    final store = await _startedStore();
    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    await store.skipActiveRestTimer();
    expect(store.activeWorkoutSession!.restEndedAt, isNotNull);
    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    expect(store.activeWorkoutSession!.restEndedAt, isNull,
        reason: 'kolejna seria zaczyna nowy pomiar, nie dziedziczy starego');
  });

  test('pomiar przeżywa zapis i odczyt sesji', () async {
    final store = await _startedStore();
    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    await store.skipActiveRestTimer();
    final restored =
        ActiveWorkoutSession.fromJson(store.activeWorkoutSession!.toJson());
    expect(restored.lastSetCompletedAt, isNotNull);
    expect(restored.restEndedAt, isNotNull);
  });

  test('seria prowadzona przez trenera dostaje SZACOWANE RPE z sygnałów',
      () async {
    final store = await _startedStore();
    await store.logGuidedSet(outcome: SetOutcome.asPlanned);
    final first = _lastSet(store);
    expect(first.rpeSource, 'estimated');
    expect(first.estimatedRpe, greaterThan(0));

    await store.skipActiveRestTimer();
    await store.logGuidedSet(outcome: SetOutcome.asPlanned);
    final second = _lastSet(store);
    // Druga seria po skróconej przerwie NIE może mieć tego samego wysiłku
    // co pierwsza — to była istota błędu „zawsze RPE 7".
    expect(second.estimatedRpe, greaterThan(first.estimatedRpe));
  });

  test('pomiar bez zdarzenia końca przerwy jest oznaczony jako niepewny',
      () async {
    final store = await _startedStore();
    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    // Brak wywołania skipActiveRestTimer/markRestEnded — timer po prostu leci.
    await store.saveActiveWorkoutSet(weightKg: 40, repetitions: 10, rpe: 0);
    expect(_lastSet(store).isRestVerified, isFalse);
  });
}
