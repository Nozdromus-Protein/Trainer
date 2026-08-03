/// Limity objętości ZESTAWU ĆWICZEŃ — dolna i górna granica per PARTIA MIĘŚNIOWA.
///
/// PROBLEM, KTÓRY TO ROZWIĄZUJE: dotąd nic nie pilnowało, ile zestaw ma mieć
/// różnych ćwiczeń na partię, ile serii na ćwiczenie i w jakim zakresie
/// powtórzeń. Generator, edycja zestawu i rekomendacje trenera mogły wypuścić
/// dzień z jednym ćwiczeniem na klatkę albo z dziesięcioma na biceps.
///
/// Model jest trójwarstwowy — każda partia ma trzy pary „min–max":
///  * ĆWICZENIA — ile RÓŻNYCH ruchów na tę partię ma zestaw,
///  * SERIE     — ile serii w jednym ćwiczeniu tej partii,
///  * POWTÓRZENIA — zakres powtórzeń pojedynczej serii.
///
/// INTENSYWNOŚĆ A LIMITY (zmiana względem wcześniejszego założenia): wybrana
/// intensywność ([WorkoutIntensityLevel]) PRZESUWA granice — lekki dzień ma
/// węższy zakres ćwiczeń i serii, bardzo wysoki szerszy. Wcześniej limity były
/// od intensywności całkowicie niezależne, przez co „bardzo wysoka" i „lekka"
/// dawały ten sam projekt zestawu.
///
/// Rozdział ról zostaje: limity opisują ZAKRES, w jakim zestaw ma być
/// zbudowany, a gałka kroków intensywności ([applyIntensityStepToItem]
/// w `deload_cycle.dart`) nadal działa NA GOTOWYM zestawie i nie jest przez nie
/// przycinana. Limity egzekwujemy PRZED nałożeniem korekty, nie po.
///
/// Czysty Dart — bez UI, deterministyczny, łatwy do testów.
library;

import 'exercise.dart';
import 'trainer_enums.dart';
import 'workout_plan.dart';

// ============================================================================
// Zakres min–max
// ============================================================================

/// Para „najmniej – najwięcej" z przycinaniem wartości.
class VolumeBounds {
  const VolumeBounds(this.min, this.max);

  final int min;
  final int max;

  /// Przycina [value] do zakresu (zakres odwrócony jest naprawiany).
  int clampValue(int value) {
    final low = min <= max ? min : max;
    final high = min <= max ? max : min;
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }

  bool contains(int value) => value >= min && value <= max;

  /// Zakres przesunięty o [minDelta]/[maxDelta] z zachowaniem sensu (min ≤ max)
  /// i twardej podłogi [floor].
  VolumeBounds shifted(int minDelta, int maxDelta, {int floor = 1}) {
    final newMin = (min + minDelta) < floor ? floor : (min + minDelta);
    final newMax = (max + maxDelta) < newMin ? newMin : (max + maxDelta);
    return VolumeBounds(newMin, newMax);
  }

  /// Część wspólna z [other]; gdy zakresy się nie przecinają, wygrywa THIS
  /// (limit twardy) — [other] jest tylko preferencją (np. zakres celu).
  VolumeBounds intersect(VolumeBounds other) {
    final low = min > other.min ? min : other.min;
    final high = max < other.max ? max : other.max;
    if (low > high) return this;
    return VolumeBounds(low, high);
  }

  String get label => min == max ? '$min' : '$min–$max';

  Map<String, dynamic> toJson() => {'min': min, 'max': max};

  factory VolumeBounds.fromJson(
          Map<String, dynamic> json, VolumeBounds fallback) =>
      VolumeBounds(
        (json['min'] as num?)?.toInt() ?? fallback.min,
        (json['max'] as num?)?.toInt() ?? fallback.max,
      );

  @override
  bool operator ==(Object other) =>
      other is VolumeBounds && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'VolumeBounds($min–$max)';
}

/// Komplet limitów jednej partii mięśniowej.
class MuscleVolumeLimits {
  const MuscleVolumeLimits({
    required this.exercises,
    required this.sets,
    required this.reps,
  });

  /// Ile RÓŻNYCH ćwiczeń na tę partię ma zawierać zestaw.
  final VolumeBounds exercises;

  /// Ile serii przypada na jedno ćwiczenie tej partii.
  final VolumeBounds sets;

  /// Zakres powtórzeń pojedynczej serii.
  final VolumeBounds reps;

  /// Najmniejsza sensowna liczba serii roboczych na partię w jednym zestawie.
  int get minWorkingSets => exercises.min * sets.min;

  /// Największa dopuszczalna liczba serii roboczych na partię w zestawie.
  int get maxWorkingSets => exercises.max * sets.max;

  MuscleVolumeLimits copyWith({
    VolumeBounds? exercises,
    VolumeBounds? sets,
    VolumeBounds? reps,
  }) =>
      MuscleVolumeLimits(
        exercises: exercises ?? this.exercises,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
      );

  Map<String, dynamic> toJson() => {
        'exercises': exercises.toJson(),
        'sets': sets.toJson(),
        'reps': reps.toJson(),
      };

