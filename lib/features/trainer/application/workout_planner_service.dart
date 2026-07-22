/// Centralny serwis Inteligentnego Planera (czysty Dart).
///
/// Składa w jedną „propozycję na dziś" trzy istniejące elementy:
///  - [buildWeeklyTrainingAdvice] (co trenować dziś / tydzień / programy),
///  - rekomendacje trenera [SetRecommendation] (ciężar/serie/powtórzenia/przerwy
///    — liczone przez `training_coach`, tu tylko składane, bez duplikowania logiki),
///  - prognozę wysiłku (czas, aktywne kcal, woda, węglowodany, intensywność).
///
/// Dodatkowo ocenia obciążenie tygodnia (przeciążenie) i sugeruje deload.
/// Serwis jest doradczy i deterministyczny — niczego nie zapisuje ani nie
/// modyfikuje danych użytkownika. Ten sam wynik zasila ekran „Trening" oraz
/// analizę przed treningiem; aktywny trening korzysta z tych samych rekomendacji
/// trenera, więc dobór ciężaru ma jedno źródło prawdy.
library;

import 'dart:math' as math;

import '../domain/body_muscle.dart';
import '../domain/exercise.dart';
import 'training_coach.dart';
import 'weekly_training_planner.dart';

/// Skąd pochodzi dzisiejsza propozycja Planera.
enum PlannedWorkoutKind {
  /// Kolejny nieukończony dzień aktywnego programu 30-dniowego.
  programDay,

  /// Zestaw ułożony dynamicznie z regeneracji (brak aktywnego programu na dziś).
  dynamicSuggestion,

  /// Dzień lżejszy / regeneracyjny / mobilność.
  lightDay,

  /// Brak danych do ułożenia treningu.
  none,
}

/// Poziom obciążenia tygodnia (dla wykrywania przeciążenia).
enum TrainingLoadLevel { low, optimal, high, overload }

extension TrainingLoadLevelLabel on TrainingLoadLevel {
  String get label {
    switch (this) {
      case TrainingLoadLevel.low:
        return 'niskie obciążenie';
      case TrainingLoadLevel.optimal:
        return 'optymalne';
      case TrainingLoadLevel.high:
        return 'wysokie';
      case TrainingLoadLevel.overload:
        return 'możliwe przeciążenie';
    }
  }
}

/// Pojedyncze ćwiczenie w gotowej propozycji — parametry dobrane przez trenera.
class PlannedExercise {
  const PlannedExercise({
    required this.exerciseId,
    required this.name,
    required this.sets,
    required this.reps,
    required this.durationSec,
    required this.weightKg,
    required this.restSeconds,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.loadTypeLabel,
    required this.reasons,
    required this.readinessPercent,
    this.isCalibrating = false,
    this.weightDeltaKg,
  });

  final String exerciseId;
  final String name;
  final int sets;

  /// Powtórzenia (0 dla ćwiczeń czasowych).
  final int reps;

  /// Czas serii w sekundach (>0 dla ćwiczeń czasowych).
  final int durationSec;

  /// Rekomendowany ciężar na stronę/sztangę (0 = masa ciała / brak ciężaru).
  final double weightKg;
  final int restSeconds;

  /// Etykiety głównych i pomocniczych partii mięśniowych.
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  /// „Ciężar zewnętrzny" / „Masa ciała" / „Czas".
  final String loadTypeLabel;

  /// Uzasadnienia trenera dla parametrów (pierwsze najważniejsze).
  final List<String> reasons;

  /// Gotowość (regeneracja %) najsłabszej głównej partii ćwiczenia.
  final double readinessPercent;

  /// Czy ćwiczenie jest w okresie kalibracji (mało historii).
  final bool isCalibrating;

  /// Zmiana ciężaru względem ostatniego treningu (null = brak/nieznana).
  final double? weightDeltaKg;

  bool get isTimeBased => durationSec > 0 && reps <= 0;

  /// Krótki opis serii: „3 × 10", „3 × 40 s".
  String get schemeLabel {
    if (isTimeBased) return '$sets × $durationSec s';
    return '$sets × $reps';
  }
}

/// Prognozowane wartości treningu (przed jego wykonaniem) — zawsze jako zakres,
/// bo realny wydatek zależy od tempa i intensywności.
class WorkoutForecast {
  const WorkoutForecast({
    required this.minMinutes,
    required this.maxMinutes,
    required this.kcalMin,
    required this.kcalMax,
    required this.creditedKcalMin,
    required this.creditedKcalMax,
    required this.waterMinMl,
    required this.waterMaxMl,
    required this.carbsMinG,
    required this.carbsMaxG,
    required this.intensityLabel,
    required this.setCount,
  });

