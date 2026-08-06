/// Centralny system celu użytkownika (jedno źródło prawdy).
///
/// Czysty Dart. Rozdziela trzy różne pojęcia, których NIE wolno mieszać:
///  1. [DesiredPhysique] — docelowa sylwetka („jak chcę wyglądać?"),
///  2. [BodyCompositionStrategy] — aktualna strategia składu ciała
///     („co teraz robię z tłuszczem i mięśniami?"),
///  3. [TrainingFocus] — typ/priorytet treningu („jak trenuję?").
///
/// Zasada: „Sylwetka to miejsce docelowe, strategia to aktualna droga,
/// a typ treningu to sposób poruszania się po tej drodze."
///
/// Kalorie i makra liczone są ZE STRATEGII (nigdy z nazwy sylwetki) —
/// patrz [computeGoalNutritionTargets].
library;

import 'dart:math';

import 'body_composition.dart';
import 'trainer_enums.dart';

// ============================================================================
// 1. Docelowa sylwetka
// ============================================================================

/// Docelowy wygląd — długoterminowy kierunek. NIE decyduje o deficycie ani
/// nadwyżce kalorycznej.
enum DesiredPhysique {
  leanAthletic(
    'lean_athletic',
    'Szczupła i wysportowana',
    'Niska masa tłuszczowa, sprawna sylwetka bez nacisku na duże obwody.',
    legacySilhouetteId: 'lean_shredded',
  ),
  athletic(
    'athletic',
    'Atletyczna',
    'Zrównoważona muskulatura całego ciała z widoczną sprawnością.',
    legacySilhouetteId: 'athletic',
  ),
  muscular(
    'muscular',
    'Umięśniona',
    'Wyraźnie rozwinięta muskulatura z zachowaniem proporcji.',
    legacySilhouetteId: 'muscular',
  ),
  veryMuscular(
    'very_muscular',
    'Mocno umięśniona',
    'Maksymalny rozwój muskulatury (kierunek kulturystyczny).',
    legacySilhouetteId: 'muscular',
  ),
  shredded(
    'shredded',
    'Wyrzeźbiona',
    'Niski poziom tkanki tłuszczowej z widoczną separacją mięśni.',
    legacySilhouetteId: 'lean_shredded',
  ),
  vTaper(
    'v_taper',
    'Szeroka góra i węższa talia (V-taper)',
    'Szerokie barki i plecy przy wąskiej talii.',
    legacySilhouetteId: 'v_taper',
  ),
  functional(
    'functional',
    'Funkcjonalna',
    'Sprawność, mobilność i siła użytkowa ważniejsze niż wygląd.',
    legacySilhouetteId: 'athletic',
  ),
  runner(
    'runner',
    'Biegowa',
    'Sylwetka pod wydolność i bieganie — lekkość i ekonomia ruchu.',
    legacySilhouetteId: 'athletic',
  ),
  strengthBuild(
    'strength_build',
    'Siłowa',
    'Sylwetka pod siłę absolutną: mocny tułów, grzbiet i nogi.',
    legacySilhouetteId: 'strength',
  ),
  custom(
    'custom',
    'Niestandardowa',
    'Własny opis docelowej sylwetki.',
  );

  const DesiredPhysique(
    this.id,
    this.label,
    this.description, {
    this.legacySilhouetteId = '',
  });

  final String id;
  final String label;
  final String description;

  /// Id starego [SilhouetteGoal] najbliższego tej sylwetce — do ilustracji
  /// na modelu ciała i kompatybilności wstecznej (`settings.targetSilhouette`).
  final String legacySilhouetteId;

  static DesiredPhysique? fromId(String? id) {
    final normalized = id?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final physique in DesiredPhysique.values) {
      if (physique.id == normalized) return physique;
    }
    return null;
  }

  /// Mapowanie starego celu sylwetki ([SilhouetteGoal.id]) na nową sylwetkę.
  /// Stara „rekompozycja" NIE jest sylwetką — mapuje się na atletyczną
  /// (strategię przejmuje [BodyCompositionStrategy.recomposition]).
  static DesiredPhysique? fromLegacySilhouetteId(String? legacyId) {
    return switch (legacyId?.trim() ?? '') {
      'v_taper' => DesiredPhysique.vTaper,
      'athletic' => DesiredPhysique.athletic,
      'lean_shredded' => DesiredPhysique.shredded,
      'muscular' => DesiredPhysique.veryMuscular,
      'strength' => DesiredPhysique.strengthBuild,
      'recomposition' => DesiredPhysique.athletic,
      _ => null,
    };
  }
}

/// Priorytety wizualne docelowej sylwetki.
enum PhysiquePriority {
  biggerShoulders('bigger_shoulders', 'Większe barki'),
  widerBack('wider_back', 'Szersze plecy'),
  biggerChest('bigger_chest', 'Większa klatka piersiowa'),
  biggerArms('bigger_arms', 'Większe ramiona'),
  strongerForearms('stronger_forearms', 'Mocniejsze przedramiona'),
  biggerLegs('bigger_legs', 'Większe nogi'),
  strongerGlutes('stronger_glutes', 'Bardziej rozwinięte pośladki'),
  visibleAbs('visible_abs', 'Widoczny brzuch'),
  narrowerWaist('narrower_waist', 'Węższa talia'),
  upperLowerBalance('upper_lower_balance', 'Proporcje góry i dołu'),
  symmetry('symmetry', 'Poprawa symetrii'),
  sideProfile('side_profile', 'Lepsza sylwetka boczna'),
  custom('custom', 'Cel niestandardowy');

  const PhysiquePriority(this.id, this.label);

  final String id;
  final String label;

  static PhysiquePriority? fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final priority in PhysiquePriority.values) {
      if (priority.id == normalized) return priority;
    }
    return null;
  }
}

// ============================================================================
// 2. Strategia składu ciała
// ============================================================================

/// Aktualny etap pracy nad składem ciała. To NIE jest typ treningu.
enum BodyCompositionStrategy {
  fatLoss(
    'fat_loss',
    'Redukcja tkanki tłuszczowej',
    'Kontrolowany deficyt, wysokie białko, zachowanie mięśni i siły.',
  ),
  recomposition(
    'recomposition',
    'Rekompozycja',
    'Okolice TDEE lub lekki deficyt; mniej tłuszczu przy utrzymaniu lub '
        'wzroście mięśni — masa ciała zmienia się niewiele.',
  ),
  muscleGain(
    'muscle_gain',
    'Budowa masy mięśniowej',
    'Niewielka nadwyżka, progresja treningowa, kontrola tempa wzrostu talii.',
  ),
  maintenance(
    'maintenance',
    'Utrzymanie',
    'Stabilna masa i skład ciała, dalszy rozwój siły i sprawności.',
  ),
  performance(
    'performance',
    'Poprawa wydolności',
    'Energia pod obciążenia treningowe bez dużej zmiany masy.',
  ),
  automatic(
    'automatic',
    'Automatyczna rekomendacja',
    'Aplikacja proponuje strategię na podstawie danych — zmiana zawsze '
        'wymaga Twojego zatwierdzenia.',
  );

