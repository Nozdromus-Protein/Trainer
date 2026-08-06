/// Strukturalna odpowiedź Trenera AI (czysty Dart).
///
/// Etap: „Karty ćwiczeń w rozmowie z Trenerem AI".
///
/// Do tej pory czat dostawał WYŁĄCZNIE tekst. Ta warstwa pozwala backendowi
/// dołożyć dane strukturalne (lista sugerowanych ćwiczeń, propozycja zestawu,
/// ostrzeżenia, pewność), a aplikacji — pokazać je jako interaktywne karty.
///
/// Kluczowa zasada: parser NIGDY nie wywraca czatu. Jeżeli backend nie
/// obsługuje struktury (albo zwróci śmieci), [TrainerAiStructuredReply.parse]
/// oddaje samą wiadomość tekstową i pustą listę sugestii — czat działa
/// dokładnie tak jak wcześniej.
library;

/// Ocena, jak dane ćwiczenie ma się do dzisiejszej regeneracji.
enum AiRecoveryCompatibility {
  good('good', 'Dobre na dzisiaj'),
  moderate('moderate', 'Możliwe przy niższej intensywności'),
  poor('poor', 'Niepolecane — partia się regeneruje'),
  unknown('unknown', 'Brak wystarczających danych');

  const AiRecoveryCompatibility(this.key, this.label);

  final String key;
  final String label;

  static AiRecoveryCompatibility fromKey(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return AiRecoveryCompatibility.unknown;
    for (final item in AiRecoveryCompatibility.values) {
      if (item.key == normalized || item.name == normalized) return item;
    }
    if (normalized.contains('dobr') || normalized.contains('ok')) {
      return AiRecoveryCompatibility.good;
    }
    if (normalized.contains('umiar') || normalized.contains('moder')) {
      return AiRecoveryCompatibility.moderate;
    }
    if (normalized.contains('niepolec') ||
        normalized.contains('unikaj') ||
        normalized.contains('avoid')) {
      return AiRecoveryCompatibility.poor;
    }
    return AiRecoveryCompatibility.unknown;
  }
}

/// Pojedyncze ćwiczenie zaproponowane przez AI.
///
/// KAŻDE pole poza [name] jest opcjonalne — karta musi się wyrenderować także
/// wtedy, gdy AI poda samą nazwę (spec: punkt 12).
class AiExerciseSuggestion {
  const AiExerciseSuggestion({
    required this.name,
    this.exerciseId = '',
    this.description = '',
    this.primaryMuscles = const <String>[],
    this.secondaryMuscles = const <String>[],
    this.equipment = '',
    this.difficulty = '',
    this.entryType = '',
    this.loadType = '',
    this.reasonRecommended = '',
    this.recoveryCompatibility = AiRecoveryCompatibility.unknown,
    this.recoveryNote = '',
    this.confidence = 0,
    this.alreadyInDatabase = false,
    this.imageUrl = '',
    this.suggestedSets = 0,
    this.suggestedReps = 0,
    this.suggestedDurationSec = 0,
    this.suggestedRestSeconds = 0,
  });

  final String name;

  /// Identyfikator ćwiczenia w bazie aplikacji (gdy AI je rozpoznało).
  final String exerciseId;
  final String description;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String equipment;
  final String difficulty;
  final String entryType;
  final String loadType;
  final String reasonRecommended;
  final AiRecoveryCompatibility recoveryCompatibility;
  final String recoveryNote;

  /// Pewność rekomendacji 0..1 (0 = AI nie podało).
  final double confidence;
  final bool alreadyInDatabase;
  final String imageUrl;

  final int suggestedSets;
  final int suggestedReps;
  final int suggestedDurationSec;
  final int suggestedRestSeconds;

  /// Stabilny identyfikator karty w obrębie wiadomości — pozwala zaznaczać
  /// karty i nie tworzyć duplikatów przy ponownym kliknięciu „Dodaj".
  String get cardKey =>
      exerciseId.trim().isNotEmpty ? exerciseId.trim() : _slug(name);

