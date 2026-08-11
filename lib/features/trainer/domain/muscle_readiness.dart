/// Wielowymiarowy model GOTOWOŚCI mięśnia (readiness) — czysty Dart.
///
/// Zastępuje pytanie „ile godzin minęło od treningu?" pytaniem „w jakim stanie
/// jest ten mięsień i do jakiego bodźca jest dziś gotowy?".
///
/// Regeneracja NIE jest jednym procesem, więc model rozdziela ją na składowe,
/// które mają różną dynamikę i różne przyczyny:
///
///  * [MuscleReadiness.localFatigue]         — lokalne zmęczenie mięśnia,
///  * [MuscleReadiness.neuromuscular]        — zmęczenie nerwowo-mięśniowe,
///  * [MuscleReadiness.structural]           — stres strukturalny / uszkodzenia,
///  * [MuscleReadiness.energy]               — zasoby energetyczne (glikogen),
///  * [MuscleReadiness.remodelling]          — okno przebudowy tkanki (MPS),
///  * [MuscleReadiness.subjective]           — sygnały subiektywne (DOMS, sen),
///  * [MuscleReadiness.adaptation]           — oswojenie z bodźcem (RBE),
///  * [MuscleReadiness.systemicFatigue]      — zmęczenie ogólnoustrojowe,
///  * [MuscleReadiness.accumulatedLoad]      — obciążenie ostre vs. przewlekłe.
///
/// PODSTAWY (patrz też komentarze przy krzywych w `recovery_engine.dart`):
///  * MacDougall 1995 (PMID 8563679) i Phillips 1997 (PMID 9252485) — MPS jest
///    PROCESEM, nie zegarem regeneracji; dlatego [remodelling] jest osobną,
///    informacyjną składową i NIE decyduje o gotowości,
///  * Damas 2016 (PMID 27219125) — uszkodzenie maleje wraz z adaptacją, stąd
///    [adaptation] modulująca składową strukturalną,
///  * González-Badillo 2016 (PMID 26667923), Pareja-Blanco 2017 (PMID 28965198),
///    Refalo 2023 (PMID 36752989) — bliskość upadku napędza przede wszystkim
///    [neuromuscular], w sposób CIĄGŁY (bez reguł „failure = +24 h"),
///  * Nosaka 2002 (PMID 12453160) — DOMS to sygnał pomocniczy, nie miara
///    uszkodzenia; stąd [subjective] jako modyfikator o ograniczonym wpływie,
///  * Chen 2019 (PMID 30663816) — partie różnią się reakcją, stąd profile
///    czasowe per mięsień zamiast jednego zestawu stałych.
library;

import 'dart:math' as math;

import 'body_muscle.dart';

/// Rodzaj PLANOWANEGO bodźca treningowego.
///
/// Gotowość nie jest jedną liczbą: mięsień może być gotowy na technikę i lekką
/// pracę, a jednocześnie nie na maksymalną siłę. Każdy rodzaj bodźca inaczej
/// waży składowe stanu mięśnia.
enum TrainingStimulusKind {
  /// Aktywna regeneracja / bardzo lekki ruch (przepływ krwi, mobilność).
  activeRecovery('Aktywna regeneracja'),

  /// Praca techniczna — lekkie ciężary, dużo zapasu.
  technique('Trening techniczny'),

  /// Umiarkowany trening w zapasie 3+ RIR.
  moderate('Umiarkowany trening'),

  /// Ciężki trening hipertroficzny (blisko upadku, duża objętość).
  hypertrophy('Ciężki trening hipertroficzny'),

  /// Praca nad maksymalną siłą (wysokie %1RM).
  maxStrength('Trening maksymalnej siły');

  const TrainingStimulusKind(this.label);

  final String label;

