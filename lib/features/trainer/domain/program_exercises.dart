/// Dodatkowa pula ćwiczeń pod 30-dniowe programy treningowe (Etap: programy).
///
/// Czysty Dart — dane ćwiczeń z jawnym mapowaniem na partie mięśniowe
/// ([ExerciseMuscleImpact]) tak, aby regeneracja liczyła się poprawnie
/// (primary = 1.0, secondary = 0.5, stabilizer = 0.25).
///
/// Te ćwiczenia są dołączane do [ExerciseRepo.all] w `main.dart` i przechodzą
/// przez `_withLibraryMetadata` (cele, kroki techniki, oddech itd. dobierane są
/// automatycznie). Dlatego tutaj podajemy minimum: nazwę, kategorię, sprzęt,
/// poziom, typ (czasowe/serie) oraz wpływ na mięśnie.
library;

import 'exercise.dart';

// ── Skróty na role partii ────────────────────────────────────────────────────
ExerciseMuscleImpact _pri(BodyMuscle m) =>
    ExerciseMuscleImpact(muscleGroup: m, role: MuscleRole.primary);
ExerciseMuscleImpact _sec(BodyMuscle m) =>
    ExerciseMuscleImpact(muscleGroup: m, role: MuscleRole.secondary);
ExerciseMuscleImpact _stab(BodyMuscle m) =>
    ExerciseMuscleImpact(muscleGroup: m, role: MuscleRole.stabilizer);

List<String> _muscleLabels(List<ExerciseMuscleImpact> impacts) =>
    impacts.map((i) => i.muscleGroup.label).toList();

/// Ćwiczenie na serie/powtórzenia (opcjonalnie z ciężarem).
Exercise _reps(
  String id,
  String name,
  String category, {
  required List<ExerciseMuscleImpact> impacts,
  String equipment = 'masa ciała',
  String level = 'Początkujący',
  int sets = 3,
  int reps = 12,
  double met = 4.5,
  String illustration = 'generic',
  String description = '',
}) {
  return Exercise(
    id: id,
    name: name,
    category: category,
    muscles: _muscleLabels(impacts),
    equipment: equipment,
    level: level,
    illustrationType: illustration,
    description: description.isEmpty
        ? 'Ćwiczenie na kontrolowane powtórzenia. Utrzymuj technikę i pełen zakres ruchu.'
        : description,
    tips: const [
      'Dobierz ciężar tak, aby utrzymać czystą technikę do ostatniego powtórzenia.',
      'Pracuj w pełnym, kontrolowanym zakresie ruchu.',
    ],
    commonMistakes: const [
      'Zbyt duży ciężar kosztem techniki.',
      'Skracanie zakresu ruchu.',
      'Praca zamachem zamiast kontrolowanym napięciem.',
    ],
    defaultSets: sets,
    defaultReps: reps,
    defaultDurationSec: 0,
    met: met,
    muscleImpacts: impacts,
    source: 'program',
  );
}

/// Ćwiczenie czasowe (izometryczne / rozciąganie / mobilność / kardio).
Exercise _timed(
  String id,
  String name,
  String category, {
  required List<ExerciseMuscleImpact> impacts,
  int durationSec = 40,
  String equipment = 'masa ciała',
  String level = 'Początkujący',
  double met = 3.2,
  String illustration = 'generic',
  String description = '',
}) {
  return Exercise(
    id: id,
    name: name,
    category: category,
    muscles: _muscleLabels(impacts),
    equipment: equipment,
    level: level,
    illustrationType: illustration,
    description: description.isEmpty
        ? 'Ćwiczenie czasowe — utrzymuj napięcie i spokojny, kontrolowany oddech.'
        : description,
    tips: const [
      'Utrzymuj równe, spokojne napięcie przez cały czas.',
      'Oddychaj miarowo, nie wstrzymuj oddechu.',
    ],
    commonMistakes: const [
      'Zbyt szybkie, zamachowe tempo.',
      'Utrata napięcia korpusu.',
      'Wstrzymywanie oddechu.',
    ],
    defaultSets: 1,
    defaultReps: 0,
    defaultDurationSec: durationSec,
    met: met,
    muscleImpacts: impacts,
    source: 'program',
  );
}

