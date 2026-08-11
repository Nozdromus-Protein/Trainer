/// Silnik regeneracji i gotowości treningowej (czysty Dart, bez UI).
///
/// ŁAŃCUCH DECYZYJNY (spec: punkt 23):
///
///   literatura → założenia fizjologiczne → model regeneracji → bodziec
///   treningowy → historia użytkownika → kalibracja indywidualna →
///   gotowość + pewność
///
/// Model NIE jest zegarem. Każdy bodziec zostawia w partii ŁADUNEK w czterech
/// niezależnych wymiarach (lokalny, nerwowy, strukturalny, energetyczny), który
/// zanika WYKŁADNICZO z własną stałą czasową. Stałe zależą od partii
/// (Chen 2019 — partie reagują różnie), od wielkości bodźca (większy bodziec
/// = dłuższy ogon) i od indywidualnej kalibracji użytkownika.
///
///   ładunek(t) = Σ_i  x_i · exp(−Δt_i / τ)
///   zmęczenie  = 1 − exp(−ładunek)          (nasycenie: nie da się zejść < 0)
///   składowa   = 1 − zmęczenie              (0–1, „ile odzyskane")
///
/// Dzięki nasyceniu kilka lekkich sesji sumuje się sensownie, a jedna bardzo
/// ciężka nie „przepełnia" skali.
library;

import 'dart:math' as math;

import 'activity_credit.dart';
import 'exercise.dart';
import 'muscle_readiness.dart';
import 'workout_session.dart';

export 'muscle_readiness.dart';

// ===========================================================================
// Profil użytkownika
// ===========================================================================

/// Profil użytkownika na potrzeby liczenia regeneracji.
/// Wszystkie pola mają rozsądne wartości domyślne — brak danych nie psuje obliczeń.
class RecoveryProfile {
  const RecoveryProfile({
    this.bodyWeightKg = 80,
    this.heightCm = 178,
    this.age = 30,
    this.sex = '',
    this.level = 'Średniozaawansowany',
    this.trainingDaysPerWeek = 3,
  });

  final double bodyWeightKg;
  final double heightCm;
  final int age;

  /// 'Mężczyzna' / 'Kobieta' / '' (nie podano).
  final String sex;

  /// 'Początkujący' / 'Średniozaawansowany' / 'Zaawansowany'.
  final String level;
  final int trainingDaysPerWeek;

  /// Łączny mnożnik STAŁYCH CZASOWYCH wynikający z profilu.
  /// Starszy wiek i niższy staż → dłuższa regeneracja; zaawansowani i osoby
  /// trenujące częściej regenerują się nieco szybciej (adaptacja).
  double get recoveryFactor {
    var factor = 1.0;
    // Wiek: +5% na każdą dekadę powyżej 30 lat (maks. +25%).
    if (age > 30) factor *= 1.0 + (((age - 30) / 10) * 0.05).clamp(0.0, 0.25);
    // Poziom zaawansowania.
    final normalizedLevel = level.toLowerCase();
    if (normalizedLevel.contains('pocz')) {
      factor *= 1.12;
    } else if (normalizedLevel.contains('zaaw')) {
      factor *= 0.9;
    }
    // Kobiety statystycznie regenerują się minimalnie szybciej przy tej samej
    // względnej intensywności.
    if (sex.toLowerCase().startsWith('k')) factor *= 0.95;
    // Wysoka częstotliwość treningów = lepsza tolerancja objętości.
    if (trainingDaysPerWeek >= 5) factor *= 0.95;
    return factor.clamp(0.7, 1.6);
  }

  double get effectiveBodyWeightKg => bodyWeightKg <= 0 ? 80.0 : bodyWeightKg;
}

// ===========================================================================
// Profile czasowe partii mięśniowych
// ===========================================================================

/// Stałe czasowe (godziny) i skala wrażliwości JEDNEJ partii.
///
/// Chen 2019 (PMID 30663816) porównał uszkodzenie i efekt powtarzanego bodźca
/// w zginaczach/prostownikach łokcia, klatce, nogach, łydce, najszerszym
/// grzbietu i tułowiu — reakcje NIE były identyczne. Dlatego zamiast jednego
/// „bazowego okna 36 h" mamy zestaw stałych per partia, przy czym rozróżnienie
/// dotyczy głównie osi STRUKTURALNEJ (tam różnice były największe), a nie
/// wszystkich wymiarów naraz.
class MuscleRecoveryProfileData {
  const MuscleRecoveryProfileData({
    required this.sizeScale,
    required this.localTauHours,
    required this.neuralTauHours,
    required this.structuralTauHours,
    required this.energyTauHours,
  });

  /// Mnożnik ŁADUNKU: małe partie łatwiej wysycić tą samą pracą.
  final double sizeScale;

  final double localTauHours;
  final double neuralTauHours;
  final double structuralTauHours;
  final double energyTauHours;
}

const MuscleRecoveryProfileData _largeProfile = MuscleRecoveryProfileData(
  sizeScale: 0.92,
  localTauHours: 12,
  neuralTauHours: 16,
  structuralTauHours: 26,
  energyTauHours: 14,
);

const MuscleRecoveryProfileData _legProfile = MuscleRecoveryProfileData(
  sizeScale: 0.92,
  localTauHours: 11,
  neuralTauHours: 15,
  structuralTauHours: 23,
  energyTauHours: 13,
);

const MuscleRecoveryProfileData _mediumProfile = MuscleRecoveryProfileData(
  sizeScale: 1.0,
  localTauHours: 10,
  neuralTauHours: 14,
  structuralTauHours: 22,
  energyTauHours: 12,
);

/// Zginacze i prostowniki łokcia: mniejsza masa, ale w badaniach Chen 2019 to
/// właśnie ramiona pokazywały największe zmiany markerów uszkodzenia — stąd
/// KRÓTKIE stałe lokalne i DŁUGA stała strukturalna.
const MuscleRecoveryProfileData _armProfile = MuscleRecoveryProfileData(
  sizeScale: 1.08,
  localTauHours: 9,
  neuralTauHours: 12,
  structuralTauHours: 24,
  energyTauHours: 10,
);

const MuscleRecoveryProfileData _smallProfile = MuscleRecoveryProfileData(
  sizeScale: 1.05,
  localTauHours: 8,
  neuralTauHours: 10,
  structuralTauHours: 15,
  energyTauHours: 9,
);