  /// Wagi składowych dla tego rodzaju bodźca.
  ///
  /// Siła maksymalna opiera się przede wszystkim o świeżość NERWOWĄ, hipertrofia
  /// o lokalne zmęczenie i stan strukturalny, a praca lekka prawie o nic —
  /// dlatego to samo 70% gotowości znaczy co innego dla różnych planów.
  ReadinessComponentWeights get weights {
    switch (this) {
      case TrainingStimulusKind.activeRecovery:
        return const ReadinessComponentWeights(
            local: 0.18, neural: 0.14, structural: 0.50, energy: 0.18);
      case TrainingStimulusKind.technique:
        return const ReadinessComponentWeights(
            local: 0.24, neural: 0.34, structural: 0.24, energy: 0.18);
      case TrainingStimulusKind.moderate:
        return const ReadinessComponentWeights(
            local: 0.34, neural: 0.24, structural: 0.22, energy: 0.20);
      case TrainingStimulusKind.hypertrophy:
        return const ReadinessComponentWeights(
            local: 0.38, neural: 0.22, structural: 0.20, energy: 0.20);
      case TrainingStimulusKind.maxStrength:
        return const ReadinessComponentWeights(
            local: 0.24, neural: 0.46, structural: 0.20, energy: 0.10);
    }
  }

  /// Jak mocno najsłabsza składowa „ciągnie w dół" wynik ogólny.
  ///
  /// Przy pracy maksymalnej jedno wyczerpane ogniwo waży dużo bardziej niż przy
  /// lekkiej sesji — dlatego ściąganie do minimum jest zależne od bodźca.
  double get weakestPull {
    switch (this) {
      case TrainingStimulusKind.activeRecovery:
        return 0.05;
      case TrainingStimulusKind.technique:
        return 0.10;
      case TrainingStimulusKind.moderate:
        return 0.15;
      case TrainingStimulusKind.hypertrophy:
        return 0.15;
      case TrainingStimulusKind.maxStrength:
        return 0.28;
    }
  }

  /// Ile „zapasu" ma dany bodziec: lekka praca jest wykonalna także wtedy, gdy
  /// mięsień nie jest w pełni świeży (Bartolomei 2019, PMID 30844990 — lekka
  /// sesja po dużej objętości nie jest kolejnym pełnym bodźcem).
  double get tolerance {
    switch (this) {
      case TrainingStimulusKind.activeRecovery:
        return 0.32;
      case TrainingStimulusKind.technique:
        return 0.20;
      case TrainingStimulusKind.moderate:
        return 0.08;
      case TrainingStimulusKind.hypertrophy:
        return 0.0;
      case TrainingStimulusKind.maxStrength:
        return -0.06;
    }
  }

  /// Domyślny bodziec używany tam, gdzie UI pokazuje jedną liczbę gotowości.
  static const TrainingStimulusKind defaultKind =
      TrainingStimulusKind.hypertrophy;
}

/// Wagi składowych gotowości dla danego rodzaju bodźca.
class ReadinessComponentWeights {
  const ReadinessComponentWeights({
    required this.local,
    required this.neural,
    required this.structural,
    required this.energy,
  });

  final double local;
  final double neural;
  final double structural;
  final double energy;
}

/// Powód (dodatni albo ujemny), który ukształtował gotowość / rekomendację.
///
/// Rekomendacje mają być WYTŁUMACZALNE — silnik zbiera powody zamiast zwracać
/// samą liczbę (spec: punkt 17).
class ReadinessReason {
  const ReadinessReason({
    required this.code,
    required this.label,
    required this.positive,
    this.weight = 1.0,
  });

  /// Stabilny klucz (`recoveredMuscle`, `poorSleep`, `secondaryMuscleFatigue`…).
  final String code;

  /// Czytelny opis po polsku.
  final String label;

  /// `true` = czynnik sprzyjający, `false` = czynnik obciążający.
  final bool positive;

  /// Siła wpływu 0–1 (do sortowania w UI).
  final double weight;

  String get sign => positive ? '+' : '−';

  @override
  String toString() => '$sign $label';
}

/// Stan JEDNEJ partii mięśniowej w modelu wielowymiarowym.
///
/// Wszystkie składowe są wyrażone jako ODZYSKANY ułamek 0–1 (1.0 = pełna
/// świeżość tego wymiaru), żeby dało się je porównywać i ważyć.
class MuscleReadiness {
  const MuscleReadiness({
    required this.muscle,
    this.localFatigue = 1,
    this.neuromuscular = 1,
    this.structural = 1,
    this.energy = 1,
    this.remodelling = 0,
    this.subjective = 1,
    this.adaptation = 0.5,
    this.systemicFatigue = 0,
    this.accumulatedLoad = 1,
    this.confidence = 0.3,
    this.lastStimulusAt,
    this.lastStimulusMagnitude = 0,
    this.totalStimulus = 0,
    this.lastExerciseNames = const [],
    this.lastSessionId = '',
    this.reasons = const [],
    this.hasData = false,
  });