// ── KLATKA PIERSIOWA ─────────────────────────────────────────────────────────
final List<Exercise> _chest = [
  _reps('db_bench_press', 'Wyciskanie hantli na ławce płaskiej',
      'Klatka piersiowa',
      equipment: 'hantle / ławka',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 5.0,
      illustration: 'benchPress',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.triceps),
        _sec(BodyMuscle.frontShoulders)
      ]),
  _reps('incline_db_press', 'Wyciskanie hantli na skosie', 'Klatka piersiowa',
      equipment: 'hantle / ławka regulowana',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 5.0,
      illustration: 'benchPress',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.triceps)
      ]),
  _reps(
      'incline_bench_press', 'Wyciskanie sztangi na skosie', 'Klatka piersiowa',
      equipment: 'sztanga / ławka regulowana',
      level: 'Zaawansowany',
      sets: 4,
      reps: 8,
      met: 5.2,
      illustration: 'benchPress',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.triceps)
      ]),
  _reps('db_fly', 'Rozpiętki z hantlami', 'Klatka piersiowa',
      equipment: 'hantle / ławka',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 4.4,
      illustration: 'chestPress',
      impacts: [_pri(BodyMuscle.chest), _stab(BodyMuscle.frontShoulders)]),
  _reps('decline_pushup', 'Pompki z nogami na podwyższeniu', 'Klatka piersiowa',
      equipment: 'masa ciała / ławka',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 4.8,
      illustration: 'pushup',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.triceps),
        _sec(BodyMuscle.frontShoulders),
        _stab(BodyMuscle.abs)
      ]),
  _reps('chest_dip', 'Dipy na klatkę (barierki)', 'Klatka piersiowa',
      equipment: 'barierki / poręcze',
      level: 'Zaawansowany',
      sets: 4,
      reps: 8,
      met: 5.0,
      illustration: 'dips',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.triceps),
        _sec(BodyMuscle.frontShoulders)
      ]),
  _reps('db_pullover', 'Przenoszenie hantla nad głową', 'Klatka piersiowa',
      equipment: 'hantel / ławka',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 4.2,
      illustration: 'chestPress',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.lats),
        _stab(BodyMuscle.triceps)
      ]),
  _reps('diamond_pushup', 'Pompki diamentowe', 'Klatka piersiowa',
      equipment: 'masa ciała',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 4.6,
      illustration: 'pushup',
      impacts: [
        _pri(BodyMuscle.triceps),
        _sec(BodyMuscle.chest),
        _stab(BodyMuscle.frontShoulders)
      ]),
];

// ── BARKI ────────────────────────────────────────────────────────────────────
final List<Exercise> _shoulders = [
  _reps('db_shoulder_press', 'Wyciskanie hantli nad głowę', 'Barki',
      equipment: 'hantle / ławka regulowana',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 4.8,
      illustration: 'shoulderPress',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.triceps),
        _stab(BodyMuscle.traps)
      ]),
  _reps('arnold_press', 'Arnold press', 'Barki',
      equipment: 'hantle / ławka',
      level: 'Zaawansowany',
      sets: 4,
      reps: 10,
      met: 4.8,
      illustration: 'shoulderPress',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.rearShoulders),
        _sec(BodyMuscle.triceps)
      ]),
  _reps('front_raise', 'Unoszenie hantli w przód', 'Barki',
      equipment: 'hantle',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 4.0,
      illustration: 'lateralRaise',
      impacts: [_pri(BodyMuscle.frontShoulders), _stab(BodyMuscle.traps)]),
  _reps('rear_delt_fly', 'Odwrotne rozpiętki (tył barków)', 'Barki',
      equipment: 'hantle',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 14,
      met: 4.0,
      illustration: 'lateralRaise',
      impacts: [
        _pri(BodyMuscle.rearShoulders),
        _sec(BodyMuscle.upperBack),
        _stab(BodyMuscle.traps)
      ]),
  _reps('upright_row', 'Podciąganie sztangi wzdłuż tułowia', 'Barki',
      equipment: 'sztanga / hantle',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 4.4,
      illustration: 'upright',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.traps),
        _stab(BodyMuscle.biceps)
      ]),
  _reps('db_shrug', 'Wzruszanie barków z hantlami', 'Barki',
      equipment: 'hantle / sztanga',
      level: 'Początkujący',
      sets: 3,
      reps: 15,
      met: 3.8,
      illustration: 'shrug',
      impacts: [_pri(BodyMuscle.traps), _stab(BodyMuscle.rearShoulders)]),
  _reps('pike_pushup', 'Pompki w pozycji pike', 'Barki',
      equipment: 'masa ciała',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 10,
      met: 4.6,
      illustration: 'pushup',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.triceps),
        _stab(BodyMuscle.chest)
      ]),
];

