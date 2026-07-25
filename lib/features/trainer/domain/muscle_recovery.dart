/// Modele i kalkulator regeneracji mięśni (Etap mapy regeneracji).
///
/// Czysty Dart — kolory nakładane są w UI na podstawie [MuscleRecoveryState.recoveryPercent].
///
/// Kalkulator działa na punktach intensywności: każdy wpis treningowy zostawia
/// w partii "bodziec" zależny od objętości (serie × powtórzenia), ciężaru
/// względem masy ciała, RPE, czasu pracy, typu ćwiczenia i roli partii.
/// Bodziec wygasa liniowo w oknie regeneracji zależnym od wielkości partii,
/// klasy bodźca (lekki/średni/ciężki/bardzo ciężki) i profilu użytkownika
/// ([RecoveryProfile]: wiek, poziom, płeć, masa ciała).
///
/// Okno regeneracji jest dodatkowo korygowane przez realne obciążenie:
///  - korekta ZESTAWU ([sessionLoadAdjustment]) — średnie RPE i objętość kg
///    jednej sesji treningowej,
///  - korekta DNIA ([dayLoadAdjustment]) — średnie RPE dnia i łączna objętość
///    kg dnia (kilka zestawów jednego dnia wydłuża regenerację bardziej niż
///    jeden; lekki dzień ją skraca). Kalkulator przelicza się po każdym
///    zapisie treningu, więc po ostatnim treningu dnia korekta dnia obejmuje
///    automatycznie wszystkie zestawy z tego dnia.
library;

import 'activity_credit.dart';
import 'exercise.dart';
import 'workout_session.dart';

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

/// Mapuje procent regeneracji na status (null → unknown).
RecoveryStatus recoveryStatusForPercent(double? percent) {
  if (percent == null) return RecoveryStatus.unknown;
  if (percent <= 20) return RecoveryStatus.freshFatigue;
  if (percent <= 40) return RecoveryStatus.heavyFatigue;
  if (percent <= 60) return RecoveryStatus.recovering;
  if (percent <= 80) return RecoveryStatus.almostRecovered;
  return RecoveryStatus.recovered;
}

/// Klasa bodźca treningowego dla partii (na podstawie punktów intensywności).
enum TrainingIntensity {
  light('Lekki bodziec', 0.5),
  moderate('Średni bodziec', 0.85),
  hard('Ciężki bodziec', 1.25),
  veryHard('Bardzo ciężki bodziec', 1.7);

  const TrainingIntensity(this.label, this.recoveryMultiplier);

  final String label;

  /// Mnożnik bazowego okna regeneracji partii.
  final double recoveryMultiplier;

  static TrainingIntensity forStimulus(double stimulus) {
    if (stimulus < 0.8) return TrainingIntensity.light;
    if (stimulus < 1.7) return TrainingIntensity.moderate;
    if (stimulus < 2.8) return TrainingIntensity.hard;
    return TrainingIntensity.veryHard;
  }
}

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

  /// Łączny mnożnik czasu regeneracji wynikający z profilu.
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
}

/// Bazowe okno regeneracji partii przy średnim bodźcu (godziny).
/// Duże partie regenerują się dłużej niż małe.
double baseRecoveryHoursForMuscle(BodyMuscle muscle) {
  switch (muscle) {
    case BodyMuscle.quads:
    case BodyMuscle.hamstrings:
    case BodyMuscle.glutes:
    case BodyMuscle.gluteMedius:
    case BodyMuscle.lats:
    case BodyMuscle.lowerBack:
    case BodyMuscle.erectorSpinae:
    case BodyMuscle.quadratusLumborum:
    case BodyMuscle.upperBack:
    case BodyMuscle.rhomboids:
    case BodyMuscle.chest:
      return 36;
    case BodyMuscle.frontShoulders:
    case BodyMuscle.rearShoulders:
    case BodyMuscle.traps:
    case BodyMuscle.adductors:
    case BodyMuscle.hipFlexors:
    case BodyMuscle.supraspinatus:
    case BodyMuscle.infraspinatus:
    case BodyMuscle.teresMinor:
    case BodyMuscle.teresMajor:
    case BodyMuscle.subscapularis:
    case BodyMuscle.levatorScapulae:
    case BodyMuscle.tensorFasciaeLatae:
      return 30;
    case BodyMuscle.abs:
    case BodyMuscle.obliques:
    case BodyMuscle.biceps:
    case BodyMuscle.triceps:
    case BodyMuscle.forearmsFront:
    case BodyMuscle.forearmsBack:
    case BodyMuscle.calvesFront:
    case BodyMuscle.calvesBack:
    case BodyMuscle.tibialis:
    case BodyMuscle.sternocleidomastoid:
    case BodyMuscle.sideWaistBack:
    case BodyMuscle.sartorius:
    case BodyMuscle.gracilis:
    case BodyMuscle.soleus:
    case BodyMuscle.gastrocnemius:
    case BodyMuscle.serratusAnterior:
    case BodyMuscle.transverseAbdominis:
      return 24;
  }
}