  final int minMinutes;
  final int maxMinutes;
  final int kcalMin;
  final int kcalMax;

  /// Część prognozowanych aktywnych kcal, która może podnieść cel w Kaloriach
  /// przy domyślnym zaufaniu 65% i bieżącej strategii sylwetkowej.
  final int creditedKcalMin;
  final int creditedKcalMax;
  final int waterMinMl;
  final int waterMaxMl;
  final int carbsMinG;
  final int carbsMaxG;

  final String intensityLabel;
  final int setCount;

  static const empty = WorkoutForecast(
    minMinutes: 0,
    maxMinutes: 0,
    kcalMin: 0,
    kcalMax: 0,
    creditedKcalMin: 0,
    creditedKcalMax: 0,
    waterMinMl: 0,
    waterMaxMl: 0,
    carbsMinG: 0,
    carbsMaxG: 0,
    intensityLabel: 'niska',
    setCount: 0,
  );

  String get minutesLabel =>
      minMinutes == maxMinutes ? '$minMinutes min' : '$minMinutes–$maxMinutes min';
  String get kcalLabel =>
      kcalMin == kcalMax ? '$kcalMin kcal' : '$kcalMin–$kcalMax kcal';
  String get creditedKcalLabel => creditedKcalMin == creditedKcalMax
      ? '$creditedKcalMin kcal'
      : '$creditedKcalMin–$creditedKcalMax kcal';
  String get waterLabel => waterMinMl == waterMaxMl
      ? '$waterMinMl ml'
      : '$waterMinMl–$waterMaxMl ml';
  String get carbsLabel =>
      carbsMinG == carbsMaxG ? '$carbsMinG g' : '$carbsMinG–$carbsMaxG g';
}

/// Ocena obciążenia tygodnia i ryzyka przeciążenia.
class TrainingLoadAssessment {
  const TrainingLoadAssessment({
    required this.level,
    required this.headline,
    required this.signals,
  });

  final TrainingLoadLevel level;
  final String headline;
  final List<String> signals;

  static const empty = TrainingLoadAssessment(
    level: TrainingLoadLevel.optimal,
    headline: 'Obciążenie w normie.',
    signals: [],
  );
}

/// Propozycja lżejszego okresu (deload).
class DeloadAdvice {
  const DeloadAdvice({
    required this.recommended,
    required this.reason,
    required this.changes,
    required this.days,
  });

  final bool recommended;
  final String reason;

  /// Co deload by zmienił (ciężar/serie/przerwy/warianty).
  final List<String> changes;
  final int days;

  static const none = DeloadAdvice(
    recommended: false,
    reason: '',
    changes: [],
    days: 0,
  );
}

/// Pełna propozycja Planera na dziś.
class PlannedWorkout {
  const PlannedWorkout({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.exercises,
    required this.forecast,
    required this.readinessPercent,
    required this.reasonBullets,
    required this.avoid,
    required this.alternatives,
    required this.mainMuscles,
    required this.confidence,
    required this.confidenceInputs,
    required this.missingData,
    required this.load,
    required this.deload,
    required this.hasRecoveryData,
    this.programId,
    this.dayIndex,
    this.programDayNumber,
    this.programTotalDays,
    this.warnings = const [],
  });

  final PlannedWorkoutKind kind;

  /// Np. „Nogi + pośladki".
  final String title;

  /// Np. „Program: Siła 30 dni · Dzień 8/30" albo „Propozycja planera na dziś".
  final String subtitle;
  final List<PlannedExercise> exercises;
  final WorkoutForecast forecast;

  /// Gotowość organizmu (0–100) — najniższa gotowość głównych partii dnia.
  final double readinessPercent;

  /// „Dlaczego ten trening" — punkty uzasadnienia.
  final List<String> reasonBullets;

  /// Partie, których dziś unikać.
  final List<String> avoid;

  /// Dostępne alternatywy (opisy).
  final List<String> alternatives;

  /// Główne partie treningu (do mapy mięśni).
  final List<BodyMuscle> mainMuscles;

  /// Pewność rekomendacji 0–1.
  final double confidence;

  /// Dane użyte do rekomendacji.
  final List<String> confidenceInputs;

