import 'body_muscle.dart';
import 'exercise_entry_type.dart';
import 'exercise_media.dart';
import 'trainer_enums.dart';

export 'body_muscle.dart';
export 'exercise_entry_type.dart';
export 'exercise_media.dart';

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscles,
    required this.equipment,
    required this.level,
    required this.illustrationType,
    required this.description,
    required this.tips,
    required this.commonMistakes,
    required this.defaultSets,
    required this.defaultReps,
    required this.defaultDurationSec,
    required this.met,
    this.trainingGoals = const [],
    this.avoidWhen = const [],
    this.alternatives = const [],
    this.executionSteps = const [],
    this.breathing = '',
    this.tempo = '',
    this.easierVersion = '',
    this.harderVersion = '',
    this.imageUrl,
    this.imagePath,
    this.thumbnailPath,
    this.gifPath,
    this.animationAssetPath,
    this.videoPath,
    this.videoUrl,
    this.mediaItems = const [],
    this.muscleImpacts = const [],
    this.entryTypeKey = '',
    this.source = 'local',
  });

  final String id;
  final String name;
  final String category;
  final List<String> muscles;
  final String equipment;
  final String level;
  final String illustrationType;
  final String description;
  final List<String> tips;
  final List<String> commonMistakes;
  final int defaultSets;
  final int defaultReps;
  final int defaultDurationSec;
  final double met;
  final List<String> trainingGoals;
  final List<String> avoidWhen;
  final List<String> alternatives;
  final List<String> executionSteps;
  final String breathing;
  final String tempo;
  final String easierVersion;
  final String harderVersion;

  /// Zdalny obraz ćwiczenia (np. z bazy wger). Ładowany przez sieć.
  final String? imageUrl;

  /// Lokalny statyczny obraz ćwiczenia. Asset (np. `assets/exercises/squat.png`)
  /// albo ścieżka URL. Ma pierwszeństwo nad zdalnym [imageUrl] przy statycznym podglądzie.
  final String? imagePath;

  /// Miniatura ćwiczenia używana na listach/kafelkach. Asset albo URL.
  /// Gdy pusta, miniatura jest wyprowadzana z pozostałych multimediów.
  final String? thumbnailPath;

  /// Animacja / GIF ćwiczenia. Asset albo URL. Ma najwyższy priorytet w podglądzie.
  final String? gifPath;

  /// Spakowana animacja ćwiczenia (asset, np. GIF dołączony do aplikacji).
  /// Traktowana jak animowane medium, gdy brak [gifPath].
  final String? animationAssetPath;

  /// Ścieżka wideo ćwiczenia (plik lokalny albo asset). Pod obsługę odtwarzacza.
  final String? videoPath;

  /// Zdalny link do wideo (np. instruktaż). Pod obsługę odtwarzacza/linku.
  final String? videoUrl;

  /// Pełna lista multimediów ćwiczenia ([ExerciseMedia]).
  /// Opcjonalna — brak elementów oznacza powrót do pól [imagePath]/[gifPath]/...
  final List<ExerciseMedia> mediaItems;

  /// Jawnie przypisane partie mięśniowe (główne/pomocnicze/stabilizacja).
  /// Gdy puste, [effectiveMuscleImpacts] wyprowadza je z pola [muscles].
  final List<ExerciseMuscleImpact> muscleImpacts;

  /// Jawny typ wpisu danych serii (klucz [ExerciseEntryType.key]).
  /// Pusty → typ wyprowadzany z [kExerciseEntryTypeOverrides] albo heurystyki.
  final String entryTypeKey;

  final String source;

  /// Typ wpisu danych dla tego ćwiczenia — decyduje, jakie pola pokazuje
  /// panel wpisu serii (powtórzenia / ciężar / dodatkowy ciężar / czas / dystans).
  ExerciseEntryType get entryType {
    final explicit = ExerciseEntryType.fromKey(entryTypeKey);
    if (explicit != null) return explicit;
    final override = kExerciseEntryTypeOverrides[id];
    if (override != null) return override;
    return deriveEntryType(
      name: name,
      category: category,
      equipment: equipment,
      defaultDurationSec: defaultDurationSec,
      defaultReps: defaultReps,
    );
  }

  /// Wpływ na partie mięśniowe użyty do liczenia regeneracji.
  /// Jawne [muscleImpacts] mają pierwszeństwo; w przeciwnym razie wyprowadzane
  /// są z [muscles] (pierwsza = główna, kolejne = pomocnicze).
  List<ExerciseMuscleImpact> get effectiveMuscleImpacts {
    if (muscleImpacts.isNotEmpty) return muscleImpacts;
    final derived = <ExerciseMuscleImpact>[];
    final seen = <BodyMuscle>{};
    for (var i = 0; i < muscles.length; i++) {
      final muscle = BodyMuscle.fromText(muscles[i]);
      if (muscle == null || !seen.add(muscle)) continue;
      derived.add(ExerciseMuscleImpact(
        muscleGroup: muscle,
        role: i == 0 ? MuscleRole.primary : MuscleRole.secondary,
      ));
    }
    return derived;
  }

  /// Czy ćwiczenie ma jakiekolwiek (jawne lub wyprowadzone) przypisanie partii.
  bool get hasMuscleAssignment => effectiveMuscleImpacts.isNotEmpty;

  String get primaryMuscle => muscles.isEmpty ? category : muscles.first;

  /// Główne medium ćwiczenia: oznaczone [ExerciseMedia.isPrimary],
  /// a gdy żadne nie jest oznaczone — pierwsze z [mediaItems]. `null`, gdy lista pusta.
  ExerciseMedia? get primaryMedia {
    if (mediaItems.isEmpty) return null;
    for (final media in mediaItems) {
      if (media.isPrimary && media.hasContent) return media;
    }
    for (final media in mediaItems) {
      if (media.hasContent) return media;
    }
    return mediaItems.first;
  }

  ExerciseMedia? _firstMediaOfType(bool Function(MediaType) test) {
    for (final media in mediaItems) {
      if (test(media.type) && media.hasContent) return media;
    }
    return null;
  }

  static String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Ścieżka do animowanego medium (GIF) albo null.
  /// Priorytet: główne medium (jeśli animowane) > [gifPath] > [animationAssetPath]
  /// > pierwszy animowany element z [mediaItems].
  String? get animatedMediaPath {
    final primary = primaryMedia;
    if (primary != null && primary.type.isAnimated) {
      final path = primary.effectivePath;
      if (path != null) return path;
    }
    final gif = _clean(gifPath);
    if (gif != null) return gif;
    final asset = _clean(animationAssetPath);
    if (asset != null) return asset;
    return _firstMediaOfType((type) => type.isAnimated)?.effectivePath;
  }

  /// Ścieżka do statycznego obrazu (lokalny albo zdalny) albo null.
  /// Priorytet: główne medium (jeśli obraz) > [imagePath] > [imageUrl]
  /// > pierwszy obraz z [mediaItems].
  String? get staticMediaPath {
    final primary = primaryMedia;
    if (primary != null && primary.type.isImage) {
      final path = primary.effectivePath;
      if (path != null) return path;
    }
    final local = _clean(imagePath);
    if (local != null) return local;
    final remote = _clean(imageUrl);
    if (remote != null) return remote;
    return _firstMediaOfType((type) => type.isImage)?.effectivePath;
  }

  /// Ścieżka do miniatury używanej na listach. Najpierw jawna [thumbnailPath],
  /// potem miniatura/medium głównego elementu, na końcu obraz/animacja ćwiczenia.
  String? get thumbnailMediaPath {
    final thumb = _clean(thumbnailPath);
    if (thumb != null) return thumb;
    final primary = primaryMedia;
    if (primary != null) {
      final primaryThumb = primary.thumbnail;
      if (primaryThumb != null) return primaryThumb;
    }
    return staticMediaPath ?? animatedMediaPath;
  }

  /// Ścieżka/URL wideo ćwiczenia. Priorytet: [videoPath] (lokalny) > [videoUrl]
  /// > pierwsze wideo/link z [mediaItems].
  String? get videoMediaPath {
    final local = _clean(videoPath);
    if (local != null) return local;
    final remote = _clean(videoUrl);
    if (remote != null) return remote;
    return _firstMediaOfType((type) => type.isVideo)?.effectivePath;
  }

  /// Czy ćwiczenie ma jakiekolwiek multimedia (GIF, obraz lokalny/zdalny, lista mediów).
  bool get hasMedia => animatedMediaPath != null || staticMediaPath != null;

  /// Czy ćwiczenie ma wideo (lokalne, zdalne albo w [mediaItems]).
  bool get hasVideo => videoMediaPath != null;

  List<String> get supportingMuscles =>
      muscles.length <= 1 ? const [] : muscles.skip(1).toList();

  List<MuscleGroup> get muscleGroups {
    final groups = muscles.map(MuscleGroup.fromText).toSet();
    return groups.isEmpty ? const [MuscleGroup.other] : groups.toList();
  }

  Set<EquipmentType> get equipmentTypes => EquipmentType.fromText(equipment);

  Set<TrainingGoal> get typedTrainingGoals => trainingGoals
      .map(TrainingGoal.fromText)
      .whereType<TrainingGoal>()
      .toSet();

  Exercise copyWith({
    String? id,
    String? name,
    String? category,
    List<String>? muscles,
    String? equipment,
    String? level,
    String? illustrationType,
    String? description,
    List<String>? tips,
    List<String>? commonMistakes,
    int? defaultSets,
    int? defaultReps,
    int? defaultDurationSec,
    double? met,
    List<String>? trainingGoals,
    List<String>? avoidWhen,
    List<String>? alternatives,
    List<String>? executionSteps,
    String? breathing,
    String? tempo,
    String? easierVersion,
    String? harderVersion,
    String? imageUrl,
    String? imagePath,
    String? thumbnailPath,
    String? gifPath,
    String? animationAssetPath,
    String? videoPath,
    String? videoUrl,
    List<ExerciseMedia>? mediaItems,
    List<ExerciseMuscleImpact>? muscleImpacts,
    String? entryTypeKey,
    String? source,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      muscles: muscles ?? this.muscles,
      equipment: equipment ?? this.equipment,
      level: normalizeTrainingLevel(level ?? this.level),
      illustrationType: illustrationType ?? this.illustrationType,
      description: description ?? this.description,
      tips: tips ?? this.tips,
      commonMistakes: commonMistakes ?? this.commonMistakes,
      defaultSets: defaultSets ?? this.defaultSets,
      defaultReps: defaultReps ?? this.defaultReps,
      defaultDurationSec: defaultDurationSec ?? this.defaultDurationSec,
      met: met ?? this.met,
      trainingGoals: trainingGoals ?? this.trainingGoals,
      avoidWhen: avoidWhen ?? this.avoidWhen,
      alternatives: alternatives ?? this.alternatives,
      executionSteps: executionSteps ?? this.executionSteps,
      breathing: breathing ?? this.breathing,
      tempo: tempo ?? this.tempo,
      easierVersion: easierVersion ?? this.easierVersion,
      harderVersion: harderVersion ?? this.harderVersion,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePath: imagePath ?? this.imagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      gifPath: gifPath ?? this.gifPath,
      animationAssetPath: animationAssetPath ?? this.animationAssetPath,
      videoPath: videoPath ?? this.videoPath,
      videoUrl: videoUrl ?? this.videoUrl,
      mediaItems: mediaItems ?? this.mediaItems,
      muscleImpacts: muscleImpacts ?? this.muscleImpacts,
      entryTypeKey: entryTypeKey ?? this.entryTypeKey,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'muscles': muscles,
        'equipment': equipment,
        'level': level,
        'illustrationType': illustrationType,
        'description': description,
        'tips': tips,
        'commonMistakes': commonMistakes,
        'defaultSets': defaultSets,
        'defaultReps': defaultReps,
        'defaultDurationSec': defaultDurationSec,
        'met': met,
        'trainingGoals': trainingGoals,
        'avoidWhen': avoidWhen,
        'alternatives': alternatives,
        'executionSteps': executionSteps,
        'breathing': breathing,
        'tempo': tempo,
        'easierVersion': easierVersion,
        'harderVersion': harderVersion,
        'imageUrl': imageUrl,
        'imagePath': imagePath,
        'thumbnailPath': thumbnailPath,
        'gifPath': gifPath,
        'animationAssetPath': animationAssetPath,
        'videoPath': videoPath,
        'videoUrl': videoUrl,
        'mediaItems': mediaItems.map((media) => media.toJson()).toList(),
        'muscleImpacts': muscleImpacts.map((impact) => impact.toJson()).toList(),
        'entryTypeKey': entryTypeKey,
        'source': source,
      };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id']?.toString() ?? _newId('exercise'),
        name: json['name']?.toString() ?? 'Ćwiczenie',
        category: json['category']?.toString() ?? 'Inne',
        muscles: ((json['muscles'] as List?) ?? const ['całe ciało'])
            .map((value) => value.toString())
            .toList(),
        equipment: json['equipment']?.toString() ?? 'brak danych',
        level: normalizeTrainingLevel(
          json['level']?.toString() ?? 'Początkujący',
        ),
        illustrationType: json['illustrationType']?.toString() ?? 'generic',
        description: json['description']?.toString() ?? '',
        tips: ((json['tips'] as List?) ?? const <String>[])
            .map((value) => value.toString())
            .toList(),
        commonMistakes: ((json['commonMistakes'] as List?) ?? const <String>[])
            .map((value) => value.toString())
            .toList(),
        defaultSets: (json['defaultSets'] as num?)?.toInt() ?? 3,
        defaultReps: (json['defaultReps'] as num?)?.toInt() ?? 10,
        defaultDurationSec: (json['defaultDurationSec'] as num?)?.toInt() ?? 0,
        met: (json['met'] as num?)?.toDouble() ?? 4.5,
        trainingGoals: _stringList(json['trainingGoals']),
        avoidWhen: _stringList(json['avoidWhen']),
        alternatives: _stringList(json['alternatives']),
        executionSteps: _stringList(json['executionSteps']),
        breathing: json['breathing']?.toString() ?? '',
        tempo: json['tempo']?.toString() ?? '',
        easierVersion: json['easierVersion']?.toString() ?? '',
        harderVersion: json['harderVersion']?.toString() ?? '',
        imageUrl: _nullableText(json['imageUrl']),
        imagePath: _nullableText(json['imagePath']),
        thumbnailPath: _nullableText(json['thumbnailPath']),
        gifPath: _nullableText(json['gifPath']),
        animationAssetPath: _nullableText(json['animationAssetPath']),
        videoPath: _nullableText(json['videoPath']),
        videoUrl: _nullableText(json['videoUrl']),
        mediaItems: _mediaList(json['mediaItems']),
        muscleImpacts: _muscleImpactList(json['muscleImpacts']),
        entryTypeKey: json['entryTypeKey']?.toString() ?? '',
        source: json['source']?.toString() ?? 'custom',
      );
}

