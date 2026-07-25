/// Silnik „inteligentnego trenera" (czysty Dart).
///
/// Etap: Trainer ma sam dobierać ciężar/serie/powtórzenia/przerwy, szacować
/// wysiłek (RPE jako ukryty parametr) z pewnością analizy oraz decydować o
/// progresji. Wszystko jako czyste funkcje — łatwe do testowania, bez UI.
///
/// Zasady bezpieczeństwa:
///  * przy niskiej pewności NIE robimy dużych zmian (ciężar/objętość),
///  * nowe ćwiczenie ma okres kalibracyjny (ostrożny start),
///  * skoki obciążenia są ograniczone (izolacja < wielostawowe),
///  * czas serii NIE decyduje sam o intensywności (jest jednym z sygnałów),
///  * czas niezweryfikowany (tło/zapomniany timer) obniża pewność, nie wysiłek.
library;

import 'dart:math' as math;

import '../domain/trainer_models.dart';

// ============================================================================
// Kontekst i dane wejściowe
// ============================================================================

/// Profil użytkownika istotny dla doboru obciążenia i progresji.
class CoachContext {
  const CoachContext({
    this.level = 'Średniozaawansowany',
    this.goal = '',
    this.bodyWeightKg = 0,
    this.heightCm = 0,
    this.age = 0,
    this.sex = '',
    this.cycleIntensity = 1.0,
  });

  final String level;

  /// Strategia/cel treningowy (siła / masa / redukcja / kondycja / rekompozycja).
  final String goal;
  final double bodyWeightKg;
  final double heightCm;
  final int age;
  final String sex;

  /// Współczynnik intensywności z cyklu deloadu (1.0 = pełna). Zaraz po
  /// deloadzie ≈1.0, pod koniec bloku ≈0.85, w deloadzie ≈0.55. Skaluje
  /// ciężar roboczy, NIE zastępując decyzji progresji — najpierw coach dobiera
  /// ciężar z historii, a dopiero potem faza cyklu go przycina.
  final double cycleIntensity;

  bool get isFemale {
    final s = sex.toLowerCase();
    return s.contains('kob') || s.contains('female') || s == 'k';
  }
}

/// Pojedynczy wynik historyczny ćwiczenia (jedna sesja, najlepsza seria).
class CoachHistorySample {
  const CoachHistorySample({
    required this.date,
    required this.weightKg,
    required this.reps,
    required this.durationSec,
    required this.plannedReps,
    required this.allSetsCompleted,
    this.estimatedRpe = 0,
    this.timeVerified = true,
    this.rpeReliable = true,
    this.confidence = 1.0,
  });

  final DateTime date;
  final double weightKg;
  final int reps;
  final int durationSec;
  final int plannedReps;
  final bool allSetsCompleted;

  /// Wysiłek sesji (1–10). Ma sens TYLKO gdy [rpeReliable]; przy braku danych
  /// wynosi 0 — NIE wstawiamy tu wartości domyślnej udającej pomiar.
  final double estimatedRpe;
  final bool timeVerified;

  /// Czy [estimatedRpe] pochodzi z realnego sygnału (świadomy wpis użytkownika
  /// albo pewne oszacowanie), a nie z technicznej wartości domyślnej.
  final bool rpeReliable;

  /// Pewność analizy tej sesji (0–1). Zasila bezpiecznik „przy niskiej pewności
  /// nie robimy dużych zmian" w [decideProgression]. 1.0 = brak powodów do
  /// nieufności (np. ręcznie wpisane RPE albo starszy zapis bez oceny pewności).
  final double confidence;
}

// ============================================================================
// Wyniki
// ============================================================================

/// Rekomendacja parametrów pojedynczego ćwiczenia.
class SetRecommendation {
  const SetRecommendation({
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.durationSec,
    required this.restSeconds,
    required this.reasons,
    this.isCalibrating = false,
    this.calibrationNote = '',
  });

  final int sets;
  final int reps;
  final double weightKg;

  /// Dla ćwiczeń czasowych — zalecany czas serii (0 dla powtórzeniowych).
  final int durationSec;
  final int restSeconds;

  /// Czytelne uzasadnienia („poprzedni trening ukończony", „klatka 94%"…).
  final List<String> reasons;

  /// Czy jesteśmy w okresie kalibracyjnym (pierwsze wykonania ćwiczenia).
  final bool isCalibrating;
  final String calibrationNote;
}

/// Szacowany wysiłek serii wraz z pewnością analizy.
class ExertionEstimate {
  const ExertionEstimate({
    required this.rpe,
    required this.confidence,
    required this.factors,
  });

  /// Ukryte RPE 1–10 (parametr wewnętrzny, nie pokazywany jako pole do wpisania).
  final double rpe;

  /// Pewność analizy 0–1.
  final double confidence;

  /// Sygnały, na których oparto ocenę (do wyjaśnienia użytkownikowi).
  final List<String> factors;

  /// Etykieta wysiłku; przy niskiej pewności zwraca „niepewny".
  String get levelLabel {
    if (confidence < 0.5) return 'niepewny';
    if (rpe >= 8.5) return 'bardzo wysoki';
    if (rpe >= 7) return 'wysoki';
    if (rpe >= 5) return 'umiarkowany';
    return 'lekki';
  }

  int get confidencePercent => (confidence * 100).round();
}

