import '../domain/trainer_models.dart';
import 'trainer_health_connect_service_stub.dart' if (dart.library.io) 'trainer_health_connect_service_io.dart' as implementation;

abstract class TrainerHealthConnectService {
  Future<TrainerHealthConnectSnapshot> checkStatus({DateTime? date});

  Future<TrainerHealthConnectSnapshot> requestPermissions({DateTime? date});

  Future<TrainerHealthConnectSnapshot> readDailyData({DateTime? date});

  /// Sesje treningowe (bieg/chód/rower…) z Health Connect dla danego dnia —
  /// do rozpoznawania aktywności i przeliczania na kcal (z deduplikacją).
  Future<List<TrainerHealthWorkoutSession>> readWorkoutSessions({DateTime? date});
}

TrainerHealthConnectService createTrainerHealthConnectService() => implementation.createTrainerHealthConnectService();