/// Profil czasowy partii.
MuscleRecoveryProfileData muscleRecoveryProfile(BodyMuscle muscle) {
  switch (muscle) {
    case BodyMuscle.quads:
    case BodyMuscle.hamstrings:
    case BodyMuscle.glutes:
      return _legProfile;
    case BodyMuscle.chest:
    case BodyMuscle.lats:
    case BodyMuscle.upperBack:
    case BodyMuscle.lowerBack:
    case BodyMuscle.erectorSpinae:
    case BodyMuscle.rhomboids:
    case BodyMuscle.quadratusLumborum:
      return _largeProfile;
    case BodyMuscle.biceps:
    case BodyMuscle.triceps:
      return _armProfile;
    case BodyMuscle.frontShoulders:
    case BodyMuscle.rearShoulders:
    case BodyMuscle.traps:
    case BodyMuscle.adductors:
    case BodyMuscle.hipFlexors:
    case BodyMuscle.gluteMedius:
    case BodyMuscle.teresMajor:
    case BodyMuscle.tensorFasciaeLatae:
      return _mediumProfile;
    default:
      return _smallProfile;
  }
}

/// Czy partia jest DUŻA (do klasyfikacji obciążenia i limitów).
bool isLargeMuscle(BodyMuscle muscle) =>
    identical(muscleRecoveryProfile(muscle), _largeProfile) ||
    identical(muscleRecoveryProfile(muscle), _legProfile);

/// Zgodność wsteczna: orientacyjne „bazowe okno regeneracji" partii (godziny).
/// Nie jest już używane do liczenia gotowości — zostaje jako opis dla UI/AI.
double baseRecoveryHoursForMuscle(BodyMuscle muscle) {
  final profile = muscleRecoveryProfile(muscle);
  // ~3 stałe czasowe składowej strukturalnej ≈ 95% zaniku.
  return (profile.structuralTauHours * 1.4).roundToDouble();
}

// ===========================================================================
// Współczynniki modelu (skala ładunku i krzywe)
// ===========================================================================

/// Ile ładunku daje JEDNA jednostka bodźca w każdym wymiarze.
///
/// Jednostka odniesienia = solidne 3×10 przy ~2 RIR na partię GŁÓWNĄ.
/// Wartości dobrane tak, by tuż po takiej serii lokalne zmęczenie było niemal
/// pełne (co odpowiada obserwowanym ostrym spadkom siły), a po ~48 h partia
/// wracała do wysokiej gotowości przy pracy bez upadku (Pareja-Blanco 2017:
/// protokoły bez failure regenerowały się wyraźnie szybciej).
const double _kLocalLoad = 2.6;
const double _kNeuralLoad = 1.7;
const double _kStructuralLoad = 0.7;
const double _kEnergyLoad = 1.8;

/// Sumy odniesienia dla „jednej jednostki" w każdym wymiarze (3 serie × 10
/// powtórzeń przy 2 RIR). Dzięki nim wielkości są porównywalne między
/// ćwiczeniami i typami wpisu.
const double _kLocalReference = 1.653;
const double _kNeuralReference = 1.089;
const double _kStructuralReference = 2.052;
const double _kEnergyReference = 1.650;

/// Rozciągnięcie stałych czasowych wraz z wielkością bodźca — bardzo ciężka
/// sesja ma dłuższy ogon niż lekka, ale wzrost jest logarytmiczny (bez tego
/// pojedynczy potworny trening blokowałby partię na tydzień).
double _magnitudeTauScale(double totalUnits) =>
    (0.85 + 0.25 * math.log(1 + totalUnits.clamp(0.0, 30.0)))
        .clamp(0.8, 1.8)
        .toDouble();

// ===========================================================================
// Bodziec: jak liczymy obciążenie serii i ćwiczenia
// ===========================================================================

/// Jednostkowy wkład jednego wpisu treningowego w jeden wymiar zmęczenia.
class StimulusUnits {
  const StimulusUnits({
    this.local = 0,
    this.neural = 0,
    this.structural = 0,
    this.energy = 0,
  });

  final double local;
  final double neural;
  final double structural;
  final double energy;

  static const StimulusUnits zero = StimulusUnits();

  bool get isEmpty =>
      local <= 0.0001 &&
      neural <= 0.0001 &&
      structural <= 0.0001 &&
      energy <= 0.0001;

  /// Skalarny „rozmiar" bodźca — do klasyfikacji lekki/średni/ciężki.
  double get magnitude =>
      local * 0.45 + neural * 0.25 + structural * 0.15 + energy * 0.15;

  StimulusUnits scaled(double factor) => StimulusUnits(
        local: local * factor,
        neural: neural * factor,
        structural: structural * factor,
        energy: energy * factor,
      );

  StimulusUnits operator +(StimulusUnits other) => StimulusUnits(
        local: local + other.local,
        neural: neural + other.neural,
        structural: structural + other.structural,
        energy: energy + other.energy,
      );
}

/// Opis JEDNEJ serii sprowadzony do wielkości fizjologicznych.
class SetLoad {
  const SetLoad({
    required this.reps,
    required this.relativeLoad,
    required this.repsInReserve,
    required this.rirKnown,
    this.workSeconds = 0,
    this.isTimed = false,
    this.restRatio = 1.0,
    this.toFailure = false,
  });

  final int reps;

  /// Szacowany udział %1RM (0–1).
  final double relativeLoad;

  /// Zapas powtórzeń do upadku (0 = upadek).
  final double repsInReserve;

  /// Czy [repsInReserve] pochodzi z realnego sygnału (RPE/wynik serii).
  final bool rirKnown;

  final int workSeconds;
  final bool isTimed;

  /// Realna przerwa / przerwa planowana (1.0 = zgodnie z planem).
  final double restRatio;

  final bool toFailure;

  /// Bliskość upadku w skali CIĄGŁEJ 0–1 (1 = upadek).
  ///
  /// González-Badillo 2016, Pareja-Blanco 2017 i Refalo 2023 zgodnie pokazują,
  /// że koszt nerwowo-mięśniowy rośnie NIELINIOWO wraz ze zbliżaniem się do
  /// upadku, a nie skokowo w momencie jego osiągnięcia. Stąd wykładnicza,
  /// gładka funkcja zamiast reguły `failure = +24 h`.
  double get proximityToFailure =>
      math.exp(-repsInReserve.clamp(0.0, 8.0) / 2.2);

  /// Wersja „miękka" używana dla uszkodzenia strukturalnego — tam gradient jest
  /// płytszy niż w wymiarze nerwowym.
  double get structuralProximity =>
      math.exp(-repsInReserve.clamp(0.0, 8.0) / 3.0);

  /// Ile powtórzeń serii to realnie powtórzenia STYMULUJĄCE (blisko upadku).
  double get stimulatingReps {
    if (reps <= 0) return 0;
    final effective = (5 - repsInReserve).clamp(0.0, 5.0);
    return math.min(reps.toDouble(), effective + 1);
  }
}

/// Kalkulator obciążenia treningowego — zamienia surowy wpis na wielkości
/// fizjologiczne (spec 11: `kg × powtórzenia` to za mało).
class TrainingLoadCalculator {
  const TrainingLoadCalculator({this.profile = const RecoveryProfile()});

  final RecoveryProfile profile;