enum CoachProgressionAction {
  increaseWeight,
  decreaseWeight,
  increaseReps,
  increaseDuration,
  increaseRest,
  harderVariant,
  deload,
  hold,
}

/// Decyzja o zmianie parametrów na następny trening.
class ProgressionDecision {
  const ProgressionDecision({
    required this.action,
    required this.reason,
    this.weightDeltaKg = 0,
    this.repDelta = 0,
    this.durationDeltaSec = 0,
  });

  final CoachProgressionAction action;
  final String reason;
  final double weightDeltaKg;
  final int repDelta;
  final int durationDeltaSec;

  bool get changesLoad => action != CoachProgressionAction.hold;
}

// ============================================================================
// Przerwa między seriami
// ============================================================================

/// Wartość `restSeconds` oznaczająca „program NIE ustawił własnej przerwy".
///
/// Historycznie 90 s jest domyślną wartością [PlanItem.restSeconds], więc nie da
/// się jej odróżnić od świadomego wyboru użytkownika. Zachowujemy tę (zastaną)
/// semantykę, ale w JEDNYM miejscu: 90 → dobierz przerwę do typu ćwiczenia.
const int kUnsetRestSeconds = 90;

/// Przerwa bazowa wraz z czytelnym uzasadnieniem.
class RestPrescription {
  const RestPrescription({required this.seconds, required this.label});

  final int seconds;
  final String label;
}

/// Przerwa BAZOWA dla ćwiczenia: jawnie ustawiona w programie albo dobrana do
/// typu ruchu (siłowe / wielostawowe / izolowane / pomocnicze).
///
/// To jedyne źródło prawdy o przerwie — używa go [recommendSet] przy budowie
/// recepty sesji, dzięki czemu pokazywany plan i timer odpoczynku NIE mogą się
/// rozjechać (wcześniej timer liczył to niezależnie od rekomendacji).
RestPrescription baseRestFor(
  Exercise exercise, {
  required int plannedReps,
  required int plannedRestSeconds,
}) {
  if (plannedRestSeconds > 0 && plannedRestSeconds != kUnsetRestSeconds) {
    return RestPrescription(
      seconds: plannedRestSeconds.clamp(30, 600),
      label: 'Przerwa ustawiona w planie',
    );
  }
  // Typ wpisu ma pierwszeństwo przed heurystyką z nazwy: rozciąganie nie
  // potrzebuje kilkuminutowej przerwy, a ćwiczenie czasowe nie jest „siłowe"
  // tylko dlatego, że ma 0 powtórzeń (stara heurystyka dawała desce 180 s).
  final entryType = exercise.entryType;
  if (entryType == ExerciseEntryType.mobility) {
    return const RestPrescription(
        seconds: 30, label: 'Mobilność / rozciąganie');
  }
  if (entryType.showsDuration && !entryType.showsReps) {
    return const RestPrescription(seconds: 60, label: 'Ćwiczenie czasowe');
  }

  final name = exercise.name.toLowerCase();
  final isStrength = (plannedReps > 0 && plannedReps <= 6) ||
      name.contains('martwy ciąg') ||
      name.contains('deadlift');
  if (isStrength) {
    return const RestPrescription(seconds: 180, label: 'Ćwiczenie siłowe');
  }
  const isolatedKeywords = [
    'uginanie',
    'curl',
    'prostowanie',
    'unoszenie bokiem',
    'lateral raise',
    'rozpięt',
    'wspięcia',
    'łydk',
    'triceps',
  ];
  if (isolatedKeywords.any(name.contains)) {
    return const RestPrescription(seconds: 60, label: 'Ćwiczenie izolowane');
  }
  const compoundKeywords = [
    'przysiad',
    'squat',
    'wycisk',
    'bench',
    'podciąg',
    'pullup',
    'wiosł',
    'row',
    'wykrok',
    'lunge',
    'pomp',
    'dip',
    'hip thrust',
    'overhead',
  ];
  if (compoundKeywords.any(name.contains) ||
      exercise.supportingMuscles.length >= 2) {
    return const RestPrescription(
        seconds: 120, label: 'Ćwiczenie wielostawowe');
  }
  return const RestPrescription(seconds: 75, label: 'Ćwiczenie pomocnicze');
}

/// Etykieta przerwy dla recepty: uwzględnia wydłużenie przy słabej regeneracji
/// oraz jawną przerwę z planu.
///
/// [baseRestSeconds] to przerwa bazowa JUŻ ROZWIĄZANA (po heurystyce), więc nie
/// można jej podać z powrotem do [baseRestFor] jako „przerwy z planu" — trzeba
/// porównać ją z wartością, którą dobrałby sam typ ćwiczenia.
String restLabelFor(
  Exercise exercise, {
  required int plannedReps,
  required int baseRestSeconds,
  required int effectiveRestSeconds,
}) {
  if (effectiveRestSeconds > baseRestSeconds) {
    return 'Wydłużona — słabsza regeneracja';
  }
  final byType = baseRestFor(
    exercise,
    plannedReps: plannedReps,
    plannedRestSeconds: kUnsetRestSeconds,
  );
  return baseRestSeconds == byType.seconds
      ? byType.label
      : 'Przerwa ustawiona w planie';
}

// ============================================================================
// Zakresy powtórzeń wg celu
// ============================================================================

