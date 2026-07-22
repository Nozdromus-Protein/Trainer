/// Warianty programów 30-dniowych + multimedia programu.
///
/// Czysty Dart. Zasady bezpieczeństwa (sekcja 38–39 specyfikacji):
///  - wariant NIE jest kopią programu — to zestaw modyfikatorów nakładanych
///    na wspólny szablon (dni bazowe),
///  - zastosowanie wariantu NIGDY nie usuwa ukończonych dni ani nie zmienia
///    dni wcześniejszych niż wskazany dzień startu,
///  - identyfikator programu pozostaje ten sam,
///  - każda zmiana wariantu zostawia wpis w historii,
///  - obraz programu ([ProgramMedia]) jest OSOBNYM polem — nie dotyka
///    obrazów ćwiczeń; stara okładka żyje do zatwierdzenia nowej.
library;

import 'workout_plan.dart';

// ============================================================================
// Enumy wariantu
// ============================================================================

enum ProgramDifficulty {
  beginner('beginner', 'Początkujący'),
  intermediate('intermediate', 'Średniozaawansowany'),
  advanced('advanced', 'Zaawansowany');

  const ProgramDifficulty(this.id, this.label);

  final String id;
  final String label;

  static ProgramDifficulty fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final value in ProgramDifficulty.values) {
      if (value.id == normalized) return value;
    }
    return ProgramDifficulty.intermediate;
  }

  static ProgramDifficulty fromLevelLabel(String level) {
    final v = level.trim().toLowerCase();
    if (v.contains('zaaw') && !v.contains('śred') && !v.contains('sred')) {
      return ProgramDifficulty.advanced;
    }
    if (v.contains('pocz')) return ProgramDifficulty.beginner;
    return ProgramDifficulty.intermediate;
  }
}

enum ProgramEnvironment {
  anywhere('anywhere', 'Dowolne'),
  home('home', 'Dom'),
  gym('gym', 'Siłownia'),
  noEquipment('no_equipment', 'Bez sprzętu');

  const ProgramEnvironment(this.id, this.label);

  final String id;
  final String label;

  static ProgramEnvironment fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final value in ProgramEnvironment.values) {
      if (value.id == normalized) return value;
    }
    return ProgramEnvironment.anywhere;
  }
}

/// Dopasowanie wariantu do aktualnej strategii składu ciała.
enum ProgramGoalAdaptation {
  standard('standard', 'Standardowy'),
  short('short', 'Krótki'),
  intensive('intensive', 'Intensywny'),
  recomposition('recomposition', 'Pod rekompozycję'),
  fatLoss('fat_loss', 'Pod redukcję'),
  muscleGain('muscle_gain', 'Pod budowę mięśni'),
  custom('custom', 'Niestandardowy (AI)');

  const ProgramGoalAdaptation(this.id, this.label);

  final String id;
  final String label;

  static ProgramGoalAdaptation fromId(String? id) {
    final normalized = id?.trim() ?? '';
    for (final value in ProgramGoalAdaptation.values) {
      if (value.id == normalized) return value;
    }
    return ProgramGoalAdaptation.standard;
  }
}

// ============================================================================
// Multimedia programu
// ============================================================================

/// Obraz/okładka programu — osobny model, analogiczny do multimediów
/// ćwiczenia, ale NIE nadpisujący obrazów poszczególnych ćwiczeń.
class ProgramMedia {
  const ProgramMedia({
    this.imageUrl,
    this.localPath,
    this.pendingLocalPath,
    this.generatedPrompt,
    this.generationProvider,
    this.generatedAt,
    this.isAiGenerated = false,
  });

  final String? imageUrl;
  final String? localPath;

  /// Nowa okładka czekająca na zatwierdzenie — stara ([localPath]/[imageUrl])
  /// pozostaje aktywna do czasu potwierdzenia.
  final String? pendingLocalPath;
  final String? generatedPrompt;
  final String? generationProvider;
  final DateTime? generatedAt;
  final bool isAiGenerated;

