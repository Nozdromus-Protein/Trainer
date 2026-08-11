/// Stan regeneracji partii mięśniowych — warstwa zgodności nad [RecoveryEngine].
///
/// Czysty Dart — kolory nakładane są w UI na podstawie
/// [MuscleRecoveryState.recoveryPercent].
///
/// CO SIĘ ZMIENIŁO: dawniej ten plik zawierał cały model regeneracji oparty na
/// jednym „oknie regeneracji partii" (36/30/24 h × mnożniki) i liniowym zaniku
/// bodźca. Teraz liczeniem zajmuje się [RecoveryEngine], który rozkłada
/// regenerację na cztery niezależne wymiary (lokalny, nerwowo-mięśniowy,
/// strukturalny, energetyczny) o różnych krzywych zaniku, dokłada oswojenie
/// z bodźcem, zmęczenie ogólnoustrojowe, sen, odżywianie i kalibrację
/// użytkownika, a na końcu zwraca GOTOWOŚĆ z pewnością prognozy.
///
/// [MuscleRecoveryState] zostaje jako model prezentacyjny: niesie tę samą
/// „jedną liczbę" co wcześniej (`recoveryPercent`), a dodatkowo pełny stan
/// wielowymiarowy w [MuscleRecoveryState.readiness] — dzięki temu istniejące
/// ekrany, planer i most do AI działają bez zmian, a nowe UI może pokazać
/// szczegóły po kliknięciu mięśnia.
library;

import 'activity_credit.dart';
import 'exercise.dart';
import 'recovery_engine.dart';
import 'workout_session.dart';

export 'muscle_readiness.dart';
export 'recovery_engine.dart';

/// Status regeneracji partii mięśniowej.
enum RecoveryStatus {
  unknown('Brak danych'),
  freshFatigue('Świeże zmęczenie'),
  heavyFatigue('Mocne zmęczenie'),
  recovering('Regeneracja w toku'),
  almostRecovered('Prawie zregenerowane'),
  recovered('Zregenerowane');

  const RecoveryStatus(this.label);

  final String label;
}

/// Mapuje procent gotowości na status (null → unknown).
///
/// Progi (spec: punkt 20) opisują GOTOWOŚĆ, nie „procent regeneracji":
///   90–100 → bardzo dobra, 75–89 → dobra, 55–74 → umiarkowana,
///   35–54 → niska, 0–34 → bardzo niska.
/// Te same granice nakłada [recoveryColor] w UI, żeby kolor i opis nie mówiły
/// dwóch różnych rzeczy o tej samej partii.
RecoveryStatus recoveryStatusForPercent(double? percent) {
  if (percent == null) return RecoveryStatus.unknown;
  if (percent < 35) return RecoveryStatus.freshFatigue;
  if (percent < 55) return RecoveryStatus.heavyFatigue;
  if (percent < 75) return RecoveryStatus.recovering;
  if (percent < 90) return RecoveryStatus.almostRecovered;
  return RecoveryStatus.recovered;
}

/// Klasa bodźca treningowego dla partii (na podstawie wielkości bodźca
/// w jednostkach modelu: 1.0 ≈ solidne 3×10 na tę partię jako główną).
enum TrainingIntensity {
  light('Lekki bodziec'),
  moderate('Średni bodziec'),
  hard('Ciężki bodziec'),
  veryHard('Bardzo ciężki bodziec');

  const TrainingIntensity(this.label);

  final String label;

  static TrainingIntensity forStimulus(double stimulus) {
    if (stimulus < 0.55) return TrainingIntensity.light;
    if (stimulus < 1.15) return TrainingIntensity.moderate;
    if (stimulus < 2.0) return TrainingIntensity.hard;
    return TrainingIntensity.veryHard;
  }
}

