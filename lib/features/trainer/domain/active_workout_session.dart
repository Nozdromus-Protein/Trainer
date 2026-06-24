import 'training_impact.dart';
import 'workout_set.dart';

class ActiveWorkoutSession {
  const ActiveWorkoutSession({
    required this.id,
    required this.planId,
    required this.planName,
    required this.weekday,
    required this.dayTitle,
    required this.startedAt,
    required this.currentExerciseIndex,
    required this.exercises,
    this.note = '',
    this.restTimerEndsAt,
    this.restTimerRemainingSeconds = 0,
    this.restTimerTotalSeconds = 0,
    this.isRestTimerPaused = false,
  });

  final String id;
  final String planId;
  final String planName;
  final int weekday;
  final String dayTitle;
  final DateTime startedAt;
  final int currentExerciseIndex;
  final List<ActiveWorkoutExercise> exercises;
  final String note;
  final DateTime? restTimerEndsAt;
  final int restTimerRemainingSeconds;
  final int restTimerTotalSeconds;
  final bool isRestTimerPaused;

  ActiveWorkoutExercise? get currentExercise {
    if (exercises.isEmpty) return null;
    final index = currentExerciseIndex.clamp(0, exercises.length - 1);
    return exercises[index];
  }

  int get completedSetCount => exercises.fold<int>(
        0,
        (sum, exercise) => sum + exercise.completedSets.length,
      );

  int get completedExerciseCount => exercises.where((exercise) => exercise.completedSets.isNotEmpty).length;

  double get volume => exercises.fold<double>(
        0,
        (sum, exercise) => sum + exercise.volume,
      );

  double get averageRpe {
    final sets = exercises.expand((exercise) => exercise.completedSets).where((set) => set.rpe > 0).toList();
    if (sets.isEmpty) return 0;
    return sets.fold<int>(0, (sum, set) => sum + set.rpe) / sets.length;
  }

  int restSecondsRemaining([DateTime? now]) {
    if (isRestTimerPaused) return restTimerRemainingSeconds;
    final endsAt = restTimerEndsAt;
    if (endsAt == null) return restTimerRemainingSeconds;
    final seconds = endsAt.difference(now ?? DateTime.now()).inSeconds;
    return seconds.clamp(0, 3600);
  }

  bool get hasActiveRestTimer => restSecondsRemaining() > 0;