  List<String> get allMuscles => <String>[
        ...primaryMuscles,
        ...secondaryMuscles,
      ].where((m) => m.trim().isNotEmpty).toList();

  bool get hasAnyDetail =>
      description.trim().isNotEmpty ||
      primaryMuscles.isNotEmpty ||
      secondaryMuscles.isNotEmpty ||
      equipment.trim().isNotEmpty ||
      difficulty.trim().isNotEmpty ||
      reasonRecommended.trim().isNotEmpty;

  AiExerciseSuggestion copyWith({
    String? name,
    String? exerciseId,
    String? description,
    List<String>? primaryMuscles,
    List<String>? secondaryMuscles,
    String? equipment,
    String? difficulty,
    String? entryType,
    String? loadType,
    String? reasonRecommended,
    AiRecoveryCompatibility? recoveryCompatibility,
    String? recoveryNote,
    double? confidence,
    bool? alreadyInDatabase,
    String? imageUrl,
    int? suggestedSets,
    int? suggestedReps,
    int? suggestedDurationSec,
    int? suggestedRestSeconds,
  }) {
    return AiExerciseSuggestion(
      name: name ?? this.name,
      exerciseId: exerciseId ?? this.exerciseId,
      description: description ?? this.description,
      primaryMuscles: primaryMuscles ?? this.primaryMuscles,
      secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
      equipment: equipment ?? this.equipment,
      difficulty: difficulty ?? this.difficulty,
      entryType: entryType ?? this.entryType,
      loadType: loadType ?? this.loadType,
      reasonRecommended: reasonRecommended ?? this.reasonRecommended,
      recoveryCompatibility:
          recoveryCompatibility ?? this.recoveryCompatibility,
      recoveryNote: recoveryNote ?? this.recoveryNote,
      confidence: confidence ?? this.confidence,
      alreadyInDatabase: alreadyInDatabase ?? this.alreadyInDatabase,
      imageUrl: imageUrl ?? this.imageUrl,
      suggestedSets: suggestedSets ?? this.suggestedSets,
      suggestedReps: suggestedReps ?? this.suggestedReps,
      suggestedDurationSec: suggestedDurationSec ?? this.suggestedDurationSec,
      suggestedRestSeconds: suggestedRestSeconds ?? this.suggestedRestSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (exerciseId.isNotEmpty) 'exerciseId': exerciseId,
        if (description.isNotEmpty) 'description': description,
        if (primaryMuscles.isNotEmpty) 'primaryMuscles': primaryMuscles,
        if (secondaryMuscles.isNotEmpty) 'secondaryMuscles': secondaryMuscles,
        if (equipment.isNotEmpty) 'equipment': equipment,
        if (difficulty.isNotEmpty) 'difficulty': difficulty,
        if (entryType.isNotEmpty) 'entryType': entryType,
        if (loadType.isNotEmpty) 'loadType': loadType,
        if (reasonRecommended.isNotEmpty)
          'reasonRecommended': reasonRecommended,
        if (recoveryCompatibility != AiRecoveryCompatibility.unknown)
          'recoveryCompatibility': recoveryCompatibility.key,
        if (recoveryNote.isNotEmpty) 'recoveryNote': recoveryNote,
        if (confidence > 0) 'confidence': confidence,
        if (alreadyInDatabase) 'alreadyInDatabase': true,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (suggestedSets > 0) 'sets': suggestedSets,
        if (suggestedReps > 0) 'reps': suggestedReps,
        if (suggestedDurationSec > 0) 'durationSec': suggestedDurationSec,
        if (suggestedRestSeconds > 0) 'restSeconds': suggestedRestSeconds,
      };

  /// Parsuje sugestię z mapy. Zwraca `null`, gdy brakuje nawet nazwy —
  /// karta bez nazwy nie ma sensu i nie może wywrócić listy.
  static AiExerciseSuggestion? fromJson(Map<String, dynamic> json) {
    final name = _text(json['name'] ?? json['exercise'] ?? json['title']);
    if (name.isEmpty) return null;
    return AiExerciseSuggestion(
      name: name,
      exerciseId: _text(json['exerciseId'] ?? json['id']),
      description: _text(json['description'] ?? json['summary']),
      primaryMuscles: _stringList(
          json['primaryMuscles'] ?? json['primary_muscles'] ?? json['muscles']),
      secondaryMuscles: _stringList(
          json['secondaryMuscles'] ?? json['secondary_muscles']),
      equipment: _text(json['equipment']),
      difficulty: _text(json['difficulty'] ?? json['level']),
      entryType: _text(json['entryType'] ?? json['entry_type']),
      loadType: _text(json['loadType'] ?? json['load_type']),
      reasonRecommended:
          _text(json['reasonRecommended'] ?? json['reason'] ?? json['why']),
      recoveryCompatibility: AiRecoveryCompatibility.fromKey(
          json['recoveryCompatibility'] ?? json['recovery_compatibility']),
      recoveryNote: _text(json['recoveryNote'] ?? json['recovery_note']),
      confidence: _confidence(json['confidence']),
      alreadyInDatabase: json['alreadyInDatabase'] as bool? ??
          json['already_in_database'] as bool? ??
          false,
      imageUrl: _text(json['imageUrl'] ?? json['image']),
      suggestedSets: _int(json['sets'] ?? json['suggestedSets']),
      suggestedReps: _int(json['reps'] ?? json['suggestedReps']),
      suggestedDurationSec:
          _int(json['durationSec'] ?? json['duration_sec'] ?? json['seconds']),
      suggestedRestSeconds:
          _int(json['restSeconds'] ?? json['rest_seconds'] ?? json['rest']),
    );
  }
}

/// Propozycja całego zestawu zwrócona przez AI w rozmowie.
class AiSetSuggestion {
  const AiSetSuggestion({
    this.name = '',
    this.goal = '',
    this.days = const <AiSetSuggestionDay>[],
    this.note = '',
  });