// ── RAMIONA (biceps / triceps) ───────────────────────────────────────────────
final List<Exercise> _arms = [
  _reps('hammer_curl', 'Uginanie młotkowe', 'Ręce',
      equipment: 'hantle',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 3.8,
      illustration: 'bicepCurl',
      impacts: [_pri(BodyMuscle.biceps), _sec(BodyMuscle.forearmsFront)]),
  _reps('barbell_curl', 'Uginanie sztangi (biceps)', 'Ręce',
      equipment: 'sztanga',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 4.0,
      illustration: 'bicepCurl',
      impacts: [_pri(BodyMuscle.biceps), _stab(BodyMuscle.forearmsFront)]),
  _reps('incline_db_curl', 'Uginanie hantli na ławce skośnej', 'Ręce',
      equipment: 'hantle / ławka regulowana',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 3.8,
      illustration: 'bicepCurl',
      impacts: [_pri(BodyMuscle.biceps), _stab(BodyMuscle.forearmsFront)]),
  _reps('concentration_curl', 'Uginanie w podporze (koncentryczne)', 'Ręce',
      equipment: 'hantel / ławka',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 3.6,
      illustration: 'bicepCurl',
      impacts: [_pri(BodyMuscle.biceps)]),
  _reps('overhead_triceps_ext', 'Wyciskanie francuskie zza głowy', 'Ręce',
      equipment: 'hantel / sztanga',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 3.8,
      illustration: 'tricepsExtension',
      impacts: [_pri(BodyMuscle.triceps)]),
  _reps('triceps_kickback', 'Prostowanie ramienia w opadzie', 'Ręce',
      equipment: 'hantle',
      level: 'Początkujący',
      sets: 3,
      reps: 14,
      met: 3.6,
      illustration: 'tricepsExtension',
      impacts: [_pri(BodyMuscle.triceps)]),
  _reps('close_grip_bench', 'Wyciskanie wąskim chwytem', 'Ręce',
      equipment: 'sztanga / ławka',
      level: 'Zaawansowany',
      sets: 4,
      reps: 10,
      met: 4.6,
      illustration: 'benchPress',
      impacts: [
        _pri(BodyMuscle.triceps),
        _sec(BodyMuscle.chest),
        _stab(BodyMuscle.frontShoulders)
      ]),
  _reps('bench_dip', 'Dipy na ławce (triceps)', 'Ręce',
      equipment: 'ławka / masa ciała',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 4.2,
      illustration: 'dips',
      impacts: [
        _pri(BodyMuscle.triceps),
        _sec(BodyMuscle.chest),
        _stab(BodyMuscle.frontShoulders)
      ]),
  _reps('skullcrusher', 'Wyciskanie łamane (skullcrusher)', 'Ręce',
      equipment: 'sztanga / hantle / ławka',
      level: 'Zaawansowany',
      sets: 4,
      reps: 10,
      met: 4.0,
      illustration: 'tricepsExtension',
      impacts: [_pri(BodyMuscle.triceps)]),
];

