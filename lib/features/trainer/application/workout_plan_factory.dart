import 'dart:math' as math;

import '../domain/trainer_models.dart';

class WorkoutPlanFactory {
  const WorkoutPlanFactory._();

  static WorkoutPlan local({
    required String level,
    required String goal,
    required List<int> trainingWeekdays,
    required Exercise Function(String id) exerciseById,
  }) {
    final normalizedLevel = normalizeTrainingLevel(level);
    final days = <WorkoutDay>[];
    final cycle = normalizedLevel == 'Początkujący'
        ? const [
            ['incline_pushup', 'goblet_squat', 'assisted_pullup', 'plank'],
            ['lat_pulldown', 'reverse_lunge', 'face_pull', 'crunch'],
            ['pushup', 'squat', 'bicep_curl', 'side_plank'],
            ['bike', 'mountain_climber', 'calf_raise', 'triceps_extension'],
          ]
        : normalizedLevel == 'Zaawansowany'
            ? const [
                ['front_squat', 'pullup', 'bench_press', 'hollow_hold'],
                ['deadlift', 'dips', 'row', 'leg_raise'],
                [
                  'bulgarian_split_squat',
                  'shoulder_press',
                  'jump_rope',
                  'russian_twist',
                ],
                ['pistol_squat', 'burpee', 'pullup', 'plank'],
                ['run', 'hip_thrust', 'lateral_raise', 'face_pull'],
              ]
            : const [
                ['squat', 'lunge', 'crunch', 'plank'],
                ['pushup', 'pullup', 'shoulder_press', 'bicep_curl'],
                ['deadlift', 'hip_thrust', 'mountain_climber', 'side_plank'],
                [
                  'bench_press',
                  'row',
                  'lateral_raise',
                  'triceps_extension',
                ],
                ['jumping_jack', 'burpee', 'leg_raise', 'russian_twist'],
              ];

    for (var index = 0; index < trainingWeekdays.length; index++) {
      final weekday = trainingWeekdays[index];
      final exerciseIds = cycle[index % cycle.length];
      days.add(
        WorkoutDay(
          weekday: weekday,
          title: normalizedLevel == 'Początkujący'
              ? (index.isEven ? 'Fundament techniki' : 'Lekka siła + core')
              : normalizedLevel == 'Zaawansowany'
                  ? (index.isEven ? 'Siła / hipertrofia' : 'Moc + kondycja')
                  : (index.isEven ? 'Siła + brzuch' : 'Góra ciała + kondycja'),
          items: exerciseIds.map((id) {
            final exercise = exerciseById(id);
            final setModifier = normalizedLevel == 'Początkujący'
                ? -1
                : normalizedLevel == 'Zaawansowany'
                    ? 1
                    : 0;
            return PlanItem(
              exerciseId: id,
              sets: math.max(2, exercise.defaultSets + setModifier).toInt(),
              reps: exercise.defaultReps,
              durationSec: exercise.defaultDurationSec,
              note: exercise.defaultDurationSec > 0
                  ? 'czas pracy · poziom $normalizedLevel'
                  : 'kontrolowane tempo · poziom $normalizedLevel',
            );
          }).toList(),
        ),
      );
    }

    return WorkoutPlan(
      id: 'plan_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Plan lokalny $normalizedLevel: $goal',
      days: days,
      note:
          'Plan lokalny dopasowany do poziomu: $normalizedLevel. Możesz go nadpisać planem AI przez Twój backend.',
    );
  }

  static WorkoutPlan fromAi({
    required Map<String, dynamic> json,
    required String goal,
    required List<Exercise> exercises,
    required WorkoutPlan Function() fallback,
  }) {
    if (exercises.isEmpty) return fallback();

    final rawDays =
        (json['days'] as List?) ?? (json['week_plan'] as List?) ?? const [];
    final days = <WorkoutDay>[];

    for (final rawDay in rawDays.whereType<Map>()) {
      final map = Map<String, dynamic>.from(rawDay);
      final weekdayRaw = map['weekday'] ?? map['day'] ?? 1;
      final weekday = weekdayRaw is num
          ? weekdayRaw.toInt()
          : _weekdayFromText(weekdayRaw.toString());
      final rawItems =
          (map['items'] as List?) ?? (map['exercises'] as List?) ?? const [];
      final items = <PlanItem>[];

      for (final rawItem in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(rawItem);
        final name =
            (item['exercise'] ?? item['name'] ?? '').toString().toLowerCase();
        final found = exercises.firstWhere(
          (exercise) =>
              name.contains(exercise.name.toLowerCase()) ||
              exercise.name.toLowerCase().contains(name),
          orElse: () => exercises.first,
        );
        items.add(
          PlanItem(
            exerciseId: found.id,
            sets: (item['sets'] as num?)?.toInt() ?? found.defaultSets,
            reps: (item['reps'] as num?)?.toInt() ?? found.defaultReps,
            durationSec: (item['duration_sec'] as num?)?.toInt() ??
                found.defaultDurationSec,
            note: (item['note'] ?? item['reason'] ?? '').toString(),
          ),
        );
      }

      days.add(
        WorkoutDay(
          weekday: weekday,
          title: map['title']?.toString() ?? 'Trening',
          items: items,
        ),
      );
    }

    if (days.isEmpty) return fallback();
    return WorkoutPlan(
      id: 'plan_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Plan AI: $goal',
      days: days,
      note: json['note']?.toString() ?? 'Plan utworzony przez backend AI.',
    );
  }

  static int _weekdayFromText(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('wt')) return 2;
    if (normalized.contains('ś') || normalized.contains('sr')) return 3;
    if (normalized.contains('czw')) return 4;
    if (normalized.contains('pt')) return 5;
    if (normalized.contains('sob')) return 6;
    if (normalized.contains('niedz')) return 7;
    return 1;
  }
}