  final String name;
  final String goal;
  final List<AiSetSuggestionDay> days;
  final String note;

  bool get isEmpty => days.isEmpty;

  /// Wszystkie ćwiczenia propozycji, w kolejności dni.
  List<AiExerciseSuggestion> get allExercises =>
      [for (final day in days) ...day.exercises];

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (goal.isNotEmpty) 'goal': goal,
        if (note.isNotEmpty) 'note': note,
        'days': days.map((day) => day.toJson()).toList(),
      };

  static AiSetSuggestion? fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final days = <AiSetSuggestionDay>[];
    if (rawDays is List) {
      for (final item in rawDays) {
        if (item is! Map) continue;
        final day =
            AiSetSuggestionDay.fromJson(Map<String, dynamic>.from(item));
        if (day != null) days.add(day);
      }
    }
    if (days.isEmpty) return null;
    return AiSetSuggestion(
      name: _text(json['name'] ?? json['title']),
      goal: _text(json['goal']),
      days: days,
      note: _text(json['note'] ?? json['description']),
    );
  }
}

/// Pojedynczy dzień proponowanego zestawu.
class AiSetSuggestionDay {
  const AiSetSuggestionDay({
    required this.title,
    this.weekday = 0,
    this.exercises = const <AiExerciseSuggestion>[],
  });

  final String title;
  final int weekday;
  final List<AiExerciseSuggestion> exercises;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (weekday > 0) 'weekday': weekday,
        'exercises': exercises.map((item) => item.toJson()).toList(),
      };

  static AiSetSuggestionDay? fromJson(Map<String, dynamic> json) {
    final title = _text(json['title'] ?? json['name']);
    final rawExercises = json['exercises'] ?? json['items'];
    final exercises = <AiExerciseSuggestion>[];
    if (rawExercises is List) {
      for (final item in rawExercises) {
        if (item is Map) {
          final parsed =
              AiExerciseSuggestion.fromJson(Map<String, dynamic>.from(item));
          if (parsed != null) exercises.add(parsed);
        } else if (item is String && item.trim().isNotEmpty) {
          exercises.add(AiExerciseSuggestion(name: item.trim()));
        }
      }
    }
    if (title.isEmpty && exercises.isEmpty) return null;
    return AiSetSuggestionDay(
      title: title.isEmpty ? 'Trening' : title,
      weekday: _int(json['weekday']),
      exercises: exercises,
    );
  }
}

