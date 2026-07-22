/// Poprawna matematyka składu ciała (przebudowa analizy sylwetki).
///
/// Czysty Dart — bez Fluttera. Ten plik jest źródłem prawdy dla:
///  - rozłącznego podziału masy ciała (tłuszcz + FFM = 100% masy),
///  - parametrów FFM, które CZĘŚCIOWO SIĘ POKRYWAJĄ (mięśnie/woda/kości —
///    nigdy ich nie sumujemy),
///  - FFMI liczonego z FFM i wzrostu (nie z masy mięśni szkieletowych),
///  - zakresów niepewności i słownych poziomów pewności,
///  - walidacji biologicznej wyników analizy,
///  - oznaczania źródła każdej wartości (pomiar / obliczenie / szacunek AI /
///    synchronizacja).
///
/// Wszystkie zakresy referencyjne są zebrane w JEDNEJ konfiguracji
/// ([BodyCompositionReferenceRanges]) — patrz sekcja „Ograniczenia
/// implementacyjne" specyfikacji.
library;

import 'dart:math' as math;

// ============================================================================
// Źródła wartości
// ============================================================================

/// Źródło prezentowanej wartości — użytkownik nigdy nie powinien mylić
/// pomiaru z szacunkiem.
enum MeasurementSource {
  userMeasurement('user_measurement', 'Pomiar użytkownika'),
  deviceMeasurement('device_measurement', 'Pomiar z wagi / BIA'),
  computed('computed', 'Obliczenie'),
  aiEstimate('ai_estimate', 'Szacunek AI'),
  synced('synced', 'Synchronizacja');

  const MeasurementSource(this.id, this.label);

  final String id;
  final String label;

  static MeasurementSource fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final source in MeasurementSource.values) {
      if (source.id == normalized) return source;
    }
    return MeasurementSource.computed;
  }
}

// ============================================================================
// Poziomy pewności
// ============================================================================

/// Słowny poziom pewności szacunku.
enum ConfidenceLevel {
  low('niska'),
  moderate('umiarkowana'),
  high('wysoka');

  const ConfidenceLevel(this.label);

  final String label;
}

/// Mapuje procent pewności (0–100) na słowny poziom.
ConfidenceLevel confidenceLevelFor(double confidencePercent) {
  final percent = confidencePercent.isFinite ? confidencePercent : 0.0;
  if (percent >= 75) return ConfidenceLevel.high;
  if (percent >= 50) return ConfidenceLevel.moderate;
  return ConfidenceLevel.low;
}

// ============================================================================
// Konfiguracja zakresów referencyjnych (jedno miejsce, opisane)
// ============================================================================

/// Zakresy biologicznej wiarygodności używane w walidacji i clampach.
/// Nie są to normy medyczne — to szerokie granice fizycznej możliwości,
/// poza którymi wynik traktujemy jako niewiarygodny szacunek.
class BodyCompositionReferenceRanges {
  const BodyCompositionReferenceRanges({
    this.minBodyFatPercent = 3,
    this.maxBodyFatPercent = 60,
    this.minWaterPercent = 30,
    this.maxWaterPercent = 75,
    this.maxMuscleShareOfFfm = 0.75,
    this.minBonePercent = 1.5,
    this.maxBonePercent = 8,
    this.maxSkeletonPercent = 16,
    this.minWeightKg = 25,
    this.maxWeightKg = 350,
  });

  /// Tkanka tłuszczowa — biologicznie możliwy zakres (% masy ciała).
  final double minBodyFatPercent;
  final double maxBodyFatPercent;

  /// Całkowita woda organizmu (% masy ciała).
  final double minWaterPercent;
  final double maxWaterPercent;

  /// Mięśnie szkieletowe jako część FFM — powyżej tej proporcji wynik jest
  /// niewiarygodny (mięśnie nie mogą przekraczać beztłuszczowej masy).
  final double maxMuscleShareOfFfm;

  /// „Parametr kostny" rozumiany jako masa mineralna kości (% masy ciała).
  final double minBonePercent;
  final double maxBonePercent;

