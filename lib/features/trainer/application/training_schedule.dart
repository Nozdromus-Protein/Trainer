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

/// Strategia podziału tygodnia.
///
/// Rozkład DWUTOROWY dzieli tydzień na partie (klatka / plecy / nogi / brzuch)
/// z dodatkiem, a PUSH / PULL / LEGS — na wzorce ruchu. W obu przypadkach dzień
/// to nadal „partia główna + dodatek", więc reszta aplikacji (zestawy, deload,
/// regeneracja) działa bez zmian.
enum TrainingSplitStrategy {
  twoTrack('twoTrack', 'Dwutorowy (partia + dodatek)'),
  pushPullLegs('pushPullLegs', 'Push / Pull / Legs');

  const TrainingSplitStrategy(this.key, this.label);

  final String key;
  final String label;

  bool get isPushPullLegs => this == TrainingSplitStrategy.pushPullLegs;

  /// Strategia DOMYŚLNA — Push / Pull / Legs. Rotacja trzech wzorców ruchu jest
  /// czytelniejsza i lepiej znosi przestawianie dni pod regenerację niż podział
  /// na pojedyncze partie.
  static const TrainingSplitStrategy defaultStrategy =
      TrainingSplitStrategy.pushPullLegs;

  /// Nieznany albo brakujący klucz → strategia domyślna. Zapisy sprzed tego
  /// pola nie niosą strategii, więc przechodzą na Push / Pull / Legs, a ich
  /// własny plan tygodnia jest przekładany na bloki (patrz [pplAreaFor]).
  static TrainingSplitStrategy fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final strategy in TrainingSplitStrategy.values) {
      if (strategy.key == key || strategy.name == key) return strategy;
    }
    return defaultStrategy;
  }
}

/// Blok Push / Pull / Legs odpowiadający partii z rozkładu dwutorowego.
///
/// Dzięki temu przejście na PPL nie kasuje ułożonego tygodnia: „Klatka" staje
/// się dniem pchania, „Plecy" dniem ciągnięcia, „Nogi" zostają nogami.
TrainingFocusArea? pplAreaFor(TrainingFocusArea? area) {
  switch (area) {
    case TrainingFocusArea.push:
    case TrainingFocusArea.pull:
    case TrainingFocusArea.legs:
      return area;
    case TrainingFocusArea.chestTriceps:
    case TrainingFocusArea.shoulders:
      return TrainingFocusArea.push;
    case TrainingFocusArea.backBiceps:
    case TrainingFocusArea.arms:
      return TrainingFocusArea.pull;
    default:
      return null;
  }
}

/// Obszary pierwszorzędne dostępne w danej strategii.
List<TrainingFocusArea> primaryAreasFor(TrainingSplitStrategy strategy) =>
    strategy.isPushPullLegs ? kPushPullLegsAreas : kPrimaryFocusAreas;

/// Obszary, które mogą być DODATKIEM dnia w danej strategii.
///
/// W Push/Pull/Legs brzuch nie jest osobnym dniem — wchodzi jako dodatek,
/// więc lista jest o niego szersza.
List<TrainingFocusArea> secondaryAreasFor(TrainingSplitStrategy strategy) =>
    strategy.isPushPullLegs
        ? const [...kSecondaryFocusAreas, TrainingFocusArea.core]
        : kSecondaryFocusAreas;

/// Trzy poziomy odciążenia dnia — hierarchia z etapu:
/// DELOAD ma pierwszeństwo, potem REGENERACJA, a na końcu sam ZESTAW.
enum DayLoadTier {
  /// Tydzień deloadu — dzień jest lekki z założenia.
  deload('deload', 'deload (lżej)'),

  /// Partie jeszcze nie w pełni gotowe — zestaw wykonany lżej.
  recovery('recovery', 'lżejszy (regeneracja)'),

  /// Pełny zestaw zgodnie z planem.
  full('full', 'pełny zestaw');

  const DayLoadTier(this.key, this.label);

  final String key;
  final String label;

  /// Im niżej w hierarchii, tym mocniejsze odciążenie (deload = 0).
  int get rank => index;
}

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

/// Dodatki dnia w strategii Push / Pull / Legs — dobrane tak, by nie dublować
/// bloku głównego: po pchaniu i po nogach brzuch, po ciągnięciu chwyt.
const List<TrainingFocusArea> _pplSecondaryCycle = [
  TrainingFocusArea.core,
  TrainingFocusArea.forearms,
  TrainingFocusArea.core,
];

