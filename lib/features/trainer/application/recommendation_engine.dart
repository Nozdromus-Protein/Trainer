/// Silnik rekomendacji treningowych (spec: punkty 16, 17, 27).
///
/// Rekomendacja to NIE są trzy liczby („3 serie, 10 powtórzeń, 40 kg").
/// To decyzja: *co dziś zrobić z tym ćwiczeniem i dlaczego*. Silnik składa ją
/// z warstw, które już istnieją w aplikacji, i dokłada brakujące ogniwo —
/// GOTOWOŚĆ z modelu regeneracji oraz WYTŁUMACZALNOŚĆ.
///
///   plan bazowy programu
///        ↓
///   dobór trenera ([recommendSet]: historia, progresja, sufity ciężaru)
///        ↓
///   gotowość partii ([MuscleReadiness] dla PLANOWANEGO rodzaju bodźca)
///        ↓
///   kontekst (sen, odżywianie, zmęczenie ogólne, obciążenie tygodnia)
///        ↓
///   decyzja + parametry + powody + pewność
///
/// Silnik NIGDY nie blokuje treningu — może obniżyć rekomendację i wyjaśnić
/// dlaczego, ale wykonanie zestawu zostaje decyzją użytkownika (spec 34).
library;

import 'dart:math' as math;

import '../domain/exercise.dart';
import '../domain/muscle_recovery.dart';
import '../domain/session_prescription.dart';
import '../domain/workout_session.dart';
import 'training_coach.dart';

/// Decyzja rekomendacji na dziś.
enum RecommendationDecision {
  progress('PROGRESS', 'Progresja', 'Dokładamy — parametry i regeneracja na to pozwalają.'),
  maintain('MAINTAIN', 'Utrzymanie', 'Powtarzamy ostatnie parametry i utrwalamy technikę.'),
  reduce('REDUCE', 'Zmniejszenie', 'Dziś mniej — gotowość albo wydajność na to wskazują.'),
  deload('DELOAD', 'Deload', 'Tydzień odciążenia — świadomie schodzimy z obciążenia.'),
  recoverySession('RECOVERY_SESSION', 'Sesja regeneracyjna',
      'Lekka praca dla przepływu krwi i techniki, bez kosztu zmęczeniowego.');

  const RecommendationDecision(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static RecommendationDecision fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final decision in RecommendationDecision.values) {
      if (decision.key == key || decision.name == key) return decision;
    }
    return RecommendationDecision.maintain;
  }

  bool get lowersLoad =>
      this == RecommendationDecision.reduce ||
      this == RecommendationDecision.deload ||
      this == RecommendationDecision.recoverySession;
}

/// Kontekst regeneracyjno-bytowy przekazywany do rekomendacji.
class RecommendationContext {
  const RecommendationContext({
    this.readinessByMuscle = const {},
    this.environment = RecoveryEnvironment.unknown,
    this.systemicFatigue = 0,
    this.acuteChronicRatio = 1.0,
    this.hasLoadBaseline = false,
    this.isDeloadWeek = false,
    this.cycleIntensity = 1.0,
  });

  /// Gotowość partii (z [RecoveryEngine]).
  final Map<BodyMuscle, MuscleRecoveryState> readinessByMuscle;

  final RecoveryEnvironment environment;

  /// Zmęczenie ogólnoustrojowe 0–1.
  final double systemicFatigue;

  /// Obciążenie ostre / przewlekłe (1.0 = jak zwykle).
  final double acuteChronicRatio;
  final bool hasLoadBaseline;

  final bool isDeloadWeek;
  final double cycleIntensity;
}

/// Pełna, wytłumaczalna rekomendacja jednego ćwiczenia.
class ExerciseRecommendation {
  const ExerciseRecommendation({
    required this.prescription,
    required this.decision,
    required this.reasons,
    required this.confidence,
    required this.targetRir,
    this.previousSummary = '',
    this.deltaSummary = '',
    this.stimulusKind = TrainingStimulusKind.hypertrophy,
    this.limitingMuscle,
    this.limitingReadiness = 100,
    this.suggestedSetDelta = 0,
    this.volumeAdvice = '',
  });