  /// Braki danych (np. brak Health Connect).
  final List<String> missingData;
  final TrainingLoadAssessment load;
  final DeloadAdvice deload;
  final bool hasRecoveryData;

  final String? programId;
  final int? dayIndex;
  final int? programDayNumber;
  final int? programTotalDays;

  /// Ostrzeżenia Planera (np. „przedni bark nie w pełni zregenerowany").
  final List<String> warnings;

  bool get isProgramDay => kind == PlannedWorkoutKind.programDay;
  bool get isActionable =>
      kind == PlannedWorkoutKind.programDay ||
      kind == PlannedWorkoutKind.dynamicSuggestion;

  int get confidencePercent => (confidence * 100).round();
}

// ============================================================================
// Wejście do serwisu
// ============================================================================

/// Pojedyncze ćwiczenie z policzoną rekomendacją trenera — przygotowywane przez
/// warstwę magazynu (AppStore), która ma dostęp do historii i regeneracji.
class PlannerExerciseInput {
  const PlannerExerciseInput({
    required this.exercise,
    required this.recommendation,
    required this.readinessPercent,
    this.weightDeltaKg,
  });

  final Exercise exercise;
  final SetRecommendation recommendation;
  final double readinessPercent;
  final double? weightDeltaKg;
}

/// Kontekst aktywnego dnia programu 30-dniowego (gdy dziś wypada dzień programu).
class PlannerProgramContext {
  const PlannerProgramContext({
    required this.programId,
    required this.planName,
    required this.dayIndex,
    required this.dayNumber,
    required this.totalDays,
    required this.dayTitle,
    required this.isRest,
    required this.exercises,
  });

  final String programId;
  final String planName;
  final int dayIndex;
  final int dayNumber;
  final int totalDays;
  final String dayTitle;
  final bool isRest;
  final List<PlannerExerciseInput> exercises;
}

/// Sygnały zmęczenia/obciążenia liczone z historii (do przeciążenia i deloadu).
class PlannerSignals {
  const PlannerSignals({
    this.avgRecentRpe = 0,
    this.weeklyVolumeKg = 0,
    this.tiredMuscleCount = 0,
    this.hardDaysLast7 = 0,
    this.incompleteSetStreak = 0,
    this.consecutiveTrainingDays = 0,
    this.recentRunCount = 0,
    this.strengthSessionsLast7 = 0,
    this.hasLightDayLast5 = false,
    this.hasHealthConnectData = false,
    this.hasRecoveryData = false,
    this.hasHistory = false,
  });

  /// Średnie (ukryte) RPE ostatniej doby.
  final double avgRecentRpe;
  final double weeklyVolumeKg;

  /// Ile partii jest mocno zmęczonych (regeneracja < 60%).
  final int tiredMuscleCount;

  /// Ciężkie dni (RPE ≥ 8.5) w ostatnim tygodniu.
  final int hardDaysLast7;

  /// Ile sesji z rzędu skończyło się nieukończoną serią.
  final int incompleteSetStreak;

  /// Kolejne dni treningowe pod rząd (bez dnia lżejszego/wolnego).
  final int consecutiveTrainingDays;
  final int recentRunCount;
  final int strengthSessionsLast7;
  final bool hasLightDayLast5;
  final bool hasHealthConnectData;
  final bool hasRecoveryData;
  final bool hasHistory;
}

// ============================================================================
// Prognoza wysiłku (czyste funkcje)
// ============================================================================

/// Aktywne kcal netto z formuły MET. Spoczynkowe 1 MET jest już ujęte w
/// bazie Miffina, więc prognoza nie może doliczać go drugi raz.
double _metKcal(double met, double weightKg, double minutes) {
  if (met <= 0 || weightKg <= 0 || minutes <= 0) return 0;
  final netMet = math.max(0.0, met - 1.0);
  return netMet * 3.5 * weightKg / 200 * minutes;
}

double _forecastStrategyFactor(String goal) {
  final normalized = goal.trim().toLowerCase();
  if (normalized.contains('redukc')) return 0.82;
  if (normalized.contains('rekomp')) return 0.93;
  if (normalized.contains('masa')) return 1.08;
  if (normalized.contains('kondyc') || normalized.contains('wydol')) {
    return 1.05;
  }
  return 1.0;
}

