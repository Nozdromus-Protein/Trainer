/// Katalog 30-dniowych programów treningowych (Etap: programy).
///
/// Czysty Dart. Programy są generowane proceduralnie z pul ćwiczeń, z płynną
/// progresją i logiką regeneracji (dni treningowe, techniczne, mobilność oraz
/// aktywna regeneracja / odpoczynek). Dzięki temu nie ma tysięcy „hardcoded"
/// widgetów — modele danych opisują treść, a UI tylko ją renderuje.
///
/// Każdy program to [WorkoutPlan] z 30 [WorkoutDay]. Progresja rośnie stopniowo
/// (serie / czas / powtórzenia) tydzień po tygodniu, bez skoków trudności.
library;

import '../domain/exercise_intensity.dart';
import '../domain/trainer_models.dart';

/// Metadane programu do UI (karta, kolor, główne partie, sprzęt).
class WorkoutProgramMeta {
  const WorkoutProgramMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.mainMuscles,
    required this.equipment,
    this.kind = 'Siłowy',
    this.iconKey = 'generic',
    this.durationDays = 30,
  });

  final String id;
  final String title;
  final String subtitle;
  final int accentColor;
  final List<String> mainMuscles;
  final List<String> equipment;

  /// Typ programu do UI: „Siłowy", „Sylwetka / core", „Mieszany"…
  final String kind;

  /// Klucz ikony — mapowany na IconData w warstwie UI (plik pozostaje czystym Dartem).
  final String iconKey;

  /// Długość programu w dniach (kafelek pokazuje „30 dni").
  final int durationDays;
}

/// Lista programów w stałej kolejności (przewijanie lewo↔prawo w UI).
const List<WorkoutProgramMeta> kWorkoutProgramCatalog = [
  WorkoutProgramMeta(
    id: 'program_core',
    title: 'Brzuch i core',
    subtitle: 'Silny, wyrzeźbiony brzuch i skośne',
    accentColor: 0xFF24D6A3,
    mainMuscles: ['Brzuch', 'Skośne', 'Core'],
    equipment: ['Masa ciała', 'Hantle (opcjonalnie)', 'Mata'],
    kind: 'Sylwetka / core',
    iconKey: 'core',
  ),
  WorkoutProgramMeta(
    id: 'program_chest',
    title: 'Klatka piersiowa',
    subtitle: 'Masa i siła klatki',
    accentColor: 0xFFFF6B6B,
    mainMuscles: ['Klatka', 'Triceps', 'Barki przód'],
    equipment: ['Hantle', 'Sztanga', 'Ławka', 'Barierki'],
    kind: 'Siłowy',
    iconKey: 'chest',
  ),
  WorkoutProgramMeta(
    id: 'program_arms',
    title: 'Ramiona: biceps i triceps',
    subtitle: 'Biceps, triceps i mocny chwyt',
    accentColor: 0xFFB388FF,
    mainMuscles: ['Biceps', 'Triceps', 'Przedramiona'],
    equipment: ['Hantle', 'Sztanga', 'Ławka', 'Barierki'],
    kind: 'Siłowy',
    iconKey: 'arms',
  ),
  WorkoutProgramMeta(
    id: 'program_shoulders',
    title: 'Barki',
    subtitle: 'Okrągłe barki: przód, bok, tył',
    accentColor: 0xFF58A6FF,
    mainMuscles: ['Barki przód', 'Barki tył', 'Kaptury'],
    equipment: ['Hantle', 'Sztanga', 'Ławka regulowana'],
    kind: 'Siłowy',
    iconKey: 'shoulders',
  ),
  WorkoutProgramMeta(
    id: 'program_back',
    title: 'Plecy',
    subtitle: 'Szeroki, silny grzbiet',
    accentColor: 0xFFFFB86B,
    mainMuscles: ['Najszerszy', 'Górne plecy', 'Dolny grzbiet'],
    equipment: ['Hantle', 'Sztanga', 'Ławka', 'Barierki'],
    kind: 'Siłowy',
    iconKey: 'back',
  ),
  WorkoutProgramMeta(
    id: 'program_forearms',
    title: 'Przedramiona i chwyt',
    subtitle: 'Chwyt i grube przedramiona',
    accentColor: 0xFF7FD1AE,
    mainMuscles: ['Zginacze', 'Prostowniki', 'Chwyt'],
    equipment: ['Hantle', 'Sztanga'],
    kind: 'Siłowy',
    iconKey: 'forearms',
  ),
  WorkoutProgramMeta(
    id: 'program_legs',
    title: 'Nogi',
    subtitle: 'Uda, pośladki, łydki, stabilizacja',
    accentColor: 0xFFFF9E64,
    mainMuscles: ['Czworogłowe', 'Dwugłowe', 'Pośladki', 'Łydki'],
    equipment: ['Hantle', 'Sztanga', 'Ławka', 'Barierki'],
    kind: 'Siłowy',
    iconKey: 'legs',
  ),
];

/// Definicja pul ćwiczeń pod jeden program.
class _ProgramTemplate {
  const _ProgramTemplate({
    required this.id,
    required this.name,
    required this.note,
    required this.goal,
    required this.warmup,
    required this.main,
    required this.accessory,
    required this.finisher,
    required this.stretch,
    this.timedStyle = false,
  });

  final String id;
  final String name;
  final String note;
  final String goal;

  /// Rozgrzewka (czasowe).
  final List<String> warmup;

  /// Ćwiczenia główne (compound / izolacja — serie/powtórzenia lub czasowe dla core).
  final List<String> main;

  /// Ćwiczenia pomocnicze.
  final List<String> accessory;

  /// Wykończenie (core / kondycja).
  final List<String> finisher;

  /// Rozciąganie / mobilność (czasowe).
  final List<String> stretch;

  /// Program „czasowy" (brzuch) — dni treningowe budowane z dużej puli ćwiczeń czasowych.
  final bool timedStyle;
}

// Pule rozgrzewkowe POD PARTIE. Rozgrzewka ma przygotować to, co za chwilę
// pracuje — wymachy nóg przed wyciskaniem tylko kradną czas. Każdy program ma
// więc własną pulę; wspólnej puli ogólnej nie ma, bo nie miała odbiorcy.
const List<String> _warmupPush = [ // klatka: wyciskania, pompki, dipy
  'arm_circles',
  'scapular_pushup',
  'doorway_chest_opener',
  'band_pull_apart',
  'wall_slides',
];
const List<String> _warmupShoulders = [ // barki: praca nad głową, rotatory
  'arm_circles',
  'wall_slides',
  'shoulder_external_rotation',
  'band_pull_apart',
  'scapular_pushup',
];
const List<String> _warmupPull = [ // plecy: podciąganie, wiosłowanie
  'thoracic_rotation',
  'band_pull_apart',
  'scapular_pull',
  'arm_circles',
  'cat_cow',
];
const List<String> _warmupArms = [ // ramiona: łokcie, nadgarstki, obręcz
  'arm_circles',
  'wrist_circles',
  'band_pull_apart',
  'scapular_pushup',
];
const List<String> _warmupForearms = [ // przedramiona: chwyt i nadgarstki
  'wrist_circles',
  'arm_circles',
  'band_pull_apart',
];
const List<String> _warmupLegs = [ // nogi: biodra, kolana, kostki
  'leg_swings',
  'hip_circles',
  'ankle_rocks',
  'world_greatest_stretch',
];
const List<String> _warmupCore = [ // brzuch: tułów i biodra
  'torso_twist',
  'cat_cow',
  'hip_circles',
  'world_greatest_stretch',
];


// Pule ROZCIĄGANIA pod partie. Rozciąganie nie wchodzi już do dni treningowych
// (robiło z nich dziury) — ma własne, krótkie zestawy w sekcji „Rozciąganie".
const List<String> _stretchPush = [
  'chest_doorway_stretch',
  'shoulder_cross_stretch',
  'triceps_stretch',
  'thread_the_needle',
  'child_pose',
];
const List<String> _stretchPull = [
  'child_pose',
  'thread_the_needle',
  'cat_cow',
  'downward_dog',
  'lying_twist_stretch_left',
];
const List<String> _stretchShoulders = [
  'shoulder_cross_stretch',
  'chest_doorway_stretch',
  'neck_stretch',
  'thread_the_needle',
  'child_pose',
];
const List<String> _stretchArms = [
  'triceps_stretch',
  'forearm_stretch',
  'shoulder_cross_stretch',
  'child_pose',
  'cat_cow',
];
const List<String> _stretchForearms = [
  'forearm_stretch',
  'triceps_stretch',
  'shoulder_cross_stretch',
  'neck_stretch',
];
const List<String> _stretchLegs = [
  'quad_stretch',
  'hamstring_stretch',
  'hip_flexor_stretch',
  'calf_stretch',
  'pigeon_pose',
  'downward_dog',
];
const List<String> _stretchCore = [
  'cobra_stretch',
  'child_pose',
  'cat_cow',
  'lying_twist_stretch_left',
  'lying_twist_stretch_right',
  'hip_flexor_stretch',
];

