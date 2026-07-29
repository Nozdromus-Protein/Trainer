/// REALNE TEMPO treningu i ostrożna progresja po zestawie (czysty Dart).
///
/// PROBLEM, KTÓRY TO ROZWIĄZUJE: aplikacja liczyła czas zestawu z planu
/// („serie × przerwa + powtórzenia × 3 s"), więc kto skraca odpoczynek i robi
/// serie szybciej, dostawał prognozę oderwaną od rzeczywistości. Co gorsza,
/// „poszło szybciej" bywało czytane jako „było lekko" i kończyło się dużym
/// dołożeniem ciężaru.
///
/// Tutaj rozdzielamy dwie rzeczy:
///  1. TEMPO ([SessionPace]) — ile użytkownik naprawdę odpoczywa i jak szybko
///     wykonuje serie względem planu. Służy do liczenia czasu i gęstości pracy.
///  2. DOWÓD na progresję ([cautiousProgressionStep]) — krótszy odpoczynek albo
///     ręczne dołożenie ciężaru NIE jest dowodem na to, że można dołożyć jeszcze
///     raz tyle samo. Takie sygnały TŁUMIĄ krok progresji zamiast go podbijać.
library;

import 'dart:math' as math;

import '../domain/session_prescription.dart';
import '../domain/workout_set.dart';

// ============================================================================
// Tempo: odpoczynek i czas pracy względem planu
// ============================================================================

/// Jedna zmierzona seria: co plan zakładał i co realnie się wydarzyło.
class SetTempoSample {
  const SetTempoSample({
    this.plannedRestSec = 0,
    this.actualRestSec = 0,
    this.plannedWorkSec = 0,
    this.actualWorkSec = 0,
    this.restVerified = true,
    this.workVerified = true,
  });

  final int plannedRestSec;
  final int actualRestSec;
  final int plannedWorkSec;
  final int actualWorkSec;

  /// Czy pomiar odpoczynku pochodzi z realnego zdarzenia (koniec/pominięcie
  /// timera), a nie z odtworzenia luki między zapisami serii.
  final bool restVerified;
  final bool workVerified;

  /// Zero sekund przerwy to POPRAWNY pomiar (przerwa pominięta od razu),
  /// więc próbkę uznajemy też wtedy, gdy pomiar jest potwierdzony zdarzeniem.
  bool get hasRest =>
      plannedRestSec > 0 && (actualRestSec > 0 || restVerified);
  bool get hasWork => plannedWorkSec > 0 && actualWorkSec > 0;

  double get restRatio => hasRest ? actualRestSec / plannedRestSec : 1.0;
  double get workRatio => hasWork ? actualWorkSec / plannedWorkSec : 1.0;

  /// Sample z realnych danych serii. `previousEndedAt` to koniec poprzedniej
  /// serii — bez niego nie da się odtworzyć odpoczynku.
  factory SetTempoSample.fromSet(WorkoutSet set, {required int typicalWorkSec}) =>
      SetTempoSample(
        plannedRestSec: set.plannedRestSec,
        actualRestSec: set.restBeforeSec,
        plannedWorkSec: typicalWorkSec,
        actualWorkSec: set.activeSeconds,
        restVerified: set.isRestVerified,
        workVerified: set.isTimeVerified,
      );
}

/// Uśrednione tempo użytkownika w tej sesji / w historii ćwiczenia.
class SessionPace {
  const SessionPace({
    this.restRatio = 1.0,
    this.workRatio = 1.0,
    this.restSamples = 0,
    this.workSamples = 0,
    this.verifiedSamples = 0,
  });

  /// Ile z planowanej przerwy użytkownik realnie wykorzystuje (0.6 = 60%).
  final double restRatio;

  /// Ile z szacowanego czasu serii realnie zajmuje praca (0.8 = szybciej).
  final double workRatio;

  final int restSamples;
  final int workSamples;

  /// Ile próbek pochodzi z pewnego pomiaru (a nie z odtworzenia luki).
  final int verifiedSamples;

  static const SessionPace neutral = SessionPace();

  /// Dwie próbki to minimum, żeby nie wyciągać wniosków z jednego zdarzenia.
  bool get hasRestData => restSamples >= 2;
  bool get hasWorkData => workSamples >= 2;
  bool get hasData => hasRestData || hasWorkData;