  /// Masa całego szkieletu (z wodą i tkankami) — górna granica % masy ciała.
  /// Wartości między [maxBonePercent] a tym progiem oznaczamy jako
  /// „szacowana masa szkieletu", nie „masa mineralna kości".
  final double maxSkeletonPercent;

  /// Masa ciała, dla której w ogóle liczymy skład.
  final double minWeightKg;
  final double maxWeightKg;
}

/// Domyślna konfiguracja zakresów referencyjnych.
const kBodyCompositionRanges = BodyCompositionReferenceRanges();

// ============================================================================
// Rozłączny podział masy ciała: tłuszcz + FFM
// ============================================================================

/// Rozłączny podział masy ciała. Gwarancje:
///  - [fatMassKg] + [fatFreeMassKg] == [bodyWeightKg] (co do grama),
///  - [bodyFatPercent] + [fatFreeMassPercent] == 100.0 (dokładnie),
///  - żadna wartość nie jest ujemna, NaN ani nieskończona.
class BodyCompositionBreakdown {
  const BodyCompositionBreakdown._({
    required this.bodyWeightKg,
    required this.bodyFatPercent,
    required this.fatMassKg,
    required this.fatFreeMassKg,
    required this.fatFreeMassPercent,
  });

  final double bodyWeightKg;

  /// Tkanka tłuszczowa w % masy ciała (zaokrąglona do 0.1 p.p.).
  final double bodyFatPercent;

  /// Masa tłuszczowa w kg (zaokrąglona do 0.1 kg).
  final double fatMassKg;

  /// Beztłuszczowa masa ciała (FFM) w kg — dokładnie masa − tłuszcz.
  final double fatFreeMassKg;

  /// FFM w % masy ciała — dokładnie 100 − [bodyFatPercent].
  final double fatFreeMassPercent;
}

/// Liczy rozłączny podział masy ciała.
///
/// Zwraca `null`, gdy dane wejściowe nie pozwalają na sensowny wynik:
/// brak masy, brak BF, wartości ujemne, NaN, nieskończoność albo BF ≥ 100%.
/// Zaokrąglenia są spójne: procenty sumują się DOKŁADNIE do 100, a kilogramy
/// DOKŁADNIE do masy ciała (FFM = masa − zaokrąglony tłuszcz).
BodyCompositionBreakdown? computeBodyCompositionBreakdown({
  required double bodyWeightKg,
  required double bodyFatPercent,
  BodyCompositionReferenceRanges ranges = kBodyCompositionRanges,
}) {
  if (!bodyWeightKg.isFinite || !bodyFatPercent.isFinite) return null;
  if (bodyWeightKg <= 0 || bodyFatPercent <= 0) return null;
  if (bodyFatPercent >= 100) return null;
  if (bodyWeightKg < ranges.minWeightKg || bodyWeightKg > ranges.maxWeightKg) {
    return null;
  }

  final roundedBf = _round1(bodyFatPercent);
  final fatMass = _round1(bodyWeightKg * roundedBf / 100);
  // FFM = DOKŁADNE dopełnienie masy (bez drugiego zaokrąglenia) — suma
  // kilogramów zawsze równa się masie ciała, niezależnie od precyzji wagi.
  final ffm = bodyWeightKg - fatMass;
  final ffmPercent = _round1(100.0 - roundedBf);
  if (ffm <= 0 || fatMass < 0) return null;

  return BodyCompositionBreakdown._(
    bodyWeightKg: bodyWeightKg,
    bodyFatPercent: roundedBf,
    fatMassKg: fatMass,
    fatFreeMassKg: ffm,
    fatFreeMassPercent: ffmPercent,
  );
}

// ============================================================================
// FFMI — zawsze z FFM i wzrostu
// ============================================================================