  final BodyMuscle muscle;

  /// Lokalne zmęczenie mięśnia — odzyskane 0–1 (spec 1A).
  final double localFatigue;

  /// Regeneracja nerwowo-mięśniowa — odzyskana 0–1 (spec 1B).
  final double neuromuscular;

  /// Regeneracja strukturalna (uszkodzenia/stres mechaniczny) 0–1 (spec 1C).
  final double structural;

  /// Zasoby energetyczne (glikogen, nawodnienie) 0–1 (spec 1D).
  final double energy;

  /// Nasilenie przebudowy tkanki 0–1 (spec 1E). To NIE jest miara gotowości —
  /// wysoka wartość znaczy „trwa przebudowa", a nie „mięsień zablokowany".
  final double remodelling;

  /// Sygnały subiektywne (DOMS, samopoczucie, sen) 0–1 (spec 1F).
  final double subjective;

  /// Oswojenie z bodźcem 0–1: 0 = zupełnie nowy ruch, 1 = ruch wyćwiczony
  /// (repeated-bout effect; Howatson 2007, Damas 2016).
  final double adaptation;

  /// Zmęczenie ogólnoustrojowe 0–1 (0 = brak) — wspólne dla całego ciała.
  final double systemicFatigue;

  /// Relacja obciążenia ostrego do przewlekłego, 1.0 = zgodne z normą
  /// użytkownika, <1 = nagły skok objętości (spec 26).
  final double accumulatedLoad;

  /// Pewność prognozy 0–1 (spec 7).
  final double confidence;

  final DateTime? lastStimulusAt;

  /// Wielkość ostatniego bodźca w jednostkach modelu (1.0 ≈ solidne 3×10).
  final double lastStimulusMagnitude;

  /// Suma bodźców w oknie analizy (do klasyfikacji obciążenia).
  final double totalStimulus;

  final List<String> lastExerciseNames;
  final String lastSessionId;

  /// Najważniejsze powody aktualnego stanu (spec 17/20).
  final List<ReadinessReason> reasons;

  /// Czy w oknie analizy w ogóle był jakiś bodziec.
  final bool hasData;

  /// Gotowość 0–100 dla DOMYŚLNEGO bodźca (to pokazuje mapa regeneracji).
  double get readinessPercent =>
      readinessFor(TrainingStimulusKind.defaultKind);

  /// Gotowość 0–100 dla KONKRETNEGO rodzaju planowanego treningu (spec 3).
  double readinessFor(TrainingStimulusKind kind) {
    final w = kind.weights;
    final total = w.local + w.neural + w.structural + w.energy;
    final weighted = (localFatigue * w.local +
            neuromuscular * w.neural +
            structural * w.structural +
            energy * w.energy) /
        (total <= 0 ? 1 : total);
    final weakest = math.min(
      math.min(localFatigue, neuromuscular),
      math.min(structural, energy),
    );
    final pull = kind.weakestPull;
    var value = weighted * (1 - pull) + weakest * pull;

    // Zmęczenie ogólnoustrojowe i sygnały subiektywne działają jako
    // MODYFIKATORY o ograniczonym zakresie — nie mogą same „zablokować" partii
    // (Nosaka 2002: DOMS ≠ miara uszkodzenia).
    value *= (1 - systemicFatigue * 0.18).clamp(0.75, 1.0);
    value *= (0.88 + subjective * 0.12).clamp(0.85, 1.0);
    // Nagły skok obciążenia względem normy użytkownika obniża gotowość
    // ostrożnościowo (spec 26), ale maksymalnie o 12%.
    value *= accumulatedLoad.clamp(0.88, 1.0);

    // Zapas rodzaju bodźca: lekka praca jest wykonalna także przy niepełnej
    // świeżości (Bartolomei 2019).
    value += kind.tolerance * (1 - value);
    return (value * 100).clamp(0.0, 100.0);
  }

