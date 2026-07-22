/// Trwały, proceduralny rozkład treningu (data → obszary treningowe).
///
/// PROBLEM, KTÓRY TO ROZWIĄZUJE: dotąd tydzień powstawał od zera przy każdym
/// budowaniu widoku — z bieżącej regeneracji i z AKTYWNEGO planu. Skutek:
/// kliknięcie innego zestawu przestawiało cały tydzień (dzień nóg zamieniał się
/// w dzień klatki), a „Plan tygodnia" nie zgadzał się z rozkładem pod nim.
///
/// Tutaj rozkład to wprost PLAN TYGODNIA: dzień tygodnia → partia
/// pierwszorzędna + drugorzędna. Jest deterministyczny i policzalny na dowolną
/// datę w przód (także po deloadzie), bo nie zależy od żadnej kotwicy ani od
/// tego, co użytkownik ostatnio kliknął. Regeneracja może go PRZESTAWIĆ, ale
/// świadomie i z widoczną adnotacją, zamiast losowo przetasować.
///
/// DWA TORY: pierwszy (klatka / plecy / nogi / brzuch) niesie dzień, drugi
/// (barki / ramiona / przedramiona / bieg) jest dodatkiem — dzięki temu każda
/// partia mieści się w tygodniu dwa razy bez mnożenia dni treningowych.
library;

import '../domain/body_muscle.dart';
import '../domain/muscle_recovery.dart';
import 'weekly_training_planner.dart';

/// Plan JEDNEGO dnia tygodnia.
///
/// `primary == null && secondary == null` oznacza DZIEŃ WOLNY.
class TrainingDayPlan {
  const TrainingDayPlan({this.primary, this.secondary});

  /// Dzień wolny — brak obu obszarów.
  static const TrainingDayPlan rest = TrainingDayPlan();

  /// Partia główna dnia (tor pierwszorzędny).
  final TrainingFocusArea? primary;

  /// Dodatek dnia (tor drugorzędny).
  final TrainingFocusArea? secondary;

  bool get isRest => primary == null && secondary == null;

  /// Partie obciążane tego dnia (główne + dodatek).
  List<BodyMuscle> get muscles => <BodyMuscle>[
        ...?primary?.muscles,
        ...?secondary?.muscles,
      ];

  String get label {
    if (isRest) return 'Dzień wolny';
    if (primary == null) return secondary!.label;
    if (secondary == null) return primary!.label;
    return '${primary!.label} + ${secondary!.label}';
  }

  TrainingDayPlan copyWith({
    TrainingFocusArea? primary,
    TrainingFocusArea? secondary,
    bool clearPrimary = false,
    bool clearSecondary = false,
  }) =>
      TrainingDayPlan(
        primary: clearPrimary ? null : (primary ?? this.primary),
        secondary: clearSecondary ? null : (secondary ?? this.secondary),
      );

  Map<String, dynamic> toJson() => {
        if (primary != null) 'primary': primary!.name,
        if (secondary != null) 'secondary': secondary!.name,
      };

  factory TrainingDayPlan.fromJson(Map<String, dynamic> json) =>
      TrainingDayPlan(
        primary: focusAreaFromKey(json['primary']),
        secondary: focusAreaFromKey(json['secondary']),
      );
}

/// Domyślny tor pierwszorzędny — najważniejsze partie w kółko.
const List<TrainingFocusArea> _defaultPrimaryCycle = kPrimaryFocusAreas;

/// Domyślny tor drugorzędny — dodatki dobrane tak, by nie dublować partii
/// głównej dnia (barki po klatce, przedramiona po plecach, bieg po nogach…).
const List<TrainingFocusArea> _defaultSecondaryCycle = [
  TrainingFocusArea.shoulders,
  TrainingFocusArea.forearms,
  TrainingFocusArea.cardio,
  TrainingFocusArea.arms,
];