({int min, int max}) targetRepRange(String goal) {
  final g = goal.toLowerCase();
  if (g.contains('sił') || g.contains('sil') || g.contains('strength')) {
    return (min: 4, max: 6);
  }
  if (g.contains('redu') ||
      g.contains('spal') ||
      g.contains('fat') ||
      g.contains('kond') ||
      g.contains('wydol')) {
    return (min: 12, max: 18);
  }
  if (g.contains('masa') ||
      g.contains('hipert') ||
      g.contains('mięś') ||
      g.contains('mies')) {
    return (min: 8, max: 12);
  }
  return (min: 8, max: 12); // rekompozycja / domyślnie
}

// ============================================================================
// Klasyfikacja ćwiczenia (izolacja vs wielostawowe) i bezpieczny skok
// ============================================================================

const Set<MuscleGroup> _isolationGroups = {
  MuscleGroup.biceps,
  MuscleGroup.triceps,
  MuscleGroup.forearms,
  MuscleGroup.calves,
};

bool isIsolationExercise(Exercise exercise) {
  final groups = exercise.muscleGroups;
  final primary = groups.isEmpty ? MuscleGroup.other : groups.first;
  if (_isolationGroups.contains(primary)) return true;
  final name = exercise.name.toLowerCase();
  return name.contains('unoszenie') ||
      name.contains('uginanie') ||
      name.contains('rozpiętki') ||
      name.contains('rozpietki') ||
      name.contains('wznosy') ||
      name.contains('prostowanie') && !name.contains('tułow');
}

/// Bezpieczny krok ciężaru (kg) dla ćwiczenia i poziomu użytkownika.
double safeWeightStepKg(Exercise exercise, String level) {
  final isolation = isIsolationExercise(exercise);
  final normalized = normalizeTrainingLevel(level);
  if (isolation) {
    return normalized == 'Zaawansowany' ? 1.0 : 1.25;
  }
  // Wielostawowe — większy, ale rozsądny skok.
  switch (normalized) {
    case 'Początkujący':
      return 2.5;
    case 'Zaawansowany':
      return 2.5;
    default:
      return 2.5;
  }
}

double _levelStrengthFactor(String level) {
  switch (normalizeTrainingLevel(level)) {
    case 'Zaawansowany':
      return 1.3;
    case 'Średniozaawansowany':
      return 1.0;
    default:
      return 0.72;
  }
}

// ============================================================================
// Model obciążenia: czym ćwiczenie jest obciążane
// ============================================================================

/// Sposób obciążenia ćwiczenia — decyduje o punkcie startowym ORAZ o suficie
/// realnego ciężaru.
///
/// PROBLEM, KTÓRY TO ROZWIĄZUJE: sam wzorzec ruchu (np. „przysiad") nie mówi
/// nic o tym, ile da się w nim unieść. Goblet squat to przysiad, ale ciężar
/// trzyma się w jednym hantlu/kettlebellu przy mostku — 0,75 masy ciała
/// (rozsądne dla przysiadu ze sztangą) daje tam wartość fizycznie nieosiągalną.
/// Dlatego ułamek masy ciała i twardy sufit liczymy PER IMPLEMENT, nie per ruch.
enum ExerciseLoadStyle {
  /// Brak ciężaru zewnętrznego (masa ciała, guma, ćwiczenie czasowe).
  none,

  /// Sztanga — ciężar całkowity na gryfie.
  barbell,

  /// Para hantli (jeden w każdej ręce) — wpisujemy ciężar JEDNEGO hantla.
  dumbbellPair,

  /// JEDEN ciężar trzymany oburącz: goblet, kettlebell przy mostku, hantel
  /// pionowo. Tu limit narzuca chwyt i pozycja, a nie siła nóg.
  singleImplement,

  /// Maszyna / wyciąg — stos ciężarków.
  machine,
}

const List<String> _singleImplementNames = [
  'goblet',
  'kettlebell',
  'kettlebel',
  'swing',
  'wymach',
  'przysiad z ciężarem przed',
];

const List<String> _dumbbellPairNames = [
  'hantli',
  'hantlami',
  'hantle',
  'dumbbell',
];

/// Sposób obciążenia ćwiczenia (sprzęt + nazwa).
ExerciseLoadStyle loadStyleFor(Exercise exercise) {
  final entryType = exercise.entryType;
  if (!entryType.showsWeight || entryType.usesBodyweight) {
    return ExerciseLoadStyle.none;
  }
  final name = exercise.name.toLowerCase();
  final equipment = exercise.equipment.toLowerCase();

  // Nazwa ma pierwszeństwo: „Goblet squat" ma sprzęt „hantel / kettlebell",
  // ale sposób trzymania jednoznacznie wskazuje jeden implement.
  if (_singleImplementNames.any(name.contains)) {
    return ExerciseLoadStyle.singleImplement;
  }
  final types = EquipmentType.fromText(exercise.equipment);
  if (types.contains(EquipmentType.barbell) && !equipment.startsWith('hant')) {
    return ExerciseLoadStyle.barbell;
  }
  if (types.contains(EquipmentType.machine) ||
      types.contains(EquipmentType.cable)) {
    return ExerciseLoadStyle.machine;
  }
  if (types.contains(EquipmentType.kettlebell) &&
      !types.contains(EquipmentType.dumbbell)) {
    return ExerciseLoadStyle.singleImplement;
  }
  if (types.contains(EquipmentType.dumbbell)) {
    // Hantel W LICZBIE POJEDYNCZEJ („hantel") to jeden ciężar; „hantle" /
    // „z hantlami" to para.
    if (_dumbbellPairNames.any(name.contains) ||
        equipment.contains('hantle') ||
        equipment.contains('hantlami')) {
      return ExerciseLoadStyle.dumbbellPair;
    }
    return equipment.contains('hantel')
        ? ExerciseLoadStyle.singleImplement
        : ExerciseLoadStyle.dumbbellPair;
  }
  if (types.contains(EquipmentType.barbell)) return ExerciseLoadStyle.barbell;
  return ExerciseLoadStyle.none;
}