/// Stan regeneracji pojedynczej partii (model prezentacyjny).
class MuscleRecoveryState {
  const MuscleRecoveryState({
    required this.muscleGroup,
    this.recoveryPercent,
    this.fatiguePercent,
    this.lastTrainedAt,
    this.estimatedFullRecoveryAt,
    this.estimatedHoursRemaining = 0,
    this.lastWorkoutId = '',
    this.lastExerciseNames = const [],
    this.loadScore = 0,
    this.sorenessNote = '',
    this.status = RecoveryStatus.unknown,
    this.intensityLabel = '',
    this.readiness,
  });

  final BodyMuscle muscleGroup;

  /// Gotowość 0–100 dla domyślnego bodźca (dawniej „procent regeneracji").
  final double? recoveryPercent;
  final double? fatiguePercent;
  final DateTime? lastTrainedAt;

  /// Szacowany moment osiągnięcia WYSOKIEJ gotowości (nie „pełnej regeneracji"
  /// — model nie ma podstaw do takiej precyzji; spec 24).
  final DateTime? estimatedFullRecoveryAt;
  final int estimatedHoursRemaining;
  final String lastWorkoutId;
  final List<String> lastExerciseNames;
  final double loadScore;
  final String sorenessNote;
  final RecoveryStatus status;

  /// Etykieta klasy ostatniego bodźca (lekki/średni/ciężki/bardzo ciężki).
  final String intensityLabel;

  /// Pełny, wielowymiarowy stan partii (`null` dla stanów syntetycznych).
  final MuscleReadiness? readiness;

  /// Brak danych = mięsień nigdy nie trenowany w oknie analizy → szary.
  factory MuscleRecoveryState.unknown(BodyMuscle muscle) =>
      MuscleRecoveryState(muscleGroup: muscle);

  /// Buduje stan prezentacyjny z wyniku silnika.
  factory MuscleRecoveryState.fromReadiness(
    MuscleReadiness readiness, {
    double? hoursToHighReadiness,
    DateTime? now,
  }) {
    final percent = readiness.readinessPercent;
    final reference = now ?? DateTime.now();
    final hours = hoursToHighReadiness;
    return MuscleRecoveryState(
      muscleGroup: readiness.muscle,
      recoveryPercent: percent,
      fatiguePercent: 100 - percent,
      lastTrainedAt: readiness.lastStimulusAt,
      estimatedFullRecoveryAt: hours == null
          ? null
          : reference.add(Duration(minutes: (hours * 60).round())),
      estimatedHoursRemaining: hours == null ? 0 : hours.round(),
      lastWorkoutId: readiness.lastSessionId,
      lastExerciseNames: readiness.lastExerciseNames,
      loadScore: readiness.totalStimulus,
      status: recoveryStatusForPercent(percent),
      intensityLabel:
          TrainingIntensity.forStimulus(readiness.lastStimulusMagnitude).label,
      readiness: readiness,
    );
  }

  bool get hasData =>
      recoveryPercent != null && status != RecoveryStatus.unknown;

  String get statusLabel => status.label;

  /// Alias zgodny z opisem etapu — „colorState" to bucket statusu (kolor w UI).
  RecoveryStatus get colorState => status;

  /// Gotowość dla KONKRETNEGO rodzaju planowanego bodźca (spec 3).
  /// Bez pełnego stanu (starsze/syntetyczne wpisy) zwraca zwykły procent.
  double readinessFor(TrainingStimulusKind kind) =>
      readiness?.readinessFor(kind) ?? (recoveryPercent ?? 100);

  /// Pewność prognozy 0–1 (0.5 dla stanów bez pełnych danych).
  double get confidence => readiness?.confidence ?? 0.5;
}

/// Ostrzeżenie o trenowaniu partii, która nie jest jeszcze w pełni gotowa.
///
/// UWAGA PRODUKTOWA (spec 12/34): ostrzeżenie ma INFORMOWAĆ i REKOMENDOWAĆ.
/// Nigdy nie służy do blokowania zestawu ani wyłączania kliknięcia.
class RecoveryWarning {
  const RecoveryWarning({
    required this.muscle,
    required this.recoveryPercent,
    required this.status,
    required this.severe,
    this.role = MuscleRole.primary,
    this.confidence = 0.5,
  });