  bool get shortensRest => hasRestData && restRatio <= 0.85;
  bool get extendsRest => hasRestData && restRatio >= 1.2;
  bool get fasterSets => hasWorkData && workRatio <= 0.85;
  bool get slowerSets => hasWorkData && workRatio >= 1.25;

  int get restPercent => (restRatio * 100).round();
  int get workPercent => (workRatio * 100).round();

  /// Czytelne podsumowanie tempa (puste, gdy brak danych).
  String get summary {
    final parts = <String>[];
    if (shortensRest) {
      parts.add('odpoczywasz krócej niż plan ($restPercent% przerwy)');
    } else if (extendsRest) {
      parts.add('odpoczywasz dłużej niż plan ($restPercent% przerwy)');
    }
    if (fasterSets) {
      parts.add('serie idą szybciej niż zakładane ($workPercent% czasu)');
    } else if (slowerSets) {
      parts.add('serie trwają dłużej niż zakładane ($workPercent% czasu)');
    }
    return parts.isEmpty ? '' : parts.join(', ');
  }
}

/// Liczy tempo z próbek. Używa ŚREDNIEJ PRZYCIĘTEJ (odrzuca skrajną wartość
/// przy ≥4 próbkach), żeby jedna pomyłka (zapomniany timer, telefon) nie
/// przestawiła całego modelu czasu.
SessionPace measurePace(Iterable<SetTempoSample> samples) {
  final rest = <double>[];
  final work = <double>[];
  var verified = 0;
  for (final sample in samples) {
    if (sample.hasRest) {
      rest.add(sample.restRatio.clamp(0.2, 3.0).toDouble());
      if (sample.restVerified) verified++;
    }
    if (sample.hasWork) {
      work.add(sample.workRatio.clamp(0.2, 4.0).toDouble());
    }
  }
  return SessionPace(
    restRatio: _trimmedMean(rest, fallback: 1.0),
    workRatio: _trimmedMean(work, fallback: 1.0),
    restSamples: rest.length,
    workSamples: work.length,
    verifiedSamples: verified,
  );
}

double _trimmedMean(List<double> values, {required double fallback}) {
  if (values.isEmpty) return fallback;
  if (values.length < 4) {
    return values.reduce((a, b) => a + b) / values.length;
  }
  final sorted = [...values]..sort();
  final trimmed = sorted.sublist(1, sorted.length - 1);
  return trimmed.reduce((a, b) => a + b) / trimmed.length;
}

/// Szacowany czas JEDNEGO ćwiczenia (praca + przerwy) w sekundach, z realnym
/// tempem użytkownika i korektą intensywności.
///
/// [intensityFactor] to mnożnik ciężaru roboczego z gałki intensywności / fazy
/// cyklu (1.0 = standard). Cięższa praca to dłuższe serie i dłuższe przerwy —
/// bez tego prognoza czasu ignorowała podkręcenie zestawu.
int estimateExerciseSeconds({
  required int sets,
  required int reps,
  required int durationSec,
  required int restSeconds,
  SessionPace pace = SessionPace.neutral,
  double intensityFactor = 1.0,
}) {
  final safeSets = sets < 1 ? 1 : sets;
  final intensity = intensityFactor.clamp(0.5, 1.8).toDouble();
  // Cięższa seria trwa dłużej, ale nie proporcjonalnie do ciężaru — tempo ruchu
  // zwalnia umiarkowanie (30% wpływu), przerwa reaguje mocniej (60%).
  final workFactor = pace.hasWorkData ? pace.workRatio : 1.0;
  final restFactor = pace.hasRestData ? pace.restRatio : 1.0;
  final basePerSet = durationSec > 0
      ? durationSec.toDouble()
      : (reps > 0 ? reps : 10) * 3.5;
  final work = basePerSet * workFactor * (1 + (intensity - 1) * 0.3);
  final rest = restSeconds * restFactor * (1 + (intensity - 1) * 0.6);
  // Ostatnia seria ćwiczenia nie potrzebuje pełnej przerwy „w środku" —
  // liczy się jako przejście do kolejnego ruchu.
  final totalRest = rest * (safeSets - 1) + rest * 0.5;
  return math.max(1, (work * safeSets + totalRest).round());
}