/// Pełna odpowiedź Trenera AI: tekst + opcjonalne dane strukturalne.
class TrainerAiStructuredReply {
  const TrainerAiStructuredReply({
    required this.message,
    this.exerciseSuggestions = const <AiExerciseSuggestion>[],
    this.setSuggestion,
    this.warnings = const <String>[],
    this.reasoningSummary = '',
    this.confidence = 0,
    this.recommendations = const <String>[],
    this.planAnalysisPlanId = '',
    this.planAnalysisPlanName = '',
  });

  final String message;
  final List<AiExerciseSuggestion> exerciseSuggestions;
  final AiSetSuggestion? setSuggestion;
  final List<String> warnings;
  final String reasoningSummary;

  /// Pewność całej odpowiedzi 0..1 (0 = AI nie podało).
  final double confidence;
  final List<String> recommendations;

  /// Zestaw, o którego analizę poprosił użytkownik w rozmowie
  /// („Przeanalizuj mój zestaw Push"). Pole wypełnia APLIKACJA po rozpoznaniu
  /// intencji — nie backend. Puste = brak takiej prośby.
  ///
  /// Sama obecność identyfikatora niczego nie uruchamia: czat pokazuje
  /// wyłącznie przycisk otwierający pełną analizę (spec: żadnych zmian bez
  /// kliknięcia użytkownika).
  final String planAnalysisPlanId;
  final String planAnalysisPlanName;

  bool get hasStructuredData =>
      exerciseSuggestions.isNotEmpty ||
      setSuggestion != null ||
      warnings.isNotEmpty ||
      recommendations.isNotEmpty ||
      planAnalysisPlanId.trim().isNotEmpty ||
      reasoningSummary.trim().isNotEmpty;

  TrainerAiStructuredReply copyWith({
    String? message,
    List<AiExerciseSuggestion>? exerciseSuggestions,
    AiSetSuggestion? setSuggestion,
    List<String>? warnings,
    String? reasoningSummary,
    double? confidence,
    List<String>? recommendations,
    String? planAnalysisPlanId,
    String? planAnalysisPlanName,
  }) {
    return TrainerAiStructuredReply(
      message: message ?? this.message,
      exerciseSuggestions: exerciseSuggestions ?? this.exerciseSuggestions,
      setSuggestion: setSuggestion ?? this.setSuggestion,
      warnings: warnings ?? this.warnings,
      reasoningSummary: reasoningSummary ?? this.reasoningSummary,
      confidence: confidence ?? this.confidence,
      recommendations: recommendations ?? this.recommendations,
      planAnalysisPlanId: planAnalysisPlanId ?? this.planAnalysisPlanId,
      planAnalysisPlanName: planAnalysisPlanName ?? this.planAnalysisPlanName,
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        if (exerciseSuggestions.isNotEmpty)
          'exerciseSuggestions':
              exerciseSuggestions.map((item) => item.toJson()).toList(),
        if (setSuggestion != null) 'setSuggestion': setSuggestion!.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (reasoningSummary.isNotEmpty) 'reasoningSummary': reasoningSummary,
        if (confidence > 0) 'confidence': confidence,
        if (recommendations.isNotEmpty) 'recommendations': recommendations,
        if (planAnalysisPlanId.isNotEmpty)
          'planAnalysisPlanId': planAnalysisPlanId,
        if (planAnalysisPlanName.isNotEmpty)
          'planAnalysisPlanName': planAnalysisPlanName,
      };

  /// Odtwarza odpowiedź z historii czatu (zapisujemy tylko część strukturalną
  /// potrzebną do ponownego narysowania kart).
  static TrainerAiStructuredReply? fromJson(Map<String, dynamic> json) {
    final suggestions = <AiExerciseSuggestion>[];
    final raw = json['exerciseSuggestions'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final parsed =
            AiExerciseSuggestion.fromJson(Map<String, dynamic>.from(item));
        if (parsed != null) suggestions.add(parsed);
      }
    }
    final rawSet = json['setSuggestion'];
    final reply = TrainerAiStructuredReply(
      message: _text(json['message']),
      exerciseSuggestions: suggestions,
      setSuggestion: rawSet is Map
          ? AiSetSuggestion.fromJson(Map<String, dynamic>.from(rawSet))
          : null,
      warnings: _stringList(json['warnings']),
      reasoningSummary: _text(json['reasoningSummary']),
      confidence: _confidence(json['confidence']),
      recommendations: _stringList(json['recommendations']),
      planAnalysisPlanId: _text(json['planAnalysisPlanId']),
      planAnalysisPlanName: _text(json['planAnalysisPlanName']),
    );
    return reply.hasStructuredData ? reply : null;
  }

