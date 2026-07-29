/// Inteligentny planer tygodnia treningowego (Etap: propozycje na „Dzisiaj").
///
/// Czysty Dart. Na podstawie mapy regeneracji mięśni, historii (RPE, objętość),
/// cardio, profilu i dostępnych dni treningowych proponuje:
///  - co trenować dzisiaj i czego unikać,
///  - jak rozłożyć partie na najbliższy tydzień,
///  - które programy 30-dniowe pasują do aktualnego stanu regeneracji,
///  - kiedy zrobić lżejszy dzień / cardio / mobilność.
///
/// Planer jest doradczy — niczego nie wymusza i nie modyfikuje danych.
library;

import '../domain/activity_credit.dart';
import '../domain/exercise.dart';
import '../domain/exercise_intensity.dart';
import '../domain/muscle_recovery.dart';
import '../domain/workout_session.dart';
import 'workout_programs_catalog.dart';

/// Obszar treningowy planowany w tygodniu.
///
/// Obszary dzielą się na DWA TORY (kolumny rozkładu tygodnia):
///  - PIERWSZORZĘDNE ([kPrimaryFocusAreas]) — duże partie, które niosą trening:
///    klatka, plecy, nogi, brzuch. To one wypełniają główną część dnia.
///  - DRUGORZĘDNE ([kSecondaryFocusAreas]) — dodatek doklejany do dnia (barki,
///    ramiona, przedramiona, bieg), dzięki czemu każda partia mieści się
///    w tygodniu dwa razy bez rozbijania dni na kolejne treningi.
///
/// Nazwy stałych (`chestTriceps`, `backBiceps`) zostają dla zgodności zapisu —
/// zmieniły się tylko etykiety, bo biceps/triceps mają teraz własny obszar.
enum TrainingFocusArea {
  // — tor pierwszorzędny —
  //
  // Drugi argument to WSZYSTKIE partie, które ten dzień obciąża (do prognoz
  // i ostrzeżeń), trzeci — partie DEFINIUJĄCE obszar ([signatureMuscles]).
  // Rozdzielenie jest kluczowe: triceps i przedni bark PRACUJĄ w dniu klatki,
  // ale nie są „klatką". Bez tego dzień klatki wypadał jako niegotowy po dniu
  // barków, a zestaw barków znikał z dnia klatki — mimo że to normalny trening.
  chestTriceps(
    'Klatka piersiowa',
    [BodyMuscle.chest, BodyMuscle.triceps, BodyMuscle.frontShoulders],
    [BodyMuscle.chest],
  ),
  backBiceps(
    'Plecy',
    [
      BodyMuscle.lats,
      BodyMuscle.upperBack,
      BodyMuscle.biceps,
      BodyMuscle.rearShoulders
    ],
    [BodyMuscle.lats, BodyMuscle.upperBack],
  ),
  legs('Nogi', [
    BodyMuscle.quads,
    BodyMuscle.hamstrings,
    BodyMuscle.glutes,
    BodyMuscle.calvesBack
  ]),
  core('Brzuch / core', [BodyMuscle.abs, BodyMuscle.obliques]),
  // — tor pierwszorzędny w strategii Push / Pull / Legs —
  //
  // Push i Pull to CAŁE bloki ruchu, nie pojedyncze partie: dzień pchania
  // obciąża klatkę, przedni bark i triceps, dzień ciągnięcia — plecy, tylny
  // bark, biceps i przedramiona. Dzięki temu regeneracja liczona dla bloku
  // uwzględnia wszystko, co ten dzień realnie męczy.
  push('Push (pchanie)', [
    BodyMuscle.chest,
    BodyMuscle.frontShoulders,
    BodyMuscle.triceps,
    BodyMuscle.serratusAnterior,
  ]),
  pull(
    'Pull (ciągnięcie)',
    [
      BodyMuscle.lats,
      BodyMuscle.upperBack,
      BodyMuscle.rhomboids,
      BodyMuscle.rearShoulders,
      BodyMuscle.biceps,
      BodyMuscle.forearmsFront,
      BodyMuscle.traps,
    ],
    [BodyMuscle.lats, BodyMuscle.upperBack, BodyMuscle.biceps],
  ),
  // — tor drugorzędny —
  shoulders('Barki',
      [BodyMuscle.frontShoulders, BodyMuscle.rearShoulders, BodyMuscle.traps]),
  arms('Ramiona (biceps / triceps)', [BodyMuscle.biceps, BodyMuscle.triceps]),
  forearms('Przedramiona',
      [BodyMuscle.forearmsFront, BodyMuscle.forearmsBack]),
  cardio('Bieganie / cardio',
      [BodyMuscle.quads, BodyMuscle.calvesBack, BodyMuscle.hamstrings]),
  mobility('Mobilność / rozciąganie', []);

  const TrainingFocusArea(this.label, this.muscles, [this.signature = const []]);

  final String label;

  /// WSZYSTKIE partie obciążane przez ten obszar — także pomocnicze.
  /// Do prognoz, mapy mięśni i ostrzeżeń „co dziś odpoczywa".
  final List<BodyMuscle> muscles;

  /// Partie DEFINIUJĄCE obszar (puste = wszystkie z [muscles]).
  final List<BodyMuscle> signature;

