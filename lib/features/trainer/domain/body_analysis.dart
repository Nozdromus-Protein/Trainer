/// Analiza sylwetki (Etap: zdjęcia progresu + analiza AI).
///
/// Czysty Dart:
///  - [SilhouetteGoal] — katalog docelowych typów sylwetki (profesjonalne
///    nazwy, opis, partie podświetlane na modelu ciała),
///  - [BodyAnalysisResult] — wynik jednej analizy (skład ciała, postawa,
///    wymiary częsci ciała odczytane ze zdjęć, zalecenia),
///  - [estimateBodyCompositionLocally] — lokalny estymator składu ciała ze
///    wzorów antropometrycznych (działa bez AI i bez zdjęć).
///
/// Analiza jest ORIENTACYJNA — to nie jest diagnoza medyczna ani badanie
/// składu ciała (DEXA/BIA). UI zawsze pokazuje tę informację.
library;

import 'dart:math' as math;

import 'body_muscle.dart';

/// Docelowy typ sylwetki wybierany przez użytkownika.
/// [highlightPrimary]/[highlightSecondary] — partie podświetlane na modelu
/// ciała (tym samym, który służy do mapy regeneracji).
enum SilhouetteGoal {
  vTaper(
    'v_taper',
    'V-Taper — klasyczne „V"',
    'Szerokie barki i plecy, wąska talia. Kanon sylwetki estetycznej: proporcja barki/talia ≥ 1.6.',
    [
      BodyMuscle.lats,
      BodyMuscle.frontShoulders,
      BodyMuscle.rearShoulders,
      BodyMuscle.upperBack
    ],
    [BodyMuscle.chest, BodyMuscle.abs, BodyMuscle.biceps],
    'Priorytet: naciski nad głowę, podciąganie, wiosłowanie. Talia: deficyt kaloryczny + praca core.',
  ),
  athletic(
    'athletic',
    'Athletic Performance — sylwetka wysportowana',
    'Zrównoważona muskulatura całego ciała z niskim poziomem tkanki tłuszczowej i naciskiem na sprawność.',
    [BodyMuscle.quads, BodyMuscle.glutes, BodyMuscle.chest, BodyMuscle.lats],
    [
      BodyMuscle.frontShoulders,
      BodyMuscle.hamstrings,
      BodyMuscle.abs,
      BodyMuscle.calvesBack
    ],
    'Trening full body / push-pull-legs + regularne cardio i praca eksplozywna.',
  ),
  leanShredded(
    'lean_shredded',
    'Lean & Shredded — definicja',
    'Niski poziom tkanki tłuszczowej (mężczyźni ~8–12%, kobiety ~16–20%) z widoczną separacją mięśni.',
    [BodyMuscle.abs, BodyMuscle.obliques],
    [BodyMuscle.chest, BodyMuscle.frontShoulders, BodyMuscle.quads],
    'Utrzymany deficyt kaloryczny, wysokie białko (ok. 2 g/kg), trening siłowy podtrzymujący masę.',
  ),
  muscular(
    'muscular',
    'Bodybuilding — masa mięśniowa',
    'Maksymalny rozwój muskulatury wszystkich partii z zachowaniem proporcji (klasyczna sylwetka kulturystyczna).',
    [
      BodyMuscle.chest,
      BodyMuscle.lats,
      BodyMuscle.quads,
      BodyMuscle.biceps,
      BodyMuscle.triceps
    ],
    [
      BodyMuscle.frontShoulders,
      BodyMuscle.rearShoulders,
      BodyMuscle.glutes,
      BodyMuscle.hamstrings,
      BodyMuscle.calvesBack
    ],
    'Nadwyżka kaloryczna 5–10%, progresja objętości (10–20 serii/partię/tydz.), sen 7–9 h.',
  ),
  strength(
    'strength',
    'Strength / Powerbuilding — siła',
    'Sylwetka zbudowana pod siłę absolutną: mocny tułów, grzbiet, biodra i nogi; masa wyższa od estetycznego minimum.',
    [
      BodyMuscle.lowerBack,
      BodyMuscle.glutes,
      BodyMuscle.quads,
      BodyMuscle.traps
    ],
    [BodyMuscle.upperBack, BodyMuscle.hamstrings, BodyMuscle.forearmsFront],
    'Ciężkie boje wielostawowe (przysiad/martwy/wyciskanie) w zakresie 3–6 powtórzeń + akcesoria.',
  ),
  recomposition(
    'recomposition',
    'Rekompozycja — mniej tłuszczu, więcej mięśni',
    'Jednoczesna redukcja tkanki tłuszczowej i budowa masy mięśniowej — najlepsza przy wyższym % tkanki tłuszczowej.',
    [BodyMuscle.abs, BodyMuscle.chest, BodyMuscle.quads],
    [BodyMuscle.lats, BodyMuscle.glutes, BodyMuscle.frontShoulders],
    'Lekki deficyt (5–15%), białko 1.8–2.2 g/kg, trening siłowy 3–5×/tydz., kroki 8–12 tys./dzień.',
  );