/// Szacowany czas jednego ćwiczenia w sekundach (praca + odpoczynek).
int _exerciseSeconds(PlannedExercise ex) {
  final workSeconds = ex.durationSec > 0
      ? ex.sets * ex.durationSec
      : ex.sets * (ex.reps > 0 ? ex.reps : 10) * 3;
  final restSeconds = ex.sets * ex.restSeconds;
  return workSeconds + restSeconds;
}

/// Liczy prognozę (czas/kcal/woda/węglowodany/intensywność) z listy
/// gotowych ćwiczeń. Wartości zawsze jako zakres.
WorkoutForecast forecastForExercises({
  required List<PlannedExercise> exercises,
  required double bodyWeightKg,
  required String goal,
  required bool lighter,
  required List<double> mets,
}) {
  if (exercises.isEmpty) return WorkoutForecast.empty;
  final safeWeight = bodyWeightKg.isFinite && bodyWeightKg > 0 ? bodyWeightKg : 75.0;

  var totalSeconds = 0;
  var kcal = 0.0;
  var setCount = 0;
  for (var i = 0; i < exercises.length; i++) {
    final ex = exercises[i];
    setCount += ex.sets;
    final seconds = _exerciseSeconds(ex);
    totalSeconds += seconds;
    final minutes = math.max(1.0, seconds / 60);
    final met = i < mets.length ? mets[i] : 5.0;
    kcal += _metKcal(met, safeWeight, minutes);
  }

  final totalMinutes = math.max(1, (totalSeconds / 60).round());
  final minMinutes = math.max(1, (totalMinutes * 0.9).round());
  final maxMinutes = math.max(minMinutes, (totalMinutes * 1.18).round());

  final kcalCenter = kcal.round();
  final kcalMin = (kcalCenter * 0.88).round().clamp(0, 2500);
  final kcalMax = math.max(kcalMin, (kcalCenter * 1.16).round().clamp(0, 2500));

  // Prognoza doliczenia do celu używa tego samego domyślnego zaufania 65%
  // i współczynnika strategii co Kalorie. Ostateczna wartość po treningu może
  // się różnić, jeśli użytkownik zmieni poziom zaufania lub zegarek poda inne
  // aktywne kcal.
  final creditFactor = 0.65 * _forecastStrategyFactor(goal);
  final creditedKcalMin = (kcalMin * creditFactor).round();
  final creditedKcalMax = math.max(
    creditedKcalMin,
    (kcalMax * creditFactor).round(),
  );

  // Woda: baza rośnie z czasem, górny zakres uwzględnia wyższą intensywność.
  final waterMin = (280 + totalMinutes * 7).clamp(200, 2000).toInt();
  final waterMax =
      (380 + totalMinutes * 10 + (lighter ? 0 : 150)).clamp(waterMin, 2400).toInt();

  // Węglowodany dopełniają dokładnie uznaną część energii (4 kcal/g).
  final meaningful = kcalCenter >= 150 || totalMinutes >= 25;
  final carbsMin = meaningful
      ? (creditedKcalMin / 4).round().clamp(0, 180).toInt()
      : 0;
  final carbsMax = meaningful
      ? math.max(
          carbsMin,
          (creditedKcalMax / 4).round().clamp(0, 220).toInt(),
        )
      : 0;

  final intensity = _intensityLabel(
    setCount: setCount,
    goal: goal,
    lighter: lighter,
  );

  return WorkoutForecast(
    minMinutes: minMinutes,
    maxMinutes: maxMinutes,
    kcalMin: kcalMin,
    kcalMax: kcalMax,
    creditedKcalMin: creditedKcalMin,
    creditedKcalMax: creditedKcalMax,
    waterMinMl: waterMin,
    waterMaxMl: waterMax,
    carbsMinG: carbsMin,
    carbsMaxG: carbsMax,
    intensityLabel: intensity,
    setCount: setCount,
  );
}

String _intensityLabel({
  required int setCount,
  required String goal,
  required bool lighter,
}) {
  if (lighter) return 'niska';
  final g = goal.toLowerCase();
  final strengthBias = g.contains('sił') || g.contains('sil');
  if (setCount <= 8) return strengthBias ? 'średnia' : 'niska';
  if (setCount <= 14) return strengthBias ? 'średnio-wysoka' : 'średnia';
  if (setCount <= 20) return 'średnio-wysoka';
  return 'wysoka';
}

// ============================================================================
// Ocena przeciążenia i deload
// ============================================================================

