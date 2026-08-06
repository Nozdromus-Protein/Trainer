/// Analiza jakości zestawu treningowego (czysty Dart, bez Fluttera).
///
/// Etap: „Sprawdzenie jakości zestawu" + „Analiza AI istniejących zestawów".
///
/// Moduł liczy ocenę 0–100 oraz rozbija ją na konkretne zalety i problemy,
/// zawsze na REALNYCH danych aplikacji: bazie ćwiczeń, profilu sprzętowym,
/// ograniczeniach, limitach objętości, regeneracji i dostępnym czasie.
/// Nie ma tu żadnych wywołań sieciowych ani losowości — ten sam zestaw
/// zawsze dostaje tę samą ocenę.
library;

import '../domain/equipment_profile.dart';
import '../domain/exercise.dart';
import '../domain/muscle_recovery.dart';
import '../domain/trainer_enums.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_volume_limits.dart';
import 'equipment_program_filter.dart';

/// Wzorzec ruchowy — pod kontrolę „czy zestawowi nie brakuje czegoś ważnego".
enum MovementPattern {
  horizontalPush('Wyciskanie poziome'),
  verticalPush('Wyciskanie nad głowę'),
  horizontalPull('Przyciąganie poziome'),
  verticalPull('Podciąganie / ściąganie'),
  squat('Przysiad'),
  hinge('Zawias biodrowy'),
  lunge('Wykrok / praca jednonóż'),
  core('Core / stabilizacja'),
  carryOrOther('Inne');

  const MovementPattern(this.label);

  final String label;
}

/// Wzorzec ruchowy ćwiczenia — rozpoznawany z nazwy, kategorii i partii.
MovementPattern movementPatternOf(Exercise exercise) {
  final name = exercise.name.toLowerCase();
  final type = exercise.illustrationType.toLowerCase();
  final primary = primaryMuscleGroupOf(exercise);

  bool has(List<String> keys) => keys.any((key) => name.contains(key));

  if (has(['podciąg', 'podciag', 'ściąganie drążka', 'sciaganie drazka',
        'pull-up', 'pullup', 'chin-up', 'lat pulldown', 'ściąganie wyciągu',
        'sciaganie wyciagu'])) {
    return MovementPattern.verticalPull;
  }
  if (has(['wiosł', 'wiosl', 'przyciąg', 'przyciag', 'row', 'face pull'])) {
    return MovementPattern.horizontalPull;
  }
  if (has(['ohp', 'nad głow', 'nad glow', 'żołnierskie', 'zolnierskie',
        'overhead press', 'arnold', 'push press', 'wyciskanie stojąc',
        'wyciskanie stojac'])) {
    return MovementPattern.verticalPush;
  }
  if (has(['pompk', 'push-up', 'pushup', 'wyciskanie', 'dip', 'pompki'])) {
    return MovementPattern.horizontalPush;
  }
  if (has(['wykrok', 'zakrok', 'zakroki', 'bulgar', 'lunge', 'wejścia na',
        'wejscia na', 'step-up', 'step up'])) {
    return MovementPattern.lunge;
  }
  if (has(['martwy', 'deadlift', 'rdl', 'hip thrust', 'good morning',
        'zawias', 'wznosy bioder', 'unoszenie bioder', 'swing'])) {
    return MovementPattern.hinge;
  }
  if (has(['przysiad', 'squat', 'hack', 'wypychanie ciężaru nogami',
        'wypychanie ciezaru nogami', 'leg press'])) {
    return MovementPattern.squat;
  }
  if (type.contains('pull')) return MovementPattern.horizontalPull;
  if (type.contains('push')) return MovementPattern.horizontalPush;
  if (type.contains('squat')) return MovementPattern.squat;
  if (type.contains('deadlift') || type.contains('hinge')) {
    return MovementPattern.hinge;
  }
  if (type.contains('lunge')) return MovementPattern.lunge;
  if (primary == MuscleGroup.core) return MovementPattern.core;
  return MovementPattern.carryOrOther;
}

/// Pojedynczy wniosek analizy — zaleta, problem albo sugestia.
class PlanQualityNote {
  const PlanQualityNote({
    required this.text,
    this.dayIndex,
    this.exerciseId = '',
    this.severity = PlanNoteSeverity.info,
  });

  final String text;

  /// Dzień, którego dotyczy wniosek (`null` = cały zestaw).
  final int? dayIndex;
  final String exerciseId;
  final PlanNoteSeverity severity;
}