  final BodyMuscle muscle;
  final double recoveryPercent;
  final RecoveryStatus status;

  /// Czy ostrzeżenie jest mocne (partia bardzo zmęczona — sugeruj lżejszą pracę).
  final bool severe;

  /// Rola partii w ostrzeganym zestawie (główna/pomocnicza).
  final MuscleRole role;

  /// Pewność prognozy gotowości tej partii.
  final double confidence;

  /// Krótka rekomendacja — CO Z TYM ZROBIĆ, nie „nie wolno".
  String get recommendation => severe
      ? 'Możesz trenować, ale Trainer rekomenduje wyraźnie mniejszą objętość '
          'albo lżejszą wersję zestawu.'
      : 'Możesz trenować — rozważ mniejszy ciężar lub o serię mniej.';
}

/// Zwraca ostrzeżenia o gotowości dla zestawu ćwiczeń: partie główne/pomocnicze,
/// które są poniżej progu. Stabilizatory pomijamy, a mocne ostrzeżenie (severe)
/// dotyczy partii poniżej [severeBelow]%.
List<RecoveryWarning> recoveryWarningsForExercises(
  Iterable<Exercise> exercises,
  Map<BodyMuscle, MuscleRecoveryState> recovery, {
  double warnBelow = 60,
  double severeBelow = 40,
  TrainingStimulusKind kind = TrainingStimulusKind.defaultKind,
}) {
  // Najwyższa rola danej partii w całym zestawie (główna > pomocnicza > stab.).
  final roleByMuscle = <BodyMuscle, MuscleRole>{};
  for (final exercise in exercises) {
    for (final impact in exercise.effectiveMuscleImpacts) {
      final existing = roleByMuscle[impact.muscleGroup];
      if (existing == null || impact.role.weight > existing.weight) {
        roleByMuscle[impact.muscleGroup] = impact.role;
      }
    }
  }

  final warnings = <RecoveryWarning>[];
  roleByMuscle.forEach((muscle, role) {
    if (role == MuscleRole.stabilizer) return; // stabilizatorów nie ostrzegamy
    final state = recovery[muscle];
    if (state == null || !state.hasData) return;
    final percent = state.readinessFor(kind);
    if (percent < warnBelow) {
      warnings.add(RecoveryWarning(
        muscle: muscle,
        recoveryPercent: percent,
        status: recoveryStatusForPercent(percent),
        severe: percent < severeBelow,
        role: role,
        confidence: state.confidence,
      ));
    }
  });
  warnings.sort((a, b) => a.recoveryPercent.compareTo(b.recoveryPercent));
  return warnings;
}

/// Lokalna sugestia treningowa dla partii (bez AI).
String recoverySuggestionForMuscle(MuscleRecoveryState state) {
  final detail = state.readiness;
  if (detail != null && state.hasData) {
    // Gotowość zależy od rodzaju bodźca — sugestia mówi wprost, co jest dziś
    // rozsądne, zamiast dzielić świat na „można / nie można" (spec 3).
    final heavy = detail.readinessFor(TrainingStimulusKind.hypertrophy);
    final moderate = detail.readinessFor(TrainingStimulusKind.moderate);
    final light = detail.readinessFor(TrainingStimulusKind.technique);
    if (heavy >= 80) {
      return 'Gotowa do pełnego treningu — możesz zaplanować ciężką pracę.';
    }
    if (moderate >= 70) {
      return 'Umiarkowany trening jest w porządku (${moderate.round()}%); '
          'na ciężką hipertrofię jeszcze trochę za wcześnie (${heavy.round()}%).';
    }
    if (light >= 65) {
      return 'Dziś raczej technika i lekka praca (${light.round()}%) — mocny '
          'bodziec byłby kosztowny (${heavy.round()}%).';
    }
    return 'Partia po mocnym bodźcu — najlepiej aktywna regeneracja albo inna '
        'partia. Trening jest możliwy, ale rekomendujemy mniejszą objętość.';
  }
  switch (state.status) {
    case RecoveryStatus.unknown:
      return 'Brak danych — wykonaj trening, aby śledzić gotowość tej partii.';
    case RecoveryStatus.freshFatigue:
    case RecoveryStatus.heavyFatigue:
      return 'Mocno zmęczona — dziś lepiej lżejsza wersja albo inna partia.';
    case RecoveryStatus.recovering:
      return 'Regeneracja w toku — możliwy lekki trening, bez maksymalnej intensywności.';
    case RecoveryStatus.almostRecovered:
      return 'Prawie gotowe — niedługo można obciążyć tę partię mocniej.';
    case RecoveryStatus.recovered:
      return 'Zregenerowane — partia gotowa do pełnego treningu.';
  }
}