  final Prescription prescription;
  final RecommendationDecision decision;

  /// Powody „+"/„−" — UI tłumaczy je na język naturalny (spec 17).
  final List<ReadinessReason> reasons;

  /// Pewność rekomendacji 0–1 (spec 7).
  final double confidence;

  /// Docelowy zapas powtórzeń do upadku.
  final int targetRir;

  /// Krótki opis poprzedniego wykonania („90 kg × 10 × 3, RPE 8,5").
  final String previousSummary;

  /// Co się zmieniło względem ostatniego treningu („+2,5 kg").
  final String deltaSummary;

  /// Rodzaj bodźca, do którego dopasowano rekomendację.
  final TrainingStimulusKind stimulusKind;

  /// Partia, która najbardziej ograniczyła rekomendację (jeśli jakaś).
  final BodyMuscle? limitingMuscle;
  final double limitingReadiness;

  /// SUGEROWANA zmiana liczby serii (ujemna = rekomendujemy mniej).
  /// Nie jest stosowana automatycznie — plan zostaje taki, jak zaplanowany.
  final int suggestedSetDelta;

  /// Zdanie o objętości do pokazania użytkownikowi ('' = brak uwag).
  final String volumeAdvice;

  String get confidenceLabel {
    if (confidence >= 0.75) return 'wysoka';
    if (confidence >= 0.5) return 'średnia';
    return 'niska';
  }

  int get confidencePercent => (confidence * 100).round();

  List<ReadinessReason> get positiveReasons =>
      [for (final reason in reasons) if (reason.positive) reason];

  List<ReadinessReason> get negativeReasons =>
      [for (final reason in reasons) if (!reason.positive) reason];
}

/// Sygnały przemawiające za deloadem (spec 27).
///
/// Deload NIE wynika z jednego słabego dnia — potrzeba zbieżności kilku
/// sygnałów w dłuższym oknie.
class DeloadSignals {
  const DeloadSignals({
    this.performanceDropSessions = 0,
    this.elevatedRpeSessions = 0,
    this.lowReadinessMuscles = 0,
    this.acuteChronicRatio = 1.0,
    this.systemicFatigue = 0,
    this.reasons = const [],
  });

  final int performanceDropSessions;
  final int elevatedRpeSessions;
  final int lowReadinessMuscles;
  final double acuteChronicRatio;
  final double systemicFatigue;
  final List<String> reasons;

  /// Ile niezależnych sygnałów się zapaliło.
  int get score {
    var value = 0;
    if (performanceDropSessions >= 2) value++;
    if (elevatedRpeSessions >= 3) value++;
    if (lowReadinessMuscles >= 4) value++;
    if (acuteChronicRatio >= 1.6) value++;
    if (systemicFatigue >= 0.55) value++;
    return value;
  }

  /// Kandydat na deload dopiero przy ≥3 zbieżnych sygnałach.
  bool get isCandidate => score >= 3;

  /// Warto uważać, ale to jeszcze nie deload.
  bool get isWatch => score == 2;
}

/// Silnik rekomendacji.
class RecommendationEngine {
  const RecommendationEngine();

  /// Rodzaj bodźca wynikający z celu treningowego i planu ćwiczenia.
  static TrainingStimulusKind stimulusKindFor({
    required String goal,
    required int plannedReps,
    required Exercise exercise,
  }) {
    final entryType = exercise.entryType;
    if (entryType == ExerciseEntryType.mobility) {
      return TrainingStimulusKind.activeRecovery;
    }
    final range = targetRepRange(goal);
    if (range.max <= 6 || (plannedReps >= 1 && plannedReps <= 5)) {
      return TrainingStimulusKind.maxStrength;
    }
    if (range.min >= 12) return TrainingStimulusKind.moderate;
    return TrainingStimulusKind.hypertrophy;
  }