/// Stan regeneracji pojedynczej partii.
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
  });

  final BodyMuscle muscleGroup;
  final double? recoveryPercent;
  final double? fatiguePercent;
  final DateTime? lastTrainedAt;
  final DateTime? estimatedFullRecoveryAt;
  final int estimatedHoursRemaining;
  final String lastWorkoutId;
  final List<String> lastExerciseNames;
  final double loadScore;
  final String sorenessNote;
  final RecoveryStatus status;

  /// Etykieta klasy ostatniego bodźca (lekki/średni/ciężki/bardzo ciężki).
  final String intensityLabel;

  /// Brak danych = mięsień nigdy nie trenowany w oknie analizy → szary.
  factory MuscleRecoveryState.unknown(BodyMuscle muscle) =>
      MuscleRecoveryState(muscleGroup: muscle);

  bool get hasData =>
      recoveryPercent != null && status != RecoveryStatus.unknown;

  String get statusLabel => status.label;

  /// Alias zgodny z opisem etapu — „colorState" to bucket statusu (kolor liczony w UI).
  RecoveryStatus get colorState => status;
}

/// Ostrzeżenie o trenowaniu partii, która jest jeszcze w trakcie regeneracji.
class RecoveryWarning {
  const RecoveryWarning({
    required this.muscle,
    required this.recoveryPercent,
    required this.status,
    required this.severe,
  });

  final BodyMuscle muscle;
  final double recoveryPercent;
  final RecoveryStatus status;

  /// Czy ostrzeżenie jest mocne (partia bardzo zmęczona — sugeruj odpuszczenie).
  final bool severe;
}

/// Zwraca ostrzeżenia o regeneracji dla zestawu ćwiczeń: partie główne/pomocnicze,
/// które są poniżej progu regeneracji. „W miarę rozumu" — stabilizatory pomijamy,
/// a mocne ostrzeżenie (severe) dotyczy partii poniżej [severeBelow]%.
List<RecoveryWarning> recoveryWarningsForExercises(
  Iterable<Exercise> exercises,
  Map<BodyMuscle, MuscleRecoveryState> recovery, {
  double warnBelow = 60,
  double severeBelow = 40,
}) {
  // Najwyższa rola danej partii w całym zestawie (główna > pomocnicza > stabilizacja).
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
    final percent = state.recoveryPercent ?? 100;
    if (percent < warnBelow) {
      warnings.add(RecoveryWarning(
        muscle: muscle,
        recoveryPercent: percent,
        status: state.status,
        severe: percent < severeBelow,
      ));
    }
  });
  warnings.sort((a, b) => a.recoveryPercent.compareTo(b.recoveryPercent));
  return warnings;
}

/// Lokalna sugestia treningowa dla partii (bez AI).
String recoverySuggestionForMuscle(MuscleRecoveryState state) {
  switch (state.status) {
    case RecoveryStatus.unknown:
      return 'Brak danych — wykonaj trening, aby śledzić regenerację tej partii.';
    case RecoveryStatus.freshFatigue:
    case RecoveryStatus.heavyFatigue:
      return 'Mocno zmęczona — dziś lepiej odpuść tę partię albo zrób lżejszą wersję.';
    case RecoveryStatus.recovering:
      return 'Regeneracja w toku — możliwy lekki trening, bez maksymalnej intensywności.';
    case RecoveryStatus.almostRecovered:
      return 'Prawie gotowe — niedługo można obciążyć tę partię mocniej.';
    case RecoveryStatus.recovered:
      return 'Zregenerowane — partia gotowa do pełnego treningu.';
  }
}

/// Zbiorcze obciążenie zestawu ćwiczeń albo całego dnia:
/// łączna objętość kg i średnie RPE (tylko z wpisów, które mają RPE).
class TrainingLoadStats {
  double volumeKg = 0;
  int _rpeSum = 0;
  int _rpeCount = 0;
  int entryCount = 0;

