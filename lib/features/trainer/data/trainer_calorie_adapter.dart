import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trainer_models.dart';

class TrainerCalorieLocalAdapter {
  const TrainerCalorieLocalAdapter({SharedPreferences? preferences}) : _preferences = preferences;

  static const impactQueueKey = 'trainer_calorie_bridge_training_impacts_v1';
  static const latestImpactKey = 'trainer_calorie_bridge_latest_impact_v1';
  static const dailyAdjustmentsKey = 'trainer_calorie_bridge_daily_adjustments_v1';
  static const dailyAdjustmentsUpdatedAtKey = 'trainer_calorie_bridge_daily_adjustments_at_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async => _preferences ?? SharedPreferences.getInstance();

  Future<void> publishTrainingImpacts(Iterable<TrainingImpact> impacts) async {
    final preferences = await _prefs;
    final unique = _deduplicated(impacts);
    final bridgePayload = unique.map((impact) => impact.toCalorieBridgeJson()).toList();
    await preferences.setString(impactQueueKey, jsonEncode(bridgePayload));
    if (unique.isNotEmpty) {
      await preferences.setString(latestImpactKey, jsonEncode(unique.first.toCalorieBridgeJson()));
    } else {
      await preferences.remove(latestImpactKey);
    }
  }

  Future<List<Map<String, dynamic>>> loadBridgePayload() async {
    final preferences = await _prefs;
    final rawValue = preferences.getString(impactQueueKey);
    if (rawValue == null || rawValue.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
    } on Object {
      return <Map<String, dynamic>>[];
    }
  }

  /// Publikuje pakiety korekty dnia (jeden na dzień, deduplikacja po dateKey).
  /// [nutritionTargets] — opcjonalne dzienne cele żywieniowe z docelowej
  /// sylwetki (kcal + makra); jadą w pełnym JSON-ie każdego pakietu (kolumna
  /// `payload` w ContentProviderze), więc nie wymagają zmian po stronie Kotlina.
  /// [bodySnapshot] — masa ciała, obwody i skład ciała: Licznik Kalorii
  /// pokazuje z tego zakładkę „Postęp" i NIE prowadzi własnego dziennika wagi.
  /// Zwraca moment publikacji — Trainer używa go jako statusu synchronizacji.
  Future<DateTime> publishDailyAdjustments(
    Iterable<TrainerDailyAdjustment> adjustments, {
    Map<String, dynamic>? nutritionTargets,
    Map<String, dynamic>? bodySnapshot,
  }) async {
    final preferences = await _prefs;
    final byDate = <String, TrainerDailyAdjustment>{};
    for (final adjustment in adjustments) {
      final existing = byDate[adjustment.dateKey];
      if (existing == null || adjustment.updatedAt.isAfter(existing.updatedAt)) {
        byDate[adjustment.dateKey] = adjustment;
      }
    }
    final sorted = byDate.values.toList()..sort((left, right) => right.date.compareTo(left.date));
    final payload = [
      for (final adjustment in sorted)
        {
          ...adjustment.toCalorieBridgeJson(),
          if (nutritionTargets != null) 'nutritionTargets': nutritionTargets,
          if (bodySnapshot != null) 'bodySnapshot': bodySnapshot,
        },
    ];
    final publishedAt = DateTime.now();
    await preferences.setString(dailyAdjustmentsKey, jsonEncode(payload));
    await preferences.setString(dailyAdjustmentsUpdatedAtKey, publishedAt.toIso8601String());
    return publishedAt;
  }

  /// Odczyt opublikowanych pakietów korekty dnia (diagnostyka / status w UI).
  Future<List<Map<String, dynamic>>> loadDailyAdjustmentsPayload() async {
    final preferences = await _prefs;
    final rawValue = preferences.getString(dailyAdjustmentsKey);
    if (rawValue == null || rawValue.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
    } on Object {
      return <Map<String, dynamic>>[];
    }
  }

  /// Ostatni moment publikacji pakietów korekty dnia (null = jeszcze nie było).
  Future<DateTime?> lastDailyAdjustmentsPublishedAt() async {
    final preferences = await _prefs;
    final raw = preferences.getString(dailyAdjustmentsUpdatedAtKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<TrainingImpact> _deduplicated(Iterable<TrainingImpact> impacts) {
    final byKey = <String, TrainingImpact>{};
    for (final impact in impacts) {
      byKey[impact.deduplicationKey] = impact;
    }
    final values = byKey.values.toList()..sort((left, right) => right.date.compareTo(left.date));
    return values;
  }
}
