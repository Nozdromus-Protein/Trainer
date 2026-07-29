import 'session_prescription.dart';
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
    this.dayIndex = -1,
    this.note = '',
    this.restTimerEndsAt,
    this.restTimerRemainingSeconds = 0,
    this.restTimerTotalSeconds = 0,
    this.isRestTimerPaused = false,
    this.isPaused = false,
    this.pausedByBackground = false,
    this.activeSegmentStartedAt,
    this.accumulatedActiveSeconds = 0,
    this.accumulatedPauseSeconds = 0,
    this.pauseStartedAt,
    this.partCount = 1,
    this.lastSetCompletedAt,
    this.restEndedAt,
  });

  final String id;
  final String planId;
  final String planName;
  final int weekday;
  final String dayTitle;

  /// Indeks dnia w programie ([WorkoutPlan.days]) albo -1, gdy trening ad-hoc.
  /// Pozwala oznaczyć właściwy dzień jako ukończony po zakończeniu. Etap 31.
  final int dayIndex;
  final DateTime startedAt;
  final int currentExerciseIndex;
  final List<ActiveWorkoutExercise> exercises;
  final String note;
  final DateTime? restTimerEndsAt;
  final int restTimerRemainingSeconds;
  final int restTimerTotalSeconds;
  final bool isRestTimerPaused;

  // ===== Rozdzielenie czasów: aktywny / pauza / tło / brutto (Etap: trener) =====

  /// Czy CAŁY trening jest wstrzymany (globalna pauza użytkownika albo tło).
  final bool isPaused;

  /// Czy pauza wynika z przejścia aplikacji do tła (do właściwego dialogu).
  final bool pausedByBackground;

  /// Początek bieżącego AKTYWNEGO odcinka; null, gdy trening jest wstrzymany.
  final DateTime? activeSegmentStartedAt;

  /// Zsumowany aktywny czas z już zamkniętych odcinków (s).
  final int accumulatedActiveSeconds;

  /// Zsumowany czas pauz/tła z już zamkniętych przerw (s).
  final int accumulatedPauseSeconds;

  /// Początek bieżącej pauzy/tła; null, gdy trening jest aktywny.
  final DateTime? pauseStartedAt;

  /// Liczba części treningu (po długiej przerwie rośnie — podział na części).
  final int partCount;

  // ===== Pomiar REALNEGO tempa (odpoczynek i czas serii) =====

  /// Kiedy zapisano ostatnią serię — początek odliczania odpoczynku.
  final DateTime? lastSetCompletedAt;

  /// Kiedy odpoczynek faktycznie się skończył (timer dobiegł końca albo został
  /// pominięty/skrócony). Dzięki temu wiemy, ile użytkownik NAPRAWDĘ odpoczywał
  /// i ile trwała sama praca — zamiast wierzyć, że trzymał się planu.
  final DateTime? restEndedAt;

  /// Realny odpoczynek przed kolejną serią (s) wraz z informacją, czy pomiar
  /// jest pewny. Gdy nie było zdarzenia końca przerwy (np. ekran gracza nie był
  /// otwarty), odtwarzamy go z luki między zapisami i oznaczamy jako niepewny.
  ({int restSec, int workSec, bool verified}) measureRestAndWork({
    required int plannedRestSec,
    DateTime? now,
  }) {
    final start = lastSetCompletedAt;
    if (start == null) return (restSec: 0, workSec: 0, verified: false);
    final moment = now ?? DateTime.now();
    final gapMs = moment.difference(start).inMilliseconds;
    if (gapMs < 0) return (restSec: 0, workSec: 0, verified: false);
    final ended = restEndedAt;
    if (ended != null && !ended.isBefore(start) && !ended.isAfter(moment)) {
      // Mamy ZDARZENIE końca przerwy — pomiar jest pewny nawet wtedy, gdy
      // wypadł na zero sekund (przerwa pominięta natychmiast).
      final restMs = ended.difference(start).inMilliseconds;
      return (
        restSec: restMs ~/ 1000,
        workSec: (gapMs - restMs) ~/ 1000,
        verified: true
      );
    }
    // Bez zdarzenia: zakładamy, że przerwa trwała tyle, ile plan (albo całą
    // lukę, gdy była krótsza), a reszta luki to praca. Pomiar niepewny.
    final gap = gapMs ~/ 1000;
    if (gap <= 0) return (restSec: 0, workSec: 0, verified: false);
    final planned = plannedRestSec > 0 ? plannedRestSec : 0;
    final rest = planned == 0 ? 0 : (gap < planned ? gap : planned);
    return (restSec: rest, workSec: gap - rest, verified: false);
  }

  ActiveWorkoutExercise? get currentExercise {
    if (exercises.isEmpty) return null;
    final index = currentExerciseIndex.clamp(0, exercises.length - 1);
    return exercises[index];
  }

  int get completedSetCount => exercises.fold<int>(
        0,
        (sum, exercise) => sum + exercise.completedSets.length,
      );

  int get completedExerciseCount =>
      exercises.where((exercise) => exercise.completedSets.isNotEmpty).length;

  double get volume => exercises.fold<double>(
        0,
        (sum, exercise) => sum + exercise.volume,
      );

  double get averageRpe {
    final sets = exercises
        .expand((exercise) => exercise.completedSets)
        .where((set) => set.rpe > 0)
        .toList();
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

  // ===== Czasy =====

  int _secondsSince(DateTime from, DateTime? now) {
    final seconds = (now ?? DateTime.now()).difference(from).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// Aktywny czas treningu netto (bez pauz i tła), w sekundach.
  int netActiveSeconds([DateTime? now]) {
    var total = accumulatedActiveSeconds;
    final segment = activeSegmentStartedAt;
    if (!isPaused && segment != null) {
      total += _secondsSince(segment, now);
    }
    return total;
  }

  /// Czas bieżącej, jeszcze niezamkniętej pauzy/tła (s).
  int currentPauseSeconds([DateTime? now]) {
    final start = pauseStartedAt;
    if (start == null) return 0;
    return _secondsSince(start, now);
  }

  /// Łączny czas pauz i tła (s).
  int totalPauseSeconds([DateTime? now]) =>
      accumulatedPauseSeconds + currentPauseSeconds(now);

  /// Czas brutto od uruchomienia treningu (s).
  int grossSeconds([DateTime? now]) => _secondsSince(startedAt, now);

  /// Wstrzymuje trening: zamyka aktywny odcinek i zaczyna liczyć pauzę.
  /// [byBackground] rozróżnia pauzę użytkownika od przejścia do tła.
  ActiveWorkoutSession pausedNow({bool byBackground = false, DateTime? now}) {
    if (isPaused) {
      // Już wstrzymany — utrwal jedynie źródło (tło), jeśli trzeba.
      return byBackground && !pausedByBackground
          ? copyWith(pausedByBackground: true)
          : this;
    }
    final moment = now ?? DateTime.now();
    final segment = activeSegmentStartedAt;
    final add = segment == null ? 0 : _secondsSince(segment, moment);
    return copyWith(
      isPaused: true,
      pausedByBackground: byBackground,
      accumulatedActiveSeconds: accumulatedActiveSeconds + add,
      clearActiveSegmentStartedAt: true,
      pauseStartedAt: moment,
    );
  }

  /// Wznawia trening: zamyka pauzę i otwiera nowy aktywny odcinek. Gdy przerwa
  /// była długa (≥ [longBreakThresholdSec]), zwiększa liczbę części treningu.
  ActiveWorkoutSession resumedNow({
    DateTime? now,
    int longBreakThresholdSec = 1800,
  }) {
    if (!isPaused) return this;
    final moment = now ?? DateTime.now();
    final start = pauseStartedAt;
    final pauseAdd = start == null ? 0 : _secondsSince(start, moment);
    final longBreak = pauseAdd >= longBreakThresholdSec;
    return copyWith(
      isPaused: false,
      pausedByBackground: false,
      accumulatedPauseSeconds: accumulatedPauseSeconds + pauseAdd,
      clearPauseStartedAt: true,
      activeSegmentStartedAt: moment,
      partCount: longBreak ? partCount + 1 : partCount,
    );
  }

  /// Zamrożenie po restarcie/awarii: NIE doliczamy nieznanej luki do aktywnego
  /// czasu (nie wiemy, kiedy aplikacja zniknęła) — zamykamy odcinek bez
  /// wydłużania i przechodzimy w pauzę (tło), żeby pokazać dialog wznowienia.
  ActiveWorkoutSession frozenOnRestart({DateTime? now}) {
    if (isPaused) {
      return pausedByBackground ? this : copyWith(pausedByBackground: true);
    }
    final moment = now ?? DateTime.now();
    return copyWith(
      isPaused: true,
      pausedByBackground: true,
      clearActiveSegmentStartedAt: true,
      pauseStartedAt: moment,
    );
  }

  ActiveWorkoutSession copyWith({
    String? id,
    String? planId,
    String? planName,
    int? weekday,
    String? dayTitle,
    int? dayIndex,
    DateTime? startedAt,
    int? currentExerciseIndex,
    List<ActiveWorkoutExercise>? exercises,
    String? note,
    DateTime? restTimerEndsAt,
    int? restTimerRemainingSeconds,
    int? restTimerTotalSeconds,
    bool? isRestTimerPaused,
    bool clearRestTimerEndsAt = false,
    bool? isPaused,
    bool? pausedByBackground,
    DateTime? activeSegmentStartedAt,
    int? accumulatedActiveSeconds,
    int? accumulatedPauseSeconds,
    DateTime? pauseStartedAt,
    int? partCount,
    bool clearActiveSegmentStartedAt = false,
    bool clearPauseStartedAt = false,
    DateTime? lastSetCompletedAt,
    DateTime? restEndedAt,
    bool clearRestEndedAt = false,
  }) {
    return ActiveWorkoutSession(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      weekday: weekday ?? this.weekday,
      dayTitle: dayTitle ?? this.dayTitle,
      dayIndex: dayIndex ?? this.dayIndex,
      startedAt: startedAt ?? this.startedAt,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      exercises: exercises ?? this.exercises,
      note: note ?? this.note,
      restTimerEndsAt:
          clearRestTimerEndsAt ? null : restTimerEndsAt ?? this.restTimerEndsAt,
      restTimerRemainingSeconds:
          restTimerRemainingSeconds ?? this.restTimerRemainingSeconds,
      restTimerTotalSeconds:
          restTimerTotalSeconds ?? this.restTimerTotalSeconds,
      isRestTimerPaused: isRestTimerPaused ?? this.isRestTimerPaused,
      isPaused: isPaused ?? this.isPaused,
      pausedByBackground: pausedByBackground ?? this.pausedByBackground,
      activeSegmentStartedAt: clearActiveSegmentStartedAt
          ? null
          : activeSegmentStartedAt ?? this.activeSegmentStartedAt,
      accumulatedActiveSeconds:
          accumulatedActiveSeconds ?? this.accumulatedActiveSeconds,
      accumulatedPauseSeconds:
          accumulatedPauseSeconds ?? this.accumulatedPauseSeconds,
      pauseStartedAt:
          clearPauseStartedAt ? null : pauseStartedAt ?? this.pauseStartedAt,
      partCount: partCount ?? this.partCount,
      lastSetCompletedAt: lastSetCompletedAt ?? this.lastSetCompletedAt,
      restEndedAt: clearRestEndedAt ? null : restEndedAt ?? this.restEndedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'planName': planName,
        'weekday': weekday,
        'dayTitle': dayTitle,
        'dayIndex': dayIndex,
        'startedAt': startedAt.toIso8601String(),
        'currentExerciseIndex': currentExerciseIndex,
        'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
        'note': note,
        'restTimerEndsAt': restTimerEndsAt?.toIso8601String(),
        'restTimerRemainingSeconds': restTimerRemainingSeconds,
        'restTimerTotalSeconds': restTimerTotalSeconds,
        'isRestTimerPaused': isRestTimerPaused,
        'isPaused': isPaused,
        'pausedByBackground': pausedByBackground,
        'activeSegmentStartedAt': activeSegmentStartedAt?.toIso8601String(),
        'accumulatedActiveSeconds': accumulatedActiveSeconds,
        'accumulatedPauseSeconds': accumulatedPauseSeconds,
        'pauseStartedAt': pauseStartedAt?.toIso8601String(),
        'partCount': partCount,
        if (lastSetCompletedAt != null)
          'lastSetCompletedAt': lastSetCompletedAt!.toIso8601String(),
        if (restEndedAt != null) 'restEndedAt': restEndedAt!.toIso8601String(),
      };

  factory ActiveWorkoutSession.fromJson(Map<String, dynamic> json) {
    final exercises = ((json['exercises'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              ActiveWorkoutExercise.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
    final rawIndex = (json['currentExerciseIndex'] as num?)?.toInt() ?? 0;
    return ActiveWorkoutSession(
      id: json['id']?.toString() ??
          'active_${DateTime.now().microsecondsSinceEpoch}',
      planId: json['planId']?.toString() ?? '',
      planName: json['planName']?.toString() ?? 'Trening',
      weekday: (json['weekday'] as num?)?.toInt() ?? DateTime.monday,
      dayTitle: json['dayTitle']?.toString() ?? 'Trening',
      dayIndex: (json['dayIndex'] as num?)?.toInt() ?? -1,
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      currentExerciseIndex:
          exercises.isEmpty ? 0 : rawIndex.clamp(0, exercises.length - 1),
      exercises: exercises,
      note: json['note']?.toString() ?? '',
      restTimerEndsAt:
          DateTime.tryParse(json['restTimerEndsAt']?.toString() ?? ''),
      restTimerRemainingSeconds:
          (json['restTimerRemainingSeconds'] as num?)?.toInt() ?? 0,
      restTimerTotalSeconds:
          (json['restTimerTotalSeconds'] as num?)?.toInt() ?? 0,
      isRestTimerPaused: json['isRestTimerPaused'] as bool? ?? false,
      isPaused: json['isPaused'] as bool? ?? false,
      pausedByBackground: json['pausedByBackground'] as bool? ?? false,
      // Zgodność wsteczna: starszy zapis bez odcinków — aktywny trening zaczyna
      // liczyć czas od startedAt (żeby netto miało sens), pauza od zapisu.
      activeSegmentStartedAt:
          DateTime.tryParse(json['activeSegmentStartedAt']?.toString() ?? '') ??
              ((json['isPaused'] as bool? ?? false)
                  ? null
                  : (DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
                      DateTime.now())),
      accumulatedActiveSeconds:
          (json['accumulatedActiveSeconds'] as num?)?.toInt() ?? 0,
      accumulatedPauseSeconds:
          (json['accumulatedPauseSeconds'] as num?)?.toInt() ?? 0,
      pauseStartedAt:
          DateTime.tryParse(json['pauseStartedAt']?.toString() ?? ''),
      partCount: (json['partCount'] as num?)?.toInt() ?? 1,
      lastSetCompletedAt:
          DateTime.tryParse(json['lastSetCompletedAt']?.toString() ?? ''),
      restEndedAt: DateTime.tryParse(json['restEndedAt']?.toString() ?? ''),
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
    this.prescription,
  });

  final String exerciseId;

  /// Efektywna liczba serii dla tej sesji (rekomendacja albo plan bazowy).
  final int plannedSets;

  /// Efektywna liczba powtórzeń dla tej sesji.
  final int plannedReps;

  /// Efektywny ciężar roboczy (kg) dla tej sesji.
  final double suggestedWeightKg;

  /// Efektywna przerwa (s) dla tej sesji.
  final int restSeconds;
  final String note;
  final List<WorkoutSet> completedSets;
  final bool isSkipped;

  /// Recepta sesji: baza + rekomendacja + kontekst (Etap: rekomendacje przed
  /// wykonaniem). `null` dla starszych/ad-hoc sesji bez snapshotu.
  final SessionPrescription? prescription;

  double get volume => completedSets.fold<double>(
        0,
        (sum, set) => sum + set.volume,
      );

  /// Efektywny czas serii (s) używany przez timer/panel: ręczne nadpisanie →
  /// rekomendacja z recepty → [fallback] (np. domyślny czas ćwiczenia).
  int effectiveDurationSec(int fallback) {
    final rx = prescription;
    if (rx != null && rx.effectiveDurationSec > 0)
      return rx.effectiveDurationSec;
    return fallback;
  }

  ActiveWorkoutExercise copyWith({
    String? exerciseId,
    int? plannedSets,
    int? plannedReps,
    double? suggestedWeightKg,
    int? restSeconds,
    String? note,
    List<WorkoutSet>? completedSets,
    bool? isSkipped,
    SessionPrescription? prescription,
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
      prescription: prescription ?? this.prescription,
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
        if (prescription != null) 'prescription': prescription!.toJson(),
      };

  factory ActiveWorkoutExercise.fromJson(Map<String, dynamic> json) =>
      ActiveWorkoutExercise(
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
        prescription: json['prescription'] is Map
            ? SessionPrescription.fromJson(
                Map<String, dynamic>.from(json['prescription'] as Map))
            : null,
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
    this.planId = '',
    this.dayIndex = -1,
    this.dayLabel = '',
    this.skippedCount = 0,
    this.totalDistanceMeters = 0,
    this.netActiveSeconds = 0,
    this.pauseSeconds = 0,
    this.partCount = 1,
    this.completionStatus = 'completed',
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

  /// Powiązanie z programem (Etap 31) — do aktualizacji postępu i opcji „powtórz/cofnij".
  final String planId;
  final int dayIndex;
  final String dayLabel;

  /// Liczba pominiętych ćwiczeń w sesji.
  final int skippedCount;

  /// Łączny dystans z serii cardio (metry); 0 gdy trening bez cardio.
  final double totalDistanceMeters;

  /// Aktywny czas netto (bez pauz i tła), w sekundach.
  final int netActiveSeconds;

  /// Łączny czas pauz i tła (s).
  final int pauseSeconds;

  /// Liczba części treningu (po długiej przerwie > 1).
  final int partCount;

  /// Status ukończenia: 'completed' | 'partial' | 'interrupted'.
  final String completionStatus;

  /// Czas brutto od uruchomienia do zakończenia.
  Duration get duration => endedAt.difference(startedAt);

  /// Aktywny czas netto jako [Duration].
  Duration get activeDuration => Duration(seconds: netActiveSeconds);

  /// Czas pauz jako [Duration].
  Duration get pauseDuration => Duration(seconds: pauseSeconds);

  bool get isPartial => completionStatus != 'completed';
}