  const BodyCompositionStrategy(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static BodyCompositionStrategy? fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final strategy in BodyCompositionStrategy.values) {
      if (strategy.id == normalized) return strategy;
    }
    return null;
  }

  /// Etykieta fazy dla starszych odbiorców mostu (Kalorie).
  String get legacyPhaseLabel => switch (this) {
        BodyCompositionStrategy.fatLoss => 'Redukcja',
        BodyCompositionStrategy.recomposition => 'Rekompozycja',
        BodyCompositionStrategy.muscleGain => 'Nadwyżka (masa)',
        BodyCompositionStrategy.maintenance => 'Utrzymanie',
        BodyCompositionStrategy.performance => 'Wydolność',
        BodyCompositionStrategy.automatic => 'Utrzymanie',
      };
}

/// Mapowanie starego pola `trainingMode` (Redukcja/Masa/Rekompozycja/
/// Kondycja/Utrzymanie) na strategię składu ciała.
BodyCompositionStrategy strategyFromLegacyTrainingMode(String value) {
  final v = value.trim().toLowerCase();
  if (v.contains('redu')) return BodyCompositionStrategy.fatLoss;
  if (v.contains('masa') || v.contains('bulk')) {
    return BodyCompositionStrategy.muscleGain;
  }
  if (v.contains('kond') || v.contains('wydol')) {
    return BodyCompositionStrategy.performance;
  }
  if (v.contains('utrzym')) return BodyCompositionStrategy.maintenance;
  return BodyCompositionStrategy.recomposition;
}

/// Odwrotne mapowanie — utrzymuje stare pole `trainingMode` spójne z profilem
/// (stare ścieżki kodu, np. rekomendacje programów, dalej działają).
String legacyTrainingModeForStrategy(BodyCompositionStrategy strategy) {
  return switch (strategy) {
    BodyCompositionStrategy.fatLoss => 'Redukcja',
    BodyCompositionStrategy.muscleGain => 'Masa',
    BodyCompositionStrategy.performance => 'Kondycja',
    _ => 'Rekompozycja',
  };
}

// ============================================================================
// 3. Typ / priorytet treningu
// ============================================================================

/// Sposób trenowania. Celowo NIE zawiera redukcji/masy/rekompozycji/
/// utrzymania — to są strategie składu ciała, nie typy treningu.
enum TrainingFocus {
  hypertrophy('hypertrophy', 'Hipertrofia'),
  strength('strength', 'Siła'),
  strengthHypertrophy('strength_hypertrophy', 'Siła i hipertrofia'),
  endurance('endurance', 'Wytrzymałość'),
  running('running', 'Bieganie'),
  hybrid('hybrid', 'Trening hybrydowy'),
  generalFitness('general_fitness', 'Sprawność ogólna'),
  mobility('mobility', 'Mobilność'),
  corrective('corrective', 'Trening korekcyjny'),
  mixed('mixed', 'Mieszany');

  const TrainingFocus(this.id, this.label);

  final String id;
  final String label;

  static TrainingFocus? fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final focus in TrainingFocus.values) {
      if (focus.id == normalized) return focus;
    }
    return null;
  }

  /// Mapowanie luźnego tekstu (stare dane) na typ treningu. Wartości
  /// strategii (redukcja/masa/rekompozycja/utrzymanie) świadomie zwracają
  /// null — nie są typem treningu.
  static TrainingFocus? fromLegacyText(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v.contains('hipert')) return TrainingFocus.hypertrophy;
    if (v.contains('sił') || v.contains('sil')) return TrainingFocus.strength;
    if (v.contains('bieg')) return TrainingFocus.running;
    if (v.contains('wytrzym') || v.contains('endur')) {
      return TrainingFocus.endurance;
    }
    if (v.contains('hybryd')) return TrainingFocus.hybrid;
    if (v.contains('mobil')) return TrainingFocus.mobility;
    if (v.contains('korek')) return TrainingFocus.corrective;
    if (v.contains('sprawno')) return TrainingFocus.generalFitness;
    if (v.contains('miesz')) return TrainingFocus.mixed;
    return null;
  }
}

// ============================================================================
// Źródło celu i metadane synchronizacji
// ============================================================================

enum GoalSource {
  trainer('trainer', 'Trainer'),
  caloriesApp('calories_app', 'Licznik Kalorii'),
  manual('manual', 'Ręcznie'),
  aiRecommendation('ai_recommendation', 'Rekomendacja AI'),
  migrated('migrated', 'Migracja starych ustawień');

  const GoalSource(this.id, this.label);

  final String id;
  final String label;

  static GoalSource fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final source in GoalSource.values) {
      if (source.id == normalized) return source;
    }
    return GoalSource.trainer;
  }
}

/// Metadane synchronizacji celu między aplikacjami — ochrona przed pętlą
/// i nadpisaniem nowszej wersji starszą.
class GoalSyncMetadata {
  const GoalSyncMetadata({
    required this.sourceApp,
    required this.revision,
    required this.updatedAt,
    required this.changeId,
  });

  final String sourceApp;
  final int revision;
  final DateTime updatedAt;
  final String changeId;

  Map<String, dynamic> toJson() => {
        'sourceApp': sourceApp,
        'revision': revision,
        'updatedAt': updatedAt.toIso8601String(),
        'changeId': changeId,
      };

  factory GoalSyncMetadata.fromJson(Map<String, dynamic> json) =>
      GoalSyncMetadata(
        sourceApp: json['sourceApp']?.toString() ?? 'trainer',
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        changeId: json['changeId']?.toString() ?? '',
      );

  /// Czy przychodząca aktualizacja powinna zostać zastosowana przy znanym
  /// ostatnim stanie. Chroni przed: ponownym odebraniem tego samego
  /// [changeId] i nadpisaniem nowszej rewizji starszą.
  static bool shouldApplyIncoming({
    required int incomingRevision,
    required String incomingChangeId,
    required int lastAppliedRevision,
    required String lastAppliedChangeId,
  }) {
    if (incomingChangeId.isNotEmpty &&
        incomingChangeId == lastAppliedChangeId) {
      return false; // duplikat tej samej zmiany
    }
    if (incomingRevision < lastAppliedRevision) {
      return false; // starsza rewizja nie nadpisuje nowszej
    }
    return true;
  }
}

// ============================================================================
// Centralny profil celu
// ============================================================================

/// Jedno źródło prawdy o celu użytkownika. Trainer jest domyślnym właścicielem
/// profilu; Kalorie tylko go odbierają.
class UserBodyGoalProfile {
  const UserBodyGoalProfile({
    required this.desiredPhysique,
    this.customPhysiqueDescription = '',
    this.physiquePriorities = const [],
    required this.bodyCompositionStrategy,
    required this.trainingFocus,
    this.secondaryTrainingFocuses = const [],
    this.targetBodyFatMinPercent,
    this.targetBodyFatMaxPercent,
    this.targetWeightKg,
    this.targetWaistCm,
    this.targetTimeframeWeeks,
    this.paceKgPerWeek,
    this.automaticRecommendationsEnabled = true,
    this.calorieTargetLocked = false,
    this.autoPublishToCalories = true,
    required this.goalSource,
    required this.updatedAt,
    this.revision = 1,
    this.changeId = '',
  });