const Map<String, _ProgramTemplate> _templates = {
  'program_core': _ProgramTemplate(
    id: 'program_core',
    name: 'Brzuch i core',
    note:
        'Codzienna progresja brzucha i skośnych. Dni treningowe, technika, mobilność i aktywna regeneracja. W dalszych tygodniach dokładamy obciążenie (hantle).',
    goal: 'Sylwetka',
    timedStyle: true,
    warmup: _warmupCore,
    main: [
      'standing_bicycle_crunch',
      'flutter_kicks',
      'windshield_wipers',
      'plank_taps',
      'alt_v_up',
      'crunches_legs_raised',
      'plank_hip_dips',
      'crunch_90_90',
      'oblique_crunch_reach',
      'double_knees_to_chest',
      'side_crunch_left',
      'side_crunch_right',
    ],
    accessory: [
      'crunch',
      'leg_raise',
      'russian_twist',
      'plank',
      'side_plank',
      'hollow_hold',
      'mountain_climber'
    ],
    finisher: ['mountain_climber', 'high_knees', 'jumping_jack', 'burpee'],
    stretch: [
      'cobra_stretch',
      'child_pose',
      'cat_cow',
      'lying_twist_stretch_left',
      'lying_twist_stretch_right',
      'hip_flexor_stretch'
    ],
  ),
  'program_chest': _ProgramTemplate(
    id: 'program_chest',
    name: 'Klatka piersiowa',
    note:
        'Rozbudowa klatki: wyciskania sztangą i hantlami, rozpiętki, dipy. Progresja objętości i ciężaru z rozsądnym odpoczynkiem.',
    goal: 'Masa',
    warmup: _warmupPush,
    main: [
      'bench_press',
      'incline_bench_press',
      'db_bench_press',
      'incline_db_press',
      'chest_dip'
    ],
    accessory: [
      'db_fly',
      'db_pullover',
      'dips',
      'decline_pushup',
      'diamond_pushup'
    ],
    finisher: ['decline_pushup', 'diamond_pushup', 'pushup'],
    stretch: [
      'chest_doorway_stretch',
      'shoulder_cross_stretch',
      'triceps_stretch',
      'thread_the_needle',
      'child_pose'
    ],
  ),
  'program_arms': _ProgramTemplate(
    id: 'program_arms',
    name: 'Ramiona: biceps i triceps',
    note:
        'Biceps i triceps z przedramionami jako wsparcie. Naprzemienne dni siły i objętości, wykończenia i mobilność.',
    goal: 'Masa',
    warmup: _warmupArms,
    main: [
      'barbell_curl',
      'close_grip_bench',
      'hammer_curl',
      'skullcrusher',
      'incline_db_curl',
      'overhead_triceps_ext'
    ],
    accessory: [
      'bicep_curl',
      'triceps_extension',
      'concentration_curl',
      'triceps_kickback',
      'bench_dip',
      'reverse_curl'
    ],
    finisher: ['dips', 'bench_dip', 'dead_hang', 'farmers_carry'],
    stretch: [
      'triceps_stretch',
      'forearm_stretch',
      'shoulder_cross_stretch',
      'child_pose',
      'cat_cow'
    ],
  ),
  'program_shoulders': _ProgramTemplate(
    id: 'program_shoulders',
    name: 'Barki',
    note:
        'Przód, bok i tył barków plus kaptury jako wsparcie. Wyciskania, unoszenia i odwrotne rozpiętki z progresją.',
    goal: 'Masa',
    warmup: _warmupShoulders,
    main: [
      'shoulder_press',
      'db_shoulder_press',
      'arnold_press',
      'upright_row'
    ],
    accessory: [
      'lateral_raise',
      'rear_delt_fly',
      'front_raise',
      'db_shrug',
      'face_pull',
      'pike_pushup'
    ],
    finisher: ['pike_pushup', 'lateral_raise'],
    stretch: [
      'shoulder_cross_stretch',
      'chest_doorway_stretch',
      'neck_stretch',
      'thread_the_needle',
      'child_pose'
    ],
  ),
  'program_back': _ProgramTemplate(
    id: 'program_back',
    name: 'Plecy',
    note:
        'Najszerszy, górne i środkowe plecy, dolny grzbiet oraz kaptury. Podciągania, wiosłowania i prostowania tułowia.',
    goal: 'Masa',
    warmup: _warmupPull,
    main: [
      'pullup',
      'chin_up',
      'bent_over_row',
      'pendlay_row',
      'one_arm_db_row',
      'lat_pulldown'
    ],
    accessory: [
      'row',
      'db_shrug',
      'straight_arm_pulldown',
      'face_pull',
      'back_extension',
      'inverted_row'
    ],
    finisher: ['back_extension', 'dead_hang', 'superman'],
    stretch: [
      'child_pose',
      'thread_the_needle',
      'cat_cow',
      'downward_dog',
      'lying_twist_stretch_left'
    ],
  ),
  'program_forearms': _ProgramTemplate(
    id: 'program_forearms',
    name: 'Przedramiona i chwyt',
    note:
        'Zginacze, prostowniki, chwyt i stabilizacja nadgarstków. Krótsze, częste bodźce z rosnącą objętością.',
    goal: 'Siła',
    warmup: _warmupForearms,
    main: ['wrist_curl', 'reverse_wrist_curl', 'reverse_curl', 'wrist_roller'],
    accessory: [
      'hammer_curl',
      'bicep_curl',
      'reverse_curl',
      'wrist_curl',
      'reverse_wrist_curl'
    ],
    finisher: ['dead_hang', 'farmers_carry'],
    stretch: [
      'forearm_stretch',
      'triceps_stretch',
      'shoulder_cross_stretch',
      'neck_stretch'
    ],
  ),
  'program_legs': _ProgramTemplate(
    id: 'program_legs',
    name: 'Nogi',
    note:
        'Czworogłowe, dwugłowe, pośladki, łydki, przywodziciele i stabilizacja piszczeli. Przysiady, martwe ciągi i wykroki z progresją.',
    goal: 'Masa',
    warmup: _warmupLegs,
    main: [
      'squat',
      'deadlift',
      'front_squat',
      'romanian_deadlift_db',
      'bulgarian_split_squat',
      'goblet_squat'
    ],
    accessory: [
      'hip_thrust',
      'walking_lunge',
      'reverse_lunge',
      'step_up',
      'seated_calf_raise',
      'calf_raise',
      'cossack_squat'
    ],
    finisher: ['calf_raise', 'seated_calf_raise', 'tibialis_raise'],
    stretch: [
      'quad_stretch',
      'hamstring_stretch',
      'hip_flexor_stretch',
      'calf_stretch',
      'pigeon_pose',
      'downward_dog'
    ],
  ),
};

/// Charakter dnia w mikrocyklu tygodniowym.
enum _DayKind {
  strengthA,
  strengthB,
  technique,
  mobility,
  strengthC,
  conditioning,
  rest
}

/// Mapuje wewnętrzny charakter dnia na trwały [WorkoutDayKind] zapisywany
/// w planie — dzięki temu po wygenerowaniu programu nadal wiadomo, który dzień
/// jest ciężki (wcześniej ta wiedza ginęła wraz z generatorem).
WorkoutDayKind _kindOf(_DayKind kind) {
  switch (kind) {
    case _DayKind.strengthA:
    case _DayKind.strengthB:
    case _DayKind.strengthC:
      return WorkoutDayKind.strength;
    case _DayKind.technique:
      return WorkoutDayKind.technique;
    case _DayKind.mobility:
      return WorkoutDayKind.mobility;
    case _DayKind.conditioning:
      return WorkoutDayKind.conditioning;
    case _DayKind.rest:
      return WorkoutDayKind.rest;
  }
}

/// Rytm zestawu: SAME dni ciężkie, różniące się tylko charakterem obciążenia.
///
/// Odpoczynek wynika z rozkładu tygodnia (dni wolne), a odciążenie z tygodnia
/// deloadu — to on robi z treningu wersję lekką. Trzymanie dni „technicznych"
/// i „kondycyjnych" wewnątrz zestawu robiło z programu dziury: dzień klatki
/// potrafił zejść na pompki i plank, mimo że użytkownik ma sztangę i hantle.
const List<_DayKind> _weekRhythm = [
  _DayKind.strengthA, // najcięższy bój — niskie powtórzenia, długa przerwa
  _DayKind.strengthC, // hipertrofia, duża objętość
  _DayKind.strengthB, // objętość, więcej powtórzeń
  _DayKind.strengthA,
  _DayKind.strengthC,
];

class _LevelProfile {
  const _LevelProfile(
      this.baseSets, this.strengthRest, this.coreRest, this.repShift);
  final int baseSets;
  final int strengthRest;
  final int coreRest;
  final int repShift; // korekta powtórzeń względem domyślnych
}

_LevelProfile _profileFor(String level) {
  final normalized = normalizeTrainingLevel(level);
  switch (normalized) {
    case 'Zaawansowany':
      return const _LevelProfile(4, 75, 20, -1);
    case 'Średniozaawansowany':
      return const _LevelProfile(3, 75, 20, 0);
    default:
      return const _LevelProfile(3, 90, 25, 1);
  }
}

