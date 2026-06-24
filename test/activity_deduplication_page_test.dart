import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('activity deduplication page renders diagnostics without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.selectedDate = DateTime(2026, 6, 24);
    await store.upsertActivityEntry(
      TrainerActivityEntry(
        id: 'steps-1',
        date: DateTime(2026, 6, 24, 9),
        source: TrainerActivitySource.steps,
        type: TrainerActivityType.ordinaryStepsWalk,
        estimatedKcal: 180,
        sourceActivityId: 'daily-steps',
        durationMin: 180,
        steps: 9000,
      ),
    );
    await store.upsertActivityEntry(
      TrainerActivityEntry(
        id: 'walk-1',
        date: DateTime(2026, 6, 24, 10),
        source: TrainerActivitySource.watch,
        type: TrainerActivityType.measuredWalk,
        estimatedKcal: 120,
        sourceActivityId: 'walk-window',
        startedAt: DateTime(2026, 6, 24, 10),
        endedAt: DateTime(2026, 6, 24, 10, 35),
        durationMin: 35,
      ),
    );
    await store.upsertActivityEntry(
      TrainerActivityEntry(
        id: 'run-1',
        date: DateTime(2026, 6, 24, 10),
        source: TrainerActivitySource.run,
        type: TrainerActivityType.run,
        estimatedKcal: 360,
        sourceActivityId: 'run-window',
        startedAt: DateTime(2026, 6, 24, 10, 5),
        endedAt: DateTime(2026, 6, 24, 10, 38),
        durationMin: 33,
      ),
    );
    await store.upsertTrainingImpact(
      TrainingImpact(
        id: 'impact-session-1',
        sessionId: 'session-1',
        sessionName: 'Plan · Góra',
        date: DateTime(2026, 6, 24, 18),
        isTrainingDay: true,
        estimatedBurnedKcal: 260,
        suggestedCalorieAdjustmentKcal: 130,
        suggestedExtraWaterMl: 650,
        suggestedExtraProteinG: 30,
        postWorkoutMealSuggestion: 'Białko po treningu',
        durationMin: 45,
        exerciseCount: 4,
        setCount: 12,
        volumeKg: 8000,
        averageRpe: 8,
        createdAt: DateTime(2026, 6, 24, 19),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: ActivityDeduplicationPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Anty-dublowanie aktywności'), findsOneWidget);
    expect(find.text('Kroki'), findsWidgets);
    expect(find.text('Chód mierzony'), findsWidgets);
    expect(find.text('Bieg mierzony'), findsOneWidget);
    expect(find.text('Trening siłowy'), findsWidgets);
    expect(find.text('Zaliczono do kcal'), findsWidgets);
    expect(find.text('Pominięto jako duplikat'), findsWidgets);
    expect(find.textContaining('Zaliczone:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
