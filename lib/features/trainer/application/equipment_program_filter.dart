/// Filtr programów pod dostępny sprzęt + automatyczne zamienniki (czysty Dart).
///
/// Etap: „Programy zgodne ze sprzętem". Ten moduł:
///  1. przechowuje JEDNOZNACZNE wymagania sprzętowe ćwiczeń programowych
///     ([kExerciseEquipmentOptions]) w modelu „dowolny z zestawów" (OR z ANDów),
///  2. sprawdza, czy ćwiczenie jest wykonalne przy sprzęcie użytkownika,
///  3. sprawdza kolizje z ograniczeniami ([LimitationProfile]),
///  4. dobiera zamiennik angażujący podobne mięśnie i pasujący do sprzętu
///     ([kExerciseSubstitutions] + awaryjny zamiennik z masy ciała),
///  5. przepuszcza cały [WorkoutPlan] przez filtr i raportuje zmiany,
///  6. waliduje gotowy plan (żadne niedozwolone ćwiczenie nie może przejść).
///
/// Postępy/ukończone dni NIE są tu ruszane — filtr działa na treści dni.
library;

import '../domain/trainer_models.dart';

// ============================================================================
// 1. Jednoznaczne wymagania sprzętowe (OR z zestawów AND).
//    `[{barbell, bench, rack}]` = wymaga sztangi I ławki I stojaków.
//    `[{barbell}, {dumbbell}]` = wystarczy sztanga ALBO hantle.
//    Brak wpisu = ćwiczenie z masy ciała (patrz fallback niżej).
// ============================================================================