// ============================================================================
// Ręczne działania użytkownika w trakcie zestawu
// ============================================================================

/// Co użytkownik zmienił RĘCZNIE względem recepty sesji.
class ManualSetChanges {
  const ManualSetChanges({
    this.weightDeltaKg = 0,
    this.repDelta = 0,
    this.setDelta = 0,
    this.changedSetCount = 0,
  });

  /// Największa dodatnia (albo ujemna) różnica ciężaru vs rekomendacja.
  final double weightDeltaKg;

  /// Różnica powtórzeń w najlepszej serii vs rekomendacja.
  final int repDelta;

  /// Różnica liczby wykonanych serii vs zaplanowana.
  final int setDelta;

  /// Ile serii różniło się od recepty.
  final int changedSetCount;

  static const ManualSetChanges none = ManualSetChanges();

  bool get addedLoad => weightDeltaKg > 0.01;
  bool get reducedLoad => weightDeltaKg < -0.01;
  bool get addedVolume => repDelta > 0 || setDelta > 0;
  bool get any =>
      addedLoad || reducedLoad || repDelta != 0 || setDelta != 0;

  /// Krótkie etykiety do karty sugestii („+2,5 kg", „+1 seria").
  List<String> get labels => [
        if (weightDeltaKg.abs() > 0.01)
          '${weightDeltaKg > 0 ? '+' : '−'}${_fmt(weightDeltaKg.abs())} kg',
        if (repDelta != 0) '${repDelta > 0 ? '+' : '−'}${repDelta.abs()} powt.',
        if (setDelta != 0)
          '${setDelta > 0 ? '+' : '−'}${setDelta.abs()} ${setDelta.abs() == 1 ? 'seria' : 'serie'}',
      ];
}

/// Wykrywa ręczne odstępstwa od recepty na podstawie zapisanych serii.
ManualSetChanges detectManualChanges({
  required Prescription planned,
  required List<WorkoutSet> completed,
  bool showsWeight = true,
  bool showsReps = true,
}) {
  final counted = [for (final set in completed) if (set.countsForProgress) set];
  if (counted.isEmpty) return ManualSetChanges.none;

  double weightDelta = 0;
  int repDelta = 0;
  var changed = 0;
  for (final set in counted) {
    var differs = false;
    if (showsWeight && planned.weightKg > 0 && set.weightKg > 0) {
      final delta = set.weightKg - planned.weightKg;
      if (delta.abs() > 0.01) {
        differs = true;
        if (delta.abs() > weightDelta.abs()) weightDelta = delta;
      }
    }
    if (showsReps && planned.reps > 0 && set.repetitions > 0) {
      final delta = set.repetitions - planned.reps;
      if (delta != 0) {
        differs = true;
        if (delta.abs() > repDelta.abs()) repDelta = delta;
      }
    }
    if (differs) changed++;
  }
  final setDelta = planned.sets > 0 ? counted.length - planned.sets : 0;
  return ManualSetChanges(
    weightDeltaKg: weightDelta,
    repDelta: repDelta,
    setDelta: setDelta,
    changedSetCount: changed,
  );
}

// ============================================================================
// Ostrożna progresja po zestawie
// ============================================================================

/// Dowód z jednego ćwiczenia w zakończonym zestawie.
class ExerciseSessionEvidence {
  const ExerciseSessionEvidence({
    required this.exerciseId,
    required this.exerciseName,
    required this.plannedSets,
    required this.completedSets,
    required this.allSetsCompleted,
    this.pace = SessionPace.neutral,
    this.manual = ManualSetChanges.none,
    this.avgRpe = 0,
    this.rpeReliable = false,
    this.confidence = 1.0,
    this.successStreak = 0,
  });

  final String exerciseId;
  final String exerciseName;
  final int plannedSets;
  final int completedSets;
  final bool allSetsCompleted;
  final SessionPace pace;
  final ManualSetChanges manual;
  final double avgRpe;
  final bool rpeReliable;

  /// Pewność analizy (0–1) — z szacowania wysiłku.
  final double confidence;

  /// Ile udanych sesji tego ćwiczenia z rzędu (razem z tą).
  final int successStreak;
}