  /// Docelowy zapas powtórzeń (RIR) na dziś.
  ///
  /// Refalo 2023 (PMID 36752989): 3-RIR, 1-RIR i upadek dają WYRAŹNIE różne
  /// koszty zmęczeniowe. Skoro tak, cel RIR musi zależeć od gotowości i fazy
  /// cyklu, a nie być stałą wpisaną w program.
  static int targetRirFor({
    required double readinessPercent,
    required RecommendationDecision decision,
    required bool isDeloadWeek,
  }) {
    if (isDeloadWeek || decision == RecommendationDecision.deload) return 4;
    if (decision == RecommendationDecision.recoverySession) return 5;
    if (readinessPercent >= 88) return 2;
    if (readinessPercent >= 72) return 2;
    if (readinessPercent >= 55) return 3;
    return 4;
  }

  /// Buduje rekomendację ćwiczenia na tę sesję.
  ExerciseRecommendation build({
    required Exercise exercise,
    required SetRecommendation coachRecommendation,
    required Prescription base,
    required CoachContext ctx,
    required List<CoachHistorySample> history,
    required RecommendationContext context,
    DeloadSignals deloadSignals = const DeloadSignals(),
  }) {
    final kind = stimulusKindFor(
      goal: ctx.goal,
      plannedReps: coachRecommendation.reps,
      exercise: exercise,
    );

    // --- Gotowość partii istotnych dla ćwiczenia ---
    BodyMuscle? limiting;
    var limitingReadiness = 100.0;
    var secondaryFatigue = <BodyMuscle, double>{};
    for (final impact in exercise.effectiveMuscleImpacts) {
      if (impact.role == MuscleRole.stabilizer) continue;
      final state = context.readinessByMuscle[impact.muscleGroup];
      if (state == null || !state.hasData) continue;
      final percent = state.readinessFor(kind);
      if (impact.role == MuscleRole.primary) {
        if (percent < limitingReadiness) {
          limitingReadiness = percent;
          limiting = impact.muscleGroup;
        }
      } else if (percent < 65) {
        secondaryFatigue[impact.muscleGroup] = percent;
      }
    }

    final reasons = <ReadinessReason>[];
    void add(String code, String label, bool positive, [double weight = 0.5]) =>
        reasons.add(ReadinessReason(
            code: code, label: label, positive: positive, weight: weight));

    // --- Decyzja ---
    var decision = _decisionFrom(
      coachRecommendation: coachRecommendation,
      history: history,
      readiness: limitingReadiness,
      context: context,
      deloadSignals: deloadSignals,
    );

    // --- Parametry po korekcie gotowością ---
    var sets = coachRecommendation.sets;
    var reps = coachRecommendation.reps;
    var weight = coachRecommendation.weightKg;
    var duration = coachRecommendation.durationSec;
    var rest = coachRecommendation.restSeconds;

    // WAŻNA ZASADA (spec 34): silnik obniża INTENSYWNOŚĆ i podnosi zapas do
    // upadku, ale NIE wycina użytkownikowi zaplanowanych serii ani czasu pracy.
    // Objętość jest sugerowana jako rekomendacja ([suggestedSetDelta]) —
    // decyzja, czy odpuścić serię, należy do użytkownika.
    var suggestedSetDelta = 0;
    var volumeAdvice = '';
    switch (decision) {
      case RecommendationDecision.recoverySession:
        if (weight > 0) {
          weight = roundToPlate(weight * 0.6,
              step: safeWeightStepKg(exercise, ctx.level));
        }
        suggestedSetDelta = sets >= 3 ? -2 : (sets >= 2 ? -1 : 0);
        volumeAdvice =
            'Rekomendowana sesja regeneracyjna: lekki ciężar i o ${suggestedSetDelta.abs()} '
            '${suggestedSetDelta.abs() == 1 ? 'serię' : 'serie'} mniej.';
        add('lowReadiness',
            'Gotowość ${limitingReadiness.round()}% — proponuję sesję regeneracyjną',
            false, 1.0);
        break;
      case RecommendationDecision.deload:
        if (weight > 0) {
          weight = roundToPlate(weight * 0.75,
              step: safeWeightStepKg(exercise, ctx.level));
        }
        suggestedSetDelta = sets >= 3 ? -1 : 0;
        volumeAdvice = 'Deload — pracuj lżej i nie goń objętości.';
        add('deloadWeek', 'Tydzień deloadu — świadome odciążenie', false, 0.9);
        break;
      case RecommendationDecision.reduce:
        if (weight > 0) {
          weight = roundToPlate(weight * 0.9,
              step: safeWeightStepKg(exercise, ctx.level));
        } else if (reps > 1) {
          reps = math.max(1, reps - 1);
        }
        if (sets >= 3) {
          suggestedSetDelta = -1;
          volumeAdvice = 'Rozważ jedną serię mniej — gotowość nie jest pełna.';
        }
        break;
      case RecommendationDecision.progress:
      case RecommendationDecision.maintain:
        break;
    }

    // Dłuższa przerwa, gdy partia nie jest w pełni gotowa — czas między seriami
    // jest najtańszym sposobem obniżenia kosztu sesji.
    if (limitingReadiness < 65 && rest > 0) {
      rest = (rest * 1.15).round();
    }

    final targetRir = targetRirFor(
      readinessPercent: limitingReadiness,
      decision: decision,
      isDeloadWeek: context.isDeloadWeek,
    );

    // --- Powody (spec 17) ---
    if (limiting != null) {
      if (limitingReadiness >= 85) {
        add('recoveredMuscle',
            '${limiting.label}: gotowość ${limitingReadiness.round()}%',
            true, 0.8);
      } else if (limitingReadiness < 60) {
        add('lowReadiness',
            '${limiting.label}: gotowość tylko ${limitingReadiness.round()}%',
            false, 1.0);
      } else {
        add('partialReadiness',
            '${limiting.label}: gotowość ${limitingReadiness.round()}%',
            false, 0.5);
      }
    }
    secondaryFatigue.forEach((muscle, percent) {
      add('secondaryMuscleFatigue',
          '${muscle.label} ma zmęczenie z poprzedniej sesji (${percent.round()}%)',
          false, 0.6);
    });
    if (history.length >= 2) {
      final last = history.last;
      if (last.allSetsCompleted) {
        add('performanceTrend', 'Poprzedni trening ukończony w całości', true,
            0.7);
      } else {
        add('performanceTrend', 'Poprzednio nie wszystkie serie wyszły', false,
            0.7);
      }
      if (last.rpeReliable && last.estimatedRpe > 0) {
        if (last.estimatedRpe >= 8.5) {
          add('previousRIR',
              'Ostatnio było bardzo ciężko (RPE ${_fmt(last.estimatedRpe)})',
              false, 0.6);
        } else if (last.estimatedRpe <= 7) {
          add('previousRIR',
              'Ostatnio zostawał zapas (RPE ${_fmt(last.estimatedRpe)})', true,
              0.6);
        }
      }
    } else {
      add('calibration', 'Za mało wykonań — Trainer jeszcze kalibruje', false,
          0.4);
    }
    final environment = context.environment;
    if (environment.hasSleepData) {
      if (environment.sleepFactor < 1.0) {
        add('poorSleep', 'Krótki sen tej nocy', false, 0.6);
      } else {
        add('goodSleep', 'Sen w normie', true, 0.4);
      }
    }
    if (environment.hasNutritionData && environment.energyFactor < 1.0) {
      add('energyDeficit', 'Deficyt energetyczny', false, 0.5);
    }
    if (context.systemicFatigue >= 0.5) {
      add('systemicFatigue', 'Wysokie zmęczenie ogólne', false, 0.7);
    }
    if (context.hasLoadBaseline && context.acuteChronicRatio >= 1.6) {
      add('loadSpike', 'Ten tydzień jest cięższy niż Twoja norma', false, 0.7);
    }
    reasons.sort((a, b) => b.weight.compareTo(a.weight));

    // --- Pewność rekomendacji ---
    var confidence = 0.35;
    confidence += (history.length / 8).clamp(0.0, 0.25);
    if (history.isNotEmpty && history.last.rpeReliable) confidence += 0.1;
    if (limiting != null) {
      confidence +=
          (context.readinessByMuscle[limiting]?.confidence ?? 0.4) * 0.25;
    }
    if (environment.hasSleepData) confidence += 0.04;
    if (environment.hasNutritionData) confidence += 0.04;
    if (coachRecommendation.isCalibrating) confidence -= 0.18;
    confidence = confidence.clamp(0.15, 0.95).toDouble();

    // --- Podsumowanie poprzedniego wykonania i delty ---
    final previousSummary = _previousSummary(history, exercise);
    final deltaSummary = _deltaSummary(
      history: history,
      exercise: exercise,
      weight: weight,
      reps: reps,
      duration: duration,
    );

    return ExerciseRecommendation(
      prescription: Prescription(
        sets: sets < 1 ? 1 : sets,
        reps: reps,
        weightKg: weight,
        durationSec: duration,
        restSeconds: rest,
      ),
      decision: decision,
      reasons: reasons,
      confidence: confidence,
      targetRir: targetRir,
      previousSummary: previousSummary,
      deltaSummary: deltaSummary,
      stimulusKind: kind,
      limitingMuscle: limiting,
      limitingReadiness: limitingReadiness,
      suggestedSetDelta: suggestedSetDelta,
      volumeAdvice: volumeAdvice,
    );
  }

