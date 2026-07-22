import '../domain/trainer_models.dart';
import 'trainer_health_connect_service.dart';

TrainerHealthConnectService createTrainerHealthConnectService() => const UnsupportedTrainerHealthConnectService();

class UnsupportedTrainerHealthConnectService implements TrainerHealthConnectService {
  const UnsupportedTrainerHealthConnectService();

  @override
  Future<TrainerHealthConnectSnapshot> checkStatus({DateTime? date}) async => _snapshot(date, 'Health Connect jest dostępny tylko na Androidzie.');

  @override
  Future<TrainerHealthConnectSnapshot> requestPermissions({DateTime? date}) async => _snapshot(date, 'Nie można poprosić o uprawnienia na tej platformie.');

  @override
  Future<TrainerHealthConnectSnapshot> readDailyData({DateTime? date}) async => _snapshot(date, 'Odczyt Health Connect jest dostępny tylko na Androidzie.');

  @override
  Future<List<TrainerHealthWorkoutSession>> readWorkoutSessions({DateTime? date}) async => const <TrainerHealthWorkoutSession>[];

  TrainerHealthConnectSnapshot _snapshot(DateTime? date, String message) {
    final now = DateTime.now();
    final day = date ?? now;
    return TrainerHealthConnectSnapshot(
      id: 'health_connect_${day.year}_${day.month}_${day.day}',
      date: DateTime(day.year, day.month, day.day),
      checkedAt: now,
      sdkStatus: 'unsupported_platform',
      isAvailable: false,
      permissionsGranted: false,
      grantedPermissions: const <String>[],
      missingPermissions: const <String>[
        'Kroki',
        'Dystans',
        'Aktywne kcal',
        'Treningi',
        'Tętno',
        'Sen',
      ],
      steps: 0,
      distanceKm: 0,
      activeKcal: 0,
      workoutSessions: 0,
      workoutMinutes: 0,
      averageHeartRate: 0,
      heartRateSamples: 0,
      sleepMinutes: 0,
      availableData: const <String>[],
      missingData: const <String>[
        'Kroki',
        'Dystans',
        'Aktywne kcal',
        'Sesje treningowe',
        'Tętno',
        'Sen',
      ],
      errorMessage: message,
    );
  }
}