const Map<String, List<Set<EquipmentType>>> kExerciseEquipmentOptions = {
  // ── Klatka ──
  'db_bench_press': [
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  'incline_db_press': [
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  'bench_press': [
    {EquipmentType.barbell, EquipmentType.bench, EquipmentType.rack}
  ],
  'incline_bench_press': [
    {EquipmentType.barbell, EquipmentType.bench, EquipmentType.rack}
  ],
  'db_fly': [
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  'db_pullover': [
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  'chest_dip': [
    {EquipmentType.pullUpBar}
  ],
  'dips': [
    {EquipmentType.pullUpBar}
  ],
  // ── Barki ──
  'db_shoulder_press': [
    {EquipmentType.dumbbell}
  ],
  'shoulder_press': [
    {EquipmentType.barbell},
    {EquipmentType.dumbbell}
  ],
  'arnold_press': [
    {EquipmentType.dumbbell}
  ],
  'upright_row': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'lateral_raise': [
    {EquipmentType.dumbbell},
    {EquipmentType.cable}
  ],
  'front_raise': [
    {EquipmentType.dumbbell}
  ],
  'rear_delt_fly': [
    {EquipmentType.dumbbell}
  ],
  'db_shrug': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'face_pull': [
    {EquipmentType.cable},
    {EquipmentType.resistanceBand}
  ],
  // ── Ręce ──
  'hammer_curl': [
    {EquipmentType.dumbbell}
  ],
  'barbell_curl': [
    {EquipmentType.barbell}
  ],
  'bicep_curl': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'incline_db_curl': [
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  'concentration_curl': [
    {EquipmentType.dumbbell}
  ],
  'overhead_triceps_ext': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'triceps_kickback': [
    {EquipmentType.dumbbell}
  ],
  'triceps_extension': [
    {EquipmentType.dumbbell},
    {EquipmentType.cable},
    {EquipmentType.resistanceBand}
  ],
  'close_grip_bench': [
    {EquipmentType.barbell, EquipmentType.bench}
  ],
  'bench_dip': [
    {EquipmentType.bench}
  ],
  'skullcrusher': [
    {EquipmentType.barbell, EquipmentType.bench},
    {EquipmentType.dumbbell, EquipmentType.bench}
  ],
  // ── Przedramiona ──
  'wrist_curl': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'reverse_wrist_curl': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'reverse_curl': [
    {EquipmentType.barbell},
    {EquipmentType.dumbbell}
  ],
  'wrist_roller': [
    {EquipmentType.barbell},
    {EquipmentType.dumbbell}
  ],
  'farmers_carry': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell},
    {EquipmentType.kettlebell}
  ],
  'dead_hang': [
    {EquipmentType.pullUpBar}
  ],
  // ── Plecy ──
  'bent_over_row': [
    {EquipmentType.barbell}
  ],
  'one_arm_db_row': [
    {EquipmentType.dumbbell}
  ],
  'pendlay_row': [
    {EquipmentType.barbell}
  ],
  'chin_up': [
    {EquipmentType.pullUpBar}
  ],
  'pullup': [
    {EquipmentType.pullUpBar}
  ],
  'inverted_row': [
    {EquipmentType.pullUpBar}
  ],
  'lat_pulldown': [
    {EquipmentType.cable},
    {EquipmentType.machine}
  ],
  'row': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell},
    {EquipmentType.cable}
  ],
  'straight_arm_pulldown': [
    {EquipmentType.cable},
    {EquipmentType.resistanceBand}
  ],
  'back_extension': [
    {EquipmentType.bench}
  ],
  // ── Nogi ──
  'squat': [
    {EquipmentType.barbell, EquipmentType.rack}
  ],
  'front_squat': [
    {EquipmentType.barbell, EquipmentType.rack}
  ],
  'deadlift': [
    {EquipmentType.barbell}
  ],
  'romanian_deadlift_db': [
    {EquipmentType.dumbbell},
    {EquipmentType.barbell}
  ],
  'goblet_squat': [
    {EquipmentType.dumbbell},
    {EquipmentType.kettlebell}
  ],
  'step_up': [
    {EquipmentType.step},
    {EquipmentType.bench}
  ],
  'hip_thrust': [
    {EquipmentType.bench}
  ],
  'seated_calf_raise': [
    {EquipmentType.dumbbell}
  ],
};

// ============================================================================
// 2. Łańcuchy zamienników (od najbliższego do awaryjnego z masy ciała).
//    Filtr bierze PIERWSZY dostępny + bezpieczny, którego jeszcze nie użyto.
// ============================================================================

const Map<String, List<String>> kExerciseSubstitutions = {
  // Klatka
  'bench_press': [
    'db_bench_press',
    'decline_pushup',
    'pushup',
    'diamond_pushup'
  ],
  'incline_bench_press': [
    'incline_db_press',
    'db_bench_press',
    'pike_pushup',
    'pushup'
  ],
  'db_bench_press': ['bench_press', 'decline_pushup', 'pushup'],
  'incline_db_press': ['incline_bench_press', 'pike_pushup', 'pushup'],
  'chest_dip': ['dips', 'decline_pushup', 'diamond_pushup', 'pushup'],
  'dips': ['chest_dip', 'diamond_pushup', 'close_grip_bench', 'pushup'],
  'db_fly': ['chest_dip', 'incline_pushup', 'pushup'],
  'db_pullover': ['one_arm_db_row', 'pushup'],
  // Barki
  'db_shoulder_press': ['shoulder_press', 'arnold_press', 'pike_pushup'],
  'shoulder_press': ['db_shoulder_press', 'arnold_press', 'pike_pushup'],
  'arnold_press': ['db_shoulder_press', 'shoulder_press', 'pike_pushup'],
  'upright_row': ['db_shrug', 'lateral_raise', 'pike_pushup'],
  'lateral_raise': ['front_raise', 'rear_delt_fly', 'pike_pushup'],
  'front_raise': ['lateral_raise', 'pike_pushup'],
  'rear_delt_fly': ['face_pull', 'superman', 'thread_the_needle'],
  'db_shrug': ['upright_row', 'farmers_carry', 'superman'],
  'face_pull': ['rear_delt_fly', 'inverted_row', 'superman'],
  // Ręce
  'hammer_curl': [
    'bicep_curl',
    'barbell_curl',
    'concentration_curl',
    'chin_up'
  ],
  'barbell_curl': [
    'bicep_curl',
    'hammer_curl',
    'concentration_curl',
    'chin_up'
  ],
  'bicep_curl': [
    'hammer_curl',
    'barbell_curl',
    'concentration_curl',
    'chin_up'
  ],
  'incline_db_curl': [
    'hammer_curl',
    'concentration_curl',
    'barbell_curl',
    'chin_up'
  ],
  'concentration_curl': ['hammer_curl', 'bicep_curl', 'chin_up'],
  'close_grip_bench': [
    'diamond_pushup',
    'dips',
    'bench_dip',
    'triceps_kickback'
  ],
  'skullcrusher': [
    'overhead_triceps_ext',
    'triceps_kickback',
    'diamond_pushup',
    'bench_dip'
  ],
  'overhead_triceps_ext': [
    'triceps_kickback',
    'skullcrusher',
    'diamond_pushup',
    'bench_dip'
  ],
  'triceps_kickback': ['overhead_triceps_ext', 'diamond_pushup', 'bench_dip'],
  'triceps_extension': [
    'triceps_kickback',
    'overhead_triceps_ext',
    'diamond_pushup',
    'bench_dip'
  ],
  'bench_dip': ['diamond_pushup', 'chest_dip'],
  // Przedramiona
  'wrist_curl': ['reverse_wrist_curl', 'farmers_carry', 'dead_hang'],
  'reverse_wrist_curl': ['wrist_curl', 'reverse_curl', 'farmers_carry'],
  'reverse_curl': ['hammer_curl', 'wrist_curl', 'farmers_carry'],
  'wrist_roller': ['wrist_curl', 'farmers_carry', 'dead_hang'],
  'farmers_carry': ['dead_hang', 'wall_sit'],
  'dead_hang': ['farmers_carry', 'wall_sit'],
  // Plecy
  'lat_pulldown': [
    'one_arm_db_row',
    'bent_over_row',
    'inverted_row',
    'superman'
  ],
  'pullup': ['one_arm_db_row', 'bent_over_row', 'inverted_row', 'superman'],
  'chin_up': [
    'one_arm_db_row',
    'bent_over_row',
    'hammer_curl',
    'inverted_row',
    'superman'
  ],
  'inverted_row': ['one_arm_db_row', 'bent_over_row', 'superman'],
  'bent_over_row': [
    'one_arm_db_row',
    'pendlay_row',
    'inverted_row',
    'superman'
  ],
  'pendlay_row': [
    'bent_over_row',
    'one_arm_db_row',
    'inverted_row',
    'superman'
  ],
  'one_arm_db_row': ['bent_over_row', 'inverted_row', 'superman'],
  'row': ['one_arm_db_row', 'bent_over_row', 'inverted_row', 'superman'],
  'straight_arm_pulldown': ['db_pullover', 'one_arm_db_row', 'superman'],
  'back_extension': ['superman', 'glute_bridge'],
  // Nogi
  'squat': ['front_squat', 'goblet_squat', 'bulgarian_split_squat', 'wall_sit'],
  'front_squat': ['squat', 'goblet_squat', 'bulgarian_split_squat', 'wall_sit'],
  'deadlift': ['romanian_deadlift_db', 'glute_bridge', 'back_extension'],
  'romanian_deadlift_db': ['deadlift', 'glute_bridge', 'back_extension'],
  'goblet_squat': ['squat', 'front_squat', 'bulgarian_split_squat', 'wall_sit'],
  'step_up': ['reverse_lunge', 'walking_lunge', 'bulgarian_split_squat'],
  'hip_thrust': ['glute_bridge', 'romanian_deadlift_db'],
  'seated_calf_raise': ['calf_raise', 'tibialis_raise'],
};

/// Awaryjny zamiennik z masy ciała wg głównej partii (zawsze dostępny).
const Map<MuscleGroup, String> kBodyweightFallbackByMuscle = {
  MuscleGroup.chest: 'pushup',
  MuscleGroup.back: 'superman',
  MuscleGroup.shoulders: 'pike_pushup',
  MuscleGroup.biceps: 'plank',
  MuscleGroup.triceps: 'diamond_pushup',
  MuscleGroup.forearms: 'plank',
  MuscleGroup.core: 'plank',
  MuscleGroup.quadriceps: 'bulgarian_split_squat',
  MuscleGroup.hamstrings: 'glute_bridge',
  MuscleGroup.glutes: 'glute_bridge',
  MuscleGroup.calves: 'calf_raise',
  MuscleGroup.fullBody: 'mountain_climber',
  MuscleGroup.cardio: 'march_steady',
  MuscleGroup.other: 'plank',
};

// ============================================================================
// 3. Ograniczenia — które ćwiczenia są niebezpieczne przy danym ograniczeniu.
// ============================================================================

const Set<String> _jumpExerciseIds = {
  'burpee',
  'jumping_jack',
  'high_knees',
  'skater_hops',
  'butt_kicks',
  'jump_rope',
};

const Set<String> _runningExerciseIds = {
  'run',
  'butt_kicks',
  'high_knees',
};

const Set<String> _kneeStressIds = {
  'squat',
  'front_squat',
  'goblet_squat',
  'bulgarian_split_squat',
  'walking_lunge',
  'reverse_lunge',
  'cossack_squat',
  'step_up',
  'wall_sit',
  'burpee',
  'skater_hops',
  'jump_rope',
};

const Set<String> _lowerBackStressIds = {
  'deadlift',
  'romanian_deadlift_db',
  'bent_over_row',
  'pendlay_row',
  'back_extension',
  'superman',
  'good_morning',
};

const Set<String> _overheadIds = {
  'shoulder_press',
  'db_shoulder_press',
  'arnold_press',
  'pike_pushup',
  'overhead_triceps_ext',
  'upright_row',
};

const Set<String> _lyingIds = {
  'bench_press',
  'incline_bench_press',
  'db_bench_press',
  'incline_db_press',
  'db_fly',
  'db_pullover',
  'skullcrusher',
  'glute_bridge',
  'hip_thrust',
  'crunch',
  'crunches_legs_raised',
  'leg_raise',
  'flutter_kicks',
  'hollow_hold',
  'cobra_stretch',
  'superman',
};

/// Czy ćwiczenie koliduje z którymkolwiek ograniczeniem użytkownika.
bool exerciseViolatesLimitation(Exercise exercise, LimitationProfile limits) {
  if (limits.isEmpty) return false;
  final id = exercise.id;
  final text =
      '${exercise.name} ${exercise.category} ${exercise.muscles.join(' ')}'
          .toLowerCase();

  for (final flag in limits.flags) {
    switch (flag) {
      case TrainingLimitation.noJumps:
        if (_jumpExerciseIds.contains(id) ||
            text.contains('skok') ||
            text.contains('podskok') ||
            text.contains('wybicie') ||
            text.contains('jump') ||
            text.contains('pajac')) {
          return true;
        }
        break;
      case TrainingLimitation.noRunning:
        if (_runningExerciseIds.contains(id) ||
            text.contains('bieg') ||
            text.contains('run')) {
          return true;
        }
        break;
      case TrainingLimitation.knees:
        if (_kneeStressIds.contains(id) ||
            text.contains('przysiad') ||
            text.contains('squat') ||
            text.contains('wykrok') ||
            text.contains('lunge') ||
            text.contains('skok')) {
          return true;
        }
        break;
      case TrainingLimitation.lowerBack:
        if (_lowerBackStressIds.contains(id) ||
            text.contains('martwy') ||
            text.contains('deadlift') ||
            text.contains('wiosł') ||
            text.contains('hiperekst') ||
            text.contains('skłon')) {
          return true;
        }
        break;
      case TrainingLimitation.overhead:
        if (_overheadIds.contains(id) ||
            text.contains('nad głow') ||
            text.contains('nad glow') ||
            text.contains('overhead')) {
          return true;
        }
        break;
      case TrainingLimitation.noLying:
        if (_lyingIds.contains(id) ||
            text.contains('leż') ||
            text.contains('lying')) {
          return true;
        }
        break;
    }
  }

  // Własny tekst — proste dopasowanie słów kluczowych (biodra, nadgarstki…).
  final custom = limits.customText.toLowerCase().trim();
  if (custom.isNotEmpty) {
    if ((custom.contains('nadgarst') || custom.contains('wrist')) &&
        (text.contains('nadgarst') ||
            text.contains('wyciskan') ||
            text.contains('pomp'))) {
      return true;
    }
    if ((custom.contains('łokie') || custom.contains('lokie')) &&
        (text.contains('prostowanie') || text.contains('uginanie'))) {
      return true;
    }
  }
  return false;
}

// ============================================================================
// 4. Dostępność sprzętowa ćwiczenia.
// ============================================================================

/// Zestawy sprzętu (OR z ANDów) wymagane przez ćwiczenie. Zamapowane wpisy mają
/// pierwszeństwo; w innym wypadku czytamy pole tekstowe (fallback zachowawczy).
List<Set<EquipmentType>> requiredEquipmentOptionsFor(Exercise exercise) {
  final mapped = kExerciseEquipmentOptions[exercise.id];
  if (mapped != null) return mapped;
  final types = exercise.equipmentTypes;
  // Nieznane wymaganie (tylko „inny sprzęt") NIE jest automatyczną zgodą —
  // przechodzi tylko przy pełnej siłowni (owned zawiera „other").
  if (types.length == 1 && types.contains(EquipmentType.other)) {
    return const [
      {EquipmentType.other}
    ];
  }
  final parsed = types
      .where((t) =>
          t != EquipmentType.bodyweight &&
          t != EquipmentType.mat &&
          t != EquipmentType.other)
      .toSet();
  return [parsed]; // pusty zestaw = z masy ciała (zawsze dostępne)
}

/// Czy ćwiczenie da się wykonać przy posiadanym [owned] sprzęcie.
bool isExerciseAvailable(Exercise exercise, Set<EquipmentType> owned) {
  for (final option in requiredEquipmentOptionsFor(exercise)) {
    if (owned.containsAll(option)) return true;
  }
  return false;
}

/// Faktycznie użyty (najtańszy dostępny) zestaw sprzętu — do podsumowania.
Set<EquipmentType> satisfiedEquipmentFor(
  Exercise exercise,
  Set<EquipmentType> owned,
) {
  for (final option in requiredEquipmentOptionsFor(exercise)) {
    if (owned.containsAll(option)) return option;
  }
  return const <EquipmentType>{};
}

// ============================================================================
// 5. Dobór zamiennika.
// ============================================================================

/// Najlepszy zamiennik dla [original]: pierwszy z łańcucha, który jest dostępny,
/// bezpieczny i jeszcze nieużyty w danym dniu. Awaryjnie — ćwiczenie z masy
/// ciała pod główną partię. `null`, gdy nic sensownego nie ma.
String? bestSubstituteId(
  Exercise original,
  Set<EquipmentType> owned,
  LimitationProfile limits,
  Exercise Function(String id) resolve, {
  Set<String> exclude = const <String>{},
}) {
  bool ok(String id) {
    if (id == original.id || exclude.contains(id)) return false;
    final candidate = resolve(id);
    if (candidate.id != id) return false; // resolver nie zna id
    return isExerciseAvailable(candidate, owned) &&
        !exerciseViolatesLimitation(candidate, limits);
  }

  for (final id in kExerciseSubstitutions[original.id] ?? const <String>[]) {
    if (ok(id)) return id;
  }

  final group = original.muscleGroups.isNotEmpty
      ? original.muscleGroups.first
      : MuscleGroup.other;
  final fallback = kBodyweightFallbackByMuscle[group];
  if (fallback != null && ok(fallback)) return fallback;
  if (ok('plank')) return 'plank';
  return null;
}

// ============================================================================
// 6. Filtr całego planu + raport.
// ============================================================================

/// Wynik dopasowania planu do sprzętu: nowy plan + statystyki dla UI.
class EquipmentPlanReport {
  const EquipmentPlanReport({
    required this.usedEquipment,
    required this.substitutedCount,
    required this.removedCount,
    required this.profile,
    required this.limits,
  });

  /// Sprzęt faktycznie użyty w dopasowanym planie (bez masy ciała/maty).
  final Set<EquipmentType> usedEquipment;

  /// Liczba ćwiczeń zamienionych z powodu braku sprzętu lub ograniczeń.
  final int substitutedCount;

  /// Liczba ćwiczeń usuniętych (gdy nie było żadnego sensownego zamiennika).
  final int removedCount;

  final EquipmentProfile profile;
  final LimitationProfile limits;

  bool get usedMachinesOrCables =>
      usedEquipment.contains(EquipmentType.machine) ||
      usedEquipment.contains(EquipmentType.cable);

  /// Czytelne informacje dla użytkownika (pkt 6 specyfikacji).
  List<String> get notes {
    final result = <String>[
      'Program dopasowany do sprzętu: ${profile.ownedSummary}.',
    ];
    if (!usedMachinesOrCables) {
      result.add('Nie użyto maszyn ani wyciągów.');
    }
    if (substitutedCount > 0) {
      result.add(
          'Zastąpiono $substitutedCount ${_exercisesWord(substitutedCount)} z powodu braku sprzętu lub ograniczeń.');
    }
    if (removedCount > 0) {
      result.add(
          'Usunięto $removedCount ${_exercisesWord(removedCount)} bez bezpiecznego zamiennika.');
    }
    if (!limits.isEmpty) {
      final labels = limits.flags.map((f) => f.label.toLowerCase()).toList();
      if (labels.isNotEmpty) {
        result.add('Uwzględniono ograniczenia: ${labels.join(', ')}.');
      }
    }
    return result;
  }
}

String _exercisesWord(int n) {
  if (n == 1) return 'ćwiczenie';
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'ćwiczenia';
  }
  return 'ćwiczeń';
}

