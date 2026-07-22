import 'training_impact.dart';

enum TrainerActivitySource {
  manual,
  trainer,
  healthConnect,
  watch,
  steps,
  run,
  measuredWalk,
}

enum TrainerActivityType {
  strengthTraining,
  ordinaryStepsWalk,
  measuredWalk,
  run,
  bike,
  otherCardio,
}

extension TrainerActivitySourceLabel on TrainerActivitySource {
  String get key {
    switch (this) {
      case TrainerActivitySource.manual:
        return 'manual';
      case TrainerActivitySource.trainer:
        return 'trainer';
      case TrainerActivitySource.healthConnect:
        return 'health_connect';
      case TrainerActivitySource.watch:
        return 'watch';
      case TrainerActivitySource.steps:
        return 'steps';
      case TrainerActivitySource.run:
        return 'run';
      case TrainerActivitySource.measuredWalk:
        return 'measured_walk';
    }
  }

  String get label {
    switch (this) {
      case TrainerActivitySource.manual:
        return 'Manual';
      case TrainerActivitySource.trainer:
        return 'Trainer';
      case TrainerActivitySource.healthConnect:
        return 'Health Connect';
      case TrainerActivitySource.watch:
        return 'Zegarek';
      case TrainerActivitySource.steps:
        return 'Kroki';
      case TrainerActivitySource.run:
        return 'Bieg';
      case TrainerActivitySource.measuredWalk:
        return 'Chód mierzony';
    }
  }

  static TrainerActivitySource fromKey(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    for (final source in TrainerActivitySource.values) {
      if (source.key == normalized) return source;
    }
    if (normalized.contains('health')) return TrainerActivitySource.healthConnect;
    if (normalized.contains('watch') || normalized.contains('zeg')) return TrainerActivitySource.watch;
    if (normalized.contains('step') || normalized.contains('krok')) return TrainerActivitySource.steps;
    if (normalized.contains('run') || normalized.contains('bieg')) return TrainerActivitySource.run;
    if (normalized.contains('walk') || normalized.contains('chod')) return TrainerActivitySource.measuredWalk;
    if (normalized.contains('trainer')) return TrainerActivitySource.trainer;
    return TrainerActivitySource.manual;
  }
}

extension TrainerActivityTypeLabel on TrainerActivityType {
  String get key {
    switch (this) {
      case TrainerActivityType.strengthTraining:
        return 'strength_training';
      case TrainerActivityType.ordinaryStepsWalk:
        return 'ordinary_steps_walk';
      case TrainerActivityType.measuredWalk:
        return 'measured_walk';
      case TrainerActivityType.run:
        return 'run';
      case TrainerActivityType.bike:
        return 'bike';
      case TrainerActivityType.otherCardio:
        return 'other_cardio';
    }
  }

  String get label {
    switch (this) {
      case TrainerActivityType.strengthTraining:
        return 'Trening siłowy';
      case TrainerActivityType.ordinaryStepsWalk:
        return 'Chód zwykły z kroków';
      case TrainerActivityType.measuredWalk:
        return 'Chód mierzony';
      case TrainerActivityType.run:
        return 'Bieg';
      case TrainerActivityType.bike:
        return 'Rower';
      case TrainerActivityType.otherCardio:
        return 'Inne cardio';
    }
  }

  static TrainerActivityType fromKey(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    for (final type in TrainerActivityType.values) {
      if (type.key == normalized) return type;
    }
    if (normalized.contains('strength') || normalized.contains('sil')) return TrainerActivityType.strengthTraining;
    if (normalized.contains('step') || normalized.contains('krok')) return TrainerActivityType.ordinaryStepsWalk;
    if (normalized.contains('walk') || normalized.contains('chod')) return TrainerActivityType.measuredWalk;
    if (normalized.contains('run') || normalized.contains('bieg')) return TrainerActivityType.run;
    if (normalized.contains('bike') || normalized.contains('rower')) return TrainerActivityType.bike;
    return TrainerActivityType.otherCardio;
  }
}

class TrainerActivityEntry {
  const TrainerActivityEntry({
    required this.id,
    required this.date,
    required this.source,
    required this.type,
    required this.estimatedKcal,
    this.sourceActivityId = '',
    this.linkedSessionId = '',
    this.startedAt,
    this.endedAt,
    this.durationMin = 0,
    this.distanceKm = 0,
    this.steps = 0,
    this.note = '',
    this.routePoints = const <List<double>>[],
    this.avgHeartRate = 0,
    this.maxHeartRate = 0,
    this.sweatLossMl = 0,
    this.hrZoneMinutes = const <int>[],
    this.kcalFromDevice = false,
  });