  /// Szacunkowy udział %1RM na podstawie liczby powtórzeń (odwrócona formuła
  /// Epleya). Nie wymaga znajomości 1RM ani historii — daje sensowny,
  /// monotoniczny sygnał: 1 powt. ≈ 100%, 5 ≈ 86%, 10 ≈ 75%, 20 ≈ 60%.
  static double relativeLoadFromReps(int reps) {
    if (reps <= 0) return 0.45; // izometria / praca czasowa
    return (1.0 / (1.0 + reps / 30.0)).clamp(0.35, 1.0);
  }

  /// Zapas powtórzeń (RIR) wyprowadzony OSTROŻNIE.
  ///
  /// Kolejność: jawny RIR z wyniku serii → RPE (RIR ≈ 10 − RPE) → brak danych
  /// (neutralne 2.5 z obniżoną pewnością; spec 31).
  static ({double rir, bool known}) rirFor({
    double rpe = 0,
    bool failure = false,
    bool completed = true,
  }) {
    if (failure) return (rir: 0, known: true);
    if (rpe > 0) {
      return (rir: (10.0 - rpe).clamp(0.0, 8.0).toDouble(), known: true);
    }
    if (!completed) return (rir: 0.5, known: true);
    return (rir: 2.5, known: false);
  }

  /// Rozkłada wpis treningowy na listę serii z wielkościami fizjologicznymi.
  List<SetLoad> setsFor(WorkoutLog log, Exercise exercise) {
    final entryType = exercise.entryType;
    final isTimed = entryType.showsDuration && !entryType.showsReps;
    final recorded =
        log.workoutSets.where((set) => set.isCompleted && !set.isFailure);

    if (recorded.isNotEmpty) {
      return [
        for (final set in recorded)
          () {
            final rpe = set.estimatedRpe > 0
                ? set.estimatedRpe
                : (set.rpe > 0 ? set.rpe.toDouble() : 0.0);
            final rir = rirFor(
              rpe: rpe,
              failure: set.outcome == 'notCompleted',
              completed: set.isCompleted,
            );
            final work = set.activeSeconds > 0
                ? set.activeSeconds
                : (set.durationSec > 0 ? set.durationSec : 0);
            final restRatio = set.plannedRestSec > 0 && set.restBeforeSec > 0
                ? (set.restBeforeSec / set.plannedRestSec).clamp(0.2, 2.5)
                : 1.0;
            return SetLoad(
              reps: set.repetitions,
              relativeLoad: isTimed
                  ? 0.45
                  : relativeLoadFromReps(
                      set.repetitions > 0 ? set.repetitions : log.reps),
              repsInReserve: rir.rir,
              rirKnown: rir.known,
              workSeconds: work,
              isTimed: isTimed,
              restRatio: restRatio.toDouble(),
              toFailure: rir.rir <= 0.25,
            );
          }(),
      ];
    }

    // Starszy zapis: tylko zbiorcze sets/reps/rpe (spec 31 — musi działać).
    final sets = log.sets <= 0 ? 1 : log.sets.clamp(1, 20);
    final reps = log.reps <= 0 ? (isTimed ? 0 : 8) : log.reps.clamp(1, 60);
    final rir = rirFor(rpe: log.rpe > 0 ? log.rpe.toDouble() : 0);
    final perSetWork = isTimed && log.durationSec > 0
        ? (log.durationSec / sets).round()
        : 0;
    return [
      for (var i = 0; i < sets; i++)
        SetLoad(
          reps: reps,
          relativeLoad: isTimed ? 0.45 : relativeLoadFromReps(reps),
          repsInReserve: rir.rir,
          rirKnown: rir.known,
          workSeconds: perSetWork,
          isTimed: isTimed,
          toFailure: rir.rir <= 0.25,
        ),
    ];
  }

  /// Rodzaj ćwiczenia — siłowe męczą partię najmocniej, mobilność prawie wcale.
  static double exerciseTypeFactor(Exercise exercise, WorkoutLog log) {
    final text = '${exercise.category} ${exercise.name}'.toLowerCase();
    if (text.contains('rozgrzew') ||
        text.contains('warmup') ||
        text.contains('warm-up')) {
      return 0.25;
    }
    if (text.contains('mobil') ||
        text.contains('stretch') ||
        text.contains('rozciąg') ||
        text.contains('rozciag')) {
      return 0.3;
    }
    if (text.contains('kardio') ||
        text.contains('cardio') ||
        text.contains('bieg') ||
        text.contains('rower') ||
        exercise.met >= 8) {
      return 0.55;
    }
    // Ćwiczenia czasowe bez obciążenia (deska itp.) — lżejszy bodziec.
    if (log.weightKg <= 0 &&
        (log.durationSec > 0 || exercise.defaultDurationSec > 0)) {
      return 0.8;
    }
    return 1.0;
  }

  /// Nasilenie fazy EKSCENTRYCZNEJ ćwiczenia — główny motor uszkodzeń.
  ///
  /// Nie mamy pomiaru tempa, więc korzystamy z charakteru ruchu: ruchy z dużym
  /// rozciągnięciem pod obciążeniem (RDL, wykroki, rozpiętki, przysiad
  /// bułgarski) obciążają strukturalnie mocniej niż maszyny i izometria.
  static double eccentricFactor(Exercise exercise) {
    final entryType = exercise.entryType;
    if (entryType == ExerciseEntryType.mobility) return 0.4;
    if (entryType.showsDuration && !entryType.showsReps) return 0.6;
    final name = exercise.name.toLowerCase();
    const highStretch = [
      'rumuński',
      'rumunski',
      'romanian',
      'rdl',
      'wykrok',
      'lunge',
      'bułgar',
      'bulgar',
      'rozpięt',
      'rozpiet',
      'fly',
      'przeprost',
      'nordic',
      'dip',
      'podciąg',
      'podciag',
      'pullup',
      'pull-up',
      'martwy',
      'deadlift',
      'sissy',
      'zakroki',
      'step',
    ];
    if (highStretch.any(name.contains)) return 1.35;
    final equipment = exercise.equipment.toLowerCase();
    if (equipment.contains('maszyn') || equipment.contains('wyciąg')) {
      return 0.85;
    }
    return 1.0;
  }