/// Ułamek masy ciała jako punkt wyjścia dla ciężaru roboczego SZTANGOWEGO
/// (ostrożny). Dla innych implementów jest przeliczany w [_startFractionFor].
double _barbellFractionFor(Exercise exercise) {
  final groups = exercise.muscleGroups;
  final primary = groups.isEmpty ? MuscleGroup.other : groups.first;
  final name = exercise.name.toLowerCase();
  // Duże wzorce dolne.
  if (name.contains('martwy') || name.contains('deadlift')) return 0.9;
  if (name.contains('przysiad') || name.contains('squat')) return 0.75;
  switch (primary) {
    case MuscleGroup.quadriceps:
    case MuscleGroup.hamstrings:
    case MuscleGroup.glutes:
      return 0.6;
    case MuscleGroup.back:
    case MuscleGroup.chest:
      return 0.45;
    case MuscleGroup.shoulders:
      return 0.3;
    case MuscleGroup.biceps:
    case MuscleGroup.triceps:
    case MuscleGroup.forearms:
      return 0.14;
    case MuscleGroup.calves:
      return 0.5;
    default:
      return 0.25;
  }
}

/// Ułamek masy ciała na START dla danego implementu.
double _startFractionFor(Exercise exercise, ExerciseLoadStyle style) {
  final barbell = _barbellFractionFor(exercise);
  switch (style) {
    case ExerciseLoadStyle.none:
      return 0;
    case ExerciseLoadStyle.barbell:
      return barbell;
    case ExerciseLoadStyle.machine:
      // Maszyna prowadzi ruch — nieco więcej niż wolny ciężar, ale bez przesady.
      return barbell * 0.95;
    case ExerciseLoadStyle.dumbbellPair:
      // Ciężar JEDNEGO hantla ≈ 40% odpowiednika sztangowego.
      return barbell * 0.40;
    case ExerciseLoadStyle.singleImplement:
      // Jeden ciężar trzymany przy tułowiu — ogranicza go chwyt i pozycja,
      // nie siła partii. Stąd niski, płaski ułamek zamiast ułamka ruchu.
      return math.min(barbell * 0.35, 0.28);
  }
}

/// TWARDY sufit ciężaru roboczego dla ćwiczenia — granica fizycznego sensu.
///
/// Zwraca 0, gdy ćwiczenie nie używa ciężaru zewnętrznego. Sufit obowiązuje na
/// KOŃCU doboru (po progresji i po skalowaniu fazą cyklu), więc żadna ścieżka
/// nie może wypuścić wartości nieosiągalnej danym sprzętem.
double maxPracticalLoadKg(Exercise exercise, CoachContext ctx) {
  final style = loadStyleFor(exercise);
  if (style == ExerciseLoadStyle.none) return 0;
  final bw = ctx.bodyWeightKg > 0 ? ctx.bodyWeightKg : 75;
  final sexMult = ctx.isFemale ? 0.7 : 1.0;
  switch (style) {
    case ExerciseLoadStyle.none:
      return 0;
    case ExerciseLoadStyle.barbell:
      return bw * 2.5 * sexMult;
    case ExerciseLoadStyle.machine:
      return bw * 2.2 * sexMult;
    case ExerciseLoadStyle.dumbbellPair:
      // Jeden hantel: nawet mocni ludzie rzadko przekraczają 50–60 kg na rękę.
      return math.min(bw * 0.75, 60.0) * sexMult;
    case ExerciseLoadStyle.singleImplement:
      // Goblet / kettlebell przy mostku — powyżej ~40 kg chwyt jest granicą.
      return math.min(bw * 0.40, 40.0) * sexMult;
  }
}

/// Przycina ciężar do [maxPracticalLoadKg] (0 = brak limitu / brak ciężaru).
double clampToPracticalLoad(
  double weightKg,
  Exercise exercise,
  CoachContext ctx,
) {
  if (weightKg <= 0) return weightKg;
  final ceiling = maxPracticalLoadKg(exercise, ctx);
  if (ceiling <= 0 || weightKg <= ceiling) return weightKg;
  return roundToPlate(ceiling, step: safeWeightStepKg(exercise, ctx.level));
}

/// Zaokrągla ciężar do sensownego kroku (2.5 kg dla większych, 1 kg dla małych).
double roundToPlate(double weightKg, {double step = 2.5}) {
  if (weightKg <= 0) return 0;
  final rounded = (weightKg / step).round() * step;
  return rounded < step ? step : double.parse(rounded.toStringAsFixed(2));
}