  MuscleReadiness copyWith({
    double? localFatigue,
    double? neuromuscular,
    double? structural,
    double? energy,
    double? remodelling,
    double? subjective,
    double? adaptation,
    double? systemicFatigue,
    double? accumulatedLoad,
    double? confidence,
    DateTime? lastStimulusAt,
    double? lastStimulusMagnitude,
    double? totalStimulus,
    List<String>? lastExerciseNames,
    String? lastSessionId,
    List<ReadinessReason>? reasons,
    bool? hasData,
  }) =>
      MuscleReadiness(
        muscle: muscle,
        localFatigue: localFatigue ?? this.localFatigue,
        neuromuscular: neuromuscular ?? this.neuromuscular,
        structural: structural ?? this.structural,
        energy: energy ?? this.energy,
        remodelling: remodelling ?? this.remodelling,
        subjective: subjective ?? this.subjective,
        adaptation: adaptation ?? this.adaptation,
        systemicFatigue: systemicFatigue ?? this.systemicFatigue,
        accumulatedLoad: accumulatedLoad ?? this.accumulatedLoad,
        confidence: confidence ?? this.confidence,
        lastStimulusAt: lastStimulusAt ?? this.lastStimulusAt,
        lastStimulusMagnitude:
            lastStimulusMagnitude ?? this.lastStimulusMagnitude,
        totalStimulus: totalStimulus ?? this.totalStimulus,
        lastExerciseNames: lastExerciseNames ?? this.lastExerciseNames,
        lastSessionId: lastSessionId ?? this.lastSessionId,
        reasons: reasons ?? this.reasons,
        hasData: hasData ?? this.hasData,
      );

  /// Skrócony, czytelny opis stanu — bez udawania precyzji medycznej (spec 24).
  String get headline {
    final percent = readinessPercent;
    if (!hasData) return 'Brak danych o obciążeniu tej partii.';
    if (percent >= 90) return 'Gotowa do pełnego treningu.';
    if (percent >= 75) return 'Dobra gotowość — pełny trening jest w porządku.';
    if (percent >= 55) {
      return 'Umiarkowana gotowość — rozważ mniejszą objętość lub intensywność.';
    }
    if (percent >= 35) {
      return 'Niska gotowość — lepiej lekki bodziec albo inna partia.';
    }
    return 'Bardzo niska gotowość — ta partia dostała niedawno mocny bodziec.';
  }
}

/// Zapisany „migawkowy" stan partii (spec 25).
///
/// Zapisywany ZDARZENIOWO (po treningu), nie co sekundę — pozwala później
/// zrobić wykresy, ocenić trafność prognoz i skalibrować model.
class RecoverySnapshot {
  const RecoverySnapshot({
    required this.timestamp,
    required this.muscle,
    required this.readiness,
    required this.localFatigue,
    required this.neuromuscular,
    required this.structural,
    required this.energy,
    required this.systemicFatigue,
    required this.confidence,
    this.mainReasons = const [],
    this.trigger = 'workout',
  });

  static const String schema = 'trainer.recovery_snapshot.v1';

  final DateTime timestamp;
  final BodyMuscle muscle;
  final double readiness;
  final double localFatigue;
  final double neuromuscular;
  final double structural;
  final double energy;
  final double systemicFatigue;
  final double confidence;
  final List<String> mainReasons;

