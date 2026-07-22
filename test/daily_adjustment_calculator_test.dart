import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/daily_adjustment_calculator.dart';
import 'package:licznik_treningu/features/trainer/domain/activity_credit.dart';
import 'package:licznik_treningu/features/trainer/domain/health_connect_snapshot.dart';

void main() {
  final day = DateTime(2026, 7, 20); // Monday

  TrainerHealthConnectSnapshot snapshot({
    int steps = 0,
    double activeKcal = 0,
  }) {
    return TrainerHealthConnectSnapshot(
      id: 'snapshot',
      date: day,
      checkedAt: day,
      sdkStatus: 'available',
      isAvailable: true,
      permissionsGranted: true,
      grantedPermissions: const <String>[],
      missingPermissions: const <String>[],
      steps: steps,
      distanceKm: 0,
      activeKcal: activeKcal,
      workoutSessions: 0,
      workoutMinutes: 0,
      averageHeartRate: 0,
      heartRateSamples: 0,
      sleepMinutes: 0,
      availableData: const <String>[],
      missingData: const <String>[],
    );
  }

  ActivityCreditDecision strengthWorkout(int kcal) {
    return ActivityCreditDecision(
      entry: TrainerActivityEntry(
        id: 'strength',
        date: day,
        source: TrainerActivitySource.trainer,
        type: TrainerActivityType.strengthTraining,
        estimatedKcal: kcal,
      ),
      includedInCalories: true,
      skippedAsDuplicate: false,
      reason: 'test',
    );
  }

  test('active calories from watch do not duplicate strength workout', () {
    final result = buildTrainerDailyAdjustment(
      day: day,
      decisions: <ActivityCreditDecision>[strengthWorkout(300)],
      impactsForDay: const [],
      snapshot: snapshot(activeKcal: 800),
      bodyWeightKg: 96,
    );

    expect(result.workoutKcal, 300);
    expect(result.totalAdjustmentKcal, 800);
    expect(result.healthDerivedKcal, 500);
  });

  test('work fallback replaces ordinary steps instead of adding to them', () {
    final result = buildTrainerDailyAdjustment(
      day: day,
      decisions: const <ActivityCreditDecision>[],
      impactsForDay: const [],
      snapshot: snapshot(steps: 10000),
      bodyWeightKg: 100,
      workIntensity: 'moderate',
      workHoursPerDay: 8,
      workWeekdays: const <int>[1, 2, 3, 4, 5],
    );

    expect(result.stepsKcal, 450);
    expect(result.workKcal, 1120);
    expect(result.totalAdjustmentKcal, 1120);
  });
}
