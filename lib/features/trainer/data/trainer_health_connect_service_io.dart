import 'dart:io' show Platform;

import 'package:health/health.dart';

import '../domain/trainer_models.dart';
import 'trainer_health_connect_service.dart';

TrainerHealthConnectService createTrainerHealthConnectService() => TrainerHealthConnectServiceIo();

class TrainerHealthConnectServiceIo implements TrainerHealthConnectService {
  TrainerHealthConnectServiceIo({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const _dailyDataLabels = <String>[
    'Kroki',
    'Dystans',
    'Aktywne kcal',
    'Sesje treningowe',
    'Tętno',
    'Sen',
  ];

  static const _permissionSpecs = <_HealthPermissionSpec>[
    _HealthPermissionSpec('Kroki', [HealthDataType.STEPS]),
    _HealthPermissionSpec('Dystans', [HealthDataType.DISTANCE_DELTA]),
    _HealthPermissionSpec('Aktywne kcal', [HealthDataType.ACTIVE_ENERGY_BURNED]),
    _HealthPermissionSpec('Treningi', [HealthDataType.WORKOUT]),
    _HealthPermissionSpec('Tętno', [HealthDataType.HEART_RATE]),
    _HealthPermissionSpec('Sen', [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION]),
  ];

  static const _requestTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_SESSION,
  ];

  static const _readAccess = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  @override
  Future<TrainerHealthConnectSnapshot> checkStatus({DateTime? date}) async {
    final day = _dayOnly(date ?? DateTime.now());
    if (!Platform.isAndroid) {
      return _emptySnapshot(
        day,
        sdkStatus: 'unsupported_platform',
        errorMessage: 'Health Connect działa tylko na Androidzie.',
      );
    }

    try {
      await _health.configure();
      final status = await _health.getHealthConnectSdkStatus();
      final isAvailable = await _health.isHealthConnectAvailable();
      final permissions = await _readPermissionState(isAvailable);
      return _emptySnapshot(
        day,
        sdkStatus: status?.name ?? 'unknown',
        isAvailable: isAvailable,
        grantedPermissions: permissions.granted,
        missingPermissions: permissions.missing,
        errorMessage: isAvailable ? '' : 'Health Connect nie jest dostępny albo wymaga aktualizacji.',
      );
    } on Object catch (error) {
      return _emptySnapshot(
        day,
        sdkStatus: 'error',
        errorMessage: 'Nie udało się sprawdzić Health Connect: ${_shortError(error)}',
      );
    }
  }

  @override
  Future<TrainerHealthConnectSnapshot> requestPermissions({DateTime? date}) async {
    final day = _dayOnly(date ?? DateTime.now());
    final status = await checkStatus(date: day);
    if (!status.isAvailable) return status;
    if (status.missingPermissions.isEmpty) {
      return status.copyWith(permissionsGranted: true, errorMessage: '');
    }

    try {
      final granted = await _health.requestAuthorization(
        _requestTypes,
        permissions: _readAccess,
      );
      final refreshed = await checkStatus(date: day);
      return refreshed.copyWith(
        permissionsGranted: refreshed.missingPermissions.isEmpty,
        errorMessage: granted || refreshed.missingPermissions.isEmpty ? refreshed.errorMessage : 'Część uprawnień nie została przyznana.',
      );
    } on Object catch (error) {
      return status.copyWith(
        checkedAt: DateTime.now(),
        errorMessage: 'Nie udało się poprosić o uprawnienia: ${_shortError(error)}',
      );
    }
  }

  @override
  Future<TrainerHealthConnectSnapshot> readDailyData({DateTime? date}) async {
    final day = _dayOnly(date ?? DateTime.now());
    final status = await checkStatus(date: day);
    if (!status.isAvailable) return status;

    final start = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    final rawEnd = start.add(const Duration(days: 1));
    final end = _sameDate(day, now) && rawEnd.isAfter(now) ? now : rawEnd;
    final errors = <String>[];

    var steps = 0;
    if (status.grantedPermissions.contains('Kroki')) {
      try {
        steps = await _health.getTotalStepsInInterval(start, end) ?? 0;
      } on Object catch (error) {
        errors.add('Kroki: ${_shortError(error)}');
      }
    }

    final distancePoints = status.grantedPermissions.contains('Dystans')
        ? await _safePoints(
            types: const [HealthDataType.DISTANCE_DELTA],
            start: start,
            end: end,
            label: 'Dystans',
            errors: errors,
          )
        : const <HealthDataPoint>[];
    final distanceKm = _sumNumeric(distancePoints) / 1000;

    final kcalPoints = status.grantedPermissions.contains('Aktywne kcal')
        ? await _safePoints(
            types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
            start: start,
            end: end,
            label: 'Aktywne kcal',
            errors: errors,
          )
        : const <HealthDataPoint>[];
    final activeKcal = _sumNumeric(kcalPoints);

    final workoutPoints = status.grantedPermissions.contains('Treningi')
        ? await _safePoints(
            types: const [HealthDataType.WORKOUT],
            start: start,
            end: end,
            label: 'Treningi',
            errors: errors,
          )
        : const <HealthDataPoint>[];
    final workoutMinutes = workoutPoints.fold<int>(
      0,
      (sum, point) => sum + point.dateTo.difference(point.dateFrom).inMinutes.clamp(0, 1440),
    );

    final heartPoints = status.grantedPermissions.contains('Tętno')
        ? await _safePoints(
            types: const [HealthDataType.HEART_RATE],
            start: start,
            end: end,
            label: 'Tętno',
            errors: errors,
          )
        : const <HealthDataPoint>[];
    final heartValues = heartPoints.map(_numericValue).where((value) => value > 0).toList();
    final averageHeartRate = heartValues.isEmpty ? 0.0 : heartValues.fold<double>(0, (sum, value) => sum + value) / heartValues.length;

    var sleepPoints = <HealthDataPoint>[];
    var sleepMinutes = 0;
    if (status.grantedPermissions.contains('Sen')) {
      sleepPoints = await _safePoints(
        types: const [HealthDataType.SLEEP_ASLEEP],
        start: start,
        end: end,
        label: 'Sen',
        errors: errors,
      );
      sleepMinutes = _sumNumeric(sleepPoints).round();
      if (sleepMinutes <= 0) {
        sleepPoints = await _safePoints(
          types: const [HealthDataType.SLEEP_SESSION],
          start: start,
          end: end,
          label: 'Sesja snu',
          errors: errors,
        );
        sleepMinutes = sleepPoints.fold<int>(
          0,
          (sum, point) => sum + point.dateTo.difference(point.dateFrom).inMinutes.clamp(0, 1440),
        );
      }
    }

    final availableData = <String>[
      if (steps > 0) 'Kroki',
      if (distanceKm > 0) 'Dystans',
      if (activeKcal > 0) 'Aktywne kcal',
      if (workoutPoints.isNotEmpty) 'Sesje treningowe',
      if (heartValues.isNotEmpty) 'Tętno',
      if (sleepMinutes > 0 || sleepPoints.isNotEmpty) 'Sen',
    ];
    final missingData = _dailyDataLabels.where((label) => !availableData.contains(label)).toList();
    final errorMessage = [
      if (status.errorMessage.trim().isNotEmpty) status.errorMessage,
      ...errors,
    ].join('\n');

    return status.copyWith(
      checkedAt: DateTime.now(),
      permissionsGranted: status.missingPermissions.isEmpty,
      steps: steps,
      distanceKm: distanceKm,
      activeKcal: activeKcal,
      workoutSessions: workoutPoints.length,
      workoutMinutes: workoutMinutes,
      averageHeartRate: averageHeartRate,
      heartRateSamples: heartValues.length,
      sleepMinutes: sleepMinutes,
      availableData: availableData,
      missingData: missingData,
      errorMessage: errorMessage,
    );
  }

  Future<_PermissionState> _readPermissionState(bool isAvailable) async {
    if (!isAvailable) {
      return const _PermissionState(
        granted: <String>[],
        missing: <String>['Kroki', 'Dystans', 'Aktywne kcal', 'Treningi', 'Tętno', 'Sen'],
      );
    }

    final granted = <String>[];
    final missing = <String>[];
    for (final spec in _permissionSpecs) {
      try {
        final hasPermission = await _health.hasPermissions(
              spec.types,
              permissions: List<HealthDataAccess>.filled(spec.types.length, HealthDataAccess.READ),
            ) ??
            false;
        if (hasPermission) {
          granted.add(spec.label);
        } else {
          missing.add(spec.label);
        }
      } on Object {
        missing.add(spec.label);
      }
    }
    return _PermissionState(granted: granted, missing: missing);
  }

  Future<List<HealthDataPoint>> _safePoints({
    required List<HealthDataType> types,
    required DateTime start,
    required DateTime end,
    required String label,
    required List<String> errors,
  }) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: end,
      );
      return _health.removeDuplicates(points);
    } on Object catch (error) {
      errors.add('$label: ${_shortError(error)}');
      return const <HealthDataPoint>[];
    }
  }

  TrainerHealthConnectSnapshot _emptySnapshot(
    DateTime date, {
    required String sdkStatus,
    bool isAvailable = false,
    List<String> grantedPermissions = const <String>[],
    List<String> missingPermissions = const <String>[
      'Kroki',
      'Dystans',
      'Aktywne kcal',
      'Treningi',
      'Tętno',
      'Sen',
    ],
    String errorMessage = '',
  }) {
    final day = _dayOnly(date);
    return TrainerHealthConnectSnapshot(
      id: 'health_connect_${day.year}_${day.month}_${day.day}',
      date: day,
      checkedAt: DateTime.now(),
      sdkStatus: sdkStatus,
      isAvailable: isAvailable,
      permissionsGranted: missingPermissions.isEmpty,
      grantedPermissions: grantedPermissions,
      missingPermissions: missingPermissions,
      steps: 0,
      distanceKm: 0,
      activeKcal: 0,
      workoutSessions: 0,
      workoutMinutes: 0,
      averageHeartRate: 0,
      heartRateSamples: 0,
      sleepMinutes: 0,
      availableData: const <String>[],
      missingData: _dailyDataLabels,
      errorMessage: errorMessage,
    );
  }

  static double _sumNumeric(Iterable<HealthDataPoint> points) => points.fold<double>(0, (sum, point) => sum + _numericValue(point));

  static double _numericValue(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) return value.numericValue.toDouble();
    final json = value.toJson();
    final raw = json['numericValue'] ?? json['numeric_value'] ?? json['value'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static DateTime _dayOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  static bool _sameDate(DateTime left, DateTime right) => left.year == right.year && left.month == right.month && left.day == right.day;

  static String _shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }
}

class _HealthPermissionSpec {
  const _HealthPermissionSpec(this.label, this.types);

  final String label;
  final List<HealthDataType> types;
}

class _PermissionState {
  const _PermissionState({required this.granted, required this.missing});

  final List<String> granted;
  final List<String> missing;
}