/// FFMI = FFM / wzrost² (opcjonalnie znormalizowane do 1.80 m).
/// NIGDY nie liczymy FFMI z masy mięśni szkieletowych.
/// Zwraca `null` przy braku danych albo wartościach niefizycznych.
double? computeFfmi({
  required double fatFreeMassKg,
  required double heightCm,
  bool normalizedTo180cm = true,
}) {
  if (!fatFreeMassKg.isFinite || !heightCm.isFinite) return null;
  if (fatFreeMassKg <= 0 || heightCm < 100 || heightCm > 250) return null;
  final heightM = heightCm / 100.0;
  var ffmi = fatFreeMassKg / (heightM * heightM);
  if (normalizedTo180cm) ffmi += 6.1 * (1.8 - heightM);
  if (!ffmi.isFinite || ffmi <= 0) return null;
  return _round1(ffmi);
}

// ============================================================================
// Zakres niepewności tkanki tłuszczowej
// ============================================================================

/// Prawdopodobny zakres BF (± margines zależny od pewności analizy).
/// Analiza ze zdjęcia to szacunek — margines rośnie przy niskiej pewności.
({double min, double max}) bodyFatRangeForConfidence({
  required double bodyFatPercent,
  required double confidencePercent,
  BodyCompositionReferenceRanges ranges = kBodyCompositionRanges,
}) {
  final bf = bodyFatPercent.isFinite ? bodyFatPercent : 0.0;
  final margin = switch (confidenceLevelFor(confidencePercent)) {
    ConfidenceLevel.high => 2.0,
    ConfidenceLevel.moderate => 3.0,
    ConfidenceLevel.low => 5.0,
  };
  final min = _round1(
    (bf - margin).clamp(ranges.minBodyFatPercent, ranges.maxBodyFatPercent),
  );
  final max = _round1(
    (bf + margin).clamp(ranges.minBodyFatPercent, ranges.maxBodyFatPercent),
  );
  return (min: min, max: max);
}

/// Margines błędu (w punktach procentowych BF), poniżej którego zmiany
/// między analizami NIE traktujemy jako pewnego postępu/regresu.
double bodyFatChangeErrorMarginPp(double confidencePercent) {
  return switch (confidenceLevelFor(confidencePercent)) {
    ConfidenceLevel.high => 1.0,
    ConfidenceLevel.moderate => 1.5,
    ConfidenceLevel.low => 2.5,
  };
}

/// Czy zmiana BF między dwiema analizami mieści się w marginesie błędu.
/// Porównanie używa NIŻSZEJ pewności z obu analiz (słabsze ogniwo).
bool bodyFatChangeWithinErrorMargin({
  required double deltaPercentPoints,
  required double olderConfidencePercent,
  required double newerConfidencePercent,
}) {
  final weakest = math.min(
    olderConfidencePercent.isFinite ? olderConfidencePercent : 0,
    newerConfidencePercent.isFinite ? newerConfidencePercent : 0,
  );
  return deltaPercentPoints.abs() <=
      bodyFatChangeErrorMarginPp(weakest.toDouble());
}

// ============================================================================
// Masa przy docelowym BF (zachowana FFM) — zawsze jako zakres
// ============================================================================

/// Szacowana masa ciała odpowiadająca docelowemu ZAKRESOWI BF przy
/// zachowaniu obecnej FFM. To szacunek — prezentuj z zastrzeżeniem.
({double min, double max})? weightRangeForTargetBodyFat({
  required double fatFreeMassKg,
  required double targetBodyFatMinPercent,
  required double targetBodyFatMaxPercent,
}) {
  if (!fatFreeMassKg.isFinite || fatFreeMassKg <= 0) return null;
  if (!targetBodyFatMinPercent.isFinite || !targetBodyFatMaxPercent.isFinite) {
    return null;
  }
  final low = math.min(targetBodyFatMinPercent, targetBodyFatMaxPercent);
  final high = math.max(targetBodyFatMinPercent, targetBodyFatMaxPercent);
  if (low <= 0 || high >= 100) return null;
  // masa = FFM / (1 − BF/100); niższy BF → niższa masa.
  final minWeight = fatFreeMassKg / (1 - low / 100);
  final maxWeight = fatFreeMassKg / (1 - high / 100);
  if (!minWeight.isFinite || !maxWeight.isFinite) return null;
  return (min: _round1(minWeight), max: _round1(maxWeight));
}

