class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.order,
    required this.repetitions,
    required this.weightKg,
    required this.durationSec,
    required this.rpe,
    required this.isCompleted,
    this.note = '',
  });

  final String id;
  final int order;
  final int repetitions;
  final double weightKg;
  final int durationSec;
  final int rpe;
  final bool isCompleted;
  final String note;

  double get volume => repetitions * weightKg;

  WorkoutSet copyWith({
    String? id,
    int? order,
    int? repetitions,
    double? weightKg,
    int? durationSec,
    int? rpe,
    bool? isCompleted,
    String? note,
  }) {
    return WorkoutSet(
      id: id ?? this.id,
      order: order ?? this.order,
      repetitions: repetitions ?? this.repetitions,
      weightKg: weightKg ?? this.weightKg,
      durationSec: durationSec ?? this.durationSec,
      rpe: rpe ?? this.rpe,
      isCompleted: isCompleted ?? this.isCompleted,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order': order,
        'repetitions': repetitions,
        'weightKg': weightKg,
        'durationSec': durationSec,
        'rpe': rpe,
        'isCompleted': isCompleted,
        'note': note,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        id: json['id']?.toString() ??
            'set_${DateTime.now().microsecondsSinceEpoch}',
        order: (json['order'] as num?)?.toInt() ?? 1,
        repetitions: (json['repetitions'] as num?)?.toInt() ??
            (json['reps'] as num?)?.toInt() ??
            0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        rpe: (json['rpe'] as num?)?.toInt() ?? 0,
        isCompleted: json['isCompleted'] as bool? ?? true,
        note: json['note']?.toString() ?? '',
      );
}