  factory MuscleVolumeLimits.fromJson(
    Map<String, dynamic> json,
    MuscleVolumeLimits fallback,
  ) =>
      MuscleVolumeLimits(
        exercises: json['exercises'] is Map
            ? VolumeBounds.fromJson(
                Map<String, dynamic>.from(json['exercises'] as Map),
                fallback.exercises)
            : fallback.exercises,
        sets: json['sets'] is Map
            ? VolumeBounds.fromJson(
                Map<String, dynamic>.from(json['sets'] as Map), fallback.sets)
            : fallback.sets,
        reps: json['reps'] is Map
            ? VolumeBounds.fromJson(
                Map<String, dynamic>.from(json['reps'] as Map), fallback.reps)
            : fallback.reps,
      );

  @override
  bool operator ==(Object other) =>
      other is MuscleVolumeLimits &&
      other.exercises == exercises &&
      other.sets == sets &&
      other.reps == reps;

  @override
  int get hashCode => Object.hash(exercises, sets, reps);
}

// ============================================================================
// Domyślne limity per partia
// ============================================================================

/// Limity domyślne. Duże partie znoszą więcej ruchów i serii niż małe; brzuch
/// i łydki pracują w wyższych powtórzeniach. Zakresy powtórzeń są CELOWO
/// szerokie — zawężenie do celu (siła 4–6, masa 8–12…) robi [volumeLimitsFor],
/// a twarda granica ma tylko odcinać absurdy (seria na 2 albo na 45 powtórzeń).
const Map<MuscleGroup, MuscleVolumeLimits> kDefaultMuscleVolumeLimits = {
  MuscleGroup.chest: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 6),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(4, 20),
  ),
  MuscleGroup.back: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 7),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(4, 20),
  ),
  MuscleGroup.shoulders: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 6),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(6, 22),
  ),
  MuscleGroup.biceps: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 5),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(6, 20),
  ),
  MuscleGroup.triceps: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 5),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(6, 20),
  ),
  MuscleGroup.forearms: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 5),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(8, 25),
  ),
  MuscleGroup.core: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 8),
    sets: VolumeBounds(2, 5),
    reps: VolumeBounds(8, 30),
  ),
  MuscleGroup.quadriceps: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 6),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(4, 20),
  ),
  MuscleGroup.hamstrings: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 5),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(4, 20),
  ),
  MuscleGroup.glutes: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 5),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(6, 20),
  ),
  MuscleGroup.calves: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 4),
    sets: VolumeBounds(3, 5),
    reps: VolumeBounds(8, 25),
  ),
  MuscleGroup.fullBody: MuscleVolumeLimits(
    exercises: VolumeBounds(3, 8),
    sets: VolumeBounds(2, 5),
    reps: VolumeBounds(6, 25),
  ),
  MuscleGroup.cardio: MuscleVolumeLimits(
    exercises: VolumeBounds(1, 4),
    sets: VolumeBounds(1, 5),
    reps: VolumeBounds(6, 30),
  ),
  MuscleGroup.other: MuscleVolumeLimits(
    exercises: VolumeBounds(2, 6),
    sets: VolumeBounds(2, 5),
    reps: VolumeBounds(6, 25),
  ),
};

const MuscleVolumeLimits _fallbackLimits = MuscleVolumeLimits(
  exercises: VolumeBounds(2, 6),
  sets: VolumeBounds(2, 5),
  reps: VolumeBounds(6, 25),
);

/// Konfiguracja limitów: włącznik + nadpisania użytkownika per partia.
///
/// Puste [overrides] = same wartości domyślne, więc zapis w ustawieniach jest
/// mały, a aktualizacja domyślnych obejmuje wszystkich, którzy nic nie zmieniali.
class VolumeLimitsConfig {
  const VolumeLimitsConfig({
    this.enabled = true,
    this.overrides = const <MuscleGroup, MuscleVolumeLimits>{},
  });

  /// Gdy false — limity są tylko informacyjne (nic nie przycinamy).
  final bool enabled;

  final Map<MuscleGroup, MuscleVolumeLimits> overrides;

  static const VolumeLimitsConfig standard = VolumeLimitsConfig();

  /// Limity partii BEZ korekt poziomu i celu (surowe „min–max" z ustawień).
  MuscleVolumeLimits rawFor(MuscleGroup group) =>
      overrides[group] ?? kDefaultMuscleVolumeLimits[group] ?? _fallbackLimits;

  bool get hasOverrides => overrides.isNotEmpty;

  VolumeLimitsConfig withGroup(MuscleGroup group, MuscleVolumeLimits limits) {
    final next = Map<MuscleGroup, MuscleVolumeLimits>.from(overrides);
    if (limits == (kDefaultMuscleVolumeLimits[group] ?? _fallbackLimits)) {
      next.remove(group);
    } else {
      next[group] = limits;
    }
    return VolumeLimitsConfig(enabled: enabled, overrides: next);
  }

  VolumeLimitsConfig copyWith({
    bool? enabled,
    Map<MuscleGroup, MuscleVolumeLimits>? overrides,
  }) =>
      VolumeLimitsConfig(
        enabled: enabled ?? this.enabled,
        overrides: overrides ?? this.overrides,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (overrides.isNotEmpty)
          'overrides': {
            for (final entry in overrides.entries)
              entry.key.name: entry.value.toJson(),
          },
      };

  factory VolumeLimitsConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['overrides'];
    final overrides = <MuscleGroup, MuscleVolumeLimits>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final group = muscleGroupFromKey(entry.key.toString());
        if (group == null || entry.value is! Map) continue;
        overrides[group] = MuscleVolumeLimits.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
          kDefaultMuscleVolumeLimits[group] ?? _fallbackLimits,
        );
      }
    }
    return VolumeLimitsConfig(
      enabled: json['enabled'] as bool? ?? true,
      overrides: overrides,
    );
  }
}

