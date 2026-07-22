import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_coach.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/application/workout_planner_service.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise.dart';

Exercise _exercise(
  String id,
  List<ExerciseMuscleImpact> impacts, {
  double met = 5,
}) {
  return Exercise(
    id: id,
    name: id,
    category: 'Test',
    muscles: const [],
    equipment: 'hantle',
    level: 'Średniozaawansowany',
    illustrationType: 'generic',
    description: '',
    tips: const [],
    commonMistakes: const [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: met,
    muscleImpacts: impacts,
  );
}

SetRecommendation _rec({
  int sets = 3,
  int reps = 10,
  double weight = 20,
  int rest = 90,
}) {
  return SetRecommendation(
    sets: sets,
    reps: reps,
    weightKg: weight,
    durationSec: 0,
    restSeconds: rest,
    reasons: const ['Cel: rozwój masy.'],
  );
}

PlannerExerciseInput _input(String id, {double readiness = 90, double? delta}) {
  return PlannerExerciseInput(
    exercise: _exercise(id, const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.triceps, role: MuscleRole.secondary),
    ]),
    recommendation: _rec(),
    readinessPercent: readiness,
    weightDeltaKg: delta,
  );
}

WeeklyTrainingAdvice _advice({
  String headline = 'Dobry dzień na trening: Klatka / triceps.',
  List<String> avoid = const [],
}) {
  return WeeklyTrainingAdvice(
    todayHeadline: headline,
    todayAvoid: avoid,
    notes: const [],
    week: const [],
    programs: const [],
    areaReadiness: const [
      AreaReadinessToday(area: TrainingFocusArea.chestTriceps, percent: 90),
      AreaReadinessToday(area: TrainingFocusArea.legs, percent: 70),
    ],
  );
}

void main() {
  test('program day produces a forecast, title and subtitle', () {
    final program = PlannerProgramContext(
      programId: 'prog_1',
      planName: 'Siła 30 dni',
      dayIndex: 7,
      dayNumber: 8,
      totalDays: 30,
      dayTitle: 'Klatka + triceps',
      isRest: false,
      exercises: [_input('bench'), _input('dip', readiness: 88)],
    );

    final planned = buildPlannedWorkout(
      advice: _advice(avoid: const ['Barki (48%)']),
      program: program,
      dynamicExercises: const [],
      signals: const PlannerSignals(hasHistory: true, hasRecoveryData: true),
      bodyWeightKg: 80,
      goal: 'Masa',
    );

    expect(planned.kind, PlannedWorkoutKind.programDay);
    expect(planned.title, 'Klatka + triceps');
    expect(planned.subtitle, contains('Dzień 8/30'));
    expect(planned.exercises, hasLength(2));
    expect(planned.forecast.kcalMax, greaterThan(0));
    expect(planned.forecast.minMinutes, greaterThan(0));
    expect(planned.readinessPercent, 88);
    expect(planned.reasonBullets, isNotEmpty);
    expect(planned.alternatives, isNotEmpty);
    expect(planned.confidence, greaterThan(0.5));
    // Główne partie do mapy mięśni.
    expect(planned.mainMuscles, contains(BodyMuscle.chest));
  });

  test('forecast uses net kcal and carbs cover only credited energy', () {
    const exercise = PlannedExercise(
      exerciseId: 'forecast_test',
      name: 'Test',
      sets: 3,
      reps: 10,
      durationSec: 0,
      weightKg: 20,
      restSeconds: 90,
      primaryMuscles: <String>['Klatka'],
      secondaryMuscles: <String>[],
      loadTypeLabel: 'Ciężar zewnętrzny',
      reasons: <String>[],
      readinessPercent: 90,
    );
    final forecast = forecastForExercises(
      exercises: List<PlannedExercise>.filled(5, exercise),
      bodyWeightKg: 80,
      goal: 'Rekompozycja',
      lighter: false,
      mets: List<double>.filled(5, 5),
    );

    // 5 ćwiczeń × 6 min × (5-1) MET netto dla 80 kg = ok. 168 kcal.
    expect(forecast.kcalMin, closeTo(148, 1));
    expect(forecast.kcalMax, closeTo(195, 1));
    expect(forecast.creditedKcalMin, closeTo(89, 1));
    expect(forecast.creditedKcalMax, closeTo(118, 1));
    expect((forecast.carbsMinG * 4 - forecast.creditedKcalMin).abs(),
        lessThanOrEqualTo(2));
    expect((forecast.carbsMaxG * 4 - forecast.creditedKcalMax).abs(),
        lessThanOrEqualTo(2));
  });

  test('time cap trims auxiliary exercises but keeps the main lift', () {
    final program = PlannerProgramContext(
      programId: 'p',
      planName: 'Test',
      dayIndex: 0,
      dayNumber: 1,
      totalDays: 10,
      dayTitle: 'Full body',
      isRest: false,
      exercises: [
        for (var i = 0; i < 6; i++) _input('ex_$i'),
      ],
    );

    final full = buildPlannedWorkout(
      advice: _advice(),
      program: program,
      dynamicExercises: const [],
      signals: const PlannerSignals(hasHistory: true, hasRecoveryData: true),
      bodyWeightKg: 80,
      goal: 'Masa',
    );
    final short = buildPlannedWorkout(
      advice: _advice(),
      program: program,
      dynamicExercises: const [],
      signals: const PlannerSignals(hasHistory: true, hasRecoveryData: true),
      bodyWeightKg: 80,
      goal: 'Masa',
      timeCapMinutes: 15,
    );

    expect(short.forecast.maxMinutes, lessThanOrEqualTo(full.forecast.maxMinutes));
    expect(short.exercises, isNotEmpty);
    expect(short.exercises.first.exerciseId, 'ex_0');
    expect(short.forecast.setCount, lessThan(full.forecast.setCount));
  });

  test('overload signals trigger a high load level and deload advice', () {
    const signals = PlannerSignals(
      avgRecentRpe: 9.0,
      tiredMuscleCount: 5,
      hardDaysLast7: 4,
      incompleteSetStreak: 2,
      consecutiveTrainingDays: 6,
      strengthSessionsLast7: 6,
      hasHistory: true,
      hasRecoveryData: true,
    );
    final load = assessTrainingLoad(signals);
    expect(load.level, TrainingLoadLevel.overload);
    expect(load.signals, isNotEmpty);

    final deload = assessDeload(signals, load);
    expect(deload.recommended, isTrue);
    expect(deload.days, greaterThan(0));
    expect(deload.changes, isNotEmpty);
  });

  test('fresh, easy week reports low load and no deload', () {
    const signals = PlannerSignals(
      avgRecentRpe: 6.0,
      tiredMuscleCount: 0,
      hardDaysLast7: 0,
      hasLightDayLast5: true,
      hasHistory: true,
      hasRecoveryData: true,
    );
    final load = assessTrainingLoad(signals);
    expect(load.level, TrainingLoadLevel.low);
    expect(assessDeload(signals, load).recommended, isFalse);
  });

  test('missing recovery/health data lowers confidence and lists gaps', () {
    final planned = buildPlannedWorkout(
      advice: _advice(),
      program: null,
      dynamicExercises: [_input('bench')],
      signals: const PlannerSignals(hasHistory: true),
      bodyWeightKg: 80,
      goal: 'Masa',
    );
    expect(planned.kind, PlannedWorkoutKind.dynamicSuggestion);
    expect(planned.missingData, isNotEmpty);
    expect(planned.confidence, lessThan(0.85));
  });
}
