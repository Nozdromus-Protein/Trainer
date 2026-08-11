/// Personalizacja modelu regeneracji (spec: punkt 6).
///
/// ZASADA: literatura jest PUNKTEM STARTOWYM, nie wyrocznią dla każdego.
/// Model bazowy ([RecoveryEngine]) jest deterministyczny i wspólny; ta warstwa
/// dokłada do niego niewielkie, indywidualne korekty stałych czasowych na
/// podstawie tego, jak użytkownik NAPRAWDĘ znosi kolejne treningi.
///
/// Świadomie NIE używamy tu uczenia maszynowego. Zamiast tego:
///  * porównujemy PROGNOZĘ gotowości sprzed sesji z REALNĄ wydajnością w tej
///    sesji (ciężar, powtórzenia, odczuwany wysiłek),
///  * aktualizujemy korektę małym krokiem (średnia wykładnicza),
///  * wymagamy minimalnej liczby obserwacji, zanim korekta zacznie działać,
///  * twardo ograniczamy zakres korekty,
///  * ignorujemy obserwacje o niskiej jakości danych.
///
/// Dzięki temu jeden dziwny trening nie przestawi profilu użytkownika.
library;

import 'dart:math' as math;

import '../domain/exercise.dart';
import '../domain/muscle_readiness.dart';
import '../domain/workout_session.dart';

/// Wydajność JEDNEGO ćwiczenia w sesji względem poprzedniego wykonania.
class ExercisePerformanceDelta {
  const ExercisePerformanceDelta({
    required this.exerciseId,
    required this.performanceDelta,
    required this.rpeDelta,
    required this.confidence,
    this.hasReference = false,
  });

  final String exerciseId;

  /// Względna zmiana wydajności: 0.0 = tak samo, +0.05 = o 5% lepiej.
  /// Liczona z tonażu najlepszej serii (ciężar × powtórzenia) albo z czasu
  /// pracy dla ćwiczeń czasowych.
  final double performanceDelta;

  /// Zmiana odczuwanego wysiłku: dodatnia = było ciężej niż poprzednio.
  final double rpeDelta;

  /// Jakość danych obserwacji 0–1.
  final double confidence;

  /// Czy w ogóle było z czym porównać.
  final bool hasReference;
}

/// Obserwacja gotowości JEDNEJ partii: co model przewidział vs. co się stało.
class ReadinessObservation {
  const ReadinessObservation({
    required this.muscle,
    required this.predictedReadiness,
    required this.performanceDelta,
    required this.rpeDelta,
    required this.confidence,
  });

  final BodyMuscle muscle;

  /// Gotowość, jaką model przewidywał NA POCZĄTKU sesji (0–100).
  final double predictedReadiness;

  final double performanceDelta;
  final double rpeDelta;
  final double confidence;

  /// Błąd modelu w skali −1…+1.
  ///
  ///  * `> 0` — model był ZBYT OPTYMISTYCZNY (obiecywał gotowość, a wydajność
  ///    spadła) → regeneracja trwa dłużej, niż zakłada model → wydłużamy stałe,
  ///  * `< 0` — model był ZBYT KONSERWATYWNY (straszył zmęczeniem, a użytkownik
  ///    powtórzył wynik bez pogorszenia) → skracamy stałe,
  ///  * `0` — brak wyraźnego sygnału; nie uczymy się z niczego.
  double get error {
    final droppedPerformance = performanceDelta <= -0.05 || rpeDelta >= 1.0;
    final heldPerformance = performanceDelta >= -0.01 && rpeDelta <= 0.5;

    if (predictedReadiness >= 85 && droppedPerformance) {
      // Im pewniejsza była prognoza, tym większy błąd.
      final magnitude = ((predictedReadiness - 85) / 15).clamp(0.0, 1.0);
      final drop = math.max(
        (-performanceDelta).clamp(0.0, 0.3) / 0.3,
        (rpeDelta / 2.0).clamp(0.0, 1.0),
      );
      return (0.4 + 0.6 * magnitude) * drop;
    }
    if (predictedReadiness <= 78 && heldPerformance) {
      final magnitude = ((78 - predictedReadiness) / 30).clamp(0.0, 1.0);
      return -(0.4 + 0.6 * magnitude);
    }
    return 0;
  }
}

/// Serwis kalibracji: obserwacje → nowy profil korekt.
class RecoveryPersonalizationService {
  const RecoveryPersonalizationService();

  /// Ile ostatnich sesji danego ćwiczenia bierzemy do porównania wydajności.
  static const int comparisonWindowSessions = 4;

  /// Aktualizuje profil kalibracji o obserwacje z jednej sesji.
  RecoveryCalibrationProfile apply(
    RecoveryCalibrationProfile profile,
    Iterable<ReadinessObservation> observations, {
    DateTime? at,
  }) {
    var result = profile;
    for (final observation in observations) {
      final error = observation.error;
      if (error == 0) continue;
      final current = result.forMuscle(observation.muscle);
      result = result.withMuscle(
        observation.muscle,
        current.updated(
          error: error,
          weight: observation.confidence,
          at: at,
        ),
      );
    }
    return result;
  }