/// Ostrożny startowy ciężar dla ćwiczenia z ciężarem, gdy brak historii.
/// NIE wynika ze zdjęcia sylwetki — z antropometrii, poziomu i SPOSOBU
/// OBCIĄŻENIA ([loadStyleFor]), a na końcu jest przycięty do fizycznego sufitu.
double estimateInitialWeight(Exercise exercise, CoachContext ctx) {
  final entryType = exercise.entryType;
  if (!entryType.showsWeight || entryType.usesBodyweight) return 0;
  final style = loadStyleFor(exercise);
  if (style == ExerciseLoadStyle.none) return 0;
  final bw = ctx.bodyWeightKg > 0 ? ctx.bodyWeightKg : 75;
  final fraction = _startFractionFor(exercise, style);
  final levelMult = _levelStrengthFactor(ctx.level);
  final sexMult = ctx.isFemale ? 0.65 : 1.0;
  // Start kalibracyjny jest CELOWO ostrożny (×0.82), żeby pierwsze serie były
  // pewne i bezpieczne — dokładność rośnie po kilku wykonaniach.
  final raw = bw * fraction * levelMult * sexMult * 0.82;
  final step = safeWeightStepKg(exercise, ctx.level);
  return clampToPracticalLoad(roundToPlate(raw, step: step), exercise, ctx);
}

// ============================================================================
// Rekomendacja serii
// ============================================================================

const int kCalibrationSessions = 3;

SetRecommendation recommendSet({
  required Exercise exercise,
  required int plannedSets,
  required int plannedReps,
  required double plannedWeightKg,
  required int plannedDurationSec,
  required int plannedRestSeconds,
  required CoachContext ctx,
  List<CoachHistorySample> history = const [],
  double recoveryPercent = 100,
}) {
  final entryType = exercise.entryType;
  final range = targetRepRange(ctx.goal);
  final reasons = <String>[];
  final isCalibrating = history.length < kCalibrationSessions;

  // Odpoczynek: przerwa bazowa (z planu albo dobrana do typu ćwiczenia),
  // wydłużona gdy regeneracja słaba. Liczona TU i zapisywana w recepcie —
  // timer odpoczynku czyta tę samą wartość, więc plan i timer się nie rozjeżdżają.
  var rest = baseRestFor(
    exercise,
    plannedReps: plannedReps,
    plannedRestSeconds: plannedRestSeconds,
  ).seconds;
  if (recoveryPercent < 60) {
    rest += 20;
    reasons.add(
        'Regeneracja partii ${recoveryPercent.round()}% — dłuższa przerwa.');
  }

  // Ćwiczenia czasowe / mobilność — prowadzimy czasem, nie ciężarem.
  if (entryType.showsDuration && !entryType.showsReps) {
    final baseDuration = plannedDurationSec > 0
        ? plannedDurationSec
        : (exercise.defaultDurationSec > 0 ? exercise.defaultDurationSec : 40);
    var duration = baseDuration;
    // Bierzemy WYŁĄCZNIE ostatni WIARYGODNY zapis czasu (walidacja odsiewa
    // uszkodzone/sztuczne wartości, np. czas całej sesji podzielony przez liczbę
    // ćwiczeń). Bez tego deska 45 s dostawała rekomendację ~308 s.
    final lastValid = _lastPlausibleDuration(history, baseDuration);
    if (!isCalibrating && lastValid != null) {
      if (lastValid.allSetsCompleted &&
          lastValid.timeVerified &&
          recoveryPercent >= 60) {
        // Mobilność progresujemy jakością/regularnością, nie „na siłę" czasem.
        if (entryType == ExerciseEntryType.mobility) {
          duration = lastValid.durationSec;
          reasons.add('Utrzymaj czas i skup się na płynnym zakresie ruchu.');
        } else {
          duration = lastValid.durationSec + 5;
          reasons.add('Poprzedni czas utrzymany stabilnie — dokładamy 5 s.');
        }
      } else {
        duration = lastValid.durationSec;
        reasons.add('Utrzymujemy dotychczasowy czas serii.');
      }
    } else if (!isCalibrating && history.isNotEmpty) {
      // Historia jest, ale bez wiarygodnego czasu — zostajemy przy bazie.
      reasons
          .add('Brak wiarygodnego czasu w historii — utrzymuję plan bazowy.');
    }
    if (isCalibrating) {
      reasons.add('Ćwiczenie czasowe — utrzymaj kontrolę do końca.');
    }
    return SetRecommendation(
      sets: plannedSets,
      reps: 0,
      weightKg: 0,
      durationSec: duration,
      restSeconds: rest,
      reasons: reasons,
      isCalibrating: isCalibrating,
      calibrationNote: isCalibrating ? kCalibrationMessage : '',
    );
  }

  // Cel powtórzeń w zakresie strategii.
  var reps = plannedReps > 0 ? plannedReps : range.max;
  reps = reps.clamp(range.min, range.max);

  double weight;
  if (entryType.usesBodyweight || !entryType.showsWeight) {
    // Masa ciała — dodatkowy ciężar 0 na start; progresja przez powtórzenia.
    weight = history.isEmpty ? 0 : history.last.weightKg;
    if (isCalibrating) {
      reasons.add(
          'Ćwiczenie z masy ciała — rozwijamy powtórzenia, potem trudniejszy wariant.');
    }
  } else if (history.isEmpty) {
    weight = plannedWeightKg > 0
        ? plannedWeightKg
        : estimateInitialWeight(exercise, ctx);
    reasons.add(
        'Ostrożny start — Trainer poznaje Twoje możliwości w tym ćwiczeniu.');
  } else {
    final last = history.last;
    weight = last.weightKg > 0
        ? last.weightKg
        : (plannedWeightKg > 0
            ? plannedWeightKg
            : estimateInitialWeight(exercise, ctx));
    if (!isCalibrating) {
      final decision = decideProgression(
        exercise: exercise,
        ctx: ctx,
        history: history,
        recoveryPercent: recoveryPercent,
        // Pewność analizy OSTATNIEJ sesji realnie zasila bezpiecznik „przy
        // niskiej pewności nie zmieniamy obciążenia". Wcześniej parametr nie był
        // przekazywany, więc bezpiecznik nigdy nie działał w aplikacji.
        lastConfidence: history.last.confidence,
      );
      switch (decision.action) {
        case CoachProgressionAction.increaseWeight:
          weight = roundToPlate(weight + decision.weightDeltaKg,
              step: safeWeightStepKg(exercise, ctx.level));
          reasons.add(decision.reason);
          break;
        case CoachProgressionAction.increaseReps:
          reps = (reps + decision.repDelta).clamp(range.min, range.max);
          reasons.add(decision.reason);
          break;
        case CoachProgressionAction.decreaseWeight:
        case CoachProgressionAction.deload:
          weight = roundToPlate(weight + decision.weightDeltaKg,
              step: safeWeightStepKg(exercise, ctx.level));
          reasons.add(decision.reason);
          break;
        default:
          reasons.add(decision.reason);
      }
    }
  }

  // Faza cyklu (deload i rampa po nim) przycina ciężar roboczy DOPIERO po
  // decyzji progresji — historia i regeneracja nadal rządzą doborem bazowym.
  final cycleFactor = ctx.cycleIntensity.clamp(0.4, 1.6);
  if (weight > 0 && (cycleFactor < 0.99 || cycleFactor > 1.01)) {
    weight = roundToPlate(weight * cycleFactor,
        step: safeWeightStepKg(exercise, ctx.level));
    final percent = (cycleFactor * 100).round();
    reasons.add(cycleFactor <= 0.7
        ? 'Deload — ciężar zredukowany do ok. $percent%.'
        : (cycleFactor > 1.01
            ? 'Ręczne podkręcenie — ciężar ok. $percent% roboczego.'
            : 'Faza cyklu — ciężar ok. $percent% roboczego.'));
  }

  // OSTATNIA bramka: ciężar nie może przekroczyć fizycznego sensu ćwiczenia
  // (np. goblet squat ≠ przysiad ze sztangą). Sufit stoi PO progresji i PO
  // skalowaniu cyklem, więc żadna ścieżka go nie omija.
  final cappedWeight = clampToPracticalLoad(weight, exercise, ctx);
  if (cappedWeight < weight) {
    reasons.add(
        'Ciężar ograniczony do realnego maksimum dla tego sposobu trzymania '
        '(${_fmt(cappedWeight)} kg).');
  }
  weight = cappedWeight;

  if (reasons.isEmpty) {
    reasons.add('Cel: ${_goalLabel(ctx.goal)}.');
  }

  return SetRecommendation(
    sets: plannedSets < 1 ? 1 : plannedSets,
    reps: reps,
    weightKg: weight,
    durationSec: 0,
    restSeconds: rest,
    reasons: reasons,
    isCalibrating: isCalibrating,
    calibrationNote: isCalibrating ? kCalibrationMessage : '',
  );
}