/// Ranga poziomu: początkujący 0, średniozaawansowany 1, zaawansowany 2.
///
/// UWAGA: kolejność sprawdzeń jest istotna — „śred" trzeba sprawdzić PRZED
/// „zaaw", bo słowo „średnioza(zaaw)ansowany" zawiera podciąg „zaaw". Naiwne
/// `contains('zaaw')` na pierwszym miejscu (jak w [normalizeTrainingLevel])
/// zaklasyfikowałoby średniozaawansowanego jako zaawansowanego.
int _levelRank(String level) {
  final n = level.trim().toLowerCase();
  if (n.contains('śred') ||
      n.contains('sred') ||
      n.contains('inter') ||
      n.contains('mid')) {
    return 1;
  }
  if (n.contains('zaaw') || n.contains('adv')) return 2;
  return 0;
}

/// Filtruje pulę ćwiczeń pod poziom użytkownika. Początkujący NIE dostaje
/// ćwiczeń oznaczonych „Zaawansowany" (chyba że inaczej pula byłaby pusta) —
/// wcześniej dobór ćwiczeń nie patrzył na poziom w ogóle. Średniozaawansowany
/// i zaawansowany dostają pełną pulę, więc istniejące programy tych poziomów
/// pozostają identyczne (progresja/determinizm bez zmian).
///
/// WYJĄTEK: jeśli po odsianiu poziomu w puli nie zostaje ANI JEDEN ruch
/// z obciążeniem zewnętrznym, wpuszczamy obciążone z powrotem. U nich trudność
/// reguluje CIĘŻAR, a nie sam ruch — bez tego początkujący ze sztangą i hantlami
/// dostawał zestaw czysto kalisteniczny.
List<String> _forLevel(
  List<String> pool,
  Exercise Function(String) resolve,
  int userRank,
) {
  if (userRank >= 1) return pool; // średnio/zaawansowany — pełna pula
  final within = [
    for (final id in pool)
      if (_levelRank(resolve(id).level) <= 1) id,
  ];
  if (within.isEmpty) return pool;
  if (within.any((id) => _usesLoad(resolve(id).equipment))) return within;
  final loaded = [
    for (final id in pool)
      if (_usesLoad(resolve(id).equipment)) id,
  ];
  return loaded.isEmpty ? within : [...within, ...loaded];
}

/// Pula uporządkowana pod INTENSYWNOŚĆ: najpierw ruchy z obciążeniem
/// zewnętrznym (od najcięższego wg [exerciseIntensityScore]), potem reszta.
///
/// [offset] rotuje start w obrębie części obciążonej — dzień w dzień zmieniają
/// się ćwiczenia, ale pierwsza pozycja zawsze jest ciężka. To tu leżał problem
/// „w dniu klatki widzę tylko pompki": zwykłe [_pick] brało z puli po kolei,
/// więc co kilka dni zestaw zaczynał się od wariantu kalistenicznego.
List<String> _pickIntense(
  List<String> pool,
  int count,
  int offset,
  Exercise Function(String) resolve,
) {
  if (pool.isEmpty) return const [];
  final ranked = [...pool]
    ..sort((a, b) => exerciseIntensityScore(resolve(b))
        .compareTo(exerciseIntensityScore(resolve(a))));
  final loaded = [
    for (final id in ranked)
      if (_usesLoad(resolve(id).equipment)) id,
  ];
  final bodyweight = [
    for (final id in ranked)
      if (!_usesLoad(resolve(id).equipment)) id,
  ];
  final ordered = [...loaded, ...bodyweight];
  final start = loaded.isEmpty ? offset : offset % loaded.length;
  return _pick(ordered, count, start);
}

/// Buduje wszystkie programy katalogu jako [WorkoutPlan] (30 dni każdy).
List<WorkoutPlan> buildWorkoutProgramCatalog({
  required Exercise Function(String id) resolveExercise,
  String level = 'Średniozaawansowany',
  double bodyWeightKg = 0,
  double heightCm = 0,
  int age = 0,
}) {
  return [
    for (final meta in kWorkoutProgramCatalog)
      buildWorkoutProgram(
        meta.id,
        resolveExercise: resolveExercise,
        level: level,
        bodyWeightKg: bodyWeightKg,
        heightCm: heightCm,
        age: age,
      ),
  ];
}

/// Zamienniki o niskim wpływie na stawy — używane przy wysokim BMI,
/// żeby ostrożniej dawkować skoki/interwały (pkt: dopasowanie do wagi).
const Map<String, String> _lowImpactSwaps = {
  'burpee': 'mountain_climber',
  'jumping_jack': 'step_touch',
  'high_knees': 'march_steady',
  'skater_hops': 'step_touch',
  'jump_rope': 'march_steady',
};

/// BMI z wagi/wzrostu; 0, gdy brakuje danych (wtedy nie korygujemy programu).
double _bmiOf(double bodyWeightKg, double heightCm) {
  if (bodyWeightKg <= 0 || heightCm <= 0) return 0;
  final meters = heightCm / 100;
  return bodyWeightKg / (meters * meters);
}

/// Buduje pojedynczy program 30-dniowy o podanym [programId].
///
/// Opcjonalne [bodyWeightKg] / [heightCm] / [age] delikatnie dopasowują
/// intensywność (dłuższe przerwy przy wieku 55+, zamienniki bez skoków przy
/// BMI ≥ 30). Wartości domyślne (0) nie zmieniają NIC — istniejące programy
/// i testy pozostają identyczne.
WorkoutPlan buildWorkoutProgram(
  String programId, {
  required Exercise Function(String id) resolveExercise,
  String level = 'Średniozaawansowany',
  double bodyWeightKg = 0,
  double heightCm = 0,
  int age = 0,
}) {
  final template = _templates[programId] ?? _templates['program_core']!;
  var profile = _profileFor(level);
  final normalizedLevel = normalizeTrainingLevel(level);

  // Rozsądne, zachowawcze korekty pod wiek i masę ciała (pkt 6 specyfikacji).
  final bmi = _bmiOf(bodyWeightKg, heightCm);
  if (age >= 55) {
    profile = _LevelProfile(
      profile.baseSets,
      profile.strengthRest + 15,
      profile.coreRest + 5,
      profile.repShift - 1,
    );
  } else if (bmi >= 30) {
    profile = _LevelProfile(
      profile.baseSets,
      profile.strengthRest + 10,
      profile.coreRest + 5,
      profile.repShift,
    );
  }
  final lowImpact = bmi >= 30;

  final days = <WorkoutDay>[
    for (var d = 1; d <= 30; d++)
      _buildDay(d, template, profile, normalizedLevel, resolveExercise,
          lowImpact: lowImpact),
  ];
  return WorkoutPlan(
    id: '${programId}_$normalizedLevel',
    name: template.name,
    days: days,
    note: template.note,
    goal: template.goal,
    level: normalizedLevel,
    allowAnyDay: false,
  );
}