  static const schemaVersion = 1;

  final DesiredPhysique desiredPhysique;

  /// Opis własnej sylwetki (dla [DesiredPhysique.custom]).
  final String customPhysiqueDescription;
  final List<PhysiquePriority> physiquePriorities;
  final BodyCompositionStrategy bodyCompositionStrategy;
  final TrainingFocus trainingFocus;
  final List<TrainingFocus> secondaryTrainingFocuses;

  /// Docelowy ZAKRES tkanki tłuszczowej (osobne pole, ręcznie edytowalne —
  /// nie wynika sztywno z nazwy sylwetki).
  final double? targetBodyFatMinPercent;
  final double? targetBodyFatMaxPercent;
  final double? targetWeightKg;
  final double? targetWaistCm;
  final int? targetTimeframeWeeks;

  /// Preferowane tempo zmiany masy (kg/tydzień; znak wynika ze strategii).
  final double? paceKgPerWeek;

  final bool automaticRecommendationsEnabled;

  /// Ręczna blokada celu kalorycznego — most nie nadpisuje kcal w Kaloriach.
  final bool calorieTargetLocked;

  /// Czy Trainer automatycznie publikuje aktualizacje celu do Kalorii.
  final bool autoPublishToCalories;

  final GoalSource goalSource;
  final DateTime updatedAt;

  /// Numer wersji konfiguracji — rośnie przy każdej zmianie.
  final int revision;

  /// Unikalny identyfikator ostatniej zmiany.
  final String changeId;

  /// Środek docelowego zakresu BF (do prostych porównań).
  double? get targetBodyFatPercent {
    final min = targetBodyFatMinPercent;
    final max = targetBodyFatMaxPercent;
    if (min == null && max == null) return null;
    if (min != null && max != null) return (min + max) / 2;
    return min ?? max;
  }

  /// Priorytety sylwetkowe przetłumaczone na partie mięśniowe.
  ///
  /// Używane przy budowie i analizie zestawów („czy zestaw w ogóle rusza to,
  /// co dla mnie ważne?"). Priorytety bez jednoznacznej partii (symetria,
  /// proporcje, cel niestandardowy) są celowo pomijane — nie zgadujemy.
  List<MuscleGroup> get priorityMuscleGroups {
    final result = <MuscleGroup>[];
    for (final priority in physiquePriorities) {
      final group = switch (priority) {
        PhysiquePriority.biggerShoulders => MuscleGroup.shoulders,
        PhysiquePriority.widerBack => MuscleGroup.back,
        PhysiquePriority.biggerChest => MuscleGroup.chest,
        PhysiquePriority.biggerArms => MuscleGroup.biceps,
        PhysiquePriority.strongerForearms => MuscleGroup.forearms,
        PhysiquePriority.biggerLegs => MuscleGroup.quadriceps,
        PhysiquePriority.strongerGlutes => MuscleGroup.glutes,
        PhysiquePriority.visibleAbs => MuscleGroup.core,
        PhysiquePriority.narrowerWaist => MuscleGroup.core,
        PhysiquePriority.upperLowerBalance => null,
        PhysiquePriority.symmetry => null,
        PhysiquePriority.sideProfile => null,
        PhysiquePriority.custom => null,
      };
      if (group != null && !result.contains(group)) result.add(group);
    }
    return result;
  }

  /// Efektywna strategia do obliczeń — „automatyczna" liczy się jak
  /// utrzymanie do czasu zatwierdzenia rekomendacji przez użytkownika.
  BodyCompositionStrategy get effectiveStrategy =>
      bodyCompositionStrategy == BodyCompositionStrategy.automatic
          ? BodyCompositionStrategy.maintenance
          : bodyCompositionStrategy;