// ── PRZEDRAMIONA ─────────────────────────────────────────────────────────────
final List<Exercise> _forearms = [
  _reps('wrist_curl', 'Uginanie nadgarstków (zginacze)', 'Przedramiona',
      equipment: 'hantle / sztanga',
      level: 'Początkujący',
      sets: 3,
      reps: 15,
      met: 3.4,
      illustration: 'wristCurl',
      impacts: [_pri(BodyMuscle.forearmsFront)]),
  _reps('reverse_wrist_curl', 'Prostowanie nadgarstków (prostowniki)',
      'Przedramiona',
      equipment: 'hantle / sztanga',
      level: 'Początkujący',
      sets: 3,
      reps: 15,
      met: 3.4,
      illustration: 'wristCurl',
      impacts: [_pri(BodyMuscle.forearmsBack)]),
  _reps('reverse_curl', 'Uginanie podchwytem odwrotnym', 'Przedramiona',
      equipment: 'sztanga / hantle',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 12,
      met: 3.6,
      illustration: 'bicepCurl',
      impacts: [_pri(BodyMuscle.forearmsBack), _sec(BodyMuscle.biceps)]),
  _reps('wrist_roller', 'Rolka na przedramiona', 'Przedramiona',
      equipment: 'rolka / obciążenie',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 6,
      met: 3.8,
      illustration: 'wristRoller',
      impacts: [_pri(BodyMuscle.forearmsFront), _sec(BodyMuscle.forearmsBack)]),
  _timed('farmers_carry', 'Marsz farmera', 'Przedramiona',
      equipment: 'hantle / sztanga',
      level: 'Średniozaawansowany',
      durationSec: 40,
      met: 5.0,
      illustration: 'farmerCarry',
      impacts: [
        _pri(BodyMuscle.forearmsFront),
        _sec(BodyMuscle.traps),
        _stab(BodyMuscle.abs)
      ]),
  _timed('dead_hang', 'Zwis na drążku', 'Przedramiona',
      equipment: 'drążek',
      level: 'Początkujący',
      durationSec: 30,
      met: 3.6,
      illustration: 'deadHang',
      impacts: [_pri(BodyMuscle.forearmsFront), _stab(BodyMuscle.lats)]),
];

// ── PLECY ────────────────────────────────────────────────────────────────────
final List<Exercise> _back = [
  _reps('bent_over_row', 'Wiosłowanie sztangą w opadzie', 'Plecy',
      equipment: 'sztanga',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 5.0,
      illustration: 'row',
      impacts: [
        _pri(BodyMuscle.lats),
        _sec(BodyMuscle.upperBack),
        _sec(BodyMuscle.biceps),
        _stab(BodyMuscle.lowerBack)
      ]),
  _reps('one_arm_db_row', 'Wiosłowanie hantlą jednorącz', 'Plecy',
      equipment: 'hantel / ławka',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 4.6,
      illustration: 'row',
      impacts: [
        _pri(BodyMuscle.lats),
        _sec(BodyMuscle.upperBack),
        _sec(BodyMuscle.biceps)
      ]),
  _reps('pendlay_row', 'Wiosłowanie Pendlay', 'Plecy',
      equipment: 'sztanga',
      level: 'Zaawansowany',
      sets: 4,
      reps: 8,
      met: 5.2,
      illustration: 'row',
      impacts: [
        _pri(BodyMuscle.upperBack),
        _sec(BodyMuscle.lats),
        _stab(BodyMuscle.lowerBack)
      ]),
  _reps('chin_up', 'Podciąganie podchwytem', 'Plecy',
      equipment: 'drążek',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 8,
      met: 5.0,
      illustration: 'pullUp',
      impacts: [
        _pri(BodyMuscle.lats),
        _sec(BodyMuscle.biceps),
        _sec(BodyMuscle.upperBack)
      ]),
  _reps('inverted_row', 'Australijskie podciąganie', 'Plecy',
      equipment: 'drążek / barierki',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 4.4,
      illustration: 'row',
      impacts: [
        _pri(BodyMuscle.upperBack),
        _sec(BodyMuscle.lats),
        _sec(BodyMuscle.biceps)
      ]),
  _reps('straight_arm_pulldown', 'Ściąganie wyprostowanych ramion', 'Plecy',
      equipment: 'guma / wyciąg',
      level: 'Początkujący',
      sets: 3,
      reps: 14,
      met: 3.8,
      illustration: 'pull',
      impacts: [_pri(BodyMuscle.lats), _stab(BodyMuscle.triceps)]),
  _reps('back_extension', 'Prostowanie tułowia (hiperekstensje)', 'Plecy',
      equipment: 'ławka / masa ciała',
      level: 'Początkujący',
      sets: 3,
      reps: 15,
      met: 4.0,
      illustration: 'backExtension',
      impacts: [
        _pri(BodyMuscle.lowerBack),
        _sec(BodyMuscle.glutes),
        _sec(BodyMuscle.hamstrings)
      ]),
  _timed('superman', 'Superman', 'Plecy',
      equipment: 'masa ciała',
      level: 'Początkujący',
      durationSec: 30,
      met: 3.2,
      illustration: 'superman',
      impacts: [_pri(BodyMuscle.lowerBack), _sec(BodyMuscle.glutes)]),
];