/// Naprawia plan zapisany przez starsze wersje aplikacji, w których wszystkie
/// obszary mogły trafić do jednego pola. Wartość z niewłaściwego toru jest
/// przenoszona zamiast usuwana.
TrainingDayPlan normalizeTrainingDayPlan(
  TrainingDayPlan plan, {
  required int weekday,
  TrainingDayPlan? fallback,
  TrainingSplitStrategy strategy = TrainingSplitStrategy.twoTrack,
}) {
  if (plan.isRest) return TrainingDayPlan.rest;

  // Przejście na Push / Pull / Legs nie kasuje ułożonego tygodnia — partia
  // z rozkładu dwutorowego staje się swoim blokiem ruchu.
  if (strategy.isPushPullLegs && !kPushPullLegsAreas.contains(plan.primary)) {
    final mapped = pplAreaFor(plan.primary) ?? pplAreaFor(plan.secondary);
    if (mapped != null) {
      plan = TrainingDayPlan(
        primary: mapped,
        // Dawna partia główna wraca jako dodatek, o ile pasuje do toru
        // drugorzędnego (np. „Brzuch" po dniu nóg).
        secondary: secondaryAreasFor(strategy).contains(plan.primary)
            ? plan.primary
            : plan.secondary,
      );
    }
  }

  final secondaryAreas = secondaryAreasFor(strategy);
  TrainingFocusArea? primary =
      kAllPrimaryTrackAreas.contains(plan.primary) ? plan.primary : null;
  TrainingFocusArea? secondary =
      secondaryAreas.contains(plan.secondary) ? plan.secondary : null;

  if (primary == null && kAllPrimaryTrackAreas.contains(plan.secondary)) {
    primary = plan.secondary;
  }
  if (secondary == null && secondaryAreas.contains(plan.primary)) {
    secondary = plan.primary;
  }
  // Ten sam obszar nie może stać w obu torach naraz.
  if (primary != null && primary == secondary) secondary = null;

  // Sam dodatek nie powinien zamieniać dnia treningowego w dzień wolny.
  final cycle = primaryAreasFor(strategy);
  primary ??= kAllPrimaryTrackAreas.contains(fallback?.primary)
      ? fallback!.primary
      : cycle[((weekday >= 1 && weekday <= 7 ? weekday : 1) - 1) % cycle.length];

  return TrainingDayPlan(primary: primary, secondary: secondary);
}

