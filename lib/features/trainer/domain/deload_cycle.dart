/// Cykliczny deload (odciążenie) — domena.
///
/// Deload to zaplanowany okres zejścia z objętości i intensywności, dający
/// mięśniom odpoczynek. Cykl liczy się periodycznie od [DeloadCycle.anchor]:
/// [DeloadCycle.trainingDays] dni normalnego treningu, potem
/// [DeloadCycle.deloadDays] dni deloadu i tak w kółko. Dzięki temu kalendarz
/// jest przewidywalny na wiele tygodni w przód.
///
/// Deload ADAPTACYJNY (przesuwanie momentu na podstawie zmęczenia) realizuje
/// warstwa aplikacji — gdy sygnały zmęczenia są wysokie, przesuwa [anchor]
/// przez [reanchorDeloadStart], tak by deload zaczął się wcześniej. Sama domena
/// pozostaje czysta, deterministyczna i łatwa do testów.
library;

import 'dart:math' as math;

import 'workout_plan.dart';

/// Intensywność w trakcie deloadu (ułamek zwykłego obciążenia).
const double _deloadIntensity = 0.55;

/// Intensywność zaraz po deloadzie (mocne wejście) i minimalna pod koniec bloku
/// treningowego (schodzimy, ale „nie za mało" aż do kolejnego deloadu).
const double _peakIntensity = 1.0;
const double _floorIntensity = 0.85;

/// Faza cyklu w danym dniu.
enum DeloadPhase { none, training, deload }

/// Konfiguracja cyklicznego deloadu.
class DeloadCycle {
  const DeloadCycle({
    this.enabled = true,
    this.anchor,
    this.trainingDays = 35, // ~5 tygodni
    this.deloadDays = 7, // ~1 tydzień
    this.adaptive = true,
  });

  /// Czy deload jest włączony.
  final bool enabled;

  /// Początek bieżącego bloku TRENINGOWEGO (od niego liczy się cały cykl).
  /// `null` = jeszcze nie zainicjowano (warstwa aplikacji ustawia na „dziś").
  final DateTime? anchor;

  /// Długość bloku treningowego w dniach (domyślnie 35 = 5 tygodni).
  final int trainingDays;

  /// Długość deloadu w dniach (domyślnie 7 = 1 tydzień).
  final int deloadDays;

  /// Czy moment deloadu ma być dostrajany zmęczeniem (adaptacyjnie).
  final bool adaptive;

  int get cycleDays => trainingDays + deloadDays;

  /// Czy cykl jest gotowy do liczenia (włączony, z kotwicą i sensownymi dniami).
  bool get isConfigured =>
      enabled && anchor != null && trainingDays > 0 && deloadDays > 0;

  DeloadCycle copyWith({
    bool? enabled,
    DateTime? anchor,
    int? trainingDays,
    int? deloadDays,
    bool? adaptive,
    bool clearAnchor = false,
  }) {
    return DeloadCycle(
      enabled: enabled ?? this.enabled,
      anchor: clearAnchor ? null : (anchor ?? this.anchor),
      trainingDays: trainingDays ?? this.trainingDays,
      deloadDays: deloadDays ?? this.deloadDays,
      adaptive: adaptive ?? this.adaptive,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (anchor != null) 'anchor': _dateKey(anchor!),
        'trainingDays': trainingDays,
        'deloadDays': deloadDays,
        'adaptive': adaptive,
      };

  factory DeloadCycle.fromJson(Map<String, dynamic> json) => DeloadCycle(
        enabled: json['enabled'] as bool? ?? true,
        anchor: _parseDate(json['anchor']),
        trainingDays: (json['trainingDays'] as num?)?.toInt() ?? 35,
        deloadDays: (json['deloadDays'] as num?)?.toInt() ?? 7,
        adaptive: json['adaptive'] as bool? ?? true,
      );

  /// Cykl domyślny, zakotwiczony na dziś (start bloku treningowego = dziś,
  /// pierwszy deload za [trainingDays] dni).
  factory DeloadCycle.startingToday(
    DateTime today, {
    int trainingDays = 35,
    int deloadDays = 7,
    bool adaptive = true,
  }) =>
      DeloadCycle(
        enabled: true,
        anchor: _dateOnly(today),
        trainingDays: trainingDays,
        deloadDays: deloadDays,
        adaptive: adaptive,
      );
}

/// Status deloadu dla konkretnej daty.
class DeloadStatus {
  const DeloadStatus({
    required this.phase,
    this.daysUntilDeload = 0,
    this.deloadDayNumber = 0,
    this.deloadTotalDays = 0,
    this.windowStart,
    this.windowEnd,
    this.intensityFactor = 1.0,
    this.daysAfterDeload = 0,
    this.previousWindowEnd,
  });

  final DeloadPhase phase;

  /// Faza treningowa: ile dni do STARTU najbliższego deloadu (>= 0).
  final int daysUntilDeload;

  /// Faza deloadu: który to dzień deloadu (1..[deloadTotalDays]).
  final int deloadDayNumber;
  final int deloadTotalDays;