const String kCalibrationMessage =
    'Trainer poznaje Twoje możliwości w tym ćwiczeniu. Dokładność rekomendacji '
    'wzrośnie po kilku wykonaniach.';

String _goalLabel(String goal) {
  final g = goal.toLowerCase();
  if (g.contains('sił') || g.contains('sil')) return 'rozwój siły';
  if (g.contains('redu') || g.contains('spal')) return 'redukcja';
  if (g.contains('kond') || g.contains('wydol')) return 'kondycja';
  if (g.contains('masa') || g.contains('mięś') || g.contains('mies')) {
    return 'rozwój masy mięśniowej';
  }
  return 'rozwój sylwetki';
}

// ============================================================================
// Szacowanie wysiłku (ukryte RPE) + pewność
// ============================================================================

ExertionEstimate estimateExertion({
  required SetOutcome outcome,
  required Exercise exercise,
  required int plannedReps,
  required int actualReps,
  required double weightKg,
  int activeSeconds = 0,
  bool timeVerified = true,
  int plannedRestSeconds = 0,
  int actualRestSeconds = 0,
  double recoveryPercent = 100,
  int? heartRateBpm,
  int age = 30,
  int setIndex = 0,
  int firstSetReps = 0,
}) {
  final factors = <String>[];
  double rpe;
  double confidence = 0.6;

  switch (outcome) {
    case SetOutcome.asPlanned:
      rpe = 7.0;
      factors.add('Seria ukończona zgodnie z planem.');
      confidence += 0.15;
      break;
    case SetOutcome.notCompleted:
      rpe = 9.0;
      factors.add('Seria nieukończona — bliskie maksimum lub za duży ciężar.');
      confidence += 0.1;
      break;
    case SetOutcome.interrupted:
      rpe = 6.0;
      factors.add('Seria przerwana — wysiłek trudny do oceny.');
      confidence -= 0.3;
      break;
    case SetOutcome.didDifferently:
      rpe = 7.0;
      factors.add('Wykonano inaczej niż zaplanowano.');
      break;
  }

  // Spadek wydajności między seriami (nie sam czas!).
  if (firstSetReps > 0 && actualReps > 0 && setIndex > 0) {
    final drop = (firstSetReps - actualReps) / firstSetReps;
    if (drop >= 0.3) {
      rpe += 1.0;
      factors.add('Wyraźny spadek powtórzeń względem pierwszej serii.');
    } else if (drop >= 0.15) {
      rpe += 0.5;
    }
  }

  // Wykonanie ponad plan → łatwiej niż zakładano.
  if (plannedReps > 0 &&
      actualReps > plannedReps &&
      outcome == SetOutcome.asPlanned) {
    rpe -= 0.5;
    factors.add('Powtórzeń więcej niż w planie — jest zapas.');
  }

  // Regeneracja: słaba partia → subiektywnie ciężej.
  if (recoveryPercent < 60) {
    rpe += 0.5;
    factors.add('Niska regeneracja partii (${recoveryPercent.round()}%).');
  }

  // Tętno (jeśli z zegarka) — realny sygnał wysiłku + pewność.
  if (heartRateBpm != null && heartRateBpm > 0) {
    final maxHr = 220 - (age > 0 ? age : 30);
    final reserve = ((heartRateBpm - 60) / (maxHr - 60)).clamp(0.0, 1.2);
    if (reserve >= 0.85) {
      rpe += 0.7;
      factors.add('Wysokie tętno ($heartRateBpm bpm).');
    } else if (reserve <= 0.5) {
      rpe -= 0.3;
    }
    confidence += 0.15;
    factors.add('Dostępne dane tętna.');
  } else {
    factors.add('Brak danych tętna z zegarka.');
  }

  // Czas serii — TYLKO jako sygnał pewności, nie jako miara wysiłku.
  final typical =
      _typicalSetSeconds(exercise, actualReps > 0 ? actualReps : plannedReps);
  if (activeSeconds > 0 && timeVerified) {
    if (typical > 0 && activeSeconds > typical * 4) {
      confidence -= 0.35;
      factors.add('Nietypowo długi czas serii — oznaczony jako niepewny.');
    } else if (typical > 0 &&
        activeSeconds >= typical * 0.5 &&
        activeSeconds <= typical * 2.5) {
      confidence += 0.15;
      factors.add('Czas serii w typowym zakresie.');
    }
  } else if (activeSeconds > 0 && !timeVerified) {
    confidence -= 0.3;
    factors.add('Czas niezweryfikowany (tło aplikacji / zatrzymany timer).');
  }

  // Odpoczynek zgodny z planem podnosi pewność.
  if (plannedRestSeconds > 0 && actualRestSeconds > 0) {
    final ratio = actualRestSeconds / plannedRestSeconds;
    if (ratio >= 0.7 && ratio <= 1.6) {
      confidence += 0.05;
    } else {
      confidence -= 0.05;
    }
  }

  rpe = rpe.clamp(1.0, 10.0);
  confidence = confidence.clamp(0.1, 0.98);
  return ExertionEstimate(rpe: rpe, confidence: confidence, factors: factors);
}