/// Naprawia plan zapisany przez starsze wersje aplikacji, w których wszystkie
/// obszary mogły trafić do jednego pola. Wartość z niewłaściwego toru jest
/// przenoszona zamiast usuwana.
TrainingDayPlan normalizeTrainingDayPlan(
  TrainingDayPlan plan, {
  required int weekday,
  TrainingDayPlan? fallback,
}) {
  if (plan.isRest) return TrainingDayPlan.rest;

  TrainingFocusArea? primary =
      kPrimaryFocusAreas.contains(plan.primary) ? plan.primary : null;
  TrainingFocusArea? secondary =
      kSecondaryFocusAreas.contains(plan.secondary) ? plan.secondary : null;

  if (primary == null && kPrimaryFocusAreas.contains(plan.secondary)) {
    primary = plan.secondary;
  }
  if (secondary == null && kSecondaryFocusAreas.contains(plan.primary)) {
    secondary = plan.primary;
  }

  // Sam dodatek nie powinien zamieniać dnia treningowego w dzień wolny.
  primary ??= kPrimaryFocusAreas.contains(fallback?.primary)
      ? fallback!.primary
      : _defaultPrimaryCycle[
          ((weekday >= 1 && weekday <= 7 ? weekday : 1) - 1) %
              _defaultPrimaryCycle.length];

  return TrainingDayPlan(primary: primary, secondary: secondary);
}

/// Domyślny plan tygodnia dla podanych dni treningowych (1 = pn … 7 = nd).
///
/// Partie pierwszorzędne idą cyklicznie, dodatek dnia jest do nich dobrany —
/// przy 6–7 dniach każda duża partia wypada w tygodniu dwa razy.
Map<int, TrainingDayPlan> defaultWeekPlan(List<int> trainingWeekdays) {
  final days = trainingWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
    ..sort();
  final result = <int, TrainingDayPlan>{
    for (var weekday = 1; weekday <= 7; weekday++)
      weekday: TrainingDayPlan.rest,
  };
  for (var i = 0; i < days.length; i++) {
    result[days[i]] = TrainingDayPlan(
      primary: _defaultPrimaryCycle[i % _defaultPrimaryCycle.length],
      secondary: _defaultSecondaryCycle[i % _defaultSecondaryCycle.length],
    );
  }
  return result;
}

/// Konfiguracja rozkładu — zapisywana, więc stabilna między uruchomieniami.
class TrainingScheduleConfig {
  const TrainingScheduleConfig({
    this.enabled = true,
    this.anchor,
    this.weekdayPlans = const <int, TrainingDayPlan>{},
    this.rotationKeys = const <String>[],
    this.trainingWeekdays = const <int>[1, 2, 3, 4, 5, 6],
  });

  final bool enabled;

  /// Data pierwszego uruchomienia rozkładu. Nie wpływa już na układ (jest
  /// deterministyczny per dzień tygodnia) — zostaje jako metryka i do migracji
  /// starych zapisów opartych na rotacji slotowej.
  final DateTime? anchor;

  /// Plan tygodnia: dzień tygodnia (1–7) → partie dnia. Pusty = plan domyślny
  /// (albo migracja ze starej [rotationKeys]).
  final Map<int, TrainingDayPlan> weekdayPlans;

  /// STARY zapis rotacji ([TrainingFocusArea.name] w kolejności slotów).
  /// Trzymany wyłącznie po to, żeby zapisany wcześniej układ nie przepadł.
  final List<String> rotationKeys;

  /// Dni treningowe z profilu — używane, gdy nie ma jeszcze planu tygodnia.
  final List<int> trainingWeekdays;

  /// Plan tygodnia po rozwiązaniu: zawsze 7 wpisów (1–7).
  Map<int, TrainingDayPlan> get weekPlan {
    if (weekdayPlans.isNotEmpty) {
      final fallback = defaultWeekPlan(trainingWeekdays);
      return <int, TrainingDayPlan>{
        for (var weekday = 1; weekday <= 7; weekday++)
          weekday: weekdayPlans[weekday] == null
              ? TrainingDayPlan.rest
              : normalizeTrainingDayPlan(
                  weekdayPlans[weekday]!,
                  weekday: weekday,
                  fallback: fallback[weekday],
                ),
      };
    }
    if (rotationKeys.isNotEmpty) return _migratedFromRotation();
    return defaultWeekPlan(trainingWeekdays);
  }

  /// Plan dnia tygodnia (1 = poniedziałek … 7 = niedziela).
  TrainingDayPlan planForWeekday(int weekday) =>
      weekPlan[weekday] ?? TrainingDayPlan.rest;