  /// Bodziec CAŁEGO wpisu w jednostkach modelu (przed rolą partii).
  StimulusUnits unitsFor(WorkoutLog log, Exercise exercise) {
    final sets = setsFor(log, exercise);
    if (sets.isEmpty) return StimulusUnits.zero;
    final typeFactor = exerciseTypeFactor(exercise, log);
    final eccentric = eccentricFactor(exercise);

    // Ciężar względem masy ciała — ta sama liczba powtórzeń przy 100 kg kosztuje
    // więcej niż przy sztandze samej. Wpływ ograniczony: %1RM (z powtórzeń) jest
    // ważniejszym sygnałem intensywności.
    final relativeExternal =
        (log.weightKg / profile.effectiveBodyWeightKg).clamp(0.0, 2.0);
    final externalFactor = 0.85 + relativeExternal * 0.35;

    var local = 0.0;
    var neural = 0.0;
    var structural = 0.0;
    var energy = 0.0;

    for (final set in sets) {
      final repFactor = set.isTimed
          ? (set.workSeconds > 0 ? set.workSeconds / 40.0 : 1.0)
              .clamp(0.15, 3.0)
              .toDouble()
          : (set.reps / 10.0).clamp(0.15, 3.0).toDouble();

      // 1. LOKALNE ZMĘCZENIE — objętość ważona bliskością upadku i obciążeniem.
      final setWeight = 0.30 + 0.75 * set.proximityToFailure;
      local += setWeight * repFactor * (0.4 + 0.6 * set.relativeLoad);

      // 2. ZMĘCZENIE NERWOWO-MIĘŚNIOWE — rośnie z %1RM i bliskością upadku.
      neural += (0.25 + 0.75 * math.pow(set.relativeLoad, 1.5)) *
          (0.15 + 0.85 * set.proximityToFailure);

      // 3. STRES STRUKTURALNY — objętość × ekscentryka × (płytszy) gradient RIR.
      structural +=
          repFactor * (0.35 + 0.65 * set.structuralProximity) * eccentric;

      // 4. ENERGIA — długa praca, dużo powtórzeń, krótkie przerwy, niższe %1RM.
      final restDensity = (2.0 - set.restRatio).clamp(0.8, 1.4).toDouble();
      energy +=
          repFactor * (0.4 + 0.6 * (1 - set.relativeLoad)) * restDensity;
    }

    return StimulusUnits(
      local: (local / _kLocalReference) * typeFactor * externalFactor,
      neural: (neural / _kNeuralReference) * typeFactor * externalFactor,
      structural: (structural / _kStructuralReference) * typeFactor,
      energy: (energy / _kEnergyReference) * typeFactor,
    );
  }
}

// ===========================================================================
// Historia ćwiczeń: oswojenie z bodźcem (repeated-bout effect)
// ===========================================================================

/// Znajomość ćwiczenia przez użytkownika (spec 5).
class ExerciseFamiliarity {
  const ExerciseFamiliarity({
    this.sessions = 0,
    this.lastPerformed,
    this.daysSinceLast = -1,
    this.loadJump = 0,
    this.volumeJump = 0,
    this.known = false,
  });

  static const ExerciseFamiliarity unknown = ExerciseFamiliarity();

  /// Ile razy ćwiczenie było wykonane (sesje, nie serie).
  final int sessions;
  final DateTime? lastPerformed;
  final int daysSinceLast;

  /// Względna zmiana obciążenia względem poprzedniego wykonania (0.2 = +20%).
  final double loadJump;

  /// Względna zmiana objętości (serie × powtórzenia).
  final double volumeJump;

  /// Czy w ogóle mamy wiarygodną historię (bez niej NIE zgadujemy „nowości").
  final bool known;

  /// Wynik oswojenia 0–1 (1 = ruch dobrze wyćwiczony).
  ///
  /// Howatson 2007 (PMID 17373600) i Damas 2016 (PMID 27219125): pierwszy
  /// kontakt z bodźcem daje wyraźnie większe uszkodzenie, które maleje wraz
  /// z kolejnymi powtórzeniami tego samego wzorca.
  double get score {
    if (!known) return 0.5; // brak danych = neutralnie, nie „nowe"
    if (sessions <= 0) return 0.0;
    var base = (1 - math.exp(-sessions / 2.5)).clamp(0.0, 1.0).toDouble();
    // Długa przerwa częściowo cofa adaptację (efekt powtarzanego bodźca zanika).
    if (daysSinceLast > 42) {
      base *= 0.55;
    } else if (daysSinceLast > 21) {
      base *= 0.75;
    } else if (daysSinceLast > 14) {
      base *= 0.9;
    }
    return base.clamp(0.0, 1.0).toDouble();
  }

  /// Mnożnik ŁADUNKU STRUKTURALNEGO wynikający z nowości bodźca.
  /// 0.62 (ruch wyćwiczony) … 1.55 (pierwszy kontakt / powrót po długiej przerwie).
  double get structuralModifier {
    if (!known) return 1.0;
    var modifier = 1.55 - 0.93 * score;
    // Nagły skok ciężaru albo objętości to też „nowy" bodziec dla tkanki.
    if (loadJump > 0.1) modifier *= 1 + (loadJump.clamp(0.0, 0.6) * 0.5);
    if (volumeJump > 0.25) modifier *= 1 + (volumeJump.clamp(0.0, 1.0) * 0.3);
    return modifier.clamp(0.55, 2.0).toDouble();
  }

  /// Ile nowość odbiera PEWNOŚCI prognozy.
  double get confidencePenalty {
    if (!known) return 0.10;
    if (sessions >= 6) return 0.0;
    if (sessions >= 3) return 0.04;
    return 0.12;
  }
}

/// Buduje mapę oswojenia dla ćwiczeń występujących w historii.
Map<String, ExerciseFamiliarity> buildFamiliarityMap(
  List<WorkoutLog> history, {
  DateTime? now,
}) {
  if (history.isEmpty) return const {};
  final reference = now ?? DateTime.now();
  // Sesje per ćwiczenie (jeden trening = jedna obserwacja).
  final sessionsByExercise = <String, Set<String>>{};
  final lastByExercise = <String, WorkoutLog>{};
  final previousByExercise = <String, WorkoutLog>{};
  final sorted = [...history]
    ..sort((a, b) => a.effectivePerformedAt.compareTo(b.effectivePerformedAt));

  for (final log in sorted) {
    final id = log.exerciseId;
    if (id.isEmpty) continue;
    final sessionKey = log.sessionId.trim().isNotEmpty
        ? log.sessionId
        : '${log.date.year}-${log.date.month}-${log.date.day}';
    sessionsByExercise.putIfAbsent(id, () => <String>{}).add(sessionKey);
    final previousLast = lastByExercise[id];
    if (previousLast != null) previousByExercise[id] = previousLast;
    lastByExercise[id] = log;
  }

  // Historia jest WIARYGODNA dopiero wtedy, gdy w ogóle coś w niej jest —
  // pojedynczy wpis nie pozwala odróżnić „nowego ćwiczenia" od „pierwszego
  // zapisu w aplikacji" (spec 24: nie udajemy precyzji, której nie mamy).
  final totalSessions = <String>{
    for (final log in sorted)
      log.sessionId.trim().isNotEmpty
          ? log.sessionId
          : '${log.date.year}-${log.date.month}-${log.date.day}',
  }.length;
  final historyIsMeaningful = totalSessions >= 3;

  final result = <String, ExerciseFamiliarity>{};
  sessionsByExercise.forEach((id, sessions) {
    final last = lastByExercise[id]!;
    final previous = previousByExercise[id];
    final days = reference.difference(last.effectivePerformedAt).inDays;
    var loadJump = 0.0;
    var volumeJump = 0.0;
    if (previous != null) {
      if (previous.weightKg > 0 && last.weightKg > 0) {
        loadJump = (last.weightKg - previous.weightKg) / previous.weightKg;
      }
      final previousVolume = (previous.sets * previous.reps).toDouble();
      final lastVolume = (last.sets * last.reps).toDouble();
      if (previousVolume > 0) {
        volumeJump = (lastVolume - previousVolume) / previousVolume;
      }
    }
    result[id] = ExerciseFamiliarity(
      sessions: sessions.length,
      lastPerformed: last.effectivePerformedAt,
      daysSinceLast: days < 0 ? 0 : days,
      loadJump: loadJump,
      volumeJump: volumeJump,
      known: historyIsMeaningful,
    );
  });
  return result;
}

