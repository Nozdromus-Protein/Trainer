import 'program_variant.dart';

/// Maksymalna ręczna korekta intensywności w krokach (±6) — jedno źródło
/// prawdy dla planu, dnia i logiki w `deload_cycle.dart`.
/// Jeden krok to ≈5% ciężaru i +1 powtórzenie; seria dochodzi co drugi krok.
const int kMaxIntensitySteps = 6;

/// Maksymalna korekta ŁĄCZNA (program + dzień). Obie gałki mają po
/// ±[kMaxIntensitySteps], więc razem dają dwukrotność — dzień da się podkręcić
/// ponad to, co ustawione dla całego programu.
const int kMaxCombinedIntensitySteps = kMaxIntensitySteps * 2;

/// Status pojedynczego dnia programu w widoku liniowym (Etap 28).
enum WorkoutDayStatus {
  /// Dzień ukończony.
  completed,

  /// Bieżący dzień do wykonania (tryb liniowy).
  active,

  /// Dzień dostępny do treningu (np. w trybie „dowolny dzień").
  available,

  /// Dzień zablokowany do czasu ukończenia poprzedniego.
  locked,

  /// Dzień odpoczynku (brak ćwiczeń) — osobny status wizualny.
  rest,
}

class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.days,
    required this.note,
    this.goal = 'Sylwetka',
    this.isActive = false,
    this.level = '',
    this.imageAsset,
    this.allowAnyDay = false,
    this.completedDays = const <int>{},
    this.activeVariantId = '',
    this.variantHistory = const <ProgramVariantChange>[],
    this.media,
    this.intensitySteps = 0,
  });

  final String id;
  final String name;
  final List<WorkoutDay> days;
  final String note;
  final String goal;
  final bool isActive;

  /// Poziom programu (np. „Początkujący"/„Średniozaawansowany"/„Zaawansowany").
  /// Pusty = nie pokazuj etykiety poziomu. Etap 28.
  final String level;

  /// Opcjonalny obraz tła nagłówka programu (asset/URL). Brak = gradient. Etap 28.
  final String? imageAsset;

  /// Czy użytkownik może trenować dowolny dzień (wyłącza blokowanie). Etap 28.
  final bool allowAnyDay;

  /// Indeksy dni (w [days]) oznaczonych jako ukończone. Etap 28.
  final Set<int> completedDays;

  /// Aktualnie zastosowany wariant programu ('' = szablon bazowy).
  final String activeVariantId;

  /// Historia zmian wariantów — moment każdej zmiany zostaje oznaczony,
  /// ukończone dni nigdy nie są przeliczane wstecz.
  final List<ProgramVariantChange> variantHistory;

  /// Okładka/obraz programu (osobne pole — nie dotyka obrazów ćwiczeń).
  final ProgramMedia? media;

  /// Ręczna korekta intensywności całego programu w krokach
  /// (−[kMaxIntensitySteps]..+[kMaxIntensitySteps]).
  /// Nakładka NAD automatyczną rampą cyklu; 0 = zestawy jak zaprojektowane.
  final int intensitySteps;

  WorkoutPlan copyWith({
    String? id,
    String? name,
    List<WorkoutDay>? days,
    String? note,
    String? goal,
    bool? isActive,
    String? level,
    String? imageAsset,
    bool? allowAnyDay,
    Set<int>? completedDays,
    String? activeVariantId,
    List<ProgramVariantChange>? variantHistory,
    ProgramMedia? media,
    bool clearMedia = false,
    int? intensitySteps,
  }) {
    return WorkoutPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      days: days ?? this.days,
      note: note ?? this.note,
      goal: goal ?? this.goal,
      isActive: isActive ?? this.isActive,
      level: level ?? this.level,
      imageAsset: imageAsset ?? this.imageAsset,
      allowAnyDay: allowAnyDay ?? this.allowAnyDay,
      completedDays: completedDays ?? this.completedDays,
      activeVariantId: activeVariantId ?? this.activeVariantId,
      variantHistory: variantHistory ?? this.variantHistory,
      media: clearMedia ? null : (media ?? this.media),
      intensitySteps: intensitySteps ?? this.intensitySteps,
    );
  }

  // ===== Etap 28: logika programu liniowego =====

  /// Liczba ukończonych dni (zliczane tylko poprawne indeksy).
  int get completedCount =>
      completedDays.where((index) => index >= 0 && index < days.length).length;

  /// Postęp programu w zakresie 0..1.
  double get progress => days.isEmpty ? 0 : completedCount / days.length;

  /// Czy dzień jest dniem odpoczynku (brak ćwiczeń albo tytuł sugerujący odpoczynek).
  bool isRestDay(WorkoutDay day) {
    if (day.items.isEmpty) return true;
    final title = day.title.toLowerCase();
    return title.contains('odpocz') || title.contains('rest');
  }

  bool isDayCompleted(int index) => completedDays.contains(index);

  /// Indeks bieżącego dnia (pierwszy nieukończony). Gdy wszystkie ukończone,
  /// zwraca [days].length (program zakończony).
  int get currentDayIndex {
    for (var index = 0; index < days.length; index++) {
      if (!isDayCompleted(index)) return index;
    }
    return days.length;
  }

  /// Czy cały program jest ukończony.
  bool get isProgramCompleted =>
      days.isNotEmpty && currentDayIndex >= days.length;

  /// Status dnia o danym indeksie (z uwzględnieniem trybu „dowolny dzień").
  WorkoutDayStatus statusForDay(int index) {
    if (index < 0 || index >= days.length) return WorkoutDayStatus.locked;
    if (isDayCompleted(index)) return WorkoutDayStatus.completed;
    final locked = !allowAnyDay && index > currentDayIndex;
    if (locked) return WorkoutDayStatus.locked;
    if (isRestDay(days[index])) return WorkoutDayStatus.rest;
    if (!allowAnyDay && index == currentDayIndex) {
      return WorkoutDayStatus.active;
    }
    return WorkoutDayStatus.available;
  }

  /// Czy dany dzień można wystartować (nie jest zablokowany ani pusty bez sensu).
  bool canStartDay(int index) {
    final status = statusForDay(index);
    return status != WorkoutDayStatus.locked;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days.map((day) => day.toJson()).toList(),
        'note': note,
        'goal': goal,
        'isActive': isActive,
        'level': level,
        'imageAsset': imageAsset,
        'allowAnyDay': allowAnyDay,
        'completedDays': completedDays.toList()..sort(),
        if (activeVariantId.isNotEmpty) 'activeVariantId': activeVariantId,
        if (variantHistory.isNotEmpty)
          'variantHistory': [
            for (final change in variantHistory) change.toJson(),
          ],
        if (media != null) 'media': media!.toJson(),
        if (intensitySteps != 0) 'intensitySteps': intensitySteps,
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id']?.toString() ??
            'plan_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'Plan',
        days: ((json['days'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => WorkoutDay.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        note: json['note']?.toString() ?? '',
        goal: normalizeWorkoutPlanGoal(json['goal']?.toString() ?? ''),
        isActive: json['isActive'] as bool? ?? false,
        level: json['level']?.toString() ?? '',
        imageAsset: _nullableText(json['imageAsset']),
        allowAnyDay: json['allowAnyDay'] as bool? ?? false,
        completedDays: ((json['completedDays'] as List?) ?? const [])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .toSet(),
        activeVariantId: json['activeVariantId']?.toString() ?? '',
        variantHistory: [
          for (final raw in (json['variantHistory'] as List? ?? const []))
            if (raw is Map)
              ProgramVariantChange.fromJson(Map<String, dynamic>.from(raw)),
        ],
        media: json['media'] is Map
            ? ProgramMedia.fromJson(
                Map<String, dynamic>.from(json['media'] as Map),
              )
            : null,
        intensitySteps: ((json['intensitySteps'] as num?)?.toInt() ?? 0)
            .clamp(-kMaxIntensitySteps, kMaxIntensitySteps),
      );
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

const List<String> workoutPlanGoals = [
  'Masa',
  'Redukcja',
  'Siła',
  'Kondycja',
  'Sylwetka',
];

String normalizeWorkoutPlanGoal(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('masa') ||
      normalized.contains('hipert') ||
      normalized.contains('mięś') ||
      normalized.contains('mies')) {
    return 'Masa';
  }
  if (normalized.contains('redu') ||
      normalized.contains('spal') ||
      normalized.contains('fat')) {
    return 'Redukcja';
  }
  if (normalized.contains('sił') || normalized.contains('sil')) {
    return 'Siła';
  }
  if (normalized.contains('kond') ||
      normalized.contains('wydol') ||
      normalized.contains('cardio')) {
    return 'Kondycja';
  }
  return 'Sylwetka';
}

/// Charakter dnia w mikrocyklu programu.
///
/// Zapisywany razem z planem, żeby po wygenerowaniu programu dało się odróżnić
/// dzień CIĘŻKI (siłowy) od techniki/mobilności/kondycji — wcześniej ta wiedza
/// istniała tylko w generatorze katalogu i ginęła bezpowrotnie.
enum WorkoutDayKind {
  /// Dzień siłowy — CIĘŻKI: wymaga osobnego programu rozgrzewkowego.
  strength('strength', 'Siłowy'),
  technique('technique', 'Technika'),
  mobility('mobility', 'Mobilność'),
  conditioning('conditioning', 'Kondycja'),
  rest('rest', 'Odpoczynek'),

  /// Nieznany — starszy zapis albo plan własny; charakter wnioskowany z treści.
  unknown('', 'Nieokreślony');

  const WorkoutDayKind(this.key, this.label);

  final String key;
  final String label;

  /// Czy ten dzień jest ciężki (wymaga rozgrzewki jako osobnego programu).
  bool get isHeavy => this == WorkoutDayKind.strength;

  static WorkoutDayKind fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) return WorkoutDayKind.unknown;
    for (final kind in WorkoutDayKind.values) {
      if (kind.key == normalized || kind.name == normalized) return kind;
    }
    return WorkoutDayKind.unknown;
  }
}