List<ExerciseMedia> _mediaList(Object? value) {
  if (value is! List) return const [];
  final result = <ExerciseMedia>[];
  for (final item in value) {
    if (item is Map) {
      result.add(ExerciseMedia.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return result;
}

List<ExerciseMuscleImpact> _muscleImpactList(Object? value) {
  if (value is! List) return const [];
  final result = <ExerciseMuscleImpact>[];
  for (final item in value) {
    if (item is Map) {
      final impact = ExerciseMuscleImpact.fromJson(Map<String, dynamic>.from(item));
      if (impact != null) result.add(impact);
    }
  }
  return result;
}

String normalizeTrainingLevel(String value) {
  final normalized = value.trim().toLowerCase();
  // „śred" MUSI być sprawdzone przed „zaaw": słowo „średnioza(zaaw)ansowany"
  // zawiera podciąg „zaaw", więc sprawdzenie zaawansowanego jako pierwsze
  // błędnie klasyfikowało średniozaawansowanego jako zaawansowanego.
  if (normalized.contains('śred') ||
      normalized.contains('sred') ||
      normalized.contains('inter') ||
      normalized.contains('mid')) {
    return 'Średniozaawansowany';
  }
  if (normalized.contains('zaaw')) return 'Zaawansowany';
  return 'Początkujący';
}

/// Ranga poziomu do porównań: początkujący 0, średniozaawansowany 1,
/// zaawansowany 2. Pozwala pytać „czy to ćwiczenie jest ponad mój poziom".
int trainingLevelRank(String value) {
  switch (normalizeTrainingLevel(value)) {
    case 'Zaawansowany':
      return 2;
    case 'Średniozaawansowany':
      return 1;
    default:
      return 0;
  }
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _newId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