TrainingLoadAssessment assessTrainingLoad(PlannerSignals signals) {
  if (!signals.hasHistory) {
    return const TrainingLoadAssessment(
      level: TrainingLoadLevel.low,
      headline: 'Za mało danych, by ocenić obciążenie — wykonaj kilka treningów.',
      signals: [],
    );
  }

  final reasons = <String>[];
  var score = 0;

  if (signals.avgRecentRpe >= 8.5) {
    score += 2;
    reasons.add('Wysokie średnie RPE ostatniej doby (${signals.avgRecentRpe.toStringAsFixed(1)}).');
  } else if (signals.avgRecentRpe >= 7.5) {
    score += 1;
    reasons.add('Podwyższone RPE ostatnich treningów.');
  }
  if (signals.tiredMuscleCount >= 4) {
    score += 2;
    reasons.add('${signals.tiredMuscleCount} partii mocno zmęczonych.');
  } else if (signals.tiredMuscleCount >= 2) {
    score += 1;
    reasons.add('${signals.tiredMuscleCount} partie w regeneracji.');
  }
  if (signals.hardDaysLast7 >= 4) {
    score += 2;
    reasons.add('${signals.hardDaysLast7} ciężkich dni w tygodniu.');
  } else if (signals.hardDaysLast7 >= 3) {
    score += 1;
  }
  if (signals.incompleteSetStreak >= 2) {
    score += 2;
    reasons.add('Powtarzające się nieukończone serie.');
  }
  if (signals.consecutiveTrainingDays >= 5 && !signals.hasLightDayLast5) {
    score += 1;
    reasons.add('Brak dnia lżejszego od kilku dni.');
  }
  if (signals.recentRunCount >= 2) {
    score += 1;
    reasons.add('Kilka biegów — nogi mocno obciążone.');
  }
  if (signals.weeklyVolumeKg >= 40000) {
    score += 1;
    reasons.add('Duża objętość tygodniowa.');
  }

  TrainingLoadLevel level;
  String headline;
  if (score >= 5) {
    level = TrainingLoadLevel.overload;
    headline = 'Możliwe przeciążenie — rozważ lżejszy okres.';
  } else if (score >= 3) {
    level = TrainingLoadLevel.high;
    headline = 'Wysokie obciążenie — pilnuj regeneracji.';
  } else if (score >= 1) {
    level = TrainingLoadLevel.optimal;
    headline = 'Obciążenie optymalne.';
  } else {
    level = TrainingLoadLevel.low;
    headline = 'Niskie obciążenie — jest miejsce na mocniejszy trening.';
  }
  return TrainingLoadAssessment(level: level, headline: headline, signals: reasons);
}

DeloadAdvice assessDeload(PlannerSignals signals, TrainingLoadAssessment load) {
  final overload = load.level == TrainingLoadLevel.overload;
  final chronicHardWork = signals.hardDaysLast7 >= 3 &&
      !signals.hasLightDayLast5 &&
      signals.avgRecentRpe >= 8.0;
  final stalling = signals.incompleteSetStreak >= 2 && signals.avgRecentRpe >= 8.0;
  final recommended = overload || chronicHardWork || stalling;
  if (!recommended) return DeloadAdvice.none;

  final reason = overload
      ? 'W ostatnich dniach obciążenie było wysokie, a organizm nie miał lżejszego dnia.'
      : stalling
          ? 'Powtarzają się nieukończone serie przy wysokim wysiłku — wyniki zaczynają spadać.'
          : 'Kilka ciężkich dni z rzędu bez odciążenia.';
  return DeloadAdvice(
    recommended: true,
    reason: reason,
    days: 4,
    changes: const [
      'zmniejszenie ciężaru o około 10%',
      'jedna seria mniej w ćwiczeniu',
      'dłuższe przerwy między seriami',
      'łatwiejsze warianty najcięższych ćwiczeń',
      'więcej mobilności, mniej ciężkiego cardio',
    ],
  );
}

// ============================================================================
// Główna funkcja składająca propozycję
// ============================================================================