  /// Parsuje odpowiedź backendu. [fallbackMessage] to tekst wyliczony
  /// dotychczasową ścieżką — używany, gdy backend nie zwróci pola `message`.
  ///
  /// Metoda jest CELOWO tolerancyjna: nieznane kształty danych po prostu
  /// pomija, zamiast rzucać wyjątkiem, żeby czat nigdy nie „zniknął".
  static TrainerAiStructuredReply parse(
    Object? payload, {
    required String fallbackMessage,
  }) {
    if (payload is! Map) {
      return TrainerAiStructuredReply(message: fallbackMessage);
    }
    final json = Map<String, dynamic>.from(payload);
    // Backend może zapakować strukturę w podobiekt („structured"/„data").
    final nested = json['structured'] ?? json['data'] ?? json['result'];
    final source = nested is Map
        ? <String, dynamic>{...json, ...Map<String, dynamic>.from(nested)}
        : json;

    final suggestions = <AiExerciseSuggestion>[];
    final rawSuggestions = source['exerciseSuggestions'] ??
        source['exercise_suggestions'] ??
        source['exercises'] ??
        source['suggestedExercises'];
    if (rawSuggestions is List) {
      for (final item in rawSuggestions) {
        if (item is Map) {
          final parsed =
              AiExerciseSuggestion.fromJson(Map<String, dynamic>.from(item));
          if (parsed != null) suggestions.add(parsed);
        } else if (item is String && item.trim().isNotEmpty) {
          // Backend zwrócił samą listę nazw — to nadal użyteczna karta.
          suggestions.add(AiExerciseSuggestion(name: item.trim()));
        }
      }
    }

    AiSetSuggestion? setSuggestion;
    final rawSet = source['setSuggestion'] ??
        source['set_suggestion'] ??
        source['planSuggestion'];
    if (rawSet is Map) {
      setSuggestion = AiSetSuggestion.fromJson(Map<String, dynamic>.from(rawSet));
    }

    final message = _text(source['message'] ?? source['reply']);
    return TrainerAiStructuredReply(
      message: message.isEmpty ? fallbackMessage : message,
      exerciseSuggestions: _dedupe(suggestions),
      setSuggestion: setSuggestion,
      warnings: _stringList(source['warnings']),
      reasoningSummary:
          _text(source['reasoningSummary'] ?? source['reasoning_summary']),
      confidence: _confidence(source['confidence']),
      recommendations: _stringList(source['recommendations']),
    );
  }
}

/// Usuwa powtórzone karty (ta sama nazwa/id) zachowując kolejność AI.
List<AiExerciseSuggestion> _dedupe(List<AiExerciseSuggestion> items) {
  final seen = <String>{};
  final result = <AiExerciseSuggestion>[];
  for (final item in items) {
    if (seen.add(item.cardKey)) result.add(item);
  }
  return result;
}

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9ąćęłńóśźż]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String _text(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

/// Pewność w 0..1. Akceptuje też procenty (np. 88 → 0.88).
double _confidence(Object? value) {
  final raw = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '') ?? 0;
  if (raw <= 0) return 0;
  if (raw > 1) return (raw / 100).clamp(0.0, 1.0);
  return raw.clamp(0.0, 1.0);
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = _text(value);
  return text.isEmpty ? const <String>[] : <String>[text];
}