  const SilhouetteGoal(
    this.id,
    this.label,
    this.description,
    this.highlightPrimary,
    this.highlightSecondary,
    this.strategy,
  );

  final String id;

  /// Profesjonalna nazwa typu sylwetki.
  final String label;
  final String description;

  /// Partie najmocniej akcentowane w tym typie (ilustracja na modelu ciała).
  final List<BodyMuscle> highlightPrimary;
  final List<BodyMuscle> highlightSecondary;

  /// Krótka strategia treningowo-żywieniowa dla tego celu.
  final String strategy;

  static SilhouetteGoal? fromId(String? id) {
    final normalized = id?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final goal in SilhouetteGoal.values) {
      if (goal.id == normalized) return goal;
    }
    return null;
  }
}

/// Klucze wymiarów ciała odczytywanych z analizy (cm) + polskie etykiety.
const Map<String, String> kBodyPartLabels = {
  'neck': 'Szyja',
  'shoulders': 'Barki',
  'chest': 'Klatka',
  'waist': 'Pas',
  'hips': 'Biodra',
  'arm': 'Ramię',
  'forearm': 'Przedramię',
  'thigh': 'Udo',
  'calf': 'Łydka',
};

/// Szacunkowy skład ciała (w % masy ciała) + wskaźniki pochodne.
class BodyCompositionEstimate {
  const BodyCompositionEstimate({
    this.bodyFatPercent = 0,
    this.musclePercent = 0,
    this.waterPercent = 0,
    this.bonePercent = 0,
    this.visceralFatLevel = 0,
    this.bmi = 0,
    this.ffmi = 0,
    this.method = '',
  });

  final double bodyFatPercent;

  /// Mięśnie szkieletowe jako % masy ciała.
  final double musclePercent;
  final double waterPercent;
  final double bonePercent;

  /// Poziom tłuszczu trzewnego w skali 1–20 (jak w analizatorach BIA; 0 = brak danych).
  final double visceralFatLevel;
  final double bmi;

  /// Fat-Free Mass Index (znormalizowany do 180 cm) — miara umięśnienia.
  final double ffmi;

  /// Źródło szacunku: 'ai_photo' | 'formulas' | ''.
  final String method;

  bool get hasData =>
      bodyFatPercent > 0 || musclePercent > 0 || waterPercent > 0;

  Map<String, dynamic> toJson() => {
        'bodyFatPercent': bodyFatPercent,
        'musclePercent': musclePercent,
        'waterPercent': waterPercent,
        'bonePercent': bonePercent,
        'visceralFatLevel': visceralFatLevel,
        'bmi': bmi,
        'ffmi': ffmi,
        'method': method,
      };

  factory BodyCompositionEstimate.fromJson(Map<String, dynamic> json) =>
      BodyCompositionEstimate(
        bodyFatPercent: _asDouble(json['bodyFatPercent']),
        musclePercent: _asDouble(json['musclePercent']),
        waterPercent: _asDouble(json['waterPercent']),
        bonePercent: _asDouble(json['bonePercent']),
        visceralFatLevel: _asDouble(json['visceralFatLevel']),
        bmi: _asDouble(json['bmi']),
        ffmi: _asDouble(json['ffmi']),
        method: json['method']?.toString() ?? '',
      );
}