/// Domyślny plan tygodnia dla podanych dni treningowych (1 = pn … 7 = nd).
///
/// Partie pierwszorzędne idą cyklicznie, dodatek dnia jest do nich dobrany —
/// przy 6–7 dniach każda duża partia wypada w tygodniu dwa razy. W strategii
/// Push / Pull / Legs cykl ma trzy bloki, więc przy 6 dniach każdy wypada
/// dokładnie dwa razy.
Map<int, TrainingDayPlan> defaultWeekPlan(
  List<int> trainingWeekdays, {
  TrainingSplitStrategy strategy = TrainingSplitStrategy.twoTrack,
}) {
  final days = trainingWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
    ..sort();
  final result = <int, TrainingDayPlan>{
    for (var weekday = 1; weekday <= 7; weekday++)
      weekday: TrainingDayPlan.rest,
  };
  final primaryCycle =
      strategy.isPushPullLegs ? kPushPullLegsAreas : _defaultPrimaryCycle;
  final secondaryCycle =
      strategy.isPushPullLegs ? _pplSecondaryCycle : _defaultSecondaryCycle;
  for (var i = 0; i < days.length; i++) {
    result[days[i]] = TrainingDayPlan(
      primary: primaryCycle[i % primaryCycle.length],
      secondary: secondaryCycle[i % secondaryCycle.length],
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
    this.strategy = TrainingSplitStrategy.defaultStrategy,
  });

  final bool enabled;

  /// Strategia podziału tygodnia (dwutorowa albo Push / Pull / Legs).
  final TrainingSplitStrategy strategy;

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
      final fallback = defaultWeekPlan(trainingWeekdays, strategy: strategy);
      return <int, TrainingDayPlan>{
        for (var weekday = 1; weekday <= 7; weekday++)
          weekday: weekdayPlans[weekday] == null
              ? TrainingDayPlan.rest
              : normalizeTrainingDayPlan(
                  weekdayPlans[weekday]!,
                  weekday: weekday,
                  fallback: fallback[weekday],
                  strategy: strategy,
                ),
      };
    }
    if (rotationKeys.isNotEmpty) return _migratedFromRotation();
    return defaultWeekPlan(trainingWeekdays, strategy: strategy);
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
    TrainingSplitStrategy? strategy,
    bool clearWeekdayPlans = false,
  }) =>
      TrainingScheduleConfig(
        enabled: enabled ?? this.enabled,
        anchor: anchor ?? this.anchor,
        weekdayPlans: clearWeekdayPlans
            ? const <int, TrainingDayPlan>{}
            : (weekdayPlans ?? this.weekdayPlans),
        rotationKeys:
            clearWeekdayPlans ? const <String>[] : (rotationKeys ?? this.rotationKeys),
        trainingWeekdays: trainingWeekdays ?? this.trainingWeekdays,
        strategy: strategy ?? this.strategy,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'strategy': strategy.key,
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
      strategy: TrainingSplitStrategy.fromKey(json['strategy']),
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
    this.loadTier = DayLoadTier.full,
    this.intensityScale = 1.0,
    this.readinessPercent = 100,
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

  /// Poziom odciążenia dnia w hierarchii Deload > Regeneracja > Zestaw.
  final DayLoadTier loadTier;

  /// Mnożnik obciążenia zestawu dla tego dnia (1.0 = pełny). Deload i słabsza
  /// regeneracja go obniżają; NIE zastępuje gałki intensywności użytkownika.
  final double intensityScale;

  /// Gotowość (regeneracja %) bloku głównego w tym dniu.
  final double readinessPercent;

  bool get moved => movedFrom != null;

  bool get isLightened => loadTier != DayLoadTier.full;

  /// Etykieta dnia: „Klatka piersiowa + Barki".
  String get label {
    if (isRest || (area == null && secondaryArea == null)) return 'Dzień wolny';
    if (area == null) return secondaryArea!.label;
    if (secondaryArea == null) return area!.label;
    return '${area!.label} + ${secondaryArea!.label}';
  }

  /// Nazwa dnia z poziomem obciążenia — hierarchia jest widoczna w nazwie
  /// zestawu: „Push + Brzuch · deload (lżej)" albo „· lżejszy (regeneracja 54%)".
  String get labelWithLoad {
    if (isRest) return label;
    switch (loadTier) {
      case DayLoadTier.deload:
        return '$label · ${DayLoadTier.deload.label}';
      case DayLoadTier.recovery:
        return '$label · lżejszy (regeneracja ${readinessPercent.round()}%)';
      case DayLoadTier.full:
        return label;
    }
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
    DayLoadTier? loadTier,
    double? intensityScale,
    double? readinessPercent,
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
        loadTier: loadTier ?? this.loadTier,
        intensityScale: intensityScale ?? this.intensityScale,
        readinessPercent: readinessPercent ?? this.readinessPercent,
      );

  /// Postać przekazywana planerowi tygodnia (czyste dane, bez cyklu importów).
  ScheduledFocusDay toFocusDay() => ScheduledFocusDay(
        date: date,
        primary: area,
        secondary: secondaryArea,
        isRest: isRest,
        isDeload: isDeload,
        note: note,
        loadSuffix: loadTier == DayLoadTier.deload
            ? DayLoadTier.deload.label
            : loadTier == DayLoadTier.recovery
                ? 'lżejszy (regeneracja ${readinessPercent.round()}%)'
                : '',
        intensityScale: intensityScale,
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
///
/// [readinessIgnoring] liczy gotowość z POMINIĘCIEM wskazanych partii. Używamy
/// go dla dodatku dnia: partie, które i tak obciąża dziś blok główny (przedni
/// bark i triceps w dniu klatki), nie mogą wyrzucić dodatku z tego samego dnia.
/// To one blokowały „barki po klatce" — zestaw znikał, a dzień zamykał się sam.
List<ScheduledDay> resolveScheduleWithRecovery(
  List<ScheduledDay> schedule,
  double Function(TrainingFocusArea area, DateTime date) readiness, {
  double minReadiness = 60,
  int lookAheadDays = 6,
  double Function(
    TrainingFocusArea area,
    DateTime date,
    Iterable<BodyMuscle> ignoreMuscles,
  )? readinessIgnoring,

  /// Dni JUŻ ZAMKNIĘTE (wykonane albo miniona data) — nie wolno ich przestawiać
  /// ani odchudzać. Bez tego świeżo wytrenowana partia miała niską gotowość,
  /// więc rozkład „naprawiał" dzisiejszy dzień, podmieniając zrobioną klatkę
  /// na nogi. To, co się wydarzyło, jest faktem, a nie planem do poprawienia.
  bool Function(ScheduledDay day)? isLocked,
}) {
  bool locked(ScheduledDay day) => isLocked?.call(day) ?? false;
  final result = [...schedule];
  for (var i = 0; i < result.length; i++) {
    final current = result[i];
    final area = current.area;
    if (area == null || current.isRest || current.moved) continue;
    if (locked(current)) continue;
    if (readiness(area, current.date) >= minReadiness) continue;
    // Ostatni dzień, do którego nie ma już czego przestawić — dalej pilnuje
    // tego bramka odciążenia ([applyLoadHierarchy]).

    // Szukaj dnia treningowego, którego obszar da się wykonać dziś,
    // a bieżący obszar zdąży się zregenerować na jego termin.
    for (var j = i + 1; j < result.length && j <= i + lookAheadDays; j++) {
      final candidate = result[j];
      final other = candidate.area;
      if (other == null || candidate.isRest || candidate.moved) continue;
      if (locked(candidate)) continue;
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

  // Dodatek dnia odpada, gdy jego WŁASNE partie są jeszcze zmęczone. Partie
  // wspólne z blokiem głównym TEGO SAMEGO dnia są wyłączone z oceny — są dziś
  // trenowane razem (barki po klatce, ramiona po plecach), więc ich zmęczenie
  // nie może kasować dodatku. To ono zamykało dzień po pierwszym zestawie.
  for (var i = 0; i < result.length; i++) {
    final day = result[i];
    final extra = day.secondaryArea;
    if (extra == null || day.isRest || locked(day)) continue;
    final sharedWithMain = day.area?.muscles ?? const <BodyMuscle>[];
    final extraReadiness = readinessIgnoring == null
        ? readiness(extra, day.date)
        : readinessIgnoring(extra, day.date, sharedWithMain);
    if (extraReadiness >= minReadiness) continue;
    final note = day.note.isEmpty
        ? '${extra.label} pomijamy — jeszcze się regeneruje.'
        : '${day.note} ${extra.label} pomijamy — jeszcze się regeneruje.';
    result[i] = day.copyWith(clearSecondary: true, note: note);
  }
  return result;
}

/// Nakłada HIERARCHIĘ ODCIĄŻENIA: Deload ⟶ Regeneracja ⟶ Zestaw ćwiczeń.
///
/// Kolejność jest sztywna i nienegocjowalna:
///  1. DELOAD — gdy dzień wypada w oknie deloadu, jest lekki z definicji
///     i regeneracja nie może go już „podkręcić";
///  2. REGENERACJA — dzień, którego nie dało się przestawić, a partie nie są
///     w pełni gotowe, dostaje ZESTAW W LŻEJSZEJ WERSJI (tyle, ile trzeba —
///     im niższa gotowość, tym mocniejsze odciążenie);
///  3. ZESTAW — dopiero na końcu obowiązuje pełna wersja zaplanowanego zestawu.
///
/// Zwraca dni z ustawionym [ScheduledDay.loadTier] i [ScheduledDay.intensityScale];
/// nazwa dnia ([ScheduledDay.labelWithLoad]) niesie ten sam poziom.
List<ScheduledDay> applyLoadHierarchy(
  List<ScheduledDay> schedule,
  double Function(TrainingFocusArea area, DateTime date) readiness, {
  double minReadiness = 60,
  double deloadScale = 0.6,

  /// Dni zamknięte (wykonane / minione) zostają jak są — nie doklejamy im
  /// „lżejszy (regeneracja 30%)", bo to zmęczenie pochodzi z ICH treningu.
  bool Function(ScheduledDay day)? isLocked,
}) {
  return [
    for (final day in schedule)
      if (day.isRest || day.area == null || (isLocked?.call(day) ?? false))
        day
      else
        _withLoadTier(day, readiness, minReadiness, deloadScale),
  ];
}

ScheduledDay _withLoadTier(
  ScheduledDay day,
  double Function(TrainingFocusArea area, DateTime date) readiness,
  double minReadiness,
  double deloadScale,
) {
  final area = day.area!;
  final percent = readiness(area, day.date);
  // 1. Deload wygrywa ze wszystkim.
  if (day.isDeload) {
    return day.copyWith(
      loadTier: DayLoadTier.deload,
      intensityScale: deloadScale,
      readinessPercent: percent,
    );
  }
  // 2. Regeneracja: zestaw zostaje, ale w lżejszej wersji — dokładnie na tyle,
  // na ile brakuje gotowości (nigdy poniżej 65% obciążenia).
  if (percent < minReadiness) {
    final deficit = (minReadiness - percent) / minReadiness; // 0..1
    final scale = (1 - deficit * 0.35).clamp(0.65, 1.0).toDouble();
    final note = day.note.isEmpty
        ? '${area.label}: gotowość ${percent.round()}% — zestaw w lżejszej wersji.'
        : '${day.note} Zestaw w lżejszej wersji (gotowość ${percent.round()}%).';
    return day.copyWith(
      loadTier: DayLoadTier.recovery,
      intensityScale: scale,
      readinessPercent: percent,
      note: note,
    );
  }
  // 3. Pełny zestaw.
  return day.copyWith(
    loadTier: DayLoadTier.full,
    intensityScale: 1.0,
    readinessPercent: percent,
  );
}

/// Gotowość obszaru liczona z mapy regeneracji, z prognozą na przyszłe dni.
///
/// Im dalej w przyszłość, tym więcej godzin na regenerację — dzięki temu
/// rozkład na kolejne tygodnie nie jest blokowany dzisiejszym zmęczeniem.
/// Gotowość obszaru liczona z partii, które go DEFINIUJĄ
/// ([TrainingFocusArea.signatureMuscles]), z prognozą na przyszłe dni.
///
/// Partie pomocnicze (triceps i przedni bark w dniu klatki, biceps w dniu
/// pleców) celowo NIE decydują o przełożeniu dnia. Wcześniej jedna zmęczona
/// partia wspierająca wystarczała, żeby cały blok wypadł jako niegotowy — dzień
/// klatki nie mógł stanąć po dniu barków, a rotacja push / pull / legs blokowała
/// się sama. Zmęczenie partii pomocniczych nadal widać w ostrzeżeniach dnia.
///
/// [ignoreMuscles] pozwala pominąć partie, które i tak są dziś trenowane przez
/// blok główny — używa tego dobór DODATKU dnia.
///
/// [bestMuscle] przełącza agregację z NAJSŁABSZEJ partii na NAJLEPSZĄ.
///
/// Blok GŁÓWNY oceniamy najsłabszą partią — zmęczone uda naprawdę blokują dzień
/// nóg. DODATEK dnia oceniamy najlepszą: „Ramiona" to biceps i triceps, więc
/// zmęczony triceps po dniu pchania nie może skasować całego dodatku, skoro na
/// biceps jest pełna gotowość. Dodatek odpada dopiero wtedy, gdy NIC z jego
/// partii nie jest gotowe.
double scheduleReadiness(
  TrainingFocusArea area,
  DateTime date,
  DateTime now,
  Map<BodyMuscle, MuscleRecoveryState> recovery, {
  Iterable<BodyMuscle> ignoreMuscles = const [],
  bool bestMuscle = false,
}) {
  final muscles = [
    for (final muscle in area.signatureMuscles)
      if (!ignoreMuscles.contains(muscle)) muscle,
  ];
  if (muscles.isEmpty) return 100;
  final hoursAhead =
      _dateOnly(date).difference(_dateOnly(now)).inHours.toDouble();
  var worst = 100.0;
  var best = 0.0;
  var hasAny = false;
  for (final muscle in muscles) {
    final state = recovery[muscle];
    // Partia bez danych jest w pełni zregenerowana.
    final base = state == null || !state.hasData
        ? 100.0
        : (state.recoveryPercent ?? 100);
    // Regeneracja postępuje ~2 pkt/godz. — prosta, przewidywalna prognoza.
    final projected = (base + hoursAhead * 2).clamp(0, 100).toDouble();
    if (projected < worst) worst = projected;
    if (projected > best) best = projected;
    hasAny = true;
  }
  if (!hasAny) return 100;
  return bestMuscle ? best : worst;
}