  /// Buduje obserwacje dla partii obciążonych w zakończonej sesji.
  ///
  /// [sessionLogs]      — wpisy zapisane w tej sesji,
  /// [history]          — historia SPRZED tej sesji (do porównania wydajności),
  /// [predictedAtStart] — gotowość policzona modelem na moment startu sesji.
  List<ReadinessObservation> observationsFor({
    required List<WorkoutLog> sessionLogs,
    required List<WorkoutLog> history,
    required Map<BodyMuscle, double> predictedAtStart,
    required Exercise Function(String id) resolveExercise,
  }) {
    if (sessionLogs.isEmpty || predictedAtStart.isEmpty) return const [];

    // 1. Wydajność per ćwiczenie względem poprzedniego wykonania.
    final deltas = <String, ExercisePerformanceDelta>{};
    for (final log in sessionLogs) {
      final delta = _deltaFor(log, history, resolveExercise(log.exerciseId));
      if (delta.hasReference) deltas[log.exerciseId] = delta;
    }
    if (deltas.isEmpty) return const [];

    // 2. Przeniesienie wydajności na partie — ważone udziałem partii
    //    w ćwiczeniu (tylko partie GŁÓWNE niosą wiarygodny sygnał; wydajność
    //    wyciskania nie mówi wiele o stanie tricepsa).
    final performanceByMuscle = <BodyMuscle, List<ExercisePerformanceDelta>>{};
    for (final entry in deltas.entries) {
      final exercise = resolveExercise(entry.key);
      for (final impact in exercise.effectiveMuscleImpacts) {
        if (impact.role != MuscleRole.primary) continue;
        performanceByMuscle
            .putIfAbsent(impact.muscleGroup, () => [])
            .add(entry.value);
      }
    }

    final observations = <ReadinessObservation>[];
    performanceByMuscle.forEach((muscle, list) {
      final predicted = predictedAtStart[muscle];
      if (predicted == null) return;
      var performance = 0.0;
      var rpe = 0.0;
      var confidence = 0.0;
      for (final delta in list) {
        performance += delta.performanceDelta * delta.confidence;
        rpe += delta.rpeDelta * delta.confidence;
        confidence += delta.confidence;
      }
      if (confidence <= 0.2) return;
      observations.add(ReadinessObservation(
        muscle: muscle,
        predictedReadiness: predicted,
        performanceDelta: performance / confidence,
        rpeDelta: rpe / confidence,
        // Więcej ćwiczeń na partię = pewniejsza obserwacja, ale nigdy 100%.
        confidence: (confidence / list.length).clamp(0.0, 1.0).toDouble() *
            (list.length >= 2 ? 1.0 : 0.75),
      ));
    });
    return observations;
  }

  /// Porównanie jednego wpisu z jego poprzednimi wykonaniami.
  ExercisePerformanceDelta _deltaFor(
    WorkoutLog log,
    List<WorkoutLog> history,
    Exercise exercise,
  ) {
    final previous = <WorkoutLog>[
      for (final entry in history)
        if (entry.exerciseId == log.exerciseId &&
            entry.sessionId != log.sessionId)
          entry,
    ]..sort(
        (a, b) => b.effectivePerformedAt.compareTo(a.effectivePerformedAt));
    if (previous.isEmpty) {
      return ExercisePerformanceDelta(
        exerciseId: log.exerciseId,
        performanceDelta: 0,
        rpeDelta: 0,
        confidence: 0,
      );
    }
    final reference = previous.take(comparisonWindowSessions).toList();

    double scoreOf(WorkoutLog entry) {
      final entryType = exercise.entryType;
      if (entryType.showsDuration && !entryType.showsReps) {
        var seconds = 0;
        for (final set in entry.workoutSets) {
          if (!set.countsForProgress) continue;
          seconds += set.activeSeconds > 0 ? set.activeSeconds : set.durationSec;
        }
        return (seconds > 0 ? seconds : entry.durationSec).toDouble();
      }
      // Najlepsza seria: ciężar × powtórzenia (dla masy ciała same powtórzenia).
      var best = 0.0;
      for (final set in entry.workoutSets) {
        if (!set.countsForProgress) continue;
        final value = (set.weightKg <= 0 ? 1.0 : set.weightKg) *
            (set.repetitions <= 0 ? 1 : set.repetitions);
        if (value > best) best = value;
      }
      if (best <= 0) {
        best = (entry.weightKg <= 0 ? 1.0 : entry.weightKg) *
            (entry.reps <= 0 ? 1 : entry.reps);
      }
      return best;
    }

    double rpeOf(WorkoutLog entry) {
      var sum = 0.0;
      var count = 0;
      for (final set in entry.workoutSets) {
        final value = set.estimatedRpe > 0
            ? set.estimatedRpe
            : (set.rpe > 0 ? set.rpe.toDouble() : 0);
        if (value > 0 && set.countsForProgress) {
          sum += value;
          count++;
        }
      }
      if (count > 0) return sum / count;
      return entry.rpe > 0 ? entry.rpe.toDouble() : 0;
    }

    final current = scoreOf(log);
    var referenceScore = 0.0;
    for (final entry in reference) {
      final value = scoreOf(entry);
      if (value > referenceScore) referenceScore = value;
    }
    if (referenceScore <= 0 || current <= 0) {
      return ExercisePerformanceDelta(
        exerciseId: log.exerciseId,
        performanceDelta: 0,
        rpeDelta: 0,
        confidence: 0,
      );
    }

    final currentRpe = rpeOf(log);
    final referenceRpe = rpeOf(reference.first);
    final rpeKnown = currentRpe > 0 && referenceRpe > 0;

    // Jakość obserwacji: dane serii + znane RPE + świeżość odniesienia.
    var confidence = 0.45;
    if (log.workoutSets.isNotEmpty) confidence += 0.2;
    if (rpeKnown) confidence += 0.25;
    final daysApart = log.effectivePerformedAt
        .difference(reference.first.effectivePerformedAt)
        .inDays
        .abs();
    if (daysApart > 21) confidence -= 0.25;

    return ExercisePerformanceDelta(
      exerciseId: log.exerciseId,
      performanceDelta:
          ((current - referenceScore) / referenceScore).clamp(-1.0, 1.0),
      rpeDelta: rpeKnown ? (currentRpe - referenceRpe) : 0,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      hasReference: true,
    );
  }
}