  final String id;
  final DateTime date;
  final TrainerActivitySource source;
  final TrainerActivityType type;
  final int estimatedKcal;
  final String sourceActivityId;
  final String linkedSessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int durationMin;
  final double distanceKm;
  final int steps;
  final String note;

  /// Trasa GPS aktywności (bieg/chód z zegarka): lista punktów [lat, lng],
  /// uproszczona do ~120 punktów. Pusta, gdy Health Connect nie udostępnił
  /// trasy (brak zgody „Trasy ćwiczeń") albo aktywność nie ma GPS.
  final List<List<double>> routePoints;

  /// Średnie / maksymalne tętno sesji (0 = brak danych).
  final double avgHeartRate;
  final double maxHeartRate;

  /// Szacowana utrata wody przez pot (ml). Health Connect nie udostępnia potu,
  /// więc to szacunek Trainera (czas × intensywność z tętna × masa ciała).
  final int sweatLossMl;

  /// Minuty w strefach pulsu [niska, kontrola wagi, aerobowa, anaerobowa, maks.]
  /// policzone z próbek tętna sesji. Pusta lista = brak danych tętna.
  final List<int> hrZoneMinutes;

  /// Czy [estimatedKcal] pochodzi wprost z zegarka / Samsung Health
  /// (a nie z własnego wzoru Trainera).
  final bool kcalFromDevice;

  bool get hasRoute => routePoints.length >= 2;

  bool get hasHeartRate => avgHeartRate > 0;

  /// Kadencja (kroki na minutę) — liczona, nie zapisywana.
  int get cadenceSpm => durationMin > 0 && steps > 0 ? (steps / durationMin).round() : 0;

