/// Pojedyncza sesja treningowa odczytana z Health Connect (zegarek/telefon).
///
/// Trainer używa jej do rozpoznania biegu, chodu i roweru oraz zamiany na
/// wpisy aktywności ([TrainerActivityEntry]) z przeliczeniem na kcal.
/// [sourceId] (uuid rekordu Health Connect) jest stabilnym kluczem
/// deduplikacji — ta sama sesja nigdy nie zostanie policzona dwa razy.
class TrainerHealthWorkoutSession {
  const TrainerHealthWorkoutSession({
    required this.sourceId,
    required this.activityType,
    required this.start,
    required this.end,
    this.energyKcal = 0,
    this.distanceKm = 0,
    this.sourceName = '',
    this.steps = 0,
    this.avgHeartRate = 0,
    this.maxHeartRate = 0,
    this.hrSamples = const <int>[],
  });

  final String sourceId;

  /// Surowy typ aktywności z Health Connect, np. RUNNING / WALKING / BIKING.
  final String activityType;
  final DateTime start;
  final DateTime end;

  /// Kcal zarejestrowane przez zegarek/Samsung Health dla tej sesji
  /// (agregat okna sesji) — główne źródło prawdy, gdy > 0.
  final double energyKcal;
  final double distanceKm;
  final String sourceName;

  /// Kroki zarejestrowane w oknie sesji (agregat Health Connect).
  final int steps;
  final double avgHeartRate;
  final double maxHeartRate;

  /// Próbki tętna z sesji (uśrednione, ~180 wartości) — do stref pulsu.
  final List<int> hrSamples;

  int get durationMin {
    final minutes = end.difference(start).inMinutes;
    if (minutes < 0) return 0;
    return minutes > 1440 ? 1440 : minutes;
  }

  String get _type => activityType.toUpperCase();
  bool get isRun => _type.contains('RUN') || _type.contains('JOG');
  bool get isWalk => !isRun && (_type.contains('WALK') || _type.contains('HIK'));
  bool get isBike => _type.contains('BIK') || _type.contains('CYCL');
}

class TrainerHealthConnectSnapshot {
  const TrainerHealthConnectSnapshot({
    required this.id,
    required this.date,
    required this.checkedAt,
    required this.sdkStatus,
    required this.isAvailable,
    required this.permissionsGranted,
    required this.grantedPermissions,
    required this.missingPermissions,
    required this.steps,
    required this.distanceKm,
    required this.activeKcal,
    required this.workoutSessions,
    required this.workoutMinutes,
    required this.averageHeartRate,
    required this.heartRateSamples,
    required this.sleepMinutes,
    required this.availableData,
    required this.missingData,
    this.errorMessage = '',
    this.activeKcalEstimated = false,
    this.distanceEstimated = false,
  });

  static const schema = 'trainer_health_connect_snapshot_v1';

  final String id;
  final DateTime date;
  final DateTime checkedAt;
  final String sdkStatus;
  final bool isAvailable;
  final bool permissionsGranted;
  final List<String> grantedPermissions;
  final List<String> missingPermissions;
  final int steps;
  final double distanceKm;
  final double activeKcal;
  final int workoutSessions;
  final int workoutMinutes;
  final double averageHeartRate;
  final int heartRateSamples;
  final int sleepMinutes;
  final List<String> availableData;
  final List<String> missingData;
  final String errorMessage;

  /// Zegarek nie oddał aktywnych kcal do Health Connect — wartość [activeKcal]
  /// to szacunek Trainera (sesje biegu/chodu + kroki × masa ciała).
  final bool activeKcalEstimated;

  /// Analogicznie: [distanceKm] oszacowany (sesje albo kroki × długość kroku).
  final bool distanceEstimated;

  String get dateKey => _dateKey(date);

  bool get hasAnyDailyData => steps > 0 || distanceKm > 0 || activeKcal > 0 || workoutSessions > 0 || heartRateSamples > 0 || sleepMinutes > 0;

