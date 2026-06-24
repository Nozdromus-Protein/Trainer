import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exercise progress data detects stagnation and estimates 1RM', () {
    final logs = [
      _exerciseLog(date: DateTime(2026, 6, 1), weight: 100, reps: 5),
      _exerciseLog(date: DateTime(2026, 6, 8), weight: 100, reps: 5),
      _exerciseLog(date: DateTime(2026, 6, 15), weight: 100, reps: 5),
    ];

    final progress = buildExerciseProgressData(exerciseId: 'squat', logs: logs);

    expect(progress.hasHistory, isTrue);
    expect(progress.points, hasLength(3));
    expect(progress.lastUsedWeight, 100);
    expect(progress.bestWeight, 100);
    expect(progress.bestSet?.repetitions, 5);
    expect(progress.totalVolume, 1500);
    expect(progress.lastPerformedAt, DateTime(2026, 6, 15));
    expect(progress.estimatedOneRepMax, closeTo(116.7, 0.1));
    expect(progress.isStagnating, isTrue);
    expect(progress.suggestionTitle, 'Zwiększ powtórzenia');
  });

  testWidgets('exercise details show progress history charts and 1RM calculator without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.logs
      ..clear()
      ..addAll([
        _exerciseLog(date: DateTime(2026, 6, 1), weight: 100, reps: 5),
        _exerciseLog(date: DateTime(2026, 6, 8), weight: 100, reps: 5),
        _exerciseLog(date: DateTime(2026, 6, 15), weight: 100, reps: 5),
      ]);
    await store.saveLogs();

    final restored = AppStore();
    await restored.load();
    await tester.binding.setSurfaceSize(const Size(320, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: restored,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const ExerciseDetailsPage(exerciseId: 'squat'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final detailsScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Historia progresu'), 500, scrollable: detailsScroll);
    expect(find.text('Historia progresu'), findsOneWidget);
    expect(find.text('Ostatni ciężar'), findsOneWidget);
    expect(find.text('Najlepszy ciężar'), findsOneWidget);
    expect(find.text('Najlepsza seria'), findsOneWidget);
    expect(find.text('Możliwa stagnacja'), findsOneWidget);
    expect(find.text('Sugestia: Zwiększ powtórzenia'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Ciężar w czasie'), 500, scrollable: detailsScroll);
    expect(find.text('Ciężar w czasie'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Objętość w czasie'), 500, scrollable: detailsScroll);
    expect(find.text('Objętość w czasie'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kalkulator 1RM'), 500, scrollable: detailsScroll);
    expect(find.text('Kalkulator 1RM'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('one_rm_weight')), '100');
    await tester.enterText(find.byKey(const Key('one_rm_reps')), '5');
    await tester.pump();

    expect(find.text('116.7 kg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

WorkoutLog _exerciseLog({
  required DateTime date,
  required double weight,
  required int reps,
}) {
  return WorkoutLog(
    id: 'squat_${date.microsecondsSinceEpoch}',
    exerciseId: 'squat',
    date: date,
    sets: 1,
    reps: reps,
    weightKg: weight,
    durationSec: 600,
    rpe: 8,
    calories: 80,
    note: '',
    aiConfidence: 0,
    workoutSets: [
      WorkoutSet(
        id: 'set_${date.microsecondsSinceEpoch}',
        order: 1,
        repetitions: reps,
        weightKg: weight,
        durationSec: 0,
        rpe: 8,
        isCompleted: true,
      ),
    ],
    sessionId: 'session_${date.microsecondsSinceEpoch}',
    sessionName: 'Plan Siła · Nogi',
    sessionStartedAt: date.subtract(const Duration(minutes: 40)),
    sessionEndedAt: date,
  );
}