  void addLog(WorkoutLog log) {
    entryCount++;
    final logVolume = log.volume;
    if (logVolume > 0 && logVolume.isFinite) volumeKg += logVolume;
    if (log.rpe > 0) {
      _rpeSum += log.rpe.clamp(1, 10);
      _rpeCount++;
    }
  }

  /// Średnie RPE (0 = brak danych RPE w zestawie/dniu).
  double get averageRpe => _rpeCount == 0 ? 0 : _rpeSum / _rpeCount;
}

/// Korekta RPE: średnie RPE 5–6 = lekki/średni bodziec (krótsza regeneracja),
/// 7–8 = solidny trening (punkt odniesienia), 9–10 = bardzo ciężki (dłuższa).
double _rpeAdjustment(double averageRpe) {
  if (averageRpe <= 0) return 1.0; // brak danych RPE — bez korekty
  if (averageRpe <= 5.5) return 0.92;
  if (averageRpe <= 6.5) return 0.97;
  if (averageRpe <= 7.5) return 1.0;
  if (averageRpe <= 8.5) return 1.07;
  return 1.14;
}

/// Korekta objętości: tonaż (kg) względem masy ciała. Mała objętość skraca
/// okno regeneracji, bardzo duża je wydłuża. Progi w wielokrotnościach masy
/// ciała, żeby 3600 kg znaczyło co innego dla 60 kg i 110 kg użytkownika.
double _volumeAdjustment(
  double volumeKg,
  double bodyWeightKg, {
  required double lightBelow,
  required double heavyAbove,
  required double veryHeavyAbove,
}) {
  if (volumeKg <= 0) return 1.0; // brak obciążenia (np. dzień mobilności)
  final bodyWeight = bodyWeightKg <= 0 ? 80.0 : bodyWeightKg;
  final relative = volumeKg / bodyWeight;
  if (relative < lightBelow) return 0.95;
  if (relative < heavyAbove) return 1.0;
  if (relative < veryHeavyAbove) return 1.06;
  return 1.12;
}

/// Korekta okna regeneracji z JEDNEGO zestawu ćwiczeń (sesji):
/// średnie RPE zestawu × objętość kg zestawu. Zakres 0.85–1.25.
double sessionLoadAdjustment({
  required double averageRpe,
  required double volumeKg,
  required double bodyWeightKg,
}) {
  final raw = _rpeAdjustment(averageRpe) *
      _volumeAdjustment(
        volumeKg,
        bodyWeightKg,
        lightBelow: 15,
        heavyAbove: 45,
        veryHeavyAbove: 80,
      );
  return raw.clamp(0.85, 1.25);
}

/// Korekta „końca dnia": średnie RPE dnia × łączna objętość kg dnia.
/// Tłumiona (×0.6 od pełnej krzywej), bo uzupełnia korektę zestawu, a przy
/// jednym zestawie dziennie dane pokrywają się z sesją — bez tłumienia ten
/// sam trening liczyłby się podwójnie. Zakres 0.9–1.18.
double dayLoadAdjustment({
  required double averageRpe,
  required double volumeKg,
  required double bodyWeightKg,
}) {
  final raw = (_rpeAdjustment(averageRpe) *
          _volumeAdjustment(
            volumeKg,
            bodyWeightKg,
            lightBelow: 20,
            heavyAbove: 60,
            veryHeavyAbove: 110,
          ))
      .clamp(0.85, 1.3);
  return (1.0 + (raw - 1.0) * 0.6).clamp(0.9, 1.18);
}

/// Pojedynczy bodziec treningowy w partii (jeden wpis treningowy × rola partii).
class _StimulusEvent {
  _StimulusEvent({
    required this.date,
    required this.stimulus,
    required this.recoveryHours,
    required this.sessionId,
    required this.exerciseName,
  });

  final DateTime date;

  /// Punkty intensywności (1.0 ≈ solidne 3×10 na tę partię jako główną).
  final double stimulus;

  /// Po ilu godzinach bodziec w pełni wygasa.
  final double recoveryHours;
  final String sessionId;
  final String exerciseName;

  /// Ile bodźca jeszcze zostało (1.0 tuż po treningu → 0.0 po [recoveryHours]).
  double remainingFraction(DateTime now) {
    final hoursSince = now.difference(date).inMinutes / 60.0;
    if (hoursSince <= 0) return 1.0;
    if (recoveryHours <= 0) return 0.0;
    return (1.0 - hoursSince / recoveryHours).clamp(0.0, 1.0);
  }

