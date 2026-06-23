class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.days,
    required this.note,
    this.goal = 'Sylwetka',
    this.isActive = false,
  });

  final String id;
  final String name;
  final List<WorkoutDay> days;
  final String note;
  final String goal;
  final bool isActive;

  WorkoutPlan copyWith({
    String? id,
    String? name,
    List<WorkoutDay>? days,
    String? note,
    String? goal,
    bool? isActive,
  }) {
    return WorkoutPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      days: days ?? this.days,
      note: note ?? this.note,
      goal: goal ?? this.goal,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days.map((day) => day.toJson()).toList(),
        'note': note,
        'goal': goal,
        'isActive': isActive,
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id']?.toString() ??
            'plan_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'Plan',
        days: ((json['days'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => WorkoutDay.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        note: json['note']?.toString() ?? '',
        goal: normalizeWorkoutPlanGoal(json['goal']?.toString() ?? ''),
        isActive: json['isActive'] as bool? ?? false,
      );
}

const List<String> workoutPlanGoals = [
  'Masa',
  'Redukcja',
  'Siła',
  'Kondycja',
  'Sylwetka',
];

String normalizeWorkoutPlanGoal(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('masa') ||
      normalized.contains('hipert') ||
      normalized.contains('mięś') ||
      normalized.contains('mies')) {
    return 'Masa';
  }
  if (normalized.contains('redu') ||
      normalized.contains('spal') ||
      normalized.contains('fat')) {
    return 'Redukcja';
  }
  if (normalized.contains('sił') || normalized.contains('sil')) {
    return 'Siła';
  }
  if (normalized.contains('kond') ||
      normalized.contains('wydol') ||
      normalized.contains('cardio')) {
    return 'Kondycja';
  }
  return 'Sylwetka';
}

class WorkoutDay {
  const WorkoutDay({
    required this.weekday,
    required this.title,
    required this.items,
  });

  final int weekday;
  final String title;
  final List<PlanItem> items;

  WorkoutDay copyWith({
    int? weekday,
    String? title,
    List<PlanItem>? items,
  }) {
    return WorkoutDay(
      weekday: weekday ?? this.weekday,
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'title': title,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        title: json['title']?.toString() ?? 'Trening',
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => PlanItem.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
      );
}

class PlanItem {
  const PlanItem({
    required this.exerciseId,
    required this.sets,
    required this.reps,
    required this.durationSec,
    required this.note,
    this.suggestedWeightKg = 0,
    this.restSeconds = 90,
  });

  final String exerciseId;
  final int sets;
  final int reps;
  final int durationSec;
  final String note;
  final double suggestedWeightKg;
  final int restSeconds;

  PlanItem copyWith({
    String? exerciseId,
    int? sets,
    int? reps,
    int? durationSec,
    String? note,
    double? suggestedWeightKg,
    int? restSeconds,
  }) {
    return PlanItem(
      exerciseId: exerciseId ?? this.exerciseId,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      durationSec: durationSec ?? this.durationSec,
      note: note ?? this.note,
      suggestedWeightKg: suggestedWeightKg ?? this.suggestedWeightKg,
      restSeconds: restSeconds ?? this.restSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets,
        'reps': reps,
        'durationSec': durationSec,
        'note': note,
        'suggestedWeightKg': suggestedWeightKg,
        'restSeconds': restSeconds,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        exerciseId: json['exerciseId']?.toString() ?? '',
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        reps: (json['reps'] as num?)?.toInt() ?? 10,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        note: json['note']?.toString() ?? '',
        suggestedWeightKg: (json['suggestedWeightKg'] as num?)?.toDouble() ?? 0,
        restSeconds: (json['restSeconds'] as num?)?.toInt() ?? 90,
      );
}
