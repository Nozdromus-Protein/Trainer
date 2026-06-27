/// Etap 26 (commit "etap 21 multimedia modele danych") — modele danych multimediów ćwiczeń.
///
/// Plik definiuje:
/// * [MediaType] — typ pojedynczego medium ćwiczenia,
/// * [ExerciseMedia] — pojedynczy element multimediów (zdjęcie/GIF/wideo/link/asset).
///
/// Wszystkie multimedia są OPCJONALNE. Brak multimediów nie może powodować crasha —
/// UI ma korzystać z estetycznego fallbacku (patrz `ExercisePlaceholder` w main.dart).
/// Ten etap dodaje wyłącznie strukturę danych pod kolejne etapy (galeria, wybór z dysku).
library;

/// Rodzaj pojedynczego medium ćwiczenia.
///
/// * [image] — statyczny obraz (lokalny plik albo asset).
/// * [gif]   — animowany GIF (lokalny plik albo asset).
/// * [video] — plik wideo (lokalny albo zdalny URL).
/// * [url]   — zewnętrzny link (np. YouTube / strona z instruktażem).
/// * [asset] — zasób spakowany z aplikacją (np. `assets/exercises/...`).
/// * [none]  — brak medium / nieznany typ (fallback, nigdy nie wyrzuca wyjątku).
enum MediaType {
  image('image', 'Zdjęcie'),
  gif('gif', 'Animacja'),
  video('video', 'Wideo'),
  url('url', 'Link'),
  asset('asset', 'Zasób'),
  none('none', 'Brak');

  const MediaType(this.key, this.label);

  /// Klucz używany w serializacji JSON.
  final String key;

  /// Czytelna nazwa po polsku (np. do oznaczeń w UI).
  final String label;

  /// Czy medium jest animowane (GIF). Wykorzystywane przy wyborze głównej animacji.
  bool get isAnimated => this == MediaType.gif;

  /// Czy medium jest wideo albo zewnętrznym linkiem do wideo.
  bool get isVideo => this == MediaType.video || this == MediaType.url;

  /// Czy medium jest statycznym obrazem.
  bool get isImage => this == MediaType.image;

  /// Bezpieczne mapowanie z tekstu (JSON / dane użytkownika) na [MediaType].
  /// Nieznane wartości zwracają [MediaType.none] — bez wyjątku.
  static MediaType fromKey(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final type in MediaType.values) {
      if (type.key == normalized) return type;
    }
    // Tolerancja na aliasy / dawne dane.
    switch (normalized) {
      case 'photo':
      case 'picture':
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return MediaType.image;
      case 'animation':
      case 'animated':
        return MediaType.gif;
      case 'mp4':
      case 'mov':
      case 'movie':
        return MediaType.video;
      case 'link':
      case 'youtube':
      case 'remote':
        return MediaType.url;
      default:
        return MediaType.none;
    }
  }

  /// Próbuje wykryć typ medium na podstawie ścieżki/URL-a.
  /// Używane jako fallback, gdy typ nie został zapisany jawnie.
  static MediaType guessFromPath(String? path) {
    final lower = path?.trim().toLowerCase() ?? '';
    if (lower.isEmpty) return MediaType.none;
    final isRemote =
        lower.startsWith('http://') || lower.startsWith('https://');
    if (lower.endsWith('.gif')) return MediaType.gif;
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v')) {
      return MediaType.video;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return isRemote ? MediaType.image : MediaType.asset;
    }
    if (isRemote) return MediaType.url;
    return MediaType.asset;
  }
}

/// Pojedynczy element multimediów przypięty do ćwiczenia.
///
/// Może wskazywać na plik lokalny ([localPath]) albo zasób zdalny ([remoteUrl]).
/// Co najmniej jedno z tych pól powinno być ustawione, ale model jest tolerancyjny:
/// gdy oba są puste, [effectivePath] zwraca `null`, a UI pokaże fallback.
class ExerciseMedia {
  const ExerciseMedia({
    required this.id,
    required this.exerciseId,
    required this.type,
    this.localPath,
    this.remoteUrl,
    this.thumbnailPath,
    this.title = '',
    this.description = '',
    this.isPrimary = false,
    this.createdAt,
  });

  /// Unikalny identyfikator medium.
  final String id;

  /// Identyfikator ćwiczenia, do którego należy to medium.
  final String exerciseId;

  /// Typ medium ([MediaType]).
  final MediaType type;

  /// Lokalna ścieżka (plik z dysku albo asset, np. `assets/exercises/squat.gif`).
  final String? localPath;

  /// Zdalny URL (np. obraz/wideo z sieci).
  final String? remoteUrl;

  /// Opcjonalna miniatura (asset/URL) — używana na listach zamiast pełnego medium.
  final String? thumbnailPath;

  /// Krótki tytuł medium (np. „Ujęcie z boku").
  final String title;

  /// Dłuższy opis medium (np. wskazówka do kadru).
  final String description;

  /// Czy to jest główne medium ćwiczenia (miniatura + główna animacja w treningu).
  final bool isPrimary;

  /// Kiedy medium zostało dodane.
  final DateTime? createdAt;

  /// Czy [effectivePath] wskazuje na zasób zdalny (URL).
  bool get isRemote {
    final path = effectivePath;
    if (path == null) return false;
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// Główna ścieżka medium: najpierw lokalna, potem zdalna. `null`, gdy brak obu.
  String? get effectivePath {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) return local;
    final remote = remoteUrl?.trim();
    if (remote != null && remote.isNotEmpty) return remote;
    return null;
  }

  /// Ścieżka do miniatury: najpierw [thumbnailPath], potem [effectivePath].
  /// Dla wideo/linku nie zwraca samego pliku wideo (nie da się go pokazać jako
  /// obraz) — jeśli brak osobnej miniatury, zwraca `null` i UI użyje fallbacku.
  String? get thumbnail {
    final thumb = thumbnailPath?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    if (type.isVideo) return null;
    return effectivePath;
  }

  /// Czy to medium ma jakąkolwiek użyteczną zawartość.
  bool get hasContent => effectivePath != null;

  ExerciseMedia copyWith({
    String? id,
    String? exerciseId,
    MediaType? type,
    String? localPath,
    String? remoteUrl,
    String? thumbnailPath,
    String? title,
    String? description,
    bool? isPrimary,
    DateTime? createdAt,
  }) {
    return ExerciseMedia(
      id: id ?? this.id,
      exerciseId: exerciseId ?? this.exerciseId,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      title: title ?? this.title,
      description: description ?? this.description,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'type': type.key,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'thumbnailPath': thumbnailPath,
        'title': title,
        'description': description,
        'isPrimary': isPrimary,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory ExerciseMedia.fromJson(Map<String, dynamic> json) {
    final localPath = _nullableText(json['localPath']);
    final remoteUrl = _nullableText(json['remoteUrl']);
    // Jeśli typ nie zapisany, spróbuj wykryć go ze ścieżki — bez crasha.
    final rawType = json['type'];
    final type = rawType == null
        ? MediaType.guessFromPath(localPath ?? remoteUrl)
        : MediaType.fromKey(rawType);
    return ExerciseMedia(
      id: json['id']?.toString() ?? _newId('media'),
      exerciseId: json['exerciseId']?.toString() ?? '',
      type: type,
      localPath: localPath,
      remoteUrl: remoteUrl,
      thumbnailPath: _nullableText(json['thumbnailPath']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isPrimary: json['isPrimary'] == true,
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _newId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
