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