  /// Co wywołało zapis: `workout` | `manual` | `daily`.
  final String trigger;

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'timestamp': timestamp.toIso8601String(),
        'muscle': muscle.key,
        'readiness': _round(readiness),
        'localFatigue': _round(localFatigue),
        'neuromuscular': _round(neuromuscular),
        'structural': _round(structural),
        'energy': _round(energy),
        'systemicFatigue': _round(systemicFatigue),
        'confidence': _round(confidence),
        if (mainReasons.isNotEmpty) 'mainReasons': mainReasons,
        'trigger': trigger,
      };

  static double _round(double value) =>
      double.parse(value.toStringAsFixed(4));

  static RecoverySnapshot? fromJson(Map<String, dynamic> json) {
    final muscle = BodyMuscle.fromKey(json['muscle']);
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    if (muscle == null || timestamp == null) return null;
    double num_(Object? value, [double fallback = 0]) =>
        (value as num?)?.toDouble() ?? fallback;
    return RecoverySnapshot(
      timestamp: timestamp,
      muscle: muscle,
      readiness: num_(json['readiness']),
      localFatigue: num_(json['localFatigue'], 1),
      neuromuscular: num_(json['neuromuscular'], 1),
      structural: num_(json['structural'], 1),
      energy: num_(json['energy'], 1),
      systemicFatigue: num_(json['systemicFatigue']),
      confidence: num_(json['confidence'], 0.3),
      mainReasons: [
        for (final reason in (json['mainReasons'] as List? ?? const []))
          reason.toString(),
      ],
      trigger: json['trigger']?.toString() ?? 'workout',
    );
  }

  /// Buduje migawkę ze stanu gotowości.
  factory RecoverySnapshot.from(
    MuscleReadiness readiness, {
    required DateTime timestamp,
    String trigger = 'workout',
  }) =>
      RecoverySnapshot(
        timestamp: timestamp,
        muscle: readiness.muscle,
        readiness: readiness.readinessPercent,
        localFatigue: readiness.localFatigue,
        neuromuscular: readiness.neuromuscular,
        structural: readiness.structural,
        energy: readiness.energy,
        systemicFatigue: readiness.systemicFatigue,
        confidence: readiness.confidence,
        mainReasons: [
          for (final reason in readiness.reasons.take(3)) reason.code,
        ],
        trigger: trigger,
      );
}

/// Indywidualna kalibracja regeneracji JEDNEJ partii (spec 6).
///
/// Model bazowy jest wspólny (evidence-based), a kalibracja przesuwa go
/// delikatnie pod konkretnego użytkownika. Zakres jest CELOWO wąski i wymaga
/// wielu obserwacji — pojedynczy dziwny trening nie może przestawić profilu.
class MuscleRecoveryCalibration {
  const MuscleRecoveryCalibration({
    this.tauScale = 1.0,
    this.observations = 0,
    this.lastUpdated,
  });

  /// Mnożnik stałych czasowych: <1 = użytkownik regeneruje się szybciej niż
  /// zakłada model bazowy, >1 = wolniej.
  final double tauScale;

  /// Liczba obserwacji, na których oparto korektę.
  final int observations;

  final DateTime? lastUpdated;

  /// Twarde granice korekty — model bazowy zawsze zostaje rozpoznawalny.
  static const double minScale = 0.72;
  static const double maxScale = 1.38;

  /// Ile obserwacji trzeba, żeby korekta w ogóle zaczęła działać.
  static const int minObservations = 3;

  /// Maksymalny krok pojedynczej obserwacji (odporność na anomalie).
  static const double maxStep = 0.035;

  /// Czy korekta jest już na tyle ugruntowana, żeby jej użyć.
  bool get isActive => observations >= minObservations;

  /// Efektywny mnożnik: przy małej liczbie obserwacji korekta jest wygaszana
  /// liniowo w stronę 1.0 (stopniowe uczenie, spec 6).
  double get effectiveScale {
    if (observations <= 0) return 1.0;
    final ramp = (observations / 10).clamp(0.0, 1.0);
    return (1.0 + (tauScale - 1.0) * ramp)
        .clamp(minScale, maxScale)
        .toDouble();
  }

  /// Wkład kalibracji w pewność prognozy (więcej obserwacji = pewniej).
  double get confidenceBonus => (observations / 25).clamp(0.0, 0.12).toDouble();

  /// Nowa kalibracja po obserwacji.
  ///
  /// [error] > 0 oznacza „model był zbyt OPTYMISTYCZNY" (prognoza wyższa niż
  /// realna wydajność) → regeneracja trwa dłużej → tauScale rośnie.
  /// [error] < 0 oznacza „model był zbyt KONSERWATYWNY" → tauScale maleje.
  /// [weight] 0–1 to pewność obserwacji.
  MuscleRecoveryCalibration updated({
    required double error,
    required double weight,
    DateTime? at,
  }) {
    final clampedWeight = weight.clamp(0.0, 1.0);
    if (clampedWeight <= 0.05) return this;
    // Odporność na anomalie: pojedynczy skrajny wynik jest ścinany.
    final boundedError = error.clamp(-1.0, 1.0);
    final step = (boundedError * clampedWeight * maxStep)
        .clamp(-maxStep, maxStep)
        .toDouble();
    return MuscleRecoveryCalibration(
      tauScale: (tauScale + step).clamp(minScale, maxScale).toDouble(),
      observations: observations + 1,
      lastUpdated: at ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tauScale': double.parse(tauScale.toStringAsFixed(4)),
        'observations': observations,
        if (lastUpdated != null) 'lastUpdated': lastUpdated!.toIso8601String(),
      };

  factory MuscleRecoveryCalibration.fromJson(Map<String, dynamic> json) =>
      MuscleRecoveryCalibration(
        tauScale: ((json['tauScale'] as num?)?.toDouble() ?? 1.0)
            .clamp(minScale, maxScale)
            .toDouble(),
        observations: (json['observations'] as num?)?.toInt() ?? 0,
        lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? ''),
      );
}

