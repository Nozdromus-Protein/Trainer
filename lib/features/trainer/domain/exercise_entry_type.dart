/// Typy wpisów danych ćwiczeń (Etap: przebudowa wpisów serii).
///
/// Czysty Dart. Każde ćwiczenie ma przypisany typ wpisu, na podstawie którego
/// UI pokazuje właściwe pola (powtórzenia / ciężar roboczy / dodatkowy ciężar /
/// czas / dystans). Ćwiczenia bez jawnego typu dostają typ wyprowadzony
/// heurystycznie z kategorii, sprzętu i czasu domyślnego ([deriveEntryType]).
library;

/// Typ wpisu danych dla ćwiczenia.
enum ExerciseEntryType {
  /// Tylko powtórzenia (np. proste ćwiczenia bez obciążenia i bez masy ciała).
  repsOnly('reps_only', 'Powtórzenia'),

  /// Powtórzenia + ciężar zewnętrzny (sztanga, hantle, maszyna).
  repsWeight('reps_weight', 'Powtórzenia + ciężar'),

  /// Masa własnego ciała + powtórzenia (pompki, podciąganie).
  bodyweightReps('bodyweight_reps', 'Masa ciała + powtórzenia'),

  /// Masa własnego ciała + czas (deska, mountain climber).
  bodyweightTime('bodyweight_time', 'Masa ciała + czas'),

  /// Masa ciała ze wspomaganiem (guma/maszyna asystująca, np. podciąganie z gumą).
  assistedBodyweight('assisted_bodyweight', 'Masa ciała ze wspomaganiem'),

  /// Tylko czas (np. erg, wall sit z obciążeniem trzymanym statycznie).
  timeOnly('time_only', 'Czas'),

  /// Cardio: dystans + czas (bieg, rower — wpis ręczny).
  cardioDistanceTime('cardio_distance_time', 'Cardio: dystans + czas'),

  /// Cardio mierzone przez Health Connect / zegarek (wpis automatyczny).
  cardioHealthConnect('cardio_health_connect', 'Cardio z Health Connect'),

  /// Mobilność / rozciąganie (czas, bez obciążenia i RPE traktowane lekko).
  mobility('mobility', 'Mobilność / rozciąganie');

  const ExerciseEntryType(this.key, this.label);

  /// Klucz serializacji (snake_case, zgodny ze specyfikacją etapu).
  final String key;

  /// Czytelna etykieta PL.
  final String label;