  /// Dni tygodnia, w których faktycznie coś się dzieje.
  List<int> get activeWeekdays => [
        for (var weekday = 1; weekday <= 7; weekday++)
          if (!planForWeekday(weekday).isRest) weekday,
      ];

  bool get isConfigured => enabled && activeWeekdays.isNotEmpty;

  /// Ile razy w tygodniu wypada dany obszar (w obu torach razem).
  int occurrencesOf(TrainingFocusArea area) {
    var count = 0;
    for (final plan in weekPlan.values) {
      if (plan.primary == area || plan.secondary == area) count++;
    }
    return count;
  }

  /// Migracja starego zapisu: rotacja slotowa rozłożona po dniach treningowych
  /// w ich naturalnej kolejności, dodatki dobrane jak w planie domyślnym.
  Map<int, TrainingDayPlan> _migratedFromRotation() {
    final rotation = <TrainingFocusArea>[
      for (final key in rotationKeys)
        if (focusAreaFromKey(key) != null) focusAreaFromKey(key)!,
    ];
    if (rotation.isEmpty) return defaultWeekPlan(trainingWeekdays);
    final days = trainingWeekdays
        .where((d) => d >= 1 && d <= 7)
        .toSet()
        .toList()
      ..sort();
    final result = <int, TrainingDayPlan>{
      for (var weekday = 1; weekday <= 7; weekday++)
        weekday: TrainingDayPlan.rest,
    };
    for (var i = 0; i < days.length; i++) {
      final area = rotation[i % rotation.length];
      final isPrimary = kPrimaryFocusAreas.contains(area);
      result[days[i]] = TrainingDayPlan(
        primary: isPrimary
            ? area
            : _defaultPrimaryCycle[i % _defaultPrimaryCycle.length],
        secondary: isPrimary
            ? _defaultSecondaryCycle[i % _defaultSecondaryCycle.length]
            : area,
      );
    }
    return result;
  }

  TrainingScheduleConfig copyWith({
    bool? enabled,
    DateTime? anchor,
    Map<int, TrainingDayPlan>? weekdayPlans,
    List<String>? rotationKeys,
    List<int>? trainingWeekdays,
  }) =>
      TrainingScheduleConfig(
        enabled: enabled ?? this.enabled,
        anchor: anchor ?? this.anchor,
        weekdayPlans: weekdayPlans ?? this.weekdayPlans,
        rotationKeys: rotationKeys ?? this.rotationKeys,
        trainingWeekdays: trainingWeekdays ?? this.trainingWeekdays,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (anchor != null)
          'anchor': '${anchor!.year.toString().padLeft(4, '0')}-'
              '${anchor!.month.toString().padLeft(2, '0')}-'
              '${anchor!.day.toString().padLeft(2, '0')}',
        if (weekdayPlans.isNotEmpty)
          'weekdayPlans': {
            for (final entry in weekdayPlans.entries)
              entry.key.toString(): entry.value.toJson(),
          },
        'rotationKeys': rotationKeys,
        'trainingWeekdays': trainingWeekdays,
      };

  factory TrainingScheduleConfig.fromJson(Map<String, dynamic> json) {
    final rawAnchor = json['anchor']?.toString();
    final parsed = rawAnchor == null ? null : DateTime.tryParse(rawAnchor);
    final rawPlans = json['weekdayPlans'];
    return TrainingScheduleConfig(
      enabled: json['enabled'] as bool? ?? true,
      anchor: parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day),
      weekdayPlans: rawPlans is Map
          ? {
              for (final entry in rawPlans.entries)
                if (int.tryParse(entry.key.toString()) != null &&
                    entry.value is Map)
                  int.parse(entry.key.toString()): TrainingDayPlan.fromJson(
                      Map<String, dynamic>.from(entry.value as Map)),
            }
          : const <int, TrainingDayPlan>{},
      rotationKeys: [
        for (final key in (json['rotationKeys'] as List? ?? const []))
          key.toString(),
      ],
      trainingWeekdays: [
        for (final day in (json['trainingWeekdays'] as List? ?? const []))
          (day as num).toInt(),
      ],
    );
  }
}