WorkoutDay _buildDay(
  int dayNumber,
  _ProgramTemplate t,
  _LevelProfile profile,
  String level,
  Exercise Function(String) resolve, {
  bool lowImpact = false,
}) {
  final week = (dayNumber - 1) ~/ 7; // 0..4
  final kind = _weekRhythm[(dayNumber - 1) % _weekRhythm.length];
  final offset = dayNumber - 1;
  final durationBonus = week * 4; // czasowe rosną 0→16 s
  final repBonus = week; // powtórzenia rosną 0→4
  final setBonus = week >= 3 ? 1 : 0; // dodatkowa seria w końcowych tygodniach

  // Pule dobierane pod poziom: początkujący nie dostaje ćwiczeń zaawansowanych.
  final userRank = _levelRank(level);
  final mainPool = _forLevel(t.main, resolve, userRank);
  final accessoryPool = _forLevel(t.accessory, resolve, userRank);
  final finisherPool = _forLevel(t.finisher, resolve, userRank);

  final items = <PlanItem>[];

  // Przy wysokim BMI skoki są podmieniane na warianty bez wybicia
  // (duplikaty po podmianie usuwa _dedupById).
  String swap(String id) => lowImpact ? (_lowImpactSwaps[id] ?? id) : id;

  void addWarmup() {
    // Ciężki dzień NIE dostaje rozgrzewki inline: bramka rozgrzewki wymaga
    // przed nim ukończenia programu rozgrzewkowego partii
    // ([kWarmupWorkoutCatalog]), a inline + program to 2× rozgrzewka.
    if (_kindOf(kind).isHeavy) return;
    for (final id
        in _pick(t.warmup, kind == _DayKind.mobility ? 3 : 2, offset)) {
      items.add(_timedItem(swap(id), resolve,
          sets: 1, durationBonus: durationBonus, rest: 10, note: 'Rozgrzewka'));
    }
  }

  /// Rozciąganie NIE trafia już do dni treningowych — ma własne zestawy
  /// (sekcja „Rozciąganie" obok rozgrzewek). Zostaje tylko dla dni czysto
  /// mobilnościowych/odpoczynkowych, gdyby wróciły do rytmu.
  void addStretch(int count) {
    for (final id in _pick(t.stretch, count, offset)) {
      items.add(_timedItem(id, resolve,
          sets: 1, durationBonus: durationBonus, rest: 8, note: 'Rozciąganie'));
    }
  }

  void addMain({
    required int count,
    required int sets,
    int repShift = 0,
    String note = 'Seria główna',
    int? repCeil, // twardy limit powtórzeń (dzień siłowy → niskie zakresy)
    int? restOverride, // nadpisanie przerwy (dzień siłowy → dłuższa przerwa)
  }) {
    for (final id in _pickIntense(mainPool, count, offset, resolve)) {
      items.add(_smartItem(
        id,
        resolve,
        sets: sets,
        strengthRest: profile.strengthRest,
        coreRest: profile.coreRest,
        durationBonus: durationBonus,
        repBonus: repBonus + repShift + profile.repShift,
        weightHint: week >= 2,
        note: note,
        repCeil: repCeil,
        restOverride: restOverride,
      ));
    }
  }

  void addAccessory({required int count, required int sets, int repShift = 0}) {
    for (final id in _pickIntense(accessoryPool, count, offset + 2, resolve)) {
      items.add(_smartItem(
        id,
        resolve,
        sets: sets,
        strengthRest: profile.strengthRest - 10,
        coreRest: profile.coreRest,
        durationBonus: durationBonus,
        repBonus: repBonus + repShift + profile.repShift,
        weightHint: week >= 2,
        note: 'Ćwiczenie pomocnicze',
      ));
    }
  }

  void addFinisher(int count) {
    for (final id in _pick(finisherPool, count, offset + 1)) {
      items.add(_smartItem(
        swap(id),
        resolve,
        sets: 1,
        strengthRest: profile.strengthRest - 20,
        coreRest: profile.coreRest,
        durationBonus: durationBonus,
        repBonus: repBonus + profile.repShift,
        weightHint: false,
        note: 'Wykończenie',
      ));
    }
  }

  final String title;

  if (t.timedStyle) {
    // Program brzucha — dni treningowe z dużą pulą ćwiczeń czasowych (~24 pozycje).
    switch (kind) {
      case _DayKind.strengthA:
      case _DayKind.strengthB:
      case _DayKind.strengthC:
        title = 'Dzień $dayNumber · Brzuch — pełny obwód';
        addWarmup();
        for (final id in _pick(mainPool, mainPool.length, offset)) {
          items.add(_timedItem(id, resolve,
              sets: 1 + setBonus,
              durationBonus: durationBonus,
              rest: profile.coreRest,
              note: 'Obwód brzucha'));
        }
        for (final id in _pick(accessoryPool, 5, offset)) {
          items.add(_smartItem(id, resolve,
              sets: 2 + setBonus,
              strengthRest: profile.coreRest,
              coreRest: profile.coreRest,
              durationBonus: durationBonus,
              repBonus: repBonus + profile.repShift,
              weightHint: week >= 2,
              note: 'Core'));
        }
        break;
      case _DayKind.conditioning:
        title = 'Dzień $dayNumber · Brzuch + kondycja';
        addWarmup();
        for (final id in _pick(mainPool, 8, offset)) {
          items.add(_timedItem(id, resolve,
              sets: 1,
              durationBonus: durationBonus,
              rest: profile.coreRest,
              note: 'Obwód brzucha'));
        }
        addFinisher(4);
        break;
      case _DayKind.technique:
        title = 'Dzień $dayNumber · Technika i kontrola';
        addWarmup();
        for (final id in _pick(mainPool, 8, offset)) {
          items.add(_timedItem(id, resolve,
              sets: 1,
              durationBonus: 0,
              rest: profile.coreRest + 5,
              note: 'Wolne tempo — technika'));
        }
        break;
      case _DayKind.mobility:
        title = 'Dzień $dayNumber · Mobilność i rozciąganie';
        addWarmup();
        addStretch(7);
        break;
      case _DayKind.rest:
        title = 'Dzień $dayNumber · Odpoczynek / aktywna regeneracja';
        addWarmup();
        addStretch(4);
        break;
    }
    return WorkoutDay(
        weekday: ((dayNumber - 1) % 7) + 1,
        title: title,
        items: _dedupById(items),
        kind: _kindOf(kind));
  }

  // Programy siłowe (klatka/ramiona/barki/plecy/przedramiona/nogi).
  switch (kind) {
    case _DayKind.strengthA:
      // Dzień PRAWDZIWIE siłowy: ciężkie boje złożone, niskie powtórzenia
      // i długa przerwa. Bez kalistenicznego wykończenia (plank/mountain
      // climber) — to ono nadawało dawnej „Sile A" gimnastyczny charakter.
      title = 'Dzień $dayNumber · Siła A — ciężka';
      addWarmup();
      addMain(
        count: 3,
        sets: profile.baseSets + setBonus,
        note: 'Seria główna — ciężko, niskie powtórzenia',
        repCeil: 6,
        restOverride: profile.strengthRest + 75,
      );
      addAccessory(count: 2, sets: profile.baseSets);
      break;
    case _DayKind.strengthB:
      // Bez kalistenicznego wykończenia — objętość robimy na obciążeniu,
      // a nie na pompkach i planku doklejonych na koniec.
      title = 'Dzień $dayNumber · Objętość B';
      addWarmup();
      addMain(
          count: 3,
          sets: profile.baseSets,
          repShift: 2,
          note: 'Seria główna — więcej powtórzeń');
      addAccessory(count: 3, sets: profile.baseSets);
      break;
    case _DayKind.strengthC:
      title = 'Dzień $dayNumber · Hipertrofia C';
      addWarmup();
      addMain(count: 4, sets: profile.baseSets + setBonus);
      addAccessory(count: 3, sets: profile.baseSets);
      break;
    case _DayKind.technique:
      title = 'Dzień $dayNumber · Dzień techniczny (lżejszy)';
      addWarmup();
      addMain(
          count: 3, sets: 2, repShift: 3, note: 'Lekko — dopracuj technikę');
      addAccessory(count: 2, sets: 2);
      break;
    case _DayKind.conditioning:
      title = 'Dzień $dayNumber · Akcesoria + kondycja';
      addWarmup();
      addAccessory(count: 4, sets: profile.baseSets);
      addFinisher(3);
      break;
    case _DayKind.mobility:
      title = 'Dzień $dayNumber · Mobilność i rozciąganie';
      addWarmup();
      addStretch(6);
      break;
    case _DayKind.rest:
      title = 'Dzień $dayNumber · Odpoczynek / aktywna regeneracja';
      addWarmup();
      addStretch(4);
      break;
  }
  // Dzień CIĘŻKI idzie od najcięższego boju do najlżejszej pracy — bez
  // przeplatania go rozciąganiem. Mobilność ma swoje własne dni.
  final ordered = _kindOf(kind).isHeavy
      ? _sortByIntensityDesc(_dedupById(items), resolve)
      : _dedupById(items);
  return WorkoutDay(
      weekday: ((dayNumber - 1) % 7) + 1,
      title: title,
      items: ordered,
      kind: _kindOf(kind));
}

/// Porządkuje pozycje od najcięższej do najlżejszej.
List<PlanItem> _sortByIntensityDesc(
    List<PlanItem> items, Exercise Function(String) resolve) {
  final sorted = [...items];
  sorted.sort((a, b) => exerciseIntensityScore(resolve(b.exerciseId))
      .compareTo(exerciseIntensityScore(resolve(a.exerciseId))));
  return sorted;
}

/// Usuwa powtórzone ćwiczenia w obrębie jednego dnia (zostawia pierwsze wystąpienie).
List<PlanItem> _dedupById(List<PlanItem> items) {
  final seen = <String>{};
  final result = <PlanItem>[];
  for (final item in items) {
    if (seen.add(item.exerciseId)) result.add(item);
  }
  return result;
}

/// Wybiera [count] identyfikatorów z [pool], zaczynając od [offset] (z zawijaniem),
/// bez duplikatów. Zwraca mniej, jeśli pula jest krótsza.
List<String> _pick(List<String> pool, int count, int offset) {
  if (pool.isEmpty) return const [];
  final result = <String>[];
  final seen = <String>{};
  for (var i = 0; i < pool.length && result.length < count; i++) {
    final id = pool[(offset + i) % pool.length];
    if (seen.add(id)) result.add(id);
  }
  return result;
}

/// Pozycja czasowa (rozgrzewka / rozciąganie / izometria).
PlanItem _timedItem(
  String id,
  Exercise Function(String) resolve, {
  required int sets,
  int durationBonus = 0,
  int rest = 10,
  String note = '',
}) {
  final ex = resolve(id);
  final base = ex.defaultDurationSec > 0 ? ex.defaultDurationSec : 30;
  return PlanItem(
    exerciseId: id,
    sets: sets,
    reps: 0,
    durationSec: base + durationBonus,
    note: note,
    restSeconds: rest,
  );
}