  /// Aktywna ścieżka okładki (lokalna ma pierwszeństwo).
  String? get effectivePath {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) return local;
    final remote = imageUrl?.trim();
    if (remote != null && remote.isNotEmpty) return remote;
    return null;
  }

  bool get hasCover => effectivePath != null;
  bool get hasPending => (pendingLocalPath?.trim() ?? '').isNotEmpty;

  /// Zatwierdza oczekującą okładkę (dopiero teraz stara jest zastępowana).
  ProgramMedia approvePending() {
    if (!hasPending) return this;
    return ProgramMedia(
      imageUrl: null,
      localPath: pendingLocalPath,
      pendingLocalPath: null,
      generatedPrompt: generatedPrompt,
      generationProvider: generationProvider,
      generatedAt: generatedAt,
      isAiGenerated: isAiGenerated,
    );
  }

  /// Odrzuca oczekującą okładkę — aktywna zostaje bez zmian.
  ProgramMedia rejectPending() {
    if (!hasPending) return this;
    return copyWith(clearPending: true);
  }

  ProgramMedia copyWith({
    String? imageUrl,
    String? localPath,
    String? pendingLocalPath,
    String? generatedPrompt,
    String? generationProvider,
    DateTime? generatedAt,
    bool? isAiGenerated,
    bool clearPending = false,
    bool clearCover = false,
  }) {
    return ProgramMedia(
      imageUrl: clearCover ? null : (imageUrl ?? this.imageUrl),
      localPath: clearCover ? null : (localPath ?? this.localPath),
      pendingLocalPath:
          clearPending ? null : (pendingLocalPath ?? this.pendingLocalPath),
      generatedPrompt: generatedPrompt ?? this.generatedPrompt,
      generationProvider: generationProvider ?? this.generationProvider,
      generatedAt: generatedAt ?? this.generatedAt,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
    );
  }

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'localPath': localPath,
        'pendingLocalPath': pendingLocalPath,
        'generatedPrompt': generatedPrompt,
        'generationProvider': generationProvider,
        'generatedAt': generatedAt?.toIso8601String(),
        'isAiGenerated': isAiGenerated,
      };

  factory ProgramMedia.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final t = value?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return ProgramMedia(
      imageUrl: text(json['imageUrl']),
      localPath: text(json['localPath']),
      pendingLocalPath: text(json['pendingLocalPath']),
      generatedPrompt: text(json['generatedPrompt']),
      generationProvider: text(json['generationProvider']),
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      isAiGenerated: json['isAiGenerated'] == true,
    );
  }
}

// ============================================================================
// Wariant programu
// ============================================================================

/// Wariant programu 30-dniowego. Bazą jest wspólny szablon (dni programu);
/// wariant przechowuje RÓŻNICE (modyfikatory), a pełne dni tylko wtedy,
/// gdy wygenerowało je AI ([explicitDays]).
class ProgramVariant {
  const ProgramVariant({
    required this.id,
    required this.programId,
    required this.name,
    required this.difficulty,
    this.environment = ProgramEnvironment.anywhere,
    this.goalAdaptation = ProgramGoalAdaptation.standard,
    this.description = '',
    this.setsDelta = 0,
    this.repsDelta = 0,
    this.restDeltaSeconds = 0,
    this.durationDeltaSec = 0,
    this.maxExercisesPerDay = 0,
    this.extraCardioShare = 0,
    this.explicitDays = const [],
    this.isAiGenerated = false,
    this.createdAt,
  });

  final String id;
  final String programId;
  final String name;
  final ProgramDifficulty difficulty;
  final ProgramEnvironment environment;
  final ProgramGoalAdaptation goalAdaptation;
  final String description;

  /// Modyfikatory nakładane na dni bazowe (tylko dni treningowe od dnia
  /// zastosowania wariantu).
  final int setsDelta;
  final int repsDelta;
  final int restDeltaSeconds;
  final int durationDeltaSec;

  /// 0 = bez limitu; >0 = skróć dzień do N pierwszych pozycji (wariant krótki).
  final int maxExercisesPerDay;

  /// Informacyjny udział cardio (0–1) — używany w opisie różnic.
  final double extraCardioShare;

  /// Pełne dni wygenerowane przez AI (puste = wariant modyfikatorowy).
  final List<WorkoutDay> explicitDays;

  final bool isAiGenerated;
  final DateTime? createdAt;

  bool get isModifierBased => explicitDays.isEmpty;