  static ExerciseEntryType? fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final type in ExerciseEntryType.values) {
      if (type.key == normalized || type.name == normalized) return type;
    }
    return null;
  }

  /// Czy panel wpisu pokazuje pole „Powtórzenia".
  bool get showsReps {
    switch (this) {
      case ExerciseEntryType.repsOnly:
      case ExerciseEntryType.repsWeight:
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.assistedBodyweight:
        return true;
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.timeOnly:
      case ExerciseEntryType.cardioDistanceTime:
      case ExerciseEntryType.cardioHealthConnect:
      case ExerciseEntryType.mobility:
        return false;
    }
  }

  /// Czy panel wpisu pokazuje pole ciężaru (etykieta w [weightFieldLabel]).
  bool get showsWeight {
    switch (this) {
      case ExerciseEntryType.repsWeight:
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.assistedBodyweight:
        return true;
      case ExerciseEntryType.repsOnly:
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.timeOnly:
      case ExerciseEntryType.cardioDistanceTime:
      case ExerciseEntryType.cardioHealthConnect:
      case ExerciseEntryType.mobility:
        return false;
    }
  }

  /// Czy panel wpisu pokazuje pole czasu serii.
  bool get showsDuration {
    switch (this) {
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.timeOnly:
      case ExerciseEntryType.cardioDistanceTime:
      case ExerciseEntryType.cardioHealthConnect:
      case ExerciseEntryType.mobility:
        return true;
      case ExerciseEntryType.repsOnly:
      case ExerciseEntryType.repsWeight:
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.assistedBodyweight:
        return false;
    }
  }

  /// Czy panel wpisu pokazuje pole dystansu (cardio — ręczne i z zegarka;
  /// przy zapisie z Health Connect dystans można też wpisać/skorygować ręcznie).
  bool get showsDistance =>
      this == ExerciseEntryType.cardioDistanceTime ||
      this == ExerciseEntryType.cardioHealthConnect;

  /// Czy RPE ma sens dla tego typu (mobilność go nie potrzebuje).
  bool get showsRpe => this != ExerciseEntryType.mobility;

  /// Czy ćwiczenie bazuje na masie własnego ciała (info dla użytkownika,
  /// masa liczona z profilu — pole ciężaru to tylko dodatek/wspomaganie).
  bool get usesBodyweight {
    switch (this) {
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.assistedBodyweight:
        return true;
      default:
        return false;
    }
  }

  // ===== Metadane progresji (Etap: progresja zależna od typu ćwiczenia) =====
  //
  // Każdy typ wpisu jawnie deklaruje, jakie sposoby progresji są sensowne.
  // Silnik rekomendacji i podsumowanie NIE proponują progresji, której dany
  // typ nie obsługuje (np. „Dodaj 1 kg" dla deski czy rozciągania).

  /// Czy ćwiczenie może być progresowane zwiększaniem ciężaru zewnętrznego.
  /// Tylko klasyczne ćwiczenia z ciężarem roboczym (sztanga/hantle/maszyna).
  bool get supportsWeightProgression => this == ExerciseEntryType.repsWeight;

  /// Czy ćwiczenie w ogóle korzysta z dodatkowego/zewnętrznego obciążenia
  /// (pole ciężaru istnieje: ciężar roboczy, dodatkowy ciężar, wspomaganie).
  bool get supportsExternalLoad => showsWeight;

  /// Czy sensowna jest progresja przez zwiększanie powtórzeń.
  bool get supportsRepProgression => showsReps;

  /// Czy sensowna jest progresja przez dodanie serii.
  bool get supportsSetProgression {
    switch (this) {
      case ExerciseEntryType.cardioDistanceTime:
      case ExerciseEntryType.cardioHealthConnect:
        return false;
      default:
        return true;
    }
  }

  /// Czy sensowna jest progresja przez wydłużanie czasu serii.
  bool get supportsDurationProgression {
    switch (this) {
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.timeOnly:
      case ExerciseEntryType.mobility:
        return true;
      default:
        return false;
    }
  }

  /// Czy sensowna jest progresja przez dystans (cardio).
  bool get supportsDistanceProgression => showsDistance;

  /// Czy sensowna jest progresja przez tempo/intensywność (cardio).
  bool get supportsPaceProgression => showsDistance;

  /// Czy sensowna jest progresja przez trudniejszy wariant ćwiczenia
  /// (masa ciała / izometria — gdy powtórzenia/czas dojdą do górnego pułapu).
  bool get supportsHarderVariation {
    switch (this) {
      case ExerciseEntryType.repsOnly:
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.bodyweightTime:
      case ExerciseEntryType.assistedBodyweight:
      case ExerciseEntryType.timeOnly:
        return true;
      default:
        return false;
    }
  }

  /// Czytelny opis głównego trybu progresji (do UI/wyjaśnień).
  String get progressionMode {
    if (supportsWeightProgression) return 'ciężar';
    if (this == ExerciseEntryType.mobility) return 'jakość ruchu';
    if (supportsDurationProgression) return 'czas';
    if (supportsDistanceProgression) return 'dystans / tempo';
    if (usesBodyweight) return 'powtórzenia / trudniejszy wariant';
    if (supportsRepProgression) return 'powtórzenia';
    return 'utrzymanie';
  }

  /// Etykieta pola ciężaru zależna od typu wpisu.
  String get weightFieldLabel {
    switch (this) {
      case ExerciseEntryType.bodyweightReps:
        return 'Dodatkowy ciężar (kg)';
      case ExerciseEntryType.assistedBodyweight:
        return 'Wspomaganie (kg)';
      default:
        return 'Ciężar roboczy (kg)';
    }
  }

  /// Podpowiedź pod panelem wpisu (pusta, gdy niepotrzebna).
  String get helperText {
    switch (this) {
      case ExerciseEntryType.bodyweightReps:
      case ExerciseEntryType.bodyweightTime:
        return 'Masa ciała liczona automatycznie z profilu. Wpisz tylko dodatkowy ciężar, jeśli go używasz.';
      case ExerciseEntryType.assistedBodyweight:
        return 'Wpisz, ile kg wspomagania (guma / maszyna) użyto — im mniej, tym trudniej.';
      case ExerciseEntryType.cardioHealthConnect:
        return 'Ta aktywność może być też mierzona przez zegarek / Health Connect.';
      default:
        return '';
    }
  }
}

/// Od jakiego czasu trwania ćwiczenie „w ruchu" ma sens jako cardio z dystansem.
/// Krótsze drille (40–60 s w obwodzie) prowadzi się czasem, nie kilometrami.
const int _kCardioDistanceMinSeconds = 300;