class WorkoutDay {
  const WorkoutDay({
    required this.weekday,
    required this.title,
    required this.items,
    this.kind = WorkoutDayKind.unknown,
    this.intensitySteps = 0,
  });

  final int weekday;
  final String title;
  final List<PlanItem> items;

  /// Ręczna korekta intensywności TEGO dnia, sumowana z korektą całego
  /// programu ([WorkoutPlan.intensitySteps]). Zakres ±[kMaxIntensitySteps].
  final int intensitySteps;

  /// Charakter dnia. [WorkoutDayKind.unknown] dla starszych zapisów i planów
  /// własnych — wtedy „ciężkość" wnioskuje się z zawartości dnia.
  final WorkoutDayKind kind;

  WorkoutDay copyWith({
    int? weekday,
    String? title,
    List<PlanItem>? items,
    WorkoutDayKind? kind,
    int? intensitySteps,
  }) {
    return WorkoutDay(
      weekday: weekday ?? this.weekday,
      title: title ?? this.title,
      items: items ?? this.items,
      kind: kind ?? this.kind,
      intensitySteps: intensitySteps ?? this.intensitySteps,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'title': title,
        'items': items.map((item) => item.toJson()).toList(),
        if (kind != WorkoutDayKind.unknown) 'kind': kind.key,
        if (intensitySteps != 0) 'intensitySteps': intensitySteps,
      };

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        title: json['title']?.toString() ?? 'Trening',
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => PlanItem.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        kind: WorkoutDayKind.fromKey(json['kind']),
        intensitySteps: ((json['intensitySteps'] as num?)?.toInt() ?? 0)
            .clamp(-kMaxIntensitySteps, kMaxIntensitySteps),
      );
}

