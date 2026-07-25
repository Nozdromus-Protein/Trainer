import 'workout_set.dart';

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.exerciseId,
    required this.date,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.durationSec,
    required this.rpe,
    required this.calories,
    required this.note,
    required this.aiConfidence,
    this.workoutSets = const [],
    this.sessionId = '',
    this.sessionName = '',
    this.sessionStartedAt,
    this.sessionEndedAt,
    this.sessionNote = '',
    this.performedAt,
  });

  final String id;
  final String exerciseId;

  /// DZIEŃ treningowy (lokalna północ). Trening 23:40 → 00:20 należy w całości
  /// do dnia, w którym się zaczął — na tym opiera się historia, statystyki dnia
  /// i most do Kalorii, więc pole celowo NIE niesie godziny.
  final DateTime date;
  final int sets;
  final int reps;
  final double weightKg;
  final int durationSec;
  final int rpe;
  final double calories;
  final String note;
  final double aiConfidence;
  final List<WorkoutSet> workoutSets;
  final String sessionId;
  final String sessionName;
  final DateTime? sessionStartedAt;
  final DateTime? sessionEndedAt;
  final String sessionNote;

  /// MOMENT wykonania (z godziną) dla wpisów spoza sesji treningowej.
  /// `null` = brak jawnego znacznika; patrz [effectivePerformedAt].
  final DateTime? performedAt;

  /// Realny moment wysiłku — używany przez model regeneracji.
  ///
  /// [date] to sama data dnia (północ), więc liczenie od niej wygaszało bodziec
  /// o tyle godzin, ile minęło od północy: trening o 21:00 wyglądał zaraz po
  /// zakończeniu jak sprzed 21 godzin i mapa mięśni pokazywała „zregenerowane".
  /// Kolejność: jawny znacznik → koniec sesji → start sesji → dzień treningowy.
  DateTime get effectivePerformedAt =>
      performedAt ?? sessionEndedAt ?? sessionStartedAt ?? date;

  double get volume => workoutSets.isEmpty
      ? sets * reps * weightKg
      : workoutSets
          .where((workoutSet) => workoutSet.isCompleted)
          .fold<double>(0, (sum, workoutSet) => sum + workoutSet.volume);

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'date': date.toIso8601String(),
        'sets': sets,
        'reps': reps,
        'weightKg': weightKg,
        'durationSec': durationSec,
        'rpe': rpe,
        'calories': calories,
        'note': note,
        'aiConfidence': aiConfidence,
        'workoutSets':
            workoutSets.map((workoutSet) => workoutSet.toJson()).toList(),
        'sessionId': sessionId,
        'sessionName': sessionName,
        'sessionStartedAt': sessionStartedAt?.toIso8601String(),
        'sessionEndedAt': sessionEndedAt?.toIso8601String(),
        'sessionNote': sessionNote,
        'performedAt': performedAt?.toIso8601String(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id']?.toString() ??
            'session_${DateTime.now().microsecondsSinceEpoch}',
        exerciseId: json['exerciseId']?.toString() ?? '',
        date:
            DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        sets: (json['sets'] as num?)?.toInt() ?? 0,
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        // 0 = brak oceny. NIE wstawiamy domyślnej „7", bo fabrykowałaby
        // wiarygodnie wyglądający pomiar tam, gdzie żadnego nie było.
        rpe: (json['rpe'] as num?)?.toInt() ?? 0,
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString() ?? '',
        aiConfidence: (json['aiConfidence'] as num?)?.toDouble() ?? 0,
        workoutSets: ((json['workoutSets'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => WorkoutSet.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        sessionId: json['sessionId']?.toString() ?? '',
        sessionName: json['sessionName']?.toString() ?? '',
        sessionStartedAt:
            DateTime.tryParse(json['sessionStartedAt']?.toString() ?? ''),
        sessionEndedAt:
            DateTime.tryParse(json['sessionEndedAt']?.toString() ?? ''),
        sessionNote: json['sessionNote']?.toString() ?? '',
        performedAt: DateTime.tryParse(json['performedAt']?.toString() ?? ''),
      );
}

class WorkoutLog extends WorkoutSession {
  const WorkoutLog({
    required super.id,
    required super.exerciseId,
    required super.date,
    required super.sets,
    required super.reps,
    required super.weightKg,
    required super.durationSec,
    required super.rpe,
    required super.calories,
    required super.note,
    required super.aiConfidence,
    super.workoutSets,
    super.sessionId,
    super.sessionName,
    super.sessionStartedAt,
    super.sessionEndedAt,
    super.sessionNote,
    super.performedAt,
    this.planId = '',
    this.dayIndex = -1,
  });

  /// Plan (zestaw), z którego pochodzi wpis. Pusty = wpis ręczny / spoza planu.
  ///
  /// Bez tego nie dało się stwierdzić, KTÓRY zestaw został dziś wykonany —
  /// rozkład dwutorowy potrzebuje tego, żeby po pierwszorzędnym przejść do
  /// drugorzędnego zamiast proponować w kółko ten sam program.
  final String planId;

  /// Indeks dnia w planie (−1 = nieznany / wpis spoza planu).
  final int dayIndex;

  WorkoutLog copyWith({
    String? id,
    String? exerciseId,
    DateTime? date,
    int? sets,
    int? reps,
    double? weightKg,
    int? durationSec,
    int? rpe,
    double? calories,
    String? note,
    double? aiConfidence,
    List<WorkoutSet>? workoutSets,
    String? sessionId,
    String? sessionName,
    DateTime? sessionStartedAt,
    DateTime? sessionEndedAt,
    String? sessionNote,
    DateTime? performedAt,
    String? planId,
    int? dayIndex,
  }) {
    return WorkoutLog(
      id: id ?? this.id,
      exerciseId: exerciseId ?? this.exerciseId,
      date: date ?? this.date,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weightKg: weightKg ?? this.weightKg,
      durationSec: durationSec ?? this.durationSec,
      rpe: rpe ?? this.rpe,
      calories: calories ?? this.calories,
      note: note ?? this.note,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      workoutSets: workoutSets ?? this.workoutSets,
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      sessionEndedAt: sessionEndedAt ?? this.sessionEndedAt,
      sessionNote: sessionNote ?? this.sessionNote,
      performedAt: performedAt ?? this.performedAt,
      planId: planId ?? this.planId,
      dayIndex: dayIndex ?? this.dayIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (planId.isNotEmpty) 'planId': planId,
        if (dayIndex >= 0) 'dayIndex': dayIndex,
      };

  factory WorkoutLog.fromJson(Map<String, dynamic> json) {
    final session = WorkoutSession.fromJson(json);
    return WorkoutLog(
      id: session.id,
      exerciseId: session.exerciseId,
      date: session.date,
      sets: session.sets,
      reps: session.reps,
      weightKg: session.weightKg,
      durationSec: session.durationSec,
      rpe: session.rpe,
      calories: session.calories,
      note: session.note,
      aiConfidence: session.aiConfidence,
      workoutSets: session.workoutSets,
      sessionId: session.sessionId,
      sessionName: session.sessionName,
      sessionStartedAt: session.sessionStartedAt,
      sessionEndedAt: session.sessionEndedAt,
      sessionNote: session.sessionNote,
      performedAt: session.performedAt,
      planId: json['planId']?.toString() ?? '',
      dayIndex: (json['dayIndex'] as num?)?.toInt() ?? -1,
    );
  }
}