/// Wynik jednej analizy sylwetki (AI ze zdjęć albo lokalny estymator).
class BodyAnalysisResult {
  const BodyAnalysisResult({
    required this.id,
    required this.date,
    this.photoFrontPath = '',
    this.photoSidePath = '',
    this.photoBackPath = '',
    this.composition = const BodyCompositionEstimate(),
    this.currentSilhouette = '',
    this.targetSilhouetteId = '',
    this.postureNotes = '',
    this.symmetryNotes = '',
    this.strengths = const [],
    this.weaknesses = const [],
    this.estimatedMeasurementsCm = const {},
    this.summary = '',
    this.trainingRecommendations = const [],
    this.nutritionRecommendations = const [],
    this.risks = const [],
    this.confidencePercent = 0,
    this.source = '',
    this.contextUsed = const [],
    this.schemaVersion = 1,
    this.bodyWeightKgAtAnalysis = 0,
    this.waistCmAtAnalysis = 0,
    this.bodyFatRangeMinPercent = 0,
    this.bodyFatRangeMaxPercent = 0,
    this.validationIssues = const [],
    this.lowReliability = false,
    this.strategyIdAtAnalysis = '',
    this.physiqueIdAtAnalysis = '',
    this.possibleImbalances = const [],
    this.watchAreas = const [],
    this.developmentPriorities = const [],
    this.modelVersion = '',
    this.rawAiJson = '',
  });

  final String id;
  final DateTime date;
  final String photoFrontPath;
  final String photoSidePath;
  final String photoBackPath;
  final BodyCompositionEstimate composition;

  /// Profesjonalna klasyfikacja obecnej sylwetki (np. „mezomorf z tendencją
  /// endomorficzną", „skinny fat", „V-taper w budowie").
  final String currentSilhouette;

  /// Cel wybrany przez użytkownika w chwili analizy ([SilhouetteGoal.id]).
  final String targetSilhouetteId;
  final String postureNotes;
  final String symmetryNotes;
  final List<String> strengths;
  final List<String> weaknesses;

  /// Wymiary części ciała odczytane z analizy (klucz → cm), patrz [kBodyPartLabels].
  final Map<String, double> estimatedMeasurementsCm;

  /// Szczegółowy opis sylwetki i drogi do celu.
  final String summary;
  final List<String> trainingRecommendations;
  final List<String> nutritionRecommendations;

  /// Uwagi ostrożnościowe (np. asymetria wymagająca konsultacji).
  final List<String> risks;

  /// Pewność analizy 0–100 (deklarowana przez model).
  final double confidencePercent;

  /// 'gemini' | 'openai' | 'local'.
  final String source;

  /// Jakie dane aplikacji zostały uwzględnione (np. 'pomiary', 'treningi 30 dni').
  final List<String> contextUsed;

  /// Wersja schematu analizy: 1 = stary model (przed przebudową analizy
  /// sylwetki), 2 = nowy (FFM, zakresy, walidacja). Stare analizy pozostają
  /// nietknięte i są oznaczane w UI jako wykonane wcześniejszą wersją.
  final int schemaVersion;

  /// Masa ciała obowiązująca w dniu analizy (0 = nieznana — policz z pomiarów).
  final double bodyWeightKgAtAnalysis;

  /// Obwód talii w dniu analizy (0 = brak).
  final double waistCmAtAnalysis;

  /// Prawdopodobny zakres tkanki tłuszczowej (0 = wyprowadź z pewności).
  final double bodyFatRangeMinPercent;
  final double bodyFatRangeMaxPercent;

  /// Problemy znalezione w walidacji biologicznej (czytelne komunikaty).
  final List<String> validationIssues;

  /// Analiza oznaczona jako „niska wiarygodność" (nie przeszła walidacji).
  final bool lowReliability;

  /// Strategia i sylwetka wybrane w chwili analizy (id z centralnego profilu).
  final String strategyIdAtAnalysis;
  final String physiqueIdAtAnalysis;

  /// Ostrożna analiza wizualna: możliwe dysproporcje, obszary do obserwacji,
  /// priorytety rozwoju (język „może wskazywać", bez diagnoz).
  final List<String> possibleImbalances;
  final List<String> watchAreas;
  final List<String> developmentPriorities;

  /// Wersja/model AI użyty do analizy (np. 'gemini-2.5-flash').
  final String modelVersion;

  /// Surowa odpowiedź AI zachowana do diagnostyki — NIE jest pokazywana
  /// jako zweryfikowany wynik.
  final String rawAiJson;

  SilhouetteGoal? get targetGoal => SilhouetteGoal.fromId(targetSilhouetteId);