/// PEŁNE słowa oznaczające przemieszczanie się. Świadomie bez dopasowania po
/// fragmencie: „run" siedzi w „crunches", „chod" w „chodzone", a „bieg"
/// w „przebiegu" — każde takie trafienie zamieniało ćwiczenie siłowe w cardio.
const Set<String> _kCardioWords = {
  'bieg', 'biegu', 'biegi', 'bieganie', 'biegowy', 'biegowe', //
  'bieżnia', 'bieznia', 'bieżni', 'biezni',
  'jog', 'jogging', 'run', 'running', 'sprint', 'sprinty',
  'marsz', 'marszu', 'marszem', 'spacer', 'spaceru',
  'chód', 'chod', 'chodu', 'chodem',
  'rower', 'roweru', 'rowerze', 'rowerowy', 'bike', 'cycling',
  'orbitrek', 'orbitreku', 'ergometr', 'ergometrze',
  'kardio', 'cardio', 'walk', 'walking', 'nordic',
};

bool _hasCardioWord(String text) {
  for (final token in text.split(RegExp(r'[^a-ząćęłńóśźż]+'))) {
    if (token.isNotEmpty && _kCardioWords.contains(token)) return true;
  }
  return false;
}

bool _isCardioEquipment(String equipment) =>
    equipment.contains('bież') ||
    equipment.contains('biez') ||
    equipment.contains('orbitrek') ||
    equipment.contains('ergometr') ||
    equipment.contains('rower');

/// Heurystyczne wyprowadzenie typu wpisu dla ćwiczenia bez jawnego przypisania.
///
/// Kolejność ma znaczenie: mobilność → **ćwiczenie na powtórzenia** → cardio →
/// czasowe → masa ciała → ciężar.
///
/// [defaultReps] rozstrzyga konflikt „ile powtórzeń kontra ile sekund". Bez
/// niego dopasowanie po fragmencie nazwy wygrywało z twardymi danymi ćwiczenia:
/// „Wykroki **chod**zone" (3 × 12 powtórzeń) trafiały na słowo kluczowe „chód"
/// i dostawały panel cardio z dystansem i czasem, mimo że karta ćwiczenia
/// pokazywała serie i powtórzenia. Ćwiczenie z dodatnimi powtórzeniami i bez
/// czasu domyślnego JEST powtórzeniowe — żadne słowo w nazwie tego nie zmienia.
ExerciseEntryType deriveEntryType({
  required String name,
  required String category,
  required String equipment,
  required int defaultDurationSec,
  int defaultReps = 0,
}) {
  final text = '$name $category'.toLowerCase();
  final eq = equipment.toLowerCase();

  bool hasAny(List<String> keys) => keys.any(text.contains);

  bool isBodyweightEquipment() =>
      (eq.contains('masa ciała') ||
          eq.contains('masa ciala') ||
          eq.contains('bez sprzętu') ||
          eq.contains('bez sprzetu') ||
          eq.contains('brak') ||
          eq.trim().isEmpty ||
          eq.contains('mata') ||
          eq.contains('drążek') ||
          eq.contains('drazek')) &&
      !eq.contains('sztang') &&
      !eq.contains('hant') &&
      !eq.contains('kett') &&
      !eq.contains('maszyn') &&
      !eq.contains('wyciąg') &&
      !eq.contains('wyciag');

  if (hasAny([
    'mobil',
    'rozciąg',
    'rozciag',
    'stretch',
    'rozgrzew',
    'krążenia',
    'krazenia'
  ])) {
    return ExerciseEntryType.mobility;
  }

  // Twarde dane ćwiczenia biją heurystykę z nazwy.
  if (defaultReps > 0 && defaultDurationSec <= 0) {
    return isBodyweightEquipment()
        ? ExerciseEntryType.bodyweightReps
        : ExerciseEntryType.repsWeight;
  }

  // Cardio z DYSTANSEM to przemieszczanie się w terenie, a nie każdy ruch,
  // w którego nazwie padnie słowo kojarzone z bieganiem. Stąd dwa warunki:
  // dopasowanie CAŁYCH SŁÓW (nie fragmentów) oraz realny czas trwania albo
  // sprzęt cardio. Bez tego „C(run)ches" łapało się na „run", a 40-sekundowy
  // „Bieg z piętami do pośladków" dostawał pole „Dystans (km)".
  final locomotion = _hasCardioWord(text) || _isCardioEquipment(eq);
  if (locomotion &&
      (defaultDurationSec >= _kCardioDistanceMinSeconds ||
          _isCardioEquipment(eq))) {
    return ExerciseEntryType.cardioDistanceTime;
  }

  final bodyweightOnly = (eq.contains('masa ciała') ||
          eq.contains('masa ciala') ||
          eq.contains('bez sprzętu') ||
          eq.contains('bez sprzetu') ||
          eq.contains('brak') ||
          eq.trim().isEmpty ||
          eq.contains('mata') ||
          eq.contains('drążek') ||
          eq.contains('drazek')) &&
      !eq.contains('sztang') &&
      !eq.contains('hant') &&
      !eq.contains('kett') &&
      !eq.contains('maszyn') &&
      !eq.contains('wyciąg') &&
      !eq.contains('wyciag');

  if (defaultDurationSec > 0) {
    return bodyweightOnly
        ? ExerciseEntryType.bodyweightTime
        : ExerciseEntryType.timeOnly;
  }
  if (bodyweightOnly) {
    // Podciąganie / dipy często robi się z gumą — ale bez jawnych danych
    // traktujemy je jak zwykłe bodyweight_reps (dodatkowy ciężar >= 0).
    return ExerciseEntryType.bodyweightReps;
  }
  return ExerciseEntryType.repsWeight;
}