enum PlanNoteSeverity { info, warning, critical }

/// Statystyki jednego dnia zestawu.
class PlanDayStats {
  const PlanDayStats({
    required this.dayIndex,
    required this.title,
    required this.exerciseCount,
    required this.totalSets,
    required this.estimatedMinutes,
    required this.setsByMuscle,
    required this.patterns,
    required this.requiresMissingEquipment,
  });

  final int dayIndex;
  final String title;
  final int exerciseCount;
  final int totalSets;
  final int estimatedMinutes;

  /// Serie robocze przypisane do partii GŁÓWNEJ ćwiczenia.
  final Map<MuscleGroup, int> setsByMuscle;
  final Set<MovementPattern> patterns;
  final bool requiresMissingEquipment;

  bool get isRestDay => exerciseCount == 0;
}

/// Wynik analizy jakości zestawu.
class PlanQualityReport {
  const PlanQualityReport({
    required this.score,
    required this.strengths,
    required this.issues,
    required this.suggestions,
    required this.dayStats,
    required this.weeklySetsByMuscle,
    required this.totalExercises,
    required this.totalSets,
    required this.estimatedMinutes,
    required this.missingPatterns,
    required this.confidence,
    this.basis = const <String>[],
  });

  /// Ocena 0–100.
  final int score;
  final List<PlanQualityNote> strengths;
  final List<PlanQualityNote> issues;
  final List<PlanQualityNote> suggestions;
  final List<PlanDayStats> dayStats;
  final Map<MuscleGroup, int> weeklySetsByMuscle;
  final int totalExercises;
  final int totalSets;

  /// Sumaryczny szacowany czas wszystkich dni treningowych (min).
  final int estimatedMinutes;
  final Set<MovementPattern> missingPatterns;

  /// Pewność analizy 0..1 — spada, gdy brakuje danych (historii, profilu).
  final double confidence;

  /// Na czym oparto analizę (poziom, cel, sprzęt, regeneracja…).
  final List<String> basis;

  int get trainingDays => dayStats.where((day) => !day.isRestDay).length;

  bool get hasProblems => issues.isNotEmpty;

  PlanQualityReport copyWith({
    List<String>? basis,
    double? confidence,
  }) =>
      PlanQualityReport(
        score: score,
        strengths: strengths,
        issues: issues,
        suggestions: suggestions,
        dayStats: dayStats,
        weeklySetsByMuscle: weeklySetsByMuscle,
        totalExercises: totalExercises,
        totalSets: totalSets,
        estimatedMinutes: estimatedMinutes,
        missingPatterns: missingPatterns,
        confidence: confidence ?? this.confidence,
        basis: basis ?? this.basis,
      );
}

/// Szacowany czas jednego ćwiczenia w minutach (serie × (praca + przerwa)).
int estimatePlanItemMinutes(PlanItem item, Exercise exercise) {
  final sets = item.sets <= 0 ? 1 : item.sets;
  final rest = item.restSeconds > 0 ? item.restSeconds : 90;
  final work = item.durationSec > 0
      ? item.durationSec
      : (exercise.defaultDurationSec > 0
          ? exercise.defaultDurationSec
          : (item.reps <= 0 ? 10 : item.reps) * 4);
  final seconds = sets * (work + rest);
  return (seconds / 60).ceil();
}