class EquipmentFilteredPlan {
  const EquipmentFilteredPlan({required this.plan, required this.report});
  final WorkoutPlan plan;
  final EquipmentPlanReport report;
}

/// Buduje pozycję z podmienionym ćwiczeniem, dopasowując parametry do TYPU
/// zamiennika (czasowe vs serie/powtórzenia) i dopisując notatkę archiwalną
/// o oryginale — bez ruszania historii/logów użytkownika.
PlanItem _swapItem(PlanItem item, Exercise original, Exercise replacement) {
  final baseNote = item.note.trim();
  final swapNote = 'zamiennik za: ${original.name} (brak sprzętu/ograniczenie)';
  final note = baseNote.isEmpty ? swapNote : '$baseNote · $swapNote';
  if (replacement.defaultDurationSec > 0) {
    return item.copyWith(
      exerciseId: replacement.id,
      reps: 0,
      durationSec: item.durationSec > 0
          ? item.durationSec
          : replacement.defaultDurationSec,
      suggestedWeightKg: 0,
      note: note,
    );
  }
  return item.copyWith(
    exerciseId: replacement.id,
    reps: item.reps > 0
        ? item.reps
        : (replacement.defaultReps > 0 ? replacement.defaultReps : 12),
    durationSec: 0,
    suggestedWeightKg: 0,
    note: note,
  );
}