PlannedExercise _plannedFromInput(PlannerExerciseInput input) {
  final exercise = input.exercise;
  final rec = input.recommendation;
  final primary = <String>[];
  final secondary = <String>[];
  for (final impact in exercise.effectiveMuscleImpacts) {
    if (impact.role == MuscleRole.primary) {
      primary.add(impact.muscleGroup.label);
    } else if (impact.role == MuscleRole.secondary) {
      secondary.add(impact.muscleGroup.label);
    }
  }
  final entryType = exercise.entryType;
  final loadLabel = rec.durationSec > 0 && rec.reps <= 0
      ? 'Czas'
      : (entryType.usesBodyweight || !entryType.showsWeight)
          ? 'Masa ciała'
          : 'Ciężar zewnętrzny';
  return PlannedExercise(
    exerciseId: exercise.id,
    name: exercise.name,
    sets: rec.sets,
    reps: rec.reps,
    durationSec: rec.durationSec,
    weightKg: rec.weightKg,
    restSeconds: rec.restSeconds,
    primaryMuscles: primary,
    secondaryMuscles: secondary,
    loadTypeLabel: loadLabel,
    reasons: rec.reasons,
    readinessPercent: input.readinessPercent,
    isCalibrating: rec.isCalibrating,
    weightDeltaKg: input.weightDeltaKg,
  );
}