/// Główna analiza zestawu. Wszystkie parametry poza [plan] i [resolve] mają
/// wartości domyślne — analiza działa nawet przy pustym profilu (wtedy sama
/// obniża [PlanQualityReport.confidence] i mówi o tym wprost).
PlanQualityReport analyzePlanQuality(
  WorkoutPlan plan, {
  required Exercise Function(String id) resolve,
  EquipmentProfile equipment = const EquipmentProfile(),
  LimitationProfile limitations = const LimitationProfile(),
  String level = '',
  String goal = '',
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
  VolumeLimitsConfig volumeLimits = VolumeLimitsConfig.standard,
  Map<BodyMuscle, MuscleRecoveryState> recovery =
      const <BodyMuscle, MuscleRecoveryState>{},
  int availableMinutes = 0,
  List<MuscleGroup> priorityMuscles = const <MuscleGroup>[],
  bool hasHistory = true,
}) {
  final owned = equipment.resolveOwned();
  final strengths = <PlanQualityNote>[];
  final issues = <PlanQualityNote>[];
  final suggestions = <PlanQualityNote>[];
  final dayStats = <PlanDayStats>[];
  final weeklySets = <MuscleGroup, int>{};
  final allPatterns = <MovementPattern>{};

  var totalExercises = 0;
  var totalSets = 0;
  var totalMinutes = 0;
  var equipmentIssues = 0;
  var limitationIssues = 0;

  for (var dayIndex = 0; dayIndex < plan.days.length; dayIndex++) {
    final day = plan.days[dayIndex];
    final setsByMuscle = <MuscleGroup, int>{};
    final patterns = <MovementPattern>{};
    final seenIds = <String>{};
    var dayMinutes = 0;
    var daySets = 0;
    var dayEquipmentMissing = false;

    for (final item in day.items) {
      final exercise = resolve(item.exerciseId);
      final sets = item.sets <= 0 ? 1 : item.sets;
      daySets += sets;
      dayMinutes += estimatePlanItemMinutes(item, exercise);

      final group = primaryMuscleGroupOf(exercise);
      setsByMuscle[group] = (setsByMuscle[group] ?? 0) + sets;
      weeklySets[group] = (weeklySets[group] ?? 0) + sets;
      final pattern = movementPatternOf(exercise);
      patterns.add(pattern);
      allPatterns.add(pattern);

      if (!seenIds.add(item.exerciseId)) {
        issues.add(PlanQualityNote(
          text: '${day.title}: ćwiczenie „${exercise.name}" powtarza się '
              'w tym samym dniu.',
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          severity: PlanNoteSeverity.warning,
        ));
      }
      if (!isExerciseAvailable(exercise, owned)) {
        dayEquipmentMissing = true;
        equipmentIssues++;
        issues.add(PlanQualityNote(
          text: '${day.title}: „${exercise.name}" wymaga sprzętu, którego nie '
              'masz w profilu (${exercise.equipment}).',
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          severity: PlanNoteSeverity.critical,
        ));
      }
      if (exerciseViolatesLimitation(exercise, limitations)) {
        limitationIssues++;
        issues.add(PlanQualityNote(
          text: '${day.title}: „${exercise.name}" koliduje z Twoimi '
              'ograniczeniami.',
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          severity: PlanNoteSeverity.critical,
        ));
      }
    }

    totalExercises += day.items.length;
    totalSets += daySets;
    totalMinutes += dayMinutes;

    dayStats.add(PlanDayStats(
      dayIndex: dayIndex,
      title: day.title,
      exerciseCount: day.items.length,
      totalSets: daySets,
      estimatedMinutes: dayMinutes,
      setsByMuscle: setsByMuscle,
      patterns: patterns,
      requiresMissingEquipment: dayEquipmentMissing,
    ));

    if (day.items.isEmpty) continue;

    // Czas dnia względem dostępnego czasu.
    if (availableMinutes > 0 && dayMinutes > availableMinutes + 10) {
      issues.add(PlanQualityNote(
        text: '${day.title}: około $dayMinutes min — więcej niż Twoje '
            '$availableMinutes min.',
        dayIndex: dayIndex,
        severity: PlanNoteSeverity.warning,
      ));
      suggestions.add(PlanQualityNote(
        text: '${day.title}: skróć trening — usuń jedno ćwiczenie pomocnicze '
            'albo zetnij serię w dwóch ruchach.',
        dayIndex: dayIndex,
      ));
    }

    // Za mało ćwiczeń w dniu treningowym.
    if (day.items.length < 3 && !plan.isRestDay(day)) {
      suggestions.add(PlanQualityNote(
        text: '${day.title}: tylko ${day.items.length} '
            '${_exerciseWord(day.items.length)} — rozważ dołożenie ruchu '
            'pomocniczego.',
        dayIndex: dayIndex,
      ));
    }

    // Zbyt duże nałożenie jednej partii w dniu.
    setsByMuscle.forEach((group, sets) {
      if (!kLimitedMuscleGroups.contains(group)) return;
      final limits = volumeLimitsFor(
        group,
        level: level,
        goal: goal,
        config: volumeLimits,
        intensity: intensity,
      );
      if (sets > limits.maxWorkingSets) {
        issues.add(PlanQualityNote(
          text: '${day.title}: ${group.label.toLowerCase()} dostaje $sets serii '
              '— powyżej limitu ${limits.maxWorkingSets}.',
          dayIndex: dayIndex,
          severity: PlanNoteSeverity.warning,
        ));
      }
    });

    // Kolejność: duże ruchy złożone powinny iść przed izolacją.
    final orderIssue = _firstOrderProblem(day, resolve);
    if (orderIssue != null) {
      suggestions.add(PlanQualityNote(
        text: '${day.title}: $orderIssue',
        dayIndex: dayIndex,
      ));
    }
  }

  // --- Analiza tygodniowa ---
  final trainingDays = dayStats.where((day) => !day.isRestDay).length;

  // Kolizje z regeneracją (dni obciążające zmęczone partie).
  final recoveryConflicts = <String>[];
  if (recovery.isNotEmpty) {
    weeklySets.forEach((group, sets) {
      if (sets <= 0) return;
      final worst = _worstRecoveryForGroup(group, recovery);
      if (worst != null && worst < 55) {
        recoveryConflicts.add(
            '${group.label.toLowerCase()} (${worst.round()}%)');
      }
    });
    if (recoveryConflicts.isNotEmpty) {
      issues.add(PlanQualityNote(
        text: 'Zestaw mocno obciąża partie, które się jeszcze regenerują: '
            '${recoveryConflicts.take(3).join(', ')}.',
        severity: PlanNoteSeverity.warning,
      ));
    }
  }

  // Dwa dni z rzędu obciążające tę samą partię.
  for (var i = 1; i < dayStats.length; i++) {
    final previous = dayStats[i - 1];
    final current = dayStats[i];
    if (previous.isRestDay || current.isRestDay) continue;
    for (final entry in current.setsByMuscle.entries) {
      if (entry.value < 4) continue;
      final before = previous.setsByMuscle[entry.key] ?? 0;
      if (before >= 4) {
        issues.add(PlanQualityNote(
          text: 'Dwa dni z rzędu mocno angażują '
              '${entry.key.label.toLowerCase()} (${previous.title} → '
              '${current.title}).',
          dayIndex: i,
          severity: PlanNoteSeverity.warning,
        ));
        break;
      }
    }
  }

  // Brakujące wzorce ruchowe (tylko dla zestawów o ambicji „pełnego" planu).
  final missingPatterns = <MovementPattern>{};
  if (totalExercises >= 4) {
    const expected = <MovementPattern>{
      MovementPattern.horizontalPush,
      MovementPattern.horizontalPull,
      MovementPattern.squat,
      MovementPattern.hinge,
    };
    for (final pattern in expected) {
      if (!allPatterns.contains(pattern)) missingPatterns.add(pattern);
    }
  }

  // Równowaga push/pull.
  final pushSets = _setsForPatterns(plan, resolve, {
    MovementPattern.horizontalPush,
    MovementPattern.verticalPush,
  });
  final pullSets = _setsForPatterns(plan, resolve, {
    MovementPattern.horizontalPull,
    MovementPattern.verticalPull,
  });
  final balanced = pushSets == 0 && pullSets == 0
      ? true
      : (pushSets - pullSets).abs() <=
          (pushSets + pullSets) * 0.35 + 2;

  // Priorytetowe partie bez pokrycia.
  for (final group in priorityMuscles) {
    final sets = weeklySets[group] ?? 0;
    if (sets == 0) {
      issues.add(PlanQualityNote(
        text: 'Brakuje ćwiczeń na wybrany priorytet: '
            '${group.label.toLowerCase()}.',
        severity: PlanNoteSeverity.warning,
      ));
    }
  }

  // --- Zalety ---
  if (equipmentIssues == 0 && totalExercises > 0) {
    strengths.add(const PlanQualityNote(
        text: 'Wszystkie ćwiczenia pasują do Twojego sprzętu.'));
  }
  if (limitationIssues == 0 && !limitations.isEmpty) {
    strengths.add(const PlanQualityNote(
        text: 'Zestaw respektuje Twoje ograniczenia treningowe.'));
  }
  if (balanced && pushSets + pullSets >= 4) {
    strengths.add(PlanQualityNote(
        text: 'Dobra równowaga Push/Pull ($pushSets vs $pullSets serii).'));
  }
  if (availableMinutes > 0 &&
      dayStats.every((day) =>
          day.isRestDay || day.estimatedMinutes <= availableMinutes + 10)) {
    strengths.add(PlanQualityNote(
        text: 'Każdy dzień mieści się w Twoim limicie $availableMinutes min.'));
  }
  if (missingPatterns.isEmpty && totalExercises >= 4) {
    strengths.add(const PlanQualityNote(
        text: 'Zestaw pokrywa podstawowe wzorce ruchowe.'));
  }
  for (final group in priorityMuscles) {
    final sets = weeklySets[group] ?? 0;
    if (sets >= 6) {
      strengths.add(PlanQualityNote(
          text: 'Priorytet ${group.label.toLowerCase()} dostaje $sets serii '
              'w zestawie.'));
    }
  }

  // --- Sugestie ---
  for (final pattern in missingPatterns) {
    suggestions.add(PlanQualityNote(
        text: 'Brakuje wzorca „${pattern.label}" — dołóż jedno ćwiczenie '
            'tego typu.'));
  }
  if (!balanced && pushSets + pullSets > 0) {
    final weaker = pushSets < pullSets ? 'pchających' : 'ciągnących';
    suggestions.add(PlanQualityNote(
        text: 'Nierówny Push/Pull ($pushSets vs $pullSets serii) — dołóż '
            'ćwiczenie z grupy ruchów $weaker.'));
  }
  if (trainingDays == 0 && plan.days.isNotEmpty) {
    issues.add(const PlanQualityNote(
      text: 'Zestaw nie ma ani jednego dnia z ćwiczeniami.',
      severity: PlanNoteSeverity.critical,
    ));
  }

  // --- Ocena ---
  var score = 100;
  for (final issue in issues) {
    switch (issue.severity) {
      case PlanNoteSeverity.critical:
        score -= 12;
      case PlanNoteSeverity.warning:
        score -= 6;
      case PlanNoteSeverity.info:
        score -= 2;
    }
  }
  score -= suggestions.length * 2;
  score += strengths.length * 2;
  score = score.clamp(0, 100);

  // --- Pewność ---
  var confidence = 1.0;
  if (!hasHistory) confidence -= 0.25;
  if (level.trim().isEmpty) confidence -= 0.1;
  if (goal.trim().isEmpty) confidence -= 0.1;
  if (recovery.isEmpty) confidence -= 0.15;
  if (availableMinutes <= 0) confidence -= 0.05;
  confidence = confidence.clamp(0.2, 1.0);

  return PlanQualityReport(
    score: score,
    strengths: strengths,
    issues: issues,
    suggestions: suggestions,
    dayStats: dayStats,
    weeklySetsByMuscle: weeklySets,
    totalExercises: totalExercises,
    totalSets: totalSets,
    estimatedMinutes: totalMinutes,
    missingPatterns: missingPatterns,
    confidence: confidence,
  );
}