  int get photoCount =>
      (photoFrontPath.isEmpty ? 0 : 1) +
      (photoSidePath.isEmpty ? 0 : 1) +
      (photoBackPath.isEmpty ? 0 : 1);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'photoFrontPath': photoFrontPath,
        'photoSidePath': photoSidePath,
        'photoBackPath': photoBackPath,
        'composition': composition.toJson(),
        'currentSilhouette': currentSilhouette,
        'targetSilhouetteId': targetSilhouetteId,
        'postureNotes': postureNotes,
        'symmetryNotes': symmetryNotes,
        'strengths': strengths,
        'weaknesses': weaknesses,
        'estimatedMeasurementsCm': estimatedMeasurementsCm,
        'summary': summary,
        'trainingRecommendations': trainingRecommendations,
        'nutritionRecommendations': nutritionRecommendations,
        'risks': risks,
        'confidencePercent': confidencePercent,
        'source': source,
        'contextUsed': contextUsed,
        'schemaVersion': schemaVersion,
        if (bodyWeightKgAtAnalysis > 0)
          'bodyWeightKgAtAnalysis': bodyWeightKgAtAnalysis,
        if (waistCmAtAnalysis > 0) 'waistCmAtAnalysis': waistCmAtAnalysis,
        if (bodyFatRangeMinPercent > 0)
          'bodyFatRangeMinPercent': bodyFatRangeMinPercent,
        if (bodyFatRangeMaxPercent > 0)
          'bodyFatRangeMaxPercent': bodyFatRangeMaxPercent,
        if (validationIssues.isNotEmpty) 'validationIssues': validationIssues,
        if (lowReliability) 'lowReliability': lowReliability,
        if (strategyIdAtAnalysis.isNotEmpty)
          'strategyIdAtAnalysis': strategyIdAtAnalysis,
        if (physiqueIdAtAnalysis.isNotEmpty)
          'physiqueIdAtAnalysis': physiqueIdAtAnalysis,
        if (possibleImbalances.isNotEmpty)
          'possibleImbalances': possibleImbalances,
        if (watchAreas.isNotEmpty) 'watchAreas': watchAreas,
        if (developmentPriorities.isNotEmpty)
          'developmentPriorities': developmentPriorities,
        if (modelVersion.isNotEmpty) 'modelVersion': modelVersion,
        if (rawAiJson.isNotEmpty) 'rawAiJson': rawAiJson,
      };

  factory BodyAnalysisResult.fromJson(Map<String, dynamic> json) =>
      BodyAnalysisResult(
        id: json['id']?.toString() ??
            'analysis_${DateTime.now().microsecondsSinceEpoch}',
        date:
            DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        photoFrontPath: json['photoFrontPath']?.toString() ?? '',
        photoSidePath: json['photoSidePath']?.toString() ?? '',
        photoBackPath: json['photoBackPath']?.toString() ?? '',
        composition: json['composition'] is Map
            ? BodyCompositionEstimate.fromJson(
                Map<String, dynamic>.from(json['composition'] as Map))
            : const BodyCompositionEstimate(),
        currentSilhouette: json['currentSilhouette']?.toString() ?? '',
        targetSilhouetteId: json['targetSilhouetteId']?.toString() ?? '',
        postureNotes: json['postureNotes']?.toString() ?? '',
        symmetryNotes: json['symmetryNotes']?.toString() ?? '',
        strengths: _asStringList(json['strengths']),
        weaknesses: _asStringList(json['weaknesses']),
        estimatedMeasurementsCm:
            _asMeasurementMap(json['estimatedMeasurementsCm']),
        summary: json['summary']?.toString() ?? '',
        trainingRecommendations: _asStringList(json['trainingRecommendations']),
        nutritionRecommendations:
            _asStringList(json['nutritionRecommendations']),
        risks: _asStringList(json['risks']),
        confidencePercent: _asDouble(json['confidencePercent']),
        source: json['source']?.toString() ?? '',
        contextUsed: _asStringList(json['contextUsed']),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        bodyWeightKgAtAnalysis: _asDouble(json['bodyWeightKgAtAnalysis']),
        waistCmAtAnalysis: _asDouble(json['waistCmAtAnalysis']),
        bodyFatRangeMinPercent: _asDouble(json['bodyFatRangeMinPercent']),
        bodyFatRangeMaxPercent: _asDouble(json['bodyFatRangeMaxPercent']),
        validationIssues: _asStringList(json['validationIssues']),
        lowReliability: json['lowReliability'] == true,
        strategyIdAtAnalysis: json['strategyIdAtAnalysis']?.toString() ?? '',
        physiqueIdAtAnalysis: json['physiqueIdAtAnalysis']?.toString() ?? '',
        possibleImbalances: _asStringList(json['possibleImbalances']),
        watchAreas: _asStringList(json['watchAreas']),
        developmentPriorities: _asStringList(json['developmentPriorities']),
        modelVersion: json['modelVersion']?.toString() ?? '',
        rawAiJson: json['rawAiJson']?.toString() ?? '',
      );

  /// Buduje wynik z surowej odpowiedzi AI (tolerancyjne parsowanie: liczby
  /// mogą przyjść jako stringi, listy mogą być pojedynczym tekstem).
  factory BodyAnalysisResult.fromAiJson(
    Map<String, dynamic> json, {
    required String id,
    required DateTime date,
    required String source,
    String photoFrontPath = '',
    String photoSidePath = '',
    String photoBackPath = '',
    String targetSilhouetteId = '',
    List<String> contextUsed = const [],
    String modelVersion = '',
    String rawAiJson = '',
  }) {
    final rawComposition = json['composition'] is Map
        ? Map<String, dynamic>.from(json['composition'] as Map)
        : json;
    final composition = BodyCompositionEstimate(
      bodyFatPercent: _asDouble(rawComposition['bodyFatPercent']).clamp(0, 70),
      musclePercent: _asDouble(rawComposition['musclePercent']).clamp(0, 70),
      waterPercent: _asDouble(rawComposition['waterPercent']).clamp(0, 80),
      bonePercent: _asDouble(rawComposition['bonePercent']).clamp(0, 25),
      visceralFatLevel:
          _asDouble(rawComposition['visceralFatLevel']).clamp(0, 20),
      bmi: _asDouble(rawComposition['bmi']).clamp(0, 80),
      ffmi: _asDouble(rawComposition['ffmi']).clamp(0, 40),
      method: 'ai_photo',
    );
    // Zakres BF od modelu (opcjonalny obiekt {"min","max"} albo płaskie pola).
    final rawRange = rawComposition['bodyFatRangePercent'];
    double rangeMin = 0;
    double rangeMax = 0;
    if (rawRange is Map) {
      rangeMin = _asDouble(rawRange['min']).clamp(0, 70);
      rangeMax = _asDouble(rawRange['max']).clamp(0, 70);
    } else {
      rangeMin = _asDouble(rawComposition['bodyFatMinPercent']).clamp(0, 70);
      rangeMax = _asDouble(rawComposition['bodyFatMaxPercent']).clamp(0, 70);
    }
    if (rangeMin > rangeMax) {
      final swap = rangeMin;
      rangeMin = rangeMax;
      rangeMax = swap;
    }
    return BodyAnalysisResult(
      id: id,
      date: date,
      photoFrontPath: photoFrontPath,
      photoSidePath: photoSidePath,
      photoBackPath: photoBackPath,
      composition: composition,
      currentSilhouette: json['currentSilhouette']?.toString().trim() ?? '',
      targetSilhouetteId: targetSilhouetteId,
      postureNotes: json['postureNotes']?.toString().trim() ?? '',
      symmetryNotes: json['symmetryNotes']?.toString().trim() ?? '',
      strengths: _asStringList(json['strengths']),
      weaknesses: _asStringList(json['weaknesses']),
      estimatedMeasurementsCm:
          _asMeasurementMap(json['estimatedMeasurementsCm']),
      summary: json['summary']?.toString().trim() ?? '',
      trainingRecommendations: _asStringList(json['trainingRecommendations']),
      nutritionRecommendations: _asStringList(json['nutritionRecommendations']),
      risks: _asStringList(json['risks']),
      confidencePercent: _asDouble(json['confidencePercent']).clamp(0, 100),
      source: source,
      contextUsed: contextUsed,
      schemaVersion: 2,
      bodyFatRangeMinPercent: rangeMin,
      bodyFatRangeMaxPercent: rangeMax,
      possibleImbalances: _asStringList(json['possibleImbalances']),
      watchAreas: _asStringList(json['watchAreas']),
      developmentPriorities: _asStringList(json['developmentPriorities']),
      modelVersion: modelVersion,
      rawAiJson: rawAiJson,
    );
  }

  /// Kopia z nadpisanymi polami — model jest niemutowalny, a stare analizy
  /// nigdy nie są nadpisywane bez kopii (nowy obiekt).
  BodyAnalysisResult copyWith({
    BodyCompositionEstimate? composition,
    double? bodyWeightKgAtAnalysis,
    double? waistCmAtAnalysis,
    double? bodyFatRangeMinPercent,
    double? bodyFatRangeMaxPercent,
    List<String>? validationIssues,
    bool? lowReliability,
    String? strategyIdAtAnalysis,
    String? physiqueIdAtAnalysis,
    int? schemaVersion,
    double? confidencePercent,
  }) {
    final base = BodyAnalysisResult.fromJson(toJson());
    return BodyAnalysisResult(
      id: base.id,
      date: base.date,
      photoFrontPath: base.photoFrontPath,
      photoSidePath: base.photoSidePath,
      photoBackPath: base.photoBackPath,
      composition: composition ?? base.composition,
      currentSilhouette: base.currentSilhouette,
      targetSilhouetteId: base.targetSilhouetteId,
      postureNotes: base.postureNotes,
      symmetryNotes: base.symmetryNotes,
      strengths: base.strengths,
      weaknesses: base.weaknesses,
      estimatedMeasurementsCm: base.estimatedMeasurementsCm,
      summary: base.summary,
      trainingRecommendations: base.trainingRecommendations,
      nutritionRecommendations: base.nutritionRecommendations,
      risks: base.risks,
      confidencePercent: confidencePercent ?? base.confidencePercent,
      source: base.source,
      contextUsed: base.contextUsed,
      schemaVersion: schemaVersion ?? base.schemaVersion,
      bodyWeightKgAtAnalysis:
          bodyWeightKgAtAnalysis ?? base.bodyWeightKgAtAnalysis,
      waistCmAtAnalysis: waistCmAtAnalysis ?? base.waistCmAtAnalysis,
      bodyFatRangeMinPercent:
          bodyFatRangeMinPercent ?? base.bodyFatRangeMinPercent,
      bodyFatRangeMaxPercent:
          bodyFatRangeMaxPercent ?? base.bodyFatRangeMaxPercent,
      validationIssues: validationIssues ?? base.validationIssues,
      lowReliability: lowReliability ?? base.lowReliability,
      strategyIdAtAnalysis: strategyIdAtAnalysis ?? base.strategyIdAtAnalysis,
      physiqueIdAtAnalysis: physiqueIdAtAnalysis ?? base.physiqueIdAtAnalysis,
      possibleImbalances: base.possibleImbalances,
      watchAreas: base.watchAreas,
      developmentPriorities: base.developmentPriorities,
      modelVersion: base.modelVersion,
      rawAiJson: base.rawAiJson,
    );
  }
}