  /// Start i koniec (ostatni dzień) najbliższego/bieżącego okna deloadu.
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Sugerowana intensywność dnia (0.55 w deloadzie; 1.0→0.85 w bloku).
  final double intensityFactor;

  /// Faza treningowa: który to dzień PO zakończeniu poprzedniego deloadu
  /// (1 = pierwszy dzień po deloadzie). 0 = brak wcześniejszego deloadu.
  final int daysAfterDeload;

  /// Ostatni dzień POPRZEDNIEGO okna deloadu (null, gdy jeszcze go nie było).
  final DateTime? previousWindowEnd;

  bool get isDeload => phase == DeloadPhase.deload;
  bool get isTraining => phase == DeloadPhase.training;
  bool get isActive => phase != DeloadPhase.none;

  static const none = DeloadStatus(phase: DeloadPhase.none);
}

/// Status deloadu dla [date] przy konfiguracji [cycle].
DeloadStatus deloadStatusForDate(DeloadCycle cycle, DateTime date) {
  if (!cycle.isConfigured) return DeloadStatus.none;
  final anchor = _dateOnly(cycle.anchor!);
  final day = _dateOnly(date);
  final cycleLen = cycle.cycleDays;
  final elapsed = day.difference(anchor).inDays;

  // Start i-tego okna deloadu = anchor + trainingDays + i * cycleLen.
  DateTime startOf(int k) =>
      anchor.add(Duration(days: cycle.trainingDays + k * cycleLen));

  var i = elapsed < cycle.trainingDays
      ? 0
      : (elapsed - cycle.trainingDays) ~/ cycleLen;
  var start = startOf(i);
  var end = start.add(Duration(days: cycle.deloadDays - 1));
  // Doprecyzuj do okna, którego koniec nie jest przed dniem.
  while (end.isBefore(day)) {
    i++;
    start = startOf(i);
    end = start.add(Duration(days: cycle.deloadDays - 1));
  }

  final inDeload = !day.isBefore(start) && !day.isAfter(end);
  if (inDeload) {
    return DeloadStatus(
      phase: DeloadPhase.deload,
      deloadDayNumber: day.difference(start).inDays + 1,
      deloadTotalDays: cycle.deloadDays,
      windowStart: start,
      windowEnd: end,
      intensityFactor: _deloadIntensity,
    );
  }
  // Poprzednie okno deloadu (do „ile dni po deloadzie").
  DateTime? previousEnd;
  var daysAfter = 0;
  if (i > 0) {
    previousEnd =
        startOf(i - 1).add(Duration(days: cycle.deloadDays - 1));
    daysAfter = day.difference(previousEnd).inDays;
  }
  return DeloadStatus(
    phase: DeloadPhase.training,
    daysUntilDeload: start.difference(day).inDays,
    deloadTotalDays: cycle.deloadDays,
    windowStart: start,
    windowEnd: end,
    intensityFactor: _trainingIntensity(cycle, day),
    daysAfterDeload: daysAfter,
    previousWindowEnd: previousEnd,
  );
}

/// Czytelna etykieta intensywności dla współczynnika z [DeloadStatus].
String intensityLabel(double factor) {
  if (factor <= 0.7) return 'Lekka (deload)';
  if (factor >= 0.97) return 'Bardzo mocna';
  if (factor >= 0.93) return 'Mocna';
  if (factor >= 0.88) return 'Solidna';
  return 'Umiarkowana';
}

/// Pozycja planu pokazana w PODGLĄDZIE dnia przy danej intensywności.
/// W deloadzie stosuje realne odciążenie ([deloadPlanItem]); w bloku
/// treningowym zostawia objętość, a intensywność wyraża procentem ciężaru
/// roboczego (dokładne kilogramy dobiera coach z historii).
PlanItem previewPlanItemAtIntensity(PlanItem item, double factor) {
  if (factor <= 0.7) return deloadPlanItem(item);
  final percent = (factor * 100).round();
  final base = item.note.trim();
  final note = base.isEmpty
      ? '≈$percent% ciężaru roboczego'
      : '$base · ≈$percent% ciężaru roboczego';
  return item.copyWith(
    note: note,
    suggestedWeightKg: item.suggestedWeightKg > 0
        ? item.suggestedWeightKg * factor
        : item.suggestedWeightKg,
  );
}

/// Dzień planu w podglądzie przy danej intensywności.
WorkoutDay previewDayAtIntensity(WorkoutDay day, double factor) => day.copyWith(
      items: [
        for (final item in day.items) previewPlanItemAtIntensity(item, factor),
      ],
    );

/// Czy [date] wypada w deloadzie (do kolorowania kalendarza).
bool isDeloadDay(DeloadCycle cycle, DateTime date) =>
    deloadStatusForDate(cycle, date).isDeload;

/// Sugerowana intensywność treningu w [date]: zaraz po deloadzie mocno
/// (≈1.0), potem stopniowo łagodniej, ale „nie za mało" (podłoga ≈0.85) aż do
/// kolejnego deloadu.
double _trainingIntensity(DeloadCycle cycle, DateTime day) {
  final anchor = _dateOnly(cycle.anchor!);
  final cycleLen = cycle.cycleDays;
  var pos = day.difference(anchor).inDays % cycleLen;
  if (pos < 0) pos += cycleLen;
  if (cycle.trainingDays <= 1) return _peakIntensity;
  final p = (pos / (cycle.trainingDays - 1)).clamp(0.0, 1.0);
  return _peakIntensity - (_peakIntensity - _floorIntensity) * p;
}

/// Przesuwa cykl tak, by DELOAD zaczął się w [start] (deload adaptacyjny —
/// „przyciągnięcie" na podstawie zmęczenia). Kolejne cykle liczą się dalej
/// periodycznie od tego momentu.
DeloadCycle reanchorDeloadStart(DeloadCycle cycle, DateTime start) =>
    cycle.copyWith(
      anchor: _dateOnly(start).subtract(Duration(days: cycle.trainingDays)),
    );

/// Zmniejsza obciążenie pojedynczej pozycji planu pod deload: mniej serii,
/// lżejsze/krótsze serie, dłuższa przerwa oraz czytelna adnotacja.
PlanItem deloadPlanItem(PlanItem item) {
  final sets = math.max(1, (item.sets * 0.6).round());
  final note = _deloadNote(item.note);
  if (item.durationSec > 0) {
    final shorter = (item.durationSec * 0.8).round();
    return item.copyWith(
      sets: sets,
      durationSec: shorter < 10 ? item.durationSec : shorter,
      note: note,
      restSeconds: (item.restSeconds * 1.2).round(),
    );
  }
  // Powtórzenia zostają umiarkowane; ciężar schodzi (adnotacja), objętość maleje.
  final reps =
      item.reps <= 6 ? item.reps : math.max(6, (item.reps * 0.7).round());
  return item.copyWith(
    sets: sets,
    reps: reps,
    note: note,
    restSeconds: (item.restSeconds * 1.25).round(),
  );
}

/// Zmienia cały dzień planu na wariant deloadowy (lżejsze pozycje). Tytuł
/// i charakter dnia zostają — oznaczenie „deload" dodaje warstwa UI.
WorkoutDay deloadWorkoutDay(WorkoutDay day) => day.copyWith(
      items: [for (final item in day.items) deloadPlanItem(item)],
    );

// ── Ręczna korekta intensywności zestawu ─────────────────────────────────────
//
// Nakładka NAD automatyczną rampą cyklu: użytkownik (np. po rozmowie z trenerem)
// może kilka razy podkręcić albo zejść z intensywności. Krok jest umiarkowany,
// żeby kilka kliknięć nie wywróciło programu.

/// Mnożnik ciężaru roboczego dla ręcznej korekty — jeden krok ≈ 5%.
double intensityStepFactor(int steps) => 1 +
    0.05 *
        steps.clamp(-kMaxCombinedIntensitySteps, kMaxCombinedIntensitySteps);

/// Etykieta korekty do UI: „standard", „+1", „−2".
String intensityStepLabel(int steps) {
  final s =
      steps.clamp(-kMaxCombinedIntensitySteps, kMaxCombinedIntensitySteps);
  if (s == 0) return 'standard';
  return s > 0 ? '+$s' : '−${-s}';
}

/// Pozycja planu po ręcznej korekcie o [steps] kroków.
///
/// Jeden krok to: +1 powtórzenie i ≈5% ciężaru. Seria dochodzi dopiero co DRUGI
/// krok — objętość jest najmocniejszą dźwignią i nie powinna rosnąć z każdym
/// kliknięciem.
PlanItem applyIntensityStepToItem(PlanItem item, int steps) {
  final s =
      steps.clamp(-kMaxCombinedIntensitySteps, kMaxCombinedIntensitySteps);
  if (s == 0) return item;
  // Przyrost serii ograniczony — przy dużych krokach objętość
  // nie może eksplodować.
  final sets = math.max(1, item.sets + (s ~/ 2).clamp(-4, 4));
  if (item.durationSec > 0) {
    return item.copyWith(
      sets: sets,
      durationSec: math.max(10, (item.durationSec * (1 + 0.08 * s)).round()),
    );
  }
  // CIĘŻARU tu nie ruszamy: dobiera go coach z historii i skaluje przez
  // [CoachContext.cycleIntensity]. Mnożenie także tutaj liczyłoby korektę
  // dwa razy.
  return item.copyWith(
    sets: sets,
    reps: item.reps > 0 ? (item.reps + s).clamp(4, 30) : item.reps,
  );
}

/// Cały dzień po ręcznej korekcie intensywności.
WorkoutDay applyIntensityStep(WorkoutDay day, int steps) => steps == 0
    ? day
    : day.copyWith(items: [
        for (final item in day.items) applyIntensityStepToItem(item, steps),
      ]);

String _deloadNote(String base) {
  final trimmed = base.trim();
  if (trimmed.toLowerCase().contains('deload')) return trimmed;
  return trimmed.isEmpty ? 'Deload — lżej' : '$trimmed · deload (lżej)';
}

// ── Pomocnicze: daty ─────────────────────────────────────────────────────────
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed == null ? null : _dateOnly(parsed);
}