/// Najniższa (najgorsza) regeneracja wśród partii ciała mapowanych na [group].
double? _worstRecoveryForGroup(
  MuscleGroup group,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
) {
  double? worst;
  for (final entry in recovery.entries) {
    if (muscleGroupOfBodyMuscle(entry.key) != group) continue;
    final state = entry.value;
    if (!state.hasData) continue;
    final percent = state.recoveryPercent;
    if (percent == null) continue;
    if (worst == null || percent < worst) worst = percent;
  }
  return worst;
}

int _setsForPatterns(
  WorkoutPlan plan,
  Exercise Function(String id) resolve,
  Set<MovementPattern> patterns,
) {
  var sets = 0;
  for (final day in plan.days) {
    for (final item in day.items) {
      final exercise = resolve(item.exerciseId);
      if (patterns.contains(movementPatternOf(exercise))) {
        sets += item.sets <= 0 ? 1 : item.sets;
      }
    }
  }
  return sets;
}

/// Pierwszy problem z kolejnością w dniu: izolacja przed dużym ruchem złożonym.
String? _firstOrderProblem(
  WorkoutDay day,
  Exercise Function(String id) resolve,
) {
  var sawIsolation = false;
  String? isolationName;
  for (final item in day.items) {
    final exercise = resolve(item.exerciseId);
    final pattern = movementPatternOf(exercise);
    final isCompound = pattern != MovementPattern.core &&
        pattern != MovementPattern.carryOrOther &&
        exercise.effectiveMuscleImpacts.length > 1;
    if (!isCompound) {
      if (pattern != MovementPattern.core) {
        sawIsolation = true;
        isolationName ??= exercise.name;
      }
      continue;
    }
    if (sawIsolation && isolationName != null) {
      return 'ćwiczenie złożone „${exercise.name}" jest po izolacji '
          '„$isolationName" — złożone ruchy rób na świeżo.';
    }
  }
  return null;
}

String _exerciseWord(int count) {
  if (count == 1) return 'ćwiczenie';
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'ćwiczenia';
  }
  return 'ćwiczeń';
}