  /// Partie, po których poznajemy ten obszar: czy został dziś przetrenowany
  /// i czy jest gotowy na dziś.
  ///
  /// Świadomie WĘŻSZE niż [muscles]. Triceps i przedni bark pracują w dniu
  /// klatki, ale to nie znaczy, że dzień barków „już był" ani że klatka jest
  /// niegotowa dzień po barkach — inaczej push / pull / legs blokowałyby się
  /// nawzajem na okrągło.
  List<BodyMuscle> get signatureMuscles =>
      signature.isEmpty ? muscles : signature;

  /// Czy obszar należy do toru pierwszorzędnego (duże partie).
  bool get isPrimaryTrack => kPrimaryFocusAreas.contains(this);
}

/// Obszary PIERWSZORZĘDNE — najważniejsze partie, jedna na dzień treningowy.
const List<TrainingFocusArea> kPrimaryFocusAreas = [
  TrainingFocusArea.chestTriceps,
  TrainingFocusArea.backBiceps,
  TrainingFocusArea.legs,
  TrainingFocusArea.core,
];

/// Obszary pierwszorzędne strategii PUSH / PULL / LEGS.
///
/// Osobna lista, bo to inny podział tego samego ciała: dzień niesie CAŁY wzorzec
/// ruchu (pchanie / ciągnięcie / nogi), a nie pojedynczą partię. Rozkład
/// dwutorowy zostaje bez zmian dla tych, którzy go używają.
const List<TrainingFocusArea> kPushPullLegsAreas = [
  TrainingFocusArea.push,
  TrainingFocusArea.pull,
  TrainingFocusArea.legs,
];

/// Wszystkie obszary, które mogą stać na pozycji GŁÓWNEJ dnia — niezależnie od
/// wybranej strategii. Używane przy naprawie zapisanych planów.
const List<TrainingFocusArea> kAllPrimaryTrackAreas = [
  ...kPrimaryFocusAreas,
  TrainingFocusArea.push,
  TrainingFocusArea.pull,
];

/// Obszary DRUGORZĘDNE — dodatek doklejany do dnia obok partii głównej.
const List<TrainingFocusArea> kSecondaryFocusAreas = [
  TrainingFocusArea.shoulders,
  TrainingFocusArea.arms,
  TrainingFocusArea.forearms,
  TrainingFocusArea.cardio,
  TrainingFocusArea.mobility,
];

/// Obszary siłowe brane pod uwagę przy ocenie gotowości na dziś.
const List<TrainingFocusArea> kStrengthFocusAreas = [
  TrainingFocusArea.chestTriceps,
  TrainingFocusArea.backBiceps,
  TrainingFocusArea.legs,
  TrainingFocusArea.core,
  TrainingFocusArea.shoulders,
  TrainingFocusArea.arms,
];

/// Obszar po kluczu ([TrainingFocusArea.name]); `null`, gdy klucz nieznany.
TrainingFocusArea? focusAreaFromKey(Object? value) {
  final key = value?.toString().trim() ?? '';
  if (key.isEmpty) return null;
  for (final area in TrainingFocusArea.values) {
    if (area.name == key) return area;
  }
  return null;
}

/// Jeden dzień STAŁEGO rozkładu podany planerowi z zewnątrz
/// (`training_schedule`). Dzięki temu planer nie wymyśla tygodnia od nowa,
/// tylko OPISUJE ustalony rozkład i doraźnie go koryguje pod regenerację.
///
/// Typ jest celowo „głupi" (czyste dane), żeby nie tworzyć cyklu importów
/// między planerem a rozkładem.
class ScheduledFocusDay {
  const ScheduledFocusDay({
    required this.date,
    this.primary,
    this.secondary,
    this.isRest = false,
    this.isDeload = false,
    this.note = '',
    this.loadSuffix = '',
    this.intensityScale = 1.0,
  });

  final DateTime date;

  /// Partia główna dnia (`null` dla dnia wolnego).
  final TrainingFocusArea? primary;

  /// Dodatek dnia z toru drugorzędnego (`null` = brak).
  final TrainingFocusArea? secondary;
  final bool isRest;
  final bool isDeload;

  /// Adnotacja rozkładu (np. „dzień przestawiony pod regenerację").
  final String note;

  /// Poziom odciążenia dnia dopisywany do nazwy zestawu („deload (lżej)",
  /// „lżejszy (regeneracja 54%)"). Pusty = pełny zestaw.
  final String loadSuffix;

  /// Mnożnik obciążenia zestawu wynikający z hierarchii
  /// Deload > Regeneracja > Zestaw (1.0 = pełny).
  final double intensityScale;

  /// Etykieta dnia: „Klatka piersiowa + Barki" (z poziomem obciążenia).
  String get label {
    if (isRest || (primary == null && secondary == null)) return 'Dzień wolny';
    final base = primary == null
        ? secondary!.label
        : secondary == null
            ? primary!.label
            : '${primary!.label} + ${secondary!.label}';
    return loadSuffix.isEmpty ? base : '$base · $loadSuffix';
  }

  /// Partie obciążane tego dnia (główne + dodatek).
  List<BodyMuscle> get muscles => <BodyMuscle>[
        ...?primary?.muscles,
        ...?secondary?.muscles,
      ];
}

/// Propozycja na jeden dzień tygodnia.
class WeeklyDaySuggestion {
  const WeeklyDaySuggestion({
    required this.date,
    required this.weekday,
    required this.title,
    required this.reason,
    this.isRest = false,
    this.isLight = false,
    this.isCardio = false,
  });