// ============================================================================
// Nazewnictwo parametru kostnego
// ============================================================================

/// Właściwa nazwa parametru kostnego w zależności od wartości.
/// AI/wzory nie mierzą masy mineralnej kości — nazwa musi być uczciwa.
String boneParameterLabel({
  required double bonePercent,
  BodyCompositionReferenceRanges ranges = kBodyCompositionRanges,
}) {
  if (!bonePercent.isFinite || bonePercent <= 0) {
    return 'Brak wystarczających danych';
  }
  if (bonePercent <= ranges.maxBonePercent) {
    return 'Szacowana masa mineralna kości';
  }
  if (bonePercent <= ranges.maxSkeletonPercent) {
    return 'Szacowana masa szkieletu';
  }
  return 'Parametr kostny (niewiarygodny)';
}

/// Czy parametr kostny wygląda biologicznie wiarygodnie (jako masa mineralna
/// LUB masa szkieletu). Powyżej progu szkieletu — ostrzegamy i pozwalamy pominąć.
bool boneParameterPlausible(
  double bonePercent, {
  BodyCompositionReferenceRanges ranges = kBodyCompositionRanges,
}) {
  return bonePercent.isFinite &&
      bonePercent > 0 &&
      bonePercent <= ranges.maxSkeletonPercent;
}

// ============================================================================
// Walidacja biologiczna
// ============================================================================

/// Pojedynczy problem znaleziony w walidacji (czytelny dla użytkownika).
class BodyCompositionIssue {
  const BodyCompositionIssue({
    required this.field,
    required this.message,
    this.blocking = false,
  });

  /// Które pole jest problematyczne ('bodyFat', 'muscle', 'water', 'bone',
  /// 'weight', 'general').
  final String field;
  final String message;

  /// Problem blokujący = wynik oznaczamy jako „niska wiarygodność".
  final bool blocking;
}

/// Wynik walidacji biologicznej analizy.
class BodyCompositionValidation {
  const BodyCompositionValidation({required this.issues});

  final List<BodyCompositionIssue> issues;

  /// Analiza wiarygodna = brak problemów blokujących.
  bool get isReliable => issues.every((issue) => !issue.blocking);

  /// Czy jest cokolwiek do pokazania użytkownikowi.
  bool get hasIssues => issues.isNotEmpty;

  List<String> get messages =>
      [for (final issue in issues) issue.message];
}