  UserBodyGoalProfile copyWith({
    DesiredPhysique? desiredPhysique,
    String? customPhysiqueDescription,
    List<PhysiquePriority>? physiquePriorities,
    BodyCompositionStrategy? bodyCompositionStrategy,
    TrainingFocus? trainingFocus,
    List<TrainingFocus>? secondaryTrainingFocuses,
    double? targetBodyFatMinPercent,
    double? targetBodyFatMaxPercent,
    double? targetWeightKg,
    double? targetWaistCm,
    int? targetTimeframeWeeks,
    double? paceKgPerWeek,
    bool? automaticRecommendationsEnabled,
    bool? calorieTargetLocked,
    bool? autoPublishToCalories,
    GoalSource? goalSource,
    DateTime? updatedAt,
    int? revision,
    String? changeId,
    bool clearTargetBodyFat = false,
    bool clearTargetWeight = false,
    bool clearTargetWaist = false,
  }) {
    return UserBodyGoalProfile(
      desiredPhysique: desiredPhysique ?? this.desiredPhysique,
      customPhysiqueDescription:
          customPhysiqueDescription ?? this.customPhysiqueDescription,
      physiquePriorities: physiquePriorities ?? this.physiquePriorities,
      bodyCompositionStrategy:
          bodyCompositionStrategy ?? this.bodyCompositionStrategy,
      trainingFocus: trainingFocus ?? this.trainingFocus,
      secondaryTrainingFocuses:
          secondaryTrainingFocuses ?? this.secondaryTrainingFocuses,
      targetBodyFatMinPercent: clearTargetBodyFat
          ? null
          : (targetBodyFatMinPercent ?? this.targetBodyFatMinPercent),
      targetBodyFatMaxPercent: clearTargetBodyFat
          ? null
          : (targetBodyFatMaxPercent ?? this.targetBodyFatMaxPercent),
      targetWeightKg:
          clearTargetWeight ? null : (targetWeightKg ?? this.targetWeightKg),
      targetWaistCm:
          clearTargetWaist ? null : (targetWaistCm ?? this.targetWaistCm),
      targetTimeframeWeeks: targetTimeframeWeeks ?? this.targetTimeframeWeeks,
      paceKgPerWeek: paceKgPerWeek ?? this.paceKgPerWeek,
      automaticRecommendationsEnabled: automaticRecommendationsEnabled ??
          this.automaticRecommendationsEnabled,
      calorieTargetLocked: calorieTargetLocked ?? this.calorieTargetLocked,
      autoPublishToCalories:
          autoPublishToCalories ?? this.autoPublishToCalories,
      goalSource: goalSource ?? this.goalSource,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      changeId: changeId ?? this.changeId,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'desiredPhysique': desiredPhysique.id,
        'customPhysiqueDescription': customPhysiqueDescription,
        'physiquePriorities': [for (final p in physiquePriorities) p.id],
        'bodyCompositionStrategy': bodyCompositionStrategy.id,
        'trainingFocus': trainingFocus.id,
        'secondaryTrainingFocuses': [
          for (final f in secondaryTrainingFocuses) f.id,
        ],
        'targetBodyFatMinPercent': targetBodyFatMinPercent,
        'targetBodyFatMaxPercent': targetBodyFatMaxPercent,
        'targetWeightKg': targetWeightKg,
        'targetWaistCm': targetWaistCm,
        'targetTimeframeWeeks': targetTimeframeWeeks,
        'paceKgPerWeek': paceKgPerWeek,
        'automaticRecommendationsEnabled': automaticRecommendationsEnabled,
        'calorieTargetLocked': calorieTargetLocked,
        'autoPublishToCalories': autoPublishToCalories,
        'goalSource': goalSource.id,
        'updatedAt': updatedAt.toIso8601String(),
        'revision': revision,
        'changeId': changeId,
      };

  factory UserBodyGoalProfile.fromJson(Map<String, dynamic> json) {
    double? optDouble(Object? value) {
      if (value is num && value.isFinite) return value.toDouble();
      final parsed =
          double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }

    return UserBodyGoalProfile(
      desiredPhysique:
          DesiredPhysique.fromId(json['desiredPhysique']?.toString()) ??
              DesiredPhysique.athletic,
      customPhysiqueDescription:
          json['customPhysiqueDescription']?.toString() ?? '',
      physiquePriorities: [
        for (final raw in (json['physiquePriorities'] as List? ?? const []))
          if (PhysiquePriority.fromId(raw?.toString()) != null)
            PhysiquePriority.fromId(raw?.toString())!,
      ],
      bodyCompositionStrategy: BodyCompositionStrategy.fromId(
            json['bodyCompositionStrategy']?.toString(),
          ) ??
          BodyCompositionStrategy.recomposition,
      trainingFocus: TrainingFocus.fromId(json['trainingFocus']?.toString()) ??
          TrainingFocus.strengthHypertrophy,
      secondaryTrainingFocuses: [
        for (final raw
            in (json['secondaryTrainingFocuses'] as List? ?? const []))
          if (TrainingFocus.fromId(raw?.toString()) != null)
            TrainingFocus.fromId(raw?.toString())!,
      ],
      targetBodyFatMinPercent: optDouble(json['targetBodyFatMinPercent']),
      targetBodyFatMaxPercent: optDouble(json['targetBodyFatMaxPercent']),
      targetWeightKg: optDouble(json['targetWeightKg']),
      targetWaistCm: optDouble(json['targetWaistCm']),
      targetTimeframeWeeks: (json['targetTimeframeWeeks'] as num?)?.toInt(),
      paceKgPerWeek: optDouble(json['paceKgPerWeek']),
      automaticRecommendationsEnabled:
          json['automaticRecommendationsEnabled'] as bool? ?? true,
      calorieTargetLocked: json['calorieTargetLocked'] as bool? ?? false,
      autoPublishToCalories: json['autoPublishToCalories'] as bool? ?? true,
      goalSource: GoalSource.fromId(json['goalSource']?.toString()),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      changeId: json['changeId']?.toString() ?? '',
    );
  }

  GoalSyncMetadata get syncMetadata => GoalSyncMetadata(
        sourceApp: 'trainer',
        revision: revision,
        updatedAt: updatedAt,
        changeId: changeId,
      );

  /// Zwięzła sygnatura merytoryczna (bez updatedAt/changeId) — do wykrywania,
  /// czy zmiana faktycznie zmienia treść celu.
  String get signature => [
        desiredPhysique.id,
        [for (final p in physiquePriorities) p.id].join(','),
        bodyCompositionStrategy.id,
        trainingFocus.id,
        [for (final f in secondaryTrainingFocuses) f.id].join(','),
        targetBodyFatMinPercent?.toStringAsFixed(1) ?? '',
        targetBodyFatMaxPercent?.toStringAsFixed(1) ?? '',
        targetWeightKg?.toStringAsFixed(1) ?? '',
        targetWaistCm?.toStringAsFixed(1) ?? '',
        calorieTargetLocked ? 'locked' : '',
      ].join('|');
}

// ============================================================================
// Historia etapów celu
// ============================================================================

/// Jeden etap strategii w czasie (np. redukcja 23% → 17%, potem utrzymanie).
/// Poprzedni etap NIGDY nie jest nadpisywany — zamykamy go i dodajemy nowy.
class GoalPhase {
  const GoalPhase({
    required this.strategy,
    required this.startDate,
    this.endDate,
    this.startWeightKg,
    this.endWeightKg,
    this.startBodyFatPercent,
    this.endBodyFatPercent,
    this.startWaistCm,
    this.endWaistCm,
    this.reason,
    this.notes,
  });

  final BodyCompositionStrategy strategy;
  final DateTime startDate;
  final DateTime? endDate;
  final double? startWeightKg;
  final double? endWeightKg;
  final double? startBodyFatPercent;
  final double? endBodyFatPercent;
  final double? startWaistCm;
  final double? endWaistCm;
  final String? reason;
  final String? notes;

  bool get isActive => endDate == null;