/// Ostrożny krok progresji: ile z pełnego kroku naprawdę stosujemy i dlaczego.
class CautiousProgressionStep {
  const CautiousProgressionStep({
    required this.weightDeltaKg,
    required this.repDelta,
    required this.durationDeltaSec,
    required this.headline,
    required this.reasons,
    required this.appliedFraction,
    this.restAdviceSec = 0,
  });

  final double weightDeltaKg;
  final int repDelta;
  final int durationDeltaSec;

  /// Zdanie do kafelka („Następnym razem +1,25 kg (pół kroku)").
  final String headline;

  /// Co złożyło się na decyzję — dokładnie to, co pokazuje karta sugestii.
  final List<String> reasons;

  /// Jaka część pełnego kroku została zastosowana (1.0 = pełny).
  final double appliedFraction;

  /// Sugerowana korekta przerwy (s); >0 = wróć do dłuższej przerwy.
  final int restAdviceSec;

  static const CautiousProgressionStep hold = CautiousProgressionStep(
    weightDeltaKg: 0,
    repDelta: 0,
    durationDeltaSec: 0,
    headline: 'Utrzymujemy parametry',
    reasons: [],
    appliedFraction: 0,
  );

  bool get changesAnything =>
      weightDeltaKg.abs() > 0.01 || repDelta != 0 || durationDeltaSec != 0;

  /// Czy krok został świadomie stłumiony (nie jest pełny).
  bool get isDampened => appliedFraction > 0 && appliedFraction < 0.99;
}