/// Liczy stan gotowości partii na podstawie historii treningów.
///
/// Cienka warstwa nad [RecoveryEngine] — zachowuje sygnaturę używaną w całej
/// aplikacji, a dodatkowo przyjmuje kontekst regeneracji (sen, odżywianie)
/// i kalibrację użytkownika. Brak tych danych NIE psuje wyniku: dają neutralny
/// modyfikator i niższą pewność (spec 10/31).
class RecoveryCalculator {
  const RecoveryCalculator({
    this.analysisWindow = const Duration(hours: 96),
    this.profile = const RecoveryProfile(),
    this.environment = RecoveryEnvironment.unknown,
    this.calibration = RecoveryCalibrationProfile.empty,
  });

  /// Okno analizy — starsze treningi traktujemy jako w pełni zregenerowane.
  final Duration analysisWindow;

  /// Profil użytkownika (wiek, poziom, płeć, masa ciała…).
  final RecoveryProfile profile;

  /// Sen / odżywianie / samopoczucie (opcjonalne).
  final RecoveryEnvironment environment;

  /// Indywidualna kalibracja stałych czasowych (opcjonalna).
  final RecoveryCalibrationProfile calibration;

  /// Próg „wysokiej gotowości" używany w prognozie czasu.
  static const double highReadinessPercent = 85;

  RecoveryEngine get engine => RecoveryEngine(
        profile: profile,
        environment: environment,
        calibration: calibration,
        analysisWindow: analysisWindow,
      );

  /// Pełny wynik silnika (gotowość + zmęczenie ogólne + obciążenie tygodnia).
  RecoveryComputation computeDetailed({
    required List<WorkoutLog> logs,
    required Exercise Function(String id) resolveExercise,
    List<TrainerActivityEntry> activities = const [],
    List<WorkoutLog>? historyForFamiliarity,
    DateTime? now,
  }) =>
      engine.compute(
        logs: logs,
        resolveExercise: resolveExercise,
        activities: activities,
        historyForFamiliarity: historyForFamiliarity,
        now: now,
      );

  Map<BodyMuscle, MuscleRecoveryState> compute({
    required List<WorkoutLog> logs,
    required Exercise Function(String id) resolveExercise,
    List<TrainerActivityEntry> activities = const [],
    List<WorkoutLog>? historyForFamiliarity,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final computation = computeDetailed(
      logs: logs,
      resolveExercise: resolveExercise,
      activities: activities,
      historyForFamiliarity: historyForFamiliarity,
      now: reference,
    );
    return statesFrom(computation, now: reference);
  }

  /// Zamienia wynik silnika na mapę stanów prezentacyjnych.
  Map<BodyMuscle, MuscleRecoveryState> statesFrom(
    RecoveryComputation computation, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final result = <BodyMuscle, MuscleRecoveryState>{};
    computation.byMuscle.forEach((muscle, readiness) {
      result[muscle] = MuscleRecoveryState.fromReadiness(
        readiness,
        hoursToHighReadiness: hoursToReadiness(
          readiness,
          targetPercent: highReadinessPercent,
          profile: profile,
          calibration: calibration.forMuscle(muscle),
        ),
        now: reference,
      );
    });
    return result;
  }
}