/// Walidacja biologiczna wyniku analizy PRZED zapisaniem go jako fakt.
///
/// Sprawdza m.in.: zakres BF, dodatnią FFM, mięśnie ≤ FFM, wodę w zakresie,
/// parametr kostny, NaN/nieskończoności. Wartości procentowe odnoszą się
/// do aktualnej masy ciała [bodyWeightKg].
BodyCompositionValidation validateBodyComposition({
  required double bodyWeightKg,
  required double bodyFatPercent,
  double musclePercent = 0,
  double waterPercent = 0,
  double bonePercent = 0,
  BodyCompositionReferenceRanges ranges = kBodyCompositionRanges,
}) {
  final issues = <BodyCompositionIssue>[];

  void issue(String field, String message, {bool blocking = false}) {
    issues.add(
      BodyCompositionIssue(field: field, message: message, blocking: blocking),
    );
  }

  bool broken(double value) => value.isNaN || value.isInfinite;

  if (broken(bodyWeightKg) || broken(bodyFatPercent) ||
      broken(musclePercent) || broken(waterPercent) || broken(bonePercent)) {
    issue('general', 'Wynik zawiera wartości nieliczbowe (NaN/∞).',
        blocking: true);
    return BodyCompositionValidation(issues: issues);
  }

  if (bodyWeightKg <= 0) {
    issue('weight', 'Brak masy ciała — uzupełnij profil albo dodaj pomiar.',
        blocking: true);
  } else if (bodyWeightKg < ranges.minWeightKg ||
      bodyWeightKg > ranges.maxWeightKg) {
    issue('weight', 'Masa ciała poza wiarygodnym zakresem.', blocking: true);
  }

  if (bodyFatPercent <= 0) {
    issue('bodyFat', 'Brak szacunku tkanki tłuszczowej.', blocking: true);
  } else if (bodyFatPercent < ranges.minBodyFatPercent ||
      bodyFatPercent > ranges.maxBodyFatPercent) {
    issue(
      'bodyFat',
      'Tkanka tłuszczowa ${bodyFatPercent.toStringAsFixed(1)}% jest poza '
          'biologicznie możliwym zakresem '
          '(${ranges.minBodyFatPercent.toStringAsFixed(0)}–'
          '${ranges.maxBodyFatPercent.toStringAsFixed(0)}%).',
      blocking: true,
    );
  }

  final ffmPercent = 100 - bodyFatPercent;
  if (bodyFatPercent > 0 && ffmPercent <= 0) {
    issue('bodyFat', 'FFM wyszłaby ujemna — wynik odrzucony.', blocking: true);
  }

  if (musclePercent > 0 && ffmPercent > 0) {
    final muscleShare = musclePercent / ffmPercent;
    if (musclePercent >= ffmPercent) {
      issue(
        'muscle',
        'Mięśnie szkieletowe (${musclePercent.toStringAsFixed(1)}%) nie mogą '
            'przekraczać beztłuszczowej masy ciała '
            '(${ffmPercent.toStringAsFixed(1)}%).',
        blocking: true,
      );
    } else if (muscleShare > ranges.maxMuscleShareOfFfm) {
      issue(
        'muscle',
        'Udział mięśni szkieletowych w FFM wygląda na zawyżony '
            '(${(muscleShare * 100).round()}% FFM).',
      );
    }
  }

  if (waterPercent > 0 &&
      (waterPercent < ranges.minWaterPercent ||
          waterPercent > ranges.maxWaterPercent)) {
    issue(
      'water',
      'Całkowita woda organizmu ${waterPercent.toStringAsFixed(1)}% jest poza '
          'typowym zakresem (${ranges.minWaterPercent.toStringAsFixed(0)}–'
          '${ranges.maxWaterPercent.toStringAsFixed(0)}%).',
    );
  }

  if (bonePercent > 0 && !boneParameterPlausible(bonePercent, ranges: ranges)) {
    issue(
      'bone',
      'Parametr kostny ${bonePercent.toStringAsFixed(1)}% masy ciała wygląda '
          'niewiarygodnie — traktuj go wyłącznie jako przybliżenie i możesz '
          'go pominąć.',
    );
  }

  return BodyCompositionValidation(issues: issues);
}

/// Stała informacja o nakładaniu się parametrów FFM — pokazywana w UI.
const kFfmOverlapExplanation =
    'Wartości mięśni, wody i kości częściowo się pokrywają. Nie należy ich '
    'sumować, ponieważ woda znajduje się między innymi w mięśniach, narządach '
    'i kościach.';

/// Stała informacja o charakterze analizy zdjęciowej.
const kPhotoAnalysisDisclaimer =
    'Analiza zdjęcia jest szacunkiem i nie zastępuje pomiaru DEXA, '
    'profesjonalnego pomiaru fałdów ani badania wykonywanego w kontrolowanych '
    'warunkach.';

/// Notka o ograniczeniach BMI przy rozwiniętej muskulaturze.
const kBmiCaveat =
    'BMI może zawyżać ocenę masy ciała u osób z rozwiniętą muskulaturą.';

/// Warunki porównywalnych zdjęć (przypomnienie przed kolejną analizą).
const List<String> kPhotoComparisonConditions = [
  'podobna pora dnia',
  'podobne oświetlenie',
  'ta sama odległość aparatu',
  'podobny kąt',
  'neutralna pozycja, bez celowego napinania mięśni',
  'zdjęcie przodu, boku i tyłu',
  'najlepiej przed treningiem i przed dużym posiłkiem',
  'podobny poziom nawodnienia',
];

double _round1(double value) => (value * 10).roundToDouble() / 10;
