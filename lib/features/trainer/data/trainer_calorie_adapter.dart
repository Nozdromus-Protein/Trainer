import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trainer_models.dart';

class TrainerCalorieLocalAdapter {
  const TrainerCalorieLocalAdapter({SharedPreferences? preferences}) : _preferences = preferences;

  static const impactQueueKey = 'trainer_calorie_bridge_training_impacts_v1';
  static const latestImpactKey = 'trainer_calorie_bridge_latest_impact_v1';

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

  List<TrainingImpact> _deduplicated(Iterable<TrainingImpact> impacts) {
    final byKey = <String, TrainingImpact>{};
    for (final impact in impacts) {
      byKey[impact.deduplicationKey] = impact;
    }
    final values = byKey.values.toList()..sort((left, right) => right.date.compareTo(left.date));
    return values;
  }
}