/// Dzienne cele żywieniowe wyliczone z docelowej sylwetki i profilu —
/// źródło prawdy dla Licznika Kalorii (zamiast ręcznych „Danych i celów").
class SilhouetteNutritionTargets {
  const SilhouetteNutritionTargets({
    required this.silhouetteId,
    required this.silhouetteLabel,
    required this.phaseLabel,
    required this.goalKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.bmrKcal = 0,
    this.tdeeKcal = 0,
  });

  static const schema = 'trainer.nutrition_targets.v1';

  final String silhouetteId;
  final String silhouetteLabel;

  /// Faza wynikająca z sylwetki: „Redukcja" / „Utrzymanie" / „Nadwyżka (masa)"…
  /// Osobne ustawienie redukcja/masa NIE jest potrzebne — wybór sylwetki
  /// determinuje fazę.
  final String phaseLabel;
  final int goalKcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int bmrKcal;
  final int tdeeKcal;

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'silhouetteId': silhouetteId,
        'silhouetteLabel': silhouetteLabel,
        'phaseLabel': phaseLabel,
        'goalKcal': goalKcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'bmrKcal': bmrKcal,
        'tdeeKcal': tdeeKcal,
      };

  /// Zwięzła sygnatura do wykrywania zmian (publikacja mostu).
  String get signature => '$silhouetteId:$goalKcal:$proteinG:$carbsG:$fatG';
}