/// Przepuszcza cały plan przez filtr sprzętu i ograniczeń, podmieniając
/// niedostępne ćwiczenia na zamienniki. Zwraca nowy plan + raport.
///
/// [completedDays] / [id] / [isActive] itd. są ZACHOWYWANE przez wywołującego
/// (ta funkcja nie dotyka postępów — operuje tylko na `days`).
EquipmentFilteredPlan applyEquipmentToPlan(
  WorkoutPlan plan,
  EquipmentProfile profile,
  LimitationProfile limits,
  Exercise Function(String id) resolve, {
  int fromDayIndex = 0,
}) {
  final owned = profile.resolveOwned();
  final usedEquipment = <EquipmentType>{};
  var substituted = 0;
  var removed = 0;

  final newDays = <WorkoutDay>[];
  for (var dayIndex = 0; dayIndex < plan.days.length; dayIndex++) {
    final day = plan.days[dayIndex];
    // Dni sprzed punktu zmiany zostają bajt w bajt (ochrona postępu).
    if (dayIndex < fromDayIndex) {
      newDays.add(day);
      // policz użyty sprzęt też w tych dniach (spójne podsumowanie)
      for (final item in day.items) {
        final ex = resolve(item.exerciseId);
        usedEquipment.addAll(satisfiedEquipmentFor(ex, owned));
      }
      continue;
    }

    final usedIds = <String>{};
    final newItems = <PlanItem>[];
    for (final item in day.items) {
      final exercise = resolve(item.exerciseId);
      final available = isExerciseAvailable(exercise, owned) &&
          !exerciseViolatesLimitation(exercise, limits);
      if (available) {
        if (usedIds.add(item.exerciseId)) {
          newItems.add(item);
          usedEquipment.addAll(satisfiedEquipmentFor(exercise, owned));
        }
        continue;
      }
      final subId = bestSubstituteId(
        exercise,
        owned,
        limits,
        resolve,
        exclude: usedIds,
      );
      if (subId == null) {
        removed++;
        continue;
      }
      final replacement = resolve(subId);
      if (!usedIds.add(subId)) {
        // zamiennik już w dniu — usuń pozycję zamiast duplikować
        removed++;
        continue;
      }
      newItems.add(_swapItem(item, exercise, replacement));
      usedEquipment.addAll(satisfiedEquipmentFor(replacement, owned));
      substituted++;
    }
    newDays.add(day.copyWith(items: newItems));
  }

  usedEquipment.removeAll(kAlwaysAvailableEquipment);
  final report = EquipmentPlanReport(
    usedEquipment: usedEquipment,
    substitutedCount: substituted,
    removedCount: removed,
    profile: profile,
    limits: limits,
  );
  return EquipmentFilteredPlan(
      plan: plan.copyWith(days: newDays), report: report);
}