// ── NOGI ─────────────────────────────────────────────────────────────────────
final List<Exercise> _legs = [
  _reps('romanian_deadlift_db', 'Martwy ciąg rumuński z hantlami', 'Nogi',
      equipment: 'hantle / sztanga',
      level: 'Średniozaawansowany',
      sets: 4,
      reps: 10,
      met: 5.0,
      illustration: 'deadlift',
      impacts: [
        _pri(BodyMuscle.hamstrings),
        _sec(BodyMuscle.glutes),
        _stab(BodyMuscle.lowerBack)
      ]),
  _reps('walking_lunge', 'Wykroki chodzone', 'Nogi',
      equipment: 'masa ciała / hantle',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 5.0,
      illustration: 'lunge',
      impacts: [
        _pri(BodyMuscle.quads),
        _sec(BodyMuscle.glutes),
        _sec(BodyMuscle.hamstrings)
      ]),
  _reps('step_up', 'Wejścia na podwyższenie', 'Nogi',
      equipment: 'ławka / hantle',
      level: 'Początkujący',
      sets: 3,
      reps: 12,
      met: 4.8,
      illustration: 'lunge',
      impacts: [_pri(BodyMuscle.quads), _sec(BodyMuscle.glutes)]),
  _reps('glute_bridge', 'Mostek biodrowy', 'Nogi',
      equipment: 'masa ciała / sztanga',
      level: 'Początkujący',
      sets: 3,
      reps: 15,
      met: 4.0,
      illustration: 'hipThrust',
      impacts: [
        _pri(BodyMuscle.glutes),
        _sec(BodyMuscle.hamstrings),
        _stab(BodyMuscle.abs)
      ]),
  _reps('cossack_squat', 'Przysiad kozacki', 'Nogi',
      equipment: 'masa ciała / hantel',
      level: 'Średniozaawansowany',
      sets: 3,
      reps: 10,
      met: 4.8,
      illustration: 'squat',
      impacts: [
        _pri(BodyMuscle.adductors),
        _sec(BodyMuscle.quads),
        _sec(BodyMuscle.glutes)
      ]),
  _reps('seated_calf_raise', 'Wspięcia na palce siedząc', 'Nogi',
      equipment: 'hantel / masa ciała',
      level: 'Początkujący',
      sets: 4,
      reps: 18,
      met: 3.6,
      illustration: 'calfRaise',
      impacts: [_pri(BodyMuscle.calvesBack), _sec(BodyMuscle.calvesFront)]),
  _reps('tibialis_raise', 'Unoszenie stóp (piszczele)', 'Nogi',
      equipment: 'masa ciała / obciążenie',
      level: 'Początkujący',
      sets: 3,
      reps: 18,
      met: 3.2,
      illustration: 'calfRaise',
      impacts: [_pri(BodyMuscle.tibialis)]),
  _timed('wall_sit', 'Przysiad izometryczny (wall sit)', 'Nogi',
      equipment: 'masa ciała',
      level: 'Początkujący',
      durationSec: 40,
      met: 4.0,
      illustration: 'squat',
      impacts: [_pri(BodyMuscle.quads), _stab(BodyMuscle.glutes)]),
];