/// Jawne przypisania typu wpisu dla lokalnej bazy ćwiczeń (id → typ).
/// Ćwiczenia spoza mapy dostają typ z [deriveEntryType].
const Map<String, ExerciseEntryType> kExerciseEntryTypeOverrides = {
  // Klatka / ramiona — masa ciała.
  'pushup': ExerciseEntryType.bodyweightReps,
  'diamond_pushup': ExerciseEntryType.bodyweightReps,
  'wide_pushup': ExerciseEntryType.bodyweightReps,
  'incline_pushup': ExerciseEntryType.bodyweightReps,
  'decline_pushup': ExerciseEntryType.bodyweightReps,
  'pike_pushup': ExerciseEntryType.bodyweightReps,
  'dips': ExerciseEntryType.bodyweightReps,
  'bench_dips': ExerciseEntryType.bodyweightReps,
  // Plecy — drążek.
  'pullup': ExerciseEntryType.bodyweightReps,
  'chinup': ExerciseEntryType.bodyweightReps,
  'assisted_pullup': ExerciseEntryType.assistedBodyweight,
  'australian_pullup': ExerciseEntryType.bodyweightReps,
  // Core — czasowe.
  'plank': ExerciseEntryType.bodyweightTime,
  'side_plank': ExerciseEntryType.bodyweightTime,
  'mountain_climber': ExerciseEntryType.bodyweightTime,
  'hollow_body': ExerciseEntryType.bodyweightTime,
  'dead_bug': ExerciseEntryType.bodyweightTime,
  'bird_dog': ExerciseEntryType.bodyweightTime,
  'wall_sit': ExerciseEntryType.bodyweightTime,
  // Core — powtórzeniowe z masą ciała.
  'crunch': ExerciseEntryType.bodyweightReps,
  'russian_twist': ExerciseEntryType.bodyweightReps,
  'leg_raise': ExerciseEntryType.bodyweightReps,
  'hanging_leg_raise': ExerciseEntryType.bodyweightReps,
  'bicycle_crunch': ExerciseEntryType.bodyweightReps,
  'reverse_crunch': ExerciseEntryType.bodyweightReps,
  'situp': ExerciseEntryType.bodyweightReps,
  'v_up': ExerciseEntryType.bodyweightReps,
  // Nogi — masa ciała / ciężar.
  'squat': ExerciseEntryType.bodyweightReps,
  'lunge': ExerciseEntryType.bodyweightReps,
  'reverse_lunge': ExerciseEntryType.bodyweightReps,
  'glute_bridge': ExerciseEntryType.bodyweightReps,
  'calf_raise': ExerciseEntryType.bodyweightReps,
  'goblet_squat': ExerciseEntryType.repsWeight,
  'front_squat': ExerciseEntryType.repsWeight,
  'bulgarian_split_squat': ExerciseEntryType.repsWeight,
  'deadlift': ExerciseEntryType.repsWeight,
  'hip_thrust': ExerciseEntryType.repsWeight,
  // Siłowe klasyki.
  'bench_press': ExerciseEntryType.repsWeight,
  'shoulder_press': ExerciseEntryType.repsWeight,
  'row': ExerciseEntryType.repsWeight,
  'lat_pulldown': ExerciseEntryType.repsWeight,
  'bicep_curl': ExerciseEntryType.repsWeight,
  'triceps_extension': ExerciseEntryType.repsWeight,
  'lateral_raise': ExerciseEntryType.repsWeight,
  // Cardio mierzone przez zegarek / Health Connect (bieg, chód, rower) —
  // panel pokazuje czas + dystans, a wpis może przyjść też z zegarka.
  'run': ExerciseEntryType.cardioHealthConnect,
  'jog': ExerciseEntryType.cardioHealthConnect,
  'walk': ExerciseEntryType.cardioHealthConnect,
  'bike': ExerciseEntryType.cardioHealthConnect,
  'burpee': ExerciseEntryType.bodyweightReps,
  'jumping_jacks': ExerciseEntryType.bodyweightTime,
  'high_knees': ExerciseEntryType.bodyweightTime,
};