// ============================================================================
// 7. Walidacja gotowego planu (żadne niedozwolone ćwiczenie nie przechodzi).
// ============================================================================

class PlanEquipmentIssue {
  const PlanEquipmentIssue({
    required this.dayIndex,
    required this.exerciseId,
    required this.reason,
  });
  final int dayIndex;
  final String exerciseId;
  final String reason;
}

/// Sprawdza, czy w planie nie ma ćwiczeń wymagających niedostępnego sprzętu
/// ani kolidujących z ograniczeniami. Pusta lista = plan bezpieczny.
List<PlanEquipmentIssue> validatePlanEquipment(
  WorkoutPlan plan,
  EquipmentProfile profile,
  LimitationProfile limits,
  Exercise Function(String id) resolve, {
  int fromDayIndex = 0,
}) {
  final owned = profile.resolveOwned();
  final issues = <PlanEquipmentIssue>[];
  for (var dayIndex = fromDayIndex; dayIndex < plan.days.length; dayIndex++) {
    for (final item in plan.days[dayIndex].items) {
      final exercise = resolve(item.exerciseId);
      if (!isExerciseAvailable(exercise, owned)) {
        issues.add(PlanEquipmentIssue(
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          reason: 'wymaga niedostępnego sprzętu',
        ));
      } else if (exerciseViolatesLimitation(exercise, limits)) {
        issues.add(PlanEquipmentIssue(
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          reason: 'koliduje z ograniczeniem',
        ));
      }
    }
  }
  return issues;
}
