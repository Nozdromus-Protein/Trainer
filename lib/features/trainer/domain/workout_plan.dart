class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.days,
    required this.note,
  });

  final String id;
  final String name;
  final List<WorkoutDay> days;
  final String note;

  WorkoutPlan copyWith({
    String? id,
    String? name,
    List<WorkoutDay>? days,
    String? note,
  }) {
    return WorkoutPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      days: days ?? this.days,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days.map((day) => day.toJson()).toList(),
        'note': note,
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
      );
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
  });

  final String exerciseId;
  final int sets;
  final int reps;
  final int durationSec;
  final String note;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets,
        'reps': reps,
        'durationSec': durationSec,
        'note': note,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        exerciseId: json['exerciseId']?.toString() ?? '',
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        reps: (json['reps'] as num?)?.toInt() ?? 10,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        note: json['note']?.toString() ?? '',
      );
}