  DateTime get fullyRecoveredAt =>
      date.add(Duration(minutes: (recoveryHours * 60).round()));
}

/// Rodzaj ćwiczenia na potrzeby wagi bodźca (siłowe męczą partię najmocniej,
/// mobilność/rozgrzewka prawie wcale).
double _exerciseTypeFactor(Exercise exercise, WorkoutLog log) {
  final text = '${exercise.category} ${exercise.name}'.toLowerCase();
  if (text.contains('rozgrzew') ||
      text.contains('warmup') ||
      text.contains('warm-up')) return 0.25;
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
  // Ćwiczenia czasowe bez obciążenia (plank itp.) — nieco lżejszy bodziec.
  if (log.weightKg <= 0 &&
      (log.durationSec > 0 || exercise.defaultDurationSec > 0)) return 0.8;
  return 1.0;
}

/// Liczy stan regeneracji partii na podstawie historii treningów.
///
/// Każdy wpis to osobny, wygasający bodziec — kilka lekkich treningów nie
/// blokuje partii na maksymalne okno, a bardzo ciężka sesja realnie wydłuża
/// regenerację. Ćwiczenia pominięte nie trafiają do [logs] (zapisywane są
/// tylko wykonane). Ćwiczenia bez przypisanych partii są ignorowane.
class RecoveryCalculator {
  const RecoveryCalculator({
    this.analysisWindow = const Duration(hours: 96),
    this.profile = const RecoveryProfile(),
  });

  /// Okno analizy — starsze treningi traktujemy jako w pełni zregenerowane.
  final Duration analysisWindow;

  /// Profil użytkownika (wiek, poziom, płeć, masa ciała…).
  final RecoveryProfile profile;

  /// Maksymalne okno regeneracji pojedynczego bodźca.
  static const double maxRecoveryHours = 96;

  /// Minimalne okno regeneracji pojedynczego bodźca.
  static const double minRecoveryHours = 8;

  /// Skala zamiany punktów bodźca na % zmęczenia tuż po treningu.
  static const double _fatigueScale = 55;

