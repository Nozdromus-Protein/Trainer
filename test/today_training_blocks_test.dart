import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sklep z dniem „nogi + barki" na dziś i obydwoma programami wystartowanymi.
Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.setWeekdayPlan(
    DateTime.now().weekday,
    const TrainingDayPlan(
      primary: TrainingFocusArea.legs,
      secondary: TrainingFocusArea.shoulders,
    ),
  );
  Exercise resolve(String id) => ExerciseRepo.byId(id, store.customExercises);
  await store.addWorkoutPlan(
    buildWorkoutProgram('program_legs', resolveExercise: resolve)
        .copyWith(isActive: true),
  );
  await store.addWorkoutPlan(
    buildWorkoutProgram('program_shoulders', resolveExercise: resolve),
  );
  return store;
}

Future<void> _logPlan(AppStore store, String idPrefix) async {
  final plan = store.plans.firstWhere((p) => p.id.startsWith(idPrefix));
  final now = DateTime.now();
  await store.addLog(WorkoutLog(
    id: 'log_$idPrefix',
    exerciseId: plan.days.first.items.first.exerciseId,
    date: DateTime(now.year, now.month, now.day),
    sets: 3,
    reps: 8,
    weightKg: 30,
    durationSec: 900,
    rpe: 7,
    calories: 100,
    note: '',
    aiConfidence: 0,
    sessionId: 'sess_$idPrefix',
    sessionName: plan.name,
    performedAt: now,
    planId: plan.id,
    dayIndex: 0,
  ));
}

Widget _wrap(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(store: store, child: const Scaffold(body: PlanPage())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('karta pokazuje OBA zestawy dnia w kolejności wykonania',
      (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today_blocks_section')), findsOneWidget);
    expect(find.byKey(const Key('today_block_1')), findsOneWidget);
    expect(find.byKey(const Key('today_block_2')), findsOneWidget);
    expect(find.textContaining('PIERWSZORZĘDNY'), findsOneWidget);
    expect(find.textContaining('DRUGORZĘDNY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('po obu zestawach ekran „Dzisiejszy trening" jest zamknięty',
      (tester) async {
    final store = await _store();
    await _logPlan(store, 'program_legs');
    await _logPlan(store, 'program_shoulders');

    expect(store.isTodayTrainingClosed(), isTrue);
    expect(store.nextTrainingBlockToday(), isNull);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Zamknięty, ale NIE usunięty — podsumowanie obu programów zostaje.
    expect(find.byKey(const Key('today_training_closed')), findsOneWidget);
    expect(find.text('DZISIEJSZY TRENING'), findsNothing);
    expect(find.byKey(const Key('today_blocks_section')), findsOneWidget);
    expect(find.byKey(const Key('today_block_1')), findsOneWidget);
    expect(find.byKey(const Key('today_block_2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('dzień wolny nie tworzy żadnego bloku', () async {
    final store = await _store();
    await store.setWeekdayPlan(DateTime.now().weekday, TrainingDayPlan.rest);
    expect(store.todayTrainingBlocks(), isEmpty);
    expect(store.isTodayTrainingClosed(), isFalse,
        reason: 'brak treningu w rozkładzie to nie jest „zamknięty dzień"');
  });
}
