class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.order,
    required this.repetitions,
    required this.weightKg,
    required this.durationSec,
    required this.rpe,
    required this.isCompleted,
    this.isFailure = false,
    this.distanceMeters = 0,
    this.note = '',
    this.outcome = '',
    this.estimatedRpe = 0,
    this.exertionConfidence = 0,
    this.activeSeconds = 0,
    this.isTimeVerified = true,
    this.rpeSource = '',
    this.restBeforeSec = 0,
    this.plannedRestSec = 0,
    this.isRestVerified = false,
  });

  final String id;
  final int order;
  final int repetitions;
  final double weightKg;
  final int durationSec;

  /// Ręczne RPE (starsze dane) albo zaokrąglone szacowane RPE. Pole zostaje dla
  /// zgodności wstecznej — starsze, ręcznie wpisane RPE NIE jest kasowane.
  final int rpe;
  final bool isCompleted;

  /// Seria oznaczona jako nieudana — zostaje w historii, ale nie liczy się
  /// tak samo jak pełna seria przy progresie i regeneracji.
  final bool isFailure;

  /// Dystans (metry) dla wpisów cardio; 0 dla zwykłych serii.
  final double distanceMeters;

  final String note;

  /// Wybór użytkownika po serii ([SetOutcome.key]); '' = starszy zapis ręczny.
  final String outcome;

  /// Szacowane RPE (ukryty parametr, 0–10; 0 = nie liczono).
  final double estimatedRpe;

  /// Pewność szacunku wysiłku (0–1; 0 = brak oceny).
  final double exertionConfidence;

  /// Zweryfikowany aktywny czas serii (s) — bez tła/pauz; 0 = nie mierzono.
  final int activeSeconds;

  /// Czy [activeSeconds] jest wiarygodny (nie z tła/zapomnianego timera).
  final bool isTimeVerified;

  /// Źródło wartości RPE serii (Etap: rozróżnienie RPE):
  ///  * `user`      — świadomie wpisane przez użytkownika,
  ///  * `estimated` — oszacowane przez system (wynik serii + sygnały),
  ///  * `default`   — techniczna wartość domyślna (NIE dowód do progresji),
  ///  * `''`        — starszy zapis; źródło wyprowadzane heurystycznie niżej.
  final String rpeSource;

  /// REALNY odpoczynek przed tą serią (s); 0 = nie zmierzono (np. pierwsza
  /// seria ćwiczenia). Pozwala odróżnić „zrobiłem plan po pełnej przerwie"
  /// od „zrobiłem plan po połowie przerwy" — to druga sytuacja jest cięższa.
  final int restBeforeSec;

  /// Ile przerwy przewidywał plan przed tą serią (s); 0 = nieznane.
  final int plannedRestSec;

  /// Czy [restBeforeSec] pochodzi z realnego zdarzenia (koniec albo pominięcie
  /// timera), a nie z odtworzenia luki między zapisami serii.
  final bool isRestVerified;

  /// Czy w ogóle mamy czym porównać przerwę z planem.
  ///
  /// Zero sekund to POPRAWNY pomiar (przerwa pominięta od razu), więc samo
  /// `restBeforeSec > 0` nie wystarcza — liczy się potwierdzony pomiar.
  bool get hasRestMeasurement =>
      plannedRestSec > 0 && (isRestVerified || restBeforeSec > 0);

  /// Czy odpoczynek przed serią był istotnie krótszy niż zaplanowany.
  bool get restWasShortened =>
      hasRestMeasurement && restBeforeSec < plannedRestSec * 0.85;

  /// Czy odpoczynek przed serią był istotnie dłuższy niż zaplanowany.
  bool get restWasExtended =>
      hasRestMeasurement && restBeforeSec > plannedRestSec * 1.2;

  /// Czy RPE zostało świadomie wpisane przez użytkownika.
  /// Zgodność wsteczna: starszy zapis bez [rpeSource], bez wyniku ([outcome])
  /// i bez szacunku traktujemy jak ręczny wpis (panel wymuszał wybór RPE).
  bool get rpeWasUserEntered =>
      rpeSource == 'user' ||
      (rpeSource.isEmpty && outcome.isEmpty && estimatedRpe == 0 && rpe > 0);

  /// Czy RPE pochodzi z oszacowania systemu (tryb prowadzenia / timer).
  bool get rpeIsEstimated =>
      rpeSource == 'estimated' ||
      (rpeSource.isEmpty && (estimatedRpe > 0 || outcome.isNotEmpty));

  /// Czy RPE to jedynie techniczna wartość domyślna (bez realnego sygnału).
  bool get rpeIsDefault => rpeSource == 'default';

  /// Czy RPE serii jest wiarygodnym dowodem do progresji — świadomy wpis albo
  /// wystarczająco pewne oszacowanie. Domyślne/niepewne RPE nie wystarcza.
  bool get hasReliableRpe =>
      rpeWasUserEntered || (rpeIsEstimated && exertionConfidence >= 0.5);

  double get volume => isFailure ? 0 : repetitions * weightKg;

  /// Czy serię liczyć do progresu/regeneracji (zapisana i nie nieudana).
  bool get countsForProgress => isCompleted && !isFailure;

  WorkoutSet copyWith({
    String? id,
    int? order,
    int? repetitions,
    double? weightKg,
    int? durationSec,
    int? rpe,
    bool? isCompleted,
    bool? isFailure,
    double? distanceMeters,
    String? note,
    String? outcome,
    double? estimatedRpe,
    double? exertionConfidence,
    int? activeSeconds,
    bool? isTimeVerified,
    String? rpeSource,
    int? restBeforeSec,
    int? plannedRestSec,
    bool? isRestVerified,
  }) {
    return WorkoutSet(
      id: id ?? this.id,
      order: order ?? this.order,
      repetitions: repetitions ?? this.repetitions,
      weightKg: weightKg ?? this.weightKg,
      durationSec: durationSec ?? this.durationSec,
      rpe: rpe ?? this.rpe,
      isCompleted: isCompleted ?? this.isCompleted,
      isFailure: isFailure ?? this.isFailure,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      note: note ?? this.note,
      outcome: outcome ?? this.outcome,
      estimatedRpe: estimatedRpe ?? this.estimatedRpe,
      exertionConfidence: exertionConfidence ?? this.exertionConfidence,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      isTimeVerified: isTimeVerified ?? this.isTimeVerified,
      rpeSource: rpeSource ?? this.rpeSource,
      restBeforeSec: restBeforeSec ?? this.restBeforeSec,
      plannedRestSec: plannedRestSec ?? this.plannedRestSec,
      isRestVerified: isRestVerified ?? this.isRestVerified,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order': order,
        'repetitions': repetitions,
        'weightKg': weightKg,
        'durationSec': durationSec,
        'rpe': rpe,
        'isCompleted': isCompleted,
        'isFailure': isFailure,
        'distanceMeters': distanceMeters,
        'note': note,
        if (outcome.isNotEmpty) 'outcome': outcome,
        if (estimatedRpe > 0) 'estimatedRpe': estimatedRpe,
        if (exertionConfidence > 0) 'exertionConfidence': exertionConfidence,
        if (activeSeconds > 0) 'activeSeconds': activeSeconds,
        if (!isTimeVerified) 'isTimeVerified': isTimeVerified,
        if (rpeSource.isNotEmpty) 'rpeSource': rpeSource,
        if (restBeforeSec > 0) 'restBeforeSec': restBeforeSec,
        if (plannedRestSec > 0) 'plannedRestSec': plannedRestSec,
        if (isRestVerified) 'isRestVerified': isRestVerified,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        id: json['id']?.toString() ??
            'set_${DateTime.now().microsecondsSinceEpoch}',
        order: (json['order'] as num?)?.toInt() ?? 1,
        repetitions: (json['repetitions'] as num?)?.toInt() ??
            (json['reps'] as num?)?.toInt() ??
            0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        rpe: (json['rpe'] as num?)?.toInt() ?? 0,
        isCompleted: json['isCompleted'] as bool? ?? true,
        isFailure: json['isFailure'] as bool? ?? false,
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString() ?? '',
        outcome: json['outcome']?.toString() ?? '',
        estimatedRpe: (json['estimatedRpe'] as num?)?.toDouble() ?? 0,
        exertionConfidence:
            (json['exertionConfidence'] as num?)?.toDouble() ?? 0,
        activeSeconds: (json['activeSeconds'] as num?)?.toInt() ?? 0,
        isTimeVerified: json['isTimeVerified'] as bool? ?? true,
        rpeSource: json['rpeSource']?.toString() ?? '',
        restBeforeSec: (json['restBeforeSec'] as num?)?.toInt() ?? 0,
        plannedRestSec: (json['plannedRestSec'] as num?)?.toInt() ?? 0,
        isRestVerified: json['isRestVerified'] as bool? ?? false,
      );
}
