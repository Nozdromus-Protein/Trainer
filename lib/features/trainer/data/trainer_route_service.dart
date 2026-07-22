import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../domain/trainer_models.dart';

/// Natywny kanał Trainera do Health Connect ("trainer/health_native",
/// MainActivity.kt): trasy GPS sesji oraz sesje treningowe z danymi
/// ZAREJESTROWANYMI przez zegarek (kcal/dystans/kroki/tętno w oknie sesji).
/// Plugin `health` nie udostępnia tras ani agregatów per sesja.
///
/// Defensywnie: web / brak implementacji / brak zgód → puste wyniki.
class TrainerRouteService {
  const TrainerRouteService._();

  static const MethodChannel _channel = MethodChannel('trainer/health_native');

  /// Sesje treningowe dnia z danymi zarejestrowanymi przez zegarek.
  /// Pusta lista → wołający używa ścieżki pluginu `health` jako fallback.
  static Future<List<TrainerHealthWorkoutSession>> readExerciseSessions(DateTime day) async {
    if (kIsWeb) return const <TrainerHealthWorkoutSession>[];
    try {
      String two(int value) => value.toString().padLeft(2, '0');
      final dateKey = '${day.year}-${two(day.month)}-${two(day.day)}';
      final raw = await _channel.invokeMethod<dynamic>(
        'readExerciseSessions',
        <String, dynamic>{'dateKey': dateKey},
      );
      if (raw is! List) return const <TrainerHealthWorkoutSession>[];
      final sessions = <TrainerHealthWorkoutSession>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final start = DateTime.tryParse(map['start']?.toString() ?? '');
        final end = DateTime.tryParse(map['end']?.toString() ?? '');
        if (start == null || end == null) continue;
        final distanceMeters = (map['distanceMeters'] as num?)?.toDouble() ?? 0;
        final hrSamples = <int>[];
        final rawSamples = map['hrSamples'];
        if (rawSamples is List) {
          for (final sample in rawSamples) {
            final bpm = (sample as num?)?.round() ?? 0;
            if (bpm > 30 && bpm < 250) hrSamples.add(bpm);
          }
        }
        sessions.add(TrainerHealthWorkoutSession(
          sourceId: map['uuid']?.toString() ?? '',
          activityType: map['type']?.toString() ?? '',
          start: start.toLocal(),
          end: end.toLocal(),
          energyKcal: ((map['activeKcal'] as num?)?.toDouble() ?? 0).clamp(0, 20000),
          distanceKm: distanceMeters <= 0 ? 0 : distanceMeters / 1000,
          sourceName: map['sourceName']?.toString() ?? '',
          steps: ((map['steps'] as num?)?.round() ?? 0).clamp(0, 200000),
          avgHeartRate: ((map['avgHr'] as num?)?.toDouble() ?? 0).clamp(0, 250),
          maxHeartRate: ((map['maxHr'] as num?)?.toDouble() ?? 0).clamp(0, 250),
          hrSamples: hrSamples,
        ));
      }
      return sessions;
    } catch (_) {
      return const <TrainerHealthWorkoutSession>[];
    }
  }

  /// Mapa: uuid sesji Health Connect → punkty trasy [lat, lng].
  static Future<Map<String, List<List<double>>>> readExerciseRoutes(DateTime day) async {
    if (kIsWeb) return const <String, List<List<double>>>{};
    try {
      String two(int value) => value.toString().padLeft(2, '0');
      final dateKey = '${day.year}-${two(day.month)}-${two(day.day)}';
      final raw = await _channel.invokeMethod<dynamic>(
        'readExerciseRoutes',
        <String, dynamic>{'dateKey': dateKey},
      );
      if (raw is! Map) return const <String, List<List<double>>>{};
      final routes = <String, List<List<double>>>{};
      raw.forEach((key, value) {
        if (value is! List) return;
        final points = <List<double>>[];
        for (final point in value) {
          if (point is! List || point.length < 2) continue;
          final lat = (point[0] as num?)?.toDouble();
          final lng = (point[1] as num?)?.toDouble();
          if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) continue;
          points.add([lat, lng]);
        }
        if (points.length >= 2) routes[key.toString()] = points;
      });
      return routes;
    } catch (_) {
      // MissingPluginException (testy/desktop) albo błąd natywny → bez tras.
      return const <String, List<List<double>>>{};
    }
  }
}