  RecommendationDecision _decisionFrom({
    required SetRecommendation coachRecommendation,
    required List<CoachHistorySample> history,
    required double readiness,
    required RecommendationContext context,
    required DeloadSignals deloadSignals,
  }) {
    if (context.isDeloadWeek) return RecommendationDecision.deload;
    if (deloadSignals.isCandidate) return RecommendationDecision.deload;
    // Bardzo niska gotowość → sesja regeneracyjna. To REKOMENDACJA, nie zakaz:
    // użytkownik nadal może wejść w pełny zestaw (spec 12/34).
    if (readiness < 40) return RecommendationDecision.recoverySession;
    if (readiness < 62 || context.systemicFatigue >= 0.6) {
      return RecommendationDecision.reduce;
    }
    if (history.isEmpty) return RecommendationDecision.maintain;
    final last = history.last;
    if (!last.allSetsCompleted) return RecommendationDecision.reduce;
    // Progresja tylko wtedy, gdy trener realnie coś dołożył.
    final progressed = coachRecommendation.reasons.any((reason) =>
        reason.contains('proponuję +') ||
        reason.contains('dokładamy') ||
        reason.contains('Dokładamy'));
    if (progressed && readiness >= 72) return RecommendationDecision.progress;
    return RecommendationDecision.maintain;
  }