  String get dateKey {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  DateTime get effectiveStart => startedAt ?? date;

  DateTime get effectiveEnd {
    final explicitEnd = endedAt;
    if (explicitEnd != null && !explicitEnd.isBefore(effectiveStart)) return explicitEnd;
    final safeDuration = durationMin <= 0 ? 1 : durationMin;
    return effectiveStart.add(Duration(minutes: safeDuration));
  }

  bool get isOrdinarySteps => type == TrainerActivityType.ordinaryStepsWalk;

  String get stableActivityKey {
    if (linkedSessionId.trim().isNotEmpty) return 'session:${linkedSessionId.trim()}:$dateKey';
    if (sourceActivityId.trim().isNotEmpty) return 'external:${sourceActivityId.trim()}';
    return 'local:${source.key}:${type.key}:$dateKey:${effectiveStart.millisecondsSinceEpoch}:$durationMin:$estimatedKcal:$steps';
  }

  String get deduplicationKey => '${source.key}:$stableActivityKey';

  TrainerActivityEntry copyWith({
    String? id,
    DateTime? date,
    TrainerActivitySource? source,
    TrainerActivityType? type,
    int? estimatedKcal,
    String? sourceActivityId,
    String? linkedSessionId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationMin,
    double? distanceKm,
    int? steps,
    String? note,
    List<List<double>>? routePoints,
    double? avgHeartRate,
    double? maxHeartRate,
    int? sweatLossMl,
    List<int>? hrZoneMinutes,
    bool? kcalFromDevice,
  }) {
    return TrainerActivityEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      source: source ?? this.source,
      type: type ?? this.type,
      estimatedKcal: estimatedKcal ?? this.estimatedKcal,
      sourceActivityId: sourceActivityId ?? this.sourceActivityId,
      linkedSessionId: linkedSessionId ?? this.linkedSessionId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationMin: durationMin ?? this.durationMin,
      distanceKm: distanceKm ?? this.distanceKm,
      steps: steps ?? this.steps,
      note: note ?? this.note,
      routePoints: routePoints ?? this.routePoints,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      sweatLossMl: sweatLossMl ?? this.sweatLossMl,
      hrZoneMinutes: hrZoneMinutes ?? this.hrZoneMinutes,
      kcalFromDevice: kcalFromDevice ?? this.kcalFromDevice,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'dateKey': dateKey,
        'source': source.key,
        'type': type.key,
        'estimatedKcal': estimatedKcal,
        'sourceActivityId': sourceActivityId,
        'linkedSessionId': linkedSessionId,
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'durationMin': durationMin,
        'distanceKm': distanceKm,
        'steps': steps,
        'note': note,
        'routePoints': routePoints,
        'avgHeartRate': avgHeartRate,
        'maxHeartRate': maxHeartRate,
        'sweatLossMl': sweatLossMl,
        'hrZoneMinutes': hrZoneMinutes,
        'kcalFromDevice': kcalFromDevice,
        'deduplicationKey': deduplicationKey,
      };

  factory TrainerActivityEntry.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    return TrainerActivityEntry(
      id: json['id']?.toString() ?? 'activity_${date.microsecondsSinceEpoch}',
      date: date,
      source: TrainerActivitySourceLabel.fromKey(json['source']?.toString()),
      type: TrainerActivityTypeLabel.fromKey(json['type']?.toString()),
      estimatedKcal: (json['estimatedKcal'] as num?)?.round() ?? 0,
      sourceActivityId: json['sourceActivityId']?.toString() ?? '',
      linkedSessionId: json['linkedSessionId']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? ''),
      durationMin: (json['durationMin'] as num?)?.round() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      steps: (json['steps'] as num?)?.round() ?? 0,
      note: json['note']?.toString() ?? '',
      routePoints: _routePointsFromJson(json['routePoints']),
      avgHeartRate: (json['avgHeartRate'] as num?)?.toDouble() ?? 0,
      maxHeartRate: (json['maxHeartRate'] as num?)?.toDouble() ?? 0,
      sweatLossMl: (json['sweatLossMl'] as num?)?.round() ?? 0,
      hrZoneMinutes: _intListFromJson(json['hrZoneMinutes']),
      kcalFromDevice: json['kcalFromDevice'] == true,
    );
  }

  static List<int> _intListFromJson(Object? value) {
    if (value is! List) return const <int>[];
    return value.map((entry) => (entry as num?)?.round() ?? 0).toList();
  }

  /// Bezpieczne parsowanie trasy: tylko poprawne pary liczb [lat, lng].
  static List<List<double>> _routePointsFromJson(Object? value) {
    if (value is! List) return const <List<double>>[];
    final points = <List<double>>[];
    for (final entry in value) {
      if (entry is! List || entry.length < 2) continue;
      final lat = (entry[0] as num?)?.toDouble();
      final lng = (entry[1] as num?)?.toDouble();
      if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) continue;
      points.add([lat, lng]);
    }
    return points;
  }

  factory TrainerActivityEntry.fromTrainingImpact(TrainingImpact impact) {
    return TrainerActivityEntry(
      id: 'activity_${impact.sessionId}',
      date: impact.date,
      source: TrainerActivitySource.trainer,
      type: TrainerActivityType.strengthTraining,
      estimatedKcal: impact.estimatedBurnedKcal,
      sourceActivityId: impact.sessionId,
      linkedSessionId: impact.sessionId,
      startedAt: impact.date.subtract(Duration(minutes: impact.durationMin)),
      endedAt: impact.date,
      durationMin: impact.durationMin,
      note: impact.sessionName,
    );
  }
}

class ActivityCreditDecision {
  const ActivityCreditDecision({
    required this.entry,
    required this.includedInCalories,
    required this.skippedAsDuplicate,
    required this.reason,
    this.duplicateOfKey = '',
  });

  final TrainerActivityEntry entry;
  final bool includedInCalories;
  final bool skippedAsDuplicate;
  final String reason;
  final String duplicateOfKey;

  int get creditedKcal => includedInCalories ? entry.estimatedKcal : 0;

  Map<String, dynamic> toJson() => {
        'entry': entry.toJson(),
        'includedInCalories': includedInCalories,
        'skippedAsDuplicate': skippedAsDuplicate,
        'reason': reason,
        'duplicateOfKey': duplicateOfKey,
        'creditedKcal': creditedKcal,
      };
}