  /// Partie obciążane przez aktywności cardio. Bieg to NIE tylko kroki:
  /// realnie męczy łydki, uda, pośladki i zginacze bioder.
  static Map<BodyMuscle, double> _cardioMuscleWeights(
      TrainerActivityType type) {
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

  Map<BodyMuscle, MuscleRecoveryState> compute({
    required List<WorkoutLog> logs,
    required Exercise Function(String id) resolveExercise,
    List<TrainerActivityEntry> activities = const [],
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(analysisWindow);
    final events = <BodyMuscle, List<_StimulusEvent>>{};

    // Przebieg wstępny: obciążenie per zestaw (sesja) i per dzień —
    // średnie RPE + łączna objętość kg. Wpisy bez sessionId (np. ręczne)
    // grupują się w jeden "zestaw dnia", żeby nic nie wypadło z analizy.
    String dayKeyOf(DateTime date) => '${date.year}-${date.month}-${date.day}';

    // Moment bodźca to REALNA godzina wysiłku ([WorkoutSession.effectivePerformedAt]),
    // a nie północ dnia treningowego z [WorkoutLog.date]. Liczenie od północy
    // wygaszało bodziec o tyle godzin, ile minęło od niej do treningu — sesja
    // o 21:00 wyglądała tuż po zakończeniu na sprzed 21 godzin i mapa mięśni
    // pokazywała „zregenerowane" mimo świeżo wykonanej pracy.
    // Znaczniki z przyszłości (zła strefa/zegar) cofamy do [reference], żeby
    // taki wpis nie wypadł z analizy.
    DateTime stimulusAt(WorkoutLog log) {
      final moment = log.effectivePerformedAt;
      return moment.isAfter(reference) ? reference : moment;
    }

    final sessionStats = <String, TrainingLoadStats>{};
    final dayStats = <String, TrainingLoadStats>{};
    for (final log in logs) {
      if (stimulusAt(log).isBefore(cutoff)) continue;
      final sessionKey = log.sessionId.trim().isNotEmpty
          ? log.sessionId
          : 'solo_${dayKeyOf(log.date)}';
      sessionStats.putIfAbsent(sessionKey, TrainingLoadStats.new).addLog(log);
      dayStats
          .putIfAbsent(dayKeyOf(log.date), TrainingLoadStats.new)
          .addLog(log);
    }

    for (final log in logs) {
      if (stimulusAt(log).isBefore(cutoff)) continue;
      final exercise = resolveExercise(log.exerciseId);
      final impacts = exercise.effectiveMuscleImpacts;
      if (impacts.isEmpty) continue;
      final baseStimulus = _logStimulus(log, exercise);

      // Korekta okna regeneracji z realnego obciążenia: zestaw + dzień.
      final sessionKey = log.sessionId.trim().isNotEmpty
          ? log.sessionId
          : 'solo_${dayKeyOf(log.date)}';
      final session = sessionStats[sessionKey];
      final day = dayStats[dayKeyOf(log.date)];
      final sessionFactor = session == null
          ? 1.0
          : sessionLoadAdjustment(
              averageRpe: session.averageRpe,
              volumeKg: session.volumeKg,
              bodyWeightKg: profile.bodyWeightKg,
            );
      final dayFactor = day == null
          ? 1.0
          : dayLoadAdjustment(
              averageRpe: day.averageRpe,
              volumeKg: day.volumeKg,
              bodyWeightKg: profile.bodyWeightKg,
            );

      for (final impact in impacts) {
        final stimulus = baseStimulus * impact.effectiveWeight;
        if (stimulus <= 0.01) continue;
        final intensity = TrainingIntensity.forStimulus(stimulus);
        final hours = (baseRecoveryHoursForMuscle(impact.muscleGroup) *
                intensity.recoveryMultiplier *
                profile.recoveryFactor *
                sessionFactor *
                dayFactor)
            .clamp(minRecoveryHours, maxRecoveryHours);
        events.putIfAbsent(impact.muscleGroup, () => []).add(_StimulusEvent(
              date: stimulusAt(log),
              stimulus: stimulus,
              recoveryHours: hours,
              sessionId: log.sessionId,
              exerciseName: exercise.name,
            ));
      }
    }

    // Aktywności cardio (bieg/chód/rower z zegarka albo ręczne) — osobne
    // bodźce zależne od czasu, intensywności (kcal/min, tętno) i typu.
    // Bieg 11 km z wysokim tętnem realnie obciąża nogi i wydłuża regenerację.
    for (final entry in activities) {
      if (entry.date.isBefore(cutoff) || entry.date.isAfter(reference))
        continue;
      final weights = _cardioMuscleWeights(entry.type);
      if (weights.isEmpty) continue;
      final minutes = entry.durationMin > 0
          ? entry.durationMin
          : entry.estimatedKcal > 0
              ? (entry.estimatedKcal / 9).round()
              : 0;
      if (minutes <= 0) continue;
      final durationFactor = (minutes / 45.0).clamp(0.2, 2.5);

      // Intensywność: kcal na minutę względem masy ciała ORAZ tętno względem
      // maksymalnego (220 − wiek) — wygrywa mocniejszy sygnał.
      final bodyWeight =
          profile.bodyWeightKg <= 0 ? 80.0 : profile.bodyWeightKg;
      var intensity = 1.0;
      if (entry.estimatedKcal > 0) {
        final kcalPerMin = entry.estimatedKcal / minutes;
        intensity = (kcalPerMin / (bodyWeight * 0.12)).clamp(0.5, 1.8);
      }
      if (entry.avgHeartRate > 0) {
        final maxHr = (220 - profile.age).clamp(120, 210);
        final hrFactor = (0.4 + entry.avgHeartRate / maxHr).clamp(0.5, 1.8);
        if (hrFactor > intensity) intensity = hrFactor.toDouble();
      }
      final baseStimulus = (durationFactor * intensity).clamp(0.1, 5.0);

      weights.forEach((muscle, roleWeight) {
        final stimulus = baseStimulus * roleWeight;
        if (stimulus <= 0.05) return;
        final intensityClass = TrainingIntensity.forStimulus(stimulus);
        final hours = (baseRecoveryHoursForMuscle(muscle) *
                intensityClass.recoveryMultiplier *
                profile.recoveryFactor)
            .clamp(minRecoveryHours, maxRecoveryHours);
        events.putIfAbsent(muscle, () => []).add(_StimulusEvent(
              date: entry.effectiveStart,
              stimulus: stimulus,
              recoveryHours: hours,
              sessionId: entry.id,
              exerciseName: entry.type.label,
            ));
      });
    }

    final result = <BodyMuscle, MuscleRecoveryState>{};
    events.forEach((muscle, muscleEvents) {
      final state = _stateFor(muscle, muscleEvents, reference);
      if (state != null) result[muscle] = state;
    });
    return result;
  }

  /// Sekundy REALNEJ PRACY wpisu (bez przerw między seriami).
  ///
  /// `WorkoutLog.durationSec` to czas przypisany ćwiczeniu razem z przerwami —
  /// użyty wprost zawyżał objętość ćwiczeń czasowych mniej więcej dwukrotnie
  /// (3 × 40 s pracy + 2 × 60 s przerwy liczyło się jak 240 s pracy).
  static int _workSecondsOf(WorkoutLog log) {
    if (log.workoutSets.isEmpty) return log.durationSec;
    var seconds = 0;
    for (final set in log.workoutSets) {
      if (!set.isCompleted || set.isFailure) continue;
      final perSet = set.activeSeconds > 0 ? set.activeSeconds : set.durationSec;
      if (perSet > 0) seconds += perSet;
    }
    return seconds > 0 ? seconds : log.durationSec;
  }

  /// Punkty intensywności wpisu (przed przemnożeniem przez rolę partii).
  double _logStimulus(WorkoutLog log, Exercise exercise) {
    final sets = log.sets <= 0 ? 1 : log.sets.clamp(1, 12);
    final reps = log.reps <= 0 ? 8 : log.reps.clamp(1, 50);

    // Objętość względem punktu odniesienia 3×10.
    var volumeFactor = (sets * reps) / 30.0;

    // Ćwiczenia czasowe: czas PRACY zamiast powtórzeń (odniesienie 3×40 s).
    // O tym, czy ćwiczenie jest czasowe, decyduje jego typ wpisu — nie to, że
    // akurat nie zapisano ciężaru (obciążona deska też jest czasowa).
    final entryType = exercise.entryType;
    if (entryType.showsDuration && !entryType.showsReps) {
      final work = _workSecondsOf(log);
      if (work > 0) volumeFactor = work / 120.0;
    }
    volumeFactor = volumeFactor.clamp(0.15, 3.0);

    // Ciężar względem masy ciała (0 kg → 0.6, ciężar = masa ciała → 1.8).
    final bodyWeight = profile.bodyWeightKg <= 0 ? 80.0 : profile.bodyWeightKg;
    final relativeLoad = (log.weightKg / bodyWeight).clamp(0.0, 2.0);
    final weightFactor = 0.6 + relativeLoad * 1.2;

    // Subiektywna intensywność (RPE 7 ≈ 1.12).
    final rpeFactor =
        log.rpe > 0 ? (0.7 + (log.rpe.clamp(1, 10)) / 10.0 * 0.6) : 1.0;

    final typeFactor = _exerciseTypeFactor(exercise, log);

    return (volumeFactor * weightFactor * rpeFactor * typeFactor)
        .clamp(0.05, 6.0);
  }

  MuscleRecoveryState? _stateFor(
      BodyMuscle muscle, List<_StimulusEvent> events, DateTime now) {
    var fatigue = 0.0;
    var totalStimulus = 0.0;
    _StimulusEvent? latest;
    DateTime? fullRecoveryAt;
    final exerciseNames = <String>{};

    for (final event in events) {
      final remaining = event.remainingFraction(now);
      totalStimulus += event.stimulus;
      exerciseNames.add(event.exerciseName);
      if (latest == null || !event.date.isBefore(latest.date)) latest = event;
      if (remaining <= 0) continue;
      fatigue += event.stimulus * _fatigueScale * remaining;
      final eventEnd = event.fullyRecoveredAt;
      if (fullRecoveryAt == null || eventEnd.isAfter(fullRecoveryAt))
        fullRecoveryAt = eventEnd;
    }
    if (latest == null) return null;

    fatigue = fatigue.clamp(0.0, 100.0);
    final recoveryPercent = 100.0 - fatigue;
    final remainingHours = fullRecoveryAt == null
        ? 0.0
        : (fullRecoveryAt.difference(now).inMinutes / 60.0).clamp(0.0, 1000.0);
    final intensity = TrainingIntensity.forStimulus(latest.stimulus);

    return MuscleRecoveryState(
      muscleGroup: muscle,
      recoveryPercent: recoveryPercent,
      fatiguePercent: fatigue,
      lastTrainedAt: latest.date,
      estimatedFullRecoveryAt: fullRecoveryAt ?? latest.fullyRecoveredAt,
      estimatedHoursRemaining: remainingHours.round(),
      lastWorkoutId: latest.sessionId,
      lastExerciseNames: exerciseNames.toList(),
      loadScore: totalStimulus,
      status: recoveryStatusForPercent(recoveryPercent),
      intensityLabel: intensity.label,
    );
  }
}
