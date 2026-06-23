import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testPlan = WorkoutPlan(
  id: 'active-plan',
  name: 'Plan aktywny',
  goal: 'Siła',
  note: '',
  isActive: true,
  days: [
    WorkoutDay(
      weekday: DateTime.monday,
      title: 'Góra',
      items: [
        PlanItem(
          exerciseId: 'pushup',
          sets: 2,
          reps: 10,
          durationSec: 0,
          note: '',
          suggestedWeightKg: 5,
          restSeconds: 90,
        ),
        PlanItem(
          exerciseId: 'squat',
          sets: 2,
          reps: 8,
          durationSec: 0,
          note: '',
          suggestedWeightKg: 20,
          restSeconds: 120,
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active workout progress and completed session persist locally',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final started = await store.startActiveWorkout(
      plan: testPlan,
      day: testPlan.days.single,
    );
    expect(started, isTrue);
    expect(
      await store.saveActiveWorkoutSet(
        weightKg: 10,
        repetitions: 12,
        rpe: 8,
      ),
      isTrue,
    );

    final restoredDraft = AppStore();
    await restoredDraft.load();
    expect(restoredDraft.activeWorkoutSession?.completedSetCount, 1);
    expect(restoredDraft.activeWorkoutSession?.volume, 120);

    final summary = await restoredDraft.finishActiveWorkout();
    expect(summary, isNotNull);
    expect(summary!.exerciseCount, 1);
    expect(summary.setCount, 1);
    expect(summary.volume, 120);
    expect(summary.averageRpe, 8);
    expect(restoredDraft.activeWorkoutSession, isNull);
    expect(restoredDraft.logs, hasLength(1));
    expect(restoredDraft.logs.single.sessionId, summary.sessionId);
    expect(restoredDraft.logs.single.workoutSets.single.repetitions, 12);

    final restoredHistory = AppStore();
    await restoredHistory.load();
    expect(restoredHistory.activeWorkoutSession, isNull);
    expect(restoredHistory.logs.single.sessionName, 'Plan aktywny · Góra');
  });

  test('rest timer, notes and exercise replacement preserve completed sets',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.startActiveWorkout(
      plan: testPlan,
      day: testPlan.days.single,
    );
    await store.saveActiveWorkoutSet(
      weightKg: 10,
      repetitions: 12,
      rpe: 8,
    );

    expect(store.activeWorkoutSession?.restTimerTotalSeconds, 120);
    expect(store.activeWorkoutSession?.hasActiveRestTimer, isTrue);
    await store.pauseActiveRestTimer();
    final pausedSeconds = store.activeWorkoutSession!.restTimerRemainingSeconds;
    expect(store.activeWorkoutSession?.isRestTimerPaused, isTrue);
    expect(pausedSeconds, inInclusiveRange(118, 120));

    await store.adjustActiveRestTimer(30);
    expect(
      store.activeWorkoutSession?.restTimerRemainingSeconds,
      pausedSeconds + 30,
    );
    await store.updateActiveExerciseNote('Pilnuj łopatek');
    await store.updateActiveSessionNote('Dobra energia');
    await store.replaceActiveWorkoutExercise(
      ExerciseRepo.byId('squat'),
    );

    expect(
      store.activeWorkoutSession?.currentExercise?.exerciseId,
      'squat',
    );
    expect(
      store.activeWorkoutSession?.currentExercise?.completedSets,
      hasLength(1),
    );
    expect(
      store.activeWorkoutSession?.currentExercise?.completedSets.single.volume,
      120,
    );
    expect(
      store.activeWorkoutSession?.currentExercise?.note,
      'Pilnuj łopatek',
    );

    final restored = AppStore();
    await restored.load();
    expect(restored.activeWorkoutSession?.note, 'Dobra energia');
    expect(restored.activeWorkoutSession?.isRestTimerPaused, isTrue);
    expect(
      restored.activeWorkoutSession?.currentExercise?.completedSets,
      hasLength(1),
    );

    await restored.resumeActiveRestTimer();
    expect(restored.activeWorkoutSession?.isRestTimerPaused, isFalse);
    await restored.skipActiveRestTimer();
    expect(restored.activeWorkoutSession?.hasActiveRestTimer, isFalse);

    final summary = await restored.finishActiveWorkout();
    expect(summary, isNotNull);
    expect(restored.logs.single.exerciseId, 'squat');
    expect(restored.logs.single.note, 'Pilnuj łopatek');
    expect(restored.logs.single.sessionNote, 'Dobra energia');
  });

  test('rest suggestions distinguish isolated, compound and strength work', () {
    final isolated = workoutRestRecommendation(
      ExerciseRepo.byId('bicep_curl'),
      const ActiveWorkoutExercise(
        exerciseId: 'bicep_curl',
        plannedSets: 3,
        plannedReps: 12,
        suggestedWeightKg: 0,
        restSeconds: 90,
        note: '',
      ),
    );
    final compound = workoutRestRecommendation(
      ExerciseRepo.byId('pushup'),
      const ActiveWorkoutExercise(
        exerciseId: 'pushup',
        plannedSets: 3,
        plannedReps: 10,
        suggestedWeightKg: 0,
        restSeconds: 90,
        note: '',
      ),
    );
    final strength = workoutRestRecommendation(
      ExerciseRepo.byId('deadlift'),
      const ActiveWorkoutExercise(
        exerciseId: 'deadlift',
        plannedSets: 5,
        plannedReps: 5,
        suggestedWeightKg: 0,
        restSeconds: 90,
        note: '',
      ),
    );

    expect(isolated.seconds, 60);
    expect(compound.seconds, 120);
    expect(strength.seconds, 180);
  });

  testWidgets('active workout and summary do not overflow on a narrow screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.startActiveWorkout(
      plan: testPlan,
      day: testPlan.days.single,
    );
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const ActiveWorkoutPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Aktywny trening'), findsOneWidget);
    expect(find.text('Zapisz serię'), findsOneWidget);
    expect(
        find.text('Następne ćwiczenie', skipOffstage: false), findsOneWidget);
    expect(find.text('Pomiń ćwiczenie', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);

    await store.saveActiveWorkoutSet(
      weightKg: 10,
      repetitions: 12,
      rpe: 7,
    );
    await tester.pump();
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pump();

    expect(find.text('Wykonane serie'), findsOneWidget);
    expect(find.text('10 kg × 12 powt.'), findsOneWidget);
    expect(find.text('Przerwa między seriami'), findsOneWidget);
    expect(find.text('Pauza'), findsOneWidget);
    expect(find.text('−30 s'), findsOneWidget);
    expect(find.text('+30 s'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Zakończ trening'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Zakończ trening'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final savedSummary = await store.finishActiveWorkout();
    expect(savedSummary, isNotNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: HistoryPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Plan aktywny · Góra'), findsOneWidget);
    expect(find.text('1 ćwiczeń'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: WorkoutSummaryPage(
          summary: CompletedWorkoutSummary(
            sessionId: 'summary-1',
            name: 'Plan aktywny · Góra',
            startedAt: DateTime(2026, 6, 23, 18),
            endedAt: DateTime(2026, 6, 23, 18, 45),
            exerciseCount: 2,
            setCount: 4,
            volume: 1200,
            averageRpe: 8,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Trening zakończony'), findsOneWidget);
    expect(find.text('45:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