/// Pozycja dobrana do typu ćwiczenia: czasowe → czas, pozostałe → serie/powtórzenia.
PlanItem _smartItem(
  String id,
  Exercise Function(String) resolve, {
  required int sets,
  required int strengthRest,
  required int coreRest,
  int durationBonus = 0,
  int repBonus = 0,
  bool weightHint = false,
  String note = '',
  int? repCeil, // twardy górny limit powtórzeń (dzień siłowy → niskie zakresy)
  int? restOverride, // nadpisanie przerwy (dzień siłowy → dłuższa przerwa)
}) {
  final ex = resolve(id);
  // O kształcie pozycji decyduje TYP WPISU ćwiczenia, a nie sam fakt, że ma
  // ustawiony czas domyślny. Inaczej plan mógł kazać liczyć sekundy ćwiczeniu,
  // którego panel wpisu zna wyłącznie serie i powtórzenia (i odwrotnie).
  final entryType = ex.entryType;
  if (entryType.showsDuration && !entryType.showsReps) {
    final base = ex.defaultDurationSec > 0 ? ex.defaultDurationSec : 40;
    return PlanItem(
      exerciseId: id,
      sets: sets,
      reps: 0,
      durationSec: base + durationBonus,
      note: note,
      restSeconds: restOverride ?? coreRest,
    );
  }
  final reps = (ex.defaultReps > 0 ? ex.defaultReps : 12) + repBonus;
  // Podpowiedź obciążenia rośnie z tygodniami, gdy ćwiczenie używa sprzętu.
  final usesWeight = weightHint && _usesLoad(ex.equipment);
  return PlanItem(
    exerciseId: id,
    sets: sets,
    reps: reps.clamp(4, repCeil ?? 30),
    durationSec: 0,
    note: usesWeight ? '$note · dobierz ciężar (progresja)' : note,
    suggestedWeightKg: 0,
    restSeconds: restOverride ?? strengthRest,
  );
}

bool _usesLoad(String equipment) {
  final e = equipment.toLowerCase();
  return e.contains('hant') ||
      e.contains('sztang') ||
      e.contains('obciąż') ||
      e.contains('obciaz') ||
      e.contains('kett');
}

// ============================================================================
// Katalog szybkich treningów cardio (kafelki w zakładce „Trening")
// ============================================================================

/// Pojedynczy odcinek treningu cardio (ćwiczenie + parametry pozycji planu).
class CardioSegment {
  const CardioSegment(
    this.exerciseId, {
    this.sets = 1,
    this.reps = 0,
    this.durationSec = 0,
    this.rest = 15,
    this.note = '',
  });

  final String exerciseId;
  final int sets;
  final int reps;

  /// 0 → użyj domyślnego czasu ćwiczenia (dla czasowych) albo powtórzeń.
  final int durationSec;
  final int rest;
  final String note;
}

/// Metadane kafelka cardio: opis, intensywność, czas i gotowa rozpiska.
class CardioWorkoutMeta {
  const CardioWorkoutMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.intensity,
    required this.estimatedMinutes,
    required this.level,
    required this.segments,
    this.iconKey = 'cardio',
    this.equipment = 'masa ciała',
  });

  final String id;
  final String title;
  final String subtitle;
  final int accentColor;

  /// „Niska" / „Średnia" / „Wysoka" — do odznaki na kafelku.
  final String intensity;
  final int estimatedMinutes;
  final String level;
  final List<CardioSegment> segments;
  final String iconKey;
  final String equipment;
}