  /// Czytelne podsumowanie różnic względem szablonu (do podglądu).
  List<String> get differenceSummary => [
        if (setsDelta != 0)
          'Serie: ${setsDelta > 0 ? '+' : ''}$setsDelta na ćwiczenie',
        if (repsDelta != 0)
          'Powtórzenia: ${repsDelta > 0 ? '+' : ''}$repsDelta',
        if (restDeltaSeconds != 0)
          'Przerwy: ${restDeltaSeconds > 0 ? '+' : ''}$restDeltaSeconds s',
        if (durationDeltaSec != 0)
          'Czas ćwiczeń czasowych: '
              '${durationDeltaSec > 0 ? '+' : ''}$durationDeltaSec s',
        if (maxExercisesPerDay > 0)
          'Maks. $maxExercisesPerDay ćwiczeń dziennie (wariant krótszy)',
        if (environment == ProgramEnvironment.noEquipment)
          'Tylko ćwiczenia bez sprzętu',
        if (explicitDays.isNotEmpty)
          'Pełny rozkład dni wygenerowany przez AI (${explicitDays.length} dni)',
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'programId': programId,
        'name': name,
        'difficulty': difficulty.id,
        'environment': environment.id,
        'goalAdaptation': goalAdaptation.id,
        'description': description,
        'setsDelta': setsDelta,
        'repsDelta': repsDelta,
        'restDeltaSeconds': restDeltaSeconds,
        'durationDeltaSec': durationDeltaSec,
        'maxExercisesPerDay': maxExercisesPerDay,
        'extraCardioShare': extraCardioShare,
        'explicitDays': [for (final day in explicitDays) day.toJson()],
        'isAiGenerated': isAiGenerated,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory ProgramVariant.fromJson(Map<String, dynamic> json) => ProgramVariant(
        id: json['id']?.toString() ??
            'variant_${DateTime.now().microsecondsSinceEpoch}',
        programId: json['programId']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Wariant',
        difficulty: ProgramDifficulty.fromId(json['difficulty']?.toString()),
        environment: ProgramEnvironment.fromId(json['environment']?.toString()),
        goalAdaptation:
            ProgramGoalAdaptation.fromId(json['goalAdaptation']?.toString()),
        description: json['description']?.toString() ?? '',
        setsDelta: (json['setsDelta'] as num?)?.toInt() ?? 0,
        repsDelta: (json['repsDelta'] as num?)?.toInt() ?? 0,
        restDeltaSeconds: (json['restDeltaSeconds'] as num?)?.toInt() ?? 0,
        durationDeltaSec: (json['durationDeltaSec'] as num?)?.toInt() ?? 0,
        maxExercisesPerDay: (json['maxExercisesPerDay'] as num?)?.toInt() ?? 0,
        extraCardioShare:
            (json['extraCardioShare'] as num?)?.toDouble() ?? 0,
        explicitDays: [
          for (final raw in (json['explicitDays'] as List? ?? const []))
            if (raw is Map) WorkoutDay.fromJson(Map<String, dynamic>.from(raw)),
        ],
        isAiGenerated: json['isAiGenerated'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

/// Wpis historii zmiany wariantu — moment zmiany jest oznaczony w programie,
/// a ukończone dni nie są przeliczane wstecz.
class ProgramVariantChange {
  const ProgramVariantChange({
    required this.variantId,
    required this.variantName,
    required this.fromDayIndex,
    required this.date,
  });

  final String variantId;
  final String variantName;

  /// Pierwszy dzień (indeks), od którego obowiązuje nowy wariant.
  final int fromDayIndex;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'variantName': variantName,
        'fromDayIndex': fromDayIndex,
        'date': date.toIso8601String(),
      };

  factory ProgramVariantChange.fromJson(Map<String, dynamic> json) =>
      ProgramVariantChange(
        variantId: json['variantId']?.toString() ?? '',
        variantName: json['variantName']?.toString() ?? '',
        fromDayIndex: (json['fromDayIndex'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse(json['date']?.toString() ?? '') ??
            DateTime.now(),
      );
}

// ============================================================================
// Nakładanie wariantu na plan
// ============================================================================

/// Nakłada wariant na plan OD [fromDayIndex] (włącznie).
///
/// Gwarancje ochrony postępu:
///  - `plan.id` pozostaje bez zmian (żadnego nowego identyfikatora),
///  - `completedDays` pozostają nietknięte,
///  - dni o indeksie < [fromDayIndex] pozostają bajt w bajt takie same,
///  - liczba dni programu się nie zmienia (wariant AI o innej liczbie dni
///    modyfikuje tylko wspólny zakres).
WorkoutPlan applyProgramVariant(
  WorkoutPlan plan,
  ProgramVariant variant, {
  int fromDayIndex = 0,
}) {
  final start = fromDayIndex.clamp(0, plan.days.length);
  final days = <WorkoutDay>[];
  for (var index = 0; index < plan.days.length; index++) {
    final day = plan.days[index];
    if (index < start) {
      days.add(day); // dni wcześniejsze — bez zmian
      continue;
    }
    if (!variant.isModifierBased && index < variant.explicitDays.length) {
      days.add(variant.explicitDays[index]);
      continue;
    }
    days.add(_applyModifiersToDay(day, variant));
  }
  return plan.copyWith(
    days: days,
    level: variant.difficulty.label,
    // completedDays celowo NIE są przekazywane — copyWith zachowa istniejące.
  );
}

WorkoutDay _applyModifiersToDay(WorkoutDay day, ProgramVariant variant) {
  var items = day.items;
  if (variant.maxExercisesPerDay > 0 &&
      items.length > variant.maxExercisesPerDay) {
    items = items.take(variant.maxExercisesPerDay).toList();
  }
  final adjusted = <PlanItem>[
    for (final item in items)
      item.copyWith(
        sets: (item.sets + variant.setsDelta).clamp(1, 10),
        reps: item.reps > 0
            ? (item.reps + variant.repsDelta).clamp(3, 40)
            : item.reps,
        durationSec: item.durationSec > 0
            ? (item.durationSec + variant.durationDeltaSec).clamp(10, 3600)
            : item.durationSec,
        restSeconds:
            (item.restSeconds + variant.restDeltaSeconds).clamp(5, 600),
      ),
  ];
  return day.copyWith(items: adjusted);
}

// ============================================================================
// Domyślne warianty (wspólny szablon + różnice)
// ============================================================================

/// Standardowa lista wariantów dostępna dla każdego programu 30-dniowego.
/// Warianty są modyfikatorowe — korzystają ze wspólnego szablonu programu.
List<ProgramVariant> defaultVariantsForProgram(String programId) {
  ProgramVariant variant(
    String suffix,
    String name, {
    required ProgramDifficulty difficulty,
    ProgramEnvironment environment = ProgramEnvironment.anywhere,
    ProgramGoalAdaptation adaptation = ProgramGoalAdaptation.standard,
    String description = '',
    int setsDelta = 0,
    int repsDelta = 0,
    int restDelta = 0,
    int durationDelta = 0,
    int maxExercises = 0,
  }) {
    return ProgramVariant(
      id: '${programId}_variant_$suffix',
      programId: programId,
      name: name,
      difficulty: difficulty,
      environment: environment,
      goalAdaptation: adaptation,
      description: description,
      setsDelta: setsDelta,
      repsDelta: repsDelta,
      restDeltaSeconds: restDelta,
      durationDeltaSec: durationDelta,
      maxExercisesPerDay: maxExercises,
    );
  }

  return [
    variant(
      'beginner',
      'Początkujący',
      difficulty: ProgramDifficulty.beginner,
      description: 'Mniej serii, dłuższe przerwy, łagodniejsza progresja.',
      setsDelta: -1,
      repsDelta: -2,
      restDelta: 20,
      durationDelta: -5,
    ),
    variant(
      'standard',
      'Standardowy',
      difficulty: ProgramDifficulty.intermediate,
      description: 'Wariant bazowy programu bez modyfikacji.',
    ),
    variant(
      'advanced',
      'Zaawansowany',
      difficulty: ProgramDifficulty.advanced,
      description: 'Więcej serii i powtórzeń, krótsze przerwy.',
      setsDelta: 1,
      repsDelta: 2,
      restDelta: -10,
      durationDelta: 10,
    ),
    variant(
      'short',
      'Krótki (mało czasu)',
      difficulty: ProgramDifficulty.intermediate,
      adaptation: ProgramGoalAdaptation.short,
      description: 'Skrócone dni — najważniejsze ćwiczenia, mniej objętości.',
      maxExercises: 6,
      restDelta: -5,
    ),
    variant(
      'intensive',
      'Intensywny',
      difficulty: ProgramDifficulty.advanced,
      adaptation: ProgramGoalAdaptation.intensive,
      description: 'Wyższa objętość i krótsze przerwy — wymaga dobrej '
          'regeneracji.',
      setsDelta: 1,
      restDelta: -15,
      durationDelta: 8,
    ),
    variant(
      'recomposition',
      'Pod rekompozycję',
      difficulty: ProgramDifficulty.intermediate,
      adaptation: ProgramGoalAdaptation.recomposition,
      description: 'Utrzymana objętość siłowa (ochrona mięśni) przy pełnej '
          'kontroli przerw.',
      repsDelta: 1,
    ),
    variant(
      'fat_loss',
      'Pod redukcję',
      difficulty: ProgramDifficulty.intermediate,
      adaptation: ProgramGoalAdaptation.fatLoss,
      description: 'Trening siłowy zostaje pełny (redukcję robi bilans '
          'energii), delikatnie krótsze przerwy.',
      restDelta: -10,
    ),
    variant(
      'muscle_gain',
      'Pod budowę mięśni',
      difficulty: ProgramDifficulty.intermediate,
      adaptation: ProgramGoalAdaptation.muscleGain,
      description: 'Dodatkowa seria na ćwiczenie i pełne przerwy.',
      setsDelta: 1,
      restDelta: 10,
    ),
  ];
}

// ============================================================================
// Walidacja wariantu (w tym wygenerowanego przez AI)
// ============================================================================

/// Waliduje wariant przed zapisaniem. Zwraca listę problemów (pusta = OK).
List<String> validateProgramVariant(
  ProgramVariant variant, {
  required bool Function(String exerciseId) exerciseExists,
  int maxSetsPerItem = 10,
  int minRestSeconds = 5,
}) {
  final problems = <String>[];
  if (variant.programId.trim().isEmpty) {
    problems.add('Wariant nie wskazuje programu.');
  }
  if (variant.name.trim().isEmpty) {
    problems.add('Wariant nie ma nazwy.');
  }
  if (variant.isModifierBased) return problems;

  var trainingDays = 0;
  var restDays = 0;
  String? previousMainMuscleKey;
  for (var index = 0; index < variant.explicitDays.length; index++) {
    final day = variant.explicitDays[index];
    if (day.items.isEmpty) {
      restDays += 1;
      previousMainMuscleKey = null;
      continue;
    }
    trainingDays += 1;
    final ids = <String>{};
    for (final item in day.items) {
      if (item.exerciseId.trim().isEmpty || !exerciseExists(item.exerciseId)) {
        problems.add(
          'Dzień ${index + 1}: nieistniejące ćwiczenie „${item.exerciseId}".',
        );
      }
      if (!ids.add(item.exerciseId)) {
        problems.add(
          'Dzień ${index + 1}: powtórzone ćwiczenie „${item.exerciseId}" '
              'bez uzasadnienia.',
        );
      }
      if (item.sets > maxSetsPerItem || item.sets < 1) {
        problems.add(
          'Dzień ${index + 1}: nierealna liczba serii (${item.sets}).',
        );
      }
      if (item.restSeconds < minRestSeconds) {
        problems.add('Dzień ${index + 1}: przerwy krótsze niż '
            '$minRestSeconds s.');
      }
    }
    // Przeciążenie tej samej partii dzień po dniu — heurystyka po tytule dnia
    // (numer dnia jest pomijany: „Dzień 3 · Plecy" i „Dzień 4 · Plecy" kolidują).
    final muscleKey = day.title
        .toLowerCase()
        .replaceAll(RegExp(r'dzień\s*\d+\s*[·:—-]*\s*'), '')
        .trim();
    if (previousMainMuscleKey != null &&
        muscleKey.isNotEmpty &&
        muscleKey == previousMainMuscleKey) {
      problems.add(
        'Dni $index i ${index + 1} obciążają tę samą partię dzień po dniu.',
      );
    }
    previousMainMuscleKey = muscleKey;
  }
  if (variant.explicitDays.isNotEmpty && trainingDays == 0) {
    problems.add('Wariant nie zawiera żadnego dnia treningowego.');
  }
  if (variant.explicitDays.length >= 7 && restDays == 0) {
    problems.add('Wariant nie zachowuje dni regeneracyjnych.');
  }
  return problems;
}

// ============================================================================
// Prompt okładki programu
// ============================================================================

/// Buduje prompt do wygenerowania okładki programu w stylu aplikacji.
/// Korzysta z danych programu i centralnego profilu celu.
String buildProgramCoverPrompt({
  required String programName,
  String physiqueLabel = '',
  String strategyLabel = '',
  String trainingFocusLabel = '',
  String difficultyLabel = '',
  List<String> mainMuscles = const [],
  List<String> equipment = const [],
  String environmentLabel = '',
}) {
  final muscles = mainMuscles.take(4).join(', ');
  final gear = equipment.take(4).join(', ');
  final details = [
    if (muscles.isNotEmpty) 'priority muscle groups: $muscles',
    if (trainingFocusLabel.isNotEmpty) 'training style: $trainingFocusLabel',
    if (strategyLabel.isNotEmpty) 'current phase: $strategyLabel',
    if (physiqueLabel.isNotEmpty) 'target physique: $physiqueLabel',
    if (difficultyLabel.isNotEmpty) 'level: $difficultyLabel',
    if (gear.isNotEmpty) 'equipment: $gear',
    if (environmentLabel.isNotEmpty) 'environment: $environmentLabel',
  ].join('; ');
  return 'Premium fitness program cover illustration for a training program '
      '"$programName". $details. Dynamic, technical athletic silhouette in '
      'motion, modern flat vector style, dark graphite background '
      '(#0D1117), mint green accent lighting (#24D6A3), subtle gradients, '
      'no text, no watermark, no logos — clean tile-ready composition.';
}