// ===========================================================================
// Obciążenie ostre vs. przewlekłe (spec 26)
// ===========================================================================

/// Porównanie ostatniego tygodnia z typową normą użytkownika.
class AcuteChronicLoad {
  const AcuteChronicLoad({
    this.acuteUnits = 0,
    this.chronicUnitsPerWeek = 0,
    this.hasBaseline = false,
  });

  static const AcuteChronicLoad unknown = AcuteChronicLoad();

  /// Jednostki bodźca z ostatnich 7 dni.
  final double acuteUnits;

  /// Typowe tygodniowe obciążenie użytkownika (średnia z ~4 tygodni).
  final double chronicUnitsPerWeek;

  final bool hasBaseline;

  /// Iloraz ostry/przewlekły. 1.0 = jak zwykle.
  double get ratio {
    if (!hasBaseline || chronicUnitsPerWeek <= 0.2) return 1.0;
    return (acuteUnits / chronicUnitsPerWeek).clamp(0.0, 4.0).toDouble();
  }

  /// Czy tydzień jest wyraźnie cięższy niż norma (np. 12 → 25 serii).
  bool get isSpike => hasBaseline && ratio >= 1.6;

  /// Mnożnik gotowości: nagły skok = ostrożniej, spokojny tydzień = neutralnie.
  double get readinessModifier {
    if (!hasBaseline) return 1.0;
    final value = ratio;
    if (value >= 2.0) return 0.88;
    if (value >= 1.6) return 0.93;
    if (value >= 1.3) return 0.97;
    return 1.0;
  }
}

// ===========================================================================
// Silnik gotowości
// ===========================================================================

/// Pojedynczy bodziec zapisany w partii.
class _MuscleEvent {
  _MuscleEvent({
    required this.at,
    required this.units,
    required this.sessionId,
    required this.exerciseName,
    required this.familiarity,
  });

  final DateTime at;
  final StimulusUnits units;
  final String sessionId;
  final String exerciseName;
  final ExerciseFamiliarity familiarity;
}

/// Wynik obliczeń silnika dla całego ciała.
class RecoveryComputation {
  const RecoveryComputation({
    required this.byMuscle,
    required this.systemicFatigue,
    required this.acuteChronic,
    required this.confidenceInputs,
    required this.missingInputs,
  });

  final Map<BodyMuscle, MuscleReadiness> byMuscle;

  /// Zmęczenie ogólnoustrojowe 0–1 (spec 1G).
  final double systemicFatigue;

  final AcuteChronicLoad acuteChronic;

  /// Etykiety danych, które zasiliły model (do UI „dlaczego").
  final List<String> confidenceInputs;

  /// Czego zabrakło (obniża pewność).
  final List<String> missingInputs;
}

/// Główny silnik: historia + kontekst → gotowość każdej partii.
class RecoveryEngine {
  const RecoveryEngine({
    this.profile = const RecoveryProfile(),
    this.environment = RecoveryEnvironment.unknown,
    this.calibration = RecoveryCalibrationProfile.empty,
    this.analysisWindow = const Duration(hours: 96),
  });

  final RecoveryProfile profile;
  final RecoveryEnvironment environment;
  final RecoveryCalibrationProfile calibration;
  final Duration analysisWindow;

  /// Partie obciążane przez aktywności cardio. Bieg to NIE tylko kroki:
  /// realnie męczy łydki, uda, pośladki i zginacze bioder.
  static Map<BodyMuscle, double> cardioMuscleWeights(TrainerActivityType type) {
    switch (type) {
      case TrainerActivityType.run:
        return const {
          BodyMuscle.calvesBack: 1.0,
          BodyMuscle.calvesFront: 0.4,
          BodyMuscle.tibialis: 0.35,
          BodyMuscle.quads: 0.75,
          BodyMuscle.hamstrings: 0.6,
          BodyMuscle.glutes: 0.5,
          BodyMuscle.hipFlexors: 0.4,
        };
      case TrainerActivityType.measuredWalk:
        return const {
          BodyMuscle.calvesBack: 0.45,
          BodyMuscle.quads: 0.3,
          BodyMuscle.glutes: 0.25,
          BodyMuscle.hipFlexors: 0.2,
        };
      case TrainerActivityType.bike:
        return const {
          BodyMuscle.quads: 0.8,
          BodyMuscle.glutes: 0.5,
          BodyMuscle.hamstrings: 0.35,
          BodyMuscle.calvesBack: 0.3,
        };
      case TrainerActivityType.strengthTraining:
      case TrainerActivityType.ordinaryStepsWalk:
      case TrainerActivityType.otherCardio:
        return const {};
    }
  }