/// Nowa mapa planów po ustawieniu [plan] na [weekday] — gotowa do zapisu.
Map<int, TrainingDayPlan> weekPlanWithDay(
  TrainingScheduleConfig config,
  int weekday,
  TrainingDayPlan plan,
) {
  final result = Map<int, TrainingDayPlan>.from(config.weekPlan);
  result[weekday] = plan;
  return result;
}

/// Jeden dzień rozkładu.
class ScheduledDay {
  const ScheduledDay({
    required this.date,
    required this.area,
    this.secondaryArea,
    this.isRest = false,
    this.isDeload = false,
    this.movedFrom,
    this.note = '',
  });

  final DateTime date;

  /// Planowana partia GŁÓWNA; `null` dla dnia wolnego.
  final TrainingFocusArea? area;

  /// Dodatek dnia z toru drugorzędnego; `null` = brak.
  final TrainingFocusArea? secondaryArea;
  final bool isRest;

  /// Czy dzień wypada w oknie deloadu (ustawiane przez warstwę aplikacji).
  final bool isDeload;

  /// Obszar, który pierwotnie wypadał tego dnia (gdy nastąpiło przestawienie).
  final TrainingFocusArea? movedFrom;

  /// Dlaczego dzień został przestawiony.
  final String note;

  bool get moved => movedFrom != null;

  /// Etykieta dnia: „Klatka piersiowa + Barki".
  String get label {
    if (isRest || (area == null && secondaryArea == null)) return 'Dzień wolny';
    if (area == null) return secondaryArea!.label;
    if (secondaryArea == null) return area!.label;
    return '${area!.label} + ${secondaryArea!.label}';
  }

  /// Partie obciążane tego dnia (główne + dodatek).
  List<TrainingFocusArea> get areas => <TrainingFocusArea>[
        if (area != null) area!,
        if (secondaryArea != null) secondaryArea!,
      ];

  ScheduledDay copyWith({
    TrainingFocusArea? area,
    TrainingFocusArea? secondaryArea,
    bool clearSecondary = false,
    bool? isDeload,
    TrainingFocusArea? movedFrom,
    String? note,
  }) =>
      ScheduledDay(
        date: date,
        area: area ?? this.area,
        secondaryArea:
            clearSecondary ? null : (secondaryArea ?? this.secondaryArea),
        isRest: isRest,
        isDeload: isDeload ?? this.isDeload,
        movedFrom: movedFrom ?? this.movedFrom,
        note: note ?? this.note,
      );