/// Zbiór kalibracji wszystkich partii (spec 6) + serializacja do prefs.
class RecoveryCalibrationProfile {
  const RecoveryCalibrationProfile({this.byMuscle = const {}});

  static const String storageKey = 'trainer_recovery_calibration_v1';

  final Map<BodyMuscle, MuscleRecoveryCalibration> byMuscle;

  static const RecoveryCalibrationProfile empty = RecoveryCalibrationProfile();

  MuscleRecoveryCalibration forMuscle(BodyMuscle muscle) =>
      byMuscle[muscle] ?? const MuscleRecoveryCalibration();

  bool get isEmpty => byMuscle.isEmpty;

  /// Ile partii ma już ugruntowaną kalibrację (do pewności i do UI).
  int get calibratedMuscleCount =>
      byMuscle.values.where((value) => value.isActive).length;

  RecoveryCalibrationProfile withMuscle(
    BodyMuscle muscle,
    MuscleRecoveryCalibration calibration,
  ) =>
      RecoveryCalibrationProfile(byMuscle: {...byMuscle, muscle: calibration});

  Map<String, dynamic> toJson() => {
        'version': 1,
        'muscles': {
          for (final entry in byMuscle.entries)
            entry.key.key: entry.value.toJson(),
        },
      };

  factory RecoveryCalibrationProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['muscles'];
    if (raw is! Map) return const RecoveryCalibrationProfile();
    final result = <BodyMuscle, MuscleRecoveryCalibration>{};
    for (final entry in raw.entries) {
      final muscle = BodyMuscle.fromKey(entry.key);
      if (muscle == null || entry.value is! Map) continue;
      result[muscle] = MuscleRecoveryCalibration.fromJson(
          Map<String, dynamic>.from(entry.value as Map));
    }
    return RecoveryCalibrationProfile(byMuscle: result);
  }
}

/// Warunki regeneracji spoza samego treningu: sen, odżywianie, aktywność dnia.
///
/// KAŻDE pole jest opcjonalne. Brak danych NIE psuje modelu — daje neutralny
/// modyfikator i NIŻSZĄ pewność prognozy (spec 9, 10, 31).
class RecoveryEnvironment {
  const RecoveryEnvironment({
    this.sleepMinutes = 0,
    this.sleepMinutesAverage = 0,
    this.intakeKcal = 0,
    this.targetKcal = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.waterMl = 0,
    this.bodyWeightKg = 0,
    this.dailyStepCount = 0,
    this.sorenessLevel = -1,
    this.wellbeingLevel = -1,
  });

  static const RecoveryEnvironment unknown = RecoveryEnvironment();

  /// Sen ostatniej nocy (min); 0 = brak danych.
  final int sleepMinutes;

  /// Średni sen z ostatnich dni (min); 0 = brak danych.
  final int sleepMinutesAverage;

  /// Spożycie kcal dnia; 0 = brak danych z Kalorii.
  final double intakeKcal;

  /// Cel kcal dnia; 0 = brak danych.
  final double targetKcal;
  final double proteinG;
  final double carbsG;
  final double waterMl;
  final double bodyWeightKg;

  /// Kroki dnia (aktywność pozatreningowa).
  final int dailyStepCount;

  /// Subiektywna bolesność 0–10 (−1 = nie podano).
  final double sorenessLevel;

  /// Subiektywne samopoczucie 0–10 (−1 = nie podano).
  final double wellbeingLevel;

  bool get hasSleepData => sleepMinutes > 0 || sleepMinutesAverage > 0;
  bool get hasNutritionData => intakeKcal > 0 || proteinG > 0 || carbsG > 0;
  bool get hasSubjectiveData => sorenessLevel >= 0 || wellbeingLevel >= 0;

