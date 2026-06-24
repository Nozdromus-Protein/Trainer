import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trainer_models.dart';

class TrainerLocalData {
  const TrainerLocalData({
    required this.sessions,
    required this.plans,
    required this.customExercises,
    required this.exerciseLibraryPreferences,
    required this.activeWorkoutSession,
    required this.bodyMeasurements,
    required this.trainingImpacts,
    required this.activityEntries,
  });

  final List<WorkoutLog> sessions;
  final List<WorkoutPlan> plans;
  final List<Exercise> customExercises;
  final ExerciseLibraryPreferences exerciseLibraryPreferences;
  final ActiveWorkoutSession? activeWorkoutSession;
  final List<BodyMeasurement> bodyMeasurements;
  final List<TrainingImpact> trainingImpacts;
  final List<TrainerActivityEntry> activityEntries;
}

class TrainerLocalRepository {
  TrainerLocalRepository({SharedPreferences? preferences}) : _preferences = preferences;

  static const logsKey = 'workout_logs_v1';
  static const plansKey = 'workout_plans_v1';
  static const customExercisesKey = 'workout_custom_exercises_v1';
  static const exerciseLibraryPreferencesKey = 'exercise_library_preferences_v1';
  static const activeWorkoutSessionKey = 'active_workout_session_v1';
  static const bodyMeasurementsKey = 'body_measurements_v1';
  static const trainingImpactsKey = 'training_impacts_v1';
  static const activityEntriesKey = 'activity_entries_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async => _preferences ?? SharedPreferences.getInstance();

  Future<TrainerLocalData> load() async {
    final preferences = await _prefs;
    return TrainerLocalData(
      sessions: _decodeList(
        preferences.getString(logsKey),
        WorkoutLog.fromJson,
      ),
      plans: _decodeList(
        preferences.getString(plansKey),
        WorkoutPlan.fromJson,
      ),
      customExercises: _decodeList(
        preferences.getString(customExercisesKey),
        Exercise.fromJson,
      ),
      exerciseLibraryPreferences: _decodeObject(
        preferences.getString(exerciseLibraryPreferencesKey),
        ExerciseLibraryPreferences.fromJson,
        const ExerciseLibraryPreferences(),
      ),
      activeWorkoutSession: _decodeNullableObject(
        preferences.getString(activeWorkoutSessionKey),
        ActiveWorkoutSession.fromJson,
      ),
      bodyMeasurements: _decodeList(
        preferences.getString(bodyMeasurementsKey),
        BodyMeasurement.fromJson,
      ),
      trainingImpacts: _decodeList(
        preferences.getString(trainingImpactsKey),
        TrainingImpact.fromJson,
      ),
      activityEntries: _decodeList(
        preferences.getString(activityEntriesKey),
        TrainerActivityEntry.fromJson,
      ),
    );
  }

  Future<void> saveSessions(Iterable<WorkoutSession> sessions) async {
    final preferences = await _prefs;
    await preferences.setString(
      logsKey,
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
  }

  Future<void> savePlans(Iterable<WorkoutPlan> plans) async {
    final preferences = await _prefs;
    await preferences.setString(
      plansKey,
      jsonEncode(plans.map((plan) => plan.toJson()).toList()),
    );
  }

  Future<void> saveCustomExercises(Iterable<Exercise> exercises) async {
    final preferences = await _prefs;
    await preferences.setString(
      customExercisesKey,
      jsonEncode(exercises.map((exercise) => exercise.toJson()).toList()),
    );
  }

  Future<void> saveExerciseLibraryPreferences(
    ExerciseLibraryPreferences preferencesValue,
  ) async {
    final preferences = await _prefs;
    await preferences.setString(
      exerciseLibraryPreferencesKey,
      jsonEncode(preferencesValue.toJson()),
    );
  }

  Future<void> saveActiveWorkoutSession(
    ActiveWorkoutSession? activeWorkoutSession,
  ) async {
    final preferences = await _prefs;
    if (activeWorkoutSession == null) {
      await preferences.remove(activeWorkoutSessionKey);
      return;
    }
    await preferences.setString(
      activeWorkoutSessionKey,
      jsonEncode(activeWorkoutSession.toJson()),
    );
  }

  Future<void> saveBodyMeasurements(
    Iterable<BodyMeasurement> bodyMeasurements,
  ) async {
    final preferences = await _prefs;
    await preferences.setString(
      bodyMeasurementsKey,
      jsonEncode(
        bodyMeasurements.map((measurement) => measurement.toJson()).toList(),
      ),
    );
  }

  Future<void> saveTrainingImpacts(
    Iterable<TrainingImpact> trainingImpacts,
  ) async {
    final preferences = await _prefs;
    await preferences.setString(
      trainingImpactsKey,
      jsonEncode(
        trainingImpacts.map((impact) => impact.toJson()).toList(),
      ),
    );
  }

  Future<void> saveActivityEntries(
    Iterable<TrainerActivityEntry> activityEntries,
  ) async {
    final preferences = await _prefs;
    await preferences.setString(
      activityEntriesKey,
      jsonEncode(
        activityEntries.map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  List<T> _decodeList<T>(
    String? rawValue,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (rawValue == null || rawValue.trim().isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) return <T>[];
      final result = <T>[];
      for (final value in decoded.whereType<Map>()) {
        try {
          result.add(fromJson(Map<String, dynamic>.from(value)));
        } on Object {
          // Jeden uszkodzony rekord nie powinien blokować pozostałych danych.
        }
      }
      return result;
    } on Object {
      return <T>[];
    }
  }

  T _decodeObject<T>(
    String? rawValue,
    T Function(Map<String, dynamic> json) fromJson,
    T fallback,
  ) {
    if (rawValue == null || rawValue.trim().isEmpty) return fallback;
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) return fallback;
      return fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      return fallback;
    }
  }

  T? _decodeNullableObject<T>(
    String? rawValue,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (rawValue == null || rawValue.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      return null;
    }
  }
}