  String _previousSummary(
      List<CoachHistorySample> history, Exercise exercise) {
    if (history.isEmpty) return '';
    final last = history.last;
    final entryType = exercise.entryType;
    if (entryType.showsDuration && !entryType.showsReps) {
      if (last.durationSec <= 0) return '';
      return '${last.durationSec} s'
          '${last.rpeReliable && last.estimatedRpe > 0 ? ' · RPE ${_fmt(last.estimatedRpe)}' : ''}';
    }
    final parts = <String>[];
    if (last.weightKg > 0) parts.add('${_fmt(last.weightKg)} kg');
    if (last.reps > 0) parts.add('× ${last.reps}');
    if (last.rpeReliable && last.estimatedRpe > 0) {
      parts.add('· RPE ${_fmt(last.estimatedRpe)}');
    }
    return parts.join(' ');
  }

  String _deltaSummary({
    required List<CoachHistorySample> history,
    required Exercise exercise,
    required double weight,
    required int reps,
    required int duration,
  }) {
    if (history.isEmpty) return '';
    final last = history.last;
    final entryType = exercise.entryType;
    if (entryType.showsDuration && !entryType.showsReps) {
      if (last.durationSec <= 0 || duration <= 0) return '';
      final delta = duration - last.durationSec;
      if (delta == 0) return 'tyle samo co ostatnio';
      return '${delta > 0 ? '+' : ''}$delta s względem ostatniego treningu';
    }
    if (last.weightKg > 0 && weight > 0) {
      final delta = weight - last.weightKg;
      if (delta.abs() >= 0.05) {
        return '${delta > 0 ? '+' : ''}${_fmt(delta)} kg względem ostatniego treningu';
      }
    }
    if (last.reps > 0 && reps > 0 && reps != last.reps) {
      final delta = reps - last.reps;
      return '${delta > 0 ? '+' : ''}$delta powt. względem ostatniego treningu';
    }
    return 'te same parametry co ostatnio';
  }
}