  TrainerHealthConnectSnapshot copyWith({
    String? id,
    DateTime? date,
    DateTime? checkedAt,
    String? sdkStatus,
    bool? isAvailable,
    bool? permissionsGranted,
    List<String>? grantedPermissions,
    List<String>? missingPermissions,
    int? steps,
    double? distanceKm,
    double? activeKcal,
    int? workoutSessions,
    int? workoutMinutes,
    double? averageHeartRate,
    int? heartRateSamples,
    int? sleepMinutes,
    List<String>? availableData,
    List<String>? missingData,
    String? errorMessage,
    bool? activeKcalEstimated,
    bool? distanceEstimated,
  }) {
    return TrainerHealthConnectSnapshot(
      id: id ?? this.id,
      date: date ?? this.date,
      checkedAt: checkedAt ?? this.checkedAt,
      sdkStatus: sdkStatus ?? this.sdkStatus,
      isAvailable: isAvailable ?? this.isAvailable,
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
      grantedPermissions: grantedPermissions ?? this.grantedPermissions,
      missingPermissions: missingPermissions ?? this.missingPermissions,
      steps: steps ?? this.steps,
      distanceKm: distanceKm ?? this.distanceKm,
      activeKcal: activeKcal ?? this.activeKcal,
      workoutSessions: workoutSessions ?? this.workoutSessions,
      workoutMinutes: workoutMinutes ?? this.workoutMinutes,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      heartRateSamples: heartRateSamples ?? this.heartRateSamples,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      availableData: availableData ?? this.availableData,
      missingData: missingData ?? this.missingData,
      errorMessage: errorMessage ?? this.errorMessage,
      activeKcalEstimated: activeKcalEstimated ?? this.activeKcalEstimated,
      distanceEstimated: distanceEstimated ?? this.distanceEstimated,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'id': id,
        'date': date.toIso8601String(),
        'checkedAt': checkedAt.toIso8601String(),
        'sdkStatus': sdkStatus,
        'isAvailable': isAvailable,
        'permissionsGranted': permissionsGranted,
        'grantedPermissions': grantedPermissions,
        'missingPermissions': missingPermissions,
        'steps': steps,
        'distanceKm': distanceKm,
        'activeKcal': activeKcal,
        'workoutSessions': workoutSessions,
        'workoutMinutes': workoutMinutes,
        'averageHeartRate': averageHeartRate,
        'heartRateSamples': heartRateSamples,
        'sleepMinutes': sleepMinutes,
        'availableData': availableData,
        'missingData': missingData,
        'errorMessage': errorMessage,
        'activeKcalEstimated': activeKcalEstimated,
        'distanceEstimated': distanceEstimated,
      };

  factory TrainerHealthConnectSnapshot.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return TrainerHealthConnectSnapshot(
      id: json['id']?.toString() ?? 'health_connect_${now.microsecondsSinceEpoch}',
      date: _dateFromJson(json['date'], now),
      checkedAt: _dateFromJson(json['checkedAt'], now),
      sdkStatus: json['sdkStatus']?.toString() ?? 'unknown',
      isAvailable: json['isAvailable'] == true,
      permissionsGranted: json['permissionsGranted'] == true,
      grantedPermissions: _stringList(json['grantedPermissions']),
      missingPermissions: _stringList(json['missingPermissions']),
      steps: _intValue(json['steps']),
      distanceKm: _doubleValue(json['distanceKm']),
      activeKcal: _doubleValue(json['activeKcal']),
      workoutSessions: _intValue(json['workoutSessions']),
      workoutMinutes: _intValue(json['workoutMinutes']),
      averageHeartRate: _doubleValue(json['averageHeartRate']),
      heartRateSamples: _intValue(json['heartRateSamples']),
      sleepMinutes: _intValue(json['sleepMinutes']),
      availableData: _stringList(json['availableData']),
      missingData: _stringList(json['missingData']),
      errorMessage: json['errorMessage']?.toString() ?? '',
      activeKcalEstimated: json['activeKcalEstimated'] == true,
      distanceEstimated: json['distanceEstimated'] == true,
    );
  }

  static String _dateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static DateTime _dateFromJson(Object? value, DateTime fallback) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed ?? fallback;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.map((entry) => entry.toString().trim()).where((entry) => entry.isNotEmpty).toList();
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }
}
