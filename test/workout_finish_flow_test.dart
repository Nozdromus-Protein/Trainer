import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _program = WorkoutPlan(
  id: 'prog',
  name: 'Program testowy',
  note: '',
  goal: 'Sylwetka',
  isActive: true,
  days: [
    WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
      PlanItem(exerciseId: 'pushup', sets: 1, reps: 10, durationSec: 0, note: ''),
    ]),
    WorkoutDay(weekday: 2, title: 'Dzień 2', items: [
      PlanItem(exerciseId: 'squat', sets: 1, reps: 10, durationSec: 0, note: ''),
    ]),
  ],
);

WorkoutPlan _prog(AppStore store) => store.plans.firstWhere((p) => p.id == 'prog');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finishing a day marks progress, unlocks next, writes history', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.addWorkoutPlan(_program);

    final started = await store.startActiveWorkout(plan: _prog(store), day: _prog(store).days[0], dayIndex: 0);
    expect(started, isTrue);
    expect(store.activeWorkoutSession?.dayIndex, 0);

    await store.saveActiveWorkoutSet(weightKg: 20, repetitions: 10, rpe: 7);
    final summary = await store.finishActiveWorkout();

    expect(summary, isNotNull);
    expect(summary!.planId, 'prog');
    expect(summary.dayIndex, 0);
    expect(summary.dayLabel, 'Dzień 1');
    expect(summary.skippedCount, 0);

    final plan = _prog(store);
    expect(plan.isDayCompleted(0), isTrue);
    expect(plan.completedCount, 1);
    expect(plan.currentDayIndex, 1); // następny dzień odblokowany
    expect(store.activeWorkoutSession, isNull);

    // Wpis trafił do historii treningów.
    expect(store.logs.any((log) => log.sessionId == summary.sessionId), isTrue);

    // Notatka zwrotna (ocena/ból) dopisuje się do sesji.
    await store.appendWorkoutSessionNote(summary.sessionId, 'Ocena treningu: Średni');
    expect(
      store.logs.firstWhere((log) => log.sessionId == summary.sessionId).sessionNote,
      contains('Średni'),
    );

    // Cofnięcie ukończenia dnia zmniejsza postęp.
    await store.setPlanDayCompleted('prog', 0, completed: false);
    expect(_prog(store).isDayCompleted(0), isFalse);
    expect(_prog(store).completedCount, 0);
  });

  test('interrupted workout keeps session; discard clears it without crash', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.addWorkoutPlan(_program);

    await store.startActiveWorkout(plan: _prog(store), day: _prog(store).days[0], dayIndex: 0);
    // Brak zapisanych serii → zakończenie nie tworzy podsumowania, sesja zostaje.
    final summary = await store.finishActiveWorkout();
    expect(summary, isNull);
    expect(store.activeWorkoutSession, isNotNull);
    expect(_prog(store).isDayCompleted(0), isFalse);

    // Przerwanie treningu (odrzucenie) czyści sesję bez błędu.
    await store.discardActiveWorkout();
    expect(store.activeWorkoutSession, isNull);
  });
}