/// Orientacyjny typowy czas serii (s) — do wykrywania nietypowo długiego czasu.
int _typicalSetSeconds(Exercise exercise, int reps) {
  final type = exercise.entryType;
  if (type.showsDuration && !type.showsReps) {
    return exercise.defaultDurationSec > 0 ? exercise.defaultDurationSec : 60;
  }
  if (reps <= 0) return 45;
  // ~3–4 s na powtórzenie pod obciążeniem.
  final seconds = reps * 3.5;
  return seconds.clamp(10, 180).round();
}

/// Czy zarejestrowany czas serii jest nietypowo długi (do potwierdzenia przez
/// użytkownika — domyślnie NIE liczymy go do RPE/regeneracji/progresji).
bool isSetDurationSuspicious(Exercise exercise, int reps, int activeSeconds) {
  if (activeSeconds <= 0) return false;
  final typical = _typicalSetSeconds(exercise, reps);
  // Bieg/cardio bez krótkiego limitu.
  if (exercise.entryType == ExerciseEntryType.cardioDistanceTime ||
      exercise.entryType == ExerciseEntryType.cardioHealthConnect) {
    return false;
  }
  return activeSeconds > typical * 4 && activeSeconds > 240;
}

/// Czy historyczny czas serii ([candidateSec]) jest wiarygodny względem czasu
/// bazowego/planowanego ([baseSec]). Odsiewa uszkodzone/sztuczne wartości, np.
/// czas CAŁEJ sesji podzielony przez liczbę ćwiczeń (deska 45 s vs zapis 303 s).
///
/// Wiarygodny czas mieści się w rozsądnym oknie wokół bazy oraz w twardych
/// granicach fizjologicznych (3 s – 900 s).
bool isPlausibleHistoricalDuration(int baseSec, int candidateSec) {
  if (candidateSec <= 0) return false;
  if (candidateSec < 3 || candidateSec > 900) return false;
  final base = baseSec > 0 ? baseSec : 45;
  // Dolna granica: co najmniej ~40% bazy (albo 5 s). Górna: 3× baza + 60 s.
  final lower = math.max(5, (base * 0.4).floor());
  final upper = (base * 3 + 60).ceil();
  return candidateSec >= lower && candidateSec <= upper;
}