/// LEGACY: liczy dzienne cele (kcal + makra) z profilu i DOCELOWEJ SYLWETKI.
///
/// Zachowane wyłącznie dla zgodności wstecznej (stare dane/testy). Nowy kod
/// używa `computeGoalNutritionTargets` z `user_body_goal.dart`, gdzie kalorie
/// wynikają z AKTUALNEJ STRATEGII składu ciała, a nie z nazwy sylwetki —
/// docelowa sylwetka nie mówi, czy użytkownik ma teraz redukować czy budować.
///
/// - BMR: Mifflin-St Jeor (masa/wzrost/wiek/płeć),
/// - baza utrzymania: BMR + efekt termiczny jedzenia, bez aktywności,
/// - faza: wynika z sylwetki (STARY model),
/// - białko i tłuszcz: g na kg masy ciała wg sylwetki; węgle dopełniają kcal.
///
/// Zwraca null, gdy brak sylwetki albo sensownego profilu (masa/wzrost).
SilhouetteNutritionTargets? computeSilhouetteNutritionTargets({
  required SilhouetteGoal? goal,
  required double weightKg,
  required double heightCm,
  required int age,
  required String sex,
  required int trainingDaysPerWeek,
}) {
  if (goal == null || weightKg <= 0 || heightCm <= 0) return null;
  final normalizedSex = sex.trim().toLowerCase();
  final isFemale = normalizedSex.startsWith('k') ||
      normalizedSex.startsWith('f') ||
      normalizedSex.contains('kob');

  // --- BMR (Mifflin-St Jeor). ---
  final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (isFemale ? -161 : 5);

  // --- TDEE: baza siedząca + bonus za każdy dzień treningowy. ---
  // Keep this legacy result compatible with the central activity-free model.
  // Actual work, steps and training are credited once from the day package.
  final tdee = bmr / 0.90;

  // --- Faza i makra per sylwetka (kcalFactor, białko g/kg, tłuszcz g/kg). ---
  final (kcalFactor, phaseLabel, proteinPerKg, fatPerKg) = switch (goal) {
    SilhouetteGoal.leanShredded => (0.82, 'Redukcja', 2.2, 0.8),
    SilhouetteGoal.recomposition => (
        0.90,
        'Lekka redukcja (rekompozycja)',
        2.0,
        0.9
      ),
    SilhouetteGoal.vTaper => (0.92, 'Lekka redukcja', 2.0, 0.9),
    SilhouetteGoal.athletic => (1.0, 'Utrzymanie', 1.7, 1.0),
    SilhouetteGoal.strength => (1.08, 'Lekka nadwyżka', 1.8, 1.0),
    SilhouetteGoal.muscular => (1.12, 'Nadwyżka (masa)', 1.9, 1.0),
  };

  // Kcal celu — nigdy poniżej ~BMR (bezpieczny dolny próg deficytu).
  var goalKcal = tdee * kcalFactor;
  if (goalKcal < bmr) goalKcal = bmr;

  int roundTo(double value, int step) => (value / step).round() * step;
  final proteinG = roundTo(weightKg * proteinPerKg, 5);
  final fatG = roundTo(weightKg * fatPerKg, 5);
  final kcalRounded =
      goalKcal <= bmr ? (bmr / 10).ceil() * 10 : roundTo(goalKcal, 10);
  final carbsKcal = kcalRounded - proteinG * 4 - fatG * 9;
  final carbsG = carbsKcal <= 0 ? 0 : roundTo(carbsKcal / 4, 5);

  return SilhouetteNutritionTargets(
    silhouetteId: goal.id,
    silhouetteLabel: goal.label,
    phaseLabel: phaseLabel,
    goalKcal: kcalRounded,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    bmrKcal: bmr.round(),
    tdeeKcal: tdee.round(),
  );
}