  final DateTime date;
  final int weekday;

  /// Np. „Nogi", „Klatka / triceps", „Dzień wolny", „Mobilność".
  final String title;

  /// Krótkie uzasadnienie (np. „klatka zregenerowana w 92%").
  final String reason;
  final bool isRest;
  final bool isLight;

  /// Dzień wydolnościowy (bieg / rower) — planowany osobno od dni siłowych.
  final bool isCardio;

  /// Polska nazwa dnia tygodnia.
  String get weekdayLabel {
    const names = [
      'Poniedziałek',
      'Wtorek',
      'Środa',
      'Czwartek',
      'Piątek',
      'Sobota',
      'Niedziela'
    ];
    return (weekday >= 1 && weekday <= 7) ? names[weekday - 1] : '';
  }
}

/// Nadchodzący (nieukończony) dzień aktywnego programu 30-dniowego —
/// wejście dla planera, żeby proponował „Dzień X programu" zamiast samych partii.
class PlannedProgramDay {
  const PlannedProgramDay({
    required this.dayNumber,
    required this.title,
    required this.muscles,
    this.isRest = false,
  });

  /// Numer dnia w programie (1-based, np. 12 → „Dzień 12").
  final int dayNumber;
  final String title;

  /// Partie obciążane przez ćwiczenia tego dnia (bez stabilizatorów).
  final List<BodyMuscle> muscles;

  /// Dzień regeneracyjny / mobilność w programie (brak ćwiczeń siłowych).
  final bool isRest;
}

/// Dopasowanie programu 30-dniowego do aktualnej regeneracji.
class ProgramSuggestion {
  const ProgramSuggestion({
    required this.programId,
    required this.title,
    required this.readinessPercent,
    required this.reason,
  });

  final String programId;
  final String title;

  /// 0–100: jak bardzo partie programu są zregenerowane.
  final double readinessPercent;
  final String reason;
}

/// Gotowość jednego obszaru treningowego na dziś (0–100).
class AreaReadinessToday {
  const AreaReadinessToday({required this.area, required this.percent});

  final TrainingFocusArea area;
  final double percent;
}

/// Ćwiczenie proponowane przez planer na dziś — dobrane pod najlepiej
/// zregenerowany obszar, poziom użytkownika i z pominięciem zmęczonych partii.
class SuggestedExercise {
  const SuggestedExercise({
    required this.exerciseId,
    required this.name,
    required this.reason,
  });

  final String exerciseId;
  final String name;

  /// Np. „Klatka · gotowość 92%".
  final String reason;
}

/// Pełna porada planera tygodnia.
class WeeklyTrainingAdvice {
  const WeeklyTrainingAdvice({
    required this.todayHeadline,
    required this.todayAvoid,
    required this.notes,
    required this.week,
    required this.programs,
    this.areaReadiness = const [],
    this.todayExercises = const [],
    this.todayFocusLabel = '',
    this.todayIsRest = false,
    this.todayIsDeload = false,
  });

  final String todayHeadline;

  /// Etykieta dnia ze STAŁEGO rozkładu („Klatka piersiowa + Barki").
  /// Pusta, gdy rozkład nie jest ustawiony — wtedy dzień dobiera gotowość.
  final String todayFocusLabel;

  /// Czy rozkład przewiduje dziś dzień wolny.
  final bool todayIsRest;

  /// Czy dzisiejszy dzień rozkładu wypada w oknie deloadu.
  final bool todayIsDeload;

  /// Partie, których dziś lepiej unikać („Triceps (44%)").
  final List<String> todayAvoid;

  /// Dodatkowe komunikaty (wysokie RPE, cardio, brak danych…).
  final List<String> notes;
  final List<WeeklyDaySuggestion> week;
  final List<ProgramSuggestion> programs;

  /// Ranking gotowości obszarów na dziś (posortowany malejąco).
  final List<AreaReadinessToday> areaReadiness;

  /// Konkretne ćwiczenia proponowane na dziś (puste, gdy dziś wypada
  /// dzień aktywnego programu — program ma własną listę ćwiczeń).
  final List<SuggestedExercise> todayExercises;

  bool get hasRecoveryData => todayAvoid.isNotEmpty || week.isNotEmpty;

  /// Podsumowanie ułożonego tygodnia — liczby dni poszczególnych typów.
  int get strengthDays =>
      week.where((day) => !day.isRest && !day.isLight && !day.isCardio).length;
  int get cardioDays => week.where((day) => day.isCardio).length;
  int get lightDays => week.where((day) => day.isLight).length;
  int get restDays => week.where((day) => day.isRest).length;
}

/// Ranga poziomu trudności („Początkujący" 0 → „Zaawansowany" 2).
int _levelRank(String level) {
  final normalized = level.toLowerCase();
  if (normalized.contains('zaaw')) return 2;
  if (normalized.contains('śred') ||
      normalized.contains('sred') ||
      normalized.contains('inter') ||
      normalized.contains('mid')) {
    return 1;
  }
  return 0;
}

/// Próg „ciężkości" ([exerciseIntensityScore]), poniżej którego ćwiczenie jest
/// traktowane jako praca lekka. Sztanga/hantle z obciążeniem przekraczają go
/// z zapasem, pompki i warianty czysto kalisteniczne — nie.
const int _kHeavyIntensityFloor = 60;