/// Tłumi pełny krok progresji o dowody, które NIE są dowodem większej siły.
///
/// Reguły (spec: „inteligentnie i ostrożnie, z rozsądkiem"):
///  * ręczne dołożenie ciężaru w tej sesji jest ZALICZANE na poczet kroku —
///    nie dokładamy drugi raz tego samego,
///  * krótszy odpoczynek zwiększa gęstość pracy, a nie zdolność do ciężaru —
///    najpierw wróć do przerwy z planu, dopiero potem dokładaj kilogramy,
///  * szybsze serie same w sobie nie są dowodem — podbijają krok tylko razem
///    z pełnym ukończeniem i wiarygodnie niskim wysiłkiem,
///  * jedna udana sesja to pół kroku; niska pewność analizy też połowa.
CautiousProgressionStep cautiousProgressionStep({
  required ExerciseSessionEvidence evidence,
  required double fullStepKg,
  int fullRepStep = 1,
  int fullDurationStepSec = 5,
  bool preferWeight = true,
  double roundToKg = 1.25,
}) {
  final reasons = <String>[];
  if (!evidence.allSetsCompleted) {
    return CautiousProgressionStep(
      weightDeltaKg: 0,
      repDelta: 0,
      durationDeltaSec: 0,
      headline: 'Bez dokładania — najpierw domknij wszystkie serie',
      reasons: const [
        'Nie wszystkie serie zostały ukończone zgodnie z planem.',
      ],
      appliedFraction: 0,
    );
  }

  var fraction = 1.0;

  if (evidence.successStreak < 2) {
    fraction *= 0.5;
    reasons.add(
        'To dopiero pierwsza taka sesja z rzędu — dokładamy pół kroku, nie cały.');
  }
  if (evidence.confidence < 0.6) {
    fraction *= 0.5;
    reasons.add(
        'Pewność analizy tej sesji jest niska (${(evidence.confidence * 100).round()}%) — krok mniejszy.');
  }
  if (evidence.rpeReliable && evidence.avgRpe >= 8.5) {
    fraction *= 0.4;
    reasons.add(
        'Wysiłek był wysoki (RPE ${evidence.avgRpe.toStringAsFixed(1)}) — to nie moment na duży skok.');
  } else if (evidence.rpeReliable && evidence.avgRpe <= 6.0) {
    fraction *= 1.25;
    reasons.add(
        'Wysiłek był niski (RPE ${evidence.avgRpe.toStringAsFixed(1)}) — jest zapas.');
  }

  var restAdvice = 0;
  if (evidence.pace.shortensRest) {
    fraction *= 0.5;
    restAdvice = 1;
    reasons.add(
        'Odpoczywasz krócej niż plan (${evidence.pace.restPercent}% przerwy) — '
        'to podnosi gęstość pracy, a nie ciężar. Najpierw wróć do pełnej przerwy.');
  } else if (evidence.pace.extendsRest) {
    fraction *= 0.75;
    reasons.add(
        'Przerwy były dłuższe niż plan (${evidence.pace.restPercent}%) — łatwiej '
        'domknąć serie, więc krok trzymamy mniejszy.');
  }

  if (evidence.pace.fasterSets && evidence.pace.hasWorkData) {
    if (evidence.pace.shortensRest) {
      reasons.add(
          'Szybsze serie przy skróconej przerwie liczymy jako tempo, nie jako zapas siły.');
    } else {
      fraction *= 1.15;
      reasons.add(
          'Serie szły szybciej niż zakładany czas (${evidence.pace.workPercent}%) — technika wygląda pewnie.');
    }
  } else if (evidence.pace.slowerSets) {
    fraction *= 0.7;
    reasons.add(
        'Serie trwały dłużej niż zakładano (${evidence.pace.workPercent}%) — ruch zwalnia pod obciążeniem.');
  }

  // Ręczne dołożenie ciężaru: użytkownik już wykonał część progresji.
  final manual = evidence.manual;
  var credit = 0.0;
  if (manual.addedLoad) {
    credit = manual.weightDeltaKg;
    fraction *= 0.5;
    reasons.add(
        'Ciężar dołożyłeś już ręcznie (+${_fmt(manual.weightDeltaKg)} kg) — '
        'ta zmiana jest zaliczona i nie dokładamy jej drugi raz.');
  } else if (manual.reducedLoad) {
    fraction = 0;
    reasons.add(
        'Ciężar został ręcznie zmniejszony (${_fmt(manual.weightDeltaKg)} kg) — '
        'utrwalamy nowy poziom zamiast dokładać.');
  }
  if (manual.addedVolume) {
    fraction *= 0.6;
    reasons.add(
        'Objętość podniosłeś już ręcznie (${manual.labels.join(', ')}) — dokładamy ostrożniej.');
  }

  fraction = fraction.clamp(0.0, 1.0).toDouble();

  if (preferWeight && fullStepKg > 0) {
    final raw = fullStepKg * fraction - credit;
    final step = _roundStep(raw, roundToKg);
    if (step <= 0) {
      return CautiousProgressionStep(
        weightDeltaKg: 0,
        repDelta: 0,
        durationDeltaSec: 0,
        headline: credit > 0
            ? 'Zostajemy przy ciężarze z tej sesji'
            : 'Utrzymujemy ciężar',
        reasons: reasons,
        appliedFraction: fraction,
        restAdviceSec: restAdvice,
      );
    }
    return CautiousProgressionStep(
      weightDeltaKg: step,
      repDelta: 0,
      durationDeltaSec: 0,
      headline: fraction < 0.99
          ? 'Następnym razem +${_fmt(step)} kg (ostrożny krok)'
          : 'Następnym razem +${_fmt(step)} kg',
      reasons: reasons,
      appliedFraction: fraction,
      restAdviceSec: restAdvice,
    );
  }

  if (fullDurationStepSec > 0 && fullRepStep <= 0) {
    final seconds = (fullDurationStepSec * fraction).round();
    return CautiousProgressionStep(
      weightDeltaKg: 0,
      repDelta: 0,
      durationDeltaSec: seconds,
      headline: seconds > 0
          ? 'Następnym razem +$seconds s'
          : 'Utrzymujemy czas serii',
      reasons: reasons,
      appliedFraction: fraction,
      restAdviceSec: restAdvice,
    );
  }

  final reps = (fullRepStep * fraction).round();
  return CautiousProgressionStep(
    weightDeltaKg: 0,
    repDelta: reps,
    durationDeltaSec: 0,
    headline:
        reps > 0 ? 'Następnym razem +$reps powt.' : 'Utrzymujemy powtórzenia',
    reasons: reasons,
    appliedFraction: fraction,
    restAdviceSec: restAdvice,
  );
}

/// Zaokrągla krok do sensownej wielokrotności talerzy; poniżej połowy kroku
/// zwraca 0 (nie proponujemy „+0,4 kg").
double _roundStep(double raw, double unit) {
  if (raw <= 0 || unit <= 0) return 0;
  final steps = (raw / unit).round();
  if (steps <= 0) return 0;
  return double.parse((steps * unit).toStringAsFixed(2));
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