/// Ostatni (najnowszy) zapis historii z WIARYGODNYM czasem serii albo `null`.
CoachHistorySample? _lastPlausibleDuration(
  List<CoachHistorySample> history,
  int baseSec,
) {
  for (var i = history.length - 1; i >= 0; i--) {
    final sample = history[i];
    if (isPlausibleHistoricalDuration(baseSec, sample.durationSec)) {
      return sample;
    }
  }
  return null;
}

// ============================================================================
// Decyzja o progresji
// ============================================================================

ProgressionDecision decideProgression({
  required Exercise exercise,
  required CoachContext ctx,
  required List<CoachHistorySample> history,
  double recoveryPercent = 100,
  double lastConfidence = 1.0,
}) {
  if (history.isEmpty) {
    return const ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason: 'Brak historii — najpierw kalibracja ćwiczenia.',
    );
  }
  final last = history.last;
  final range = targetRepRange(ctx.goal);
  final entryType = exercise.entryType;

  // Niska pewność analizy → nie robimy dużych zmian (bezpieczeństwo).
  if (lastConfidence < 0.5) {
    return const ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason: 'Niska pewność analizy ostatniej serii — utrzymujemy parametry.',
    );
  }

  // Słaba regeneracja albo nieukończenie → hold/deload.
  if (!last.allSetsCompleted) {
    if (entryType.showsWeight && !entryType.usesBodyweight) {
      return ProgressionDecision(
        action: CoachProgressionAction.decreaseWeight,
        reason:
            'Ostatnia seria nieukończona — schodzimy o krok, żeby wrócić do czystych powtórzeń.',
        weightDeltaKg: -safeWeightStepKg(exercise, ctx.level),
      );
    }
    return const ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason: 'Ostatnia seria nieukończona — utrzymujemy parametry.',
    );
  }
  if (recoveryPercent < 55) {
    return ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason:
          'Regeneracja partii ${recoveryPercent.round()}% — utrzymujemy obciążenie.',
    );
  }

  // Ile ostatnich udanych sesji z rzędu. Ukończenie serii to sygnał OBIEKTYWNY
  // i on decyduje; RPE bierzemy pod uwagę tylko wtedy, gdy jest wiarygodne —
  // wysoki, realny wysiłek przerywa serię sukcesów. Nieznane RPE nie jest ani
  // dowodem lekkości, ani powodem do blokady (spec: punkt 5).
  var successStreak = 0;
  for (var i = history.length - 1; i >= 0; i--) {
    final sample = history[i];
    final struggled = sample.rpeReliable && sample.estimatedRpe >= 8.5;
    if (sample.allSetsCompleted && !struggled) {
      successStreak++;
    } else {
      break;
    }
  }

  if (successStreak < 2) {
    return const ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason: 'Utrwalamy technikę — jeszcze bez zwiększania obciążenia.',
    );
  }

  // Mobilność / rozciąganie — progres przez regularność i jakość ruchu,
  // nie przez „doładowanie" czasu ani obciążenia (spec: punkt 6D).
  if (entryType == ExerciseEntryType.mobility) {
    return const ProgressionDecision(
      action: CoachProgressionAction.hold,
      reason: 'Utrzymaj czas i skup się na płynnym, pełnym zakresie ruchu.',
    );
  }

  // Ćwiczenia czasowe / izometryczne — dokładamy czas.
  if (entryType.showsDuration && !entryType.showsReps) {
    return const ProgressionDecision(
      action: CoachProgressionAction.increaseDuration,
      reason: 'Stabilne, ukończone serie — dokładamy kilka sekund.',
      durationDeltaSec: 5,
    );
  }

  // Masa ciała — najpierw powtórzenia, potem trudniejszy wariant.
  if (entryType.usesBodyweight || !entryType.showsWeight) {
    if (last.reps >= range.max) {
      return const ProgressionDecision(
        action: CoachProgressionAction.harderVariant,
        reason:
            'Osiągnięty górny zakres powtórzeń — czas na trudniejszy wariant lub dodatkowy ciężar.',
      );
    }
    return const ProgressionDecision(
      action: CoachProgressionAction.increaseReps,
      reason: 'Dwie stabilne sesje z rzędu — dokładamy powtórzenie.',
      repDelta: 1,
    );
  }

  // Ciężar zewnętrzny — jeśli w górnym zakresie powtórzeń, zwiększ ciężar.
  if (last.reps >= range.max) {
    final step = safeWeightStepKg(exercise, ctx.level);
    // Przy suficie implementu (np. goblet squat) dokładanie kilogramów nie ma
    // dokąd pójść — progresujemy powtórzeniami/wariantem zamiast obiecywać
    // ciężar, który i tak zostanie przycięty.
    final ceiling = maxPracticalLoadKg(exercise, ctx);
    if (ceiling > 0 && last.weightKg + step > ceiling) {
      return const ProgressionDecision(
        action: CoachProgressionAction.harderVariant,
        reason:
            'Osiągnięty praktyczny limit ciężaru w tym ćwiczeniu — czas na '
            'trudniejszy wariant albo wolniejsze tempo.',
      );
    }
    return ProgressionDecision(
      action: CoachProgressionAction.increaseWeight,
      reason:
          'W ostatnich treningach ukończyłeś wszystkie serie stabilnie — proponuję +${_fmt(step)} kg.',
      weightDeltaKg: step,
    );
  }
  return const ProgressionDecision(
    action: CoachProgressionAction.increaseReps,
    reason: 'Dokładamy powtórzenie w tym samym ciężarze.',
    repDelta: 1,
  );
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