  GoalPhase closed({
    required DateTime endDate,
    double? endWeightKg,
    double? endBodyFatPercent,
    double? endWaistCm,
  }) {
    return GoalPhase(
      strategy: strategy,
      startDate: startDate,
      endDate: endDate,
      startWeightKg: startWeightKg,
      endWeightKg: endWeightKg ?? this.endWeightKg,
      startBodyFatPercent: startBodyFatPercent,
      endBodyFatPercent: endBodyFatPercent ?? this.endBodyFatPercent,
      startWaistCm: startWaistCm,
      endWaistCm: endWaistCm ?? this.endWaistCm,
      reason: reason,
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'strategy': strategy.id,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'startWeightKg': startWeightKg,
        'endWeightKg': endWeightKg,
        'startBodyFatPercent': startBodyFatPercent,
        'endBodyFatPercent': endBodyFatPercent,
        'startWaistCm': startWaistCm,
        'endWaistCm': endWaistCm,
        'reason': reason,
        'notes': notes,
      };

  factory GoalPhase.fromJson(Map<String, dynamic> json) {
    double? optDouble(Object? value) =>
        (value is num && value.isFinite) ? value.toDouble() : null;
    return GoalPhase(
      strategy: BodyCompositionStrategy.fromId(json['strategy']?.toString()) ??
          BodyCompositionStrategy.maintenance,
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? '') ??
          DateTime.now(),
      endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
      startWeightKg: optDouble(json['startWeightKg']),
      endWeightKg: optDouble(json['endWeightKg']),
      startBodyFatPercent: optDouble(json['startBodyFatPercent']),
      endBodyFatPercent: optDouble(json['endBodyFatPercent']),
      startWaistCm: optDouble(json['startWaistCm']),
      endWaistCm: optDouble(json['endWaistCm']),
      reason: json['reason']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

// ============================================================================
// Migracja starych ustawień
// ============================================================================

/// Buduje centralny profil celu ze STARYCH pól ustawień.
/// Nie usuwa niczego — stare pola pozostają w ustawieniach dla zgodności.
UserBodyGoalProfile migrateLegacyGoalProfile({
  required String legacyTrainingMode,
  required String legacyTargetSilhouette,
  double legacyTargetWeightKg = 0,
  DateTime? now,
  String? changeId,
}) {
  final timestamp = now ?? DateTime.now();
  final physique =
      DesiredPhysique.fromLegacySilhouetteId(legacyTargetSilhouette) ??
          DesiredPhysique.athletic;
  var strategy = strategyFromLegacyTrainingMode(legacyTrainingMode);
  // Stara sylwetka „rekompozycja" niosła też strategię — uszanuj ją,
  // jeśli tryb treningu nie mówił inaczej (domyślny tryb to rekompozycja).
  if (legacyTargetSilhouette.trim() == 'recomposition') {
    strategy = BodyCompositionStrategy.recomposition;
  }

  final focus = switch (physique) {
    DesiredPhysique.strengthBuild => TrainingFocus.strength,
    DesiredPhysique.veryMuscular ||
    DesiredPhysique.muscular =>
      TrainingFocus.hypertrophy,
    DesiredPhysique.runner => TrainingFocus.running,
    DesiredPhysique.functional => TrainingFocus.generalFitness,
    _ => TrainingFocus.strengthHypertrophy,
  };

  return UserBodyGoalProfile(
    desiredPhysique: physique,
    bodyCompositionStrategy: strategy,
    trainingFocus: focus,
    targetWeightKg: legacyTargetWeightKg > 0 ? legacyTargetWeightKg : null,
    goalSource: GoalSource.migrated,
    updatedAt: timestamp,
    revision: 1,
    changeId: changeId ?? 'migration_${timestamp.microsecondsSinceEpoch}',
  );
}

/// Sugerowany (NIE narzucony) zakres docelowego BF dla sylwetki i płci —
/// tylko podpowiedź do UI; pole pozostaje ręcznie edytowalne.
({double min, double max}) suggestedBodyFatRange(
  DesiredPhysique physique, {
  required bool isFemale,
}) {
  final base = switch (physique) {
    DesiredPhysique.shredded => (min: 8.0, max: 12.0),
    DesiredPhysique.leanAthletic => (min: 10.0, max: 14.0),
    DesiredPhysique.vTaper => (min: 10.0, max: 15.0),
    DesiredPhysique.athletic => (min: 12.0, max: 16.0),
    DesiredPhysique.runner => (min: 10.0, max: 16.0),
    DesiredPhysique.functional => (min: 12.0, max: 18.0),
    DesiredPhysique.muscular => (min: 12.0, max: 17.0),
    DesiredPhysique.veryMuscular => (min: 13.0, max: 18.0),
    DesiredPhysique.strengthBuild => (min: 15.0, max: 22.0),
    DesiredPhysique.custom => (min: 12.0, max: 18.0),
  };
  // Fizjologicznie wyższy niezbędny poziom tkanki tłuszczowej u kobiet.
  if (isFemale) return (min: base.min + 8, max: base.max + 8);
  return base;
}

// ============================================================================
// Automatyczna rekomendacja strategii (wymaga zatwierdzenia)
// ============================================================================

/// Propozycja strategii — NIGDY nie jest stosowana automatycznie.
class StrategyRecommendation {
  const StrategyRecommendation({
    required this.strategy,
    required this.reason,
    required this.categorical,
  });

  final BodyCompositionStrategy strategy;
  final String reason;

  /// false = niska pewność danych; rekomendacja sformułowana ostrożnie
  /// i nie powinna być prezentowana jako kategoryczna.
  final bool categorical;

  /// Zmiana strategii zawsze wymaga zgody użytkownika.
  bool get requiresConfirmation => true;
}

/// Proponuje strategię na podstawie danych. Zwraca null przy braku danych.
StrategyRecommendation? recommendBodyCompositionStrategy({
  required double bodyFatPercent,
  required double bodyFatConfidencePercent,
  required bool isFemale,
  double weightTrendKgPerWeek = 0,
  int trainingDaysPerWeek = 0,
  double ffmi = 0,
}) {
  if (!bodyFatPercent.isFinite || bodyFatPercent <= 0) return null;

  // Progi przesunięte dla kobiet o fizjologiczne +8 p.p.
  final shift = isFemale ? 8.0 : 0.0;
  final highBf = bodyFatPercent >= 25 + shift;
  final moderateBf = bodyFatPercent >= 17 + shift && !highBf;
  final lowBf = bodyFatPercent < 12 + shift;

  final lowConfidence =
      confidenceLevelFor(bodyFatConfidencePercent) == ConfidenceLevel.low;
  final goodMuscleBase = ffmi >= 19;
  final trainsRegularly = trainingDaysPerWeek >= 3;

  BodyCompositionStrategy strategy;
  String reason;
  if (highBf) {
    strategy = BodyCompositionStrategy.fatLoss;
    reason = 'Obecny szacunek tkanki tłuszczowej może wskazywać, że '
        'kontrolowana redukcja będzie teraz najskuteczniejsza. Trening '
        'siłowy i wysokie białko pomogą zachować mięśnie.';
  } else if (moderateBf && (goodMuscleBase || trainsRegularly)) {
    strategy = BodyCompositionStrategy.recomposition;
    reason = 'Na podstawie obecnego poziomu tkanki tłuszczowej, bazy '
        'mięśniowej i regularnych treningów rekompozycja lub łagodna '
        'redukcja może być obecnie korzystniejsza niż klasyczna masa.';
  } else if (moderateBf) {
    strategy = BodyCompositionStrategy.recomposition;
    reason = 'Umiarkowany poziom tkanki tłuszczowej może sprzyjać '
        'rekompozycji — pracy nad składem ciała bez dużej zmiany masy.';
  } else if (lowBf) {
    strategy = BodyCompositionStrategy.muscleGain;
    reason = 'Niski szacowany poziom tkanki tłuszczowej może sprzyjać '
        'kontrolowanej budowie masy mięśniowej.';
  } else {
    strategy = BodyCompositionStrategy.maintenance;
    reason = 'Skład ciała wygląda stabilnie — utrzymanie z progresją '
        'treningową może być teraz dobrym wyborem.';
  }

  if (lowConfidence) {
    reason = 'Pewność analizy jest niska, więc potraktuj to wyłącznie jako '
        'wstępną sugestię: $reason Rozważ powtórzenie analizy w lepszych '
        'warunkach przed zmianą strategii.';
  }

  return StrategyRecommendation(
    strategy: strategy,
    reason: reason,
    categorical: !lowConfidence,
  );
}

// ============================================================================
// Konflikty konfiguracji
// ============================================================================

/// Wykryty konflikt ustawień — pokazujemy komunikat, NIC nie zmieniamy sami.
class GoalConflict {
  const GoalConflict({
    required this.message,
    required this.source,
    this.suggestion = '',
  });

  final String message;

  /// Skąd pochodzi konflikt (np. 'kalorie', 'strategia', 'talia').
  final String source;
  final String suggestion;
}

/// Walidacja konfliktów między strategią, kaloriami i trendami.
List<GoalConflict> detectGoalConflicts({
  required BodyCompositionStrategy strategy,
  int goalKcal = 0,
  int tdeeKcal = 0,
  double waistTrendCmPerWeek = 0,
  List<PhysiquePriority> priorities = const [],
  int lastAppliedRevision = -1,
  int currentRevision = -1,
  bool caloriesManuallyChanged = false,
}) {
  final conflicts = <GoalConflict>[];

  if (goalKcal > 0 && tdeeKcal > 0) {
    final ratio = goalKcal / tdeeKcal;
    if (strategy == BodyCompositionStrategy.fatLoss && ratio > 1.05) {
      conflicts.add(const GoalConflict(
        message: 'Twoja aktualna konfiguracja może nie wspierać wybranego '
            'celu. Strategia to redukcja, ale cel kaloryczny wskazuje '
            'znaczną nadwyżkę.',
        source: 'kalorie',
        suggestion: 'Obniż bazowy cel kaloryczny i zachowaj kontrolowany '
            'deficyt albo zmień strategię.',
      ));
    }
    if (strategy == BodyCompositionStrategy.muscleGain && ratio < 0.90) {
      conflicts.add(const GoalConflict(
        message: 'Strategia to budowa masy mięśniowej, ale cel kaloryczny '
            'wskazuje duży deficyt.',
        source: 'kalorie',
        suggestion: 'Podnieś bazowy cel kaloryczny o niewielką nadwyżkę '
            'albo zmień strategię.',
      ));
    }
  }

  if (priorities.contains(PhysiquePriority.visibleAbs) &&
      waistTrendCmPerWeek > 0.15) {
    conflicts.add(const GoalConflict(
      message: 'Cel „widoczny brzuch" przy rosnącym trendzie obwodu talii.',
      source: 'talia',
      suggestion: 'Sprawdź bilans energii i średnią z kilku tygodni — sama '
          'pojedyncza zmiana talii może być szumem pomiarowym.',
    ));
  }

  if (caloriesManuallyChanged) {
    conflicts.add(const GoalConflict(
      message: 'Cel jest zsynchronizowany z Trainerem, ale został ręcznie '
          'zmieniony w aplikacji Kalorie.',
      source: 'synchronizacja',
      suggestion: 'Wybierz źródło prawdy: zablokuj cel kaloryczny albo '
          'przywróć synchronizację z Trainerem.',
    ));
  }

  if (lastAppliedRevision >= 0 &&
      currentRevision >= 0 &&
      lastAppliedRevision != currentRevision) {
    conflicts.add(const GoalConflict(
      message: 'Aplikacje mają różne wersje celu '
          '(Trainer: rewizja $kRevisionPlaceholder).',
      source: 'synchronizacja',
      suggestion: 'Zsynchronizuj aplikacje — nowsza rewizja powinna wygrać.',
    ));
  }

  return conflicts;
}

/// Placeholder do komunikatu o rewizji (podmieniany w UI, jeśli potrzebny).
const kRevisionPlaceholder = '—';

// ============================================================================
// Cele energetyczne i makro — liczone ZE STRATEGII
// ============================================================================

/// Dzienne cele żywieniowe wyliczone z centralnego profilu celu.
/// Zamiast jednej sztywnej liczby: cel centralny + zakres + dzień
/// treningowy/regeneracyjny + powód wyliczenia.
class GoalNutritionTargets {
  const GoalNutritionTargets({
    required this.strategy,
    required this.physiqueId,
    required this.physiqueLabel,
    required this.goalKcal,
    required this.kcalMin,
    required this.kcalMax,
    required this.trainingDayKcal,
    required this.restDayKcal,
    required this.proteinG,
    required this.proteinMinG,
    required this.proteinMaxG,
    required this.fatG,
    required this.carbsG,
    required this.sugarLimitG,
    required this.fiberGoalG,
    required this.saturatedFatLimitG,
    required this.saltLimitG,
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.rationale,
    this.sync,
    this.calorieTargetLocked = false,
  });

  static const schema = 'trainer.nutrition_targets.v3';

  final BodyCompositionStrategy strategy;
  final String physiqueId;
  final String physiqueLabel;

  /// Cel centralny (średnia tygodniowa).
  final int goalKcal;

  /// Zalecany zakres dzienny.
  final int kcalMin;
  final int kcalMax;

  /// Cele dnia treningowego / regeneracyjnego (średnia tygodniowa = cel
  /// centralny).
  final int trainingDayKcal;
  final int restDayKcal;

  final int proteinG;
  final int proteinMinG;
  final int proteinMaxG;
  final int fatG;
  final int carbsG;

  /// Orientacyjny limit cukrów wolnych/dodanych. Etykiety produktów zwykle
  /// podają cukry ogółem, więc odbiorca powinien wyjaśnić tę różnicę w UI.
  final int sugarLimitG;

  /// Minimalny dzienny cel błonnika.
  final int fiberGoalG;

  /// Górne limity jakościowe diety.
  final int saturatedFatLimitG;
  final int saltLimitG;
  final int bmrKcal;
  final int tdeeKcal;

  /// Czytelny powód wyliczenia (strategia + sposób obliczenia).
  final String rationale;

  /// Metadane synchronizacji celu (rewizja/changeId/źródło).
  final GoalSyncMetadata? sync;

  /// Ręczna blokada celu kalorycznego po stronie użytkownika.
  final bool calorieTargetLocked;

  /// Etykiety zgodne ze starym typem (UI i starszy odbiorca mostu).
  String get phaseLabel => strategy.legacyPhaseLabel;
  String get silhouetteLabel => physiqueLabel;
  String get silhouetteId => physiqueId;

  /// Payload mostu. Zachowuje klucze v1 (goalKcal/proteinG/carbsG/fatG/
  /// silhouetteId/silhouetteLabel/phaseLabel), więc starsze Kalorie dalej
  /// działają; nowe pola niosą strategię, zakresy i metadane synchronizacji.
  Map<String, dynamic> toJson() => {
        'schema': schema,
        'calorieModelVersion': 2,
        'nutritionModelVersion': 3,
        // --- klucze v1 (kompatybilność wsteczna) ---
        'silhouetteId': physiqueId,
        'silhouetteLabel': physiqueLabel,
        'phaseLabel': phaseLabel,
        'goalKcal': goalKcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'sugarLimitG': sugarLimitG,
        'fiberGoalG': fiberGoalG,
        'saturatedFatLimitG': saturatedFatLimitG,
        'saltLimitG': saltLimitG,
        'bmrKcal': bmrKcal,
        'tdeeKcal': tdeeKcal,
        // --- rozszerzenie v2 ---
        'strategyId': strategy.id,
        'strategyLabel': strategy.label,
        'kcalMin': kcalMin,
        'kcalMax': kcalMax,
        'trainingDayKcal': trainingDayKcal,
        'restDayKcal': restDayKcal,
        'proteinMinG': proteinMinG,
        'proteinMaxG': proteinMaxG,
        'rationale': rationale,
        'calorieTargetLocked': calorieTargetLocked,
        if (sync != null) 'goalSync': sync!.toJson(),
      };

  /// Sygnatura do wykrywania zmian (publikacja mostu).
  String get signature =>
      '$physiqueId:${strategy.id}:$goalKcal:$proteinG:$carbsG:$fatG'
      ':$sugarLimitG:$fiberGoalG:$saturatedFatLimitG:$saltLimitG'
      ':$trainingDayKcal:$restDayKcal:${calorieTargetLocked ? 'L' : ''}'
      ':${sync?.revision ?? 0}';
}

/// Liczy dzienne cele z profilu celu i danych ciała.
///
/// - REE: Mifflin-St Jeor; baza: REE + efekt termiczny jedzenia,
/// - kcal: baza bez aktywności × współczynnik STRATEGII,
/// - białko: g/kg FFM (gdy znana) albo g/kg masy ciała — nigdy % kalorii,
/// - tłuszcz: g/kg masy ciała w zakresie 20–35% energii; węgle dopełniają,
/// - błonnik: 14 g/1000 kcal (minimum 25 g),
/// - cukry wolne i nasycone: do 10% energii; sól: do 5 g,
/// - dzień treningowy/regeneracyjny: rozrzut wokół celu centralnego tak,
///   żeby średnia tygodniowa была równa celowi centralnemu.
///
/// Zwraca null przy braku sensownego profilu (masa/wzrost).
/// Resting energy expenditure estimated with Mifflin-St Jeor.
double mifflinStJeorRestingEnergy({
  required double weightKg,
  required double heightCm,
  required int age,
  required String sex,
}) {
  final normalizedSex = sex.trim().toLowerCase();
  final isFemale = normalizedSex.startsWith('k') ||
      normalizedSex.startsWith('f') ||
      normalizedSex.contains('kob');
  return 10 * weightKg +
      6.25 * heightCm -
      5 * age.clamp(18, 100) +
      (isFemale ? -161 : 5);
}

/// Maintenance base without work, steps, running or training.
/// Only the thermic effect of food is added to resting expenditure here.
double activityFreeMaintenanceFromRestingEnergy(
  double restingEnergy, {
  double thermicEffectShare = 0.10,
}) {
  final safeShare = thermicEffectShare.clamp(0.0, 0.25);
  return restingEnergy / (1 - safeShare);
}

/// Netto kcal z PRACY ZAWODOWEJ w dniu roboczym: (MET − 1) × kg × godziny.
///
/// Praca należy do BAZOWEGO ZERA — nie jest sportem i nie może wracać jako
/// „korekta dnia", bo wtedy ten sam ruch liczy się dwa razy.
double occupationalEnergyKcal({
  required double weightKg,
  required String workIntensity,
  required double workHoursPerDay,
}) {
  final met = switch (workIntensity.trim().toLowerCase()) {
    'sedentary' => 1.4,
    'light' => 1.8,
    'moderate' => 2.4,
    'heavy' => 3.2,
    _ => 1.0,
  };
  if (met <= 1) return 0;
  final safeWeight = weightKg.isFinite ? weightKg.clamp(30.0, 300.0) : 80.0;
  final safeHours =
      workHoursPerDay.isFinite ? workHoursPerDay.clamp(0.0, 16.0) : 0.0;
  if (safeHours <= 0) return 0;
  return (met - 1.0) * safeWeight * safeHours;
}

/// Netto kcal z CODZIENNEGO RUCHU poza pracą (NEAT: chodzenie, dom, zakupy).
///
/// To celowo NIE są klasyczne mnożniki PAL (1.35–1.9) — tamte zawierają już
/// pracę i treningi, więc użyte tu liczyłyby aktywność podwójnie.
///
/// [movementFactor] opisuje STYL ŻYCIA, nie plan treningowy. Liczba
/// zaplanowanych dni treningowych świadomie nie ma tu wpływu: wykonany trening
/// podnosi cel dynamicznie, więc plan nie może podnosić go po raz drugi.
double dailyMovementEnergyKcal({
  required double restingEnergy,
  double movementFactor = 1.15,
}) {
  final safeFactor = movementFactor.isFinite
      ? movementFactor.clamp(1.0, 1.4)
      : 1.15;
  return (safeFactor - 1.0) * restingEnergy;
}

GoalNutritionTargets? computeGoalNutritionTargets({
  required UserBodyGoalProfile? profile,
  required double weightKg,
  required double heightCm,
  required int age,
  required String sex,
  required int trainingDaysPerWeek,
  double fatFreeMassKg = 0,
  String workIntensity = 'none',
  double workHoursPerDay = 0,
}) {
  if (profile == null) return null;
  if (!weightKg.isFinite || !heightCm.isFinite) return null;
  if (weightKg <= 0 || heightCm <= 0) return null;
  final strategy = profile.effectiveStrategy;

  // BAZOWE ZERO ma warstwy: spoczynek + trawienie + praca zawodowa + codzienny
  // ruch. Poza nim zostaje wyłącznie SPORT (trening, bieg), doliczany raz
  // z faktycznego pakietu aktywności dnia. Wcześniej baza była „bez
  // aktywności", więc praca i kroki wracały jako korekta dnia — ten sam ruch
  // liczył się dwa razy, a makro zostawało policzone dla samej bazy.
  final bmr = mifflinStJeorRestingEnergy(
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
    sex: sex,
  );
  final maintenance = activityFreeMaintenanceFromRestingEnergy(bmr);
  final occupational = occupationalEnergyKcal(
    weightKg: weightKg,
    workIntensity: workIntensity,
    workHoursPerDay: workHoursPerDay,
  );
  final movement = dailyMovementEnergyKcal(restingEnergy: bmr);
  final tdee = maintenance + occupational + movement;

  // --- Kcal ze strategii. ---
  final (kcalFactor, rationaleCore) = switch (strategy) {
    BodyCompositionStrategy.fatLoss => (
        0.82,
        'baza z pracą i chodzeniem minus kontrolowany deficyt (~18%)',
      ),
    BodyCompositionStrategy.recomposition => (
        0.93,
        'baza z pracą i chodzeniem z niewielkim deficytem (rekompozycja)',
      ),
    BodyCompositionStrategy.muscleGain => (
        1.08,
        'baza z pracą i chodzeniem plus niewielka nadwyżka (budowa mięśni)',
      ),
    BodyCompositionStrategy.maintenance => (
        1.0,
        'baza z pracą i chodzeniem (utrzymanie)'
      ),
    BodyCompositionStrategy.performance => (
        1.05,
        'baza z pracą i chodzeniem z zapasem pod wydolność',
      ),
    BodyCompositionStrategy.automatic => (
        1.0,
        'baza z pracą i chodzeniem (do czasu '
            'zatwierdzenia rekomendacji strategia liczona jak utrzymanie)'
      ),
  };

  var goalKcal = tdee * kcalFactor;
  // Bezpieczny dolny próg deficytu — nigdy poniżej ~BMR.
  if (goalKcal < bmr) goalKcal = bmr;

  int roundTo(double value, int step) => (value / step).round() * step;
  final kcalRounded =
      goalKcal <= bmr ? (bmr / 10).ceil() * 10 : roundTo(goalKcal, 10);

  // --- Zakres dzienny ±5%. ---
  final kcalMin = roundTo(goalKcal * 0.95, 10);
  final kcalMax = roundTo(goalKcal * 1.05, 10);

  // --- Dzień treningowy/regeneracyjny (średnia tygodniowa = cel). ---
  // One base for every day. A completed workout raises the target dynamically,
  // so the planned number of training days must not raise it a second time.
  final trainingDayKcal = kcalRounded;
  final restDayKcal = kcalRounded;

  // --- Białko: preferuj FFM, inaczej masa ciała. Nigdy % kalorii. ---
  final proteinPerKgBody = switch (strategy) {
    BodyCompositionStrategy.fatLoss => 2.2,
    BodyCompositionStrategy.recomposition => 2.0,
    BodyCompositionStrategy.muscleGain => 1.9,
    BodyCompositionStrategy.performance => 1.6,
    _ => 1.7,
  };
  final proteinPerKgFfm = switch (strategy) {
    BodyCompositionStrategy.fatLoss => 2.6,
    BodyCompositionStrategy.recomposition => 2.4,
    BodyCompositionStrategy.muscleGain => 2.3,
    BodyCompositionStrategy.performance => 2.0,
    _ => 2.1,
  };
  final useFfm =
      fatFreeMassKg.isFinite && fatFreeMassKg > 0 && fatFreeMassKg < weightKg;
  final proteinBase =
      useFfm ? fatFreeMassKg * proteinPerKgFfm : weightKg * proteinPerKgBody;
  final proteinG = roundTo(proteinBase, 5);
  final proteinMinG = roundTo(proteinBase * 0.9, 5);
  final proteinMaxG = roundTo(proteinBase * 1.1, 5);

  // --- Tłuszcz g/kg masy w referencyjnym zakresie 20–35% energii. ---
  final fatPerKg = switch (strategy) {
    BodyCompositionStrategy.fatLoss => 0.8,
    BodyCompositionStrategy.recomposition => 0.9,
    _ => 1.0,
  };
  final fatMinG = kcalRounded * 0.20 / 9;
  final fatMaxG = kcalRounded * 0.35 / 9;
  final fatBaseG = weightKg * fatPerKg;
  final fatG = fatBaseG.clamp(fatMinG, fatMaxG).round();
  final carbsKcal = kcalRounded - proteinG * 4 - fatG * 9;
  final carbsG = carbsKcal <= 0 ? 0 : roundTo(carbsKcal / 4, 5);

  // Cele jakościowe nie rosną wraz ze spalonymi kcal dnia. Cukier jest
  // orientacyjnym limitem cukrów wolnych/dodanych; dane z etykiet żywności
  // najczęściej zawierają cukry ogółem.
  final sugarLimitG = (kcalRounded * 0.10 / 4).floor();
  final fiberGoalG = max(25, (kcalRounded / 1000 * 14).round());
  final saturatedFatLimitG = (kcalRounded * 0.10 / 9).floor();
  const saltLimitG = 5;

  final proteinBasis = useFfm
      ? 'białko z beztłuszczowej masy ciała '
          '(${proteinPerKgFfm.toStringAsFixed(1)} g/kg FFM)'
      : 'białko z masy ciała (${proteinPerKgBody.toStringAsFixed(1)} g/kg)';

  return GoalNutritionTargets(
    strategy: strategy,
    physiqueId: profile.desiredPhysique.id,
    physiqueLabel: profile.desiredPhysique.label,
    goalKcal: kcalRounded,
    kcalMin: kcalMin,
    kcalMax: kcalMax,
    trainingDayKcal: trainingDayKcal,
    restDayKcal: restDayKcal,
    proteinG: proteinG,
    proteinMinG: proteinMinG,
    proteinMaxG: proteinMaxG,
    fatG: fatG,
    carbsG: carbsG,
    sugarLimitG: sugarLimitG,
    fiberGoalG: fiberGoalG,
    saturatedFatLimitG: saturatedFatLimitG,
    saltLimitG: saltLimitG,
    bmrKcal: bmr.round(),
    tdeeKcal: tdee.round(),
    rationale: 'Strategia: ${strategy.label} — $rationaleCore; $proteinBasis. '
        'Baza obejmuje pracę zawodową i codzienny ruch, więc kroki nie liczą '
        'się drugi raz. Ponad nią dochodzi tylko sport dnia.',
    sync: profile.syncMetadata,
    calorieTargetLocked: profile.calorieTargetLocked,
  );
}

// ============================================================================
// Ocena postępu zależna od strategii
// ============================================================================

/// Ocena postępu — inne sygnały liczą się dla różnych strategii.
/// Rekompozycja NIE jest oceniana wyłącznie po masie ciała.
String assessStrategyProgress({
  required BodyCompositionStrategy strategy,
  double weightChangeKg = 0,
  double waistChangeCm = 0,
  double bodyFatChangePp = 0,
  double strengthChangePercent = 0,
  bool changesWithinErrorMargin = false,
}) {
  String signed(double value, String unit, {int decimals = 1}) =>
      '${value > 0 ? '+' : ''}${value.toStringAsFixed(decimals)} $unit';

  if (changesWithinErrorMargin) {
    return 'Zmiany mieszczą się w możliwym marginesie błędu pomiaru. '
        'Kontynuuj obserwację trendu.';
  }

  switch (strategy) {
    case BodyCompositionStrategy.recomposition:
      final waistDown = waistChangeCm < -0.2;
      final strengthUp = strengthChangePercent > 1;
      if (waistDown && strengthUp) {
        return 'Masa ciała zmieniła się niewiele, ale obwód talii spadł '
            '(${signed(waistChangeCm, 'cm')}), a wyniki siłowe wzrosły '
            '(${signed(strengthChangePercent, '%', decimals: 0)}). '
            'Może to wskazywać na udaną rekompozycję.';
      }
      if (waistDown || bodyFatChangePp < -0.3) {
        return 'Talia lub szacowany poziom tkanki tłuszczowej maleją przy '
            'stabilnej masie — kierunek zgodny z rekompozycją.';
      }
      return 'Obserwuj talię, zdjęcia porównawcze i wyniki siłowe — to one '
          'oceniają rekompozycję; masa ciała jest tu tylko parametrem '
          'pomocniczym.';
    case BodyCompositionStrategy.fatLoss:
      if (weightChangeKg < -0.2 && strengthChangePercent >= -2) {
        return 'Masa spada (${signed(weightChangeKg, 'kg')}) przy '
            'zachowanej sile — redukcja przebiega prawidłowo.';
      }
      if (weightChangeKg > 0.2) {
        return 'Średnia masa rośnie mimo strategii redukcji — sprawdź '
            'bilans energii z kilku tygodni.';
      }
      return 'Śledź średnią wagę, tempo spadku, talię i zachowanie siły.';
    case BodyCompositionStrategy.muscleGain:
      if (weightChangeKg > 0.1 && waistChangeCm <= 0.4) {
        return 'Masa rośnie (${signed(weightChangeKg, 'kg')}) przy '
            'kontrolowanej talii — budowa mięśni przebiega prawidłowo.';
      }
      if (waistChangeCm > 0.5) {
        return 'Talia rośnie szybko — rozważ zmniejszenie nadwyżki.';
      }
      return 'Śledź tempo wzrostu masy, siłę, objętość treningową i talię.';
    case BodyCompositionStrategy.maintenance ||
          BodyCompositionStrategy.automatic:
      if (weightChangeKg.abs() <= 0.3 && waistChangeCm.abs() <= 0.3) {
        return 'Masa i talia stabilne — utrzymanie działa.';
      }
      return 'Masa lub talia dryfują — obserwuj trend kilku tygodni.';
    case BodyCompositionStrategy.performance:
      return 'Oceniaj wydolność, regenerację i samopoczucie — masa jest tu '
          'parametrem pomocniczym.';
  }
}