// ── ROZCIĄGANIE / MOBILNOŚĆ (czasowe) ────────────────────────────────────────
final List<Exercise> _stretches = [
  _timed('child_pose', 'Pozycja dziecka', 'Rozciąganie',
      durationSec: 40,
      met: 2.3,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.lowerBack), _sec(BodyMuscle.lats)]),
  _timed('cobra_stretch', 'Kobra (rozciąganie brzucha)', 'Rozciąganie',
      durationSec: 30,
      met: 2.3,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.abs), _sec(BodyMuscle.lowerBack)]),
  _timed('cat_cow', 'Koci grzbiet (cat-cow)', 'Rozciąganie',
      durationSec: 40,
      met: 2.5,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.lowerBack), _sec(BodyMuscle.abs)]),
  _timed('hamstring_stretch', 'Rozciąganie dwugłowych ud', 'Rozciąganie',
      durationSec: 36,
      met: 2.3,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.hamstrings), _sec(BodyMuscle.calvesBack)]),
  _timed('quad_stretch', 'Rozciąganie czworogłowych', 'Rozciąganie',
      durationSec: 36,
      met: 2.3,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.quads), _stab(BodyMuscle.hipFlexors)]),
  _timed('hip_flexor_stretch', 'Rozciąganie zginaczy bioder', 'Rozciąganie',
      durationSec: 36,
      met: 2.3,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.hipFlexors), _sec(BodyMuscle.glutes)]),
  _timed('calf_stretch', 'Rozciąganie łydek', 'Rozciąganie',
      durationSec: 30,
      met: 2.2,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.calvesBack), _sec(BodyMuscle.calvesFront)]),
  _timed(
      'chest_doorway_stretch', 'Rozciąganie klatki w drzwiach', 'Rozciąganie',
      durationSec: 30,
      met: 2.2,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.chest), _sec(BodyMuscle.frontShoulders)]),
  _timed(
      'shoulder_cross_stretch', 'Rozciąganie barków (w poprzek)', 'Rozciąganie',
      durationSec: 30,
      met: 2.2,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.rearShoulders), _stab(BodyMuscle.traps)]),
  _timed('triceps_stretch', 'Rozciąganie tricepsa', 'Rozciąganie',
      durationSec: 28,
      met: 2.2,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.triceps), _stab(BodyMuscle.lats)]),
  _timed('forearm_stretch', 'Rozciąganie przedramion', 'Rozciąganie',
      durationSec: 28,
      met: 2.1,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.forearmsFront), _sec(BodyMuscle.forearmsBack)]),
  _timed('neck_stretch', 'Rozciąganie szyi i karku', 'Rozciąganie',
      durationSec: 28,
      met: 2.1,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.sternocleidomastoid), _stab(BodyMuscle.traps)]),
  _timed('pigeon_pose', 'Pozycja gołębia', 'Rozciąganie',
      durationSec: 40,
      met: 2.4,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.glutes), _sec(BodyMuscle.hipFlexors)]),
  _timed('thread_the_needle', 'Nawlekanie igły (mobilność klatki piersiowej)',
      'Rozciąganie',
      durationSec: 34,
      met: 2.4,
      illustration: 'stretch',
      impacts: [_pri(BodyMuscle.upperBack), _sec(BodyMuscle.rearShoulders)]),
  _timed('downward_dog', 'Pies z głową w dół', 'Rozciąganie',
      durationSec: 36,
      met: 2.8,
      illustration: 'stretch',
      impacts: [
        _pri(BodyMuscle.hamstrings),
        _sec(BodyMuscle.calvesBack),
        _stab(BodyMuscle.frontShoulders)
      ]),
];