/// Lokalny szacunek składu ciała ze wzorów antropometrycznych.
///
/// - BF%: wzór US Navy (gdy są obwody szyi i pasa), inaczej Deurenberg (BMI+wiek);
/// - woda: wzór Watsona (TBW w litrach → % masy);
/// - mięśnie szkieletowe: wzór Lee (wzrost/masa/płeć);
/// - kości: przybliżenie 15% masy beztłuszczowej (~4% masy ciała);
/// - FFMI znormalizowane do wzrostu.
///
/// Wynik jest ORIENTACYJNY (metoda 'formulas'). Zwraca pusty szacunek, gdy
/// brakuje masy albo wzrostu.
BodyCompositionEstimate estimateBodyCompositionLocally({
  required double weightKg,
  required double heightCm,
  required int age,
  required String sex,
  double waistCm = 0,
  double neckCm = 0,
  double hipsCm = 0,
}) {
  if (weightKg <= 0 || heightCm <= 0) return const BodyCompositionEstimate();
  final isFemale = sex.trim().toLowerCase().startsWith('k');
  final heightM = heightCm / 100.0;
  final bmi = weightKg / (heightM * heightM);

  // --- Tkanka tłuszczowa. ---
  double bodyFat;
  if (waistCm > 0 &&
      neckCm > 0 &&
      waistCm > neckCm &&
      (!isFemale || hipsCm > 0)) {
    // US Navy (obwody w cm, log10).
    if (isFemale) {
      bodyFat = 495 /
              (1.29579 -
                  0.35004 * _log10(waistCm + hipsCm - neckCm) +
                  0.22100 * _log10(heightCm)) -
          450;
    } else {
      bodyFat = 495 /
              (1.0324 -
                  0.19077 * _log10(waistCm - neckCm) +
                  0.15456 * _log10(heightCm)) -
          450;
    }
  } else {
    // Deurenberg: BF% = 1.2×BMI + 0.23×wiek − 10.8×płeć(M=1) − 5.4.
    bodyFat = 1.2 * bmi + 0.23 * age - (isFemale ? 0 : 10.8) - 5.4;
  }
  bodyFat = bodyFat.clamp(3.0, 60.0);

  // --- Woda całkowita (Watson, litry) → % masy ciała. ---
  final totalBodyWater = isFemale
      ? -2.097 + 0.1069 * heightCm + 0.2466 * weightKg
      : 2.447 - 0.09156 * age + 0.1074 * heightCm + 0.3362 * weightKg;
  final waterPercent = (totalBodyWater / weightKg * 100).clamp(30.0, 70.0);

  // --- Mięśnie szkieletowe (Lee 2000, kg) → % masy ciała:
  // SM = 0.244×masa + 7.8×wzrost(m) − 0.098×wiek + 6.6×płeć(M=1) − 3.3. ---
  final smmKg = 0.244 * weightKg +
      7.8 * heightM -
      0.098 * age +
      (isFemale ? 0 : 6.6) -
      3.3;
  final musclePercent = (smmKg / weightKg * 100).clamp(15.0, 60.0);

  // --- Kości: ~15% masy beztłuszczowej. ---
  final leanMassKg = weightKg * (1 - bodyFat / 100);
  final bonePercent = (leanMassKg * 0.15 / weightKg * 100).clamp(2.0, 20.0);

  // --- FFMI (znormalizowane do 1.80 m). ---
  final ffmi = leanMassKg / (heightM * heightM) + 6.1 * (1.8 - heightM);

  // --- Tłuszcz trzewny: przybliżenie z WHtR (pas/wzrost). ---
  double visceral = 0;
  if (waistCm > 0) {
    final whtr = waistCm / heightCm;
    visceral = ((whtr - 0.40) * 40).clamp(1.0, 20.0);
  }

  return BodyCompositionEstimate(
    bodyFatPercent: _round1(bodyFat),
    musclePercent: _round1(musclePercent),
    waterPercent: _round1(waterPercent),
    bonePercent: _round1(bonePercent),
    visceralFatLevel: _round1(visceral),
    bmi: _round1(bmi),
    ffmi: _round1(ffmi),
    method: 'formulas',
  );
}

double _log10(double value) => math.log(value) / math.ln10;

double _round1(double value) => (value * 10).roundToDouble() / 10;

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(
            value.replaceAll(',', '.').replaceAll('%', '').trim()) ??
        0;
  }
  return 0;
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const [] : [text];
}

Map<String, double> _asMeasurementMap(Object? value) {
  if (value is! Map) return const {};
  final result = <String, double>{};
  value.forEach((key, raw) {
    final normalized = key.toString().trim().toLowerCase();
    if (!kBodyPartLabels.containsKey(normalized)) return;
    final cm = _asDouble(raw);
    if (cm > 0 && cm < 250) result[normalized] = _round1(cm);
  });
  return result;
}