  /// Postać przekazywana planerowi tygodnia (czyste dane, bez cyklu importów).
  ScheduledFocusDay toFocusDay() => ScheduledFocusDay(
        date: date,
        primary: area,
        secondary: secondaryArea,
        isRest: isRest,
        isDeload: isDeload,
        note: note,
      );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Buduje rozkład na [days] dni począwszy od [from] — CZYSTO i deterministycznie.
///
/// Ten sam wynik niezależnie od tego, co użytkownik ostatnio kliknął.
List<ScheduledDay> buildSchedule(
  TrainingScheduleConfig config,
  DateTime from,
  int days,
) {
  if (!config.isConfigured || days <= 0) return const [];
  final plan = config.weekPlan;
  final start = _dateOnly(from);

  final result = <ScheduledDay>[];
  for (var i = 0; i < days; i++) {
    final date = start.add(Duration(days: i));
    final dayPlan = plan[date.weekday] ?? TrainingDayPlan.rest;
    if (dayPlan.isRest) {
      result.add(ScheduledDay(date: date, area: null, isRest: true));
      continue;
    }
    result.add(ScheduledDay(
      date: date,
      area: dayPlan.primary,
      secondaryArea: dayPlan.secondary,
    ));
  }
  return result;
}

/// Mapa „dzień tygodnia → partia główna" (bez korekt regeneracji).
/// Do ekranu ustawień: pokazuje, co naprawdę wypada w poniedziałek, wtorek…
Map<int, TrainingFocusArea> rotationByWeekday(
  TrainingScheduleConfig config, [
  DateTime? from,
]) {
  final result = <int, TrainingFocusArea>{};
  config.weekPlan.forEach((weekday, plan) {
    final area = plan.primary;
    if (area != null) result[weekday] = area;
  });
  return result;
}

/// Mapa „dzień tygodnia → dodatek dnia" (tor drugorzędny).
Map<int, TrainingFocusArea> secondaryByWeekday(TrainingScheduleConfig config) {
  final result = <int, TrainingFocusArea>{};
  config.weekPlan.forEach((weekday, plan) {
    final area = plan.secondary;
    if (area != null) result[weekday] = area;
  });
  return result;
}

/// Przestawia rozkład tak, by nie trenować partii, która się nie zregeneruje.
///
/// Gdy obszar zaplanowany na dany dzień ma gotowość poniżej [minReadiness],
/// szuka wśród najbliższych kolejnych dni treningowych takiego obszaru, który
/// JEST gotowy, i zamienia je miejscami. Zamiana zachowuje częstotliwość
/// (nic nie znika z tygodnia), a oba dni dostają czytelną adnotację.
/// Dodatek dnia (tor drugorzędny) nie przestawia dni — gdy jest zmęczony,
/// po prostu odpada z adnotacją, żeby nie ciągnąć całego rozkładu.
List<ScheduledDay> resolveScheduleWithRecovery(
  List<ScheduledDay> schedule,
  double Function(TrainingFocusArea area, DateTime date) readiness, {
  double minReadiness = 60,
  int lookAheadDays = 6,
}) {
  final result = [...schedule];
  for (var i = 0; i < result.length; i++) {
    final current = result[i];
    final area = current.area;
    if (area == null || current.isRest || current.moved) continue;
    if (readiness(area, current.date) >= minReadiness) continue;

    // Szukaj dnia treningowego, którego obszar da się wykonać dziś,
    // a bieżący obszar zdąży się zregenerować na jego termin.
    for (var j = i + 1; j < result.length && j <= i + lookAheadDays; j++) {
      final candidate = result[j];
      final other = candidate.area;
      if (other == null || candidate.isRest || candidate.moved) continue;
      if (other == area) continue;
      if (readiness(other, current.date) < minReadiness) continue;
      if (readiness(area, candidate.date) < minReadiness) continue;

      result[i] = current.copyWith(
        area: other,
        movedFrom: area,
        note: '${area.label} jeszcze się regeneruje — zamienione z '
            '${other.label}.',
      );
      result[j] = candidate.copyWith(
        area: area,
        movedFrom: other,
        note: 'Przesunięte z wcześniejszego dnia, żeby '
            '${area.label.toLowerCase()} zdążyły odpocząć.',
      );
      break;
    }
  }

  // Dodatek dnia odpada, gdy jego partie są jeszcze zmęczone.
  for (var i = 0; i < result.length; i++) {
    final day = result[i];
    final extra = day.secondaryArea;
    if (extra == null || day.isRest) continue;
    if (readiness(extra, day.date) >= minReadiness) continue;
    final note = day.note.isEmpty
        ? '${extra.label} pomijamy — jeszcze się regeneruje.'
        : '${day.note} ${extra.label} pomijamy — jeszcze się regeneruje.';
    result[i] = day.copyWith(clearSecondary: true, note: note);
  }
  return result;
}

/// Gotowość obszaru liczona z mapy regeneracji, z prognozą na przyszłe dni.
///
/// Im dalej w przyszłość, tym więcej godzin na regenerację — dzięki temu
/// rozkład na kolejne tygodnie nie jest blokowany dzisiejszym zmęczeniem.
double scheduleReadiness(
  TrainingFocusArea area,
  DateTime date,
  DateTime now,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
) {
  if (area.muscles.isEmpty) return 100;
  final hoursAhead =
      _dateOnly(date).difference(_dateOnly(now)).inHours.toDouble();
  var worst = 100.0;
  for (final muscle in area.muscles) {
    final state = recovery[muscle];
    if (state == null || !state.hasData) continue;
    final base = state.recoveryPercent ?? 100;
    // Regeneracja postępuje ~2 pkt/godz. — prosta, przewidywalna prognoza.
    final projected = (base + hoursAhead * 2).clamp(0, 100).toDouble();
    if (projected < worst) worst = projected;
  }
  return worst;
}