// ── ROZGRZEWKA / MOBILNOŚĆ WSTĘPNA (czasowe) ─────────────────────────────────
//
// Pula jest celowo rozbita POD PARTIE, a nie ogólna: rozgrzewka ma przygotować
// stawy i mięśnie, które za chwilę pracują. Wymachy nóg przed wyciskaniem nic
// nie wnoszą, a kosztują czas — dlatego każdy program dobiera swoje pozycje
// (patrz pule `warmup:` w workout_programs_catalog.dart).
final List<Exercise> _warmups = [
  // — Ogólne / tułów —
  _timed('arm_circles', 'Krążenia ramion', 'Rozgrzewka',
      durationSec: 30,
      met: 3.2,
      illustration: 'armCircles',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.rearShoulders)
      ]),
  _timed('torso_twist', 'Skręty tułowia', 'Rozgrzewka',
      durationSec: 30,
      met: 3.2,
      illustration: 'twist',
      impacts: [_pri(BodyMuscle.obliques), _stab(BodyMuscle.abs)]),
  _timed('leg_swings', 'Wymachy nóg', 'Rozgrzewka',
      durationSec: 30,
      met: 3.4,
      illustration: 'legSwing',
      impacts: [_pri(BodyMuscle.hipFlexors), _sec(BodyMuscle.hamstrings)]),
  _timed('world_greatest_stretch', 'Najlepszy stretch świata', 'Rozgrzewka',
      durationSec: 40,
      met: 3.4,
      illustration: 'stretch',
      impacts: [
        _pri(BodyMuscle.hipFlexors),
        _sec(BodyMuscle.hamstrings),
        _stab(BodyMuscle.upperBack)
      ]),

  // — Klatka i obręcz barkowa (pod wyciskania, pompki, dipy) —
  _timed('scapular_pushup', 'Pompka łopatkowa', 'Rozgrzewka',
      durationSec: 30,
      met: 3.4,
      illustration: 'generic',
      description:
          'W podporze przodem ściągaj i rozsuwaj łopatki bez zginania łokci. Budzi stabilizatory barku przed wyciskaniem.',
      impacts: [
        _pri(BodyMuscle.chest),
        _sec(BodyMuscle.frontShoulders),
        _stab(BodyMuscle.traps)
      ]),
  _timed('doorway_chest_opener', 'Otwarcie klatki w ościeżnicy', 'Rozgrzewka',
      durationSec: 30,
      met: 2.8,
      illustration: 'stretch',
      description:
          'Przedramiona na framudze, krok do przodu. Delikatne rozciągnięcie klatki przed pracą nad głową.',
      impacts: [_pri(BodyMuscle.chest), _sec(BodyMuscle.frontShoulders)]),

  // — Barki (rotatory, praca nad głową) —
  _timed('wall_slides', 'Ślizgi łopatek po ścianie', 'Rozgrzewka',
      durationSec: 30,
      met: 3.0,
      illustration: 'generic',
      description:
          'Plecy i przedramiona przy ścianie, ślizgaj ręce w górę bez odrywania. Mobilizuje barki przed wyciskaniem nad głowę.',
      impacts: [
        _pri(BodyMuscle.frontShoulders),
        _sec(BodyMuscle.upperBack),
        _stab(BodyMuscle.traps)
      ]),
  _timed('shoulder_external_rotation', 'Rotacje zewnętrzne barku', 'Rozgrzewka',
      durationSec: 30,
      met: 2.9,
      illustration: 'generic',
      equipment: 'guma oporowa',
      description:
          'Łokcie przy tułowiu, rotuj przedramiona na zewnątrz. Aktywuje rotatory przed ciężką pracą barku.',
      impacts: [_pri(BodyMuscle.rearShoulders), _stab(BodyMuscle.upperBack)]),
  _timed('band_pull_apart', 'Odwodzenie gumą (band pull-apart)', 'Rozgrzewka',
      durationSec: 30,
      met: 3.0,
      illustration: 'generic',
      equipment: 'guma oporowa',
      description:
          'Guma na wyprostowanych rękach, rozciągaj ją ściągając łopatki. Budzi tył barku i górne plecy.',
      impacts: [_pri(BodyMuscle.rearShoulders), _sec(BodyMuscle.upperBack)]),

  // — Plecy (łopatki, odcinek piersiowy) —
  _timed('scapular_pull', 'Ściąganie łopatek w zwisie', 'Rozgrzewka',
      durationSec: 30,
      met: 3.2,
      illustration: 'generic',
      equipment: 'drążek',
      description:
          'W zwisie ściągaj łopatki w dół bez zginania łokci. Uczy inicjacji ciągnięcia przed podciąganiem.',
      impacts: [
        _pri(BodyMuscle.lats),
        _sec(BodyMuscle.upperBack),
        _stab(BodyMuscle.traps)
      ]),
  _timed('thoracic_rotation', 'Rotacje piersiowe w klęku', 'Rozgrzewka',
      durationSec: 36,
      met: 2.9,
      illustration: 'stretch',
      description:
          'W klęku ręka za głową, rotuj tułów otwierając klatkę do sufitu. Mobilizuje odcinek piersiowy przed wiosłowaniem.',
      impacts: [_pri(BodyMuscle.upperBack), _sec(BodyMuscle.obliques)]),

  // — Nogi (biodra, kolana, kostki) —
  _timed('hip_circles', 'Krążenia bioder', 'Rozgrzewka',
      durationSec: 30,
      met: 3.2,
      illustration: 'generic',
      description:
          'Szerokie krążenia biodrami w obie strony. Rozrusza staw biodrowy przed przysiadami.',
      impacts: [_pri(BodyMuscle.hipFlexors), _sec(BodyMuscle.glutes)]),
  _timed('ankle_rocks', 'Mobilizacja kostek (knee-to-wall)', 'Rozgrzewka',
      durationSec: 30,
      met: 2.8,
      illustration: 'generic',
      description:
          'Kolano do ściany bez odrywania pięty, kołysz w przód i w tył. Otwiera kostkę przed głębokim przysiadem.',
      impacts: [_pri(BodyMuscle.calvesBack), _sec(BodyMuscle.tibialis)]),

  // — Przedramiona i chwyt —
  _timed('wrist_circles', 'Krążenia nadgarstków', 'Rozgrzewka',
      durationSec: 30,
      met: 2.6,
      illustration: 'generic',
      description:
          'Splecione dłonie, krążenia w obie strony. Przygotowuje nadgarstki do chwytu i podporów.',
      impacts: [_pri(BodyMuscle.forearmsFront), _sec(BodyMuscle.forearmsBack)]),
];

