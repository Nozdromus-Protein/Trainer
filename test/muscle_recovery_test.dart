import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

Exercise _exercise(String id,
    {List<ExerciseMuscleImpact> impacts = const [],
    List<String> muscles = const ['klatka piersiowa']}) {
  return Exercise(
    id: id,
    name: id,
    category: 'Test',
    muscles: muscles,
    equipment: 'masa ciała',
    level: 'Początkujący',
    illustrationType: 'generic',
    description: '',
    tips: const [],
    commonMistakes: const [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: 4,
    muscleImpacts: impacts,
  );
}

WorkoutLog _log(String exerciseId, DateTime date,
    {int sets = 3, int reps = 10, int rpe = 8}) {
  return WorkoutLog(
    id: 'log_$exerciseId${date.millisecondsSinceEpoch}',
    exerciseId: exerciseId,
    date: date,
    sets: sets,
    reps: reps,
    weightKg: 40,
    durationSec: 0,
    rpe: rpe,
    calories: 100,
    note: '',
    aiConfidence: 0,
    sessionId: 'session-1',
  );
}

void main() {
  group('Muscle impact + BodyMuscle', () {
    test('ExerciseMuscleImpact JSON round-trip and role weights', () {
      const impact = ExerciseMuscleImpact(
          muscleGroup: BodyMuscle.chest, role: MuscleRole.primary);
      expect(impact.effectiveWeight, 1.0);
      final restored = ExerciseMuscleImpact.fromJson(impact.toJson());
      expect(restored, isNotNull);
      expect(restored!.muscleGroup, BodyMuscle.chest);
      expect(restored.role, MuscleRole.primary);
      expect(MuscleRole.secondary.weight, 0.5);
      expect(MuscleRole.stabilizer.weight, 0.25);
    });

    test('BodyMuscle.fromText maps common Polish names', () {
      expect(BodyMuscle.fromText('klatka piersiowa'), BodyMuscle.chest);
      expect(BodyMuscle.fromText('triceps'), BodyMuscle.triceps);
      expect(BodyMuscle.fromText('pośladki'), BodyMuscle.glutes);
      expect(BodyMuscle.fromText('czworogłowe uda'), BodyMuscle.quads);
      expect(BodyMuscle.fromText('core'), BodyMuscle.abs);
      expect(BodyMuscle.fromText('xyz nieznane'), isNull);
    });

    test('BodyMuscle.fromText keeps detailed anatomical muscles', () {
      expect(
        BodyMuscle.fromText('mięsień nadgrzebieniowy'),
        BodyMuscle.supraspinatus,
      );
      expect(
        BodyMuscle.fromText('infraspinatus'),
        BodyMuscle.infraspinatus,
      );
      expect(
        BodyMuscle.fromText('mięsień zębaty przedni'),
        BodyMuscle.serratusAnterior,
      );
      expect(
        BodyMuscle.fromText('prostowniki grzbietu'),
        BodyMuscle.erectorSpinae,
      );
    });

    test('mask maps cover front and back muscles', () {
      expect(kFrontMuscleMasks[BodyMuscle.abs], hasLength(4));
      expect(kFrontMuscleMasks[BodyMuscle.quads], hasLength(2));
      expect(kBackMuscleMasks[BodyMuscle.hamstrings], hasLength(2));
      // Adductors są po obu stronach.
      expect(kFrontMuscleMasks.containsKey(BodyMuscle.adductors), isTrue);
      expect(kBackMuscleMasks.containsKey(BodyMuscle.adductors), isTrue);
      expect(kBackMuscleMasks[BodyMuscle.supraspinatus], isNotEmpty);
      expect(kFrontMuscleMasks[BodyMuscle.serratusAnterior], isNotEmpty);
    });
  });

  group('Exercise.effectiveMuscleImpacts', () {
    test('explicit impacts win over derived', () {
      final exercise = _exercise('pushup', impacts: const [
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.triceps, role: MuscleRole.secondary),
      ]);
      final impacts = exercise.effectiveMuscleImpacts;
      expect(impacts, hasLength(2));
      expect(impacts.first.muscleGroup, BodyMuscle.chest);
      expect(exercise.hasMuscleAssignment, isTrue);
    });

    test('derives impacts from muscles when none explicit (first = primary)',
        () {
      final exercise = _exercise('row', muscles: const ['plecy', 'biceps']);
      final impacts = exercise.effectiveMuscleImpacts;
      expect(impacts, isNotEmpty);
      expect(impacts.first.role, MuscleRole.primary);
      expect(
          impacts.skip(1).every((i) => i.role == MuscleRole.secondary), isTrue);
    });

    test('JSON round-trip keeps muscle impacts', () {
      final exercise = _exercise('pushup', impacts: const [
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
      ]);
      final restored = Exercise.fromJson(exercise.toJson());
      expect(restored.muscleImpacts, hasLength(1));
      expect(restored.muscleImpacts.first.muscleGroup, BodyMuscle.chest);
    });
  });

  group('RecoveryCalculator', () {
    Exercise resolve(String id) => _exercise(id, impacts: const [
          ExerciseMuscleImpact(
              muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
        ]);

    test('recently trained muscle is fatigued (low recovery)', () {
      final now = DateTime(2026, 6, 30, 12);
      final map = const RecoveryCalculator().compute(
        logs: [_log('pushup', now.subtract(const Duration(hours: 1)))],
        resolveExercise: resolve,
        now: now,
      );
      final chest = map[BodyMuscle.chest];
      expect(chest, isNotNull);
      expect(chest!.hasData, isTrue);
      expect(chest.recoveryPercent, lessThan(30));
      expect(
          chest.status == RecoveryStatus.freshFatigue ||
              chest.status == RecoveryStatus.heavyFatigue,
          isTrue);
    });

    test('old training (beyond window) is ignored', () {
      final now = DateTime(2026, 6, 30, 12);
      final map = const RecoveryCalculator().compute(
        logs: [_log('pushup', now.subtract(const Duration(days: 6)))],
        resolveExercise: resolve,
        now: now,
      );
      expect(map.containsKey(BodyMuscle.chest), isFalse);
    });

    test('exercise without muscle impacts does not load any muscle', () {
      final now = DateTime(2026, 6, 30, 12);
      final map = const RecoveryCalculator().compute(
        logs: [_log('mystery', now.subtract(const Duration(hours: 1)))],
        resolveExercise: (id) => _exercise(id, muscles: const []),
        now: now,
      );
      expect(map, isEmpty);
    });

    test('recoveryStatusForPercent buckets', () {
      expect(recoveryStatusForPercent(null), RecoveryStatus.unknown);
      expect(recoveryStatusForPercent(10), RecoveryStatus.freshFatigue);
      expect(recoveryStatusForPercent(30), RecoveryStatus.heavyFatigue);
      expect(recoveryStatusForPercent(50), RecoveryStatus.recovering);
      expect(recoveryStatusForPercent(70), RecoveryStatus.almostRecovered);
      expect(recoveryStatusForPercent(95), RecoveryStatus.recovered);
    });
  });

  group('recoveryWarningsForExercises', () {
    MuscleRecoveryState state(BodyMuscle m, double pct) => MuscleRecoveryState(
          muscleGroup: m,
          recoveryPercent: pct,
          status: recoveryStatusForPercent(pct),
          lastTrainedAt: DateTime(2026, 6, 30, 12),
        );

    test('fatigued primary muscle is warned (severe under 40%)', () {
      final exercise = _exercise('pushup', impacts: const [
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
      ]);
      final warnings = recoveryWarningsForExercises(
          [exercise], {BodyMuscle.chest: state(BodyMuscle.chest, 30)});
      expect(warnings, hasLength(1));
      expect(warnings.first.muscle, BodyMuscle.chest);
      expect(warnings.first.severe, isTrue);
    });

    test('recovered muscle is not warned', () {
      final exercise = _exercise('pushup', impacts: const [
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
      ]);
      expect(
          recoveryWarningsForExercises(
              [exercise], {BodyMuscle.chest: state(BodyMuscle.chest, 85)}),
          isEmpty);
    });

    test('stabilizer-only muscle is not warned', () {
      final exercise = _exercise('plank', impacts: const [
        ExerciseMuscleImpact(
            muscleGroup: BodyMuscle.abs, role: MuscleRole.stabilizer),
      ]);
      expect(
          recoveryWarningsForExercises(
              [exercise], {BodyMuscle.abs: state(BodyMuscle.abs, 20)}),
          isEmpty);
    });
  });
}