/// Kafelki cardio w stałej kolejności. Każdy buduje realny, jednodniowy
/// trening (rozgrzewka → część główna → wyciszenie) z istniejących ćwiczeń.
const List<CardioWorkoutMeta> kCardioWorkoutCatalog = [
  CardioWorkoutMeta(
    id: 'cardio_beginner',
    title: 'Cardio dla początkujących',
    subtitle: 'Łagodny start: marsz, krok boczny i lekkie pajacyki',
    accentColor: 0xFF4DD0A6,
    intensity: 'Niska',
    estimatedMinutes: 18,
    level: 'Początkujący',
    iconKey: 'beginner',
    segments: [
      CardioSegment('arm_circles',
          durationSec: 30, rest: 10, note: 'Rozgrzewka'),
      CardioSegment('leg_swings',
          durationSec: 30, rest: 10, note: 'Rozgrzewka'),
      CardioSegment('march_steady',
          durationSec: 180, rest: 20, note: 'Spokojne tempo'),
      CardioSegment('step_touch', sets: 2, durationSec: 60, rest: 20),
      CardioSegment('jumping_jack',
          sets: 2, durationSec: 30, rest: 25, note: 'Lekko, miękkie lądowanie'),
      CardioSegment('march_steady',
          durationSec: 120, rest: 15, note: 'Wyciszenie tempa'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_fat_burn',
    title: 'Cardio — spalanie tłuszczu',
    subtitle: 'Stałe, umiarkowane tempo z krótkimi akcentami',
    accentColor: 0xFFFF7B54,
    intensity: 'Średnia',
    estimatedMinutes: 26,
    level: 'Średniozaawansowany',
    iconKey: 'fat_burn',
    segments: [
      CardioSegment('jumping_jack',
          durationSec: 45, rest: 15, note: 'Rozgrzewka'),
      CardioSegment('march_steady',
          durationSec: 120, rest: 15, note: 'Rozgrzewka'),
      CardioSegment('high_knees', sets: 3, durationSec: 40, rest: 20),
      CardioSegment('mountain_climber', sets: 3, durationSec: 40, rest: 20),
      CardioSegment('skater_hops', sets: 3, durationSec: 40, rest: 20),
      CardioSegment('butt_kicks', sets: 2, durationSec: 40, rest: 20),
      CardioSegment('march_steady',
          durationSec: 180, rest: 15, note: 'Wyciszenie tempa'),
      CardioSegment('quad_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_endurance',
    title: 'Cardio — kondycja',
    subtitle: 'Dłuższa, równa praca budująca wydolność',
    accentColor: 0xFF58A6FF,
    intensity: 'Średnia',
    estimatedMinutes: 32,
    level: 'Średniozaawansowany',
    iconKey: 'endurance',
    segments: [
      CardioSegment('march_steady',
          durationSec: 120, rest: 15, note: 'Rozgrzewka'),
      CardioSegment('run',
          durationSec: 900, rest: 60, note: 'Równe tempo konwersacyjne'),
      CardioSegment('march_steady',
          durationSec: 180, rest: 20, note: 'Aktywna przerwa'),
      CardioSegment('run',
          durationSec: 300, rest: 30, note: 'Drugie, krótsze tempo'),
      CardioSegment('march_steady',
          durationSec: 120, rest: 15, note: 'Wyciszenie'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_hiit',
    title: 'Cardio interwałowe (HIIT)',
    subtitle: 'Krótkie, mocne interwały — maksimum w kwadrans',
    accentColor: 0xFFFF5D73,
    intensity: 'Wysoka',
    estimatedMinutes: 16,
    level: 'Zaawansowany',
    iconKey: 'hiit',
    segments: [
      CardioSegment('jumping_jack',
          durationSec: 45, rest: 15, note: 'Rozgrzewka'),
      CardioSegment('high_knees',
          sets: 4, durationSec: 30, rest: 15, note: 'Interwał — pełne tempo'),
      CardioSegment('burpee',
          sets: 4, reps: 8, rest: 30, note: 'Interwał — kontrola techniki'),
      CardioSegment('mountain_climber',
          sets: 4, durationSec: 30, rest: 15, note: 'Interwał'),
      CardioSegment('skater_hops',
          sets: 4, durationSec: 30, rest: 15, note: 'Interwał'),
      CardioSegment('jump_rope',
          sets: 2, durationSec: 60, rest: 30, note: 'Finisher'),
      CardioSegment('quad_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_recovery',
    title: 'Cardio lekkie / regeneracyjne',
    subtitle: 'Krążenie i luz bez obciążania mięśni',
    accentColor: 0xFF7FD1AE,
    intensity: 'Niska',
    estimatedMinutes: 15,
    level: 'Początkujący',
    iconKey: 'recovery',
    segments: [
      CardioSegment('march_steady',
          durationSec: 240, rest: 15, note: 'Bardzo spokojnie'),
      CardioSegment('step_touch', durationSec: 60, rest: 15),
      CardioSegment('torso_twist',
          durationSec: 30, rest: 10, note: 'Mobilność'),
      CardioSegment('leg_swings', durationSec: 30, rest: 10, note: 'Mobilność'),
      CardioSegment('downward_dog',
          durationSec: 36, rest: 10, note: 'Rozciąganie'),
      CardioSegment('child_pose',
          durationSec: 40, rest: 10, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_after_strength',
    title: 'Cardio po treningu siłowym',
    subtitle: 'Spokojne dopalenie i wyciszenie po siłowni',
    accentColor: 0xFFB388FF,
    intensity: 'Niska',
    estimatedMinutes: 12,
    level: 'Początkujący',
    iconKey: 'after_strength',
    segments: [
      CardioSegment('march_steady',
          durationSec: 300, rest: 20, note: 'Równe, lekkie tempo'),
      CardioSegment('step_touch', durationSec: 60, rest: 15),
      CardioSegment('quad_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('chest_doorway_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_running',
    title: 'Bieganie',
    subtitle: 'Sesja biegowa z rozgrzewką i schłodzeniem',
    accentColor: 0xFF26C6DA,
    intensity: 'Średnia',
    estimatedMinutes: 35,
    level: 'Średniozaawansowany',
    iconKey: 'running',
    equipment: 'buty do biegania',
    segments: [
      CardioSegment('leg_swings',
          durationSec: 30, rest: 10, note: 'Rozgrzewka'),
      CardioSegment('march_steady',
          durationSec: 180, rest: 15, note: 'Rozgrzewka marszem'),
      CardioSegment('run',
          durationSec: 1500, rest: 60, note: 'Główna część biegu'),
      CardioSegment('march_steady',
          durationSec: 180, rest: 15, note: 'Schłodzenie'),
      CardioSegment('quad_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_walking',
    title: 'Marsz / szybki chód',
    subtitle: 'Najprostsze cardio — energiczny spacer',
    accentColor: 0xFF9CCC65,
    intensity: 'Niska',
    estimatedMinutes: 30,
    level: 'Początkujący',
    iconKey: 'walking',
    segments: [
      CardioSegment('leg_swings',
          durationSec: 30, rest: 10, note: 'Rozgrzewka'),
      CardioSegment('march_steady',
          durationSec: 1500, rest: 30, note: 'Energiczne tempo marszu'),
      CardioSegment('calf_stretch',
          durationSec: 30, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hip_flexor_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
    ],
  ),
  CardioWorkoutMeta(
    id: 'cardio_cycling',
    title: 'Rowerek / ergometr',
    subtitle: 'Jazda w równym tempie — kolana lubią kadencję',
    accentColor: 0xFFFFB86B,
    intensity: 'Średnia',
    estimatedMinutes: 30,
    level: 'Początkujący',
    iconKey: 'cycling',
    equipment: 'rower / ergometr',
    segments: [
      CardioSegment('leg_swings',
          durationSec: 30, rest: 10, note: 'Rozgrzewka'),
      CardioSegment('bike',
          durationSec: 1500, rest: 30, note: 'Równa kadencja, lekki opór'),
      CardioSegment('quad_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
      CardioSegment('hamstring_stretch',
          durationSec: 36, rest: 8, note: 'Rozciąganie'),
    ],
  ),
];

/// Buduje jednodniowy trening cardio z metadanych kafelka.
/// Id planu jest stałe (= meta.id), więc ponowne dotknięcie kafelka wznawia
/// istniejący plan zamiast tworzyć duplikat.
WorkoutPlan buildCardioWorkout(
  CardioWorkoutMeta meta, {
  required Exercise Function(String id) resolveExercise,
  int? weekday,
}) {
  final items = <PlanItem>[
    for (final segment in meta.segments) _cardioItem(segment, resolveExercise),
  ];
  return WorkoutPlan(
    id: meta.id,
    name: meta.title,
    note:
        '${meta.subtitle}. Intensywność: ${meta.intensity.toLowerCase()}, ~${meta.estimatedMinutes} min.',
    goal: 'Kondycja',
    level: meta.level,
    allowAnyDay: true,
    days: [
      WorkoutDay(
        weekday: weekday ?? DateTime.now().weekday,
        title: meta.title,
        items: items,
      ),
    ],
  );
}

// ============================================================================
// Katalog programów rozgrzewkowych (bramka ciężkich dni)
// ============================================================================

/// Jak długo ukończona rozgrzewka pozostaje „świeża" dla bramki ciężkiego
/// dnia. Po tym czasie ciało stygnie i rozgrzewkę trzeba wykonać ponownie.
const Duration kWarmupFreshness = Duration(hours: 2);

/// Metadane programu rozgrzewkowego jednej partii. Rozgrzewka jest krótkim,
/// jednodniowym planem (jak kafelki cardio) budowanym z TEJ SAMEJ puli,
/// z której korzysta rozgrzewka inline programów — ciężki dzień dostaje więc
/// dokładnie to przygotowanie, które lekkie dni mają wpisane w plan.
class WarmupWorkoutMeta {
  const WarmupWorkoutMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.estimatedMinutes,
    required this.exerciseIds,
    this.iconKey = 'generic',
    this.rounds = 2,
  });

  final String id;
  final String title;
  final String subtitle;
  final int accentColor;
  final int estimatedMinutes;

  /// Pula ćwiczeń partii (te same stałe co rozgrzewki inline programów).
  final List<String> exerciseIds;

  /// Klucz ikony — te same klucze co kafelki programów (iconForProgramKey).
  final String iconKey;

  /// Liczba okrążeń puli (serie każdej pozycji).
  final int rounds;
}

/// Kafelki rozgrzewek w stałej kolejności (dział „Rozgrzewki" w UI).
/// Kolory i ikony celowo powtarzają program partii, którą przygotowują.
const List<WarmupWorkoutMeta> kWarmupWorkoutCatalog = [
  WarmupWorkoutMeta(
    id: 'warmup_push',
    title: 'Rozgrzewka — klatka',
    subtitle: 'Obręcz barkowa i łopatki pod wyciskania, pompki i dipy',
    accentColor: 0xFFFF6B6B,
    estimatedMinutes: 7,
    exerciseIds: _warmupPush,
    iconKey: 'chest',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_shoulders',
    title: 'Rozgrzewka — barki',
    subtitle: 'Rotatory i mobilność pod pracę nad głową',
    accentColor: 0xFF58A6FF,
    estimatedMinutes: 7,
    exerciseIds: _warmupShoulders,
    iconKey: 'shoulders',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_pull',
    title: 'Rozgrzewka — plecy',
    subtitle: 'Łopatki i odcinek piersiowy pod podciąganie i wiosłowanie',
    accentColor: 0xFFFFB86B,
    estimatedMinutes: 7,
    exerciseIds: _warmupPull,
    iconKey: 'back',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_arms',
    title: 'Rozgrzewka — ramiona',
    subtitle: 'Łokcie, nadgarstki i obręcz pod uginania i prostowania',
    accentColor: 0xFFB388FF,
    estimatedMinutes: 6,
    exerciseIds: _warmupArms,
    iconKey: 'arms',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_forearms',
    title: 'Rozgrzewka — przedramiona',
    subtitle: 'Nadgarstki i chwyt przed pracą przedramion',
    accentColor: 0xFF7FD1AE,
    estimatedMinutes: 4,
    exerciseIds: _warmupForearms,
    iconKey: 'forearms',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_legs',
    title: 'Rozgrzewka — nogi',
    subtitle: 'Biodra, kolana i kostki pod przysiady i martwe ciągi',
    accentColor: 0xFFFF9E64,
    estimatedMinutes: 6,
    exerciseIds: _warmupLegs,
    iconKey: 'legs',
  ),
  WarmupWorkoutMeta(
    id: 'warmup_core',
    title: 'Rozgrzewka — brzuch / core',
    subtitle: 'Tułów i biodra przed obwodami brzucha',
    accentColor: 0xFF24D6A3,
    estimatedMinutes: 6,
    exerciseIds: _warmupCore,
    iconKey: 'core',
  ),
];

/// Program katalogu → jego rozgrzewka (klucze = id z [kWorkoutProgramCatalog]).
const Map<String, String> _programWarmupIds = {
  'program_core': 'warmup_core',
  'program_chest': 'warmup_push',
  'program_arms': 'warmup_arms',
  'program_shoulders': 'warmup_shoulders',
  'program_back': 'warmup_pull',
  'program_forearms': 'warmup_forearms',
  'program_legs': 'warmup_legs',
};

/// Rozgrzewka pasująca do planu o [planId] — id programu albo pełne id planu
/// z poziomem (np. `program_chest_Średniozaawansowany`). null = plan spoza
/// katalogu; bramka nie wie wtedy, którą partię rozgrzewać, więc nie blokuje.
WarmupWorkoutMeta? warmupWorkoutForPlan(String planId) {
  for (final entry in _programWarmupIds.entries) {
    if (planId != entry.key && !planId.startsWith('${entry.key}_')) continue;
    for (final meta in kWarmupWorkoutCatalog) {
      if (meta.id == entry.value) return meta;
    }
  }
  return null;
}

/// Czy [planId] to program rozgrzewkowy z katalogu (śledzenie ukończenia).
bool isWarmupWorkoutPlan(String planId) =>
    kWarmupWorkoutCatalog.any((meta) => meta.id == planId);

/// Buduje jednodniowy program rozgrzewkowy. Id planu jest stałe (= meta.id),
/// więc ponowne dotknięcie kafelka wznawia istniejący plan zamiast duplikować.
WorkoutPlan buildWarmupWorkout(
  WarmupWorkoutMeta meta, {
  required Exercise Function(String id) resolveExercise,
  int? weekday,
}) {
  final items = <PlanItem>[
    for (final id in meta.exerciseIds)
      _timedItem(id, resolveExercise,
          sets: meta.rounds, rest: 10, note: 'Rozgrzewka'),
  ];
  return WorkoutPlan(
    id: meta.id,
    name: meta.title,
    note:
        '${meta.subtitle}. ~${meta.estimatedMinutes} min. Ukończona rozgrzewka odblokowuje ciężkie dni programu tej partii.',
    goal: 'Kondycja',
    allowAnyDay: true,
    days: [
      WorkoutDay(
        weekday: weekday ?? DateTime.now().weekday,
        title: meta.title,
        items: items,
        kind: WorkoutDayKind.mobility,
      ),
    ],
  );
}


// ============================================================================
// Katalog zestawów ROZCIĄGANIA (osobno, poza dniami treningowymi)
// ============================================================================

/// Zestawy rozciągania partii — bliźniaki rozgrzewek. Rozciąganie ma swoje
/// miejsce OBOK treningu, a nie w środku ciężkiego dnia.
const List<WarmupWorkoutMeta> kStretchWorkoutCatalog = [
  WarmupWorkoutMeta(
    id: 'stretch_push',
    title: 'Rozciąganie — klatka',
    subtitle: 'Klatka, przód barków i triceps po wyciskaniach',
    accentColor: 0xFFFF6B6B,
    estimatedMinutes: 6,
    exerciseIds: _stretchPush,
    iconKey: 'chest',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_pull',
    title: 'Rozciąganie — plecy',
    subtitle: 'Najszerszy, odcinek piersiowy i dolny grzbiet',
    accentColor: 0xFFFFB86B,
    estimatedMinutes: 6,
    exerciseIds: _stretchPull,
    iconKey: 'back',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_shoulders',
    title: 'Rozciąganie — barki',
    subtitle: 'Obręcz barkowa i kark po pracy nad głową',
    accentColor: 0xFF58A6FF,
    estimatedMinutes: 5,
    exerciseIds: _stretchShoulders,
    iconKey: 'shoulders',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_arms',
    title: 'Rozciąganie — ramiona',
    subtitle: 'Triceps, biceps i przedramiona po uginaniach',
    accentColor: 0xFFB388FF,
    estimatedMinutes: 5,
    exerciseIds: _stretchArms,
    iconKey: 'arms',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_forearms',
    title: 'Rozciąganie — przedramiona',
    subtitle: 'Nadgarstki i chwyt po pracy przedramion',
    accentColor: 0xFF7FD1AE,
    estimatedMinutes: 4,
    exerciseIds: _stretchForearms,
    iconKey: 'forearms',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_legs',
    title: 'Rozciąganie — nogi',
    subtitle: 'Uda, pośladki, biodra i łydki po przysiadach',
    accentColor: 0xFFFF9E64,
    estimatedMinutes: 7,
    exerciseIds: _stretchLegs,
    iconKey: 'legs',
    rounds: 1,
  ),
  WarmupWorkoutMeta(
    id: 'stretch_core',
    title: 'Rozciąganie — brzuch / core',
    subtitle: 'Brzuch, skośne i biodra po obwodach',
    accentColor: 0xFF24D6A3,
    estimatedMinutes: 5,
    exerciseIds: _stretchCore,
    iconKey: 'core',
    rounds: 1,
  ),
];

/// Program partii → jego zestaw rozciągania.
const Map<String, String> _programStretchIds = {
  'program_core': 'stretch_core',
  'program_chest': 'stretch_push',
  'program_arms': 'stretch_arms',
  'program_shoulders': 'stretch_shoulders',
  'program_back': 'stretch_pull',
  'program_forearms': 'stretch_forearms',
  'program_legs': 'stretch_legs',
};

/// Zestaw rozciągania pasujący do planu (albo null spoza katalogu).
WarmupWorkoutMeta? stretchWorkoutForPlan(String planId) {
  for (final entry in _programStretchIds.entries) {
    if (planId != entry.key && !planId.startsWith('${entry.key}_')) continue;
    for (final meta in kStretchWorkoutCatalog) {
      if (meta.id == entry.value) return meta;
    }
  }
  return null;
}

/// Czy [planId] to zestaw rozciągania z katalogu.
bool isStretchWorkoutPlan(String planId) =>
    kStretchWorkoutCatalog.any((meta) => meta.id == planId);

/// Buduje jednodniowy zestaw rozciągania (id stałe = meta.id).
WorkoutPlan buildStretchWorkout(
  WarmupWorkoutMeta meta, {
  required Exercise Function(String id) resolveExercise,
  int? weekday,
}) {
  final items = <PlanItem>[
    for (final id in meta.exerciseIds)
      _timedItem(id, resolveExercise,
          sets: meta.rounds, rest: 8, note: 'Rozciąganie'),
  ];
  return WorkoutPlan(
    id: meta.id,
    name: meta.title,
    note: '${meta.subtitle}. ~${meta.estimatedMinutes} min. '
        'Rozciąganie robimy PO treningu albo w osobnym momencie dnia — '
        'nie w środku ciężkiego zestawu.',
    goal: 'Sylwetka',
    allowAnyDay: true,
    days: [
      WorkoutDay(
        weekday: weekday ?? DateTime.now().weekday,
        title: meta.title,
        items: items,
        kind: WorkoutDayKind.mobility,
      ),
    ],
  );
}

// ============================================================================
// Jednorazowa migracja zapisanych planów pod bramkę rozgrzewki
// ============================================================================

/// Migruje ZAPISANY plan katalogu pod bramkę rozgrzewki i zwraca poprawioną
/// kopię — albo null, gdy plan nie jest z katalogu lub niczego nie wymagał
/// (idempotencja). Starsze zapisy mają `kind: unknown` (omijają bramkę
/// sprawdzającą [WorkoutDayKind.isHeavy]) i starą, ogólną rozgrzewkę inline
/// także w dni ciężkie.
///
/// Dla planów katalogu (id `<programId>` albo `<programId>_<poziom>`):
/// 1. uzupełnia [WorkoutDay.kind] z deterministycznego rytmu generatora
///    (`_weekRhythm[(dayNumber - 1) % _weekRhythm.length]`),
/// 2. w dniach CIĘŻKICH usuwa pozycje rozgrzewkowe inline (ćwiczenia
///    o kategorii „Rozgrzewka") — przygotowanie dostarcza program
///    rozgrzewkowy wymagany przez bramkę,
/// 3. w dniach lekkich podmienia id rozgrzewek spoza puli partii na pulę
///    danego programu (parametry pozycji, w tym czas z progresją, zostają).
///
/// `completedDays`, aktywny wariant i historia wariantów pozostają nietknięte
/// (copyWith nie dotyka tych pól). Plany własne, cardio i rozgrzewkowe → null.
WorkoutPlan? migratePlanForWarmupGate(
  WorkoutPlan plan, {
  required Exercise Function(String id) resolveExercise,
}) {
  _ProgramTemplate? template;
  for (final entry in _templates.entries) {
    if (plan.id == entry.key || plan.id.startsWith('${entry.key}_')) {
      template = entry.value;
      break;
    }
  }
  if (template == null) return null;

  final pool = template.warmup;
  bool isWarmupItem(PlanItem item) =>
      resolveExercise(item.exerciseId).category == 'Rozgrzewka';

  var changed = false;
  final days = <WorkoutDay>[];
  for (var index = 0; index < plan.days.length; index++) {
    final day = plan.days[index];
    final kind = _kindOf(_weekRhythm[index % _weekRhythm.length]);

    var items = day.items;
    if (kind.isHeavy) {
      final kept = [
        for (final item in day.items)
          if (!isWarmupItem(item)) item,
      ];
      if (kept.length != day.items.length) items = kept;
    } else {
      // Podmiana nie może zdublować ćwiczenia w obrębie dnia.
      final used = {for (final item in day.items) item.exerciseId};
      List<PlanItem>? replaced;
      for (var i = 0; i < day.items.length; i++) {
        final item = day.items[i];
        if (!isWarmupItem(item) || pool.contains(item.exerciseId)) continue;
        String? substitute;
        for (final id in pool) {
          if (used.add(id)) {
            substitute = id;
            break;
          }
        }
        if (substitute == null) continue; // pula wyczerpana — zostaw jak jest
        replaced ??= [...day.items];
        replaced[i] = item.copyWith(exerciseId: substitute);
      }
      if (replaced != null) items = replaced;
    }

    if (identical(items, day.items) && day.kind == kind) {
      days.add(day);
    } else {
      days.add(day.copyWith(items: items, kind: kind));
      changed = true;
    }
  }
  if (!changed) return null;
  return plan.copyWith(days: days);
}

// ============================================================================
// Dopasowanie programów do profilu treningowego (poziom, tryb, sprzęt,
// ograniczenia, wiek, wzrost, waga). Czysty Dart — UI tylko pokazuje wynik.
// ============================================================================

/// Profil użytkownika na potrzeby rekomendacji programów.
class ProgramUserProfile {
  const ProgramUserProfile({
    this.level = 'Średniozaawansowany',
    this.trainingMode = '',
    this.goal = '',
    this.equipment = '',
    this.limitations = '',
    this.bodyWeightKg = 0,
    this.heightCm = 0,
    this.age = 0,
    this.sex = '',
    this.trainingDaysPerWeek = 0,
  });

  final String level;
  final String trainingMode;
  final String goal;
  final String equipment;
  final String limitations;
  final double bodyWeightKg;
  final double heightCm;
  final int age;
  final String sex;
  final int trainingDaysPerWeek;

  double get bmi => _bmiOf(bodyWeightKg, heightCm);
}

/// Wynik dopasowania programu do profilu: punkty + czytelne powody dla UI
/// („Dopasowane do Twojego poziomu", „Bez sprzętu"…) i ostrzeżenia.
class ProgramRecommendation {
  const ProgramRecommendation({
    required this.score,
    required this.reasons,
    required this.cautions,
  });

  /// 0–100; im więcej, tym lepsze dopasowanie do profilu.
  final int score;
  final List<String> reasons;
  final List<String> cautions;

  bool get isRecommended => score >= 62;
  String get primaryReason => reasons.isEmpty ? '' : reasons.first;
  String get primaryCaution => cautions.isEmpty ? '' : cautions.first;
}

/// Czy sprzęt z profilu pokrywa wymaganie programu. „Siłownia" w profilu
/// odblokowuje wszystko; masa ciała / mata / pozycje „opcjonalne" nie wymagają nic.
bool _profileHasEquipment(String needed, String ownedRaw) {
  final n = needed.toLowerCase();
  if (n.contains('masa ciała') ||
      n.contains('masa ciala') ||
      n.contains('mata') ||
      n.contains('opcjonal')) {
    return true;
  }
  final o = ownedRaw.toLowerCase();
  if (o.contains('siłown') || o.contains('silown') || o.contains('gym'))
    return true;
  if (n.contains('hant')) return o.contains('hant');
  if (n.contains('sztang')) return o.contains('sztang');
  if (n.contains('ławk') || n.contains('lawk'))
    return o.contains('ławk') || o.contains('lawk');
  if (n.contains('barier'))
    return o.contains('barier') ||
        o.contains('drąż') ||
        o.contains('draz') ||
        o.contains('poręcz') ||
        o.contains('porecz');
  if (n.contains('rower') || n.contains('ergometr'))
    return o.contains('rower') || o.contains('ergometr');
  if (n.contains('but')) return true; // buty do biegania — przyjmujemy, że są
  final firstWord = n.split(' ').first;
  return firstWord.length >= 4 && o.contains(firstWord);
}

/// Dopasowanie programu 30-dniowego do profilu użytkownika.
ProgramRecommendation recommendProgram(
  WorkoutProgramMeta meta,
  ProgramUserProfile profile,
) {
  var score = 55;
  final reasons = <String>[];
  final cautions = <String>[];

  // Poziom: program jest generowany w wariancie poziomu użytkownika,
  // więc zawsze jest to realne dopasowanie (pkt 7 — warianty programu).
  final level = normalizeTrainingLevel(profile.level);
  reasons.add('Dopasowane do poziomu: $level');
  score += 8;

  // Sprzęt.
  final missing = <String>[];
  var bodyweightOnly = true;
  for (final item in meta.equipment) {
    final normalized = item.toLowerCase();
    if (normalized.contains('masa ciała') ||
        normalized.contains('masa ciala') ||
        normalized.contains('mata') ||
        normalized.contains('opcjonal')) {
      continue;
    }
    bodyweightOnly = false;
    if (!_profileHasEquipment(item, profile.equipment)) missing.add(item);
  }
  if (bodyweightOnly) {
    score += 8;
    reasons.add('Bez sprzętu');
  } else if (missing.isEmpty) {
    score += 10;
    reasons.add('Masz potrzebny sprzęt');
  } else {
    score -= 20;
    cautions.add('Wymaga: ${missing.join(', ')}');
  }

  // Tryb treningu.
  final mode = profile.trainingMode.toLowerCase();
  final isStrengthKind = meta.kind.toLowerCase().contains('sił') ||
      meta.kind.toLowerCase().contains('sil');
  if (mode.contains('reduk')) {
    if (meta.id == 'program_core') {
      score += 8;
      reasons.add('Pod tryb: redukcja');
    }
  } else if (mode.contains('mas')) {
    if (isStrengthKind) {
      score += 8;
      reasons.add('Pod tryb: masa');
    }
  } else if (mode.contains('kondy')) {
    if (meta.id == 'program_core') {
      score += 5;
      reasons.add('Pod tryb: kondycja');
    }
  } else if (mode.contains('rekompo')) {
    score += 3;
  }

  // Ograniczenia zdrowotne.
  final lim = profile.limitations.toLowerCase();
  if (lim.contains('kolan') && meta.id == 'program_legs') {
    score -= 15;
    cautions.add('Uważaj na kolana — lżejsze warianty przysiadów');
  }
  if ((lim.contains('plec') || lim.contains('lędź') || lim.contains('ledz')) &&
      (meta.id == 'program_back' || meta.id == 'program_legs')) {
    score -= 12;
    cautions.add('Ostrożnie z martwym ciągiem i wiosłowaniem');
  }
  if (lim.contains('bark') &&
      (meta.id == 'program_shoulders' || meta.id == 'program_chest')) {
    score -= 12;
    cautions.add('Ostrożnie z wyciskaniem nad głowę');
  }

  // Waga / wiek — informacja o łagodniejszym wariancie (generator to robi).
  if (profile.bmi >= 30 &&
      (meta.id == 'program_core' || meta.id == 'program_legs')) {
    cautions.add('Skoki zamienione na warianty bez wybicia');
  }
  if (profile.age >= 55) {
    cautions.add('Dłuższe przerwy i łagodniejsza progresja (wiek)');
  }

  return ProgramRecommendation(
    score: score.clamp(0, 100),
    reasons: reasons,
    cautions: cautions,
  );
}

/// Dopasowanie kafelka cardio do profilu (poziom, tryb, waga, wiek, sprzęt).
ProgramRecommendation recommendCardioWorkout(
  CardioWorkoutMeta meta,
  ProgramUserProfile profile,
) {
  var score = 55;
  final reasons = <String>[];
  final cautions = <String>[];

  const order = ['Początkujący', 'Średniozaawansowany', 'Zaawansowany'];
  final userLevel = normalizeTrainingLevel(profile.level);
  final metaLevel = normalizeTrainingLevel(meta.level);
  final distance = (order.indexOf(userLevel) - order.indexOf(metaLevel)).abs();
  if (distance == 0) {
    score += 12;
    reasons.add('Dopasowane do Twojego poziomu');
  } else if (distance == 1) {
    score += 4;
  } else {
    score -= 10;
    cautions.add('Poziom treningu: $metaLevel');
  }

  final highIntensity = meta.intensity.toLowerCase().contains('wysok');
  final gentleNeeded =
      profile.bmi >= 30 || profile.age >= 55 || userLevel == 'Początkujący';
  if (highIntensity && gentleNeeded) {
    score -= 18;
    cautions.add('Wysoka intensywność — zacznij od lżejszego cardio');
  }

  final mode = profile.trainingMode.toLowerCase();
  if (mode.contains('reduk') &&
      (meta.id == 'cardio_fat_burn' ||
          meta.id == 'cardio_walking' ||
          meta.id == 'cardio_beginner')) {
    score += 8;
    reasons.add('Pod tryb: redukcja');
  }
  if (mode.contains('kondy') &&
      (meta.id == 'cardio_endurance' ||
          meta.id == 'cardio_hiit' ||
          meta.id == 'cardio_running')) {
    score += 8;
    reasons.add('Pod tryb: kondycja');
  }
  if (mode.contains('mas') && meta.id == 'cardio_after_strength') {
    score += 6;
    reasons.add('Pod tryb: masa — lekkie dopalenie po siłowni');
  }

  final equipmentNeeded = meta.equipment.toLowerCase();
  if (equipmentNeeded.contains('masa ciała') ||
      equipmentNeeded.contains('masa ciala')) {
    score += 5;
    reasons.add('Bez sprzętu');
  } else if (!_profileHasEquipment(meta.equipment, profile.equipment)) {
    score -= 15;
    cautions.add('Wymaga: ${meta.equipment}');
  }

  final lim = profile.limitations.toLowerCase();
  if (lim.contains('kolan') &&
      (meta.id == 'cardio_hiit' || meta.id == 'cardio_running')) {
    score -= 15;
    cautions.add('Skoki/bieg mogą obciążać kolana');
  }

  return ProgramRecommendation(
    score: score.clamp(0, 100),
    reasons: reasons,
    cautions: cautions,
  );
}

PlanItem _cardioItem(CardioSegment segment, Exercise Function(String) resolve) {
  final exercise = resolve(segment.exerciseId);
  if (segment.reps > 0) {
    return PlanItem(
      exerciseId: segment.exerciseId,
      sets: segment.sets,
      reps: segment.reps,
      durationSec: 0,
      note: segment.note,
      restSeconds: segment.rest,
    );
  }
  final duration = segment.durationSec > 0
      ? segment.durationSec
      : (exercise.defaultDurationSec > 0 ? exercise.defaultDurationSec : 40);
  return PlanItem(
    exerciseId: segment.exerciseId,
    sets: segment.sets,
    reps: 0,
    durationSec: duration,
    note: segment.note,
    restSeconds: segment.rest,
  );
}