class PlanItem {
  const PlanItem({
    required this.exerciseId,
    required this.sets,
    required this.reps,
    required this.durationSec,
    required this.note,
    this.suggestedWeightKg = 0,
    this.restSeconds = 90,
  });

  final String exerciseId;
  final int sets;
  final int reps;
  final int durationSec;
  final String note;
  final double suggestedWeightKg;
  final int restSeconds;

  PlanItem copyWith({
    String? exerciseId,
    int? sets,
    int? reps,
    int? durationSec,
    String? note,
    double? suggestedWeightKg,
    int? restSeconds,
  }) {
    return PlanItem(
      exerciseId: exerciseId ?? this.exerciseId,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      durationSec: durationSec ?? this.durationSec,
      note: note ?? this.note,
      suggestedWeightKg: suggestedWeightKg ?? this.suggestedWeightKg,
      restSeconds: restSeconds ?? this.restSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets,
        'reps': reps,
        'durationSec': durationSec,
        'note': note,
        'suggestedWeightKg': suggestedWeightKg,
        'restSeconds': restSeconds,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        exerciseId: json['exerciseId']?.toString() ?? '',
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        reps: (json['reps'] as num?)?.toInt() ?? 10,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        note: json['note']?.toString() ?? '',
        suggestedWeightKg: (json['suggestedWeightKg'] as num?)?.toDouble() ?? 0,
        restSeconds: (json['restSeconds'] as num?)?.toInt() ?? 90,
      );
}