/// Partia po kluczu ([MuscleGroup.name]); `null`, gdy klucz nieznany.
MuscleGroup? muscleGroupFromKey(String value) {
  final key = value.trim();
  for (final group in MuscleGroup.values) {
    if (group.name == key) return group;
  }
  return null;
}

/// Partie, dla których w ogóle pokazujemy/pilnujemy limitów (bez „Inne").
const List<MuscleGroup> kLimitedMuscleGroups = [
  MuscleGroup.chest,
  MuscleGroup.back,
  MuscleGroup.shoulders,
  MuscleGroup.biceps,
  MuscleGroup.triceps,
  MuscleGroup.forearms,
  MuscleGroup.core,
  MuscleGroup.quadriceps,
  MuscleGroup.hamstrings,
  MuscleGroup.glutes,
  MuscleGroup.calves,
];

// ============================================================================
// Limity efektywne: poziom + cel
// ============================================================================

/// Zakres powtórzeń wynikający z celu/strategii. Zduplikowany świadomie
/// z `training_coach.targetRepRange`, żeby moduł domenowy nie zależał od
/// warstwy aplikacji (ta sama tabela, jedna linijka).
VolumeBounds goalRepBounds(String goal) {
  final g = goal.toLowerCase();
  if (g.contains('sił') || g.contains('sil') || g.contains('strength')) {
    return const VolumeBounds(4, 6);
  }
  if (g.contains('redu') ||
      g.contains('spal') ||
      g.contains('fat') ||
      g.contains('kond') ||
      g.contains('wydol')) {
    return const VolumeBounds(12, 18);
  }
  return const VolumeBounds(8, 12);
}

int _levelRank(String level) {
  final n = level.trim().toLowerCase();
  // „śred" PRZED „zaaw" — „średniozaawansowany" zawiera podciąg „zaaw".
  if (n.contains('śred') ||
      n.contains('sred') ||
      n.contains('inter') ||
      n.contains('mid')) {
    return 1;
  }
  if (n.contains('zaaw') || n.contains('adv')) return 2;
  return 0;
}

// ============================================================================
// Intensywność treningu
// ============================================================================

/// Poziom intensywności zestawu — wspólny język dla limitów, prognoz i UI.
///
/// Aplikacja przechowuje intensywność jako KROKI (−6…+6, gałka programu i dnia).
/// Ten enum tłumaczy je na cztery czytelne poziomy i mówi, co każdy z nich robi
/// z objętością: ile ćwiczeń, ile serii, jaki zakres powtórzeń i jak długa
/// przerwa.
enum WorkoutIntensityLevel {
  light('light', 'Lekka'),
  moderate('moderate', 'Umiarkowana'),
  high('high', 'Wysoka'),
  veryHigh('veryHigh', 'Bardzo wysoka');

  const WorkoutIntensityLevel(this.key, this.label);

  final String key;
  final String label;

  /// Poziom wynikający z kroków gałki intensywności.
  ///
  /// Progi są asymetryczne, bo „standard" (0 kroków) ma być umiarkowany, a nie
  /// środkiem między lekkim a bardzo wysokim.
  static WorkoutIntensityLevel fromSteps(int steps) {
    if (steps <= -3) return light;
    if (steps <= 0) return moderate;
    if (steps <= 3) return high;
    return veryHigh;
  }

  static WorkoutIntensityLevel fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final level in WorkoutIntensityLevel.values) {
      if (level.key == key || level.name == key) return level;
    }
    return WorkoutIntensityLevel.moderate;
  }

  /// Przesunięcie MAKSIMUM liczby różnych ćwiczeń na partię.
  int get exerciseMaxShift => switch (this) {
        WorkoutIntensityLevel.light => -1,
        WorkoutIntensityLevel.moderate => 0,
        WorkoutIntensityLevel.high => 1,
        WorkoutIntensityLevel.veryHigh => 2,
      };

  /// Przesunięcie MINIMUM liczby różnych ćwiczeń na partię. Rośnie wolniej niż
  /// maksimum — wysoka intensywność ma dawać SWOBODĘ, a nie przymus objętości.
  int get exerciseMinShift => switch (this) {
        WorkoutIntensityLevel.light => -1,
        WorkoutIntensityLevel.moderate => 0,
        WorkoutIntensityLevel.high => 0,
        WorkoutIntensityLevel.veryHigh => 1,
      };

  /// Przesunięcie granic liczby serii na ćwiczenie (min, max).
  (int, int) get setShift => switch (this) {
        WorkoutIntensityLevel.light => (-1, -1),
        WorkoutIntensityLevel.moderate => (0, 0),
        WorkoutIntensityLevel.high => (0, 1),
        WorkoutIntensityLevel.veryHigh => (1, 1),
      };

  /// Mnożnik długości przerwy między seriami. Ciężej = dłuższa przerwa.
  double get restFactor => switch (this) {
        WorkoutIntensityLevel.light => 0.85,
        WorkoutIntensityLevel.moderate => 1.0,
        WorkoutIntensityLevel.high => 1.1,
        WorkoutIntensityLevel.veryHigh => 1.2,
      };

  /// Przesunięcie zakresu powtórzeń. Lekki dzień idzie wyżej w powtórzeniach
  /// (mniejszy ciężar), bardzo wysoki — niżej.
  (int, int) get repShift => switch (this) {
        WorkoutIntensityLevel.light => (2, 3),
        WorkoutIntensityLevel.moderate => (0, 0),
        WorkoutIntensityLevel.high => (-1, -1),
        WorkoutIntensityLevel.veryHigh => (-2, -2),
      };

  /// Ile razy szybciej narasta zmęczenie na tym poziomie (do prognoz
  /// regeneracji i ostrzeżeń o przeciążeniu).
  double get fatigueFactor => switch (this) {
        WorkoutIntensityLevel.light => 0.75,
        WorkoutIntensityLevel.moderate => 1.0,
        WorkoutIntensityLevel.high => 1.2,
        WorkoutIntensityLevel.veryHigh => 1.4,
      };
}