/// Buduje pełną propozycję Planera na dziś.
///
/// [program] — kontekst dnia aktywnego programu (null, gdy dziś nie wypada
/// dzień programu). [dynamicExercises] — zestaw ułożony dynamicznie z regeneracji
/// (używany, gdy [program] == null i nie jest to dzień lżejszy).
PlannedWorkout buildPlannedWorkout({
  required WeeklyTrainingAdvice advice,
  required PlannerProgramContext? program,
  required List<PlannerExerciseInput> dynamicExercises,
  required PlannerSignals signals,
  required double bodyWeightKg,
  required String goal,
  double timeCapMinutes = 0,
}) {
  final load = assessTrainingLoad(signals);
  final deload = assessDeload(signals, load);
  final avoid = advice.todayAvoid;

  final missing = <String>[
    if (!signals.hasRecoveryData) 'Brak danych regeneracji (za mało historii).',
    if (!signals.hasHealthConnectData) 'Brak danych z Health Connect / zegarka.',
  ];
  final inputs = <String>[
    if (signals.hasHistory) 'historia treningów',
    if (signals.hasRecoveryData) 'mapa regeneracji',
    if (signals.hasHealthConnectData) 'Health Connect',
    if (signals.recentRunCount > 0) 'ostatnie biegi',
    'profil i cel treningowy',
  ];

  // Pewność rekomendacji: rośnie z ilością danych, spada przy brakach i kalibracji.
  var confidence = 0.5;
  if (signals.hasRecoveryData) confidence += 0.2;
  if (signals.hasHistory) confidence += 0.12;
  if (signals.hasHealthConnectData) confidence += 0.08;

  // --- Dzień programu 30-dniowego. ---
  if (program != null && !program.isRest && program.exercises.isNotEmpty) {
    var exercises = [for (final input in program.exercises) _plannedFromInput(input)];
    exercises = _applyTimeCap(exercises, timeCapMinutes);
    final mets = [for (final input in program.exercises) input.exercise.met];
    final trimmedMets = mets.take(exercises.length).toList();
    final readiness = _lowestReadiness(exercises);
    final forecast = forecastForExercises(
      exercises: exercises,
      bodyWeightKg: bodyWeightKg,
      goal: goal,
      lighter: false,
      mets: trimmedMets,
    );
    final calibrating = exercises.where((e) => e.isCalibrating).length;
    if (calibrating > 0) confidence -= 0.08;
    final mainMuscles = _collectMuscles(program.exercises);
    final bullets = <String>[
      'Dzień ${program.dayNumber} z ${program.totalDays} w programie „${program.planName}".',
      if (readiness >= 75) 'Główne partie dnia są zregenerowane (${readiness.round()}%).'
      else if (readiness >= 55) 'Partie dnia częściowo zregenerowane (${readiness.round()}%) — bez maksymalnej intensywności.'
      else 'Część partii wciąż w regeneracji (${readiness.round()}%) — Planer proponuje ostrożny start.',
      if (avoid.isNotEmpty) 'Dziś odpoczywają: ${avoid.take(2).join(', ')}.',
    ];
    return PlannedWorkout(
      kind: PlannedWorkoutKind.programDay,
      title: program.dayTitle,
      subtitle: 'Program: ${program.planName} · Dzień ${program.dayNumber}/${program.totalDays}',
      exercises: exercises,
      forecast: forecast,
      readinessPercent: readiness,
      reasonBullets: bullets,
      avoid: avoid,
      alternatives: _alternatives(advice, isProgram: true),
      mainMuscles: mainMuscles,
      confidence: confidence.clamp(0.1, 0.97),
      confidenceInputs: inputs,
      missingData: missing,
      load: load,
      deload: deload,
      hasRecoveryData: signals.hasRecoveryData,
      programId: program.programId,
      dayIndex: program.dayIndex,
      programDayNumber: program.dayNumber,
      programTotalDays: program.totalDays,
      warnings: _warnings(program.exercises, timeCapMinutes, exercises.length),
    );
  }

  // --- Dzień lżejszy / regeneracyjny albo brak gotowych ćwiczeń. ---
  //
  // Ze STAŁYM ROZKŁADEM o charakterze dnia decyduje rozkład (dzień wolny /
  // deload), a nie zgadywanie ze słów nagłówka — inaczej dzień z dodatkiem
  // „Mobilność" był brany za dzień regeneracyjny.
  final hasSchedule = advice.todayFocusLabel.isNotEmpty || advice.todayIsRest;
  final lighter = hasSchedule
      ? (advice.todayIsRest || (program != null && program.isRest))
      : (advice.todayHeadline.toLowerCase().contains('lżejsz') ||
          advice.todayHeadline.toLowerCase().contains('mobilno') ||
          (program != null && program.isRest));
  if (dynamicExercises.isEmpty || lighter) {
    return PlannedWorkout(
      kind: PlannedWorkoutKind.lightDay,
      title: advice.todayIsRest
          ? 'Dzień wolny w rozkładzie'
          : (lighter ? 'Dzień lżejszy: mobilność / core' : 'Dzień regeneracyjny'),
      subtitle: 'Propozycja planera na dziś',
      exercises: const [],
      forecast: WorkoutForecast.empty,
      readinessPercent: advice.areaReadiness.isEmpty ? 100 : advice.areaReadiness.first.percent,
      reasonBullets: [
        advice.todayHeadline,
        if (avoid.isNotEmpty) 'Dziś odpoczywają: ${avoid.take(3).join(', ')}.',
      ],
      avoid: avoid,
      alternatives: _alternatives(advice, isProgram: false),
      mainMuscles: const [],
      confidence: confidence.clamp(0.1, 0.97),
      confidenceInputs: inputs,
      missingData: missing,
      load: load,
      deload: deload,
      hasRecoveryData: signals.hasRecoveryData,
    );
  }

  // --- Dynamiczny zestaw z regeneracji. ---
  var exercises = [for (final input in dynamicExercises) _plannedFromInput(input)];
  exercises = _applyTimeCap(exercises, timeCapMinutes);
  final mets = [for (final input in dynamicExercises) input.exercise.met];
  final trimmedMets = mets.take(exercises.length).toList();
  final readiness = _lowestReadiness(exercises);
  final forecast = forecastForExercises(
    exercises: exercises,
    bodyWeightKg: bodyWeightKg,
    goal: goal,
    lighter: false,
    mets: trimmedMets,
  );
  final bestArea = advice.areaReadiness.isEmpty ? null : advice.areaReadiness.first;
  // Tytuł bierze się z ROZKŁADU, gdy jest ustawiony — dzień nazywa się tak,
  // jak zaplanował go użytkownik, a nie jak podpowiada dzisiejsza gotowość.
  final title = advice.todayFocusLabel.isNotEmpty
      ? advice.todayFocusLabel
      : (bestArea != null ? bestArea.area.label : 'Trening dnia');
  final bullets = <String>[
    advice.todayHeadline,
    if (bestArea != null) '${bestArea.area.label}: gotowość ${bestArea.percent.round()}%.',
    if (avoid.isNotEmpty) 'Dziś odpoczywają: ${avoid.take(2).join(', ')}.',
  ];
  return PlannedWorkout(
    kind: PlannedWorkoutKind.dynamicSuggestion,
    title: title,
    subtitle: advice.todayFocusLabel.isNotEmpty
        ? 'Zestaw złożony pod plan tygodnia'
        : 'Propozycja planera na dziś',
    exercises: exercises,
    forecast: forecast,
    readinessPercent: readiness,
    reasonBullets: bullets,
    avoid: avoid,
    alternatives: _alternatives(advice, isProgram: false),
    mainMuscles: _collectMuscles(dynamicExercises),
    confidence: confidence.clamp(0.1, 0.97),
    confidenceInputs: inputs,
    missingData: missing,
    load: load,
    deload: deload,
    hasRecoveryData: signals.hasRecoveryData,
    warnings: _warnings(dynamicExercises, timeCapMinutes, exercises.length),
  );
}