/// Dobiera z katalogu ćwiczenia na dziś: główna partia w [targetMuscles],
/// bez partii zmęczonych, nie trudniejsze niż poziom użytkownika,
/// maks. 2 ćwiczenia na jedną partię (różnorodność), do [limit] pozycji.
List<SuggestedExercise> _suggestExercisesForToday({
  required List<Exercise> exercises,
  required List<BodyMuscle> targetMuscles,
  required List<BodyMuscle> tiredMuscles,
  required String userLevel,
  required Map<BodyMuscle, MuscleRecoveryState> recovery,
  bool preferLowIntensity = false,
  double intensityFactor = 1.0,
  int limit = 4,
}) {
  if (exercises.isEmpty || targetMuscles.isEmpty) return const [];
  final userRank = _levelRank(userLevel);
  // Pierwsza partia obszaru jest jego partią WIODĄCĄ (dla „Klatka / triceps"
  // to klatka) — ćwiczenia na nią mają pierwszeństwo, żeby dzień klatki nie
  // wypełnił się tricepsem i przodem barków.
  final headline = targetMuscles.first;

  final candidates = <({
    Exercise exercise,
    BodyMuscle muscle,
    int levelGap,
    int index,
    bool isHeadline,
    int intensity
  })>[];
  for (var i = 0; i < exercises.length; i++) {
    final exercise = exercises[i];
    final impacts = exercise.effectiveMuscleImpacts;
    BodyMuscle? primary;
    for (final impact in impacts) {
      if (impact.role == MuscleRole.primary) {
        primary = impact.muscleGroup;
        break;
      }
    }
    if (primary == null || !targetMuscles.contains(primary)) continue;
    // Żadna obciążana partia (poza stabilizacją) nie może być zmęczona.
    final hitsTired = impacts.any((impact) =>
        impact.role != MuscleRole.stabilizer &&
        tiredMuscles.contains(impact.muscleGroup));
    if (hitsTired) continue;
    final exerciseRank = _levelRank(exercise.level);
    if (exerciseRank > userRank) continue;
    candidates.add((
      exercise: exercise,
      muscle: primary,
      levelGap: userRank - exerciseRank,
      index: i,
      isHeadline: primary == headline,
      intensity: exerciseIntensityScore(exercise),
    ));
  }

  // 1) partia wiodąca obszaru, 2) CIĘŻKOŚĆ, 3) bliskość poziomu,
  // 4) kolejność katalogu.
  //
  // ZASADA: zestaw jest CIĘŻKI z założenia. Lekkie warianty pojawiają się
  // wyłącznie wtedy, gdy odchudza je deload / dzień regeneracyjny
  // ([preferLowIntensity] albo mocno obniżony [intensityFactor]) — wcześniej
  // wystarczyła drobna korekta cyklu, żeby dzień klatki zjechał na pompki.
  final wantsLight = preferLowIntensity || intensityFactor < 0.7;
  final wantsHeavy = !wantsLight;

  // Przy ciężkim dniu odrzuć pracę lekką/mobilnościową, o ile zostaje z czego
  // budować — priorytet mają boje z obciążeniem zewnętrznym (sztanga, hantle).
  if (wantsHeavy) {
    final heavyEnough = [
      for (final candidate in candidates)
        if (candidate.intensity >= _kHeavyIntensityFloor) candidate,
    ];
    if (heavyEnough.length >= limit) {
      candidates
        ..clear()
        ..addAll(heavyEnough);
    }
  }
  candidates.sort((a, b) {
    final byHeadline =
        (a.isHeadline ? 0 : 1).compareTo(b.isHeadline ? 0 : 1);
    if (byHeadline != 0) return byHeadline;
    if (wantsHeavy) {
      final byIntensity = b.intensity.compareTo(a.intensity);
      if (byIntensity != 0) return byIntensity;
    } else if (wantsLight) {
      final byIntensity = a.intensity.compareTo(b.intensity);
      if (byIntensity != 0) return byIntensity;
    }
    final byLevel = a.levelGap.compareTo(b.levelGap);
    if (byLevel != 0) return byLevel;
    if (preferLowIntensity) {
      final byMet = a.exercise.met.compareTo(b.exercise.met);
      if (byMet != 0) return byMet;
    }
    return a.index.compareTo(b.index);
  });

  final result = <SuggestedExercise>[];
  final perMuscle = <BodyMuscle, int>{};
  for (final candidate in candidates) {
    final used = perMuscle[candidate.muscle] ?? 0;
    if (used >= 2) continue;
    final percent =
        _projectedRecovery(recovery[candidate.muscle], 0).round();
    result.add(SuggestedExercise(
      exerciseId: candidate.exercise.id,
      name: candidate.exercise.name,
      reason: '${candidate.muscle.label} · gotowość $percent%',
    ));
    perMuscle[candidate.muscle] = used + 1;
    if (result.length >= limit) break;
  }
  return result;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Różnica w pełnych dniach ([a] − [b]), bez wpływu godzin.
int _dayDifference(DateTime a, DateTime b) =>
    DateTime(a.year, a.month, a.day)
        .difference(DateTime(b.year, b.month, b.day))
        .inDays;

/// Przewidywany % regeneracji partii po [hoursAhead] godzinach od teraz.
/// Brak danych = 100 (partia świeża). Aproksymacja liniowa do pełnej regeneracji.
double _projectedRecovery(MuscleRecoveryState? state, double hoursAhead) {
  if (state == null || !state.hasData) return 100;
  final current = state.recoveryPercent ?? 100;
  if (current >= 100) return 100;
  final remaining = state.estimatedHoursRemaining.toDouble();
  if (remaining <= 0) return 100;
  if (hoursAhead >= remaining) return 100;
  return (current + (100 - current) * (hoursAhead / remaining)).clamp(0, 100);
}

/// Gotowość zestawu partii = najsłabsza partia (min), bo jedna mocno
/// zmęczona partia realnie blokuje trening całego zestawu.
double _musclesReadiness(
  List<BodyMuscle> muscles,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
  double hoursAhead,
  Map<BodyMuscle, double> plannedFatigueUntilHour,
) {
  if (muscles.isEmpty) return 100; // mobilność/odpoczynek zawsze dostępne
  var minReadiness = 100.0;
  for (final muscle in muscles) {
    var readiness = _projectedRecovery(recovery[muscle], hoursAhead);
    // Partia zaplanowana wcześniej w symulowanym tygodniu — traktuj jako
    // zmęczoną do wskazanej godziny.
    final blockedUntil = plannedFatigueUntilHour[muscle];
    if (blockedUntil != null && hoursAhead < blockedUntil) {
      readiness = readiness < 45 ? readiness : 45;
    }
    if (readiness < minReadiness) minReadiness = readiness;
  }
  return minReadiness;
}

double _areaReadiness(
  TrainingFocusArea area,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
  double hoursAhead,
  Map<BodyMuscle, double> plannedFatigueUntilHour,
) =>
    _musclesReadiness(
        area.muscles, recovery, hoursAhead, plannedFatigueUntilHour);

/// Główna funkcja planera: buduje poradę na dziś + rozkład tygodnia + programy.
WeeklyTrainingAdvice buildWeeklyTrainingAdvice({
  required Map<BodyMuscle, MuscleRecoveryState> recovery,
  required List<WorkoutLog> recentLogs,
  required List<TrainerActivityEntry> recentActivities,
  required String goal,
  required String level,
  required List<int> trainingWeekdays,
  List<WorkoutProgramMeta> programs = kWorkoutProgramCatalog,
  String activeProgramTitle = '',
  List<PlannedProgramDay> upcomingProgramDays = const [],
  List<Exercise> exercises = const [],
  /// STAŁY rozkład tygodnia z rotacji (`training_schedule`). Gdy podany,
  /// planer NIE układa tygodnia od nowa — bierze rozkład taki, jaki jest,
  /// i tylko opisuje go gotowością partii. To on decyduje, co jest „dzisiaj",
  /// niezależnie od tego, który zestaw użytkownik ostatnio otworzył.
  List<ScheduledFocusDay> fixedSchedule = const [],
  /// Intensywność wynikająca z fazy cyklu (deload / rampa po nim). Steruje
  /// tym, czy propozycje na dziś mają być ciężkie, czy spokojne.
  double intensityFactor = 1.0,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final notes = <String>[];

  // --- Partie, których dziś unikać (regeneracja < 60%). ---
  final avoid = <String>[];
  final tiredMuscles = <BodyMuscle>[];
  recovery.forEach((muscle, state) {
    final percent = state.recoveryPercent;
    if (state.hasData && percent != null && percent < 60) {
      avoid.add('${muscle.label} (${percent.round()}%)');
      tiredMuscles.add(muscle);
    }
  });
  avoid.sort();

  // --- Średnie RPE i objętość ostatniej doby (lżejszy dzień?). ---
  final dayAgo = reference.subtract(const Duration(hours: 26));
  var rpeSum = 0;
  var rpeCount = 0;
  var volumeKg = 0.0;
  for (final log in recentLogs) {
    if (log.date.isBefore(dayAgo)) continue;
    if (log.rpe > 0) {
      rpeSum += log.rpe.clamp(1, 10);
      rpeCount++;
    }
    final volume = log.volume;
    if (volume.isFinite && volume > 0) volumeKg += volume;
  }
  final avgRecentRpe = rpeCount == 0 ? 0.0 : rpeSum / rpeCount;
  final suggestLighter = avgRecentRpe >= 8.5 || tiredMuscles.length >= 4;
  if (avgRecentRpe >= 8.5) {
    notes.add(
        'Zalecany lżejszy trening — średnie RPE ostatniej doby było wysokie (${avgRecentRpe.toStringAsFixed(1)}).');
  }
  if (volumeKg > 0 && volumeKg >= 6000) {
    notes.add(
        'Duża objętość ostatniej doby (${volumeKg.round()} kg) — daj ciału chwilę na regenerację.');
  }

  // --- Cardio w ostatnich 48 h (nogi mogą być zmęczone mimo braku siłowego). ---
  final twoDaysAgo = reference.subtract(const Duration(hours: 48));
  final recentCardio = recentActivities.where((entry) {
    if (entry.date.isBefore(twoDaysAgo)) return false;
    return entry.type == TrainerActivityType.run ||
        entry.type == TrainerActivityType.bike ||
        entry.type == TrainerActivityType.measuredWalk;
  }).toList();
  if (recentCardio.any((entry) => entry.type == TrainerActivityType.run)) {
    notes.add(
        'Ostatni bieg obciążył nogi — planer uwzględnia to w regeneracji łydek i ud.');
  }

  // --- Wybór na dziś: obszar o najwyższej gotowości. ---
  const strengthAreas = kStrengthFocusAreas;
  final readinessToday = <TrainingFocusArea, double>{
    for (final area in strengthAreas)
      area: _areaReadiness(area, recovery, 0, const {}),
  };
  final sortedToday = readinessToday.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final bestToday = sortedToday.first;
  final worstToday = sortedToday.last;

  // Ranking gotowości obszarów na dziś (siłowe + cardio) — dla UI.
  final areaReadinessList = <AreaReadinessToday>[
    for (final entry in sortedToday)
      AreaReadinessToday(area: entry.key, percent: entry.value),
    AreaReadinessToday(
      area: TrainingFocusArea.cardio,
      percent: _areaReadiness(TrainingFocusArea.cardio, recovery, 0, const {}),
    ),
  ]..sort((a, b) => b.percent.compareTo(a.percent));

  // Dzień DZISIEJSZY ze stałego rozkładu — ma pierwszeństwo przed „najlepiej
  // zregenerowanym obszarem". Rozkład jest ustalony przez użytkownika i to on
  // decyduje, co jest dzisiaj; gotowość służy tylko do ostrzeżeń.
  ScheduledFocusDay? scheduledToday;
  for (final day in fixedSchedule) {
    if (_sameDate(day.date, reference)) {
      scheduledToday = day;
      break;
    }
  }

  var todayHeadline = '';
  if (scheduledToday != null) {
    final day = scheduledToday;
    if (day.isRest || (day.primary == null && day.secondary == null)) {
      todayHeadline = 'Dziś dzień wolny w Twoim rozkładzie tygodnia — '
          'regeneracja też jest treningiem.';
    } else {
      final readiness =
          _musclesReadiness(day.muscles, recovery, 0, const {}).round();
      final phase = day.isDeload ? ' · tydzień deloadu (lżej)' : '';
      final moved = day.note.isEmpty ? '' : ' ${day.note}';
      todayHeadline = readiness >= 75
          ? 'Wg planu tygodnia: ${day.label} (gotowość $readiness%)$phase.$moved'
          : readiness >= 55
              ? 'Wg planu tygodnia: ${day.label} — gotowość $readiness%, '
                  'trenuj bez maksymalnej intensywności$phase.$moved'
              : 'Wg planu tygodnia: ${day.label}, ale gotowość to $readiness% '
                  '— rozważ przesunięcie dnia albo mniejszą objętość.$moved';
    }
  } else if (recovery.values.where((s) => s.hasData).isEmpty) {
    todayHeadline =
        'Brak danych regeneracji — wykonaj pierwszy trening, a planer zacznie układać tydzień pod Twoje partie.';
  } else if (suggestLighter) {
    todayHeadline =
        'Dziś dobry moment na lżejszy dzień: mobilność, spacer albo spokojne core.';
  } else if (bestToday.value >= 75) {
    final tiredPart = worstToday.value < 60
        ? ' — ${worstToday.key.label.toLowerCase()} nadal odpoczywa'
        : '';
    todayHeadline = 'Dobry dzień na trening: ${bestToday.key.label}$tiredPart.';
  } else if (bestToday.value >= 55) {
    todayHeadline =
        'Możliwy umiarkowany trening: ${bestToday.key.label} (gotowość ${bestToday.value.round()}%). Bez maksymalnej intensywności.';
  } else {
    todayHeadline =
        'Większość partii w regeneracji — dziś najlepiej mobilność, rozciąganie albo lekki spacer.';
  }

  // --- Rozkład tygodnia. ---
  final week = <WeeklyDaySuggestion>[];
  final plannedFatigueUntilHour = <BodyMuscle, double>{};
  var lastFocus = TrainingFocusArea.mobility;
  final normalizedGoal = goal.toLowerCase();
  final wantsCardio = normalizedGoal.contains('reduk') ||
      normalizedGoal.contains('kondyc') ||
      normalizedGoal.contains('spal') ||
      recentCardio.isNotEmpty;
  var cardioPlanned = false;
  var strengthDaysPlanned = 0;
  // Kolejka nadchodzących dni aktywnego programu 30-dniowego — planer
  // rozkłada je po tygodniu tak, żeby nie kolidowały z regeneracją.
  var programQueueIndex = 0;
  String? todayProgramHeadline;

  // Wariant Z ROZKŁADEM: tydzień jest przepisany z rotacji 1:1. Nic się nie
  // przestawia „samo" — użytkownik widzi dokładnie to, co ustawił, a planer
  // dokłada tylko gotowość i adnotacje.
  if (fixedSchedule.isNotEmpty) {
    for (final day in fixedSchedule.take(7)) {
      if (day.isRest || (day.primary == null && day.secondary == null)) {
        week.add(WeeklyDaySuggestion(
          date: day.date,
          weekday: day.date.weekday,
          title: 'Dzień wolny',
          reason: day.note.isEmpty ? 'Dzień wolny w rozkładzie' : day.note,
          isRest: true,
        ));
        continue;
      }
      final hoursAhead =
          _dayDifference(day.date, reference).clamp(0, 30) * 24.0;
      final readiness =
          _musclesReadiness(day.muscles, recovery, hoursAhead, const {});
      final reasonParts = <String>[
        'Gotowość ${readiness.round()}%',
        if (day.isDeload) 'deload — lżejsza wersja',
        if (day.note.isNotEmpty) day.note,
      ];
      week.add(WeeklyDaySuggestion(
        date: day.date,
        weekday: day.date.weekday,
        title: day.label,
        reason: reasonParts.join(' · '),
        isLight: day.isDeload,
        isCardio: day.primary == TrainingFocusArea.cardio ||
            (day.primary == null && day.secondary == TrainingFocusArea.cardio),
      ));
    }
  }

  // Wariant BEZ ROZKŁADU (rotacja jeszcze nieustawiona): stary tryb doradczy —
  // symulacja 7 dni z blokadą trenowanych partii na ~48 h.
  for (var i = 0; fixedSchedule.isEmpty && i < 7; i++) {
    final date = DateTime(reference.year, reference.month, reference.day)
        .add(Duration(days: i));
    final hoursAhead = i * 24.0;
    if (!trainingWeekdays.contains(date.weekday)) {
      week.add(WeeklyDaySuggestion(
        date: date,
        weekday: date.weekday,
        title: 'Dzień wolny',
        reason: 'Poza Twoimi dniami treningowymi',
        isRest: true,
      ));
      continue;
    }
    // Dziś przy sugerowanym lżejszym dniu → mobilność/core.
    if (i == 0 && suggestLighter) {
      week.add(WeeklyDaySuggestion(
        date: date,
        weekday: date.weekday,
        title: 'Lżejszy dzień: mobilność / core',
        reason: avgRecentRpe >= 8.5
            ? 'Wysokie RPE ostatniej doby'
            : 'Kilka partii mocno zmęczonych',
        isLight: true,
      ));
      lastFocus = TrainingFocusArea.mobility;
      continue;
    }

    // Dzień aktywnego programu 30-dniowego ma pierwszeństwo, jeśli jego
    // partie są wystarczająco zregenerowane. Program czeka (nie przepada),
    // gdy regeneracja nie pozwala — wtedy planer proponuje inną partię.
    if (programQueueIndex < upcomingProgramDays.length) {
      final programDay = upcomingProgramDays[programQueueIndex];
      final programTitle =
          'Dzień ${programDay.dayNumber} programu: ${programDay.title}';
      if (programDay.isRest) {
        week.add(WeeklyDaySuggestion(
          date: date,
          weekday: date.weekday,
          title: programTitle,
          reason: 'Dzień regeneracyjny programu',
          isLight: true,
        ));
        programQueueIndex++;
        lastFocus = TrainingFocusArea.mobility;
        continue;
      }
      final programReadiness = _musclesReadiness(
          programDay.muscles, recovery, hoursAhead, plannedFatigueUntilHour);
      if (programReadiness >= 55) {
        week.add(WeeklyDaySuggestion(
          date: date,
          weekday: date.weekday,
          title: programTitle,
          reason: 'Gotowość ${programReadiness.round()}%',
        ));
        programQueueIndex++;
        strengthDaysPlanned++;
        lastFocus = TrainingFocusArea.mobility;
        for (final muscle in programDay.muscles) {
          plannedFatigueUntilHour[muscle] = hoursAhead + 48;
        }
        if (i == 0) {
          todayProgramHeadline = programReadiness >= 75
              ? 'Dobry dzień na Dzień ${programDay.dayNumber} programu — ${programDay.title} (gotowość ${programReadiness.round()}%).'
              : 'Możliwy Dzień ${programDay.dayNumber} programu — ${programDay.title} (gotowość ${programReadiness.round()}%). Bez maksymalnej intensywności.';
        }
        continue;
      }
      if (i == 0) {
        notes.add(
            'Dzień ${programDay.dayNumber} programu („${programDay.title}") poczeka — jego partie są jeszcze w regeneracji (${programReadiness.round()}%).');
      }
    }

    final candidates = <TrainingFocusArea, double>{
      for (final area in strengthAreas)
        area:
            _areaReadiness(area, recovery, hoursAhead, plannedFatigueUntilHour),
    };
    // Nie powtarzaj wczorajszego obszaru.
    candidates.remove(lastFocus);
    final ranked = candidates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;

    // Wpleć cardio raz w tygodniu (cel redukcja/kondycja albo użytkownik biega),
    // najlepiej w środku tygodnia, gdy nogi są gotowe.
    final cardioReadiness = _areaReadiness(TrainingFocusArea.cardio, recovery,
        hoursAhead, plannedFatigueUntilHour);
    if (wantsCardio &&
        !cardioPlanned &&
        i >= 2 &&
        strengthDaysPlanned >= 2 &&
        cardioReadiness >= 65) {
      week.add(WeeklyDaySuggestion(
        date: date,
        weekday: date.weekday,
        title: 'Cardio / bieg',
        reason:
            'Nogi zregenerowane (${cardioReadiness.round()}%), dobry dzień na wydolność',
        isCardio: true,
      ));
      cardioPlanned = true;
      lastFocus = TrainingFocusArea.cardio;
      for (final muscle in TrainingFocusArea.cardio.muscles) {
        plannedFatigueUntilHour[muscle] = hoursAhead + 36;
      }
      continue;
    }

    if (best.value < 55) {
      week.add(WeeklyDaySuggestion(
        date: date,
        weekday: date.weekday,
        title: 'Mobilność / lekki dzień',
        reason: 'Partie siłowe jeszcze w regeneracji',
        isLight: true,
      ));
      lastFocus = TrainingFocusArea.mobility;
      continue;
    }

    week.add(WeeklyDaySuggestion(
      date: date,
      weekday: date.weekday,
      title: best.key.label,
      reason: 'Gotowość ${best.value.round()}%',
    ));
    strengthDaysPlanned++;
    lastFocus = best.key;
    // Zablokuj trenowane partie na ~48 h w symulacji.
    for (final muscle in best.key.muscles) {
      plannedFatigueUntilHour[muscle] = hoursAhead + 48;
    }
  }

  // Dzień programu zaplanowany na dziś nadpisuje ogólny nagłówek partii
  // (użytkownik widzi konkretny „Dzień X programu", nie tylko obszar).
  // Ze STAŁYM ROZKŁADEM nagłówek zostaje przy rozkładzie — program jest tylko
  // narzędziem do zrealizowania dnia, nie źródłem tego, co dziś wypada.
  if (todayProgramHeadline != null && !suggestLighter && fixedSchedule.isEmpty) {
    todayHeadline = todayProgramHeadline;
  }

  // --- Dopasowanie programów 30-dniowych do regeneracji. ---
  final programSuggestions = <ProgramSuggestion>[];
  for (final meta in programs) {
    final muscles = <BodyMuscle>{};
    for (final label in meta.mainMuscles) {
      final muscle = BodyMuscle.fromText(label);
      if (muscle != null) muscles.add(muscle);
    }
    double readiness = 100;
    for (final muscle in muscles) {
      final value = _projectedRecovery(recovery[muscle], 0);
      if (value < readiness) readiness = value;
    }
    final isActive =
        activeProgramTitle.isNotEmpty && meta.title == activeProgramTitle;
    final reason = isActive
        ? 'Twój aktywny program'
        : readiness >= 75
            ? 'Partie programu zregenerowane'
            : readiness >= 55
                ? 'Partie częściowo zregenerowane — trenuj umiarkowanie'
                : 'Główne partie programu są jeszcze zmęczone';
    programSuggestions.add(ProgramSuggestion(
      programId: meta.id,
      title: meta.title,
      readinessPercent: readiness,
      reason: reason,
    ));
  }
  programSuggestions
      .sort((a, b) => b.readinessPercent.compareTo(a.readinessPercent));

  final top = programSuggestions.isEmpty ? null : programSuggestions.first;
  if (top != null &&
      top.readinessPercent >= 75 &&
      recovery.values.any((s) => s.hasData)) {
    notes.add('Program dopasowany do regeneracji: ${top.title}.');
  }

  // --- Konkretne ćwiczenia na dziś. ---
  // Ze stałym rozkładem cel jest znany z góry: partia GŁÓWNA dnia plus, jeśli
  // dzień ma dodatek z toru drugorzędnego, kilka pozycji na niego. Bez rozkładu
  // działa stary tryb (najlepiej zregenerowany obszar).
  var todayExercises = const <SuggestedExercise>[];
  if (scheduledToday != null) {
    final day = scheduledToday;
    if (!day.isRest) {
      // Hierarchia Deload > Regeneracja > Zestaw: skala dnia z rozkładu mnoży
      // się z fazą cyklu, więc dzień „lżejszy pod regenerację" naprawdę dobiera
      // spokojniejszą pracę, a nie tylko dostaje inną nazwę.
      final dayIntensity = intensityFactor * day.intensityScale;
      final lighterToday = day.isDeload || suggestLighter;
      final result = <SuggestedExercise>[];
      final primary = day.primary;
      if (primary != null) {
        result.addAll(_suggestExercisesForToday(
          exercises: exercises,
          targetMuscles: primary.muscles,
          tiredMuscles: tiredMuscles,
          userLevel: level,
          recovery: recovery,
          preferLowIntensity: lighterToday,
          intensityFactor: dayIntensity,
          limit: 4,
        ));
      }
      final secondary = day.secondary;
      if (secondary != null && secondary.muscles.isNotEmpty) {
        final used = {for (final e in result) e.exerciseId};
        for (final suggestion in _suggestExercisesForToday(
          exercises: exercises,
          targetMuscles: secondary.muscles,
          tiredMuscles: tiredMuscles,
          userLevel: level,
          recovery: recovery,
          preferLowIntensity: lighterToday,
          intensityFactor: dayIntensity,
          limit: 3,
        )) {
          if (used.add(suggestion.exerciseId)) result.add(suggestion);
          if (result.length >= 6) break;
        }
      }
      todayExercises = result;
    }
  } else if (todayProgramHeadline == null) {
    final lighterToday = suggestLighter || bestToday.value < 55;
    todayExercises = _suggestExercisesForToday(
      exercises: exercises,
      targetMuscles: lighterToday
          ? TrainingFocusArea.core.muscles
          : bestToday.key.muscles,
      tiredMuscles: tiredMuscles,
      userLevel: level,
      recovery: recovery,
      preferLowIntensity: lighterToday,
      intensityFactor: intensityFactor,
    );
  }

  return WeeklyTrainingAdvice(
    todayHeadline: todayHeadline,
    todayAvoid: avoid,
    notes: notes,
    week: week,
    programs: programSuggestions,
    areaReadiness: areaReadinessList,
    todayExercises: todayExercises,
    todayFocusLabel:
        scheduledToday == null || scheduledToday.isRest ? '' : scheduledToday.label,
    todayIsRest: scheduledToday?.isRest ?? false,
    todayIsDeload: scheduledToday?.isDeload ?? false,
  );
}
