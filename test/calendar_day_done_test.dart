import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kalendarz na „Dzisiaj": karteczka dnia, w którym wykonano OBA zestawy
// (pierwszo- i drugorzędny), gaśnie do połowy i dostaje ptaszka.

Future<void> _log(AppStore store, String exerciseId, DateTime day) =>
    store.addLog(WorkoutLog(
      id: 'log_${exerciseId}_${day.day}',
      exerciseId: exerciseId,
      date: DateTime(day.year, day.month, day.day),
      sets: 4,
      reps: 8,
      weightKg: 50,
      durationSec: 1200,
      rpe: 8,
      calories: 200,
      note: '',
      aiConfidence: 0,
      sessionId: 'sess_${exerciseId}_${day.day}',
      sessionName: 'Trening',
      performedAt: day,
    ));

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.updateTrainingSchedule(store.settings.trainingSchedule
      .copyWith(strategy: TrainingSplitStrategy.twoTrack));
  await store.setWeekdayPlan(
    DateTime.now().weekday,
    const TrainingDayPlan(
      primary: TrainingFocusArea.chestTriceps,
      secondary: TrainingFocusArea.shoulders,
    ),
  );
  return store;
}

Widget _wrap(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(
        store: store,
        child: const Scaffold(body: TrainingWeekCalendarCard()),
      ),
    );

int _todayIndex() => DateTime.now().weekday - 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('po OBU zestawach karteczka dnia dostaje ptaszka i przygasa',
      (tester) async {
    final store = await _store();
    final today = DateTime.now();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final doneKey = Key('calendar_day_done_${_todayIndex()}');

    // Po jednym zestawie dzień NIE jest jeszcze odhaczony.
    await _log(store, 'bench_press', today);
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    expect(find.byKey(doneKey), findsNothing);

    // Drugi zestaw domyka dzień.
    await _log(store, 'shoulder_press', today);
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    expect(find.byKey(doneKey), findsOneWidget);

    // Karteczka przygasa — 50% krycia (dzień wybrany zostaje pełny, więc
    // sprawdzamy, że w ogóle pojawiła się przygaszona karteczka tygodnia).
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((widget) => widget.opacity)
        .toList();
    expect(opacities, contains(0.5));
  });

  testWidgets('dzień bez treningu nie jest odhaczony', (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    for (var index = 0; index < 7; index++) {
      expect(find.byKey(Key('calendar_day_done_$index')), findsNothing);
    }
  });
}
