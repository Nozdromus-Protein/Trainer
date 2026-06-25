import 'trainer_enums.dart';

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
    this.gifPath,
    this.videoPath,
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

  /// Animacja / GIF ćwiczenia. Asset albo URL. Ma najwyższy priorytet w podglądzie.
  final String? gifPath;

  /// Ścieżka wideo ćwiczenia. Na razie tylko struktura pod przyszłą obsługę odtwarzacza.
  final String? videoPath;

  final String source;

  String get primaryMuscle => muscles.isEmpty ? category : muscles.first;

  /// Ścieżka do animowanego multimediów (GIF) albo null.
  String? get animatedMediaPath => (gifPath != null && gifPath!.trim().isNotEmpty) ? gifPath!.trim() : null;

  /// Ścieżka do statycznego obrazu (lokalny albo zdalny) albo null.
  String? get staticMediaPath {
    if (imagePath != null && imagePath!.trim().isNotEmpty) return imagePath!.trim();
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) return imageUrl!.trim();
    return null;
  }

  /// Czy ćwiczenie ma jakiekolwiek multimedia (GIF, obraz lokalny, obraz zdalny).
  bool get hasMedia => animatedMediaPath != null || staticMediaPath != null;

  /// Czy ćwiczenie ma wideo (na przyszłość).
  bool get hasVideo => videoPath != null && videoPath!.trim().isNotEmpty;

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
    String? gifPath,
    String? videoPath,
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
      gifPath: gifPath ?? this.gifPath,
      videoPath: videoPath ?? this.videoPath,
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
        'gifPath': gifPath,
        'videoPath': videoPath,
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
        gifPath: _nullableText(json['gifPath']),
        videoPath: _nullableText(json['videoPath']),
        source: json['source']?.toString() ?? 'custom',
      );
}

String normalizeTrainingLevel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('zaaw')) return 'Zaawansowany';
  if (normalized.contains('śred') ||
      normalized.contains('sred') ||
      normalized.contains('inter') ||
      normalized.contains('mid')) {
    return 'Średniozaawansowany';
  }
  return 'Początkujący';
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