/// Limity EFEKTYWNE dla partii: surowe granice skorygowane poziomem
/// (początkujący dostaje węższy zestaw, zaawansowany szerszy), INTENSYWNOŚCIĄ
/// (lekka zwęża, bardzo wysoka poszerza) i celem (zakres powtórzeń zawężony do
/// strategii, ale nigdy poza twarde granice).
///
/// [intensity] domyślnie jest umiarkowana, więc wywołania bez tego argumentu
/// zachowują dotychczasowe wartości co do jednego.
MuscleVolumeLimits volumeLimitsFor(
  MuscleGroup group, {
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  var limits = config.rawFor(group);
  final rank = _levelRank(level);
  if (level.trim().isNotEmpty) {
    if (rank == 0) {
      // Początkujący: mniej ruchów i serii — objętość ma być do udźwignięcia.
      limits = limits.copyWith(
        exercises: limits.exercises.shifted(0, -1, floor: 1),
        sets: limits.sets.shifted(0, -1, floor: 1),
      );
    } else if (rank == 2) {
      limits = limits.copyWith(
        exercises: limits.exercises.shifted(0, 1, floor: 1),
        sets: limits.sets.shifted(0, 1, floor: 1),
      );
    }
  }
  // Intensywność przesuwa ZAKRES budowy zestawu. Gałka kroków nadal działa
  // niezależnie, na gotowym zestawie — tu chodzi o to, żeby „bardzo wysoka"
  // i „lekka" nie projektowały identycznego treningu.
  if (intensity != WorkoutIntensityLevel.moderate) {
    final (setsMin, setsMax) = intensity.setShift;
    final (repsMin, repsMax) = intensity.repShift;
    limits = limits.copyWith(
      exercises: limits.exercises.shifted(
        intensity.exerciseMinShift,
        intensity.exerciseMaxShift,
        floor: 1,
      ),
      sets: limits.sets.shifted(setsMin, setsMax, floor: 1),
      reps: limits.reps.shifted(repsMin, repsMax, floor: 1),
    );
  }
  if (goal.trim().isNotEmpty) {
    limits = limits.copyWith(reps: limits.reps.intersect(goalRepBounds(goal)));
  }
  return limits;
}

// ============================================================================
// Partia główna ćwiczenia
// ============================================================================

/// Partia GŁÓWNA ćwiczenia jako [MuscleGroup] — z jawnych wpływów partii,
/// a gdy ich brak, z opisu tekstowego. [Exercise.muscleGroups] jest zbiorem
/// bez kolejności, więc nie nadaje się do wskazania „tej pierwszej".
MuscleGroup primaryMuscleGroupOf(Exercise exercise) {
  for (final impact in exercise.effectiveMuscleImpacts) {
    if (impact.role == MuscleRole.primary) {
      return muscleGroupOfBodyMuscle(impact.muscleGroup);
    }
  }
  final impacts = exercise.effectiveMuscleImpacts;
  if (impacts.isNotEmpty)
    return muscleGroupOfBodyMuscle(impacts.first.muscleGroup);
  return MuscleGroup.fromText(exercise.primaryMuscle);
}

/// Mapowanie anatomicznej partii na grubszą kategorię limitów.
MuscleGroup muscleGroupOfBodyMuscle(BodyMuscle muscle) {
  switch (muscle) {
    case BodyMuscle.chest:
    case BodyMuscle.serratusAnterior:
      return MuscleGroup.chest;
    case BodyMuscle.lats:
    case BodyMuscle.upperBack:
    case BodyMuscle.lowerBack:
    case BodyMuscle.rhomboids:
    case BodyMuscle.erectorSpinae:
    case BodyMuscle.quadratusLumborum:
    case BodyMuscle.teresMajor:
    case BodyMuscle.teresMinor:
    case BodyMuscle.infraspinatus:
    case BodyMuscle.subscapularis:
    case BodyMuscle.supraspinatus:
      return MuscleGroup.back;
    case BodyMuscle.frontShoulders:
    case BodyMuscle.rearShoulders:
    case BodyMuscle.traps:
    case BodyMuscle.levatorScapulae:
    case BodyMuscle.sternocleidomastoid:
      return MuscleGroup.shoulders;
    case BodyMuscle.biceps:
      return MuscleGroup.biceps;
    case BodyMuscle.triceps:
      return MuscleGroup.triceps;
    case BodyMuscle.forearmsFront:
    case BodyMuscle.forearmsBack:
      return MuscleGroup.forearms;
    case BodyMuscle.abs:
    case BodyMuscle.obliques:
    case BodyMuscle.transverseAbdominis:
    case BodyMuscle.sideWaistBack:
    case BodyMuscle.hipFlexors:
      return MuscleGroup.core;
    case BodyMuscle.quads:
    case BodyMuscle.sartorius:
    case BodyMuscle.tensorFasciaeLatae:
      return MuscleGroup.quadriceps;
    case BodyMuscle.hamstrings:
    case BodyMuscle.adductors:
    case BodyMuscle.gracilis:
      return MuscleGroup.hamstrings;
    case BodyMuscle.glutes:
    case BodyMuscle.gluteMedius:
      return MuscleGroup.glutes;
    case BodyMuscle.calvesBack:
    case BodyMuscle.calvesFront:
    case BodyMuscle.soleus:
    case BodyMuscle.gastrocnemius:
    case BodyMuscle.tibialis:
      return MuscleGroup.calves;
  }
}

/// Czy pozycja planu liczy się do OBJĘTOŚCI ROBOCZEJ partii. Rozgrzewka,
/// rozciąganie i mobilność przygotowują albo domykają trening — wliczanie ich
/// do limitów zawyżałoby zestaw i kazało wyrzucać realne boje.
bool isWorkingVolumeItem(PlanItem item, Exercise exercise) {
  final note = item.note.toLowerCase();
  if (note.contains('rozgrzew') ||
      note.contains('rozciąg') ||
      note.contains('rozciag')) {
    return false;
  }
  final category = exercise.category.toLowerCase();
  if (category.contains('rozgrzew') ||
      category.contains('rozciąg') ||
      category.contains('rozciag')) {
    return false;
  }
  return exercise.entryType != ExerciseEntryType.mobility;
}

// ============================================================================
// Analiza zestawu
// ============================================================================

enum VolumeIssueKind {
  exercisesBelowMin,
  exercisesAboveMax,
  setsBelowMin,
  setsAboveMax,
  repsBelowMin,
  repsAboveMax,
}

/// Pojedyncze naruszenie limitu (z gotowym komunikatem do UI).
class VolumeIssue {
  const VolumeIssue({
    required this.group,
    required this.kind,
    required this.actual,
    required this.limit,
    this.exerciseId = '',
    this.exerciseName = '',
  });

  final MuscleGroup group;
  final VolumeIssueKind kind;

  /// Wartość zastana (liczba ćwiczeń / serii / powtórzeń).
  final int actual;

  /// Granica, która została naruszona.
  final int limit;

  /// Ćwiczenie, którego dotyczy problem (puste dla limitu liczby ćwiczeń).
  final String exerciseId;
  final String exerciseName;

  /// Czy problem to NIEDOBÓR (za mało) — reszta to nadmiar.
  bool get isDeficit =>
      kind == VolumeIssueKind.exercisesBelowMin ||
      kind == VolumeIssueKind.setsBelowMin ||
      kind == VolumeIssueKind.repsBelowMin;

  String get message {
    switch (kind) {
      case VolumeIssueKind.exercisesBelowMin:
        return '${group.label}: $actual ćwiczenia w zestawie — minimum to $limit.';
      case VolumeIssueKind.exercisesAboveMax:
        return '${group.label}: $actual ćwiczeń w zestawie — maksimum to $limit.';
      case VolumeIssueKind.setsBelowMin:
        return '${group.label} · $exerciseName: $actual serii — minimum to $limit.';
      case VolumeIssueKind.setsAboveMax:
        return '${group.label} · $exerciseName: $actual serii — maksimum to $limit.';
      case VolumeIssueKind.repsBelowMin:
        return '${group.label} · $exerciseName: $actual powtórzeń — minimum to $limit.';
      case VolumeIssueKind.repsAboveMax:
        return '${group.label} · $exerciseName: $actual powtórzeń — maksimum to $limit.';
    }
  }
}

/// Ile zestaw realnie daje danej partii.
class MuscleVolumeCount {
  const MuscleVolumeCount({
    required this.group,
    required this.exerciseIds,
    required this.workingSets,
    required this.limits,
  });

  final MuscleGroup group;

  /// Różne ćwiczenia, dla których ta partia jest GŁÓWNA.
  final List<String> exerciseIds;

  /// Suma serii tych ćwiczeń.
  final int workingSets;

  final MuscleVolumeLimits limits;

  int get exerciseCount => exerciseIds.length;

  bool get withinExerciseLimits => limits.exercises.contains(exerciseCount);
}

/// Wynik analizy zestawu pod kątem limitów.
class WorkoutVolumeReport {
  const WorkoutVolumeReport({required this.counts, required this.issues});

  final Map<MuscleGroup, MuscleVolumeCount> counts;
  final List<VolumeIssue> issues;

  static const WorkoutVolumeReport empty =
      WorkoutVolumeReport(counts: {}, issues: []);

  bool get isValid => issues.isEmpty;

  List<String> get messages => [for (final issue in issues) issue.message];

  /// Partie, którym w zestawie brakuje ćwiczeń (do uzupełnienia z puli).
  List<MuscleGroup> get groupsNeedingMore => [
        for (final issue in issues)
          if (issue.kind == VolumeIssueKind.exercisesBelowMin) issue.group,
      ];
}

/// Sprawdza zestaw (dzień planu) względem limitów objętości.
///
/// Liczone są WYŁĄCZNIE pozycje robocze ([isWorkingVolumeItem]) i tylko partia
/// GŁÓWNA każdego ćwiczenia — inaczej triceps z wyciskania podbijałby limit
/// tricepsa, mimo że nikt go świadomie nie zaplanował.
WorkoutVolumeReport analyzeWorkoutVolume({
  required List<PlanItem> items,
  required Exercise Function(String id) resolve,
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  final byGroup = <MuscleGroup, List<({PlanItem item, Exercise exercise})>>{};
  for (final item in items) {
    final exercise = resolve(item.exerciseId);
    if (!isWorkingVolumeItem(item, exercise)) continue;
    final group = primaryMuscleGroupOf(exercise);
    byGroup.putIfAbsent(group, () => []).add((item: item, exercise: exercise));
  }

  final counts = <MuscleGroup, MuscleVolumeCount>{};
  final issues = <VolumeIssue>[];
  byGroup.forEach((group, entries) {
    final limits = volumeLimitsFor(group,
        level: level, goal: goal, config: config, intensity: intensity);
    final ids = <String>[];
    var sets = 0;
    for (final entry in entries) {
      if (!ids.contains(entry.item.exerciseId)) ids.add(entry.item.exerciseId);
      sets += entry.item.sets;
    }
    counts[group] = MuscleVolumeCount(
      group: group,
      exerciseIds: ids,
      workingSets: sets,
      limits: limits,
    );

    if (ids.length < limits.exercises.min) {
      issues.add(VolumeIssue(
        group: group,
        kind: VolumeIssueKind.exercisesBelowMin,
        actual: ids.length,
        limit: limits.exercises.min,
      ));
    } else if (ids.length > limits.exercises.max) {
      issues.add(VolumeIssue(
        group: group,
        kind: VolumeIssueKind.exercisesAboveMax,
        actual: ids.length,
        limit: limits.exercises.max,
      ));
    }

    for (final entry in entries) {
      final item = entry.item;
      final name = entry.exercise.name;
      if (item.sets < limits.sets.min) {
        issues.add(VolumeIssue(
          group: group,
          kind: VolumeIssueKind.setsBelowMin,
          actual: item.sets,
          limit: limits.sets.min,
          exerciseId: item.exerciseId,
          exerciseName: name,
        ));
      } else if (item.sets > limits.sets.max) {
        issues.add(VolumeIssue(
          group: group,
          kind: VolumeIssueKind.setsAboveMax,
          actual: item.sets,
          limit: limits.sets.max,
          exerciseId: item.exerciseId,
          exerciseName: name,
        ));
      }
      // Powtórzenia dotyczą wyłącznie pozycji powtórzeniowych.
      if (item.reps <= 0) continue;
      if (item.reps < limits.reps.min) {
        issues.add(VolumeIssue(
          group: group,
          kind: VolumeIssueKind.repsBelowMin,
          actual: item.reps,
          limit: limits.reps.min,
          exerciseId: item.exerciseId,
          exerciseName: name,
        ));
      } else if (item.reps > limits.reps.max) {
        issues.add(VolumeIssue(
          group: group,
          kind: VolumeIssueKind.repsAboveMax,
          actual: item.reps,
          limit: limits.reps.max,
          exerciseId: item.exerciseId,
          exerciseName: name,
        ));
      }
    }
  });

  return WorkoutVolumeReport(counts: counts, issues: issues);
}

// ============================================================================
// Egzekwowanie limitów
// ============================================================================

/// Przycina JEDNĄ pozycję planu do limitów jej partii głównej.
///
/// Zakres powtórzeń zawężamy tylko wtedy, gdy ćwiczenie jest powtórzeniowe —
/// pozycji czasowych limit powtórzeń nie dotyczy.
PlanItem clampPlanItemToLimits(
  PlanItem item,
  Exercise exercise, {
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  if (!config.enabled) return item;
  if (!isWorkingVolumeItem(item, exercise)) return item;
  final limits = volumeLimitsFor(
    primaryMuscleGroupOf(exercise),
    level: level,
    goal: goal,
    config: config,
    intensity: intensity,
  );
  final sets = limits.sets.clampValue(item.sets);
  final reps = item.reps > 0 ? limits.reps.clampValue(item.reps) : item.reps;
  if (sets == item.sets && reps == item.reps) return item;
  return item.copyWith(sets: sets, reps: reps);
}

/// Egzekwuje limity w całym zestawie: przycina serie/powtórzenia i usuwa
/// nadmiarowe ćwiczenia partii (od najlżejszego), gdy jest ich więcej niż
/// maksimum. NIE dodaje ćwiczeń — uzupełnianie wymaga puli, więc robi to
/// generator programu ([topUpToMinimumExercises]).
List<PlanItem> enforceVolumeLimits(
  List<PlanItem> items,
  Exercise Function(String id) resolve, {
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
  int Function(Exercise exercise)? weightOf,
}) {
  if (!config.enabled || items.isEmpty) return items;
  final clamped = <PlanItem>[
    for (final item in items)
      clampPlanItemToLimits(item, resolve(item.exerciseId),
          level: level, goal: goal, config: config, intensity: intensity),
  ];

  // Nadmiar ćwiczeń w partii — wypada najlżejsze (najniższy „ciężar" pozycji).
  final indexesByGroup = <MuscleGroup, List<int>>{};
  for (var i = 0; i < clamped.length; i++) {
    final exercise = resolve(clamped[i].exerciseId);
    if (!isWorkingVolumeItem(clamped[i], exercise)) continue;
    indexesByGroup.putIfAbsent(primaryMuscleGroupOf(exercise), () => []).add(i);
  }
  final drop = <int>{};
  indexesByGroup.forEach((group, indexes) {
    final limits = volumeLimitsFor(group,
        level: level, goal: goal, config: config, intensity: intensity);
    var excess = indexes.length - limits.exercises.max;
    if (excess <= 0) return;
    final ordered = [...indexes]..sort((a, b) {
        final wa = weightOf?.call(resolve(clamped[a].exerciseId)) ?? 0;
        final wb = weightOf?.call(resolve(clamped[b].exerciseId)) ?? 0;
        if (wa != wb) return wa.compareTo(wb); // najlżejsze pierwsze
        return b.compareTo(a); // przy remisie — od końca zestawu
      });
    for (final index in ordered) {
      if (excess <= 0) break;
      drop.add(index);
      excess--;
    }
  });
  if (drop.isEmpty) return clamped;
  return [
    for (var i = 0; i < clamped.length; i++)
      if (!drop.contains(i)) clamped[i],
  ];
}

/// Ile ćwiczeń brakuje danej partii do minimum (0 = zestaw spełnia limit).
int missingExerciseCount(
  List<PlanItem> items,
  Exercise Function(String id) resolve,
  MuscleGroup group, {
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  if (!config.enabled) return 0;
  final limits = volumeLimitsFor(group,
      level: level, goal: goal, config: config, intensity: intensity);
  final ids = <String>{};
  for (final item in items) {
    final exercise = resolve(item.exerciseId);
    if (!isWorkingVolumeItem(item, exercise)) continue;
    if (primaryMuscleGroupOf(exercise) == group) ids.add(item.exerciseId);
  }
  final missing = limits.exercises.min - ids.length;
  return missing > 0 ? missing : 0;
}

/// Uzupełnia zestaw o brakujące ćwiczenia partii [group] z podanej [pool]
/// (deterministycznie, w kolejności puli). Zwraca listę id do dołożenia.
List<String> topUpToMinimumExercises({
  required List<PlanItem> items,
  required List<String> pool,
  required Exercise Function(String id) resolve,
  required MuscleGroup group,
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  final missing = missingExerciseCount(items, resolve, group,
      level: level, goal: goal, config: config, intensity: intensity);
  if (missing <= 0 || pool.isEmpty) return const [];
  final used = {for (final item in items) item.exerciseId};
  final result = <String>[];
  for (final id in pool) {
    if (result.length >= missing) break;
    if (!used.add(id)) continue;
    if (primaryMuscleGroupOf(resolve(id)) != group) continue;
    result.add(id);
  }
  return result;
}

// ============================================================================
// Pasmo objętości: gdzie zestaw stoi względem limitu
// ============================================================================

/// Jak daleko od zalecanego zakresu leży objętość zestawu.
///
/// Rozróżnienie „nieznacznie" / „znacznie" jest celowe: drobne odchylenie to
/// normalna praca, dopiero duże ma sens komunikować jako ryzyko dla regeneracji.
enum VolumeBandStatus {
  farBelow,
  slightlyBelow,
  within,
  slightlyAbove,
  farAbove;

  bool get isWithin => this == VolumeBandStatus.within;
  bool get isBelow =>
      this == VolumeBandStatus.farBelow ||
      this == VolumeBandStatus.slightlyBelow;
  bool get isAbove =>
      this == VolumeBandStatus.farAbove ||
      this == VolumeBandStatus.slightlyAbove;

  /// Czy odchylenie zasługuje na ostrzeżenie o wpływie na regenerację.
  bool get isSevere =>
      this == VolumeBandStatus.farAbove || this == VolumeBandStatus.farBelow;

  String get label => switch (this) {
        VolumeBandStatus.farBelow => 'Znacznie poniżej limitu',
        VolumeBandStatus.slightlyBelow => 'Nieznacznie poniżej limitu',
        VolumeBandStatus.within => 'W limicie',
        VolumeBandStatus.slightlyAbove => 'Nieznacznie powyżej limitu',
        VolumeBandStatus.farAbove => 'Znacznie powyżej limitu',
      };
}

/// Objętość zestawu porównana z zakresem zalecanym dla wybranej intensywności.
class WorkoutVolumeBand {
  const WorkoutVolumeBand({
    required this.workingSets,
    required this.recommendedMin,
    required this.recommendedMax,
    required this.status,
    required this.intensity,
    required this.exerciseCount,
    required this.exerciseMin,
    required this.exerciseMax,
  });

  /// Serie ROBOCZE w całym zestawie (bez rozgrzewki i rozciągania).
  final int workingSets;
  final int recommendedMin;
  final int recommendedMax;
  final VolumeBandStatus status;
  final WorkoutIntensityLevel intensity;

  /// Liczba pozycji roboczych i zalecany zakres (do komunikatu „6 z 8").
  final int exerciseCount;
  final int exerciseMin;
  final int exerciseMax;

  static const WorkoutVolumeBand empty = WorkoutVolumeBand(
    workingSets: 0,
    recommendedMin: 0,
    recommendedMax: 0,
    status: VolumeBandStatus.within,
    intensity: WorkoutIntensityLevel.moderate,
    exerciseCount: 0,
    exerciseMin: 0,
    exerciseMax: 0,
  );

  bool get hasData => recommendedMax > 0;

  /// O ile serii przekroczono górną granicę (0, gdy nie przekroczono).
  int get setsOverMax =>
      workingSets > recommendedMax ? workingSets - recommendedMax : 0;

  /// O ile serii brakuje do dolnej granicy (0, gdy nie brakuje).
  int get setsUnderMin =>
      workingSets < recommendedMin ? recommendedMin - workingSets : 0;

  /// Odchylenie w procentach względem naruszonej granicy (0 = w limicie).
  int get deviationPercent {
    if (setsOverMax > 0 && recommendedMax > 0) {
      return ((setsOverMax / recommendedMax) * 100).round();
    }
    if (setsUnderMin > 0 && recommendedMin > 0) {
      return ((setsUnderMin / recommendedMin) * 100).round();
    }
    return 0;
  }

  /// Np. „Aktualna objętość: 34 serie robocze".
  String get currentLabel =>
      'Aktualna objętość: $workingSets ${_workingSetWord(workingSets)}';

  /// Np. „Zalecany zakres dla intensywności umiarkowanej: 18–24 serie".
  String get recommendedLabel =>
      'Zalecany zakres dla intensywności ${intensity.label.toLowerCase()}: '
      '$recommendedMin–$recommendedMax ${_setWord(recommendedMax)}';

  /// Zdanie podsumowujące odchylenie (puste, gdy zestaw jest w limicie).
  String get deviationLabel {
    switch (status) {
      case VolumeBandStatus.within:
        return '';
      case VolumeBandStatus.slightlyAbove:
      case VolumeBandStatus.farAbove:
        return 'Przekroczono górny limit o $setsOverMax '
            '${_setWord(setsOverMax)} ($deviationPercent%).';
      case VolumeBandStatus.slightlyBelow:
      case VolumeBandStatus.farBelow:
        return 'Aktualna objętość jest o $deviationPercent% niższa niż dolna '
            'granica ustawiona dla intensywności ${intensity.label.toLowerCase()}.';
    }
  }

  static String _setWord(int value) =>
      _plural(value, 'seria', 'serie', 'serii');

  static String _workingSetWord(int value) => _plural(
        value,
        'seria robocza',
        'serie robocze',
        'serii roboczych',
      );

  static String _plural(int value, String one, String few, String many) {
    if (value == 1) return one;
    final mod10 = value % 10;
    final mod100 = value % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }
}

/// Liczy objętość zestawu i porównuje ją z zakresem zalecanym dla [intensity].
///
/// Zakres powstaje z limitów WSZYSTKICH partii obecnych w zestawie: dolna
/// granica to suma minimów, górna — suma maksimów. Dzięki temu dzień na dwie
/// partie ma naturalnie szersze pasmo niż dzień na jedną.
WorkoutVolumeBand describeWorkoutVolumeBand({
  required List<PlanItem> items,
  required Exercise Function(String id) resolve,
  String level = '',
  String goal = '',
  VolumeLimitsConfig config = VolumeLimitsConfig.standard,
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
}) {
  final groups = <MuscleGroup, int>{};
  final exerciseIds = <MuscleGroup, Set<String>>{};
  var workingSets = 0;
  for (final item in items) {
    final exercise = resolve(item.exerciseId);
    if (!isWorkingVolumeItem(item, exercise)) continue;
    final group = primaryMuscleGroupOf(exercise);
    final sets = item.sets < 1 ? 1 : item.sets;
    groups[group] = (groups[group] ?? 0) + sets;
    (exerciseIds[group] ??= <String>{}).add(item.exerciseId);
    workingSets += sets;
  }
  if (groups.isEmpty) return WorkoutVolumeBand.empty;

  var min = 0;
  var max = 0;
  var exerciseMin = 0;
  var exerciseMax = 0;
  var exerciseCount = 0;
  for (final group in groups.keys) {
    final limits = volumeLimitsFor(group,
        level: level, goal: goal, config: config, intensity: intensity);
    min += limits.minWorkingSets;
    max += limits.maxWorkingSets;
    exerciseMin += limits.exercises.min;
    exerciseMax += limits.exercises.max;
    exerciseCount += exerciseIds[group]?.length ?? 0;
  }

  // Próg „nieznacznie": 15% szerokości pasma (co najmniej 2 serie robocze),
  // żeby jedna dołożona seria nie od razu krzyczała „znacznie powyżej".
  final span = (max - min).abs();
  final tolerance = (span * 0.15).round().clamp(2, 8);
  final VolumeBandStatus status;
  if (workingSets < min) {
    status = (min - workingSets) <= tolerance
        ? VolumeBandStatus.slightlyBelow
        : VolumeBandStatus.farBelow;
  } else if (workingSets > max) {
    status = (workingSets - max) <= tolerance
        ? VolumeBandStatus.slightlyAbove
        : VolumeBandStatus.farAbove;
  } else {
    status = VolumeBandStatus.within;
  }

  return WorkoutVolumeBand(
    workingSets: workingSets,
    recommendedMin: min,
    recommendedMax: max,
    status: status,
    intensity: intensity,
    exerciseCount: exerciseCount,
    exerciseMin: exerciseMin,
    exerciseMax: exerciseMax,
  );
}