/// Wykrywa sygnały deloadu z ostatnich tygodni (spec 27).
DeloadSignals detectDeloadSignals({
  required List<WorkoutLog> recentLogs,
  required Map<BodyMuscle, MuscleRecoveryState> readiness,
  required double systemicFatigue,
  required double acuteChronicRatio,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final window = reference.subtract(const Duration(days: 21));
  final relevant = [
    for (final log in recentLogs)
      if (!log.effectivePerformedAt.isBefore(window)) log,
  ]..sort((a, b) => a.effectivePerformedAt.compareTo(b.effectivePerformedAt));
  if (relevant.length < 4) return const DeloadSignals();

  // 1. Spadki wydajności: najlepsza seria ćwiczenia gorsza niż jego rekord
  //    z tego okna, w kolejnych sesjach.
  final bestByExercise = <String, double>{};
  final dropSessions = <String>{};
  final highRpeSessions = <String>{};
  for (final log in relevant) {
    final sessionKey = log.sessionId.trim().isNotEmpty
        ? log.sessionId
        : '${log.date.year}-${log.date.month}-${log.date.day}';
    final score = log.weightKg * (log.reps <= 0 ? 1 : log.reps);
    final best = bestByExercise[log.exerciseId] ?? 0;
    if (score > 0) {
      if (best > 0 && score < best * 0.93) dropSessions.add(sessionKey);
      if (score > best) bestByExercise[log.exerciseId] = score;
    }
    if (log.rpe >= 9) highRpeSessions.add(sessionKey);
  }

  final lowReadiness = readiness.values
      .where((state) => state.hasData && (state.recoveryPercent ?? 100) < 55)
      .length;

  final reasons = <String>[];
  if (dropSessions.length >= 2) {
    reasons.add('Spadek wydajności w ${dropSessions.length} sesjach.');
  }
  if (highRpeSessions.length >= 3) {
    reasons.add('Podwyższony wysiłek w ${highRpeSessions.length} sesjach.');
  }
  if (lowReadiness >= 4) {
    reasons.add('$lowReadiness partii poniżej 55% gotowości.');
  }
  if (acuteChronicRatio >= 1.6) {
    reasons.add('Ostatni tydzień wyraźnie cięższy niż Twoja norma.');
  }
  if (systemicFatigue >= 0.55) {
    reasons.add('Wysokie zmęczenie ogólnoustrojowe.');
  }

  return DeloadSignals(
    performanceDropSessions: dropSessions.length,
    elevatedRpeSessions: highRpeSessions.length,
    lowReadinessMuscles: lowReadiness,
    acuteChronicRatio: acuteChronicRatio,
    systemicFatigue: systemicFatigue,
    reasons: reasons,
  );
}

String _fmt(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