  RecoveryComputation compute({
    required List<WorkoutLog> logs,
    required Exercise Function(String id) resolveExercise,
    List<TrainerActivityEntry> activities = const [],
    List<WorkoutLog>? historyForFamiliarity,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(analysisWindow);
    final loadCalculator = TrainingLoadCalculator(profile: profile);
    final familiarity = buildFamiliarityMap(
      historyForFamiliarity ?? logs,
      now: reference,
    );

    DateTime stimulusAt(WorkoutLog log) {
      final moment = log.effectivePerformedAt;
      return moment.isAfter(reference) ? reference : moment;
    }

    final events = <BodyMuscle, List<_MuscleEvent>>{};
    var sessionUnits = 0.0; // do zmęczenia ogólnoustrojowego
    var recentHardSets = 0;
    var rpeSamples = 0;
    var setLevelSamples = 0;
    var totalLogsInWindow = 0;

    for (final log in logs) {
      final at = stimulusAt(log);
      if (at.isBefore(cutoff)) continue;
      final exercise = resolveExercise(log.exerciseId);
      final impacts = exercise.effectiveMuscleImpacts;
      if (impacts.isEmpty) continue;
      totalLogsInWindow++;
      if (log.rpe > 0) rpeSamples++;
      if (log.workoutSets.isNotEmpty) setLevelSamples++;

      final base = loadCalculator.unitsFor(log, exercise);
      if (base.isEmpty) continue;
      final exerciseFamiliarity =
          familiarity[log.exerciseId] ?? ExerciseFamiliarity.unknown;

      sessionUnits += base.magnitude;
      for (final set in loadCalculator.setsFor(log, exercise)) {
        if (set.repsInReserve <= 2.5) recentHardSets++;
      }

      for (final impact in impacts) {
        final contribution = impact.effectiveWeight;
        if (contribution <= 0.01) continue;
        // Wkład partii jest różny dla różnych wymiarów: obciążenie NERWOWE
        // koncentruje się na partii prowadzącej ruch mocniej niż zmęczenie
        // metaboliczne, które rozkłada się szerzej (spec 4).
        final units = StimulusUnits(
          local: base.local * contribution,
          neural: base.neural * math.pow(contribution, 1.25).toDouble(),
          structural: base.structural *
              contribution *
              exerciseFamiliarity.structuralModifier,
          energy: base.energy * math.pow(contribution, 0.85).toDouble(),
        );
        if (units.isEmpty) continue;
        events.putIfAbsent(impact.muscleGroup, () => []).add(_MuscleEvent(
              at: at,
              units: units,
              sessionId: log.sessionId,
              exerciseName: exercise.name,
              familiarity: exerciseFamiliarity,
            ));
      }
    }

    // Aktywności cardio — osobne bodźce (czas × intensywność × typ).
    for (final entry in activities) {
      if (entry.date.isBefore(cutoff) || entry.date.isAfter(reference)) {
        continue;
      }
      final weights = cardioMuscleWeights(entry.type);
      if (weights.isEmpty) continue;
      final minutes = entry.durationMin > 0
          ? entry.durationMin
          : entry.estimatedKcal > 0
              ? (entry.estimatedKcal / 9).round()
              : 0;
      if (minutes <= 0) continue;
      final durationFactor = (minutes / 45.0).clamp(0.2, 2.5).toDouble();
      final bodyWeight = profile.effectiveBodyWeightKg;
      var intensity = 1.0;
      if (entry.estimatedKcal > 0) {
        final kcalPerMin = entry.estimatedKcal / minutes;
        intensity =
            (kcalPerMin / (bodyWeight * 0.12)).clamp(0.5, 1.8).toDouble();
      }
      if (entry.avgHeartRate > 0) {
        final maxHr = (220 - profile.age).clamp(120, 210);
        final hrFactor =
            (0.4 + entry.avgHeartRate / maxHr).clamp(0.5, 1.8).toDouble();
        if (hrFactor > intensity) intensity = hrFactor;
      }
      final magnitude = (durationFactor * intensity).clamp(0.1, 5.0).toDouble();
      sessionUnits += magnitude * 0.5;

      weights.forEach((muscle, roleWeight) {
        final scaled = magnitude * roleWeight;
        if (scaled <= 0.05) return;
        // Cardio to przede wszystkim koszt ENERGETYCZNY i lokalny; koszt
        // strukturalny jest niski (chyba że bieg z dużą ekscentryką zbiegów —
        // tego nie mierzymy, więc nie udajemy).
        events.putIfAbsent(muscle, () => []).add(_MuscleEvent(
              at: entry.effectiveStart,
              units: StimulusUnits(
                local: scaled * 0.75,
                neural: scaled * 0.35,
                structural: scaled * 0.30,
                energy: scaled * 1.1,
              ),
              sessionId: entry.id,
              exerciseName: entry.type.label,
              familiarity: ExerciseFamiliarity.unknown,
            ));
      });
    }

    final acuteChronic = _acuteChronicLoad(logs, resolveExercise, reference);
    final systemic = _systemicFatigue(
      sessionUnits: sessionUnits,
      hardSets: recentHardSets,
      acuteChronic: acuteChronic,
      logs: logs,
      reference: reference,
    );

    final confidenceInputs = <String>[];
    final missingInputs = <String>[];
    if (totalLogsInWindow > 0) confidenceInputs.add('historia treningów');
    if (rpeSamples > 0) {
      confidenceInputs.add('ocena wysiłku (RPE)');
    } else if (totalLogsInWindow > 0) {
      missingInputs.add('brak ocen wysiłku (RPE/RIR)');
    }
    if (setLevelSamples > 0) confidenceInputs.add('dane pojedynczych serii');
    if (environment.hasSleepData) {
      confidenceInputs.add('sen z Health Connect');
    } else {
      missingInputs.add('brak danych o śnie');
    }
    if (environment.hasNutritionData) {
      confidenceInputs.add('odżywianie z Licznika Kalorii');
    } else {
      missingInputs.add('brak danych o odżywianiu');
    }
    if (environment.hasSubjectiveData) {
      confidenceInputs.add('samopoczucie / bolesność');
    }
    if (!calibration.isEmpty) {
      confidenceInputs.add('kalibracja indywidualna');
    }

    final result = <BodyMuscle, MuscleReadiness>{};
    events.forEach((muscle, muscleEvents) {
      final readiness = _readinessFor(
        muscle: muscle,
        events: muscleEvents,
        now: reference,
        systemicFatigue: systemic,
        acuteChronic: acuteChronic,
        rpeCoverage: totalLogsInWindow == 0
            ? 0.0
            : (rpeSamples / totalLogsInWindow).clamp(0.0, 1.0).toDouble(),
        setLevelCoverage: totalLogsInWindow == 0
            ? 0.0
            : (setLevelSamples / totalLogsInWindow).clamp(0.0, 1.0).toDouble(),
      );
      if (readiness != null) result[muscle] = readiness;
    });

    return RecoveryComputation(
      byMuscle: result,
      systemicFatigue: systemic,
      acuteChronic: acuteChronic,
      confidenceInputs: confidenceInputs,
      missingInputs: missingInputs,
    );
  }

  /// Ostre (7 dni) vs. przewlekłe (28 dni) obciążenie użytkownika.
  AcuteChronicLoad _acuteChronicLoad(
    List<WorkoutLog> logs,
    Exercise Function(String id) resolveExercise,
    DateTime reference,
  ) {
    if (logs.isEmpty) return AcuteChronicLoad.unknown;
    final calculator = TrainingLoadCalculator(profile: profile);
    final acuteFrom = reference.subtract(const Duration(days: 7));
    final chronicFrom = reference.subtract(const Duration(days: 28));
    var acute = 0.0;
    var chronic = 0.0;
    var chronicDays = 0;
    DateTime? oldest;
    for (final log in logs) {
      final at = log.effectivePerformedAt;
      if (at.isAfter(reference)) continue;
      if (at.isBefore(chronicFrom)) continue;
      final exercise = resolveExercise(log.exerciseId);
      if (exercise.effectiveMuscleImpacts.isEmpty) continue;
      final magnitude = calculator.unitsFor(log, exercise).magnitude;
      chronic += magnitude;
      if (!at.isBefore(acuteFrom)) acute += magnitude;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    if (oldest != null) {
      chronicDays = reference.difference(oldest).inDays;
    }
    // Norma tygodniowa ma sens dopiero po ~2,5 tygodnia obserwacji.
    if (chronicDays < 17 || chronic <= 0) {
      return AcuteChronicLoad(acuteUnits: acute, hasBaseline: false);
    }
    final weeks = (chronicDays / 7.0).clamp(1.0, 4.0);
    return AcuteChronicLoad(
      acuteUnits: acute,
      chronicUnitsPerWeek: chronic / weeks,
      hasBaseline: true,
    );
  }

  /// Zmęczenie ogólnoustrojowe 0–1 (spec 1G).
  ///
  /// Bardzo ciężki dzień nóg może zostawić quadriceps w przyzwoitym stanie,
  /// a użytkownika i tak „rozłożonego" — dlatego jest to WSPÓLNY, niezależny
  /// od partii modyfikator, liczony z całkowitej objętości, bliskości upadku,
  /// liczby trenowanych partii, snu i deficytu energetycznego.
  double _systemicFatigue({
    required double sessionUnits,
    required int hardSets,
    required AcuteChronicLoad acuteChronic,
    required List<WorkoutLog> logs,
    required DateTime reference,
  }) {
    // Świeżość: liczy się przede wszystkim ostatnia doba.
    var recentUnits = 0.0;
    final dayAgo = reference.subtract(const Duration(hours: 30));
    for (final log in logs) {
      final at = log.effectivePerformedAt;
      if (at.isBefore(dayAgo) || at.isAfter(reference)) continue;
      final hoursSince = reference.difference(at).inMinutes / 60.0;
      recentUnits += math.exp(-hoursSince / 20.0);
    }
    var fatigue = 1 - math.exp(-(sessionUnits * 0.05 + recentUnits * 0.06));
    if (hardSets >= 25) {
      fatigue += 0.10;
    } else if (hardSets >= 15) {
      fatigue += 0.05;
    }
    // Sen i energia działają na CAŁY organizm, nie na jedną partię.
    final sleep = environment.sleepFactor;
    if (sleep < 1.0) fatigue += (1.0 - sleep) * 0.9;
    final energy = environment.energyFactor;
    if (energy < 1.0) fatigue += (1.0 - energy) * 0.5;
    if (acuteChronic.isSpike) fatigue += 0.06;
    return fatigue.clamp(0.0, 1.0).toDouble();
  }

  MuscleReadiness? _readinessFor({
    required BodyMuscle muscle,
    required List<_MuscleEvent> events,
    required DateTime now,
    required double systemicFatigue,
    required AcuteChronicLoad acuteChronic,
    required double rpeCoverage,
    required double setLevelCoverage,
  }) {
    if (events.isEmpty) return null;
    final muscleProfile = muscleRecoveryProfile(muscle);
    final muscleCalibration = calibration.forMuscle(muscle);
    final tauScale = profile.recoveryFactor * muscleCalibration.effectiveScale;

    var totalUnits = 0.0;
    for (final event in events) {
      totalUnits += event.units.magnitude;
    }
    final magnitudeScale = _magnitudeTauScale(totalUnits);

    final localTau =
        muscleProfile.localTauHours * magnitudeScale * tauScale;
    final neuralTau =
        muscleProfile.neuralTauHours * magnitudeScale * tauScale;
    // Odżywianie zmienia TEMPO odbudowy, nie wielkość bodźca (Ivy 1988,
    // Areta 2014, Moore 2009 — dostępność substratu modyfikuje odpowiedź).
    final structuralTau = muscleProfile.structuralTauHours *
        magnitudeScale *
        tauScale /
        environment.proteinFactor;
    final energyTau = muscleProfile.energyTauHours *
        magnitudeScale *
        tauScale /
        environment.energyFactor;

    var localLoad = 0.0;
    var neuralLoad = 0.0;
    var structuralLoad = 0.0;
    var energyLoad = 0.0;
    var remodelling = 0.0;
    var adaptationSum = 0.0;
    var adaptationWeight = 0.0;
    var familiarityPenalty = 0.0;
    _MuscleEvent? latest;
    final names = <String>{};

    for (final event in events) {
      final hours = now.difference(event.at).inMinutes / 60.0;
      final elapsed = hours < 0 ? 0.0 : hours;
      final size = muscleProfile.sizeScale;
      localLoad += event.units.local *
          _kLocalLoad *
          size *
          math.exp(-elapsed / localTau);
      neuralLoad += event.units.neural *
          _kNeuralLoad *
          size *
          math.exp(-elapsed / neuralTau);
      structuralLoad += event.units.structural *
          _kStructuralLoad *
          size *
          math.exp(-elapsed / structuralTau);
      energyLoad += event.units.energy *
          _kEnergyLoad *
          size *
          math.exp(-elapsed / energyTau);

      // Przebudowa tkanki: MacDougall 1995 pokazał szczyt MPS w pierwszych
      // godzinach z powrotem do wartości wyjściowych w ciągu ~36 h, Phillips
      // 1997 — podwyższoną MPS jeszcze po 48 h. Rozbieżność między protokołami
      // jest realna, więc zamiast wybierać jedną liczbę modelujemy SZEROKIE,
      // gasnące okno i traktujemy je jako informację, nie jako blokadę.
      remodelling += event.units.magnitude * math.exp(-elapsed / 26.0);

      adaptationSum += event.familiarity.score * event.units.magnitude;
      adaptationWeight += event.units.magnitude;
      familiarityPenalty =
          math.max(familiarityPenalty, event.familiarity.confidencePenalty);

      names.add(event.exerciseName);
      if (latest == null || !event.at.isBefore(latest.at)) latest = event;
    }
    if (latest == null) return null;

    double recovered(double load) =>
        (math.exp(-load)).clamp(0.0, 1.0).toDouble();

    final local = recovered(localLoad);
    final neural = recovered(neuralLoad);
    final structural = recovered(structuralLoad);
    final energy = recovered(energyLoad);
    final adaptation =
        adaptationWeight <= 0 ? 0.5 : adaptationSum / adaptationWeight;

    // ---- Pewność prognozy (spec 7) ----
    var confidence = 0.32;
    confidence += (events.length / 12).clamp(0.0, 0.12);
    confidence += rpeCoverage * 0.18;
    confidence += setLevelCoverage * 0.12;
    if (environment.hasSleepData) confidence += 0.06;
    if (environment.hasNutritionData) confidence += 0.06;
    if (environment.hasSubjectiveData) confidence += 0.04;
    confidence += muscleCalibration.confidenceBonus;
    if (acuteChronic.hasBaseline) confidence += 0.05;
    confidence -= familiarityPenalty;
    if (acuteChronic.isSpike) confidence -= 0.05;
    confidence = confidence.clamp(0.15, 0.93).toDouble();

    final reasons = _reasonsFor(
      muscle: muscle,
      local: local,
      neural: neural,
      structural: structural,
      energy: energy,
      adaptation: adaptation,
      systemicFatigue: systemicFatigue,
      acuteChronic: acuteChronic,
      lastAt: latest.at,
      now: now,
    );

    return MuscleReadiness(
      muscle: muscle,
      localFatigue: local,
      neuromuscular: neural,
      structural: structural,
      energy: energy,
      remodelling: remodelling.clamp(0.0, 1.0).toDouble(),
      subjective: environment.subjectiveScore.clamp(0.0, 1.0).toDouble(),
      adaptation: adaptation,
      systemicFatigue: systemicFatigue,
      accumulatedLoad: acuteChronic.readinessModifier,
      confidence: confidence,
      lastStimulusAt: latest.at,
      lastStimulusMagnitude: latest.units.magnitude,
      totalStimulus: totalUnits,
      lastExerciseNames: names.toList(),
      lastSessionId: latest.sessionId,
      reasons: reasons,
      hasData: true,
    );
  }

  List<ReadinessReason> _reasonsFor({
    required BodyMuscle muscle,
    required double local,
    required double neural,
    required double structural,
    required double energy,
    required double adaptation,
    required double systemicFatigue,
    required AcuteChronicLoad acuteChronic,
    required DateTime lastAt,
    required DateTime now,
  }) {
    final reasons = <ReadinessReason>[];
    void add(String code, String label, bool positive, double weight) =>
        reasons.add(ReadinessReason(
            code: code, label: label, positive: positive, weight: weight));

    final hoursSince = now.difference(lastAt).inHours;
    if (local < 0.5) {
      add('localFatigue',
          'Świeże zmęczenie lokalne (${(local * 100).round()}% odzyskane)',
          false, 1 - local);
    } else if (local >= 0.85) {
      add('recoveredMuscle', 'Lokalne zmęczenie praktycznie ustąpiło', true,
          local);
    }
    if (neural < 0.6) {
      add('neuromuscularFatigue',
          'Układ nerwowo-mięśniowy jeszcze nie wrócił (${(neural * 100).round()}%)',
          false, 1 - neural);
    }
    if (structural < 0.6) {
      add('structuralStress',
          'Trwa naprawa po mocnym bodźcu mechanicznym (${(structural * 100).round()}%)',
          false, 1 - structural);
    }
    if (energy < 0.6) {
      add('energyDepleted',
          'Zasoby energetyczne jeszcze się odbudowują (${(energy * 100).round()}%)',
          false, 1 - energy);
    }
    if (adaptation < 0.35) {
      add('newStimulus',
          'Bodziec był dla tej partii nowy — reakcja bywa większa', false, 0.6);
    } else if (adaptation > 0.8) {
      add('familiarStimulus', 'Ruch dobrze oswojony — mniejsze uszkodzenia',
          true, 0.5);
    }
    if (systemicFatigue > 0.45) {
      add('systemicFatigue', 'Wysokie zmęczenie ogólne organizmu', false,
          systemicFatigue);
    }
    if (acuteChronic.isSpike) {
      add('loadSpike',
          'Ten tydzień jest wyraźnie cięższy niż Twoja norma', false, 0.7);
    }
    if (environment.hasSleepData && environment.sleepFactor < 1.0) {
      add('poorSleep', 'Krótki sen spowalnia regenerację', false,
          1 - environment.sleepFactor);
    } else if (environment.hasSleepData && environment.sleepFactor > 1.0) {
      add('goodSleep', 'Sen w normie', true, 0.4);
    }
    if (environment.hasNutritionData && environment.energyFactor < 1.0) {
      add('energyDeficit', 'Deficyt energetyczny obciąża regenerację', false,
          1 - environment.energyFactor);
    }
    if (hoursSince >= 48 && local > 0.8) {
      add('timeSinceStimulus', 'Od ostatniego bodźca minęło ponad 48 h', true,
          0.5);
    }
    reasons.sort((a, b) => b.weight.compareTo(a.weight));
    return reasons;
  }
}

// ===========================================================================
// Prognoza: kiedy partia będzie gotowa
// ===========================================================================

/// Szacowany czas (godziny) do osiągnięcia [targetPercent] gotowości.
///
/// Liczony przez symulację modelu do przodu — bez rozwiązywania równania
/// analitycznie, bo składowe mają różne stałe. Zwraca 0, gdy próg jest już
/// osiągnięty, i `null`, gdy w rozsądnym horyzoncie (168 h) nie da się go
/// osiągnąć (bardzo rzadkie, oznacza wyjątkowo duże obciążenie).
double? hoursToReadiness(
  MuscleReadiness readiness, {
  double targetPercent = 85,
  TrainingStimulusKind kind = TrainingStimulusKind.defaultKind,
  RecoveryProfile profile = const RecoveryProfile(),
  MuscleRecoveryCalibration calibration = const MuscleRecoveryCalibration(),
  double horizonHours = 168,
}) {
  if (readiness.readinessFor(kind) >= targetPercent) return 0;
  final muscleProfile = muscleRecoveryProfile(readiness.muscle);
  final scale = profile.recoveryFactor * calibration.effectiveScale;
  final magnitudeScale = _magnitudeTauScale(readiness.totalStimulus);

  double loadOf(double recoveredFraction) =>
      recoveredFraction <= 0 ? 12.0 : -math.log(recoveredFraction.clamp(1e-6, 1));

  final localLoad = loadOf(readiness.localFatigue);
  final neuralLoad = loadOf(readiness.neuromuscular);
  final structuralLoad = loadOf(readiness.structural);
  final energyLoad = loadOf(readiness.energy);

  for (var hour = 1.0; hour <= horizonHours; hour += 1) {
    final projected = readiness.copyWith(
      localFatigue: math.exp(-localLoad *
          math.exp(-hour / (muscleProfile.localTauHours * magnitudeScale * scale))),
      neuromuscular: math.exp(-neuralLoad *
          math.exp(
              -hour / (muscleProfile.neuralTauHours * magnitudeScale * scale))),
      structural: math.exp(-structuralLoad *
          math.exp(-hour /
              (muscleProfile.structuralTauHours * magnitudeScale * scale))),
      energy: math.exp(-energyLoad *
          math.exp(
              -hour / (muscleProfile.energyTauHours * magnitudeScale * scale))),
      // Zmęczenie ogólne też mija — zakładamy zanik w ~24 h.
      systemicFatigue: readiness.systemicFatigue * math.exp(-hour / 24.0),
    );
    if (projected.readinessFor(kind) >= targetPercent) return hour;
  }
  return null;
}