/// Skraca zestaw do limitu czasu, zachowując główne ćwiczenia (od początku listy)
/// i najpierw ograniczając serie ćwiczeń pomocniczych. Nigdy nie usuwa
/// pierwszego (najważniejszego) ćwiczenia.
List<PlannedExercise> _applyTimeCap(List<PlannedExercise> exercises, double capMinutes) {
  if (capMinutes <= 0 || exercises.isEmpty) return exercises;
  final capSeconds = capMinutes * 60;
  var total = exercises.fold<int>(0, (sum, e) => sum + _exerciseSeconds(e));
  if (total <= capSeconds) return exercises;

  final result = [...exercises];

  // Krok 1: obcinaj serie w ćwiczeniach od końca (pomocnicze) do min. 2 serii.
  var changed = true;
  while (total > capSeconds && changed) {
    changed = false;
    for (var i = result.length - 1; i >= 0 && total > capSeconds; i--) {
      final ex = result[i];
      if (ex.sets > 2) {
        final reduced = _withSets(ex, ex.sets - 1);
        total -= _exerciseSeconds(ex) - _exerciseSeconds(reduced);
        result[i] = reduced;
        changed = true;
      }
    }
  }

  // Krok 2: usuwaj ćwiczenia pomocnicze od końca (nigdy pierwszego).
  while (total > capSeconds && result.length > 1) {
    final removed = result.removeLast();
    total -= _exerciseSeconds(removed);
  }
  return result;
}

PlannedExercise _withSets(PlannedExercise ex, int sets) => PlannedExercise(
      exerciseId: ex.exerciseId,
      name: ex.name,
      sets: sets,
      reps: ex.reps,
      durationSec: ex.durationSec,
      weightKg: ex.weightKg,
      restSeconds: ex.restSeconds,
      primaryMuscles: ex.primaryMuscles,
      secondaryMuscles: ex.secondaryMuscles,
      loadTypeLabel: ex.loadTypeLabel,
      reasons: ex.reasons,
      readinessPercent: ex.readinessPercent,
      isCalibrating: ex.isCalibrating,
      weightDeltaKg: ex.weightDeltaKg,
    );

double _lowestReadiness(List<PlannedExercise> exercises) {
  if (exercises.isEmpty) return 100;
  var worst = 100.0;
  for (final ex in exercises) {
    if (ex.readinessPercent < worst) worst = ex.readinessPercent;
  }
  return worst;
}

List<BodyMuscle> _collectMuscles(List<PlannerExerciseInput> inputs) {
  final seen = <BodyMuscle>{};
  for (final input in inputs) {
    for (final impact in input.exercise.effectiveMuscleImpacts) {
      if (impact.role != MuscleRole.stabilizer) seen.add(impact.muscleGroup);
    }
  }
  return seen.toList();
}

List<String> _alternatives(WeeklyTrainingAdvice advice, {required bool isProgram}) {
  final alts = <String>[];
  final areas = advice.areaReadiness.where((a) => a.percent >= 60).toList();
  if (isProgram) {
    alts.add('Zestaw dynamiczny pod dzisiejszą regenerację');
  }
  for (final area in areas.take(2)) {
    alts.add('${area.area.label} (gotowość ${area.percent.round()}%)');
  }
  alts.add('Cardio / bieg');
  alts.add('Trening regeneracyjny (mobilność)');
  // Bez duplikatów, zachowując kolejność.
  final seen = <String>{};
  return [for (final a in alts) if (seen.add(a)) a];
}

List<String> _warnings(
  List<PlannerExerciseInput> inputs,
  double timeCapMinutes,
  int keptCount,
) {
  final warnings = <String>[];
  // Ćwiczenia obciążające partię < 60% regeneracji.
  for (final input in inputs.take(keptCount)) {
    if (input.readinessPercent < 60) {
      warnings.add(
          '„${input.exercise.name}" obciąża partię w regeneracji (${input.readinessPercent.round()}%) — rozważ łagodniejszy wariant.');
    }
  }
  if (timeCapMinutes > 0 && keptCount < inputs.length) {
    warnings.add(
        'Trening skrócony do limitu czasu — zachowano najważniejsze ćwiczenia (${inputs.length - keptCount} pominięto).');
  }
  return warnings;
}