  ActiveWorkoutSession copyWith({
    String? id,
    String? planId,
    String? planName,
    int? weekday,
    String? dayTitle,
    DateTime? startedAt,
    int? currentExerciseIndex,
    List<ActiveWorkoutExercise>? exercises,
    String? note,
    DateTime? restTimerEndsAt,
    int? restTimerRemainingSeconds,
    int? restTimerTotalSeconds,
    bool? isRestTimerPaused,
    bool clearRestTimerEndsAt = false,
  }) {
    return ActiveWorkoutSession(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      weekday: weekday ?? this.weekday,
      dayTitle: dayTitle ?? this.dayTitle,
      startedAt: startedAt ?? this.startedAt,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      exercises: exercises ?? this.exercises,
      note: note ?? this.note,
      restTimerEndsAt: clearRestTimerEndsAt ? null : restTimerEndsAt ?? this.restTimerEndsAt,
      restTimerRemainingSeconds: restTimerRemainingSeconds ?? this.restTimerRemainingSeconds,
      restTimerTotalSeconds: restTimerTotalSeconds ?? this.restTimerTotalSeconds,
      isRestTimerPaused: isRestTimerPaused ?? this.isRestTimerPaused,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'planName': planName,
        'weekday': weekday,
        'dayTitle': dayTitle,
        'startedAt': startedAt.toIso8601String(),
        'currentExerciseIndex': currentExerciseIndex,
        'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
        'note': note,
        'restTimerEndsAt': restTimerEndsAt?.toIso8601String(),
        'restTimerRemainingSeconds': restTimerRemainingSeconds,
        'restTimerTotalSeconds': restTimerTotalSeconds,
        'isRestTimerPaused': isRestTimerPaused,
      };

  factory ActiveWorkoutSession.fromJson(Map<String, dynamic> json) {
    final exercises = ((json['exercises'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (value) => ActiveWorkoutExercise.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
    final rawIndex = (json['currentExerciseIndex'] as num?)?.toInt() ?? 0;
    return ActiveWorkoutSession(
      id: json['id']?.toString() ?? 'active_${DateTime.now().microsecondsSinceEpoch}',
      planId: json['planId']?.toString() ?? '',
      planName: json['planName']?.toString() ?? 'Trening',
      weekday: (json['weekday'] as num?)?.toInt() ?? DateTime.monday,
      dayTitle: json['dayTitle']?.toString() ?? 'Trening',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ?? DateTime.now(),
      currentExerciseIndex: exercises.isEmpty ? 0 : rawIndex.clamp(0, exercises.length - 1),
      exercises: exercises,
      note: json['note']?.toString() ?? '',
      restTimerEndsAt: DateTime.tryParse(json['restTimerEndsAt']?.toString() ?? ''),
      restTimerRemainingSeconds: (json['restTimerRemainingSeconds'] as num?)?.toInt() ?? 0,
      restTimerTotalSeconds: (json['restTimerTotalSeconds'] as num?)?.toInt() ?? 0,
      isRestTimerPaused: json['isRestTimerPaused'] as bool? ?? false,
    );
  }
}

class ActiveWorkoutExercise {
  const ActiveWorkoutExercise({
    required this.exerciseId,
    required this.plannedSets,
    required this.plannedReps,
    required this.suggestedWeightKg,
    required this.restSeconds,
    required this.note,
    this.completedSets = const [],
    this.isSkipped = false,
  });

  final String exerciseId;
  final int plannedSets;
  final int plannedReps;
  final double suggestedWeightKg;
  final int restSeconds;
  final String note;
  final List<WorkoutSet> completedSets;
  final bool isSkipped;

  double get volume => completedSets.fold<double>(
        0,
        (sum, set) => sum + set.volume,
      );

  ActiveWorkoutExercise copyWith({
    String? exerciseId,
    int? plannedSets,
    int? plannedReps,
    double? suggestedWeightKg,
    int? restSeconds,
    String? note,
    List<WorkoutSet>? completedSets,
    bool? isSkipped,
  }) {
    return ActiveWorkoutExercise(
      exerciseId: exerciseId ?? this.exerciseId,
      plannedSets: plannedSets ?? this.plannedSets,
      plannedReps: plannedReps ?? this.plannedReps,
      suggestedWeightKg: suggestedWeightKg ?? this.suggestedWeightKg,
      restSeconds: restSeconds ?? this.restSeconds,
      note: note ?? this.note,
      completedSets: completedSets ?? this.completedSets,
      isSkipped: isSkipped ?? this.isSkipped,
    );
  }

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'plannedSets': plannedSets,
        'plannedReps': plannedReps,
        'suggestedWeightKg': suggestedWeightKg,
        'restSeconds': restSeconds,
        'note': note,
        'completedSets': completedSets.map((set) => set.toJson()).toList(),
        'isSkipped': isSkipped,
      };

  factory ActiveWorkoutExercise.fromJson(Map<String, dynamic> json) => ActiveWorkoutExercise(
        exerciseId: json['exerciseId']?.toString() ?? '',
        plannedSets: (json['plannedSets'] as num?)?.toInt() ?? 3,
        plannedReps: (json['plannedReps'] as num?)?.toInt() ?? 10,
        suggestedWeightKg: (json['suggestedWeightKg'] as num?)?.toDouble() ?? 0,
        restSeconds: (json['restSeconds'] as num?)?.toInt() ?? 90,
        note: json['note']?.toString() ?? '',
        completedSets: ((json['completedSets'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => WorkoutSet.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        isSkipped: json['isSkipped'] as bool? ?? false,
      );
}

class CompletedWorkoutSummary {
  const CompletedWorkoutSummary({
    required this.sessionId,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.exerciseCount,
    required this.setCount,
    required this.volume,
    required this.averageRpe,
    this.trainingImpact,
  });

  final String sessionId;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final int exerciseCount;
  final int setCount;
  final double volume;
  final double averageRpe;
  final TrainingImpact? trainingImpact;

  Duration get duration => endedAt.difference(startedAt);
}