List<ActivityCreditDecision> resolveActivityCredits(Iterable<TrainerActivityEntry> entries) {
  final sorted = entries.toList()
    ..sort((left, right) {
      final priorityCompare = _activityPriority(right.type).compareTo(_activityPriority(left.type));
      if (priorityCompare != 0) return priorityCompare;
      final kcalCompare = right.estimatedKcal.compareTo(left.estimatedKcal);
      if (kcalCompare != 0) return kcalCompare;
      return left.effectiveStart.compareTo(right.effectiveStart);
    });
  final accepted = <TrainerActivityEntry>[];
  final seenStableKeys = <String, TrainerActivityEntry>{};
  final decisions = <ActivityCreditDecision>[];

  for (final entry in sorted) {
    final duplicate = seenStableKeys[entry.stableActivityKey];
    if (duplicate != null) {
      decisions.add(
        ActivityCreditDecision(
          entry: entry,
          includedInCalories: false,
          skippedAsDuplicate: true,
          reason: 'Pominięto: ta sama aktywność ma już zaliczone kcal.',
          duplicateOfKey: duplicate.deduplicationKey,
        ),
      );
      continue;
    }

    final conflict = entry.isOrdinarySteps ? null : _firstWalkRunConflict(entry, accepted);
    if (conflict != null) {
      decisions.add(
        ActivityCreditDecision(
          entry: entry,
          includedInCalories: false,
          skippedAsDuplicate: true,
          reason: 'Pominięto: ten sam odcinek jest już policzony (${conflict.type.label.toLowerCase()}).',
          duplicateOfKey: conflict.deduplicationKey,
        ),
      );
      continue;
    }

    accepted.add(entry);
    seenStableKeys[entry.stableActivityKey] = entry;
    decisions.add(
      ActivityCreditDecision(
        entry: entry,
        includedInCalories: true,
        skippedAsDuplicate: false,
        reason: entry.isOrdinarySteps ? 'Zaliczone osobno jako zwykłe kroki.' : 'Zaliczone do kcal jako unikalna aktywność.',
      ),
    );
  }

  decisions.sort((left, right) {
    final typeCompare = _activityDisplayOrder(left.entry.type).compareTo(_activityDisplayOrder(right.entry.type));
    if (typeCompare != 0) return typeCompare;
    return left.entry.effectiveStart.compareTo(right.entry.effectiveStart);
  });
  return decisions;
}

int totalCreditedActivityKcal(Iterable<ActivityCreditDecision> decisions) => decisions.fold<int>(0, (sum, decision) => sum + decision.creditedKcal);

TrainerActivityEntry? _firstWalkRunConflict(TrainerActivityEntry entry, Iterable<TrainerActivityEntry> accepted) {
  for (final candidate in accepted) {
    if (_isWalkRunConflict(entry, candidate)) return candidate;
  }
  return null;
}

int _activityPriority(TrainerActivityType type) {
  switch (type) {
    case TrainerActivityType.run:
      return 90;
    case TrainerActivityType.measuredWalk:
      return 80;
    case TrainerActivityType.bike:
      return 70;
    case TrainerActivityType.otherCardio:
      return 60;
    case TrainerActivityType.strengthTraining:
      return 50;
    case TrainerActivityType.ordinaryStepsWalk:
      return 40;
  }
}

int _activityDisplayOrder(TrainerActivityType type) {
  switch (type) {
    case TrainerActivityType.ordinaryStepsWalk:
      return 0;
    case TrainerActivityType.measuredWalk:
      return 1;
    case TrainerActivityType.run:
      return 2;
    case TrainerActivityType.strengthTraining:
      return 3;
    case TrainerActivityType.bike:
      return 4;
    case TrainerActivityType.otherCardio:
      return 5;
  }
}

bool _isWalkRunConflict(TrainerActivityEntry left, TrainerActivityEntry right) {
  // Konflikt dotyczy odcinków bieg/chód w KAŻDEJ kombinacji: bieg↔chód
  // (ten sam odcinek raz jako bieg, raz jako marsz), ale też bieg↔bieg i
  // chód↔chód (ta sama sesja zapisana przez dwie aplikacje pod różnymi id).
  const overlapTypes = {TrainerActivityType.measuredWalk, TrainerActivityType.run};
  if (!overlapTypes.contains(left.type) || !overlapTypes.contains(right.type)) return false;
  if (left.dateKey != right.dateKey) return false;
  if (left.stableActivityKey == right.stableActivityKey) return true;
  if (left.sourceActivityId.isNotEmpty && left.sourceActivityId == right.sourceActivityId) return true;
  if (left.linkedSessionId.isNotEmpty && left.linkedSessionId == right.linkedSessionId) return true;
  return _overlapMinutes(left, right) >= 5;
}

int _overlapMinutes(TrainerActivityEntry left, TrainerActivityEntry right) {
  final start = left.effectiveStart.isAfter(right.effectiveStart) ? left.effectiveStart : right.effectiveStart;
  final end = left.effectiveEnd.isBefore(right.effectiveEnd) ? left.effectiveEnd : right.effectiveEnd;
  if (!end.isAfter(start)) return 0;
  return end.difference(start).inMinutes;
}
