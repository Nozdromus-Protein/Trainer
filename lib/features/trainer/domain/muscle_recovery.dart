/// Modele i kalkulator regeneracji mięśni (Etap mapy regeneracji).
///
/// Czysty Dart — kolory nakładane są w UI na podstawie [MuscleRecoveryState.recoveryPercent].
library;

import 'exercise.dart';
import 'workout_session.dart';

/// Status regeneracji partii mięśniowej.
enum RecoveryStatus {
  unknown('Brak danych'),
  freshFatigue('Świeże zmęczenie'),
  heavyFatigue('Mocne zmęczenie'),
  recovering('Regeneracja w toku'),
  almostRecovered('Prawie zregenerowane'),
  recovered('Zregenerowane');

  const RecoveryStatus(this.label);

  final String label;
}

/// Mapuje procent regeneracji na status (null → unknown).
RecoveryStatus recoveryStatusForPercent(double? percent) {
  if (percent == null) return RecoveryStatus.unknown;
  if (percent <= 20) return RecoveryStatus.freshFatigue;
  if (percent <= 40) return RecoveryStatus.heavyFatigue;
  if (percent <= 60) return RecoveryStatus.recovering;
  if (percent <= 80) return RecoveryStatus.almostRecovered;
  return RecoveryStatus.recovered;
}

/// Stan regeneracji pojedynczej partii.
class MuscleRecoveryState {
  const MuscleRecoveryState({
    required this.muscleGroup,
    this.recoveryPercent,
    this.fatiguePercent,
    this.lastTrainedAt,
    this.estimatedFullRecoveryAt,
    this.estimatedHoursRemaining = 0,
    this.lastWorkoutId = '',
    this.lastExerciseNames = const [],
    this.loadScore = 0,
    this.sorenessNote = '',
    this.status = RecoveryStatus.unknown,
  });

  final BodyMuscle muscleGroup;
  final double? recoveryPercent;
  final double? fatiguePercent;
  final DateTime? lastTrainedAt;
  final DateTime? estimatedFullRecoveryAt;
  final int estimatedHoursRemaining;
  final String lastWorkoutId;
  final List<String> lastExerciseNames;
  final double loadScore;
  final String sorenessNote;
  final RecoveryStatus status;

  /// Brak danych = mięsień nigdy nie trenowany w oknie analizy → szary.
  factory MuscleRecoveryState.unknown(BodyMuscle muscle) =>
      MuscleRecoveryState(muscleGroup: muscle);

  bool get hasData => recoveryPercent != null && status != RecoveryStatus.unknown;

  String get statusLabel => status.label;

  /// Alias zgodny z opisem etapu — „colorState" to bucket statusu (kolor liczony w UI).
  RecoveryStatus get colorState => status;
}

/// Lokalna sugestia treningowa dla partii (bez AI).
String recoverySuggestionForMuscle(MuscleRecoveryState state) {
  switch (state.status) {
    case RecoveryStatus.unknown:
      return 'Brak danych — wykonaj trening, aby śledzić regenerację tej partii.';
    case RecoveryStatus.freshFatigue:
    case RecoveryStatus.heavyFatigue:
      return 'Mocno zmęczona — dziś lepiej odpuść tę partię albo zrób lżejszą wersję.';
    case RecoveryStatus.recovering:
      return 'Regeneracja w toku — możliwy lekki trening, bez maksymalnej intensywności.';
    case RecoveryStatus.almostRecovered:
      return 'Prawie gotowe — niedługo można obciążyć tę partię mocniej.';
    case RecoveryStatus.recovered:
      return 'Zregenerowane — partia gotowa do pełnego treningu.';
  }
}

class _MuscleAggregate {
  _MuscleAggregate(this.lastTrainedAt);
  double load = 0;
  DateTime lastTrainedAt;
  String lastWorkoutId = '';
  final Set<String> exerciseNames = {};
}

/// Liczy stan regeneracji partii na podstawie historii treningów.
///
/// Ćwiczenia pominięte nie trafiają do [logs] (zapisywane są tylko wykonane),
/// więc nie obciążają mięśni. Ćwiczenia bez przypisanych partii są ignorowane.
class RecoveryCalculator {
  const RecoveryCalculator({this.analysisWindow = const Duration(hours: 96)});

  /// Okno analizy — starsze treningi traktujemy jako w pełni zregenerowane.
  final Duration analysisWindow;

  Map<BodyMuscle, MuscleRecoveryState> compute({
    required List<WorkoutLog> logs,
    required Exercise Function(String id) resolveExercise,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(analysisWindow);
    final aggregates = <BodyMuscle, _MuscleAggregate>{};

    for (final log in logs) {
      if (log.date.isBefore(cutoff)) continue;
      final exercise = resolveExercise(log.exerciseId);
      final impacts = exercise.effectiveMuscleImpacts;
      if (impacts.isEmpty) continue;
      final unit = _logLoadUnit(log);
      for (final impact in impacts) {
        final agg = aggregates.putIfAbsent(
          impact.muscleGroup,
          () => _MuscleAggregate(log.date),
        );
        agg.load += unit * impact.effectiveWeight;
        if (!log.date.isBefore(agg.lastTrainedAt)) {
          agg.lastTrainedAt = log.date;
          if (log.sessionId.isNotEmpty) agg.lastWorkoutId = log.sessionId;
        }
        agg.exerciseNames.add(exercise.name);
      }
    }

    final result = <BodyMuscle, MuscleRecoveryState>{};
    aggregates.forEach((muscle, agg) {
      result[muscle] = _stateFor(muscle, agg, reference);
    });
    return result;
  }

  double _logLoadUnit(WorkoutLog log) {
    final sets = log.sets <= 0 ? 1 : log.sets;
    final reps = log.reps <= 0 ? 8 : log.reps;
    final base = sets * (0.5 + reps / 18.0);
    final rpeFactor = log.rpe > 0 ? (0.6 + log.rpe / 12.0) : 1.0;
    final weightFactor = log.weightKg > 0 ? (1 + log.weightKg / 140.0) : 1.0;
    final durationFactor = log.durationSec > 0 ? (1 + log.durationSec / 2400.0) : 1.0;
    final value = base * rpeFactor * weightFactor * durationFactor;
    return value.clamp(0.3, 30.0);
  }

  MuscleRecoveryState _stateFor(BodyMuscle muscle, _MuscleAggregate agg, DateTime now) {
    // Większe obciążenie → dłuższe okno regeneracji (24–90 h).
    final windowHours = (28 + agg.load * 2.5).clamp(24.0, 90.0);
    final hoursSince = now.difference(agg.lastTrainedAt).inMinutes / 60.0;
    final recoveryPercent = (hoursSince / windowHours * 100).clamp(0.0, 100.0);
    final fullAt = agg.lastTrainedAt.add(Duration(minutes: (windowHours * 60).round()));
    final remaining = (windowHours - hoursSince).clamp(0.0, 1000.0);
    return MuscleRecoveryState(
      muscleGroup: muscle,
      recoveryPercent: recoveryPercent,
      fatiguePercent: 100 - recoveryPercent,
      lastTrainedAt: agg.lastTrainedAt,
      estimatedFullRecoveryAt: fullAt,
      estimatedHoursRemaining: remaining.round(),
      lastWorkoutId: agg.lastWorkoutId,
      lastExerciseNames: agg.exerciseNames.toList(),
      loadScore: agg.load,
      status: recoveryStatusForPercent(recoveryPercent),
    );
  }
}