// ── KARDIO (czasowe) — pod szybkie treningi cardio z zakładki „Trening" ──────
final List<Exercise> _cardio = [
  _timed('march_steady', 'Marsz / szybki chód', 'Kardio',
      durationSec: 600,
      met: 4.3,
      illustration: 'run',
      level: 'Początkujący',
      description:
          'Energiczny marsz w miejscu albo w terenie. Najprostsze cardio o niskiej intensywności — pracuj rytmicznie rękami i utrzymuj równe tempo.',
      impacts: [
        _pri(BodyMuscle.calvesBack),
        _sec(BodyMuscle.quads),
        _sec(BodyMuscle.hipFlexors),
        _stab(BodyMuscle.abs)
      ]),
  _timed('step_touch', 'Step touch (krok boczny)', 'Kardio',
      durationSec: 45,
      met: 3.6,
      illustration: 'jumpingJack',
      level: 'Początkujący',
      description:
          'Lekki krok boczny z dostawieniem i pracą ramion. Bardzo niskie obciążenie stawów — idealne na start i regenerację.',
      impacts: [
        _pri(BodyMuscle.calvesBack),
        _sec(BodyMuscle.adductors),
        _stab(BodyMuscle.glutes)
      ]),
  _timed('skater_hops', 'Łyżwiarz (skater hops)', 'Kardio',
      durationSec: 40,
      met: 7.0,
      illustration: 'jumpingJack',
      level: 'Średniozaawansowany',
      description:
          'Dynamiczne przeskoki z nogi na nogę jak łyżwiarz. Buduje kondycję, stabilizację kolan i siłę pośladków.',
      impacts: [
        _pri(BodyMuscle.glutes),
        _sec(BodyMuscle.quads),
        _sec(BodyMuscle.calvesBack),
        _stab(BodyMuscle.abs)
      ]),
  _timed('butt_kicks', 'Bieg z piętami do pośladków', 'Kardio',
      durationSec: 40,
      met: 7.5,
      illustration: 'highKnees',
      level: 'Początkujący',
      description:
          'Rytmiczny bieg w miejscu z uderzaniem piętami o pośladki. Rozgrzewa dwugłowe uda i podbija tętno.',
      impacts: [
        _pri(BodyMuscle.hamstrings),
        _sec(BodyMuscle.calvesBack),
        _stab(BodyMuscle.hipFlexors)
      ]),
];

/// Pełna pula dodatkowych ćwiczeń dołączana do [ExerciseRepo.all].
final List<Exercise> kProgramExercises = [
  ..._chest,
  ..._shoulders,
  ..._arms,
  ..._forearms,
  ..._back,
  ..._legs,
  ..._stretches,
  ..._warmups,
  ..._cardio,
];