  /// Modyfikator regeneracji ze SNU (0.85–1.06).
  ///
  /// Saner 2020 (PMID 32078168): pięć nocy po ~4 h w łóżku obniżyło MyoPS.
  /// To argument za tym, żeby sen BYŁ modyfikatorem, ale protokołu
  /// laboratoryjnego nie przenosimy 1:1 na użytkownika aplikacji — wpływ jest
  /// ciągły i ograniczony, bez kar w rodzaju „+24 h do każdej partii".
  double get sleepFactor {
    final minutes = sleepMinutes > 0
        ? sleepMinutes
        : (sleepMinutesAverage > 0 ? sleepMinutesAverage : 0);
    if (minutes <= 0) return 1.0; // brak danych = neutralnie
    final hours = minutes / 60.0;
    if (hours >= 8) return 1.06;
    if (hours >= 7) return 1.02;
    if (hours >= 6) return 1.0;
    if (hours >= 5) return 0.94;
    if (hours >= 4) return 0.89;
    return 0.85;
  }

  /// Modyfikator odbudowy ENERGETYCZNEJ (0.82–1.08).
  ///
  /// Ivy 1988 (PMID 3132449) — dostępność i czas podaży węglowodanów decydują
  /// o tempie odbudowy glikogenu; Areta 2014 (PMID 24595305) — krótkotrwały
  /// deficyt obniża spoczynkową MPS. Oba wyniki uzasadniają OSOBNĄ składową
  /// energetyczną, a nie próg „X g = 100% regeneracji" (Moore 2009,
  /// PMID 19056590, pokazuje zależność dawka–odpowiedź, nie stały próg).
  double get energyFactor {
    if (!hasNutritionData) return 1.0;
    var factor = 1.0;
    if (intakeKcal > 0 && targetKcal > 0) {
      final ratio = intakeKcal / targetKcal;
      if (ratio < 0.70) {
        factor *= 0.86;
      } else if (ratio < 0.85) {
        factor *= 0.93;
      } else if (ratio > 1.05) {
        factor *= 1.04;
      }
    }
    if (carbsG > 0 && bodyWeightKg > 0) {
      final perKg = carbsG / bodyWeightKg;
      // Skala względna, bez sztywnego progu — mniej węglowodanów na kg to
      // wolniejsza odbudowa zasobów, nie „zero glikogenu".
      if (perKg < 1.5) {
        factor *= 0.92;
      } else if (perKg >= 4) {
        factor *= 1.04;
      }
    }
    if (waterMl > 0 && bodyWeightKg > 0) {
      final perKg = waterMl / bodyWeightKg;
      if (perKg < 20) factor *= 0.96;
    }
    return factor.clamp(0.82, 1.08).toDouble();
  }

  /// Modyfikator regeneracji STRUKTURALNEJ z podaży białka (0.9–1.05).
  double get proteinFactor {
    if (proteinG <= 0 || bodyWeightKg <= 0) return 1.0;
    final perKg = proteinG / bodyWeightKg;
    if (perKg < 0.8) return 0.92;
    if (perKg < 1.2) return 0.98;
    if (perKg >= 1.6) return 1.05;
    return 1.0;
  }

  /// Sygnał subiektywny 0–1 (1 = czuję się dobrze). Brak danych = 1.0.
  double get subjectiveScore {
    if (!hasSubjectiveData) return 1.0;
    var score = 1.0;
    if (sorenessLevel >= 0) {
      // DOMS obniża wynik, ale NIGDY nie schodzi niżej niż 0.7 — bolesność to
      // sygnał pomocniczy, nie miara uszkodzenia (Nosaka 2002).
      score -= (sorenessLevel / 10.0) * 0.3;
    }
    if (wellbeingLevel >= 0) {
      score += ((wellbeingLevel - 5) / 5.0) * 0.1;
    }
    return score.clamp(0.7, 1.05).toDouble();
  }

  /// Ile sygnałów kontekstowych mamy (wkład do pewności prognozy).
  int get availableSignalCount =>
      (hasSleepData ? 1 : 0) +
      (hasNutritionData ? 1 : 0) +
      (hasSubjectiveData ? 1 : 0) +
      (dailyStepCount > 0 ? 1 : 0);
}
