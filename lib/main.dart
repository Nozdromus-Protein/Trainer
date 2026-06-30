import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'features/trainer/application/exercise_library_filter.dart';
import 'features/trainer/application/workout_plan_factory.dart';
import 'features/trainer/data/trainer_calorie_adapter.dart';
import 'features/trainer/data/trainer_health_connect_service.dart';
import 'features/trainer/data/trainer_local_repository.dart';
import 'features/trainer/domain/trainer_models.dart';

const String kAppName = 'Trainer';
const String kDefaultBackendUrl = 'https://trainer-rnnc.onrender.com/';
const List<String> kTrainingLevels = ['Początkujący', 'Średniozaawansowany', 'Zaawansowany'];
const List<String> kTrainingModes = ['Redukcja', 'Rekompozycja', 'Masa', 'Kondycja'];
const Map<String, int> kAccentPalette = {
  'Mięta': 0xFF24D6A3,
  'Lato': 0xFFFFB86B,
  'Premium Blue': 0xFF58A6FF,
  'Fiolet': 0xFFB388FF,
  'Czerwień': 0xFFFF6B6B,
};

String normalizeLevel(String value) {
  final v = value.trim().toLowerCase();
  if (v.contains('zaaw')) return 'Zaawansowany';
  if (v.contains('śred') || v.contains('sred') || v.contains('inter') || v.contains('mid')) return 'Średniozaawansowany';
  return 'Początkujący';
}

String normalizeTrainingMode(String value) {
  final v = value.trim().toLowerCase();
  if (v.contains('redu')) return 'Redukcja';
  if (v.contains('masa') || v.contains('bulk')) return 'Masa';
  if (v.contains('kond') || v.contains('wydol')) return 'Kondycja';
  return 'Rekompozycja';
}

String stripHtml(String input) {
  return input.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitnessApp());
}

class FitnessApp extends StatefulWidget {
  const FitnessApp({super.key});

  @override
  State<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends State<FitnessApp> {
  late final AppStore store;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    store = AppStore();
    store.load().then((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Colors.teal, false),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AppScope(
      store: store,
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final accent = Color(store.settings.accentColorValue);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: kAppName,
            theme: buildTheme(accent, false),
            darkTheme: buildTheme(accent, true),
            themeMode: store.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

ThemeData buildTheme(Color accent, bool dark) {
  final seed = accent;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF151B23) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
    ),
  );
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required Widget child}) : super(notifier: store, child: child);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }

  static AppStore read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class AppStore extends ChangeNotifier {
  AppStore({
    TrainerLocalRepository? trainerRepository,
    TrainerCalorieLocalAdapter? calorieAdapter,
    TrainerHealthConnectService? healthConnectService,
  })  : _trainerRepository = trainerRepository ?? TrainerLocalRepository(),
        _calorieAdapter = calorieAdapter ?? const TrainerCalorieLocalAdapter(),
        _healthConnectService = healthConnectService ?? createTrainerHealthConnectService();

  final TrainerLocalRepository _trainerRepository;
  final TrainerCalorieLocalAdapter _calorieAdapter;
  final TrainerHealthConnectService _healthConnectService;
  final List<WorkoutLog> logs = [];
  final List<WorkoutPlan> plans = [];
  final List<Exercise> customExercises = [];
  final List<BodyMeasurement> bodyMeasurements = [];
  final List<TrainingImpact> trainingImpacts = [];
  final List<TrainerActivityEntry> activityEntries = [];
  final List<TrainerHealthConnectSnapshot> healthConnectSnapshots = [];
  ExerciseLibraryPreferences exerciseLibraryPreferences = const ExerciseLibraryPreferences();
  ActiveWorkoutSession? activeWorkoutSession;
  AppSettings settings = AppSettings.defaults();
  DateTime selectedDate = DateTime.now();
  String? lastAiMessage;
  bool aiBusy = false;
  bool healthConnectBusy = false;
  final List<AiChatMessage> aiChatHistory = [];
  bool aiChatBusy = false;

  static const _settingsKey = 'workout_settings_v1';
  static const _warmupStatusKey = 'warmup_status_v1';
  static const _aiChatKey = 'ai_chat_history_v1';
  static const _workoutAiAnalysesKey = 'workout_ai_analyses_v1';

  final Map<String, WorkoutAiAnalysis> _workoutAiAnalyses = {};

  // Status rozgrzewki dla danej sesji treningowej: 'done' / 'skipped'.
  // Trzymany lokalnie, żeby karta rozgrzewki nie wracała po oznaczeniu.
  final Map<String, String> _warmupStatusBySession = {};

  Future<void> load() async {
    final trainerData = await _trainerRepository.load();
    logs
      ..clear()
      ..addAll(trainerData.sessions);
    plans
      ..clear()
      ..addAll(trainerData.plans);
    customExercises
      ..clear()
      ..addAll(trainerData.customExercises);
    bodyMeasurements
      ..clear()
      ..addAll(trainerData.bodyMeasurements);
    bodyMeasurements.sort((left, right) => right.date.compareTo(left.date));
    trainingImpacts
      ..clear()
      ..addAll(trainerData.trainingImpacts);
    trainingImpacts.sort((left, right) => right.date.compareTo(left.date));
    activityEntries
      ..clear()
      ..addAll(trainerData.activityEntries);
    activityEntries.sort((left, right) => right.date.compareTo(left.date));
    healthConnectSnapshots
      ..clear()
      ..addAll(trainerData.healthConnectSnapshots);
    healthConnectSnapshots.sort((left, right) => right.checkedAt.compareTo(left.checkedAt));
    exerciseLibraryPreferences = trainerData.exerciseLibraryPreferences;
    activeWorkoutSession = trainerData.activeWorkoutSession;
    if (activeWorkoutSession?.exercises.isEmpty ?? false) {
      activeWorkoutSession = null;
      await saveActiveWorkoutSession();
    }

    final prefs = await SharedPreferences.getInstance();
    final hasStoredPlans = prefs.containsKey(TrainerLocalRepository.plansKey);
    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null && rawSettings.isNotEmpty) {
      try {
        settings = AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawSettings)));
      } catch (_) {}
    }

    final rawWarmupStatus = prefs.getString(_warmupStatusKey);
    if (rawWarmupStatus != null && rawWarmupStatus.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawWarmupStatus);
        if (decoded is Map) {
          _warmupStatusBySession
            ..clear()
            ..addAll(
              decoded.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            );
        }
      } catch (_) {}
    }

    final rawAnalyses = prefs.getString(_workoutAiAnalysesKey);
    if (rawAnalyses != null && rawAnalyses.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAnalyses);
        if (decoded is Map) {
          _workoutAiAnalyses
            ..clear()
            ..addAll(
              decoded.map((k, v) => MapEntry(k.toString(), WorkoutAiAnalysis.fromJson(Map<String, dynamic>.from(v as Map)))),
            );
        }
      } catch (_) {}
    }

    final rawBackupAt = prefs.getString(_backupAtKey);
    if (rawBackupAt != null && rawBackupAt.isNotEmpty) {
      lastBackupAt = DateTime.tryParse(rawBackupAt);
    }

    final rawChat = prefs.getString(_aiChatKey);
    if (rawChat != null && rawChat.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawChat);
        if (decoded is List) {
          aiChatHistory
            ..clear()
            ..addAll(decoded.whereType<Map>().map((e) => AiChatMessage.fromJson(Map<String, dynamic>.from(e))));
        }
      } catch (_) {}
    }

    if (plans.isEmpty && !hasStoredPlans) {
      plans.add(createLocalWorkoutPlan(settings));
      await savePlans();
    } else if (plans.isNotEmpty) {
      final activeIndexes = <int>[
        for (var index = 0; index < plans.length; index++)
          if (plans[index].isActive) index,
      ];
      if (activeIndexes.length != 1) {
        final activeIndex = activeIndexes.isEmpty ? 0 : activeIndexes.first;
        for (var index = 0; index < plans.length; index++) {
          plans[index] = plans[index].copyWith(isActive: index == activeIndex);
        }
        await savePlans();
      }
    }
  }

  Future<void> saveAll() async {
    await saveLogs();
    await savePlans();
    await saveSettings();
    await saveCustomExercises();
    await saveExerciseLibraryPreferences();
    await saveActiveWorkoutSession();
    await saveBodyMeasurements();
    await saveTrainingImpacts();
    await saveActivityEntries();
    await saveHealthConnectSnapshots();
  }

  Future<void> saveLogs() async {
    await _trainerRepository.saveSessions(logs);
  }

  Future<void> savePlans() async {
    await _trainerRepository.savePlans(plans);
  }

  WorkoutPlan? get activeWorkoutPlan {
    for (final plan in plans) {
      if (plan.isActive) return plan;
    }
    return plans.isEmpty ? null : plans.first;
  }

  Future<void> addWorkoutPlan(WorkoutPlan plan) async {
    final shouldActivate = plans.isEmpty || plan.isActive;
    if (shouldActivate) {
      for (var index = 0; index < plans.length; index++) {
        plans[index] = plans[index].copyWith(isActive: false);
      }
    }
    plans.add(plan.copyWith(isActive: shouldActivate));
    await savePlans();
    notifyListeners();
  }

  Future<void> updateWorkoutPlan(WorkoutPlan updatedPlan) async {
    final index = plans.indexWhere((plan) => plan.id == updatedPlan.id);
    if (index < 0) return;
    if (updatedPlan.isActive) {
      for (var planIndex = 0; planIndex < plans.length; planIndex++) {
        plans[planIndex] = plans[planIndex].copyWith(isActive: false);
      }
    }
    plans[index] = updatedPlan;
    if (plans.isNotEmpty && !plans.any((plan) => plan.isActive)) {
      plans[index] = plans[index].copyWith(isActive: true);
    }
    await savePlans();
    notifyListeners();
  }

  Future<void> deleteWorkoutPlan(String planId) async {
    final removedWasActive = plans.any((plan) => plan.id == planId && plan.isActive);
    plans.removeWhere((plan) => plan.id == planId);
    if (removedWasActive && plans.isNotEmpty) {
      plans[0] = plans[0].copyWith(isActive: true);
    }
    await savePlans();
    notifyListeners();
  }

  Future<void> setActiveWorkoutPlan(String planId) async {
    final activeIndex = plans.indexWhere((plan) => plan.id == planId);
    if (activeIndex < 0) return;
    for (var index = 0; index < plans.length; index++) {
      plans[index] = plans[index].copyWith(isActive: index == activeIndex);
    }
    await savePlans();
    notifyListeners();
  }

  Future<WorkoutPlan?> duplicateWorkoutPlan(String planId) async {
    final source = plans.where((plan) => plan.id == planId);
    if (source.isEmpty) return null;
    final original = source.first;
    final copy = original.copyWith(
      id: 'plan_${idNow()}',
      name: '${original.name} — kopia',
      days: original.days
          .map(
            (day) => day.copyWith(
              items: day.items.map((item) => item.copyWith()).toList(),
            ),
          )
          .toList(),
      isActive: false,
    );
    plans.add(copy);
    await savePlans();
    notifyListeners();
    return copy;
  }

  Future<bool> copyWorkoutDay({
    required String planId,
    required int sourceWeekday,
    required int targetWeekday,
  }) async {
    final planIndex = plans.indexWhere((plan) => plan.id == planId);
    if (planIndex < 0 || sourceWeekday == targetWeekday) return false;
    final plan = plans[planIndex];
    final sourceDays = plan.days.where((day) => day.weekday == sourceWeekday);
    if (sourceDays.isEmpty) return false;
    final source = sourceDays.first;
    final copiedDay = source.copyWith(
      weekday: targetWeekday,
      title: '${source.title} — kopia',
      items: source.items.map((item) => item.copyWith()).toList(),
    );
    final updatedDays = [...plan.days];
    final targetIndex = updatedDays.indexWhere((day) => day.weekday == targetWeekday);
    if (targetIndex >= 0) {
      updatedDays[targetIndex] = copiedDay;
    } else {
      updatedDays.add(copiedDay);
    }
    updatedDays.sort((left, right) => left.weekday.compareTo(right.weekday));
    plans[planIndex] = plan.copyWith(days: updatedDays);
    await savePlans();
    notifyListeners();
    return true;
  }

  Future<void> upsertPlanItem({
    required String planId,
    required int weekday,
    required PlanItem item,
  }) async {
    final planIndex = plans.indexWhere((plan) => plan.id == planId);
    if (planIndex < 0) return;
    final plan = plans[planIndex];
    final dayIndex = plan.days.indexWhere((day) => day.weekday == weekday);
    if (dayIndex < 0) return;
    final day = plan.days[dayIndex];
    final items = [...day.items];
    final itemIndex = items.indexWhere((entry) => entry.exerciseId == item.exerciseId);
    if (itemIndex >= 0) {
      items[itemIndex] = item;
    } else {
      items.add(item);
    }
    final days = [...plan.days];
    days[dayIndex] = day.copyWith(items: items);
    plans[planIndex] = plan.copyWith(days: days);
    await savePlans();
    notifyListeners();
  }

  Future<void> removePlanItem({
    required String planId,
    required int weekday,
    required String exerciseId,
  }) async {
    final planIndex = plans.indexWhere((plan) => plan.id == planId);
    if (planIndex < 0) return;
    final plan = plans[planIndex];
    final dayIndex = plan.days.indexWhere((day) => day.weekday == weekday);
    if (dayIndex < 0) return;
    final day = plan.days[dayIndex];
    final days = [...plan.days];
    days[dayIndex] = day.copyWith(
      items: day.items.where((item) => item.exerciseId != exerciseId).toList(),
    );
    plans[planIndex] = plan.copyWith(days: days);
    await savePlans();
    notifyListeners();
  }

  // ===== Etap 28: postęp programu treningowego =====

  /// Oznacza/odznacza dzień programu jako ukończony i zapisuje postęp.
  Future<void> setPlanDayCompleted(
    String planId,
    int dayIndex, {
    bool completed = true,
  }) async {
    final index = plans.indexWhere((plan) => plan.id == planId);
    if (index < 0) return;
    final plan = plans[index];
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;
    final updated = {...plan.completedDays};
    if (completed) {
      updated.add(dayIndex);
    } else {
      updated.remove(dayIndex);
    }
    plans[index] = plan.copyWith(completedDays: updated);
    await savePlans();
    notifyListeners();
  }

  /// Czyści cały postęp programu (wszystkie dni stają się ponownie do zrobienia).
  Future<void> resetPlanProgress(String planId) async {
    final index = plans.indexWhere((plan) => plan.id == planId);
    if (index < 0) return;
    plans[index] = plans[index].copyWith(completedDays: const <int>{});
    await savePlans();
    notifyListeners();
  }

  /// Ustawia poziom programu (metadana nagłówka).
  Future<void> setPlanLevel(String planId, String level) async {
    final index = plans.indexWhere((plan) => plan.id == planId);
    if (index < 0) return;
    plans[index] = plans[index].copyWith(level: level);
    await savePlans();
    notifyListeners();
  }

  /// Włącza/wyłącza tryb „pozwól trenować dowolny dzień" (wyłącza blokowanie).
  Future<void> setPlanAllowAnyDay(String planId, bool value) async {
    final index = plans.indexWhere((plan) => plan.id == planId);
    if (index < 0) return;
    plans[index] = plans[index].copyWith(allowAnyDay: value);
    await savePlans();
    notifyListeners();
  }

  /// Podmienia listę ćwiczeń konkretnego dnia (po indeksie — bezpieczne dla
  /// programów liniowych, gdzie dni mogą powtarzać dzień tygodnia). Etap 29.
  Future<void> updatePlanDayItems(
    String planId,
    int dayIndex,
    List<PlanItem> items,
  ) async {
    final index = plans.indexWhere((plan) => plan.id == planId);
    if (index < 0) return;
    final plan = plans[index];
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;
    final days = [...plan.days];
    days[dayIndex] = days[dayIndex].copyWith(items: items);
    plans[index] = plan.copyWith(days: days);
    await savePlans();
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  /// Zwraca status rozgrzewki dla sesji ('done' / 'skipped') albo null,
  /// gdy użytkownik jeszcze nie zdecydował.
  String? warmupStatusForSession(String sessionId) =>
      _warmupStatusBySession[sessionId];

  /// Zapisuje status rozgrzewki dla sesji i utrwala go lokalnie.
  Future<void> setWarmupStatus(String sessionId, String status) async {
    if (sessionId.isEmpty) return;
    _warmupStatusBySession[sessionId] = status;
    // Ograniczamy rozmiar mapy, zachowując najnowsze wpisy (LinkedHashMap
    // trzyma kolejność wstawiania).
    const maxEntries = 40;
    if (_warmupStatusBySession.length > maxEntries) {
      final staleKeys = _warmupStatusBySession.keys
          .take(_warmupStatusBySession.length - maxEntries)
          .toList();
      for (final key in staleKeys) {
        _warmupStatusBySession.remove(key);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_warmupStatusKey, jsonEncode(_warmupStatusBySession));
    notifyListeners();
  }

  Future<void> saveCustomExercises() async {
    await _trainerRepository.saveCustomExercises(customExercises);
  }

  Future<void> saveBodyMeasurements() async {
    await _trainerRepository.saveBodyMeasurements(bodyMeasurements);
  }

  Future<void> saveTrainingImpacts() async {
    await _trainerRepository.saveTrainingImpacts(trainingImpacts);
    await _calorieAdapter.publishTrainingImpacts(trainingImpacts);
  }

  /// Ponownie publikuje most kalorii dla Licznika Kalorii (spalone kcal z treningów).
  Future<void> publishCalorieBridge() async {
    await _calorieAdapter.publishTrainingImpacts(trainingImpacts);
  }

  Future<void> saveActivityEntries() async {
    await _trainerRepository.saveActivityEntries(activityEntries);
  }

  Future<void> saveHealthConnectSnapshots() async {
    await _trainerRepository.saveHealthConnectSnapshots(healthConnectSnapshots);
  }

  Future<void> saveExerciseLibraryPreferences() async {
    await _trainerRepository.saveExerciseLibraryPreferences(
      exerciseLibraryPreferences,
    );
  }

  Future<void> saveActiveWorkoutSession() async {
    await _trainerRepository.saveActiveWorkoutSession(activeWorkoutSession);
  }

  Future<void> addCustomExercise(Exercise exercise) async {
    final cleaned = exercise.copyWith(source: exercise.source.isEmpty ? 'wger' : exercise.source);
    final index = customExercises.indexWhere((e) => e.id == cleaned.id);
    if (index >= 0) {
      customExercises[index] = cleaned;
    } else {
      customExercises.insert(0, cleaned);
    }
    await saveCustomExercises();
    notifyListeners();
  }

  Future<void> deleteCustomExercise(String id) async {
    customExercises.removeWhere((e) => e.id == id);
    await saveCustomExercises();
    notifyListeners();
  }

  Future<void> addBodyMeasurement(BodyMeasurement measurement) async {
    if (!measurement.hasAnyMeasurement && measurement.note.trim().isEmpty) {
      return;
    }
    bodyMeasurements.insert(0, measurement);
    bodyMeasurements.sort((left, right) => right.date.compareTo(left.date));
    await saveBodyMeasurements();
    notifyListeners();
  }

  Future<void> upsertTrainingImpact(TrainingImpact impact) async {
    final index = trainingImpacts.indexWhere((item) => item.deduplicationKey == impact.deduplicationKey || item.sessionId == impact.sessionId);
    if (index >= 0) {
      trainingImpacts[index] = impact;
    } else {
      trainingImpacts.insert(0, impact);
    }
    trainingImpacts.sort((left, right) => right.date.compareTo(left.date));
    await saveTrainingImpacts();
  }

  Future<void> upsertActivityEntry(TrainerActivityEntry entry) async {
    final index = activityEntries.indexWhere((item) => item.id == entry.id || item.stableActivityKey == entry.stableActivityKey);
    if (index >= 0) {
      activityEntries[index] = entry;
    } else {
      activityEntries.insert(0, entry);
    }
    activityEntries.sort((left, right) => right.date.compareTo(left.date));
    await saveActivityEntries();
    notifyListeners();
  }

  // --- Etap 20: backup, import i diagnostyka ---

  static const _backupKey = 'trainer_local_backup_v1';
  static const _backupAtKey = 'trainer_local_backup_at_v1';

  DateTime? lastBackupAt;

  /// Najnowszy moment zmiany danych w aplikacji — przybliżenie „ostatniego
  /// zapisu" bez ingerencji w pojedyncze metody save.
  DateTime? get lastDataActivityAt {
    final candidates = <DateTime>[
      for (final log in logs) log.date,
      for (final measurement in bodyMeasurements) measurement.date,
      for (final impact in trainingImpacts) impact.date,
      for (final snapshot in healthConnectSnapshots) snapshot.checkedAt,
      if (lastBackupAt != null) lastBackupAt!,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }

  /// Usuwa pojedynczą zarejestrowaną aktywność (np. błędny wpis kroków/biegu).
  Future<bool> removeActivityEntry(String id) async {
    final before = activityEntries.length;
    activityEntries.removeWhere((entry) => entry.id == id);
    if (activityEntries.length == before) return false;
    await saveActivityEntries();
    notifyListeners();
    return true;
  }

  /// Zwraca aktywności, które wyglądają na błędne (do ręcznej weryfikacji).
  /// Nic nie usuwa — tylko wykrywa podejrzane wpisy.
  List<TrainerActivityEntry> suspiciousActivityEntries() {
    final result = <TrainerActivityEntry>[];
    for (final entry in activityEntries) {
      final tooManyKcal = entry.estimatedKcal > 3000;
      final negative = entry.estimatedKcal < 0 || entry.steps < 0 || entry.distanceKm < 0;
      final absurdSteps = entry.steps > 80000;
      final absurdDistance = entry.distanceKm > 200;
      final stepsWithoutKcal = entry.steps > 5000 && entry.estimatedKcal == 0;
      if (tooManyKcal || negative || absurdSteps || absurdDistance || stepsWithoutKcal) {
        result.add(entry);
      }
    }
    return result;
  }

  /// Tworzy lokalną kopię wszystkich danych Trainera w SharedPreferences.
  Future<DateTime> createLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final payload = {
      'createdAt': now.toIso8601String(),
      'version': 1,
      'data': buildFullExport(this),
    };
    await prefs.setString(_backupKey, jsonEncode(payload));
    await prefs.setString(_backupAtKey, now.toIso8601String());
    lastBackupAt = now;
    notifyListeners();
    return now;
  }

  /// Czy istnieje zapisana lokalna kopia.
  Future<bool> hasLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupKey);
    return raw != null && raw.isNotEmpty;
  }

  /// Przywraca dane z lokalnej kopii. Zwraca false, gdy kopii brak lub jest błędna.
  Future<bool> restoreLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final data = decoded['data'];
      if (data is! Map) return false;
      return importFullData(Map<String, dynamic>.from(data));
    } catch (_) {
      return false;
    }
  }

  /// Importuje pełen zestaw danych Trainera z mapy JSON (np. z eksportu).
  /// Zwraca true, gdy import się powiódł. Nie usuwa danych przy błędzie.
  Future<bool> importFullData(Map<String, dynamic> data) async {
    try {
      // Parsujemy do tymczasowych list — jeśli coś jest błędne, nie ruszamy stanu.
      List<T> parseList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
        final raw = data[key];
        if (raw is! List) return <T>[];
        final out = <T>[];
        for (final item in raw.whereType<Map>()) {
          try {
            out.add(fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
        return out;
      }

      final newSettings = data['settings'] is Map ? AppSettings.fromJson(Map<String, dynamic>.from(data['settings'] as Map)) : null;
      final newLogs = parseList('logs', WorkoutLog.fromJson);
      final newPlans = parseList('plans', WorkoutPlan.fromJson);
      final newExercises = parseList('customExercises', Exercise.fromJson);
      final newMeasurements = parseList('bodyMeasurements', BodyMeasurement.fromJson);
      final newImpacts = parseList('trainingImpacts', TrainingImpact.fromJson);
      final newActivities = parseList('activityEntries', TrainerActivityEntry.fromJson);
      final newSnapshots = parseList('healthConnectSnapshots', TrainerHealthConnectSnapshot.fromJson);

      // Brak jakichkolwiek danych = nie ma czego importować.
      final hasAnything = newSettings != null ||
          newLogs.isNotEmpty ||
          newPlans.isNotEmpty ||
          newExercises.isNotEmpty ||
          newMeasurements.isNotEmpty;
      if (!hasAnything) return false;

      if (newSettings != null) settings = newSettings;
      logs
        ..clear()
        ..addAll(newLogs);
      if (newPlans.isNotEmpty) {
        plans
          ..clear()
          ..addAll(newPlans);
        if (!plans.any((p) => p.isActive)) {
          plans[0] = plans[0].copyWith(isActive: true);
        }
      }
      customExercises
        ..clear()
        ..addAll(newExercises);
      bodyMeasurements
        ..clear()
        ..addAll(newMeasurements)
        ..sort((a, b) => b.date.compareTo(a.date));
      trainingImpacts
        ..clear()
        ..addAll(newImpacts)
        ..sort((a, b) => b.date.compareTo(a.date));
      activityEntries
        ..clear()
        ..addAll(newActivities)
        ..sort((a, b) => b.date.compareTo(a.date));
      healthConnectSnapshots
        ..clear()
        ..addAll(newSnapshots)
        ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));

      await saveAll();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  TrainerHealthConnectSnapshot? get latestHealthConnectSnapshot {
    if (healthConnectSnapshots.isEmpty) return null;
    final sorted = [...healthConnectSnapshots]..sort((left, right) => right.checkedAt.compareTo(left.checkedAt));
    return sorted.first;
  }

  /// Etap 22: tylko-odczyt — snapshot Health Connect dla wskazanego dnia
  /// (np. wybranego na dashboardzie). Nie liczy nic od nowa.
  TrainerHealthConnectSnapshot? healthConnectSnapshotForDay(DateTime day) {
    TrainerHealthConnectSnapshot? best;
    for (final snapshot in healthConnectSnapshots) {
      if (sameDay(snapshot.date, day)) {
        if (best == null || snapshot.checkedAt.isAfter(best.checkedAt)) best = snapshot;
      }
    }
    return best;
  }

  /// Etap 22: tylko-odczyt — wpływ treningu (korekta dnia) dla wskazanego dnia.
  TrainingImpact? trainingImpactForDay(DateTime day) {
    for (final impact in trainingImpacts) {
      if (sameDay(impact.date, day)) return impact;
    }
    return null;
  }

  Future<TrainerHealthConnectSnapshot> checkHealthConnectStatus() async {
    return _runHealthConnectAction(
      () => _healthConnectService.checkStatus(date: selectedDate),
    );
  }

  Future<TrainerHealthConnectSnapshot> requestHealthConnectPermissions() async {
    return _runHealthConnectAction(
      () => _healthConnectService.requestPermissions(date: selectedDate),
    );
  }

  Future<TrainerHealthConnectSnapshot> readHealthConnectDailyData() async {
    return _runHealthConnectAction(
      () => _healthConnectService.readDailyData(date: selectedDate),
    );
  }

  Future<TrainerHealthConnectSnapshot> _runHealthConnectAction(
    Future<TrainerHealthConnectSnapshot> Function() action,
  ) async {
    healthConnectBusy = true;
    notifyListeners();
    try {
      final snapshot = await action();
      await upsertHealthConnectSnapshot(snapshot, notify: false);
      return snapshot;
    } finally {
      healthConnectBusy = false;
      notifyListeners();
    }
  }

  Future<void> upsertHealthConnectSnapshot(
    TrainerHealthConnectSnapshot snapshot, {
    bool notify = true,
  }) async {
    final index = healthConnectSnapshots.indexWhere(
      (item) => item.id == snapshot.id || item.dateKey == snapshot.dateKey,
    );
    if (index >= 0) {
      healthConnectSnapshots[index] = snapshot;
    } else {
      healthConnectSnapshots.insert(0, snapshot);
    }
    healthConnectSnapshots.sort((left, right) => right.checkedAt.compareTo(left.checkedAt));
    await saveHealthConnectSnapshots();
    if (notify) notifyListeners();
  }

  List<TrainerActivityEntry> activityInputsForDay(DateTime day) {
    final externalEntries = activityEntries.where((entry) => sameDay(entry.date, day)).toList();
    final strengthEntries = trainingImpacts.where((impact) => sameDay(impact.date, day)).map(TrainerActivityEntry.fromTrainingImpact).toList();
    return [...externalEntries, ...strengthEntries];
  }

  List<ActivityCreditDecision> activityCreditDecisionsForDay(DateTime day) {
    return resolveActivityCredits(activityInputsForDay(day));
  }

  bool isExerciseFavorite(String id) => exerciseLibraryPreferences.isFavorite(id);

  bool isExerciseHidden(String id) => exerciseLibraryPreferences.isHidden(id);

  Future<void> toggleExerciseFavorite(String id) async {
    final favorites = Set<String>.from(exerciseLibraryPreferences.favoriteExerciseIds);
    if (!favorites.add(id)) favorites.remove(id);
    exerciseLibraryPreferences = exerciseLibraryPreferences.copyWith(
      favoriteExerciseIds: favorites,
    );
    await saveExerciseLibraryPreferences();
    notifyListeners();
  }

  Future<void> setExerciseHidden(String id, bool hidden) async {
    final hiddenIds = Set<String>.from(exerciseLibraryPreferences.hiddenExerciseIds);
    if (hidden) {
      hiddenIds.add(id);
    } else {
      hiddenIds.remove(id);
    }
    exerciseLibraryPreferences = exerciseLibraryPreferences.copyWith(
      hiddenExerciseIds: hiddenIds,
    );
    await saveExerciseLibraryPreferences();
    notifyListeners();
  }

  Future<bool> addExerciseToPlan({
    required String exerciseId,
    required String planId,
    required int weekday,
  }) async {
    final planIndex = plans.indexWhere((plan) => plan.id == planId);
    if (planIndex < 0) return false;
    final plan = plans[planIndex];
    final dayIndex = plan.days.indexWhere((day) => day.weekday == weekday);
    if (dayIndex < 0) return false;
    final day = plan.days[dayIndex];
    if (day.items.any((item) => item.exerciseId == exerciseId)) {
      return false;
    }

    final exercise = ExerciseRepo.byId(exerciseId, customExercises);
    final updatedDay = day.copyWith(
      items: [
        ...day.items,
        PlanItem(
          exerciseId: exercise.id,
          sets: exercise.defaultSets,
          reps: exercise.defaultReps,
          durationSec: exercise.defaultDurationSec,
          note: 'Dodano z bazy ćwiczeń',
          suggestedWeightKg: 0,
          restSeconds: 90,
        ),
      ],
    );
    final updatedDays = [...plan.days];
    updatedDays[dayIndex] = updatedDay;
    plans[planIndex] = plan.copyWith(days: updatedDays);
    await savePlans();
    notifyListeners();
    return true;
  }

  void setSelectedDate(DateTime date) {
    selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await saveSettings();
    notifyListeners();
  }

  Future<void> addLog(WorkoutLog log) async {
    logs.insert(0, log);
    await saveLogs();
    notifyListeners();
  }

  Future<void> updateLog(WorkoutLog log) async {
    final i = logs.indexWhere((e) => e.id == log.id);
    if (i >= 0) {
      logs[i] = log;
      await saveLogs();
      notifyListeners();
    }
  }

  Future<void> deleteLog(String id) async {
    logs.removeWhere((e) => e.id == id);
    await saveLogs();
    notifyListeners();
  }

  Future<void> deleteLogsBySession(String sessionId) async {
    logs.removeWhere((log) => log.sessionId == sessionId);
    await saveLogs();
    notifyListeners();
  }

  Future<void> deleteHistoryEntry(String entryKey) async {
    if (entryKey.startsWith('session_')) {
      await deleteLogsBySession(entryKey.substring('session_'.length));
      return;
    }
    if (entryKey.startsWith('log_')) {
      await deleteLog(entryKey.substring('log_'.length));
    }
  }

  Future<void> updateWorkoutLogSet({
    required String logId,
    required String setId,
    required double weightKg,
    required int repetitions,
    required int rpe,
    required String note,
  }) async {
    final logIndex = logs.indexWhere((log) => log.id == logId);
    if (logIndex < 0) return;

    final log = logs[logIndex];
    if (log.workoutSets.isEmpty) {
      logs[logIndex] = log.copyWith(
        weightKg: math.max(0, weightKg).toDouble(),
        reps: math.max(0, repetitions),
        rpe: rpe.clamp(1, 10).toInt(),
        note: note.trim().isEmpty ? log.note : note.trim(),
      );
      await saveLogs();
      notifyListeners();
      return;
    }

    final setIndex = log.workoutSets.indexWhere((set) => set.id == setId);
    if (setIndex < 0) return;
    final updatedSets = [...log.workoutSets];
    updatedSets[setIndex] = updatedSets[setIndex].copyWith(
      weightKg: math.max(0, weightKg).toDouble(),
      repetitions: math.max(0, repetitions),
      rpe: rpe.clamp(1, 10).toInt(),
      note: note.trim(),
      isCompleted: true,
    );
    final completedSets = updatedSets.where((set) => set.isCompleted).toList();
    final aggregateSets = completedSets.isEmpty ? updatedSets : completedSets;
    final averageReps = (aggregateSets.fold<int>(0, (sum, set) => sum + set.repetitions) / aggregateSets.length).round();
    final averageWeight = aggregateSets.fold<double>(0, (sum, set) => sum + set.weightKg) / aggregateSets.length;
    final averageRpe = (aggregateSets.fold<int>(0, (sum, set) => sum + set.rpe) / aggregateSets.length).round();

    logs[logIndex] = log.copyWith(
      workoutSets: updatedSets,
      sets: completedSets.length,
      reps: averageReps,
      weightKg: averageWeight,
      rpe: averageRpe.clamp(1, 10).toInt(),
    );
    await saveLogs();
    notifyListeners();
  }

  Future<bool> startActiveWorkout({
    required WorkoutPlan plan,
    required WorkoutDay day,
    int? dayIndex,
  }) async {
    if (day.items.isEmpty) return false;
    // Wyznacz indeks dnia w programie (Etap 31): jawny → po tożsamości → po dniu+tytule.
    var resolvedDayIndex = dayIndex ?? -1;
    if (resolvedDayIndex < 0) {
      resolvedDayIndex = plan.days.indexWhere((entry) => identical(entry, day));
    }
    if (resolvedDayIndex < 0) {
      resolvedDayIndex = plan.days.indexWhere(
        (entry) => entry.weekday == day.weekday && entry.title == day.title,
      );
    }
    activeWorkoutSession = ActiveWorkoutSession(
      id: 'workout_${idNow()}',
      planId: plan.id,
      planName: plan.name,
      weekday: day.weekday,
      dayTitle: day.title,
      dayIndex: resolvedDayIndex,
      startedAt: DateTime.now(),
      currentExerciseIndex: 0,
      exercises: day.items
          .map(
            (item) => ActiveWorkoutExercise(
              exerciseId: item.exerciseId,
              plannedSets: item.sets,
              plannedReps: item.reps,
              suggestedWeightKg: item.suggestedWeightKg,
              restSeconds: item.restSeconds,
              note: item.note,
            ),
          )
          .toList(),
    );
    await saveActiveWorkoutSession();
    notifyListeners();
    return true;
  }

  Future<void> selectActiveWorkoutExercise(int index) async {
    final session = activeWorkoutSession;
    if (session == null || session.exercises.isEmpty) return;
    activeWorkoutSession = session.copyWith(
      currentExerciseIndex: index.clamp(0, session.exercises.length - 1),
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<bool> saveActiveWorkoutSet({
    required double weightKg,
    required int repetitions,
    required int rpe,
  }) async {
    final session = activeWorkoutSession;
    final exercise = session?.currentExercise;
    if (session == null || exercise == null) return false;
    if (exercise.completedSets.length >= exercise.plannedSets) return false;
    final exercises = [...session.exercises];
    final index = session.currentExerciseIndex;
    final updatedExercise = exercise.copyWith(
      completedSets: [
        ...exercise.completedSets,
        WorkoutSet(
          id: 'set_${idNow()}',
          order: exercise.completedSets.length + 1,
          repetitions: repetitions,
          weightKg: weightKg,
          durationSec: 0,
          rpe: rpe,
          isCompleted: true,
        ),
      ],
      isSkipped: false,
    );
    exercises[index] = updatedExercise;
    final exerciseDefinition = ExerciseRepo.byId(
      updatedExercise.exerciseId,
      customExercises,
    );
    final recommendation = workoutRestRecommendation(
      exerciseDefinition,
      updatedExercise,
    );
    activeWorkoutSession = session.copyWith(
      exercises: exercises,
      restTimerEndsAt: DateTime.now().add(Duration(seconds: recommendation.seconds)),
      restTimerRemainingSeconds: recommendation.seconds,
      restTimerTotalSeconds: recommendation.seconds,
      isRestTimerPaused: false,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
    return true;
  }

  Future<void> pauseActiveRestTimer() async {
    final session = activeWorkoutSession;
    if (session == null || session.isRestTimerPaused) return;
    final remaining = session.restSecondsRemaining();
    activeWorkoutSession = session.copyWith(
      restTimerRemainingSeconds: remaining,
      isRestTimerPaused: true,
      clearRestTimerEndsAt: true,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> resumeActiveRestTimer() async {
    final session = activeWorkoutSession;
    if (session == null || !session.isRestTimerPaused) return;
    final remaining = session.restTimerRemainingSeconds.clamp(0, 3600);
    if (remaining == 0) {
      await skipActiveRestTimer();
      return;
    }
    activeWorkoutSession = session.copyWith(
      restTimerEndsAt: DateTime.now().add(Duration(seconds: remaining)),
      restTimerRemainingSeconds: remaining,
      isRestTimerPaused: false,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> adjustActiveRestTimer(int deltaSeconds) async {
    final session = activeWorkoutSession;
    if (session == null) return;
    final remaining = (session.restSecondsRemaining() + deltaSeconds).clamp(0, 3600);
    if (remaining == 0) {
      await skipActiveRestTimer();
      return;
    }
    activeWorkoutSession = session.copyWith(
      restTimerEndsAt: session.isRestTimerPaused ? null : DateTime.now().add(Duration(seconds: remaining)),
      restTimerRemainingSeconds: remaining,
      restTimerTotalSeconds: math.max(
        remaining,
        session.restTimerTotalSeconds + deltaSeconds,
      ),
      isRestTimerPaused: session.isRestTimerPaused,
      clearRestTimerEndsAt: session.isRestTimerPaused,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> skipActiveRestTimer() async {
    final session = activeWorkoutSession;
    if (session == null) return;
    activeWorkoutSession = session.copyWith(
      restTimerRemainingSeconds: 0,
      restTimerTotalSeconds: 0,
      isRestTimerPaused: false,
      clearRestTimerEndsAt: true,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> updateActiveExerciseNote(String note) async {
    final session = activeWorkoutSession;
    final exercise = session?.currentExercise;
    if (session == null || exercise == null) return;
    final exercises = [...session.exercises];
    exercises[session.currentExerciseIndex] = exercise.copyWith(note: note.trim());
    activeWorkoutSession = session.copyWith(exercises: exercises);
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> updateActiveSessionNote(String note) async {
    final session = activeWorkoutSession;
    if (session == null) return;
    activeWorkoutSession = session.copyWith(note: note.trim());
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> replaceActiveWorkoutExercise(Exercise replacement) async {
    final session = activeWorkoutSession;
    final current = session?.currentExercise;
    if (session == null || current == null) return;
    final exercises = [...session.exercises];
    final completedSets = current.completedSets;
    var replacementExercise = current.copyWith(
      exerciseId: replacement.id,
      plannedSets: math.max(replacement.defaultSets, completedSets.length),
      plannedReps: replacement.defaultReps > 0 ? replacement.defaultReps : current.plannedReps,
      suggestedWeightKg: completedSets.isEmpty ? 0 : completedSets.last.weightKg,
      restSeconds: 90,
      completedSets: completedSets,
      isSkipped: false,
    );
    final recommendation = workoutRestRecommendation(
      replacement,
      replacementExercise,
    );
    replacementExercise = replacementExercise.copyWith(
      restSeconds: recommendation.seconds,
    );
    exercises[session.currentExerciseIndex] = replacementExercise;
    activeWorkoutSession = session.copyWith(exercises: exercises);
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> moveToNextActiveExercise({bool skipCurrent = false}) async {
    final session = activeWorkoutSession;
    if (session == null || session.exercises.isEmpty) return;
    final exercises = [...session.exercises];
    if (skipCurrent) {
      final current = exercises[session.currentExerciseIndex];
      exercises[session.currentExerciseIndex] = current.copyWith(isSkipped: true);
    }
    final nextIndex = math.min(
      session.currentExerciseIndex + 1,
      session.exercises.length - 1,
    );
    activeWorkoutSession = session.copyWith(
      exercises: exercises,
      currentExerciseIndex: nextIndex,
    );
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<void> discardActiveWorkout() async {
    activeWorkoutSession = null;
    await saveActiveWorkoutSession();
    notifyListeners();
  }

  Future<CompletedWorkoutSummary?> finishActiveWorkout() async {
    final session = activeWorkoutSession;
    if (session == null || session.completedSetCount == 0) return null;
    final endedAt = DateTime.now();
    final performed = session.exercises.where((exercise) => exercise.completedSets.isNotEmpty).toList();
    final durationSeconds = math.max(
      0,
      endedAt.difference(session.startedAt).inSeconds,
    );
    final baseDuration = performed.isEmpty ? 0 : durationSeconds ~/ performed.length;
    final durationRemainder = performed.isEmpty ? 0 : durationSeconds % performed.length;
    final sessionName = '${session.planName} · ${session.dayTitle}';
    final completedLogs = <WorkoutLog>[];

    for (var index = 0; index < performed.length; index++) {
      final activeExercise = performed[index];
      final exercise = ExerciseRepo.byId(
        activeExercise.exerciseId,
        customExercises,
      );
      final sets = activeExercise.completedSets;
      final assignedDuration = baseDuration + (index < durationRemainder ? 1 : 0);
      final averageReps = (sets.fold<int>(0, (sum, set) => sum + set.repetitions) / sets.length).round();
      final averageWeight = sets.fold<double>(0, (sum, set) => sum + set.weightKg) / sets.length;
      final averageRpe = (sets.fold<int>(0, (sum, set) => sum + set.rpe) / sets.length).round();
      final minutes = assignedDuration / 60;
      completedLogs.add(
        WorkoutLog(
          id: '${session.id}_${activeExercise.exerciseId}',
          exerciseId: activeExercise.exerciseId,
          date: endedAt,
          sets: sets.length,
          reps: averageReps,
          weightKg: averageWeight,
          durationSec: assignedDuration,
          rpe: averageRpe,
          calories: estimateCalories(
            met: exercise.met,
            weightKg: settings.bodyWeightKg,
            minutes: minutes,
          ),
          note: activeExercise.note,
          aiConfidence: 0,
          workoutSets: sets,
          sessionId: session.id,
          sessionName: sessionName,
          sessionStartedAt: session.startedAt,
          sessionEndedAt: endedAt,
          sessionNote: session.note,
        ),
      );
    }

    logs.removeWhere((log) => log.sessionId == session.id);
    logs.insertAll(0, completedLogs);
    await saveLogs();
    final impact = buildTrainingImpactForCompletedWorkout(
      session: session,
      completedLogs: completedLogs,
      settings: settings,
      endedAt: endedAt,
    );
    await upsertTrainingImpact(impact);

    // Etap 31: oznacz dzień programu jako ukończony (postęp + odblokowanie kolejnego).
    final skippedCount = session.exercises.where((exercise) => exercise.isSkipped).length;
    final dayIndex = session.dayIndex;
    var dayLabel = session.dayTitle;
    if (dayIndex >= 0) {
      final planIndex = plans.indexWhere((plan) => plan.id == session.planId);
      if (planIndex >= 0 && dayIndex < plans[planIndex].days.length) {
        dayLabel = 'Dzień ${dayIndex + 1}';
        final plan = plans[planIndex];
        if (!plan.completedDays.contains(dayIndex)) {
          plans[planIndex] = plan.copyWith(completedDays: {...plan.completedDays, dayIndex});
          await savePlans();
        }
      }
    }

    final summary = CompletedWorkoutSummary(
      sessionId: session.id,
      name: sessionName,
      startedAt: session.startedAt,
      endedAt: endedAt,
      exerciseCount: session.completedExerciseCount,
      setCount: session.completedSetCount,
      volume: session.volume,
      averageRpe: session.averageRpe,
      trainingImpact: impact,
      planId: session.planId,
      dayIndex: dayIndex,
      dayLabel: dayLabel,
      skippedCount: skippedCount,
    );
    activeWorkoutSession = null;
    await saveActiveWorkoutSession();
    notifyListeners();

    // Log pomocniczy po treningu: ćwiczenia, obciążone partie, wagi i % regeneracji.
    if (kDebugMode) {
      for (final log in completedLogs) {
        final exercise = ExerciseRepo.byId(log.exerciseId, customExercises);
        debugPrint('[Recovery] ${exercise.name} · serie ${log.sets} × ${log.reps}, RPE ${log.rpe}');
        for (final impact in exercise.effectiveMuscleImpacts) {
          debugPrint('   → ${impact.muscleGroup.label} [${impact.role.label}] waga ${impact.effectiveWeight}');
        }
      }
      muscleRecoveryMap().forEach((muscle, state) {
        debugPrint('[Recovery] ${muscle.label}: ${state.recoveryPercent?.toStringAsFixed(0)}% (${state.status.name})');
      });
    }
    return summary;
  }

  /// Etap 31: dopisuje informację zwrotną (ocena / ból) do notatki sesji w historii.
  Future<void> appendWorkoutSessionNote(String sessionId, String addition) async {
    final trimmed = addition.trim();
    if (trimmed.isEmpty) return;
    var changed = false;
    for (var index = 0; index < logs.length; index++) {
      final log = logs[index];
      if (log.sessionId != sessionId) continue;
      final existing = log.sessionNote.trim();
      if (existing.contains(trimmed)) continue;
      final combined = existing.isEmpty ? trimmed : '$existing\n$trimmed';
      logs[index] = log.copyWith(sessionNote: combined);
      changed = true;
    }
    if (changed) {
      await saveLogs();
      notifyListeners();
    }
  }

  List<WorkoutLog> logsForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return logs.where((e) => sameDay(e.date, d)).toList();
  }

  List<WorkoutLog> logsBetween(DateTime start, DateTime endInclusive) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(endInclusive.year, endInclusive.month, endInclusive.day, 23, 59, 59);
    return logs.where((e) => !e.date.isBefore(a) && !e.date.isAfter(b)).toList();
  }

  DayTotals totalsForDay(DateTime day) => DayTotals.from(logsForDay(day));

  /// Mapa regeneracji partii mięśniowych z historii treningów (Etap regeneracji).
  /// Puste, gdy brak danych — UI pokazuje wtedy wszystkie mięśnie jako szare/unknown.
  Map<BodyMuscle, MuscleRecoveryState> muscleRecoveryMap([DateTime? now]) {
    return RecoveryCalculator().compute(
      logs: logs,
      resolveExercise: (id) => ExerciseRepo.byId(id, customExercises),
      now: now,
    );
  }

  /// Suma dzisiaj spalonych kcal z treningów (Trainer), bez dublowania —
  /// korzysta z [trainingImpacts] z kluczem deduplikacji.
  int burnedKcalForDay(DateTime day) {
    var total = 0;
    for (final impact in trainingImpacts) {
      if (sameDay(impact.date, day)) total += impact.estimatedBurnedKcal;
    }
    return total;
  }

  /// Łączny czas treningów danego dnia (minuty), z zapisanych wpływów.
  int trainingMinutesForDay(DateTime day) {
    var total = 0;
    for (final impact in trainingImpacts) {
      if (sameDay(impact.date, day)) total += impact.durationMin;
    }
    return total;
  }

  Future<Map<String, dynamic>> analyzeWorkoutText(String text) async {
    aiBusy = true;
    lastAiMessage = null;
    notifyListeners();
    try {
      final api = AiBackendService(settings.backendUrl);
      final result = await api.analyzeWorkout({
        'description': text,
        'user': settings.toAiProfile(),
        'date': selectedDate.toIso8601String(),
      });
      lastAiMessage = prettyJson(result);
      return result;
    } catch (e) {
      lastAiMessage = 'Błąd AI: $e';
      rethrow;
    } finally {
      aiBusy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> generateAiPlan({required String goal, required int days, required String equipment, required String limitations}) async {
    aiBusy = true;
    lastAiMessage = null;
    notifyListeners();
    try {
      final api = AiBackendService(settings.backendUrl);
      final result = await api.generatePlan({
        'goal': goal,
        'days_per_week': days,
        'equipment': equipment,
        'limitations': limitations,
        'level': settings.level,
        'training_mode': settings.trainingMode,
        'user': settings.toAiProfile(),
      });
      lastAiMessage = prettyJson(result);
      final plan = WorkoutPlanFactory.fromAi(
        json: result,
        goal: goal,
        exercises: ExerciseRepo.combined(customExercises),
        fallback: () => createLocalWorkoutPlan(settings),
      );
      plans
        ..clear()
        ..add(plan);
      await savePlans();
      return result;
    } catch (e) {
      lastAiMessage = 'Błąd AI: $e';
      rethrow;
    } finally {
      aiBusy = false;
      notifyListeners();
    }
  }

  WorkoutAiAnalysis? workoutAiAnalysisFor(String sessionId) => _workoutAiAnalyses[sessionId];

  Future<void> _saveWorkoutAiAnalyses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _workoutAiAnalysesKey,
      jsonEncode(_workoutAiAnalyses.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<WorkoutAiAnalysis> analyzeCompletedWorkout(CompletedWorkoutSummary summary) async {
    aiBusy = true;
    notifyListeners();
    try {
      final sessionLogs = logs.where((l) => l.sessionId == summary.sessionId).toList();
      final exerciseDetails = sessionLogs.map((l) => {
        'exercise_id': l.exerciseId,
        'sets': l.sets,
        'reps': l.reps,
        'weight_kg': l.weightKg,
        'rpe': l.rpe,
        'duration_sec': l.durationSec,
        'calories': l.calories,
      }).toList();

      // Poprzednie treningi z ostatnich 7 dni jako kontekst historyczny
      final recentHistory = logsBetween(
        summary.startedAt.subtract(const Duration(days: 7)),
        summary.startedAt.subtract(const Duration(seconds: 1)),
      );
      final recentByDate = <String, List<WorkoutLog>>{};
      for (final l in recentHistory) {
        final k = l.date.toIso8601String().substring(0, 10);
        recentByDate.putIfAbsent(k, () => []).add(l);
      }

      final api = AiBackendService(settings.backendUrl);
      final result = await api.analyzeWorkout({
        'session': {
          'id': summary.sessionId,
          'name': summary.name,
          'started_at': summary.startedAt.toIso8601String(),
          'ended_at': summary.endedAt.toIso8601String(),
          'duration_minutes': summary.duration.inMinutes,
          'exercise_count': summary.exerciseCount,
          'set_count': summary.setCount,
          'volume_kg': summary.volume,
          'average_rpe': summary.averageRpe,
        },
        'exercises': exerciseDetails,
        'recent_history': recentByDate.entries.map((e) => {
          'date': e.key,
          'exercises': e.value.map((l) => {'id': l.exerciseId, 'sets': l.sets, 'reps': l.reps, 'weight_kg': l.weightKg}).toList(),
        }).toList(),
        'user': settings.toAiProfile(),
      });

      final analysis = WorkoutAiAnalysis.fromApiResult(summary.sessionId, result);
      _workoutAiAnalyses[summary.sessionId] = analysis;
      await _saveWorkoutAiAnalyses();
      notifyListeners();
      return analysis;
    } finally {
      aiBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveAiChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // Trzymaj max 100 ostatnich wiadomości
    final toSave = aiChatHistory.length > 100 ? aiChatHistory.sublist(aiChatHistory.length - 100) : aiChatHistory;
    await prefs.setString(_aiChatKey, jsonEncode(toSave.map((m) => m.toJson()).toList()));
  }

  Future<void> clearAiChatHistory() async {
    aiChatHistory.clear();
    await saveAiChatHistory();
    notifyListeners();
  }

  Future<void> chatWithAi(String userMessage) async {
    if (userMessage.trim().isEmpty) return;
    aiChatHistory.add(AiChatMessage(role: 'user', content: userMessage.trim(), timestamp: DateTime.now()));
    aiChatBusy = true;
    notifyListeners();
    try {
      final api = AiBackendService(settings.backendUrl);
      // Grupuj logi po dacie (ostatnie 5 dni z aktywnością)
      final logsByDate = <String, List<WorkoutLog>>{};
      for (final log in logs) {
        final key = log.date.toIso8601String().substring(0, 10);
        logsByDate.putIfAbsent(key, () => []).add(log);
      }
      final recentDays = logsByDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final recentLogs = recentDays.take(5).map((date) {
        final dayLogs = logsByDate[date]!;
        return {
          'date': date,
          'exercises': dayLogs.map((l) => {'id': l.exerciseId, 'sets': l.sets, 'reps': l.reps, 'weight_kg': l.weightKg}).toList(),
        };
      }).toList();
      final activePlan = activeWorkoutPlan;
      final result = await api.chat({
        'message': userMessage.trim(),
        'user': settings.toAiProfile(),
        'recent_logs': recentLogs,
        'active_plan': activePlan == null ? null : {
          'name': activePlan.name,
          'days': activePlan.days.map((d) => {'title': d.title, 'weekday': d.weekday, 'exercises': d.items.length}).toList(),
        },
        'history': aiChatHistory.length > 1
            ? aiChatHistory.sublist(math.max(0, aiChatHistory.length - 11), aiChatHistory.length - 1)
                .map((m) => {'role': m.role, 'content': m.content}).toList()
            : [],
      });
      final reply = (result['reply'] ?? result['message'] ?? result['content'] ?? result['response'] ?? result['answer'] ?? prettyJson(result)).toString().trim();
      aiChatHistory.add(AiChatMessage(role: 'assistant', content: reply, timestamp: DateTime.now()));
    } catch (e) {
      aiChatHistory.add(AiChatMessage(role: 'error', content: friendlyAiErrorMessage(e), timestamp: DateTime.now()));
    } finally {
      aiChatBusy = false;
      notifyListeners();
      await saveAiChatHistory();
    }
  }

  Future<void> generateLocalPlan() async {
    plans
      ..clear()
      ..add(createLocalWorkoutPlan(settings));
    await savePlans();
    notifyListeners();
  }
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String idNow() => DateTime.now().microsecondsSinceEpoch.toString();

// --- Etap 18: Sugestie progresji (lokalna logika) ---

enum ProgressionAction {
  increaseWeight,
  increaseReps,
  maintain,
  decreaseWeight,
  deload,
}

class ProgressionSuggestion {
  const ProgressionSuggestion({
    required this.action,
    required this.reason,
    required this.suggestedWeightKg,
    required this.suggestedReps,
    required this.currentWeightKg,
    required this.currentReps,
  });

  final ProgressionAction action;
  final String reason;
  final double suggestedWeightKg;
  final int suggestedReps;
  final double currentWeightKg;
  final int currentReps;

  String get label {
    switch (action) {
      case ProgressionAction.increaseWeight:
        return 'Zwiększ ciężar';
      case ProgressionAction.increaseReps:
        return 'Zwiększ powtórzenia';
      case ProgressionAction.maintain:
        return 'Utrzymaj';
      case ProgressionAction.decreaseWeight:
        return 'Zmniejsz ciężar';
      case ProgressionAction.deload:
        return 'Zrób deload';
    }
  }

  IconData get icon {
    switch (action) {
      case ProgressionAction.increaseWeight:
        return Icons.trending_up_rounded;
      case ProgressionAction.increaseReps:
        return Icons.add_circle_outline_rounded;
      case ProgressionAction.maintain:
        return Icons.remove_rounded;
      case ProgressionAction.decreaseWeight:
        return Icons.trending_down_rounded;
      case ProgressionAction.deload:
        return Icons.battery_charging_full_rounded;
    }
  }

  bool get hasNewValues => suggestedWeightKg != currentWeightKg || suggestedReps != currentReps;
}

/// Analizuje historię ćwiczenia i zwraca sugestię progresji.
/// Czysta lokalna logika — nie wywołuje AI ani sieci.
ProgressionSuggestion? progressionSuggestionForExercise({
  required String exerciseId,
  required List<WorkoutLog> allLogs,
  required int plannedReps,
  required double plannedWeightKg,
}) {
  // Pobierz logi tego ćwiczenia, max 20 ostatnich, posortowane od najnowszego
  final history = allLogs
      .where((l) => l.exerciseId == exerciseId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  if (history.isEmpty) return null;

  // Ostatnia sesja
  final latest = history.first;
  final currentWeight = latest.weightKg > 0 ? latest.weightKg : plannedWeightKg;
  final currentReps = latest.reps > 0 ? latest.reps : plannedReps;

  // Okno analizy: max 5 ostatnich sesji
  final window = history.take(5).toList();
  final avgRpe = window.isEmpty ? 0.0 : window.fold<double>(0, (s, l) => s + l.rpe) / window.length;
  final allCompletedReps = window.every((l) => l.reps >= plannedReps);
  final anyHighRpe = window.any((l) => l.rpe >= 9);

  // Stagnacja: min 4 sesje, ciężar nie wzrósł
  bool stagnant = false;
  if (history.length >= 4) {
    final older = history.sublist(1, math.min(5, history.length));
    final olderAvgWeight = older.fold<double>(0, (s, l) => s + l.weightKg) / older.length;
    stagnant = currentWeight <= olderAvgWeight && window.length >= 4;
  }

  // Reguły progresji:

  // 1. Zmęczenie / wysoki RPE → zmniejsz ciężar lub deload
  if (avgRpe >= 9.5 || (anyHighRpe && avgRpe >= 9.0)) {
    final newWeight = (currentWeight * 0.9).roundToDouble();
    return ProgressionSuggestion(
      action: ProgressionAction.decreaseWeight,
      reason: 'Średnie RPE ${avgRpe.toStringAsFixed(1)} — trening jest zbyt intensywny. Zmniejsz ciężar o ok. 10%.',
      suggestedWeightKg: newWeight > 0 ? newWeight : 0,
      suggestedReps: currentReps,
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  // 2. Deload: stagnacja + wysoki RPE lub długa historia bez wzrostu
  if (stagnant && avgRpe >= 8.0 && history.length >= 6) {
    final deloadWeight = (currentWeight * 0.8).roundToDouble();
    return ProgressionSuggestion(
      action: ProgressionAction.deload,
      reason: 'Brak progresu przez ostatnie ${window.length}+ sesje przy RPE ${avgRpe.toStringAsFixed(1)}. Tydzień deload (80% ciężaru) pomoże w regeneracji.',
      suggestedWeightKg: deloadWeight > 0 ? deloadWeight : 0,
      suggestedReps: math.max(6, (currentReps * 0.8).round()),
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  // 3. Niski RPE i pełne powtórzenia → zwiększ ciężar
  if ((avgRpe > 0 && avgRpe <= 7.0) && allCompletedReps && window.length >= 2) {
    final step = currentWeight < 10 ? 1.0 : currentWeight < 40 ? 2.5 : 5.0;
    final newWeight = currentWeight + step;
    return ProgressionSuggestion(
      action: ProgressionAction.increaseWeight,
      reason: 'RPE ${avgRpe.toStringAsFixed(1)} — jest rezerwa. Dodaj ${step.toStringAsFixed(step == step.roundToDouble() ? 0 : 1)} kg.',
      suggestedWeightKg: newWeight,
      suggestedReps: currentReps,
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  // 4. Dobry RPE, nieukończone powtórzenia → zwiększ powtórzenia, nie ciężar
  if (avgRpe > 0 && avgRpe <= 7.5 && !allCompletedReps && window.length >= 2) {
    final newReps = currentReps + 1;
    return ProgressionSuggestion(
      action: ProgressionAction.increaseReps,
      reason: 'Dobry RPE (${avgRpe.toStringAsFixed(1)}), ale nie wszystkie powtórzenia ukończone. Spróbuj dobić do $newReps powt. przed zwiększeniem ciężaru.',
      suggestedWeightKg: currentWeight,
      suggestedReps: newReps,
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  // 5. Stagnacja bez zbyt wysokiego RPE → zwiększ ciężar (delikatny krok)
  if (stagnant && avgRpe < 8.0) {
    final step = currentWeight < 20 ? 1.0 : 2.5;
    final newWeight = currentWeight + step;
    return ProgressionSuggestion(
      action: ProgressionAction.increaseWeight,
      reason: 'Stagnacja od ${window.length} sesji. Spróbuj zwiększyć ciężar o $step kg.',
      suggestedWeightKg: newWeight,
      suggestedReps: currentReps,
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  // 6. Utrzymaj — RPE 7–8, wszystko w porządku
  if (avgRpe >= 7.0 && avgRpe <= 8.5) {
    return ProgressionSuggestion(
      action: ProgressionAction.maintain,
      reason: 'RPE ${avgRpe.toStringAsFixed(1)} — optymalny zakres. Kontynuuj z aktualnym ciężarem.',
      suggestedWeightKg: currentWeight,
      suggestedReps: currentReps,
      currentWeightKg: currentWeight,
      currentReps: currentReps,
    );
  }

  return null;
}

// --- Etap 17: AI analiza treningu ---

class WorkoutAiAnalysis {
  const WorkoutAiAnalysis({
    required this.sessionId,
    required this.timestamp,
    required this.rating,
    required this.wentWell,
    required this.improvable,
    required this.increaseWeight,
    required this.fatigueWarning,
    required this.nextStep,
    required this.rawSummary,
  });

  final String sessionId;
  final DateTime timestamp;
  final String rating;
  final String wentWell;
  final String improvable;
  final String increaseWeight;
  final String fatigueWarning;
  final String nextStep;
  final String rawSummary;

  static WorkoutAiAnalysis fromApiResult(String sessionId, Map<String, dynamic> result) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = result[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final raw = (result['summary'] ?? result['analysis'] ?? result['message'] ?? result['reply'] ?? prettyJson(result)).toString().trim();
    return WorkoutAiAnalysis(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      rating: pick(['rating', 'ocena', 'score', 'grade']),
      wentWell: pick(['went_well', 'co_poszlo_dobrze', 'positives', 'strengths', 'dobre']),
      improvable: pick(['improvable', 'co_poprawic', 'improvements', 'weaknesses', 'poprawic']),
      increaseWeight: pick(['increase_weight', 'zwiekszac_ciezar', 'weight_recommendation', 'ciezar']),
      fatigueWarning: pick(['fatigue_warning', 'zmeczenie', 'recovery', 'regeneracja']),
      nextStep: pick(['next_step', 'nastepny_krok', 'recommendation', 'next', 'sugestia']),
      rawSummary: raw,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'timestamp': timestamp.toIso8601String(),
        'rating': rating,
        'wentWell': wentWell,
        'improvable': improvable,
        'increaseWeight': increaseWeight,
        'fatigueWarning': fatigueWarning,
        'nextStep': nextStep,
        'rawSummary': rawSummary,
      };

  factory WorkoutAiAnalysis.fromJson(Map<String, dynamic> json) => WorkoutAiAnalysis(
        sessionId: json['sessionId']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
        rating: json['rating']?.toString() ?? '',
        wentWell: json['wentWell']?.toString() ?? '',
        improvable: json['improvable']?.toString() ?? '',
        increaseWeight: json['increaseWeight']?.toString() ?? '',
        fatigueWarning: json['fatigueWarning']?.toString() ?? '',
        nextStep: json['nextStep']?.toString() ?? '',
        rawSummary: json['rawSummary']?.toString() ?? '',
      );
}

// --- Etap 16: AI Trainer czat ---

/// Zamienia techniczny błąd HTTP/sieci na czytelny komunikat dla użytkownika
/// AI Trainera. Obsługuje 404, 500 i timeout zgodnie z wymaganiami.
String friendlyAiErrorMessage(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (text.contains('404') || lower.contains('not found')) {
    return 'Endpoint AI Trainer nie istnieje na backendzie (404). Zaktualizuj/zdeployuj backend.';
  }
  if (text.contains('500') || text.contains('502') || text.contains('503') || lower.contains('server error')) {
    return 'Błąd serwera AI. Spróbuj ponownie za chwilę.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'Backend nie odpowiada. Sprawdź połączenie i spróbuj ponownie.';
  }
  if (lower.contains('socketexception') || lower.contains('failed host lookup') || lower.contains('connection')) {
    return 'Brak połączenia z backendem AI. Sprawdź internet.';
  }
  return 'Błąd połączenia z AI: $text';
}

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content, required this.timestamp});

  final String role; // 'user' | 'assistant' | 'error'
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {'role': role, 'content': content, 'timestamp': timestamp.toIso8601String()};

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        role: json['role']?.toString() ?? 'user',
        content: json['content']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      );
}

class WorkoutRestRecommendation {
  const WorkoutRestRecommendation({
    required this.seconds,
    required this.label,
  });

  final int seconds;
  final String label;
}

WorkoutRestRecommendation workoutRestRecommendation(
  Exercise exercise,
  ActiveWorkoutExercise activeExercise,
) {
  if (activeExercise.restSeconds != 90) {
    return WorkoutRestRecommendation(
      seconds: activeExercise.restSeconds.clamp(30, 600),
      label: 'Przerwa ustawiona w planie',
    );
  }
  final name = exercise.name.toLowerCase();
  final isStrength = activeExercise.plannedReps <= 6 || name.contains('martwy ciąg') || name.contains('deadlift');
  if (isStrength) {
    return const WorkoutRestRecommendation(
      seconds: 180,
      label: 'Ćwiczenie siłowe',
    );
  }
  const isolatedKeywords = [
    'uginanie',
    'curl',
    'prostowanie',
    'unoszenie bokiem',
    'lateral raise',
    'rozpięt',
    'wspięcia',
    'łydk',
    'triceps',
  ];
  if (isolatedKeywords.any(name.contains)) {
    return const WorkoutRestRecommendation(
      seconds: 60,
      label: 'Ćwiczenie izolowane',
    );
  }
  const compoundKeywords = [
    'przysiad',
    'squat',
    'wycisk',
    'bench',
    'podciąg',
    'pullup',
    'wiosł',
    'row',
    'wykrok',
    'lunge',
    'pomp',
    'dip',
    'hip thrust',
    'overhead',
  ];
  if (compoundKeywords.any(name.contains) || exercise.supportingMuscles.length >= 2) {
    return const WorkoutRestRecommendation(
      seconds: 120,
      label: 'Ćwiczenie wielostawowe',
    );
  }
  return const WorkoutRestRecommendation(
    seconds: 75,
    label: 'Ćwiczenie pomocnicze',
  );
}

String prettyJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

Map<String, dynamic>? asJsonMap(Object? value) {
  try {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}

String smartValue(dynamic value, {String fallback = '-'}) {
  if (value == null) return fallback;
  if (value is num) {
    final d = value.toDouble();
    return d == d.roundToDouble() ? d.round().toString() : d.toStringAsFixed(1);
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

List<String> smartStringList(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

String weekdayName(int weekday) {
  const names = {
    1: 'Poniedziałek',
    2: 'Wtorek',
    3: 'Środa',
    4: 'Czwartek',
    5: 'Piątek',
    6: 'Sobota',
    7: 'Niedziela',
  };
  return names[weekday] ?? 'Dzień';
}

String shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

class AppSettings {
  final double bodyWeightKg;
  final double heightCm;
  final int age;
  final String goal;
  final String level;
  final String trainingMode;
  final String equipment;
  final String limitations;
  final String backendUrl;
  final bool darkMode;
  final int accentColorValue;
  final List<int> trainingWeekdays;

  const AppSettings({
    required this.bodyWeightKg,
    required this.heightCm,
    required this.age,
    required this.goal,
    required this.level,
    required this.trainingMode,
    required this.equipment,
    required this.limitations,
    required this.backendUrl,
    required this.darkMode,
    required this.accentColorValue,
    required this.trainingWeekdays,
  });

  factory AppSettings.defaults() => const AppSettings(
        bodyWeightKg: 100,
        heightCm: 185,
        age: 28,
        goal: 'Rekompozycja / brzuch + masa mięśniowa',
        level: 'Średniozaawansowany',
        trainingMode: 'Rekompozycja',
        equipment: 'masa ciała, hantle, drążek, mata',
        limitations: '',
        backendUrl: kDefaultBackendUrl,
        darkMode: true,
        accentColorValue: 0xFF24D6A3,
        trainingWeekdays: [1, 2, 3, 4, 5, 6],
      );

  AppSettings copyWith({
    double? bodyWeightKg,
    double? heightCm,
    int? age,
    String? goal,
    String? level,
    String? trainingMode,
    String? equipment,
    String? limitations,
    String? backendUrl,
    bool? darkMode,
    int? accentColorValue,
    List<int>? trainingWeekdays,
  }) {
    return AppSettings(
      bodyWeightKg: bodyWeightKg ?? this.bodyWeightKg,
      heightCm: heightCm ?? this.heightCm,
      age: age ?? this.age,
      goal: goal ?? this.goal,
      level: level ?? this.level,
      trainingMode: trainingMode ?? this.trainingMode,
      equipment: equipment ?? this.equipment,
      limitations: limitations ?? this.limitations,
      backendUrl: backendUrl ?? this.backendUrl,
      darkMode: darkMode ?? this.darkMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      trainingWeekdays: trainingWeekdays ?? this.trainingWeekdays,
    );
  }

  Map<String, dynamic> toJson() => {
        'bodyWeightKg': bodyWeightKg,
        'heightCm': heightCm,
        'age': age,
        'goal': goal,
        'level': level,
        'trainingMode': trainingMode,
        'equipment': equipment,
        'limitations': limitations,
        'backendUrl': backendUrl,
        'darkMode': darkMode,
        'accentColorValue': accentColorValue,
        'trainingWeekdays': trainingWeekdays,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        bodyWeightKg: (json['bodyWeightKg'] as num?)?.toDouble() ?? 100,
        heightCm: (json['heightCm'] as num?)?.toDouble() ?? 185,
        age: (json['age'] as num?)?.toInt() ?? 28,
        goal: json['goal']?.toString() ?? 'Rekompozycja / brzuch + masa mięśniowa',
        level: normalizeLevel(json['level']?.toString() ?? 'Średniozaawansowany'),
        trainingMode: normalizeTrainingMode(json['trainingMode']?.toString() ?? json['mode']?.toString() ?? 'Rekompozycja'),
        equipment: json['equipment']?.toString() ?? 'masa ciała, hantle, drążek, mata',
        limitations: json['limitations']?.toString() ?? '',
        backendUrl: ((json['backendUrl']?.toString() ?? '').trim().isEmpty) ? kDefaultBackendUrl : json['backendUrl'].toString(),
        darkMode: json['darkMode'] as bool? ?? true,
        accentColorValue: (json['accentColorValue'] as num?)?.toInt() ?? 0xFF24D6A3,
        trainingWeekdays: ((json['trainingWeekdays'] as List?) ?? [1, 2, 3, 4, 5, 6]).map((e) => (e as num).toInt()).toList(),
      );

  Map<String, dynamic> toAiProfile() => {
        'body_weight_kg': bodyWeightKg,
        'height_cm': heightCm,
        'age': age,
        'goal': goal,
        'level': level,
        'trainingMode': trainingMode,
        'equipment': equipment,
        'limitations': limitations,
        'training_weekdays': trainingWeekdays,
      };
}

/// Instruktażowe wideo (asset) per ćwiczenie — odtwarzane w trakcie treningu.
/// Klucz = id ćwiczenia. Dodając kolejne ćwiczenia, dopisz tu plik wideo
/// (albo ustaw `videoPath` bezpośrednio w definicji ćwiczenia). Pliki leżą w
/// `assets/exercises/videos/` i są zadeklarowane w pubspec.yaml.
const Map<String, String> kExerciseVideoAssets = {
  'crunch': 'assets/exercises/videos/crunch.mp4',
  'hip_thrust': 'assets/exercises/videos/hip_thrust.mp4',
  'deadlift': 'assets/exercises/videos/deadlift.mp4',
  'pushup': 'assets/exercises/videos/pushup.mp4',
  'triceps_extension': 'assets/exercises/videos/triceps_extension.mp4',
  'bulgarian_split_squat': 'assets/exercises/videos/bulgarian_split_squat.mp4',
  'russian_twist': 'assets/exercises/videos/russian_twist.mp4',
  'lat_pulldown': 'assets/exercises/videos/lat_pulldown.mp4',
  'bicep_curl': 'assets/exercises/videos/bicep_curl.mp4',
  'lateral_raise': 'assets/exercises/videos/lateral_raise.mp4',
  'leg_raise': 'assets/exercises/videos/leg_raise.mp4',
  'row': 'assets/exercises/videos/row.mp4',
  'mountain_climber': 'assets/exercises/videos/mountain_climber.mp4',
  'shoulder_press': 'assets/exercises/videos/shoulder_press.mp4',
  'bench_press': 'assets/exercises/videos/bench_press.mp4',
  'lunge': 'assets/exercises/videos/lunge.mp4',
};

/// Wideo instruktażowe dla ćwiczenia o danym id (albo null).
String? exerciseVideoAsset(String id) => kExerciseVideoAssets[id];

class ExerciseRepo {
  static final List<Exercise> all = [
    Exercise(
      id: 'squat',
      name: 'Przysiad',
      category: 'Nogi',
      muscles: ['czworogłowe uda', 'pośladki', 'core'],
      equipment: 'masa ciała / sztanga / hantle',
      level: 'Początkujący',
      illustrationType: 'squat',
      description: 'Klasyczny ruch siadania i wstawania. Fundament pod nogi, pośladki i stabilizację brzucha.',
      tips: ['Stopy mniej więcej na szerokość barków.', 'Kolana prowadź w linii palców.', 'Napnij brzuch przed zejściem w dół.'],
      commonMistakes: ['Zapadanie kolan do środka.', 'Zaokrąglanie pleców.', 'Odrywanie pięt od podłoża.'],
      defaultSets: 4,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 5.0,
    ),
    Exercise(
      id: 'goblet_squat',
      name: 'Goblet squat',
      category: 'Nogi',
      muscles: ['czworogłowe uda', 'pośladki', 'core'],
      equipment: 'hantel / kettlebell',
      level: 'Początkujący',
      illustrationType: 'squat',
      description: 'Przysiad z ciężarem trzymanym przed klatką. Ułatwia utrzymanie pionowego tułowia.',
      tips: ['Trzymaj ciężar blisko mostka.', 'Łokcie prowadź między kolana.', 'Schodź tylko tak nisko, jak utrzymujesz neutralne plecy.'],
      commonMistakes: ['Uciekające pięty.', 'Opadanie klatki.', 'Za duży ciężar na start.'],
      defaultSets: 3,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 5.2,
    ),
    Exercise(
      id: 'front_squat',
      name: 'Front squat',
      category: 'Nogi',
      muscles: ['czworogłowe uda', 'core', 'górne plecy'],
      equipment: 'sztanga',
      level: 'Zaawansowany',
      illustrationType: 'squat',
      description: 'Przysiad ze sztangą z przodu. Mocno wymaga mobilności i stabilizacji tułowia.',
      tips: ['Łokcie wysoko.', 'Oddychaj i napnij brzuch przed zejściem.', 'Nie pozwól sztandze odjeżdżać od barków.'],
      commonMistakes: ['Opuszczanie łokci.', 'Zaokrąglanie górnych pleców.', 'Zbyt szybkie schodzenie.'],
      defaultSets: 4,
      defaultReps: 6,
      defaultDurationSec: 0,
      met: 6.5,
    ),
    Exercise(
      id: 'lunge',
      name: 'Wykroki',
      category: 'Nogi',
      muscles: ['pośladki', 'uda', 'core'],
      equipment: 'masa ciała / hantle',
      level: 'Początkujący',
      illustrationType: 'lunge',
      description: 'Ćwiczenie jednostronne poprawiające siłę nóg, równowagę i kontrolę bioder.',
      tips: ['Krok zrób na tyle długi, by kolano nie uciekało daleko przed stopę.', 'Tułów trzymaj stabilnie.', 'Odpychaj się całą stopą.'],
      commonMistakes: ['Chwianie bioder.', 'Zbyt krótki krok.', 'Kolano ucieka do środka.'],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 4.5,
    ),
    Exercise(
      id: 'reverse_lunge',
      name: 'Zakroki',
      category: 'Nogi',
      muscles: ['pośladki', 'uda', 'core'],
      equipment: 'masa ciała / hantle',
      level: 'Początkujący',
      illustrationType: 'lunge',
      description: 'Wersja wykroku robiona krokiem do tyłu. Często łagodniejsza dla kolan.',
      tips: ['Cofnij nogę spokojnie.', 'Przednia stopa zostaje stabilna.', 'Wracaj przez nacisk całej stopy.'],
      commonMistakes: ['Skręcanie bioder.', 'Odpychanie się palcami.', 'Za płytki zakres.'],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 4.5,
    ),
    Exercise(
      id: 'bulgarian_split_squat',
      name: 'Przysiad bułgarski',
      category: 'Nogi',
      muscles: ['pośladki', 'czworogłowe uda', 'core'],
      equipment: 'ławka / hantle',
      level: 'Średniozaawansowany',
      illustrationType: 'lunge',
      description: 'Jednostronne ćwiczenie z tylną nogą na podwyższeniu. Bardzo mocne na uda i pośladki.',
      tips: ['Ustaw stopę tak, żeby kolano szło stabilnie.', 'Zacznij bez ciężaru.', 'Kontroluj zejście.'],
      commonMistakes: ['Za blisko ławki.', 'Uciekanie kolana.', 'Zbyt duży ciężar.'],
      defaultSets: 3,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 6.0,
    ),
    Exercise(
      id: 'deadlift',
      name: 'Martwy ciąg rumuński',
      category: 'Tył ciała',
      muscles: ['dwugłowe uda', 'pośladki', 'prostowniki grzbietu'],
      equipment: 'sztanga / hantle',
      level: 'Średniozaawansowany',
      illustrationType: 'deadlift',
      description: 'Ruch zawiasu biodrowego. Bardzo dobry dla tylnej taśmy i kontroli pleców.',
      tips: ['Cofaj biodra, nie tylko pochylaj plecy.', 'Ciężar prowadź blisko nóg.', 'Plecy trzymaj neutralnie.'],
      commonMistakes: ['Zaokrąglanie pleców.', 'Zbyt głębokie zejście bez mobilności.', 'Przenoszenie ruchu na kolana zamiast bioder.'],
      defaultSets: 4,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 6.0,
    ),
    Exercise(
      id: 'hip_thrust',
      name: 'Hip thrust',
      category: 'Tył ciała',
      muscles: ['pośladki', 'dwugłowe uda', 'core'],
      equipment: 'ławka / sztanga / guma',
      level: 'Średniozaawansowany',
      illustrationType: 'hipThrust',
      description: 'Wypychanie bioder z oparciem pleców. Jedno z najlepszych ćwiczeń na pośladki.',
      tips: ['Broda lekko schowana.', 'Na górze dopnij pośladki.', 'Nie przeprostowuj lędźwi.'],
      commonMistakes: ['Ruch z pleców zamiast bioder.', 'Za wysoko ustawiona ławka.', 'Brak pauzy na górze.'],
      defaultSets: 4,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 5.5,
    ),
    Exercise(
      id: 'calf_raise',
      name: 'Wspięcia na palce',
      category: 'Nogi',
      muscles: ['łydki'],
      equipment: 'masa ciała / hantle / maszyna',
      level: 'Początkujący',
      illustrationType: 'calfRaise',
      description: 'Proste ćwiczenie na łydki. Działa najlepiej przy pełnym zakresie i kontroli.',
      tips: ['Zatrzymaj ruch na górze.', 'Schodź powoli.', 'Nie odbijaj się z dołu.'],
      commonMistakes: ['Krótki zakres.', 'Szarpanie.', 'Za szybkie tempo.'],
      defaultSets: 4,
      defaultReps: 15,
      defaultDurationSec: 0,
      met: 3.5,
    ),
    Exercise(
      id: 'pushup',
      name: 'Pompka',
      category: 'Klatka i ręce',
      muscles: ['klatka piersiowa', 'triceps', 'barki', 'core'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'pushup',
      description: 'Ruch wypychania ciała od podłoża. Świetny do budowania siły klatki, ramion i stabilizacji.',
      tips: ['Trzymaj ciało w jednej linii.', 'Łokcie prowadź lekko pod kątem.', 'Schodź kontrolowanie, wypychaj dynamicznie.'],
      commonMistakes: ['Opadanie bioder.', 'Zadzieranie głowy.', 'Za płytki zakres ruchu.'],
      defaultSets: 4,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 4.0,
    ),
    Exercise(
      id: 'incline_pushup',
      name: 'Pompka na podwyższeniu',
      category: 'Klatka i ręce',
      muscles: ['klatka piersiowa', 'triceps', 'barki'],
      equipment: 'ławka / blat',
      level: 'Początkujący',
      illustrationType: 'pushup',
      description: 'Łatwiejsza wersja pompki. Bardzo dobra do nauki napięcia i pełnego zakresu.',
      tips: ['Im wyżej dłonie, tym łatwiej.', 'Ciało trzymaj prosto.', 'Schodź klatką do podpory.'],
      commonMistakes: ['Uciekanie bioder.', 'Za krótki ruch.', 'Ręce za wysoko względem barków.'],
      defaultSets: 3,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 3.5,
    ),
    Exercise(
      id: 'bench_press',
      name: 'Wyciskanie leżąc',
      category: 'Klatka i ręce',
      muscles: ['klatka piersiowa', 'triceps', 'barki'],
      equipment: 'sztanga / ławka',
      level: 'Średniozaawansowany',
      illustrationType: 'benchPress',
      description: 'Klasyczne ćwiczenie siłowe na klatkę piersiową i triceps.',
      tips: ['Ściągnij łopatki.', 'Stopy stabilnie na ziemi.', 'Opuszczaj sztangę kontrolowanie.'],
      commonMistakes: ['Odbijanie sztangi.', 'Brak napięcia pleców.', 'Za szeroki chwyt.'],
      defaultSets: 4,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 5.0,
    ),
    Exercise(
      id: 'dips',
      name: 'Dipy',
      category: 'Klatka i ręce',
      muscles: ['triceps', 'klatka piersiowa', 'barki'],
      equipment: 'poręcze',
      level: 'Zaawansowany',
      illustrationType: 'dips',
      description: 'Mocne ćwiczenie na triceps i klatkę. Wymaga kontroli barków.',
      tips: ['Nie schodź niżej, niż pozwalają barki.', 'Trzymaj łopatki aktywne.', 'Kontroluj zejście.'],
      commonMistakes: ['Zbyt głębokie zejście.', 'Bujanie.', 'Ból z przodu barku ignorowany.'],
      defaultSets: 4,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 6.5,
    ),
    Exercise(
      id: 'pullup',
      name: 'Podciąganie',
      category: 'Plecy',
      muscles: ['najszerszy grzbietu', 'biceps', 'core'],
      equipment: 'drążek',
      level: 'Średniozaawansowany',
      illustrationType: 'pullUp',
      description: 'Mocne ćwiczenie na plecy i ręce. Można robić z gumą, negatywy albo pełne powtórzenia.',
      tips: ['Zacznij od aktywnych łopatek.', 'Nie bujaj ciałem.', 'Broda idzie nad drążek bez zadzierania szyi.'],
      commonMistakes: ['Szarpanie ruchem.', 'Brak pełnego wyprostu.', 'Bujanie nogami.'],
      defaultSets: 4,
      defaultReps: 6,
      defaultDurationSec: 0,
      met: 8.0,
    ),
    Exercise(
      id: 'assisted_pullup',
      name: 'Podciąganie z gumą',
      category: 'Plecy',
      muscles: ['najszerszy grzbietu', 'biceps'],
      equipment: 'drążek / guma',
      level: 'Początkujący',
      illustrationType: 'pullUp',
      description: 'Wersja naukowa podciągania z odciążeniem gumą.',
      tips: ['Najpierw aktywuj łopatki.', 'Nie odbijaj się z gumy.', 'Kontroluj opuszczanie.'],
      commonMistakes: ['Za mocna guma bez pracy mięśni.', 'Szarpanie.', 'Brak pełnego wyprostu.'],
      defaultSets: 4,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 5.5,
    ),
    Exercise(
      id: 'row',
      name: 'Wiosłowanie',
      category: 'Plecy',
      muscles: ['plecy', 'biceps', 'tył barków'],
      equipment: 'hantle / sztanga / wyciąg',
      level: 'Średniozaawansowany',
      illustrationType: 'row',
      description: 'Przyciąganie ciężaru w stronę tułowia. Buduje grubość pleców.',
      tips: ['Prowadź łokcie w tył.', 'Nie szarp lędźwiami.', 'Zatrzymaj ruch przy tułowiu.'],
      commonMistakes: ['Rwanie ciężarem.', 'Zaokrąglanie pleców.', 'Praca samymi rękami.'],
      defaultSets: 4,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 5.5,
    ),
    Exercise(
      id: 'lat_pulldown',
      name: 'Ściąganie drążka',
      category: 'Plecy',
      muscles: ['najszerszy grzbietu', 'biceps'],
      equipment: 'wyciąg górny',
      level: 'Początkujący',
      illustrationType: 'pullUp',
      description: 'Maszynowa alternatywa podciągania. Dobra do nauki pracy pleców.',
      tips: ['Ściągaj łokcie w dół.', 'Nie odchylaj się przesadnie.', 'Klatka lekko uniesiona.'],
      commonMistakes: ['Ciągnięcie za kark.', 'Bujanie tułowiem.', 'Za duży ciężar.'],
      defaultSets: 4,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 4.5,
    ),
    Exercise(
      id: 'face_pull',
      name: 'Face pull',
      category: 'Plecy',
      muscles: ['tył barków', 'górne plecy', 'rotatory'],
      equipment: 'wyciąg / guma',
      level: 'Początkujący',
      illustrationType: 'row',
      description: 'Ćwiczenie zdrowotne na tył barków i stabilizację łopatek.',
      tips: ['Ciągnij w stronę twarzy.', 'Łokcie wysoko.', 'Rób spokojnie i technicznie.'],
      commonMistakes: ['Za duży ciężar.', 'Przeprost lędźwi.', 'Brak kontroli łopatek.'],
      defaultSets: 3,
      defaultReps: 15,
      defaultDurationSec: 0,
      met: 3.5,
    ),
    Exercise(
      id: 'shoulder_press',
      name: 'Wyciskanie nad głowę',
      category: 'Barki',
      muscles: ['barki', 'triceps', 'core'],
      equipment: 'hantle / sztanga',
      level: 'Średniozaawansowany',
      illustrationType: 'shoulderPress',
      description: 'Ruch wypychania ciężaru nad głowę. Buduje barki, triceps i stabilizację.',
      tips: ['Napnij brzuch i pośladki.', 'Nie wyginaj mocno lędźwi.', 'Prowadź ciężar blisko pionu.'],
      commonMistakes: ['Przeprost pleców.', 'Zbyt szerokie łokcie.', 'Brak kontroli przy opuszczaniu.'],
      defaultSets: 4,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 5.5,
    ),
    Exercise(
      id: 'lateral_raise',
      name: 'Unoszenie bokiem',
      category: 'Barki',
      muscles: ['barki boczne'],
      equipment: 'hantle / linki',
      level: 'Początkujący',
      illustrationType: 'lateralRaise',
      description: 'Izolowane ćwiczenie na boczny akton barków.',
      tips: ['Unoszenie do okolic barków.', 'Łokieć lekko ugięty.', 'Nie bujaj tułowiem.'],
      commonMistakes: ['Za duży ciężar.', 'Szarpanie.', 'Unoszenie barków do uszu.'],
      defaultSets: 4,
      defaultReps: 15,
      defaultDurationSec: 0,
      met: 3.8,
    ),
    Exercise(
      id: 'bicep_curl',
      name: 'Uginanie ramion',
      category: 'Ręce',
      muscles: ['biceps', 'przedramię'],
      equipment: 'hantle / sztanga',
      level: 'Początkujący',
      illustrationType: 'bicepCurl',
      description: 'Izolowane ćwiczenie na biceps. Dobre jako dodatek do treningu góry ciała.',
      tips: ['Łokcie trzymaj blisko ciała.', 'Nie bujaj tułowiem.', 'Opuszczaj ciężar wolniej niż podnosisz.'],
      commonMistakes: ['Kołysanie ciałem.', 'Skracanie ruchu.', 'Zbyt duży ciężar.'],
      defaultSets: 3,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 3.5,
    ),
    Exercise(
      id: 'triceps_extension',
      name: 'Prostowanie ramion na triceps',
      category: 'Ręce',
      muscles: ['triceps'],
      equipment: 'wyciąg / guma / hantel',
      level: 'Początkujący',
      illustrationType: 'tricepsExtension',
      description: 'Izolowane ćwiczenie na triceps. Dobre na końcówkę treningu góry.',
      tips: ['Łokcie stabilnie przy ciele.', 'Dopnij triceps na dole.', 'Nie ruszaj barkami.'],
      commonMistakes: ['Bujanie tułowiem.', 'Uciekające łokcie.', 'Za duży ciężar.'],
      defaultSets: 3,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 3.5,
    ),
    Exercise(
      id: 'plank',
      name: 'Deska',
      category: 'Brzuch',
      muscles: ['prosty brzucha', 'poprzeczny brzucha', 'pośladki'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'plank',
      description: 'Izometryczne ćwiczenie stabilizacyjne. Buduje napięcie korpusu i kontrolę pozycji.',
      tips: ['Napnij brzuch jak przed ciosem.', 'Nie unoś bioder za wysoko.', 'Oddychaj spokojnie mimo napięcia.'],
      commonMistakes: ['Przeprost lędźwi.', 'Zbyt wysokie biodra.', 'Wstrzymywanie oddechu.'],
      defaultSets: 3,
      defaultReps: 0,
      defaultDurationSec: 45,
      met: 3.3,
    ),
    Exercise(
      id: 'side_plank',
      name: 'Deska bokiem',
      category: 'Brzuch',
      muscles: ['skośne brzucha', 'core', 'pośladki'],
      equipment: 'masa ciała / mata',
      level: 'Początkujący',
      illustrationType: 'plank',
      description: 'Stabilizacja boczna korpusu. Pomaga przy kontroli bioder i lędźwi.',
      tips: ['Biodra trzymaj wysoko.', 'Łokieć pod barkiem.', 'Ciało w jednej linii.'],
      commonMistakes: ['Opadanie bioder.', 'Skręcanie tułowia.', 'Napięta szyja.'],
      defaultSets: 3,
      defaultReps: 0,
      defaultDurationSec: 30,
      met: 3.2,
    ),
    Exercise(
      id: 'crunch',
      name: 'Spięcia brzucha',
      category: 'Brzuch',
      muscles: ['prosty brzucha'],
      equipment: 'mata',
      level: 'Początkujący',
      illustrationType: 'crunch',
      description: 'Proste ćwiczenie na kontrolowane spięcie brzucha bez ciągnięcia szyją.',
      tips: ['Patrz lekko w sufit.', 'Zwijaj żebra w stronę miednicy.', 'Nie szarp głowy rękami.'],
      commonMistakes: ['Ciągnięcie szyi.', 'Zbyt szybkie ruchy.', 'Brak napięcia na dole ruchu.'],
      defaultSets: 4,
      defaultReps: 15,
      defaultDurationSec: 0,
      met: 3.8,
    ),
    Exercise(
      id: 'leg_raise',
      name: 'Unoszenie nóg',
      category: 'Brzuch',
      muscles: ['dolna część brzucha', 'zginacze bioder'],
      equipment: 'mata / drążek',
      level: 'Średniozaawansowany',
      illustrationType: 'legRaise',
      description: 'Ćwiczenie na kontrolę miednicy i brzucha. Można robić leżąc lub w zwisie.',
      tips: ['Dociskaj lędźwie do maty.', 'Nie bujaj nogami.', 'Rób wolno.'],
      commonMistakes: ['Oderwane lędźwie.', 'Zamach nogami.', 'Ból w biodrach ignorowany.'],
      defaultSets: 4,
      defaultReps: 12,
      defaultDurationSec: 0,
      met: 4.0,
    ),
    Exercise(
      id: 'russian_twist',
      name: 'Russian twist',
      category: 'Brzuch',
      muscles: ['skośne brzucha', 'core'],
      equipment: 'masa ciała / piłka / talerz',
      level: 'Średniozaawansowany',
      illustrationType: 'russianTwist',
      description: 'Rotacyjne ćwiczenie na skośne brzucha. Najważniejsza jest kontrola, nie tempo.',
      tips: ['Plecy proste.', 'Obracaj tułów, nie tylko ręce.', 'Brzuch cały czas napięty.'],
      commonMistakes: ['Zaokrąglanie pleców.', 'Szarpanie.', 'Zbyt duży ciężar.'],
      defaultSets: 3,
      defaultReps: 20,
      defaultDurationSec: 0,
      met: 4.0,
    ),
    Exercise(
      id: 'hollow_hold',
      name: 'Hollow hold',
      category: 'Brzuch',
      muscles: ['core', 'prosty brzucha'],
      equipment: 'mata',
      level: 'Zaawansowany',
      illustrationType: 'hollowHold',
      description: 'Mocna pozycja gimnastyczna na napięcie całego brzucha.',
      tips: ['Lędźwie przyklejone do podłoża.', 'Dobierz wysokość nóg do możliwości.', 'Nie wstrzymuj oddechu.'],
      commonMistakes: ['Odrywanie lędźwi.', 'Za trudna wersja.', 'Napięta szyja.'],
      defaultSets: 4,
      defaultReps: 0,
      defaultDurationSec: 25,
      met: 4.0,
    ),
    Exercise(
      id: 'mountain_climber',
      name: 'Mountain climber',
      category: 'Brzuch i kardio',
      muscles: ['brzuch', 'barki', 'biodra'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'mountainClimber',
      description: 'Dynamiczne przyciąganie kolan w podporze. Dobre na kondycję i core.',
      tips: ['Dłonie pod barkami.', 'Nie unoś bioder zbyt wysoko.', 'Najpierw kontrola, potem tempo.'],
      commonMistakes: ['Bujanie biodrami.', 'Opadanie barków.', 'Za szybkie tempo od początku.'],
      defaultSets: 4,
      defaultReps: 0,
      defaultDurationSec: 40,
      met: 8.0,
    ),
    Exercise(
      id: 'jumping_jack',
      name: 'Pajacyki',
      category: 'Kardio',
      muscles: ['całe ciało', 'łydki', 'barki'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'jumpingJack',
      description: 'Lekki ruch kardio do rozgrzewki albo interwałów.',
      tips: ['Ląduj miękko.', 'Trzymaj rytm oddechu.', 'Nie spinaj barków.'],
      commonMistakes: ['Twarde lądowanie.', 'Zbyt szybki start bez rozgrzewki.', 'Brak kontroli kolan.'],
      defaultSets: 4,
      defaultReps: 0,
      defaultDurationSec: 45,
      met: 7.0,
    ),
    Exercise(
      id: 'burpee',
      name: 'Burpee',
      category: 'Kardio',
      muscles: ['całe ciało', 'klatka', 'nogi', 'core'],
      equipment: 'masa ciała',
      level: 'Średniozaawansowany',
      illustrationType: 'burpee',
      description: 'Intensywne ćwiczenie kondycyjne łączące zejście do podporu, pompkę i wyskok.',
      tips: ['Rób rytmicznie, nie chaotycznie.', 'Pilnuj pozycji pleców w podporze.', 'Skaluj wersję bez pompki, gdy technika siada.'],
      commonMistakes: ['Zapadanie bioder.', 'Brak oddechu.', 'Zbyt szybkie tempo kosztem techniki.'],
      defaultSets: 5,
      defaultReps: 8,
      defaultDurationSec: 0,
      met: 9.5,
    ),
    Exercise(
      id: 'high_knees',
      name: 'Bieg bokserski / high knees',
      category: 'Kardio',
      muscles: ['całe ciało', 'biodra', 'łydki'],
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'highKnees',
      description: 'Szybkie unoszenie kolan. Dobre do rozgrzewki i interwałów.',
      tips: ['Ląduj miękko.', 'Trzymaj rytm.', 'Nie pochylaj się mocno do tyłu.'],
      commonMistakes: ['Twarde lądowanie.', 'Za wysokie tempo na start.', 'Brak pracy rąk.'],
      defaultSets: 4,
      defaultReps: 0,
      defaultDurationSec: 40,
      met: 8.5,
    ),
    Exercise(
      id: 'jump_rope',
      name: 'Skakanka',
      category: 'Kardio',
      muscles: ['łydki', 'barki', 'core'],
      equipment: 'skakanka',
      level: 'Średniozaawansowany',
      illustrationType: 'jumpingJack',
      description: 'Kondycyjne ćwiczenie rytmu, pracy stóp i wydolności.',
      tips: ['Kręć głównie nadgarstkami.', 'Skacz nisko.', 'Ląduj na śródstopiu.'],
      commonMistakes: ['Za wysokie skoki.', 'Sztywne barki.', 'Za długa skakanka.'],
      defaultSets: 5,
      defaultReps: 0,
      defaultDurationSec: 60,
      met: 10.0,
    ),
    Exercise(
      id: 'bike',
      name: 'Rower / rower stacjonarny',
      category: 'Kardio',
      muscles: ['nogi', 'wydolność'],
      equipment: 'rower',
      level: 'Początkujący',
      illustrationType: 'bike',
      description: 'Kardio o łatwej regulacji intensywności. Dobre na dni lżejsze i redukcję.',
      tips: ['Dobierz kadencję bez przeciążania kolan.', 'Trzymaj równy oddech.', 'Zapisuj czas i intensywność.'],
      commonMistakes: ['Za ciężkie przełożenie.', 'Brak rozgrzewki.', 'Zgarbiona pozycja.'],
      defaultSets: 1,
      defaultReps: 0,
      defaultDurationSec: 1800,
      met: 7.0,
    ),
    Exercise(
      id: 'run',
      name: 'Bieganie',
      category: 'Kardio',
      muscles: ['nogi', 'core', 'wydolność'],
      equipment: 'buty do biegania',
      level: 'Średniozaawansowany',
      illustrationType: 'run',
      description: 'Trening kondycyjny. Możesz zapisywać czas, dystans w notatce i odczucie RPE.',
      tips: ['Zacznij spokojnie.', 'Pilnuj rytmu oddechu.', 'Nie zwiększaj objętości zbyt szybko.'],
      commonMistakes: ['Za szybkie tempo na starcie.', 'Brak regeneracji.', 'Ignorowanie bólu piszczeli/kolan.'],
      defaultSets: 1,
      defaultReps: 0,
      defaultDurationSec: 2400,
      met: 9.8,
    ),
    Exercise(
      id: 'pistol_squat',
      name: 'Pistol squat',
      category: 'Nogi',
      muscles: ['czworogłowe uda', 'pośladki', 'core'],
      equipment: 'masa ciała',
      level: 'Zaawansowany',
      illustrationType: 'squat',
      description: 'Przysiad na jednej nodze. Wymaga siły, mobilności i kontroli.',
      tips: ['Zacznij od wersji do boxa.', 'Trzymaj napięty core.', 'Kolano prowadź stabilnie.'],
      commonMistakes: ['Zbyt szybki progres.', 'Zapadanie kolana.', 'Utrata równowagi przez brak kontroli biodra.'],
      defaultSets: 4,
      defaultReps: 5,
      defaultDurationSec: 0,
      met: 6.8,
    ),
    // === Zestaw treningu brzucha (ćwiczenia czasowe) ===
    ..._abWorkoutExercises,
  ].map(_withLibraryMetadata).toList(growable: false);

  /// Pojedyncze ćwiczenie brzucha (czasowe) — wspólny szablon, by skrócić definicje.
  static Exercise _abExercise(
    String id,
    String name, {
    required int durationSec,
    required List<ExerciseMuscleImpact> impacts,
    List<String> muscles = const ['brzuch', 'core'],
    String illustration = 'crunch',
  }) {
    return Exercise(
      id: id,
      name: name,
      category: 'Brzuch',
      muscles: muscles,
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: illustration,
      description: 'Ćwiczenie czasowe na mięśnie brzucha. Utrzymuj napięcie korpusu i kontrolowane tempo.',
      tips: const ['Napnij brzuch przez cały czas.', 'Oddychaj równo, nie wstrzymuj oddechu.'],
      commonMistakes: const ['Zbyt szybkie, zamachowe tempo.', 'Odrywanie dolnego odcinka pleców.'],
      defaultSets: 1,
      defaultReps: 0,
      defaultDurationSec: durationSec,
      met: 4.0,
      muscleImpacts: impacts,
    );
  }

  /// Ćwiczenia brzucha ze zdjęć użytkownika (zestaw do trenowania od razu).
  static final List<Exercise> _abWorkoutExercises = [
    _abExercise('standing_bicycle_crunch', 'Standing Bicycle Crunches', durationSec: 56, illustration: 'crunch', impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.secondary),
    ]),
    _abExercise('flutter_kicks', 'Flutter Kicks', durationSec: 56, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.hipFlexors, role: MuscleRole.secondary),
    ]),
    _abExercise('windshield_wipers', 'Windshield Wipers', durationSec: 56, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.secondary),
    ]),
    _abExercise('plank_taps', 'Plank Taps', durationSec: 56, illustration: 'plank', muscles: const ['brzuch', 'barki', 'core'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.frontShoulders, role: MuscleRole.secondary),
    ]),
    _abExercise('alt_v_up', 'Alt V-Up', durationSec: 56, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.hipFlexors, role: MuscleRole.secondary),
    ]),
    _abExercise('side_crunch_left', 'Side Crunches Left', durationSec: 36, muscles: const ['skośne brzucha', 'core'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
    ]),
    _abExercise('side_crunch_right', 'Side Crunches Right', durationSec: 36, muscles: const ['skośne brzucha', 'core'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
    ]),
    _abExercise('crunches_legs_raised', 'Crunches With Legs Raised', durationSec: 56, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
    ]),
    _abExercise('plank_hip_dips', 'Plank Hip Dips', durationSec: 56, illustration: 'plank', muscles: const ['skośne brzucha', 'core'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.secondary),
    ]),
    _abExercise('crunch_90_90', '90/90 Crunch', durationSec: 56, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
    ]),
    _abExercise('oblique_crunch_reach', 'Oblique Crunch Reach', durationSec: 56, muscles: const ['skośne brzucha', 'brzuch', 'core'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.secondary),
    ]),
    _abExercise('double_knees_to_chest', 'Double Knees To Chest', durationSec: 36, impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.hipFlexors, role: MuscleRole.secondary),
    ]),
    _abExercise('lying_twist_stretch_left', 'Lying Twist Stretch Left', durationSec: 36, muscles: const ['skośne brzucha', 'dolny grzbiet'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
    ]),
    _abExercise('lying_twist_stretch_right', 'Lying Twist Stretch Right', durationSec: 36, muscles: const ['skośne brzucha', 'dolny grzbiet'], impacts: const [
      ExerciseMuscleImpact(muscleGroup: BodyMuscle.obliques, role: MuscleRole.primary),
    ]),
  ];

  /// Identyfikatory ćwiczeń wchodzących w skład gotowego treningu brzucha.
  static const List<String> abWorkoutSetIds = [
    'standing_bicycle_crunch',
    'flutter_kicks',
    'windshield_wipers',
    'plank_taps',
    'alt_v_up',
    'side_crunch_left',
    'side_crunch_right',
    'crunches_legs_raised',
    'plank_hip_dips',
    'crunch_90_90',
    'oblique_crunch_reach',
    'plank',
    'double_knees_to_chest',
    'lying_twist_stretch_left',
    'lying_twist_stretch_right',
  ];

  static List<Exercise> combined([List<Exercise> custom = const []]) {
    final byId = <String, Exercise>{
      for (final exercise in all) exercise.id: exercise,
    };
    for (final exercise in custom) {
      byId[exercise.id] = _withLibraryMetadata(exercise);
    }
    return byId.values.toList();
  }

  static Exercise byId(String id, [List<Exercise> custom = const []]) {
    final list = combined(custom);
    return list.firstWhere((e) => e.id == id, orElse: () => all.first);
  }

  static List<String> categories([List<Exercise> custom = const []]) {
    final set = combined(custom).map((e) => e.category).toSet().toList()..sort();
    return ['Wszystkie', ...set];
  }

  static List<Exercise> search(String query, String category, String level, [List<Exercise> custom = const []]) {
    final q = query.trim().toLowerCase();
    return combined(custom).where((e) {
      final matchesCategory = category == 'Wszystkie' || e.category == category;
      final matchesLevel = level == 'Wszystkie' || normalizeLevel(e.level) == level;
      final haystack = '${e.name} ${e.category} ${e.muscles.join(' ')} ${e.equipment} ${e.description}'.toLowerCase();
      final matchesQuery = q.isEmpty || haystack.contains(q);
      return matchesCategory && matchesLevel && matchesQuery;
    }).toList();
  }

  static Exercise _withLibraryMetadata(Exercise exercise) {
    return exercise.copyWith(
      // Etap 33: dołącz instruktażowe wideo (jeśli istnieje i nie ustawiono własnego).
      videoPath: exercise.videoPath ?? exerciseVideoAsset(exercise.id),
      trainingGoals: exercise.trainingGoals.isEmpty ? _goalsFor(exercise) : exercise.trainingGoals,
      avoidWhen: exercise.avoidWhen.isEmpty ? _avoidWhenFor(exercise) : exercise.avoidWhen,
      alternatives: exercise.alternatives.isEmpty ? _alternativesFor(exercise) : exercise.alternatives,
      executionSteps: exercise.executionSteps.isEmpty ? _executionStepsFor(exercise) : exercise.executionSteps,
      breathing: exercise.breathing.isEmpty ? _breathingFor(exercise) : exercise.breathing,
      tempo: exercise.tempo.isEmpty ? _tempoFor(exercise) : exercise.tempo,
      easierVersion: exercise.easierVersion.isEmpty ? _easierVersionFor(exercise) : exercise.easierVersion,
      harderVersion: exercise.harderVersion.isEmpty ? _harderVersionFor(exercise) : exercise.harderVersion,
    );
  }

  static List<String> _goalsFor(Exercise exercise) {
    final text = '${exercise.category} ${exercise.muscles.join(' ')}'.toLowerCase();
    if (text.contains('kardio') || text.contains('wydol') || text.contains('całe ciało')) {
      return const ['Kondycja', 'Redukcja'];
    }
    if (text.contains('brzuch') || text.contains('core')) {
      return const ['Stabilizacja', 'Siła'];
    }
    if (text.contains('bark') || text.contains('rotator')) {
      return const ['Masa mięśniowa', 'Stabilizacja'];
    }
    return const ['Siła', 'Masa mięśniowa'];
  }

  static List<String> _avoidWhenFor(Exercise exercise) {
    final text = '${exercise.category} ${exercise.muscles.join(' ')}'.toLowerCase();
    if (text.contains('kardio') || exercise.illustrationType == 'run') {
      return const [
        'Unikaj przy ostrym bólu stawów albo świeżym urazie kończyn dolnych.',
        'Przerwij przy zawrotach głowy, duszności lub bólu w klatce.',
      ];
    }
    if (text.contains('bark') || text.contains('klatka') || text.contains('triceps')) {
      return const [
        'Unikaj przy ostrym bólu barku, łokcia lub nadgarstka.',
        'Nie wykonuj zakresu, w którym tracisz kontrolę łopatki.',
      ];
    }
    if (text.contains('plec') || text.contains('grzbiet') || exercise.illustrationType == 'deadlift') {
      return const [
        'Unikaj przy ostrym bólu kręgosłupa lub promieniowaniu do kończyn.',
        'Nie zwiększaj ciężaru, jeśli nie utrzymujesz neutralnej pozycji pleców.',
      ];
    }
    return const [
      'Unikaj przy ostrym bólu trenowanej okolicy lub świeżym urazie.',
      'Przerwij ćwiczenie, gdy nie możesz utrzymać stabilnej techniki.',
    ];
  }

  static List<String> _alternativesFor(Exercise exercise) {
    final category = exercise.category.toLowerCase();
    if (category.contains('nogi') || category.contains('tył ciała')) {
      return const [
        'Przysiad do ławki',
        'Zakroki z podparciem',
        'Glute bridge',
      ];
    }
    if (category.contains('klatka') || category.contains('ręce')) {
      return const [
        'Pompka na podwyższeniu',
        'Wyciskanie hantli',
        'Wariant z gumą oporową',
      ];
    }
    if (category.contains('plecy')) {
      return const [
        'Wiosłowanie z gumą',
        'Ściąganie drążka wyciągu',
        'Wiosłowanie z podparciem',
      ];
    }
    if (category.contains('brzuch')) {
      return const ['Dead bug', 'Bird dog', 'Deska w łatwiejszym wariancie'];
    }
    if (category.contains('kardio')) {
      return const ['Szybki marsz', 'Rower stacjonarny', 'Orbitrek'];
    }
    return const [
      'Łatwiejszy wariant tego samego ruchu',
      'Wariant z gumą oporową',
      'Wariant bez dodatkowego ciężaru',
    ];
  }

  static List<String> _executionStepsFor(Exercise exercise) {
    final type = exercise.illustrationType.toLowerCase();
    if (exercise.defaultDurationSec > 0 && (type.contains('run') || type.contains('bike') || exercise.category.toLowerCase().contains('kardio'))) {
      return [
        'Ustaw bezpieczną pozycję i rozpocznij od spokojnego tempa.',
        'Utrzymuj stabilny tułów, swobodną pracę ramion i miękkie lądowanie lub płynny nacisk.',
        'Stopniowo wejdź na zaplanowaną intensywność bez gwałtownego przyspieszania.',
        'Zakończ spokojnym zwolnieniem tempa i wyrównaniem oddechu.',
      ];
    }
    if (exercise.defaultDurationSec > 0) {
      return [
        'Ustaw stawy w stabilnej pozycji i napnij mięśnie brzucha.',
        'Przyjmij pozycję opisaną dla ćwiczenia bez bólu i przeprostu.',
        'Utrzymuj równomierne napięcie przez zaplanowany czas.',
        'Zakończ pozycję spokojnie, bez nagłego rozluźnienia.',
      ];
    }
    if (type.contains('squat') || type.contains('lunge')) {
      return [
        'Ustaw stopy stabilnie i napnij brzuch przed rozpoczęciem ruchu.',
        'Rozpocznij zejście, prowadząc biodra i kolana zgodnie z kierunkiem palców stóp.',
        'Zejdź tylko do zakresu, w którym utrzymujesz neutralny tułów i pełną kontrolę.',
        'Odepchnij podłoże całą stopą i wróć do pozycji startowej bez blokowania kolan.',
      ];
    }
    if (type.contains('deadlift') || type.contains('row') || type.contains('hipthrust')) {
      return [
        'Ustaw ciężar blisko ciała, napnij brzuch i ustabilizuj łopatki.',
        'Rozpocznij ruch z bioder, utrzymując neutralną pozycję kręgosłupa.',
        'Wykonaj fazę główną bez szarpania i bez utraty napięcia tułowia.',
        'Wróć kontrolowanie, prowadząc ciężar tą samą drogą.',
      ];
    }
    if (type.contains('push') || type.contains('press') || type.contains('dips')) {
      return [
        'Ustaw dłonie i barki stabilnie, a łopatki utrzymuj pod kontrolą.',
        'Napnij brzuch i ustaw całe ciało w pewnej pozycji startowej.',
        'Wykonaj wypchnięcie bez unoszenia barków do uszu i bez przeprostu lędźwi.',
        'Wróć powoli do pozycji startowej, zachowując napięcie.',
      ];
    }
    if (type.contains('pull') || type.contains('curl')) {
      return [
        'Przyjmij stabilną pozycję i ustaw barki z dala od uszu.',
        'Rozpocznij ruch pracą docelowych mięśni, bez zamachu tułowiem.',
        'Doprowadź ruch do pełnego, bezbolesnego zakresu i krótko zatrzymaj napięcie.',
        'Opuść ciężar lub ciało wolniej, zachowując kontrolę.',
      ];
    }
    return [
      'Przyjmij stabilną pozycję startową i przygotuj potrzebny sprzęt.',
      'Napnij brzuch oraz ustaw stawy w naturalnej, bezbolesnej pozycji.',
      'Wykonaj ruch płynnie w pełnym kontrolowanym zakresie.',
      'Wróć spokojnie do pozycji startowej i powtórz bez utraty techniki.',
    ];
  }

  static String _breathingFor(Exercise exercise) {
    final text = '${exercise.category} ${exercise.illustrationType}'.toLowerCase();
    if (text.contains('kardio') || text.contains('run') || text.contains('bike')) {
      return 'Oddychaj rytmicznie i swobodnie. Nie wstrzymuj oddechu; przy większej intensywności dopasuj wydech do rytmu ruchu.';
    }
    if (exercise.defaultDurationSec > 0) {
      return 'Oddychaj spokojnie przez cały czas utrzymania pozycji. Krótki wydech pomaga ponownie napiąć brzuch bez rozluźniania sylwetki.';
    }
    return 'Weź wdech i ustabilizuj tułów przed fazą opuszczania. Wykonaj wydech podczas najtrudniejszej fazy ruchu.';
  }

  static String _tempoFor(Exercise exercise) {
    if (exercise.defaultDurationSec > 0) {
      return 'Stałe napięcie przez ${exercise.defaultDurationSec} s. Wejście i wyjście z pozycji wykonuj przez 2–3 sekundy.';
    }
    if (exercise.category.toLowerCase().contains('kardio')) {
      return 'Równe, kontrolowane tempo. Przyspieszaj dopiero po rozgrzewce i zwalniaj, gdy technika zaczyna się pogarszać.';
    }
    return '3–1–1: około 3 s fazy opuszczania, 1 s kontroli w najtrudniejszej pozycji i 1 s fazy podnoszenia.';
  }

  static String _easierVersionFor(Exercise exercise) {
    final type = exercise.illustrationType.toLowerCase();
    if (type.contains('push')) return 'Pompka na podwyższeniu lub z podparciem kolan.';
    if (type.contains('pull')) return 'Wariant z gumą oporową albo ściąganie drążka wyciągu.';
    if (type.contains('squat') || type.contains('lunge')) return 'Wariant do ławki lub z podparciem dłoni.';
    if (type.contains('deadlift')) return 'Ruch zawiasowy bez ciężaru albo z lekkimi hantlami.';
    if (exercise.defaultDurationSec > 0) return 'Skróć czas pracy i wybierz pozycję z większą liczbą punktów podparcia.';
    return 'Zmniejsz ciężar, zakres ruchu lub wykonaj wariant z podparciem.';
  }

  static String _harderVersionFor(Exercise exercise) {
    final type = exercise.illustrationType.toLowerCase();
    if (type.contains('push')) return 'Wariant z obciążeniem, wolniejszym opuszczaniem lub stopami na podwyższeniu.';
    if (type.contains('pull')) return 'Wariant bez pomocy, z pauzą w górze lub z dodatkowym obciążeniem.';
    if (type.contains('squat') || type.contains('lunge')) return 'Wariant jednostronny, z pauzą na dole albo dodatkowym obciążeniem.';
    if (type.contains('deadlift')) return 'Dodaj obciążenie lub wydłuż fazę opuszczania przy zachowaniu neutralnych pleców.';
    if (exercise.defaultDurationSec > 0) return 'Wydłuż czas pracy, ogranicz punkty podparcia lub dodaj lekkie obciążenie.';
    return 'Dodaj niewielkie obciążenie, pauzę albo wolniejszą fazę ekscentryczną.';
  }
}

WorkoutPlan createLocalWorkoutPlan(AppSettings settings) {
  return WorkoutPlanFactory.local(
    level: settings.level,
    goal: settings.goal,
    trainingWeekdays: settings.trainingWeekdays,
    exerciseById: ExerciseRepo.byId,
  );
}

extension WorkoutSessionExerciseResolver on WorkoutSession {
  Exercise exerciseFrom(List<Exercise> customExercises) {
    return ExerciseRepo.byId(exerciseId, customExercises);
  }
}

extension PlanItemExerciseResolver on PlanItem {
  Exercise exerciseFrom(List<Exercise> customExercises) {
    return ExerciseRepo.byId(exerciseId, customExercises);
  }
}

class DayTotals {
  final double calories;
  final int sets;
  final int reps;
  final int durationSec;
  final double volume;
  final int sessions;

  const DayTotals({
    required this.calories,
    required this.sets,
    required this.reps,
    required this.durationSec,
    required this.volume,
    required this.sessions,
  });

  factory DayTotals.from(List<WorkoutLog> logs) {
    return DayTotals(
      calories: logs.fold(0, (a, e) => a + e.calories),
      sets: logs.fold(0, (a, e) => a + e.sets),
      reps: logs.fold(0, (a, e) => a + e.reps * e.sets),
      durationSec: logs.fold(0, (a, e) => a + e.durationSec),
      volume: logs.fold(0, (a, e) => a + e.volume),
      sessions: logs.length,
    );
  }
}

class AiBackendService {
  final String baseUrl;

  AiBackendService(this.baseUrl);

  String get _cleanBase => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> analyzeWorkout(Map<String, dynamic> body) => _post(['/analyze-workout', '/workout/analyze'], body);

  Future<Map<String, dynamic>> generatePlan(Map<String, dynamic> body) => _post(['/generate-workout-plan', '/workout/generate-plan'], body);

  Future<Map<String, dynamic>> analyzeForm(Map<String, dynamic> body) => _post(['/analyze-exercise-form', '/workout/analyze-form'], body);

  Future<Map<String, dynamic>> chat(Map<String, dynamic> body) => _post(['/chat', '/ai/chat'], body);

  Future<Map<String, dynamic>> _post(List<String> paths, Map<String, dynamic> body) async {
    final base = _cleanBase.isEmpty ? kDefaultBackendUrl : _cleanBase;
    Object? lastError;
    for (final path in paths) {
      try {
        final uri = Uri.parse('$base$path');
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 35));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map<String, dynamic>) return data;
          return {'result': data};
        }
        lastError = 'HTTP ${response.statusCode}: ${response.body}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError ?? 'Nieznany błąd backendu');
  }
}

class WgerService {
  static const _base = 'https://wger.de/api/v2';

  Future<List<Exercise>> searchExercises(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse('$_base/exerciseinfo/?language=2&limit=24&term=${Uri.encodeQueryComponent(q)}');
    final response = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('wger API HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final results = (data is Map ? data['results'] : null) as List? ?? const [];
    return results.map((raw) => _fromWger(Map<String, dynamic>.from(raw as Map))).whereType<Exercise>().toList();
  }

  Exercise? _fromWger(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? item['uuid']?.toString() ?? idNow();
    final translations = (item['translations'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const [];
    final translation = translations.isNotEmpty ? translations.first : item;
    final name = (translation['name'] ?? item['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final description = stripHtml((translation['description'] ?? item['description'] ?? 'Opis z zewnętrznej bazy ćwiczeń.').toString());
    final category = _nameOf(item['category']).isEmpty ? _inferCategory(name, item) : _nameOf(item['category']);
    final muscles = _listNames(item['muscles']);
    final equipment = _listNames(item['equipment']).isEmpty ? 'brak danych' : _listNames(item['equipment']).join(' / ');
    final imageUrl = _firstImage(item['images']);
    final illustration = _inferIllustrationType(name, category);
    return Exercise(
      id: 'wger_$id',
      name: name,
      category: category,
      muscles: muscles.isEmpty ? ['całe ciało'] : muscles,
      equipment: equipment,
      level: 'Początkujący',
      illustrationType: illustration,
      description: description.isEmpty ? 'Ćwiczenie zaimportowane z wger. Uzupełnij opis albo użyj AI do doprecyzowania techniki.' : description,
      tips: ['Sprawdź technikę w slajdach ruchu.', 'Dobierz ciężar do poziomu i kontroli ruchu.', 'Przy bólu przerwij ćwiczenie i zmień wariant.'],
      commonMistakes: ['Za szybkie tempo.', 'Za duży ciężar kosztem zakresu ruchu.', 'Brak stabilizacji tułowia.'],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: _metForCategory(category),
      imageUrl: imageUrl,
      source: 'wger',
    );
  }

  String _nameOf(dynamic value) {
    if (value is Map) return (value['name'] ?? value['name_en'] ?? value['name_pl'] ?? '').toString();
    return value?.toString() ?? '';
  }

  List<String> _listNames(dynamic value) {
    if (value is List) {
      return value.map(_nameOf).where((e) => e.trim().isNotEmpty).toList();
    }
    final single = _nameOf(value);
    return single.isEmpty ? [] : [single];
  }

  String? _firstImage(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    for (final raw in value) {
      if (raw is Map) {
        final url = (raw['image'] ?? raw['url'] ?? raw['image_thumbnail'])?.toString();
        if (url != null && url.startsWith('http')) return url;
      }
    }
    return null;
  }

  String _inferCategory(String name, Map<String, dynamic> item) {
    final text = '${name.toLowerCase()} ${_listNames(item['muscles']).join(' ').toLowerCase()}';
    if (text.contains('leg') || text.contains('squat') || text.contains('calf') || text.contains('glute')) return 'Nogi';
    if (text.contains('back') || text.contains('row') || text.contains('pull')) return 'Plecy';
    if (text.contains('chest') || text.contains('push') || text.contains('bench')) return 'Klatka i ręce';
    if (text.contains('shoulder') || text.contains('deltoid')) return 'Barki';
    if (text.contains('abs') || text.contains('core') || text.contains('crunch')) return 'Brzuch';
    if (text.contains('cardio') || text.contains('run')) return 'Kardio';
    return 'Inne';
  }

  String _inferIllustrationType(String name, String category) {
    final t = '$name $category'.toLowerCase();
    if (t.contains('squat')) return 'squat';
    if (t.contains('lunge')) return 'lunge';
    if (t.contains('deadlift')) return 'deadlift';
    if (t.contains('thrust')) return 'hipThrust';
    if (t.contains('push') || t.contains('press-up')) return 'pushup';
    if (t.contains('bench')) return 'benchPress';
    if (t.contains('pull') || t.contains('chin')) return 'pullUp';
    if (t.contains('row')) return 'row';
    if (t.contains('curl')) return 'bicepCurl';
    if (t.contains('triceps')) return 'tricepsExtension';
    if (t.contains('plank')) return 'plank';
    if (t.contains('crunch')) return 'crunch';
    if (t.contains('raise')) return category == 'Barki' ? 'lateralRaise' : 'legRaise';
    if (t.contains('burpee')) return 'burpee';
    if (t.contains('run')) return 'run';
    if (t.contains('bike')) return 'bike';
    return 'generic';
  }

  double _metForCategory(String category) {
    final c = category.toLowerCase();
    if (c.contains('kardio')) return 7.0;
    if (c.contains('nogi') || c.contains('tył')) return 5.5;
    if (c.contains('plecy') || c.contains('klatka')) return 5.0;
    if (c.contains('brzuch')) return 3.8;
    return 4.5;
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Etap 21: wspólny sposób otwierania podstron Trainera ze spójnym AppBarem.
/// Zastępuje dawny prywatny launcher z dashboardu „Start".
void openTrainerSubPage(BuildContext context, Widget page, {String? title}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(toolbarHeight: 48, title: Text(title ?? kAppName)),
        body: SafeArea(child: page),
      ),
    ),
  );
}

/// Czy pełnoekranowy model regeneracji pokazano już w tym uruchomieniu aplikacji.
bool _recoveryStartupShown = false;

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    // Po starcie aplikacji pokaż raz pełnoekranowy model regeneracji mięśni.
    if (!_recoveryStartupShown) {
      _recoveryStartupShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openMuscleRecoveryPage(context);
      });
    }
  }

  // Etap 21: uporządkowane menu główne — 5 czytelnych zakładek.
  // Każdy ekran ma jeden jasny punkt wejścia (bez dublowania nawigacji).
  static const _pages = [
    TodayPage(),
    PlanPage(),
    ExercisesPage(),
    ProgressPage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey<int>(index),
            child: _pages[index],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today_rounded), label: 'Dzisiaj'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Trening'),
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Ćwiczenia'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Postęp'),
            NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more), label: 'Więcej'),
          ],
        ),
      ),
    );
  }
}

class TrainerHomePage extends StatelessWidget {
  const TrainerHomePage({
    super.key,
    required this.onToday,
    required this.onExercises,
    required this.onHistory,
    required this.onPlans,
    required this.onProgress,
    required this.onSettings,
  });

  final VoidCallback onToday;
  final VoidCallback onExercises;
  final VoidCallback onHistory;
  final VoidCallback onPlans;
  final VoidCallback onProgress;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final todayLogs = store.logsForDay(DateTime.now());
    final plan = store.activeWorkoutPlan;
    WorkoutDay? todayPlan;
    if (plan != null) {
      for (final day in plan.days) {
        if (day.weekday == DateTime.now().weekday) {
          todayPlan = day;
          break;
        }
      }
    }
    final hasActiveSession = store.activeWorkoutSession != null;
    final weekLogs = store.logsBetween(DateTime.now().subtract(const Duration(days: 6)), DateTime.now());
    final weekDays = weekLogs.map((l) => l.date.weekday).toSet().length;

    // Kolory akcentów per sekcja
    final mint = const Color(0xFF24D6A3);
    final blue = const Color(0xFF58A6FF);
    final amber = const Color(0xFFFFB86B);
    final purple = const Color(0xFFB388FF);
    final rose = const Color(0xFFFF6B6B);
    final cyan = const Color(0xFF26C6DA);

    final tiles = [
      TrainerHomeTileData(
        title: 'Dzisiejszy trening',
        subtitle: todayPlan == null ? 'Brak treningu w planie na dziś' : '${todayPlan.title} · ${todayPlan.items.length} ćwiczeń',
        icon: Icons.today_rounded,
        onTap: onToday,
        accentColor: mint,
        badge: hasActiveSession ? 'W TOKU' : (todayLogs.isNotEmpty ? 'GOTOWE' : null),
      ),
      TrainerHomeTileData(
        title: 'Baza ćwiczeń',
        subtitle: '${ExerciseRepo.combined(store.customExercises).length} ćwiczeń dostępnych lokalnie',
        icon: Icons.fitness_center_rounded,
        onTap: onExercises,
        accentColor: blue,
      ),
      TrainerHomeTileData(
        title: 'Historia',
        subtitle: store.logs.isEmpty ? 'Brak zapisanych wpisów' : '${store.logs.length} wpisów treningowych',
        icon: Icons.history_rounded,
        onTap: onHistory,
        accentColor: amber,
      ),
      TrainerHomeTileData(
        title: 'Plany treningowe',
        subtitle: store.plans.isEmpty ? 'Brak planów — wygeneruj z AI' : '${store.plans.length} ${store.plans.length == 1 ? 'plan' : 'planów'} · ${plan?.name ?? ''}',
        icon: Icons.calendar_month_rounded,
        onTap: onPlans,
        accentColor: purple,
      ),
      TrainerHomeTileData(
        title: 'Progres',
        subtitle: 'Podsumowanie treningów i sylwetka',
        icon: Icons.trending_up_rounded,
        onTap: onProgress,
        accentColor: rose,
      ),
      TrainerHomeTileData(
        title: 'Ustawienia',
        subtitle: 'Profil, wygląd i integracje',
        icon: Icons.tune_rounded,
        onTap: onSettings,
        accentColor: cyan,
      ),
    ];

    return PageFrame(
      title: 'Trainer',
      subtitle: 'Twój trening w jednym miejscu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero card — premium gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1A2E26), const Color(0xFF0D1B2A)]
                    : [scheme.primaryContainer, scheme.secondaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.15)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasActiveSession
                              ? 'Trening w toku ▶'
                              : todayLogs.isNotEmpty
                                  ? 'Świetna robota! 💪'
                                  : 'Gotowy na trening?',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          todayPlan != null
                              ? 'Dziś: ${todayPlan.title}'
                              : todayLogs.isNotEmpty
                                  ? '${todayLogs.length} ${todayLogs.length == 1 ? 'ćwiczenie' : 'ćwiczenia'} zapisane'
                                  : 'Otwórz plan lub dodaj wpis',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: (isDark ? Colors.white : scheme.onPrimaryContainer).withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _HeroBadge(
                              icon: Icons.local_fire_department_outlined,
                              label: '$weekDays dni w tyg.',
                              color: const Color(0xFFFF6B6B),
                            ),
                            const SizedBox(width: 8),
                            _HeroBadge(
                              icon: Icons.fitness_center_rounded,
                              label: '${store.logs.length} wpisów',
                              color: const Color(0xFF24D6A3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: onToday,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
                      ),
                      child: Icon(
                        hasActiveSession ? Icons.play_circle_rounded : Icons.directions_run_rounded,
                        color: scheme.primary,
                        size: 38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...tiles.map((tile) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TrainerHomeTile(data: tile),
          )),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class TrainerHomeTileData {
  const TrainerHomeTileData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accentColor,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accentColor;
  final String? badge;
}

class TrainerHomeTile extends StatelessWidget {
  const TrainerHomeTile({super.key, required this.data});

  final TrainerHomeTileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = data.accentColor ?? scheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: isDark ? 0.30 : 0.18),
                      accent.withValues(alpha: isDark ? 0.14 : 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: isDark ? 0.35 : 0.22), width: 1),
                ),
                child: Icon(data.icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (data.badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(data.badge!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  const PageFrame({super.key, required this.title, required this.subtitle, required this.child, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkoutHistoryPageContent();
  }
}

class WorkoutHistoryPageContent extends StatefulWidget {
  const WorkoutHistoryPageContent({super.key});

  @override
  State<WorkoutHistoryPageContent> createState() => _WorkoutHistoryPageContentState();
}

class _WorkoutHistoryPageContentState extends State<WorkoutHistoryPageContent> {
  final TextEditingController _planFilter = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _planFilter.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange(AppStore store) async {
    final now = DateTime.now();
    final oldestLogDate = store.logs.isEmpty ? DateTime(now.year - 5) : store.logs.map((log) => log.date).reduce((oldest, next) => next.isBefore(oldest) ? next : oldest);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(oldestLogDate.year, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Wybierz zakres historii',
      saveText: 'Zastosuj',
    );
    if (picked == null || !mounted) return;
    setState(() => _dateRange = picked);
  }

  void _clearFilters() {
    setState(() {
      _planFilter.clear();
      _dateRange = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final logs = [...store.logs]..sort((a, b) => b.date.compareTo(a.date));
    final allEntries = _groupTrainerWorkoutHistory(logs);
    final query = _planFilter.text.trim().toLowerCase();
    final entries = allEntries.where((entry) {
      final searchableText = '${entry.title(store.customExercises)} ${entry.subtitle(store.customExercises)}'.toLowerCase();
      final matchesName = query.isEmpty || searchableText.contains(query);
      return matchesName && _trainerHistoryEntryMatchesDateRange(entry, _dateRange);
    }).toList();

    return PageFrame(
      title: 'Historia treningów',
      subtitle: 'Wykonane sesje, szczegóły serii i lokalny zapis treningów',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Dodaj trening',
          onPressed: () => showAddWorkoutSheet(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: logs.isEmpty
          ? const _EmptyTrainerWorkoutHistoryCard()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TrainerWorkoutHistoryFiltersCard(
                  controller: _planFilter,
                  dateRange: _dateRange,
                  totalCount: allEntries.length,
                  visibleCount: entries.length,
                  onChanged: (_) => setState(() {}),
                  onPickDateRange: () => _pickDateRange(store),
                  onClear: _clearFilters,
                ),
                const SizedBox(height: 14),
                if (entries.isEmpty)
                  _NoTrainerWorkoutHistoryResultsCard(onClear: _clearFilters)
                else
                  for (var index = 0; index < entries.length; index++) ...[
                    if (index == 0 || !sameDay(entries[index - 1].date, entries[index].date)) ...[
                      if (index > 0) const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Text(
                          '${weekdayName(entries[index].date.weekday)} · ${trainerHistoryFullDate(entries[index].date)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                    _TrainerWorkoutHistoryEntryCard(
                      key: ValueKey('trainer_history_card_${entries[index].key}'),
                      entry: entries[index],
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
    );
  }
}

class _TrainerWorkoutHistoryFiltersCard extends StatelessWidget {
  const _TrainerWorkoutHistoryFiltersCard({
    required this.controller,
    required this.dateRange,
    required this.totalCount,
    required this.visibleCount,
    required this.onChanged,
    required this.onPickDateRange,
    required this.onClear,
  });

  final TextEditingController controller;
  final DateTimeRange? dateRange;
  final int totalCount;
  final int visibleCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onClear;

  bool get hasFilters => controller.text.trim().isNotEmpty || dateRange != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Filtry historii',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                MiniTag(text: '$visibleCount/$totalCount'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('history_plan_filter'),
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Nazwa planu lub dnia',
                hintText: 'Np. góra, push, redukcja',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('history_date_filter'),
                  onPressed: onPickDateRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(_trainerHistoryDateRangeLabel(dateRange)),
                ),
                if (hasFilters)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Wyczyść filtry'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrainerWorkoutHistoryCard extends StatelessWidget {
  const _EmptyTrainerWorkoutHistoryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Historia jest jeszcze pusta',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Po zakończeniu aktywnego treningu albo ręcznym dodaniu wpisu zobaczysz tutaj pełną historię.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showAddWorkoutSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Dodaj trening'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoTrainerWorkoutHistoryResultsCard extends StatelessWidget {
  const _NoTrainerWorkoutHistoryResultsCard({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.filter_alt_off_rounded, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              'Brak treningów dla tych filtrów',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Zmień zakres dat albo nazwę planu/dnia.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Wyczyść filtry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainerWorkoutHistoryEntry {
  const _TrainerWorkoutHistoryEntry({
    required this.key,
    required this.logs,
  });

  final String key;
  final List<WorkoutLog> logs;

  DateTime get date => logs.first.date;
  bool get isPlannedSession => logs.first.sessionId.isNotEmpty;

  String title(List<Exercise> customExercises) {
    final first = logs.first;
    if (first.sessionName.trim().isNotEmpty) return first.sessionName;
    return first.exerciseFrom(customExercises).name;
  }

  String subtitle(List<Exercise> customExercises) {
    if (logs.length == 1 && !isPlannedSession) return 'Wpis ręczny';
    return logs.map((log) => log.exerciseFrom(customExercises).name).join(' · ');
  }
}

List<_TrainerWorkoutHistoryEntry> _groupTrainerWorkoutHistory(List<WorkoutLog> sortedLogs) {
  final groups = <String, List<WorkoutLog>>{};
  for (final log in sortedLogs) {
    groups.putIfAbsent(_trainerHistoryEntryKeyForLog(log), () => <WorkoutLog>[]).add(log);
  }
  final entries = groups.entries
      .map(
        (entry) => _TrainerWorkoutHistoryEntry(
          key: entry.key,
          logs: entry.value,
        ),
      )
      .toList();
  entries.sort((left, right) => right.date.compareTo(left.date));
  return entries;
}

String _trainerHistoryEntryKeyForLog(WorkoutLog log) => log.sessionId.isEmpty ? 'log_${log.id}' : 'session_${log.sessionId}';

_TrainerWorkoutHistoryEntry? _findTrainerWorkoutHistoryEntry(AppStore store, String entryKey) {
  final logs = [...store.logs]..sort((a, b) => b.date.compareTo(a.date));
  for (final entry in _groupTrainerWorkoutHistory(logs)) {
    if (entry.key == entryKey) return entry;
  }
  return null;
}

bool _trainerHistoryEntryMatchesDateRange(_TrainerWorkoutHistoryEntry entry, DateTimeRange? range) {
  if (range == null) return true;
  final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}

String trainerHistoryFullDate(DateTime date) => '${shortDate(date)}.${date.year}';

String _trainerHistoryDateRangeLabel(DateTimeRange? range) {
  if (range == null) return 'Wszystkie daty';
  return '${trainerHistoryFullDate(range.start)} – ${trainerHistoryFullDate(range.end)}';
}

class _TrainerWorkoutHistoryStats {
  const _TrainerWorkoutHistoryStats({
    required this.duration,
    required this.exerciseCount,
    required this.setCount,
    required this.volume,
    required this.averageRpe,
  });

  final Duration duration;
  final int exerciseCount;
  final int setCount;
  final double volume;
  final double averageRpe;

  factory _TrainerWorkoutHistoryStats.fromLogs(List<WorkoutLog> logs) {
    final first = logs.first;
    final duration = first.sessionStartedAt != null && first.sessionEndedAt != null ? first.sessionEndedAt!.difference(first.sessionStartedAt!) : Duration(seconds: logs.fold<int>(0, (sum, log) => sum + log.durationSec));
    final setCount = logs.fold<int>(
      0,
      (sum, log) => sum + (log.workoutSets.isEmpty ? log.sets : log.workoutSets.where((set) => set.isCompleted).length),
    );
    final rpeSets = logs.expand((log) => log.workoutSets).where((set) => set.isCompleted && set.rpe > 0).toList();
    var aggregateRpe = 0;
    var aggregateRpeCount = 0;
    for (final log in logs) {
      final count = math.max(1, log.sets);
      aggregateRpe += log.rpe * count;
      aggregateRpeCount += count;
    }
    final averageRpe = rpeSets.isNotEmpty
        ? rpeSets.fold<int>(0, (sum, set) => sum + set.rpe) / rpeSets.length
        : aggregateRpeCount == 0
            ? 0.0
            : aggregateRpe / aggregateRpeCount;
    return _TrainerWorkoutHistoryStats(
      duration: duration,
      exerciseCount: logs.length,
      setCount: setCount,
      volume: logs.fold<double>(0, (sum, log) => sum + log.volume),
      averageRpe: averageRpe,
    );
  }
}

class _TrainerWorkoutHistoryEntryCard extends StatelessWidget {
  const _TrainerWorkoutHistoryEntryCard({
    super.key,
    required this.entry,
  });

  final _TrainerWorkoutHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final stats = _TrainerWorkoutHistoryStats.fromLogs(entry.logs);
    final title = entry.title(store.customExercises);
    final subtitle = entry.subtitle(store.customExercises);
    final first = entry.logs.first;
    return Card(
      key: Key('history_entry_${entry.key}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WorkoutHistoryDetailsPage(entryKey: entry.key),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      entry.isPlannedSession ? Icons.flag_rounded : Icons.fitness_center_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${trainerHistoryFullDate(entry.date)} · ${formatWorkoutDuration(stats.duration)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (first.sessionNote.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(first.sessionNote, maxLines: 3, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'details') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkoutHistoryDetailsPage(entryKey: entry.key),
                          ),
                        );
                      }
                      if (value == 'delete') {
                        final deleted = await _confirmAndDeleteTrainerWorkoutHistoryEntry(context, entry);
                        if (context.mounted && deleted) showError(context, 'Usunięto trening z historii.');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'details', child: Text('Szczegóły')),
                      PopupMenuItem(value: 'delete', child: Text('Usuń trening')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MiniTag(text: formatWorkoutDuration(stats.duration)),
                  MiniTag(text: '${stats.exerciseCount} ćwiczeń'),
                  MiniTag(text: '${stats.setCount} serii'),
                  MiniTag(text: '${stats.volume.round()} kg'),
                  MiniTag(text: stats.averageRpe == 0 ? 'RPE —' : 'RPE ${stats.averageRpe.toStringAsFixed(1)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmAndDeleteTrainerWorkoutHistoryEntry(BuildContext context, _TrainerWorkoutHistoryEntry entry) async {
  final store = AppScope.read(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Usunąć trening?'),
      content: Text(
        entry.isPlannedSession ? 'Cała sesja, ćwiczenia i serie zostaną usunięte z historii.' : 'Ten wpis treningowy zostanie usunięty z historii.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Usuń'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await store.deleteHistoryEntry(entry.key);
  return true;
}

class WorkoutHistoryDetailsPage extends StatelessWidget {
  const WorkoutHistoryDetailsPage({super.key, required this.entryKey});

  final String entryKey;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final entry = _findTrainerWorkoutHistoryEntry(store, entryKey);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Szczegóły treningu')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Ten trening nie jest już dostępny w historii.'),
          ),
        ),
      );
    }

    final stats = _TrainerWorkoutHistoryStats.fromLogs(entry.logs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Szczegóły treningu'),
        actions: [
          IconButton(
            tooltip: 'Usuń trening',
            onPressed: () async {
              final deleted = await _confirmAndDeleteTrainerWorkoutHistoryEntry(context, entry);
              if (context.mounted && deleted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _TrainerWorkoutHistoryDetailsHeader(entry: entry, stats: stats),
          const SizedBox(height: 12),
          for (final log in entry.logs) ...[
            _TrainerWorkoutExerciseHistoryCard(log: log),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TrainerWorkoutHistoryDetailsHeader extends StatelessWidget {
  const _TrainerWorkoutHistoryDetailsHeader({
    required this.entry,
    required this.stats,
  });

  final _TrainerWorkoutHistoryEntry entry;
  final _TrainerWorkoutHistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final first = entry.logs.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.title(store.customExercises),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${weekdayName(entry.date.weekday)} · ${trainerHistoryFullDate(entry.date)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: 'Czas ${formatWorkoutDuration(stats.duration)}'),
                MiniTag(text: '${stats.exerciseCount} ćwiczeń'),
                MiniTag(text: '${stats.setCount} serii'),
                MiniTag(text: 'Objętość ${stats.volume.round()} kg'),
                MiniTag(text: stats.averageRpe == 0 ? 'RPE —' : 'Śr. RPE ${stats.averageRpe.toStringAsFixed(1)}'),
              ],
            ),
            if (first.sessionNote.isNotEmpty) ...[
              const SizedBox(height: 14),
              _TrainerWorkoutHistoryNoteBox(
                title: 'Notatka sesji',
                note: first.sessionNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrainerWorkoutExerciseHistoryCard extends StatelessWidget {
  const _TrainerWorkoutExerciseHistoryCard({required this.log});

  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final exercise = log.exerciseFrom(store.customExercises);
    final sets = [...log.workoutSets]..sort((left, right) => left.order.compareTo(right.order));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 58, height: 58, child: ExerciseVisual(exercise: exercise)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          MiniTag(text: '${sets.isEmpty ? log.sets : sets.where((set) => set.isCompleted).length} serii'),
                          MiniTag(text: '${log.volume.round()} kg'),
                          MiniTag(text: 'RPE ${log.rpe}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (log.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              _TrainerWorkoutHistoryNoteBox(title: 'Notatka ćwiczenia', note: log.note),
            ],
            const SizedBox(height: 14),
            Text('Serie', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (sets.isEmpty)
              _TrainerAggregateWorkoutLogRow(log: log)
            else
              for (final set in sets) ...[
                _TrainerWorkoutSetHistoryRow(log: log, set: set),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _TrainerAggregateWorkoutLogRow extends StatelessWidget {
  const _TrainerAggregateWorkoutLogRow({required this.log});

  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Wpis zbiorczy', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MiniTag(text: '${log.sets} serii'),
              MiniTag(text: '${log.reps} powt.'),
              MiniTag(text: '${log.weightKg.toStringAsFixed(1)} kg'),
              MiniTag(text: 'RPE ${log.rpe}'),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => showAddWorkoutSheet(context, existing: log),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edytuj wpis'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerWorkoutSetHistoryRow extends StatelessWidget {
  const _TrainerWorkoutSetHistoryRow({
    required this.log,
    required this.set,
  });

  final WorkoutLog log;
  final WorkoutSet set;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('${set.order}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seria ${set.order}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MiniTag(text: '${set.weightKg.toStringAsFixed(1)} kg'),
                    MiniTag(text: '${set.repetitions} powt.'),
                    MiniTag(text: 'RPE ${set.rpe}'),
                  ],
                ),
                if (set.note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(set.note, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          IconButton(
            key: Key('edit_set_${log.id}_${set.id}'),
            tooltip: 'Edytuj serię',
            onPressed: () => showEditWorkoutSetSheet(context, log: log, set: set),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _TrainerWorkoutHistoryNoteBox extends StatelessWidget {
  const _TrainerWorkoutHistoryNoteBox({
    required this.title,
    required this.note,
  });

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(note),
        ],
      ),
    );
  }
}

Future<void> showEditWorkoutSetSheet(
  BuildContext context, {
  required WorkoutLog log,
  required WorkoutSet set,
}) async {
  final store = AppScope.read(context);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => EditWorkoutSetSheetContent(store: store, log: log, set: set),
  );
}

class EditWorkoutSetSheetContent extends StatefulWidget {
  const EditWorkoutSetSheetContent({
    super.key,
    required this.store,
    required this.log,
    required this.set,
  });

  final AppStore store;
  final WorkoutLog log;
  final WorkoutSet set;

  @override
  State<EditWorkoutSetSheetContent> createState() => _EditWorkoutSetSheetContentState();
}

class _EditWorkoutSetSheetContentState extends State<EditWorkoutSetSheetContent> {
  late final TextEditingController weight;
  late final TextEditingController repetitions;
  late final TextEditingController note;
  late int rpe;

  @override
  void initState() {
    super.initState();
    weight = TextEditingController(text: widget.set.weightKg.toStringAsFixed(1));
    repetitions = TextEditingController(text: '${widget.set.repetitions}');
    note = TextEditingController(text: widget.set.note);
    rpe = widget.set.rpe.clamp(1, 10).toInt();
  }

  @override
  void dispose() {
    weight.dispose();
    repetitions.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsedWeight = double.tryParse(weight.text.replaceAll(',', '.'));
    final parsedRepetitions = int.tryParse(repetitions.text);
    if (parsedWeight == null || parsedWeight < 0) {
      showError(context, 'Podaj poprawny ciężar.');
      return;
    }
    if (parsedRepetitions == null || parsedRepetitions < 0 || parsedRepetitions > 999) {
      showError(context, 'Powtórzenia muszą mieścić się w zakresie 0–999.');
      return;
    }
    await widget.store.updateWorkoutLogSet(
      logId: widget.log.id,
      setId: widget.set.id,
      weightKg: parsedWeight,
      repetitions: parsedRepetitions,
      rpe: rpe,
      note: note.text,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edytuj serię ${widget.set.order}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('edit_set_weight'),
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ciężar kg'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('edit_set_repetitions'),
                    controller: repetitions,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Powtórzenia'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'RPE'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('edit_set_rpe'),
                  value: rpe,
                  isExpanded: true,
                  items: List.generate(10, (index) => index + 1).map((value) => DropdownMenuItem(value: value, child: Text('$value/10'))).toList(),
                  onChanged: (value) => setState(() => rpe = value ?? rpe),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('edit_set_note'),
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notatka do serii'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('save_edited_set'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Zapisz serię'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class LegacyHistoryPage extends StatelessWidget {
  const LegacyHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final logs = [...store.logs]..sort((a, b) => b.date.compareTo(a.date));
    final entries = _groupWorkoutHistory(logs);
    return PageFrame(
      title: 'Historia',
      subtitle: 'Wszystkie treningi zapisane lokalnie na urządzeniu',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Dodaj trening',
          onPressed: () => showAddWorkoutSheet(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: logs.isEmpty
          ? Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_toggle_off_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Historia jest jeszcze pusta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dodaj pierwszy trening, a zapis pojawi się tutaj również po ponownym uruchomieniu aplikacji.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => showAddWorkoutSheet(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Dodaj trening'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  if (index == 0 || !sameDay(entries[index - 1].date, entries[index].date)) ...[
                    if (index > 0) const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Text(
                        '${weekdayName(entries[index].date.weekday)} · ${shortDate(entries[index].date)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                  if (entries[index].isPlannedSession) WorkoutHistorySessionCard(logs: entries[index].logs) else WorkoutLogCard(log: entries[index].logs.single),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _WorkoutHistoryEntry {
  const _WorkoutHistoryEntry(this.logs);

  final List<WorkoutLog> logs;

  DateTime get date => logs.first.date;
  bool get isPlannedSession => logs.first.sessionId.isNotEmpty;
}

List<_WorkoutHistoryEntry> _groupWorkoutHistory(List<WorkoutLog> sortedLogs) {
  final groups = <String, List<WorkoutLog>>{};
  for (final log in sortedLogs) {
    final key = log.sessionId.isEmpty ? 'log_${log.id}' : 'session_${log.sessionId}';
    groups.putIfAbsent(key, () => <WorkoutLog>[]).add(log);
  }
  return groups.values.map(_WorkoutHistoryEntry.new).toList();
}

class WorkoutHistorySessionCard extends StatelessWidget {
  const WorkoutHistorySessionCard({super.key, required this.logs});

  final List<WorkoutLog> logs;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final first = logs.first;
    final exerciseNames = logs.map((log) => log.exerciseFrom(store.customExercises).name).toList();
    final setCount = logs.fold<int>(0, (sum, log) => sum + log.sets);
    final volume = logs.fold<double>(0, (sum, log) => sum + log.volume);
    final rpeSets = logs.expand((log) => log.workoutSets).where((set) => set.rpe > 0).toList();
    final averageRpe = rpeSets.isEmpty ? 0.0 : rpeSets.fold<int>(0, (sum, set) => sum + set.rpe) / rpeSets.length;
    final duration = first.sessionStartedAt != null && first.sessionEndedAt != null ? first.sessionEndedAt!.difference(first.sessionStartedAt!) : Duration(seconds: logs.fold<int>(0, (sum, log) => sum + log.durationSec));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.flag_rounded, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.sessionName.isEmpty ? 'Trening z planu' : first.sessionName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(exerciseNames.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      if (first.sessionNote.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(first.sessionNote, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value != 'delete') return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Usunąć sesję?'),
                        content: const Text('Wszystkie ćwiczenia i serie tego treningu zostaną usunięte z historii.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Anuluj')),
                          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Usuń')),
                        ],
                      ),
                    );
                    if (confirmed == true) await store.deleteLogsBySession(first.sessionId);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Usuń sesję')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: formatWorkoutDuration(duration)),
                MiniTag(text: '${logs.length} ćwiczeń'),
                MiniTag(text: '$setCount serii'),
                MiniTag(text: '${volume.round()} kg'),
                MiniTag(text: averageRpe == 0 ? 'RPE —' : 'RPE ${averageRpe.toStringAsFixed(1)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final day = store.selectedDate;
    final totals = store.totalsForDay(day);
    return PageFrame(
      title: kAppName,
      subtitle: 'Dziennik dnia, statystyki i szybkie akcje',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Historia treningów',
          onPressed: () => openTrainerSubPage(context, const HistoryPage(), title: 'Historia treningów'),
          icon: const Icon(Icons.history_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Dodaj ćwiczenie',
          onPressed: () => showAddWorkoutSheet(context),
          icon: const Icon(Icons.add),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store.activeWorkoutSession != null) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Trening w toku', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${store.activeWorkoutSession!.planName} · ${store.activeWorkoutSession!.dayTitle}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => openActiveWorkoutPage(context),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('Wznów trening'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          DateSwitcher(date: day, onChanged: store.setSelectedDate),

          // === SEKCJA: Regeneracja mięśni (model + spalone kcal) ===
          const SizedBox(height: 18),
          const SectionHeader(title: 'Regeneracja mięśni'),
          const SizedBox(height: 10),
          const RecoveryTodayCard(),

          // === SEKCJA: Podsumowanie dnia (bez kafelka spalonych kcal — jest pod modelem) ===
          const SizedBox(height: 18),
          const SectionHeader(title: 'Podsumowanie dnia'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: StatCard(label: 'Serie', value: '${totals.sets}', icon: Icons.repeat)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Czas', value: '${(totals.durationSec / 60).round()} min', icon: Icons.timer_outlined)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: StatCard(label: 'Objętość', value: '${totals.volume.round()} kg', icon: Icons.monitor_weight_outlined)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Wpisy', value: '${totals.sessions}', icon: Icons.list_alt)),
            ],
          ),
          const SizedBox(height: 10),
          TrainingInsightCard(logs: store.logs, selectedDay: day),

          // === SEKCJA: Aktywność z zegarka / Health Connect ===
          const SizedBox(height: 18),
          const SectionHeader(title: 'Aktywność z zegarka'),
          const SizedBox(height: 10),
          TodayActivityCard(day: day),

          // === Sugestie i korekta dnia → osobny ekran ===
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => openDayInsightsPage(context),
            icon: const Icon(Icons.tips_and_updates_outlined),
            label: const Text('Sugestie i korekta dnia'),
          ),
        ],
      ),
    );
  }
}

Future<void> openDayInsightsPage(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const DayInsightsPage()),
  );
}

/// Osobny ekran „Sugestie i korekta dnia" (przeniesiony ze strony głównej).
class DayInsightsPage extends StatelessWidget {
  const DayInsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final day = store.selectedDate;
    final dayImpact = store.trainingImpactForDay(day);
    return Scaffold(
      appBar: AppBar(title: const Text('Sugestie i korekta dnia')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (dayImpact != null) ...[
              DayAdjustmentCard(impact: dayImpact),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Brak korekty dnia — wykonaj trening, aby zobaczyć sugestie kalorii, wody i białka.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const CalorieBridgeStatusCard(),
            const SizedBox(height: 12),
            AiQuickCard(),
          ],
        ),
      ),
    );
  }
}

/// Status przekazywania spalonych kcal z treningów do aplikacji Licznik Kalorii.
class CalorieBridgeStatusCard extends StatelessWidget {
  const CalorieBridgeStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final todayBurned = store.burnedKcalForDay(store.selectedDate);
    final latest = store.trainingImpacts.isEmpty ? null : store.trainingImpacts.first;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Flexible(child: Text(value, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Integracja z Licznikiem Kalorii', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            row('Dziś przekazane (trening)', '$todayBurned kcal'),
            if (latest != null) ...[
              row('Ostatni trening', latest.sessionName),
              row('Spalone', '${latest.estimatedBurnedKcal} kcal'),
              row('Czas', '${latest.durationMin} min'),
              row('Typ aktywności', 'strength_training'),
              row('Dzień', latest.dateKey),
            ] else
              row('Status', 'Brak treningów do przekazania'),
            const SizedBox(height: 10),
            Text(
              'Spalone kcal z ćwiczeń są publikowane lokalnie dla Licznika Kalorii (bez podwójnego liczenia — po deduplicationKey). Licznik powinien odczytać te dane i nie dodawać aktywności drugi raz.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await store.publishCalorieBridge();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dane kalorii ponownie przekazane do Licznika Kalorii.')),
                  );
                }
              },
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Wyślij ponownie'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etap 22: karta aktywności dnia z Health Connect / zegarka.
/// Tylko wyświetla istniejące dane (snapshot + zarejestrowane aktywności),
/// nic nie przelicza i nie dubluje danych Health Connect.
class TodayActivityCard extends StatelessWidget {
  const TodayActivityCard({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = store.healthConnectSnapshotForDay(day);

    // Bieg / chód mierzony z zarejestrowanych aktywności tego dnia.
    // Świadomie pomijamy "chód zwykły z kroków" — to te same kroki, które
    // pokazujemy już w liczniku "Kroki" (brak dublowania danych Health Connect).
    final activityInputs = store.activityInputsForDay(day);
    final runWalk = activityInputs
        .where((e) =>
            e.type == TrainerActivityType.run ||
            e.type == TrainerActivityType.measuredWalk)
        .toList();

    // Stan pusty — brak snapshotu i brak zarejestrowanego biegu/chodu.
    if (snapshot == null && runWalk.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.watch_outlined, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Brak danych z dzisiaj', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Nie odczytano jeszcze kroków, dystansu ani aktywnych kalorii z Health Connect / zegarka na ten dzień.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthConnectSettingsPage())),
                icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                label: const Text('Otwórz Health Connect'),
              ),
            ],
          ),
        ),
      );
    }

    final partial = snapshot != null &&
        (!snapshot.permissionsGranted || snapshot.missingData.isNotEmpty || !snapshot.hasAnyDailyData);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.watch_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Aktywność dnia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                if (snapshot != null)
                  Text(
                    'odczyt ${formatHealthConnectTimestamp(snapshot.checkedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            // Ostrzeżenie o danych częściowych.
            if (partial) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dane mogą być niepełne (brak części uprawnień lub odczytów).',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Główne liczniki: kroki, dystans, aktywne kcal.
            if (snapshot != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ActivityMetricTile(icon: Icons.directions_walk_rounded, value: '${snapshot.steps}', label: 'Kroki')),
                  const SizedBox(width: 8),
                  Expanded(child: _ActivityMetricTile(icon: Icons.route_rounded, value: formatHealthConnectDistance(snapshot.distanceKm), label: 'Dystans')),
                  const SizedBox(width: 8),
                  Expanded(child: _ActivityMetricTile(icon: Icons.local_fire_department_outlined, value: snapshot.activeKcal.toStringAsFixed(0), label: 'Akt. kcal')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MiniTag(text: 'Treningi: ${snapshot.workoutSessions} · ${snapshot.workoutMinutes} min'),
                  MiniTag(text: snapshot.heartRateSamples == 0 ? 'Tętno: —' : 'Tętno: ${snapshot.averageHeartRate.toStringAsFixed(0)} bpm'),
                  MiniTag(text: snapshot.sleepMinutes == 0 ? 'Sen: —' : 'Sen: ${formatHealthConnectMinutes(snapshot.sleepMinutes)}'),
                ],
              ),
            ],
            // Bieg / chód, jeśli dane istnieją.
            if (runWalk.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Bieg / chód', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...runWalk.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          entry.type == TrainerActivityType.run ? Icons.directions_run_rounded : Icons.directions_walk_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          [
                            if (entry.distanceKm > 0) formatHealthConnectDistance(entry.distanceKm),
                            if (entry.durationMin > 0) '${entry.durationMin} min',
                            '${entry.estimatedKcal} kcal',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityMetricTile extends StatelessWidget {
  const _ActivityMetricTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Etap 22: kompaktowa karta korekty dnia (wpływ treningu na cele).
/// Wyświetla istniejące dane TrainingImpact — nic nie przelicza.
class DayAdjustmentCard extends StatelessWidget {
  const DayAdjustmentCard({super.key, required this.impact});

  final TrainingImpact impact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tips_and_updates_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Korekta dnia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: impact.isTrainingDay ? 'Dzień treningowy' : 'Dzień bez treningu'),
                MiniTag(text: '${impact.estimatedBurnedKcal} kcal spalonych'),
                MiniTag(text: '+${impact.suggestedCalorieAdjustmentKcal} kcal celu'),
                MiniTag(text: '+${impact.suggestedExtraWaterMl} ml wody'),
                MiniTag(text: '+${impact.suggestedExtraProteinG} g białka'),
              ],
            ),
            if (impact.postWorkoutMealSuggestion.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(impact.postWorkoutMealSuggestion, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

class DateSwitcher extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const DateSwitcher({super.key, required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconButton(onPressed: () => onChanged(date.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(
                children: [
                  Text(shortDate(date), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  Text(weekdayName(date.weekday), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton(onPressed: () => onChanged(DateTime.now()), child: const Text('Dziś')),
            IconButton(onPressed: () => onChanged(date.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class DailyHero extends StatelessWidget {
  final DayTotals totals;

  const DailyHero({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spalone kalorie', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary.withOpacity(0.85))),
                const SizedBox(height: 6),
                Text('${totals.calories.round()} kcal', style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Powtórzenia: ${totals.reps} · Objętość: ${totals.volume.round()} kg', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimary.withOpacity(0.85))),
              ],
            ),
          ),
          SizedBox(
            width: 104,
            height: 104,
            child: HumanExerciseImage(type: 'burpee', lineColor: theme.colorScheme.onPrimary, backgroundColor: theme.colorScheme.onPrimary.withOpacity(0.12)),
          ),
        ],
      ),
    );
  }
}

class TrainingInsightCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final DateTime selectedDay;

  const TrainingInsightCard({super.key, required this.logs, required this.selectedDay});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = DateTime(selectedDay.year, selectedDay.month, selectedDay.day).subtract(const Duration(days: 6));
    final recent = logs.where((e) => !e.date.isBefore(start)).toList();
    final total = DayTotals.from(recent);
    final streak = _streak(logs);
    final avgRpe = recent.isEmpty ? 0 : recent.fold<int>(0, (a, e) => a + e.rpe) / recent.length;
    final top = _topExercise(recent);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Trenerski podgląd tygodnia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MiniMetric(label: 'Seria dni', value: '$streak', icon: Icons.local_fire_department_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _MiniMetric(label: '7 dni kcal', value: '${total.calories.round()}', icon: Icons.bolt)),
              const SizedBox(width: 8),
              Expanded(child: _MiniMetric(label: 'Śr. RPE', value: avgRpe == 0 ? '-' : avgRpe.toStringAsFixed(1), icon: Icons.speed)),
            ]),
            const SizedBox(height: 10),
            Text(top.isEmpty ? 'Dodaj kilka treningów, a pokażę najczęstsze ćwiczenie i kierunek progresu.' : 'Najczęściej ostatnio: $top', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  int _streak(List<WorkoutLog> logs) {
    var day = DateTime.now();
    var count = 0;
    while (count < 365) {
      final has = logs.any((e) => sameDay(e.date, day));
      if (!has) break;
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  String _topExercise(List<WorkoutLog> logs) {
    final counts = <String, int>{};
    for (final log in logs) {
      counts[log.exerciseId] = (counts[log.exerciseId] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final id = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return ExerciseRepo.byId(id).name;
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniMetric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
      ]),
    );
  }
}

class WorkoutTimerCard extends StatefulWidget {
  @override
  State<WorkoutTimerCard> createState() => _WorkoutTimerCardState();
}

class _WorkoutTimerCardState extends State<WorkoutTimerCard> {
  Timer? timer;
  int seconds = 90;
  int initial = 90;
  bool running = false;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void start() {
    timer?.cancel();
    setState(() => running = true);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (seconds <= 1) {
        timer?.cancel();
        setState(() {
          seconds = 0;
          running = false;
        });
      } else {
        setState(() => seconds--);
      }
    });
  }

  void reset(int value) {
    timer?.cancel();
    setState(() {
      initial = value;
      seconds = value;
      running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = initial == 0 ? 0.0 : seconds / initial;
    final min = (seconds ~/ 60).toString().padLeft(2, '0');
    final sec = (seconds % 60).toString().padLeft(2, '0');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Timer odpoczynku', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            Text('$min:$sec', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => reset(60), child: const Text('60 s')),
            OutlinedButton(onPressed: () => reset(90), child: const Text('90 s')),
            OutlinedButton(onPressed: () => reset(120), child: const Text('120 s')),
            FilledButton.icon(onPressed: running ? null : start, icon: const Icon(Icons.play_arrow), label: const Text('Start')),
          ]),
        ]),
      ),
    );
  }
}

class QuickWorkoutActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.flash_on, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Szybkie akcje', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: () => showAddWorkoutSheet(context, exercise: ExerciseRepo.byId('plank')), icon: const Icon(Icons.accessibility_new), label: const Text('Core')),
            FilledButton.tonalIcon(onPressed: () => showAddWorkoutSheet(context, exercise: ExerciseRepo.byId('run')), icon: const Icon(Icons.directions_run), label: const Text('Bieg')),
            FilledButton.tonalIcon(onPressed: () => showAddWorkoutSheet(context, exercise: ExerciseRepo.byId('squat')), icon: const Icon(Icons.fitness_center), label: const Text('Siła')),
            OutlinedButton.icon(onPressed: () => showPlanGenerator(context), icon: const Icon(Icons.auto_awesome), label: const Text('Plan AI')),
          ]),
        ]),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const StatCard({super.key, required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback onPressed;

  const EmptyCard({super.key, required this.icon, required this.title, required this.text, required this.buttonLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.add), label: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class WorkoutLogCard extends StatelessWidget {
  final WorkoutLog log;

  const WorkoutLogCard({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final e = log.exerciseFrom(store.customExercises);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => showAddWorkoutSheet(context, existing: log),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(width: 74, height: 74, child: ExerciseVisual(exercise: e)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${log.sets} serie × ${log.reps == 0 ? '-' : log.reps} powt. · ${log.weightKg.toStringAsFixed(1)} kg', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('${log.calories.round()} kcal · RPE ${log.rpe} · ${(log.durationSec / 60).round()} min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (log.aiConfidence > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ConfidencePill(value: log.aiConfidence),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') showAddWorkoutSheet(context, existing: log);
                  if (v == 'delete') store.deleteLog(log.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edytuj')),
                  PopupMenuItem(value: 'delete', child: Text('Usuń')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfidencePill extends StatelessWidget {
  final double value;

  const ConfidencePill({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = value <= 1 ? (value * 100).round() : value.round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(99)),
      child: Text('AI trafność $percent%', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w800)),
    );
  }
}

class AiQuickCard extends StatefulWidget {
  @override
  State<AiQuickCard> createState() => _AiQuickCardState();
}

class _AiQuickCardState extends State<AiQuickCard> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Analiza treningu AI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Np. Zrobiłem 4 serie przysiadów po 10, 70 kg, potem pompki 4x12 i plank 3x45 s...',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: store.aiBusy
                        ? null
                        : () async {
                            if (controller.text.trim().isEmpty) return;
                            try {
                              final result = await store.analyzeWorkoutText(controller.text);
                              if (!context.mounted) return;
                              showAiResultDialog(context, result);
                            } catch (e) {
                              if (!context.mounted) return;
                              showError(context, e.toString());
                            }
                          },
                    icon: store.aiBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt),
                    label: const Text('Analiza'),
                  ),
                ),
              ],
            ),
            if (store.lastAiMessage != null) ...[
              const SizedBox(height: 12),
              AiResultPreviewCard(result: asJsonMap(store.lastAiMessage) ?? {'summary': store.lastAiMessage}),
            ],
          ],
        ),
      ),
    );
  }
}

void showAiResultDialog(BuildContext context, Map<String, dynamic> result) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: AiResultPreviewCard(result: result, expanded: true),
          ),
        ),
      ),
    ),
  );
}

class AiResultPreviewCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final bool expanded;

  const AiResultPreviewCard({super.key, required this.result, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = smartValue(result['summary'] ?? result['note'] ?? result['result'], fallback: 'Analiza gotowa.');
    final intensity = smartValue(result['intensity'] ?? result['training_type'], fallback: 'brak danych');
    final calories = smartValue(result['estimated_calories'] ?? result['calories'], fallback: '0');
    final minutes = smartValue(result['duration_min'] ?? result['duration_minutes'] ?? result['total_duration_min'], fallback: '-');
    final sets = smartValue(result['total_sets'], fallback: '-');
    final volume = smartValue(result['estimated_volume_kg'] ?? result['volume_kg'], fallback: '-');
    final muscles = smartStringList(result['worked_muscles'] ?? result['muscles']);
    final suggestions = smartStringList(result['suggestions'] ?? result['tips']);
    final exercisesRaw = result['detected_exercises'] ?? result['exercises'];
    final detected = exercisesRaw is List ? exercisesRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

    Widget metric(String label, String value, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.auto_awesome),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Wynik analizy AI', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                if (expanded) IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 12),
            Text(summary, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
            const SizedBox(height: 14),
            Row(children: [
              metric('Kalorie', '$calories kcal', Icons.local_fire_department_outlined),
              const SizedBox(width: 8),
              metric('Czas', '$minutes min', Icons.timer_outlined),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              metric('Serie', sets, Icons.repeat),
              const SizedBox(width: 8),
              metric('Objętość', '$volume kg', Icons.monitor_weight_outlined),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: 'Intensywność: $intensity'),
                ...muscles.take(8).map((m) => MiniTag(text: m)),
              ],
            ),
            if (detected.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Wykryte ćwiczenia', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...detected.take(expanded ? 10 : 3).map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.40),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fitness_center, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(smartValue(e['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text('${smartValue(e['sets'])}×${smartValue(e['reps'])}', style: theme.textTheme.labelLarge),
                      ],
                    ),
                  )),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Sugestie', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              ...suggestions.take(expanded ? 8 : 3).map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e)),
                    ]),
                  )),
            ],
            if (expanded) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Surowy JSON / debug'),
                children: [SelectableText(prettyJson(result), style: theme.textTheme.bodySmall)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Buduje gotowy plan treningu brzucha (jeden dzień, ćwiczenia czasowe).
WorkoutPlan buildAbWorkoutPlan() {
  final items = <PlanItem>[
    for (final id in ExerciseRepo.abWorkoutSetIds)
      PlanItem(
        exerciseId: id,
        sets: 1,
        reps: 0,
        durationSec: ExerciseRepo.byId(id).defaultDurationSec,
        note: '',
        restSeconds: 15,
      ),
  ];
  return WorkoutPlan(
    id: 'ab_set_${idNow()}',
    name: 'Trening brzucha',
    note: 'Gotowy zestaw na brzuch i skośne — wykonuj ćwiczenia po kolei, bez długich przerw.',
    goal: 'Sylwetka',
    level: 'Początkujący',
    isActive: true,
    days: [
      WorkoutDay(weekday: DateTime.now().weekday, title: 'Brzuch — zestaw', items: items),
    ],
  );
}

/// Dodaje gotowy trening brzucha jako aktywny plan i otwiera jego szczegóły dnia.
Future<void> addReadyAbWorkout(BuildContext context) async {
  final store = AppScope.read(context);
  final existing = store.plans.where((plan) => plan.id.startsWith('ab_set_')).toList();
  final WorkoutPlan plan;
  if (existing.isNotEmpty) {
    plan = existing.first;
    await store.setActiveWorkoutPlan(plan.id);
  } else {
    plan = buildAbWorkoutPlan();
    await store.addWorkoutPlan(plan);
  }
  if (!context.mounted) return;
  await openWorkoutDayDetails(context, plan.id, 0);
}

/// Karta „Gotowe zestawy treningowe" w zakładce Ćwiczenia. Pozwala dodać gotowy
/// zestaw brzucha jednym dotknięciem i od razu go trenować.
class ReadyWorkoutSetsCard extends StatelessWidget {
  const ReadyWorkoutSetsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final exercises = [for (final id in ExerciseRepo.abWorkoutSetIds) ExerciseRepo.byId(id, store.customExercises)];
    final totalSeconds = exercises.fold<int>(0, (sum, e) => sum + (e.defaultDurationSec > 0 ? e.defaultDurationSec : 40));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Gotowe zestawy', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('NOWOŚĆ', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Trening brzucha', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              '${exercises.length} ćwiczeń · ~${(totalSeconds / 60).round()} min · masa ciała',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: exercises.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ExerciseVisual(exercise: exercises[index])),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => addReadyAbWorkout(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Dodaj i trenuj'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExercisesPage extends StatefulWidget {
  const ExercisesPage({super.key});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  final search = TextEditingController();
  String muscleGroup = 'Wszystkie';
  String equipmentType = 'Wszystkie';
  String level = 'Wszystkie';
  String trainingGoal = 'Wszystkie';
  bool onlyFavorites = false;
  bool showHidden = false;
  bool onlyAvailableEquipment = false;
  bool avoidLimitations = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final filter = ExerciseLibraryFilter(
      query: search.text,
      muscleGroup: muscleGroup == 'Wszystkie' ? null : MuscleGroup.values.firstWhere((value) => value.name == muscleGroup),
      equipmentType: equipmentType == 'Wszystkie' ? null : EquipmentType.values.firstWhere((value) => value.name == equipmentType),
      level: level == 'Wszystkie' ? null : level,
      trainingGoal: trainingGoal == 'Wszystkie' ? null : TrainingGoal.values.firstWhere((value) => value.name == trainingGoal),
      onlyFavorites: onlyFavorites,
      showHidden: showHidden,
    );
    final filteredItems = filter.apply(
      exercises: ExerciseRepo.combined(store.customExercises),
      preferences: store.exerciseLibraryPreferences,
    );
    final items = filteredItems.where((exercise) {
      final equipmentOk = !onlyAvailableEquipment || equipmentMatchesSettings(exercise, store.settings.equipment);
      final painOk = !avoidLimitations || limitationSafe(exercise, store.settings.limitations);
      return equipmentOk && painOk;
    }).toList();
    final fullLibrary = ExerciseRepo.combined(store.customExercises);
    final recentExercises = _recentExercises(store);
    final showRecent = !_hasActiveFilters && search.text.trim().isEmpty && recentExercises.isNotEmpty;
    return PageFrame(
      title: 'Baza ćwiczeń',
      subtitle: '${items.length} ćwiczeń · technika, bezpieczeństwo i lokalne preferencje',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Dodaj własne ćwiczenie',
          onPressed: () => showCreateExerciseSheet(context),
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Importuj ćwiczenie',
          onPressed: () => showWgerSearchSheet(context),
          icon: const Icon(Icons.cloud_download_outlined),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Dodaj trening',
          onPressed: () => showAddWorkoutSheet(context),
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ReadyWorkoutSetsCard(),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Szukaj po nazwie ćwiczenia',
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Wyczyść',
                              onPressed: () {
                                search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        avatar: Icon(
                          onlyFavorites ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 18,
                        ),
                        label: const Text('Ulubione'),
                        selected: onlyFavorites,
                        onSelected: (value) => setState(() => onlyFavorites = value),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                        label: Text(
                          'Ukryte (${store.exerciseLibraryPreferences.hiddenExerciseIds.length})',
                        ),
                        selected: showHidden,
                        onSelected: (value) => setState(() => showHidden = value),
                      ),
                      FilterChip(
                        label: const Text('Tylko mój sprzęt'),
                        selected: onlyAvailableEquipment,
                        onSelected: (value) => setState(() => onlyAvailableEquipment = value),
                      ),
                      FilterChip(
                        label: const Text('Omijaj ograniczenia'),
                        selected: avoidLimitations,
                        onSelected: (value) => setState(() => avoidLimitations = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Filtry bazy',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: _hasActiveFilters
                            ? () {
                                setState(() {
                                  muscleGroup = 'Wszystkie';
                                  equipmentType = 'Wszystkie';
                                  level = 'Wszystkie';
                                  trainingGoal = 'Wszystkie';
                                  onlyFavorites = false;
                                  showHidden = false;
                                  onlyAvailableEquipment = false;
                                  avoidLimitations = false;
                                });
                              }
                            : null,
                        child: const Text('Wyczyść'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 620 ? 2 : 1;
                      final width = columns == 2 ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: width,
                            child: _ExerciseFilterDropdown(
                              label: 'Partia mięśniowa',
                              value: muscleGroup,
                              options: [
                                const MapEntry('Wszystkie', 'Wszystkie'),
                                ...MuscleGroup.values.map(
                                  (value) => MapEntry(value.name, value.label),
                                ),
                              ],
                              onChanged: (value) => setState(() => muscleGroup = value),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _ExerciseFilterDropdown(
                              label: 'Sprzęt',
                              value: equipmentType,
                              options: [
                                const MapEntry('Wszystkie', 'Wszystkie'),
                                ...EquipmentType.values.map(
                                  (value) => MapEntry(value.name, value.label),
                                ),
                              ],
                              onChanged: (value) => setState(() => equipmentType = value),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _ExerciseFilterDropdown(
                              label: 'Poziom trudności',
                              value: level,
                              options: [
                                const MapEntry('Wszystkie', 'Wszystkie'),
                                ...kTrainingLevels.map(
                                  (value) => MapEntry(value, value),
                                ),
                              ],
                              onChanged: (value) => setState(() => level = value),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _ExerciseFilterDropdown(
                              label: 'Cel treningowy',
                              value: trainingGoal,
                              options: [
                                const MapEntry('Wszystkie', 'Wszystkie'),
                                ...TrainingGoal.values.map(
                                  (value) => MapEntry(value.name, value.label),
                                ),
                              ],
                              onChanged: (value) => setState(() => trainingGoal = value),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Etap 24: szybki dostęp do ostatnio używanych ćwiczeń (realne dane z logów).
          if (showRecent) ...[
            const SizedBox(height: 14),
            Text(
              'Ostatnio używane',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentExercises.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final exercise = recentExercises[index];
                  return ActionChip(
                    avatar: Icon(ExercisePlaceholder.iconForExercise(exercise), size: 18),
                    label: Text(exercise.name, overflow: TextOverflow.ellipsis),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ExerciseDetailsPage(exerciseId: exercise.id)),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  showHidden ? 'Ukryte ćwiczenia' : 'Wszystkie ćwiczenia',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${items.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            _ExerciseLibraryEmptyState(
              showingHidden: showHidden,
              query: search.text,
              baseEmpty: fullLibrary.isEmpty,
              onAdd: () => showCreateExerciseSheet(context),
              onClearFilters: () {
                search.clear();
                setState(() {
                  muscleGroup = 'Wszystkie';
                  equipmentType = 'Wszystkie';
                  level = 'Wszystkie';
                  trainingGoal = 'Wszystkie';
                  onlyFavorites = false;
                  showHidden = false;
                  onlyAvailableEquipment = false;
                  avoidLimitations = false;
                });
              },
            )
          else
            ...items.map(
              (exercise) => ExerciseCard(
                exercise: exercise,
                isFavorite: store.isExerciseFavorite(exercise.id),
                isHidden: store.isExerciseHidden(exercise.id),
                onFavorite: () => store.toggleExerciseFavorite(exercise.id),
                onHidden: () => store.setExerciseHidden(
                  exercise.id,
                  !store.isExerciseHidden(exercise.id),
                ),
                onEdit: () => showCreateExerciseSheet(
                  context,
                  exercise: exercise,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters => muscleGroup != 'Wszystkie' || equipmentType != 'Wszystkie' || level != 'Wszystkie' || trainingGoal != 'Wszystkie' || onlyFavorites || showHidden || onlyAvailableEquipment || avoidLimitations;

  /// Etap 24: ostatnio używane ćwiczenia z historii treningów (realne dane).
  /// Zwraca maks. 8 unikalnych ćwiczeń od najnowszego wpisu.
  List<Exercise> _recentExercises(AppStore store) {
    final sortedLogs = [...store.logs]..sort((a, b) => b.date.compareTo(a.date));
    final seen = <String>{};
    final result = <Exercise>[];
    for (final log in sortedLogs) {
      if (seen.add(log.exerciseId)) {
        result.add(ExerciseRepo.byId(log.exerciseId, store.customExercises));
        if (result.length >= 8) break;
      }
    }
    return result;
  }
}

class _ExerciseFilterDropdown extends StatelessWidget {
  const _ExerciseFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<MapEntry<String, String>> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.key,
              child: Text(
                option.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _ExerciseLibraryEmptyState extends StatelessWidget {
  const _ExerciseLibraryEmptyState({
    required this.showingHidden,
    required this.onAdd,
    required this.onClearFilters,
    this.query = '',
    this.baseEmpty = false,
  });

  final bool showingHidden;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;
  final String query;
  final bool baseEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = query.trim().isNotEmpty;

    // Dobór komunikatu zależnie od przyczyny pustej listy.
    final IconData icon;
    final String title;
    final String message;
    if (baseEmpty) {
      icon = Icons.fitness_center_rounded;
      title = 'Baza ćwiczeń jest pusta';
      message = 'Dodaj pierwsze ćwiczenie albo zaimportuj je z zewnętrznej bazy.';
    } else if (showingHidden) {
      icon = Icons.visibility_outlined;
      title = 'Brak ukrytych ćwiczeń';
      message = 'Ukryte pozycje pojawią się tutaj i będzie można je przywrócić.';
    } else if (hasQuery) {
      icon = Icons.search_off_rounded;
      title = 'Brak wyników dla „${query.trim()}"';
      message = 'Sprawdź pisownię, wyczyść filtry albo dodaj własne ćwiczenie.';
    } else {
      icon = Icons.search_off_rounded;
      title = 'Brak ćwiczeń dla wybranych filtrów';
      message = 'Wyczyść filtry albo dodaj własne ćwiczenie.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 46, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!baseEmpty)
                  OutlinedButton(
                    onPressed: onClearFilters,
                    child: const Text('Wyczyść filtry'),
                  ),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Dodaj ćwiczenie'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void showWgerSearchSheet(BuildContext context) {
  final store = AppScope.read(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => WgerSearchSheetContent(store: store, hostContext: context),
  );
}

class WgerSearchSheetContent extends StatefulWidget {
  final AppStore store;
  final BuildContext hostContext;

  const WgerSearchSheetContent({super.key, required this.store, required this.hostContext});

  @override
  State<WgerSearchSheetContent> createState() => _WgerSearchSheetContentState();
}

class _WgerSearchSheetContentState extends State<WgerSearchSheetContent> {
  final query = TextEditingController();
  bool busy = false;
  String message = '';
  List<Exercise> results = const [];

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> runSearch() async {
    if (query.text.trim().isEmpty || busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final found = await WgerService().searchExercises(query.text);
      if (!mounted) return;
      setState(() {
        results = found;
        message = found.isEmpty ? 'Brak wyników. Spróbuj angielskiej nazwy, np. squat, row, bench press.' : 'Znaleziono ${found.length} ćwiczeń. Kliknij + przy wybranym ćwiczeniu.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => message = 'Błąd API: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addExercise(Exercise exercise) async {
    await widget.store.addCustomExercise(exercise);
    if (!mounted) return;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.hostContext.mounted) {
        showError(widget.hostContext, 'Dodano do bazy: ${exercise.name}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Import ćwiczeń z wger', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Najlepiej działa po angielsku: squat, push up, row, curl, deadlift. Po dodaniu ćwiczenie trafia do lokalnej bazy.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: query,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nazwa ćwiczenia online'),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => runSearch(),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : runSearch,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
              label: const Text('Szukaj w darmowej bazie'),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            ...results.map((exercise) => Card(
                  child: ListTile(
                    leading: SizedBox(width: 54, height: 54, child: ExerciseVisual(exercise: exercise)),
                    title: Text(exercise.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${exercise.category} · ${exercise.equipment}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton.filledTonal(
                      onPressed: () => addExercise(exercise),
                      tooltip: 'Dodaj do bazy',
                      icon: const Icon(Icons.add),
                    ),
                    onTap: () => addExercise(exercise),
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.isFavorite,
    required this.isHidden,
    required this.onFavorite,
    required this.onHidden,
    required this.onEdit,
  });

  final Exercise exercise;
  final bool isFavorite;
  final bool isHidden;
  final VoidCallback onFavorite;
  final VoidCallback onHidden;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ExerciseDetailsPage(exerciseId: exercise.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                height: 92,
                child: Stack(
                  children: [
                    Container(
                      width: 78,
                      height: 92,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ExerciseVisual(exercise: exercise),
                    ),
                    // Etap 24: znacznik animacji na miniaturze, gdy ćwiczenie ma GIF.
                    if (exercise.animatedMediaPath != null)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.gif_box_rounded, size: 14, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exercise.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: isFavorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych',
                          onPressed: onFavorite,
                          icon: Icon(
                            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                            color: isFavorite ? const Color(0xFFFFC857) : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Opcje ćwiczenia',
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'hide') onHidden();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Edytuj'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'hide',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                ),
                                title: Text(
                                  isHidden ? 'Przywróć' : 'Ukryj',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.primaryMuscle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.supportingMuscles.isEmpty ? 'Bez dodatkowych partii pomocniczych' : 'Pomocnicze: ${exercise.supportingMuscles.join(' · ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        MiniTag(text: normalizeLevel(exercise.level)),
                        MiniTag(text: exercise.equipment),
                        if (exercise.trainingGoals.isNotEmpty) MiniTag(text: exercise.trainingGoals.first),
                        if (isHidden) const MiniTag(text: 'Ukryte'),
                        if (exercise.source != 'local') MiniTag(text: exercise.source),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiniTag extends StatelessWidget {
  final String text;

  const MiniTag({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class ExerciseDetailsPage extends StatelessWidget {
  const ExerciseDetailsPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final exercise = ExerciseRepo.byId(exerciseId, store.customExercises);
    final theme = Theme.of(context);
    final isFavorite = store.isExerciseFavorite(exercise.id);
    final isHidden = store.isExerciseHidden(exercise.id);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Szczegóły ćwiczenia'),
        actions: [
          IconButton(
            tooltip: 'Edytuj ćwiczenie',
            onPressed: () => showCreateExerciseSheet(context, exercise: exercise),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'visibility') {
                store.setExerciseHidden(exercise.id, !isHidden);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'visibility',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  title: Text(isHidden ? 'Przywróć' : 'Ukryj'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            exercise.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MiniTag(text: exercise.primaryMuscle),
              MiniTag(text: normalizeLevel(exercise.level)),
              MiniTag(text: exercise.equipment),
              if (isHidden) const MiniTag(text: 'Ukryte'),
            ],
          ),
          const SizedBox(height: 16),
          // Etap 15: podgląd multimediów (GIF/zdjęcie) gdy ćwiczenie je ma.
          // Etap 27: galeria multimediów (główne medium + pozioma lista) gdy są mediaItems.
          if (exercise.mediaItems.any((media) => media.hasContent)) ...[
            ExerciseMediaGallery(exercise: exercise),
            const SizedBox(height: 12),
          ] else if (exercise.hasMedia) ...[
            _ExerciseMediaHero(exercise: exercise),
            const SizedBox(height: 12),
          ],
          _ExerciseMuscleMapPlaceholder(exercise: exercise),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Najważniejsze informacje',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  _ExerciseAttributeRow(
                    icon: Icons.adjust_rounded,
                    label: 'Główna partia',
                    value: exercise.primaryMuscle,
                  ),
                  _ExerciseAttributeRow(
                    icon: Icons.hub_outlined,
                    label: 'Partie pomocnicze',
                    value: exercise.supportingMuscles.isEmpty ? 'Brak' : exercise.supportingMuscles.join(', '),
                  ),
                  _ExerciseAttributeRow(
                    icon: Icons.fitness_center_rounded,
                    label: 'Sprzęt',
                    value: exercise.equipment,
                  ),
                  _ExerciseAttributeRow(
                    icon: Icons.signal_cellular_alt_rounded,
                    label: 'Poziom trudności',
                    value: normalizeLevel(exercise.level),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Opis techniki',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    exercise.description,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ExerciseExecutionStepsCard(steps: exercise.executionSteps),
          const SizedBox(height: 12),
          _ExerciseBreathingTempoCard(
            breathing: exercise.breathing,
            tempo: exercise.tempo,
          ),
          const SizedBox(height: 12),
          InfoListCard(title: 'Najczęstsze błędy', icon: Icons.warning_amber_rounded, items: exercise.commonMistakes),
          const SizedBox(height: 12),
          InfoListCard(
            title: 'Kiedy unikać ćwiczenia',
            icon: Icons.health_and_safety_outlined,
            items: exercise.avoidWhen,
          ),
          const SizedBox(height: 12),
          _ExerciseVariantsCard(exercise: exercise),
          const SizedBox(height: 12),
          ExerciseSubstitutionsCard(exercise: exercise),
          const SizedBox(height: 12),
          ExerciseProgressHistorySection(
            exercise: exercise,
            logs: store.logs,
          ),
          // Etap 18: sugestia progresji w szczegółach ćwiczenia
          Builder(builder: (ctx) {
            final activePlan = store.activeWorkoutPlan;
            final todayWeekday = DateTime.now().weekday;
            final planItem = activePlan?.days
                .where((d) => d.weekday == todayWeekday)
                .expand((d) => d.items)
                .where((it) => it.exerciseId == exercise.id)
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ProgressionSuggestionCard(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                logs: store.logs,
                plannedReps: planItem?.reps ?? exercise.defaultReps,
                plannedWeightKg: planItem?.suggestedWeightKg ?? 0,
                planId: activePlan?.id,
                weekday: todayWeekday,
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: _ExerciseDetailsActions(
        isFavorite: isFavorite,
        onFavorite: () => store.toggleExerciseFavorite(exercise.id),
        onAddToPlan: () => showAddExerciseToPlanSheet(context, exercise),
      ),
    );
  }
}

class _ExerciseMuscleMapPlaceholder extends StatelessWidget {
  const _ExerciseMuscleMapPlaceholder({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 380;
            final visual = Container(
              width: compact ? 96 : 126,
              height: compact ? 130 : 164,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.accessibility_new_rounded,
                    size: compact ? 82 : 108,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.42,
                    ),
                  ),
                  Positioned(
                    top: compact ? 48 : 58,
                    child: Container(
                      width: compact ? 38 : 48,
                      height: compact ? 46 : 58,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.38,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ],
              ),
            );
            final description = Column(
              crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Mapa zaangażowanych mięśni',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Miejsce przygotowane pod przyszłą grafikę sylwetki. Na tym etapie pokazujemy czytelny podgląd partii.',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: compact ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MiniTag(text: 'Główna: ${exercise.primaryMuscle}'),
                    ...exercise.supportingMuscles.take(3).map((muscle) => MiniTag(text: muscle)),
                  ],
                ),
              ],
            );
            if (compact) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  visual,
                  const SizedBox(height: 16),
                  description,
                ],
              );
            }
            return Row(
              children: [
                visual,
                const SizedBox(width: 20),
                Expanded(child: description),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExerciseExecutionStepsCard extends StatelessWidget {
  const _ExerciseExecutionStepsCard({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wykonanie krok po kroku',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...steps.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Text(
                            '${entry.key + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              entry.value,
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseBreathingTempoCard extends StatelessWidget {
  const _ExerciseBreathingTempoCard({
    required this.breathing,
    required this.tempo,
  });

  final String breathing;
  final String tempo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _ExerciseGuidanceCard(
            icon: Icons.air_rounded,
            title: 'Oddychanie',
            text: breathing,
          ),
          _ExerciseGuidanceCard(
            icon: Icons.speed_rounded,
            title: 'Tempo ruchu',
            text: tempo,
          ),
        ];
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              cards.first,
              const SizedBox(height: 12),
              cards.last,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 12),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

class _ExerciseGuidanceCard extends StatelessWidget {
  const _ExerciseGuidanceCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseVariantsCard extends StatelessWidget {
  const _ExerciseVariantsCard({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Warianty trudności',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _ExerciseVariantRow(
              icon: Icons.south_east_rounded,
              title: 'Łatwiejsza wersja',
              text: exercise.easierVersion,
              color: theme.colorScheme.tertiary,
            ),
            const Divider(height: 24),
            _ExerciseVariantRow(
              icon: Icons.north_east_rounded,
              title: 'Trudniejsza wersja',
              text: exercise.harderVersion,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseVariantRow extends StatelessWidget {
  const _ExerciseVariantRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseDetailsActions extends StatelessWidget {
  const _ExerciseDetailsActions({
    required this.isFavorite,
    required this.onFavorite,
    required this.onAddToPlan,
  });

  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onAddToPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final favoriteButton = OutlinedButton.icon(
              onPressed: onFavorite,
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFavorite ? const Color(0xFFFFC857) : null,
              ),
              label: Text(
                isFavorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych',
              ),
            );
            final planButton = FilledButton.icon(
              onPressed: onAddToPlan,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Dodaj do planu'),
            );
            if (constraints.maxWidth < 430) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  planButton,
                  const SizedBox(height: 8),
                  favoriteButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: favoriteButton),
                const SizedBox(width: 10),
                Expanded(child: planButton),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> showAddExerciseToPlanSheet(
  BuildContext context,
  Exercise exercise,
) async {
  final hostContext = context;
  final store = AppScope.read(context);
  if (store.plans.isEmpty || store.plans.every((plan) => plan.days.isEmpty)) {
    showError(context, 'Najpierw utwórz plan z przynajmniej jednym dniem.');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dodaj do planu',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wybierz dzień dla: ${exercise.name}',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                for (final plan in store.plans) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      plan.name,
                      style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final day in plan.days)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Builder(
                        builder: (context) {
                          final alreadyAdded = day.items.any(
                            (item) => item.exerciseId == exercise.id,
                          );
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('${day.weekday}'),
                            ),
                            title: Text(
                              weekdayName(day.weekday),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${day.title} · ${day.items.length} ćwiczeń',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Icon(
                              alreadyAdded ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                              color: alreadyAdded ? Theme.of(context).colorScheme.primary : null,
                            ),
                            onTap: alreadyAdded
                                ? null
                                : () async {
                                    final added = await store.addExerciseToPlan(
                                      exerciseId: exercise.id,
                                      planId: plan.id,
                                      weekday: day.weekday,
                                    );
                                    if (!sheetContext.mounted) return;
                                    Navigator.of(sheetContext).pop();
                                    if (hostContext.mounted) {
                                      showError(
                                        hostContext,
                                        added ? 'Dodano ${exercise.name} do planu.' : 'Ćwiczenie jest już w tym dniu.',
                                      );
                                    }
                                  },
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ExerciseAttributeRow extends StatelessWidget {
  const _ExerciseAttributeRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;

  const InfoListCard({super.key, required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 10),
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(e))]),
                )),
          ],
        ),
      ),
    );
  }
}

void analyzeFormDialog(BuildContext context, Exercise exercise) {
  final note = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Analiza techniki: ${exercise.name}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 4, decoration: const InputDecoration(hintText: 'Opisz, co czujesz albo nagraj opis: np. przy przysiadzie czuję lędźwie, kolana uciekają do środka...')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final store = AppScope.read(context);
                try {
                  final result = await AiBackendService(store.settings.backendUrl).analyzeForm({
                    'exercise': exercise.name,
                    'notes': note.text,
                    'user': store.settings.toAiProfile(),
                  });
                  if (!context.mounted) return;
                  Navigator.pop(sheetContext);
                  showAiResultDialog(context, result);
                } catch (e) {
                  if (!context.mounted) return;
                  showError(context, e.toString());
                }
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Sprawdź przez AI'),
            ),
          ],
        ),
      );
    },
  );
}

/// Kompaktowe podsumowanie dzisiejszego treningu w zakładce „Trening".
/// Przeniesione ze strony głównej „Dzisiaj".
class _PlanTodayTrainingCard extends StatelessWidget {
  const _PlanTodayTrainingCard();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final day = store.selectedDate;
    final logs = store.logsForDay(day);
    final totals = store.totalsForDay(day);
    // Karta pojawia się tylko, gdy jest dzisiejszy trening (czyste UI, gdy brak).
    if (logs.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.today_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Dzisiejszy trening', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                TextButton(
                  onPressed: () => openTrainerSubPage(context, const HistoryPage(), title: 'Historia treningów'),
                  child: const Text('Historia'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...[
              Text(
                '${logs.length} ćwiczeń · ${totals.sets} serii · ${(totals.durationSec / 60).round()} min · ${totals.calories.round()} kcal',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final log in logs.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.fitness_center_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.exerciseFrom(store.customExercises).name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text('${log.sets}×${log.reps}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              if (logs.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('+ ${logs.length - 4} więcej', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => showAddWorkoutSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Dodaj ćwiczenie'),
            ),
          ],
        ),
      ),
    );
  }
}

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final activePlan = store.activeWorkoutPlan;
    return PageFrame(
      title: 'Plany treningowe',
      subtitle: '${store.plans.length} ${store.plans.length == 1 ? 'plan' : 'planów'} zapisanych lokalnie',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Utwórz plan',
          onPressed: () => showWorkoutPlanEditor(context),
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Generator planu AI',
          onPressed: () => showPlanGenerator(context),
          icon: const Icon(Icons.auto_awesome),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PlanTodayTrainingCard(),
          const SizedBox(height: 14),
          if (activePlan != null) ...[
            _ActivePlanSummary(plan: activePlan),
            const SizedBox(height: 14),
          ],
          FilledButton.icon(
            onPressed: () => showWorkoutPlanEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Dodaj plan'),
          ),
          const SizedBox(height: 14),
          if (store.plans.isEmpty)
            EmptyCard(
              icon: Icons.event_note_rounded,
              title: 'Brak planów treningowych',
              text: 'Utwórz pierwszy plan i przypisz ćwiczenia do wybranych dni tygodnia.',
              buttonLabel: 'Utwórz plan',
              onPressed: () => showWorkoutPlanEditor(context),
            )
          else
            for (final plan in store.plans) WorkoutPlanCard(plan: plan),
        ],
      ),
    );
  }
}

class _ActivePlanSummary extends StatelessWidget {
  const _ActivePlanSummary({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exerciseCount = plan.days.fold<int>(0, (sum, day) => sum + day.items.length);
    final level = plan.level.trim();
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openWorkoutProgram(context, plan.id),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    child: const Icon(Icons.bolt_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aktywny plan', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(plan.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            plan.goal,
                            if (level.isNotEmpty) level,
                            '${plan.days.length} dni',
                            '$exerciseCount ćwiczeń',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: plan.progress,
                        minHeight: 8,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${plan.completedCount}/${plan.days.length} dni', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openWorkoutProgram(context, plan.id),
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Otwórz program'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => startWorkoutFromActivePlan(context, plan),
                      icon: Icon(AppScope.of(context).activeWorkoutSession == null ? Icons.play_arrow_rounded : Icons.play_circle_outline_rounded),
                      label: Text(AppScope.of(context).activeWorkoutSession == null ? 'Trenuj' : 'Wznów'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ActiveWorkoutConflictAction { resume, replace }

Future<void> openActiveWorkoutPage(BuildContext context) async {
  if (AppScope.read(context).activeWorkoutSession == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      // Etap 30: pełnoekranowy tryb „Aktywne ćwiczenie".
      builder: (_) => const ActiveExercisePlayerPage(),
    ),
  );
}

/// Etap 30: szczegółowy widok treningu (serie, ciężar, RPE, lista, rozgrzewka).
/// Dostępny z menu pełnoekranowego odtwarzacza jako „wysuwana sekcja danych siłowych".
Future<void> openDetailedWorkoutView(BuildContext context) async {
  if (AppScope.read(context).activeWorkoutSession == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ActiveWorkoutPage(),
    ),
  );
}

Future<void> startWorkoutFromActivePlan(
  BuildContext context,
  WorkoutPlan plan,
) async {
  final store = AppScope.read(context);
  if (store.activeWorkoutSession != null) {
    await openActiveWorkoutPage(context);
    return;
  }
  WorkoutDay? today;
  for (final day in plan.days) {
    if (day.weekday == DateTime.now().weekday && day.items.isNotEmpty) {
      today = day;
      break;
    }
  }
  if (today != null) {
    await startWorkoutForDay(context, plan: plan, day: today);
    return;
  }
  final availableDays = plan.days.where((day) => day.items.isNotEmpty).toList();
  if (availableDays.isEmpty) {
    showError(context, 'Dodaj ćwiczenia do planu przed rozpoczęciem treningu.');
    return;
  }
  final selectedDay = await showModalBottomSheet<WorkoutDay>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Wybierz dzień treningowy', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final day in availableDays)
                  ListTile(
                    leading: CircleAvatar(child: Text('${day.weekday}')),
                    title: Text(weekdayName(day.weekday)),
                    subtitle: Text('${day.title} · ${day.items.length} ćwiczeń'),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: () => Navigator.pop(sheetContext, day),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (context.mounted && selectedDay != null) {
    await startWorkoutForDay(context, plan: plan, day: selectedDay);
  }
}

Future<void> startWorkoutForDay(
  BuildContext context, {
  required WorkoutPlan plan,
  required WorkoutDay day,
  int? dayIndex,
}) async {
  final store = AppScope.read(context);
  if (day.items.isEmpty) {
    showError(context, 'Ten dzień nie ma jeszcze ćwiczeń.');
    return;
  }
  final existing = store.activeWorkoutSession;
  if (existing != null) {
    final action = await showDialog<_ActiveWorkoutConflictAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trening już trwa'),
        content: Text('Masz zapisaną sesję „${existing.planName} · ${existing.dayTitle}”. Możesz ją wznowić albo potwierdzić rozpoczęcie nowej.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anuluj')),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, _ActiveWorkoutConflictAction.resume),
            child: const Text('Wznów'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _ActiveWorkoutConflictAction.replace),
            child: const Text('Porzuć i rozpocznij'),
          ),
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == _ActiveWorkoutConflictAction.resume) {
      await openActiveWorkoutPage(context);
      return;
    }
    await store.discardActiveWorkout();
  }
  if (!context.mounted) return;
  // Ostrzeżenie o regeneracji przed startem zestawu (mocno zmęczone partie → potwierdzenie).
  final dayExercises = [for (final item in day.items) ExerciseRepo.byId(item.exerciseId, store.customExercises)];
  final canStart = await confirmRecoveryBeforeStart(context, dayExercises);
  if (!canStart || !context.mounted) return;
  final started = await store.startActiveWorkout(plan: plan, day: day, dayIndex: dayIndex);
  if (!context.mounted) return;
  if (!started) {
    showError(context, 'Nie udało się rozpocząć pustego treningu.');
    return;
  }
  await openActiveWorkoutPage(context);
}

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({super.key});

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  final weight = TextEditingController();
  final repetitions = TextEditingController();
  Timer? timer;
  int rpe = 7;
  String? loadedExerciseId;
  int? loadedExerciseIndex;
  bool leaving = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    weight.dispose();
    repetitions.dispose();
    super.dispose();
  }

  void syncFields(ActiveWorkoutSession session) {
    final exercise = session.currentExercise;
    if (exercise == null) return;
    if (loadedExerciseId == exercise.exerciseId && loadedExerciseIndex == session.currentExerciseIndex) return;
    loadedExerciseId = exercise.exerciseId;
    loadedExerciseIndex = session.currentExerciseIndex;
    final lastSet = exercise.completedSets.isEmpty ? null : exercise.completedSets.last;
    weight.text = _formatPlanWeight(lastSet?.weightKg ?? exercise.suggestedWeightKg);
    repetitions.text = '${lastSet?.repetitions ?? exercise.plannedReps}';
    rpe = lastSet?.rpe ?? 7;
  }

  Future<bool> confirmLeave() async {
    if (leaving) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Przerwać trening?'),
        content: const Text('Zapisane serie pozostaną na urządzeniu. Trening będzie można wznowić później.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Zostań')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Wyjdź i zachowaj')),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> leaveWorkout() async {
    if (!await confirmLeave() || !mounted) return;
    leaving = true;
    Navigator.of(context).pop();
  }

  Future<void> saveSet(AppStore store) async {
    final parsedWeight = double.tryParse(weight.text.trim().replaceAll(',', '.'));
    final parsedRepetitions = int.tryParse(repetitions.text.trim());
    if (parsedWeight == null || parsedWeight < 0 || parsedWeight > 9999) {
      showError(context, 'Podaj poprawny ciężar.');
      return;
    }
    if (parsedRepetitions == null || parsedRepetitions < 1 || parsedRepetitions > 999) {
      showError(context, 'Powtórzenia muszą mieścić się w zakresie 1–999.');
      return;
    }
    final saved = await store.saveActiveWorkoutSet(
      weightKg: parsedWeight,
      repetitions: parsedRepetitions,
      rpe: rpe,
    );
    if (mounted && !saved) showError(context, 'Wszystkie zaplanowane serie są już zapisane.');
  }

  Future<void> finishWorkout(AppStore store) async {
    final session = store.activeWorkoutSession;
    if (session == null) return;
    if (session.completedSetCount == 0) {
      showError(context, 'Zapisz przynajmniej jedną serię przed zakończeniem treningu.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zakończyć trening?'),
        content: Text('Zapiszesz ${session.completedSetCount} serii w historii treningów.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Wróć')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Zakończ')),
        ],
      ),
    );
    if (confirmed != true) return;
    final stretchingFocus = warmupFocusForSession(session, store.customExercises);
    final summary = await store.finishActiveWorkout();
    if (!mounted || summary == null) return;
    leaving = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryPage(
          summary: summary,
          stretchingFocus: stretchingFocus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final session = store.activeWorkoutSession;
    if (session == null || session.currentExercise == null) {
      return const Scaffold(body: Center(child: Text('Brak aktywnego treningu')));
    }
    syncFields(session);
    final activeExercise = session.currentExercise!;
    final exercise = ExerciseRepo.byId(activeExercise.exerciseId, store.customExercises);
    final elapsed = DateTime.now().difference(session.startedAt);
    final setLimitReached = activeExercise.completedSets.length >= activeExercise.plannedSets;
    final isLastExercise = session.currentExerciseIndex >= session.exercises.length - 1;

    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await leaveWorkout();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aktywny trening'),
          leading: IconButton(
            tooltip: 'Wyjdź',
            onPressed: leaveWorkout,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _ActiveWorkoutHeader(
                session: session,
                elapsed: elapsed,
                onEditNote: () => showActiveSessionNoteSheet(context),
              ),
              const SizedBox(height: 12),
              _WorkoutWarmupCard(session: session, store: store),
              const SizedBox(height: 12),
              _CurrentExerciseCard(
                exercise: exercise,
                activeExercise: activeExercise,
                position: session.currentExerciseIndex + 1,
                total: session.exercises.length,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final replace = OutlinedButton.icon(
                    onPressed: () => showReplaceActiveExerciseSheet(context),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Zamień ćwiczenie'),
                  );
                  final note = OutlinedButton.icon(
                    onPressed: () => showActiveExerciseNoteSheet(context),
                    icon: const Icon(Icons.note_alt_outlined),
                    label: Text(activeExercise.note.isEmpty ? 'Dodaj notatkę' : 'Edytuj notatkę'),
                  );
                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [replace, const SizedBox(height: 8), note],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: replace),
                      const SizedBox(width: 10),
                      Expanded(child: note),
                    ],
                  );
                },
              ),
              if (activeExercise.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: const Text('Notatka do ćwiczenia'),
                    subtitle: Text(activeExercise.note),
                  ),
                ),
              ],
              if (session.hasActiveRestTimer) ...[
                const SizedBox(height: 12),
                _ActiveRestTimerCard(
                  session: session,
                  recommendation: workoutRestRecommendation(exercise, activeExercise),
                ),
              ],
              const SizedBox(height: 12),
              // Etap 18: sugestia progresji dla aktywnego ćwiczenia
              ProgressionSuggestionCard(
                exerciseId: activeExercise.exerciseId,
                exerciseName: exercise.name,
                logs: store.logs,
                plannedReps: activeExercise.plannedReps,
                plannedWeightKg: activeExercise.suggestedWeightKg,
                planId: store.activeWorkoutPlan?.id,
                weekday: session.weekday,
                onApplied: () => setState(() {}),
              ),
              if (activeExercise.completedSets.isNotEmpty) ...[
                _CompletedSetsCard(sets: activeExercise.completedSets),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Nowa seria', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: weight,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Ciężar (kg)'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: repetitions,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Powtórzenia'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        key: ValueKey('${activeExercise.exerciseId}_${session.currentExerciseIndex}'),
                        initialValue: rpe,
                        decoration: const InputDecoration(labelText: 'RPE'),
                        items: [
                          for (var value = 1; value <= 10; value++) DropdownMenuItem(value: value, child: Text('$value / 10')),
                        ],
                        onChanged: (value) => setState(() => rpe = value ?? rpe),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: setLimitReached ? null : () => saveSet(store),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(setLimitReached ? 'Wszystkie serie zapisane' : 'Zapisz serię'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final next = FilledButton.tonalIcon(
                    onPressed: isLastExercise
                        ? null
                        : () async {
                            await store.moveToNextActiveExercise();
                            final nextSession = store.activeWorkoutSession;
                            if (nextSession != null) syncFields(nextSession);
                          },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Następne ćwiczenie'),
                  );
                  final skip = OutlinedButton.icon(
                    onPressed: activeExercise.isSkipped
                        ? null
                        : () async {
                            await store.moveToNextActiveExercise(skipCurrent: true);
                            final nextSession = store.activeWorkoutSession;
                            if (nextSession != null) syncFields(nextSession);
                          },
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(activeExercise.isSkipped ? 'Ćwiczenie pominięte' : 'Pomiń ćwiczenie'),
                  );
                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [next, const SizedBox(height: 8), skip],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: next),
                      const SizedBox(width: 10),
                      Expanded(child: skip),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Text('Wszystkie ćwiczenia', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              for (var index = 0; index < session.exercises.length; index++)
                _ActiveWorkoutExerciseTile(
                  activeExercise: session.exercises[index],
                  exercise: ExerciseRepo.byId(session.exercises[index].exerciseId, store.customExercises),
                  selected: index == session.currentExerciseIndex,
                  onTap: () async {
                    await store.selectActiveWorkoutExercise(index);
                    final nextSession = store.activeWorkoutSession;
                    if (nextSession != null) syncFields(nextSession);
                  },
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => finishWorkout(store),
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Zakończ trening'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ETAP 30 — Pełnoekranowy tryb „Aktywne ćwiczenie".
// ============================================================================

String _fmtClock(int totalSeconds) {
  final s = totalSeconds.clamp(0, 359999);
  final m = s ~/ 60;
  final sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// Slide-up z danymi siłowymi (ciężar / powtórzenia / RPE) bieżącego ćwiczenia.
/// Zachowuje istniejący zapis serii ([AppStore.saveActiveWorkoutSet]). Etap 30.
Future<void> showActiveStrengthSheet(BuildContext context) async {
  final store = AppScope.read(context);
  final session = store.activeWorkoutSession;
  final active = session?.currentExercise;
  if (session == null || active == null) return;
  final exercise = ExerciseRepo.byId(active.exerciseId, store.customExercises);
  final lastSet = active.completedSets.isEmpty ? null : active.completedSets.last;
  final weightCtrl = TextEditingController(text: _formatPlanWeight(lastSet?.weightKg ?? active.suggestedWeightKg));
  final repsCtrl = TextEditingController(text: '${lastSet?.repetitions ?? active.plannedReps}');
  var rpe = lastSet?.rpe ?? 7;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final current = store.activeWorkoutSession?.currentExercise ?? active;
        final setLimitReached = current.completedSets.length >= current.plannedSets;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Dane siłowe', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(exercise.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Ciężar (kg)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: repsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Powtórzenia'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: rpe,
                  decoration: const InputDecoration(labelText: 'RPE'),
                  items: [for (var v = 1; v <= 10; v++) DropdownMenuItem(value: v, child: Text('$v / 10'))],
                  onChanged: (value) => setSheetState(() => rpe = value ?? rpe),
                ),
                if (current.completedSets.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Zapisane serie', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  for (var i = 0; i < current.completedSets.length; i++)
                    Builder(builder: (context) {
                      final set = current.completedSets[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Seria ${i + 1}: ${_formatPlanWeight(set.weightKg)} kg × ${set.repetitions} · RPE ${set.rpe}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      );
                    }),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: setLimitReached
                      ? null
                      : () async {
                          final parsedWeight = double.tryParse(weightCtrl.text.trim().replaceAll(',', '.'));
                          final parsedReps = int.tryParse(repsCtrl.text.trim());
                          if (parsedWeight == null || parsedWeight < 0 || parsedWeight > 9999) {
                            showError(context, 'Podaj poprawny ciężar.');
                            return;
                          }
                          if (parsedReps == null || parsedReps < 1 || parsedReps > 999) {
                            showError(context, 'Powtórzenia muszą mieścić się w zakresie 1–999.');
                            return;
                          }
                          final saved = await store.saveActiveWorkoutSet(weightKg: parsedWeight, repetitions: parsedReps, rpe: rpe);
                          if (!sheetContext.mounted) return;
                          if (!saved) {
                            showError(context, 'Wszystkie zaplanowane serie są już zapisane.');
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                        },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(setLimitReached ? 'Wszystkie serie zapisane' : 'Zapisz serię'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  weightCtrl.dispose();
  repsCtrl.dispose();
}

class ActiveExercisePlayerPage extends StatefulWidget {
  const ActiveExercisePlayerPage({super.key});

  @override
  State<ActiveExercisePlayerPage> createState() => _ActiveExercisePlayerPageState();
}

class _ActiveExercisePlayerPageState extends State<ActiveExercisePlayerPage> {
  Timer? _ticker;
  bool _leaving = false;
  bool _muted = false;
  bool _workRunning = false;
  int _workSecondsLeft = 0;
  bool _wasResting = false;
  String? _loadedExId;
  int? _loadedExIndex;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final store = AppScope.read(context);
    final session = store.activeWorkoutSession;
    if (session == null) {
      setState(() {});
      return;
    }
    final resting = session.hasActiveRestTimer;
    if (_wasResting && !resting) {
      final active = session.currentExercise;
      if (active != null) {
        final ex = ExerciseRepo.byId(active.exerciseId, store.customExercises);
        if (ex.defaultDurationSec > 0 && active.completedSets.length < active.plannedSets) {
          _workSecondsLeft = ex.defaultDurationSec;
          _workRunning = false;
        }
      }
    }
    _wasResting = resting;
    if (!resting && _workRunning && _workSecondsLeft > 0) {
      _workSecondsLeft--;
      if (_workSecondsLeft <= 0) {
        _workRunning = false;
        _completeTimedSet(store);
      }
    }
    setState(() {});
  }

  void _syncExercise(ActiveWorkoutSession session, Exercise exercise, ActiveWorkoutExercise active) {
    if (_loadedExId == active.exerciseId && _loadedExIndex == session.currentExerciseIndex) return;
    _loadedExId = active.exerciseId;
    _loadedExIndex = session.currentExerciseIndex;
    _workRunning = false;
    _workSecondsLeft = exercise.defaultDurationSec > 0 ? exercise.defaultDurationSec : 0;
  }

  Future<void> _completeTimedSet(AppStore store) async {
    final session = store.activeWorkoutSession;
    final active = session?.currentExercise;
    if (session == null || active == null) return;
    if (active.completedSets.length >= active.plannedSets) return;
    await store.saveActiveWorkoutSet(
      weightKg: active.suggestedWeightKg,
      repetitions: active.plannedReps > 0 ? active.plannedReps : 1,
      rpe: 7,
    );
  }

  Future<void> _finishNow(AppStore store) async {
    final session = store.activeWorkoutSession;
    if (session == null) return;
    final focus = warmupFocusForSession(session, store.customExercises);
    final summary = await store.finishActiveWorkout();
    if (!mounted || summary == null) return;
    _leaving = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryPage(summary: summary, stretchingFocus: focus),
      ),
    );
  }

  Future<void> _handleExit() async {
    if (_leaving) return;
    final store = AppScope.read(context);
    final session = store.activeWorkoutSession;
    final hasSets = (session?.completedSetCount ?? 0) > 0;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Czy zakończyć trening?'),
        content: Text(hasSets
            ? 'Zapisz trening w historii, odrzuć postęp albo wróć do ćwiczenia.'
            : 'Nie zapisano jeszcze żadnej serii. Możesz zachować trening do wznowienia, odrzucić go albo wrócić.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'discard'), child: const Text('Odrzuć')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, hasSets ? 'save' : 'keep'), child: Text(hasSets ? 'Zapisz i wyjdź' : 'Zachowaj i wyjdź')),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'discard') {
      await store.discardActiveWorkout();
      if (!mounted) return;
      _leaving = true;
      Navigator.of(context).pop();
      return;
    }
    if (action == 'keep') {
      _leaving = true;
      Navigator.of(context).pop();
      return;
    }
    await _finishNow(store);
  }

  Future<void> _openMenu(AppStore store) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fitness_center_rounded),
              title: const Text('Dane siłowe (seria, ciężar, RPE)'),
              onTap: () => Navigator.pop(sheetContext, 'strength'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Zamień ćwiczenie'),
              onTap: () => Navigator.pop(sheetContext, 'swap'),
            ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('Notatka do ćwiczenia'),
              onTap: () => Navigator.pop(sheetContext, 'note'),
            ),
            ListTile(
              leading: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
              title: Text(_muted ? 'Włącz komunikaty' : 'Wycisz komunikaty'),
              onTap: () => Navigator.pop(sheetContext, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.view_list_rounded),
              title: const Text('Widok szczegółowy'),
              onTap: () => Navigator.pop(sheetContext, 'detailed'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.flag_rounded, color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Zakończ trening', style: TextStyle(color: Theme.of(sheetContext).colorScheme.error, fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(sheetContext, 'finish'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'strength':
        await showActiveStrengthSheet(context);
        break;
      case 'swap':
        await showReplaceActiveExerciseSheet(context);
        break;
      case 'note':
        await showActiveExerciseNoteSheet(context);
        break;
      case 'mute':
        setState(() => _muted = !_muted);
        break;
      case 'detailed':
        await openDetailedWorkoutView(context);
        break;
      case 'finish':
        await _handleExit();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final session = store.activeWorkoutSession;
    if (session == null || session.currentExercise == null) {
      return const Scaffold(body: Center(child: Text('Brak aktywnego treningu')));
    }
    final theme = Theme.of(context);
    final active = session.currentExercise!;
    final exercise = ExerciseRepo.byId(active.exerciseId, store.customExercises);
    _syncExercise(session, exercise, active);

    final total = session.exercises.length;
    final index = session.currentExerciseIndex;
    final resting = session.hasActiveRestTimer;
    final setsDone = active.completedSets.length;
    final setFrac = active.plannedSets == 0 ? 0.0 : (setsDone / active.plannedSets).clamp(0.0, 1.0);
    final progress = total == 0 ? 0.0 : ((index + setFrac) / total).clamp(0.0, 1.0);
    final elapsed = DateTime.now().difference(session.startedAt);

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleExit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, store, theme, index, total, elapsed),
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              Expanded(
                child: resting
                    ? _buildRestState(context, store, theme, session, index, total)
                    : _buildExerciseState(context, store, theme, session, exercise, active, index, total),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppStore store, ThemeData theme, int index, int total, Duration elapsed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Wyjdź',
            onPressed: _handleExit,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              'Ćwiczenie ${index + 1}/$total',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(_fmtClock(elapsed.inSeconds), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Menu',
            onPressed: () => _openMenu(store),
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseState(
    BuildContext context,
    AppStore store,
    ThemeData theme,
    ActiveWorkoutSession session,
    Exercise exercise,
    ActiveWorkoutExercise active,
    int index,
    int total,
  ) {
    final media = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: _PlayerExerciseMedia(
        key: ValueKey('${active.exerciseId}_$index'),
        exercise: exercise,
        paused: !_workRunning && exercise.defaultDurationSec > 0,
      ),
    );

    final panel = _buildInfoPanel(context, store, theme, exercise, active, index, total);

    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        if (landscape) {
          return Row(
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.all(12), child: media)),
              SizedBox(
                width: math.min(360, constraints.maxWidth * 0.46),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                  child: panel,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: media)),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: panel),
          ],
        );
      },
    );
  }

  Widget _buildInfoPanel(
    BuildContext context,
    AppStore store,
    ThemeData theme,
    Exercise exercise,
    ActiveWorkoutExercise active,
    int index,
    int total,
  ) {
    final isTimed = exercise.defaultDurationSec > 0;
    final setsDone = active.completedSets.length;
    final allSetsDone = setsDone >= active.plannedSets;
    final isLast = index >= total - 1;
    final coach = _coachMessage(exercise, active, isTimed, allSetsDone);
    final recoveryWarnings = recoveryWarningsForExercises([exercise], store.muscleRecoveryMap());

    Widget bigDisplay;
    if (isTimed && !allSetsDone) {
      bigDisplay = Text(
        _fmtClock(_workSecondsLeft),
        style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900, height: 1),
      );
    } else {
      bigDisplay = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Seria ${math.min(setsDone + (allSetsDone ? 0 : 1), active.plannedSets)}/${active.plannedSets}',
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1),
          ),
          const SizedBox(height: 4),
          Text(
            allSetsDone
                ? 'Ćwiczenie ukończone'
                : '${active.plannedReps} powt.${active.suggestedWeightKg > 0 ? ' · ${_formatPlanWeight(active.suggestedWeightKg)} kg' : ''}',
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    // Główny przycisk akcji (zależny od typu ćwiczenia / stanu).
    Widget primary;
    if (allSetsDone) {
      primary = FilledButton.icon(
        onPressed: () => _advance(store, index, total),
        icon: Icon(isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded),
        label: Text(isLast ? 'Zakończ trening' : 'Następne ćwiczenie'),
      );
    } else if (isTimed) {
      primary = FilledButton.icon(
        onPressed: () => setState(() => _workRunning = !_workRunning),
        icon: Icon(_workRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(_workRunning
            ? 'Pauza'
            : (_workSecondsLeft >= exercise.defaultDurationSec ? 'Start' : 'Wznów')),
      );
    } else {
      primary = FilledButton.icon(
        onPressed: () => showActiveStrengthSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Zapisz serię'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          exercise.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        if (recoveryWarnings.isNotEmpty) ...[
          Center(child: _RecoveryMiniWarning(warning: recoveryWarnings.first)),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: 22,
          child: Center(
            child: coach.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    coach,
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w900),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: bigDisplay),
        const SizedBox(height: 8),
        // Kropki postępu serii.
        if (active.plannedSets > 0)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              for (var i = 0; i < active.plannedSets; i++)
                Icon(
                  i < setsDone ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: i < setsDone ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                ),
            ],
          ),
        const SizedBox(height: 14),
        primary,
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundControl(
              icon: Icons.skip_previous_rounded,
              label: 'Poprzedni',
              onPressed: index <= 0 ? null : () => store.selectActiveWorkoutExercise(index - 1),
            ),
            _RoundControl(
              icon: Icons.skip_next_rounded,
              label: 'Pomiń',
              onPressed: active.isSkipped ? null : () => store.moveToNextActiveExercise(skipCurrent: true),
            ),
            if (isTimed)
              _RoundControl(
                icon: Icons.fitness_center_rounded,
                label: 'Dane',
                onPressed: () => showActiveStrengthSheet(context),
              ),
            _RoundControl(
              icon: isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
              label: isLast ? 'Zakończ' : 'Następne',
              onPressed: () => _advance(store, index, total),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _advance(AppStore store, int index, int total) async {
    if (index >= total - 1) {
      await _handleExit();
      return;
    }
    await store.moveToNextActiveExercise();
  }

  String _coachMessage(Exercise exercise, ActiveWorkoutExercise active, bool isTimed, bool allSetsDone) {
    if (allSetsDone) return 'Gotowe';
    if (!isTimed) return '';
    final total = exercise.defaultDurationSec;
    if (!_workRunning) return 'Przygotuj się';
    if (_workSecondsLeft <= 10) return 'Ostatnie 10 sekund';
    if (_workSecondsLeft >= total) return 'Start';
    if (_workSecondsLeft == (total / 2).round()) return 'Połowa czasu';
    return '';
  }

  Widget _buildRestState(
    BuildContext context,
    AppStore store,
    ThemeData theme,
    ActiveWorkoutSession session,
    int index,
    int total,
  ) {
    final remaining = session.restSecondsRemaining();
    final paused = session.isRestTimerPaused;
    final nextIndex = math.min(index + 1, total - 1);
    final hasNext = nextIndex != index;
    final nextActive = session.exercises[nextIndex];
    final nextExercise = ExerciseRepo.byId(nextActive.exerciseId, store.customExercises);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ODPOCZYNEK', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(_fmtClock(remaining), textAlign: TextAlign.center, style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 16),
          if (hasNext)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  SizedBox(width: 48, height: 48, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ExerciseVisual(exercise: nextExercise))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Następne ćwiczenie', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                        Text(nextExercise.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => store.adjustActiveRestTimer(15),
                  child: const Text('+15 s'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => store.adjustActiveRestTimer(30),
                  child: const Text('+30 s'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => paused ? store.resumeActiveRestTimer() : store.pauseActiveRestTimer(),
                  icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(paused ? 'Wznów' : 'Pauza'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => store.skipActiveRestTimer(),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Pomiń odpoczynek'),
          ),
        ],
      ),
    );
  }
}

/// Duże medium ćwiczenia w trybie aktywnym: GIF (loop), zdjęcie, poster wideo
/// albo estetyczny fallback. Etap 30.
class _PlayerExerciseMedia extends StatelessWidget {
  const _PlayerExerciseMedia({super.key, required this.exercise, this.paused = false});

  final Exercise exercise;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animated = exercise.animatedMediaPath;
    final staticPath = exercise.staticMediaPath;
    final fallback = ExercisePlaceholder(exercise: exercise);

    // Etap 33: wideo instruktażowe (asset/plik) jest głównym medium w trakcie treningu.
    final videoPath = exercise.videoMediaPath;
    final videoLower = videoPath?.toLowerCase() ?? '';
    final isRemoteVideo = videoLower.startsWith('http://') || videoLower.startsWith('https://');
    final playableVideo = videoPath != null && !kIsWeb && !isRemoteVideo;

    Widget media;
    Widget? badge;
    if (playableVideo) {
      media = _LoopingVideo(source: videoPath, paused: paused, fallback: fallback);
      badge = _badge(theme, Icons.movie_outlined, 'Wideo');
    } else if (animated != null) {
      media = buildExerciseMediaImage(animated, fit: BoxFit.contain, fallback: fallback);
      badge = _badge(theme, Icons.gif_box_outlined, 'Animacja');
    } else if (staticPath != null) {
      media = buildExerciseMediaImage(staticPath, fit: BoxFit.contain, fallback: fallback);
      badge = _badge(theme, Icons.image_outlined, 'Zdjęcie');
    } else if (exercise.hasVideo) {
      // Wideo zdalne / web — pokaż poster + ikonę odtwarzania (bez wbudowanego odtwarzacza).
      final poster = exercise.thumbnailMediaPath;
      media = Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null) buildExerciseMediaImage(poster, fit: BoxFit.contain, fallback: fallback) else fallback,
          Container(
            color: Colors.black.withValues(alpha: 0.25),
            alignment: Alignment.center,
            child: const Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white),
          ),
        ],
      );
      badge = _badge(theme, Icons.movie_outlined, 'Wideo');
    } else {
      media = fallback;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: const EdgeInsets.all(10), child: media),
          if (badge != null) Positioned(left: 12, top: 12, child: badge),
          if (paused)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              alignment: Alignment.center,
              child: Icon(Icons.pause_circle_filled_rounded, size: 72, color: Colors.white.withValues(alpha: 0.9)),
            ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onPrimary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary)),
        ],
      ),
    );
  }
}

/// Zapętlone, wyciszone wideo instruktażowe (asset albo plik z dysku).
/// Autoodtwarzanie z reagowaniem na pauzę treningu; błąd inicjalizacji albo brak
/// pliku → [fallback] (nigdy nie crashuje). Etap 33.
class _LoopingVideo extends StatefulWidget {
  const _LoopingVideo({required this.source, required this.paused, required this.fallback});

  final String source;
  final bool paused;
  final Widget fallback;

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = widget.source.startsWith('assets/')
          ? VideoPlayerController.asset(widget.source)
          : VideoPlayerController.file(File(widget.source));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (!widget.paused) {
        await controller.play();
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _LoopingVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;
    if (widget.paused && controller.value.isPlaying) {
      controller.pause();
    } else if (!widget.paused && !controller.value.isPlaying) {
      controller.play();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _MediaLoadingBox();
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// Okrągły przycisk sterujący z etykietą (poprzedni/pomiń/następne itd.). Etap 30.
class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Mapa regeneracji mięśni: model człowieka + maski + dynamiczne kolory.
// ============================================================================

const Color kRecoveryUnknownColor = Color(0xFF8A8F98);

/// Kolor mięśnia na podstawie procentu regeneracji (null → szary „unknown").
/// Zielony kolor zapisany w masce PNG jest ignorowany — kolor nakładamy tutaj.
Color recoveryColor(double? recoveryPercent, {bool dark = false}) {
  if (recoveryPercent == null) return kRecoveryUnknownColor;
  final p = recoveryPercent;
  late final Color base;
  if (p <= 20) {
    base = const Color(0xFFFF3B30);
  } else if (p <= 40) {
    base = const Color(0xFFFF6B2C);
  } else if (p <= 60) {
    base = const Color(0xFFFFB020);
  } else if (p <= 80) {
    base = const Color(0xFFB7E75A);
  } else {
    base = const Color(0xFF35D07F);
  }
  return dark ? Color.lerp(base, Colors.white, 0.12)! : base;
}

/// Siatka etykiet (do trafiania w mięsień) zbudowana z alfy masek. Etap regeneracji.
class _BodyLabelGrid {
  _BodyLabelGrid(this.width, this.height, this.indices, this.muscles);

  final int width;
  final int height;
  final Uint8List indices; // 0 = brak, w przeciwnym razie indeks mięśnia + 1
  final List<BodyMuscle> muscles;

  BodyMuscle? muscleAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final value = indices[y * width + x];
    if (value == 0) return null;
    final index = value - 1;
    return (index >= 0 && index < muscles.length) ? muscles[index] : null;
  }
}

/// Model człowieka z kolorowanymi maskami mięśni. Renderuje bazę + maski jako Stack
/// (każda warstwa Positioned.fill), całość skalowana BoxFit.contain. Crash-safe:
/// brak/uszkodzona maska jest pomijana z logiem; brak bazy → fallback.
class BodyMuscleMap extends StatefulWidget {
  const BodyMuscleMap({
    super.key,
    required this.side,
    required this.dark,
    required this.recovery,
    this.onMuscleTap,
    this.onBackgroundTap,
  });

  final BodyMuscleSide side;
  final bool dark;
  final Map<BodyMuscle, MuscleRecoveryState> recovery;
  final ValueChanged<BodyMuscle>? onMuscleTap;

  /// Wywoływane po dotknięciu modelu poza mięśniem (np. do przełączenia przód/tył).
  final VoidCallback? onBackgroundTap;

  @override
  State<BodyMuscleMap> createState() => _BodyMuscleMapState();
}

class _BodyMuscleMapState extends State<BodyMuscleMap> {
  _BodyLabelGrid? _grid;
  BodyMuscleSide? _gridSide;

  @override
  void initState() {
    super.initState();
    _ensureGrid();
  }

  @override
  void didUpdateWidget(covariant BodyMuscleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side != widget.side) _ensureGrid();
  }

  Future<void> _ensureGrid() async {
    final side = widget.side;
    if (_gridSide == side && _grid != null) return;
    final grid = await _buildLabelGrid(side);
    if (!mounted || widget.side != side) return;
    setState(() {
      _grid = grid;
      _gridSide = side;
    });
  }

  Future<_BodyLabelGrid?> _buildLabelGrid(BodyMuscleSide side) async {
    final masks = muscleMasksForSide(side);
    final muscles = masks.keys.toList();
    int gw = 0;
    int gh = 0;
    Uint8List? indices;
    for (var i = 0; i < muscles.length; i++) {
      for (final file in masks[muscles[i]]!) {
        try {
          final data = await rootBundle.load(bodyMaskAsset(side, file));
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 150);
          final frame = await codec.getNextFrame();
          final image = frame.image;
          final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final w = image.width;
          final h = image.height;
          image.dispose();
          if (bytes == null) continue;
          if (indices == null) {
            gw = w;
            gh = h;
            indices = Uint8List(gw * gh);
          }
          if (w != gw || h != gh) continue; // pomiń maski o innym rozmiarze
          final raw = bytes.buffer.asUint8List();
          for (var p = 0; p < gw * gh; p++) {
            if (raw[p * 4 + 3] > 40) indices[p] = i + 1;
          }
        } catch (error) {
          debugPrint('[BodyMuscleMap] pominięto maskę ${bodyMaskAsset(side, file)}: $error');
        }
      }
    }
    if (indices == null) return null;
    return _BodyLabelGrid(gw, gh, indices, muscles);
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final grid = _grid;
    final onTap = widget.onMuscleTap;
    if (grid == null || onTap == null) return;
    final scale = math.min(size.width / grid.width, size.height / grid.height);
    final dispW = grid.width * scale;
    final dispH = grid.height * scale;
    final lx = details.localPosition.dx - (size.width - dispW) / 2;
    final ly = details.localPosition.dy - (size.height - dispH) / 2;
    if (lx < 0 || ly < 0 || lx >= dispW || ly >= dispH) return;
    final gx = (lx / scale).floor().clamp(0, grid.width - 1);
    final gy = (ly / scale).floor().clamp(0, grid.height - 1);
    final muscle = grid.muscleAt(gx, gy);
    if (muscle != null) {
      onTap(muscle);
    } else {
      widget.onBackgroundTap?.call();
    }
  }

  Widget _baseFallback() {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.accessibility_new_rounded, size: 64, color: scheme.outline)),
    );
  }

  Widget _maskLayer(BodyMuscle muscle, String file) {
    final state = widget.recovery[muscle];
    final hasData = state?.hasData ?? false;
    final color = recoveryColor(state?.recoveryPercent, dark: widget.dark)
        .withValues(alpha: hasData ? 0.82 : 0.42);
    return IgnorePointer(
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          bodyMaskAsset(widget.side, file),
          fit: BoxFit.fill,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = bodyBaseAsset(widget.side, dark: widget.dark);
    final grid = _grid;

    // Do czasu zbudowania siatki (i poznania proporcji) pokaż samą bazę (contain).
    if (grid == null) {
      return Center(
        child: Image.asset(base, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _baseFallback()),
      );
    }

    final masks = muscleMasksForSide(widget.side);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapUp(details, size),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: grid.width.toDouble(),
              height: grid.height.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Image.asset(base, fit: BoxFit.fill, errorBuilder: (_, __, ___) => _baseFallback()),
                  ),
                  for (final muscle in masks.keys)
                    for (final file in masks[muscle]!) Positioned.fill(child: _maskLayer(muscle, file)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatRecoveryAgo(DateTime time, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 60) return '${diff.inMinutes} min temu';
  if (diff.inHours < 24) return '${diff.inHours} h temu';
  return '${diff.inDays} dni temu';
}

/// Bottom sheet ze szczegółami regeneracji partii mięśniowej. Etap regeneracji.
Future<void> showMuscleRecoverySheet(BuildContext context, BodyMuscle muscle, MuscleRecoveryState? state) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final dark = theme.brightness == Brightness.dark;
      final s = state ?? MuscleRecoveryState.unknown(muscle);
      final color = recoveryColor(s.recoveryPercent, dark: dark);
      Widget row(String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(muscle.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                ],
              ),
              const SizedBox(height: 14),
              row('Regeneracja', s.recoveryPercent == null ? '—' : '${s.recoveryPercent!.round()}%'),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (s.recoveryPercent ?? 0) / 100,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 8),
              row('Status', s.statusLabel),
              if (s.lastTrainedAt != null) row('Ostatnio trenowane', _formatRecoveryAgo(s.lastTrainedAt!)),
              if (s.hasData)
                row('Do pełnej regeneracji', s.estimatedHoursRemaining <= 0 ? 'gotowe' : '~${s.estimatedHoursRemaining} h'),
              if (s.lastExerciseNames.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Obciążające ćwiczenia', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(s.lastExerciseNames.join(' · '), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(recoverySuggestionForMuscle(s), style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Przełącznik widoku Przód / Tył modelu.
class _BodySideToggle extends StatelessWidget {
  const _BodySideToggle({required this.side, required this.onChanged});

  final BodyMuscleSide side;
  final ValueChanged<BodyMuscleSide> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<BodyMuscleSide>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: BodyMuscleSide.front, label: Text('Przód')),
        ButtonSegment(value: BodyMuscleSide.back, label: Text('Tył')),
      ],
      selected: {side},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// Legenda kolorów regeneracji.
class RecoveryLegend extends StatelessWidget {
  const RecoveryLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget chip(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        chip(kRecoveryUnknownColor, 'Brak danych'),
        chip(recoveryColor(10, dark: dark), 'Zmęczone'),
        chip(recoveryColor(50, dark: dark), 'W toku'),
        chip(recoveryColor(70, dark: dark), 'Prawie'),
        chip(recoveryColor(95, dark: dark), 'Gotowe'),
      ],
    );
  }
}

/// Lokalna sugestia ogólna na podstawie całej mapy regeneracji (bez AI).
String overallRecoverySuggestion(Map<BodyMuscle, MuscleRecoveryState> recovery) {
  final data = recovery.values.where((state) => state.hasData).toList();
  if (data.isEmpty) {
    return 'Brak danych regeneracji — wykonaj trening, aby zobaczyć analizę partii.';
  }
  final tired = data.where((s) => (s.recoveryPercent ?? 100) <= 40).toList();
  if (tired.length >= 3) {
    return 'Kilka dużych partii jest mocno zmęczonych — dziś dobrze zrobi mobility, stretching albo spacer.';
  }
  if (tired.isNotEmpty) {
    final names = tired.map((s) => s.muscleGroup.label).take(3).join(', ');
    return 'Zmęczone partie ($names) — rozważ lżejszy trening albo inną partię.';
  }
  final ready = data.where((s) => (s.recoveryPercent ?? 0) >= 80).toList();
  if (ready.isNotEmpty) {
    final names = ready.map((s) => s.muscleGroup.label).take(3).join(', ');
    return 'Gotowe do treningu: $names.';
  }
  return 'Większość partii w trakcie regeneracji — trenuj umiarkowanie.';
}

/// Pigułka z dzisiejszymi spalonymi kcal (styl Licznika Kalorii). Etap regeneracji.
class RecoveryKcalPill extends StatelessWidget {
  const RecoveryKcalPill({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final day = store.selectedDate;
    final burned = store.burnedKcalForDay(day);
    final minutes = store.trainingMinutesForDay(day);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.local_fire_department_rounded, color: theme.colorScheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  burned > 0 ? 'Spalone dzisiaj' : 'Aktywność dzisiaj',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$burned', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(width: 4),
                    Text('kcal', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                if (minutes > 0)
                  Text('Trening: $minutes min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                else if (burned == 0)
                  Text('Brak danych aktywności dzisiaj', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Karta modelu człowieka i regeneracji mięśni na stronie „Dzisiaj". Etap regeneracji.
class RecoveryTodayCard extends StatefulWidget {
  const RecoveryTodayCard({super.key});

  @override
  State<RecoveryTodayCard> createState() => _RecoveryTodayCardState();
}

class _RecoveryTodayCardState extends State<RecoveryTodayCard> {
  BodyMuscleSide _side = BodyMuscleSide.front;

  void _toggleSide() {
    setState(() => _side = _side == BodyMuscleSide.front ? BodyMuscleSide.back : BodyMuscleSide.front);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final recovery = store.muscleRecoveryMap();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.self_improvement_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Regeneracja mięśni', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                _BodySideToggle(side: _side, onChanged: (s) => setState(() => _side = s)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              recovery.isEmpty
                  ? 'Brak danych — wykonaj trening, aby zobaczyć regenerację.'
                  : 'Dotknij modelu, aby zmienić widok • dotknij mięśnia po szczegóły.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 230,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: BodyMuscleMap(
                  key: ValueKey(_side),
                  side: _side,
                  dark: dark,
                  recovery: recovery,
                  onMuscleTap: (muscle) => showMuscleRecoverySheet(context, muscle, recovery[muscle]),
                  onBackgroundTap: _toggleSide,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const RecoveryKcalPill(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleSide,
                    icon: const Icon(Icons.cached_rounded, size: 18),
                    label: Text(_side == BodyMuscleSide.front ? 'Pokaż tył' : 'Pokaż przód'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => openMuscleRecoveryPage(context),
                    icon: const Icon(Icons.insights_rounded, size: 18),
                    label: const Text('Szczegóły'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openMuscleRecoveryPage(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const MuscleRecoveryPage()),
  );
}

/// Baner ostrzegający o trenowaniu partii będących jeszcze w regeneracji.
/// Informacyjny (nie blokuje). Pusta lista → nic nie pokazuje.
class RecoveryWarningBanner extends StatelessWidget {
  const RecoveryWarningBanner({super.key, required this.warnings});

  final List<RecoveryWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final severe = warnings.any((w) => w.severe);
    final accent = severe ? scheme.error : const Color(0xFFE08600);
    final list = warnings.take(3).map((w) => '${w.muscle.label} ${w.recoveryPercent.round()}%').join(', ');
    final extra = warnings.length > 3 ? ' (+${warnings.length - 3})' : '';
    final title = severe ? 'Mocno zmęczone partie' : 'Uwaga na regenerację';
    final message = severe
        ? 'Te partie nie są jeszcze zregenerowane: $list$extra. Dziś lepiej je odpuść albo zrób lżejszą wersję.'
        : 'Partie w trakcie regeneracji: $list$extra. Rozważ lżejszy trening lub inną partię.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(severe ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: accent)),
                const SizedBox(height: 2),
                Text(message, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sprawdza regenerację przed startem zestawu i — jeśli któraś partia jest mocno
/// zmęczona — prosi o potwierdzenie. Zwraca `true`, gdy można startować.
Future<bool> confirmRecoveryBeforeStart(BuildContext context, Iterable<Exercise> exercises) async {
  final store = AppScope.read(context);
  final warnings = recoveryWarningsForExercises(exercises, store.muscleRecoveryMap());
  final severe = warnings.where((w) => w.severe).toList();
  if (severe.isEmpty) return true;
  final list = severe.take(3).map((w) => '${w.muscle.label} (${w.recoveryPercent.round()}%)').join(', ');
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Partie jeszcze w regeneracji'),
      content: Text(
        'Te partie nie są w pełni zregenerowane: $list.\n\n'
        'Trening teraz może spowolnić regenerację i zwiększyć ryzyko przeciążenia. Chcesz mimo to trenować?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Trenuj mimo to')),
      ],
    ),
  );
  return proceed == true;
}

/// Mała pigułka ostrzegająca o regeneracji bieżącego ćwiczenia (w odtwarzaczu).
class _RecoveryMiniWarning extends StatelessWidget {
  const _RecoveryMiniWarning({required this.warning});

  final RecoveryWarning warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = warning.severe ? theme.colorScheme.error : const Color(0xFFE08600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${warning.muscle.label} w regeneracji · ${warning.recoveryPercent.round()}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pełny ekran „Regeneracja mięśni". Etap regeneracji.
class MuscleRecoveryPage extends StatefulWidget {
  const MuscleRecoveryPage({super.key});

  @override
  State<MuscleRecoveryPage> createState() => _MuscleRecoveryPageState();
}

class _MuscleRecoveryPageState extends State<MuscleRecoveryPage> {
  BodyMuscleSide _side = BodyMuscleSide.front;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final recovery = store.muscleRecoveryMap();
    final fatigued = recovery.values.where((state) => state.hasData).toList()
      ..sort((a, b) => (a.recoveryPercent ?? 100).compareTo(b.recoveryPercent ?? 100));

    return Scaffold(
      appBar: AppBar(title: const Text('Regeneracja mięśni')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Center(child: _BodySideToggle(side: _side, onChanged: (s) => setState(() => _side = s))),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: BodyMuscleMap(
                  key: ValueKey(_side),
                  side: _side,
                  dark: dark,
                  recovery: recovery,
                  onMuscleTap: (muscle) => showMuscleRecoverySheet(context, muscle, recovery[muscle]),
                  onBackgroundTap: () => setState(() => _side = _side == BodyMuscleSide.front ? BodyMuscleSide.back : BodyMuscleSide.front),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const RecoveryLegend(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(overallRecoverySuggestion(recovery), style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (fatigued.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.self_improvement_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Brak danych regeneracji — wykonaj trening z przypisanymi partiami mięśniowymi, aby zobaczyć mapę.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Text('Najbardziej zmęczone partie', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              for (final state in fatigued.take(6)) _FatiguedMuscleRow(state: state),
            ],
          ],
        ),
      ),
    );
  }
}

class _FatiguedMuscleRow extends StatelessWidget {
  const _FatiguedMuscleRow({required this.state});

  final MuscleRecoveryState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = recoveryColor(state.recoveryPercent, dark: dark);
    final percent = (state.recoveryPercent ?? 0).round();
    final eta = state.estimatedHoursRemaining <= 0 ? 'gotowe' : '~${state.estimatedHoursRemaining} h';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showMuscleRecoverySheet(context, state.muscleGroup, state),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(state.muscleGroup.label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800))),
                      Text('$percent%', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${state.statusLabel} · do pełnej regeneracji $eta', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Etap 15: rozgrzewka, mobility i stretching -------------------------

/// Statusy rozgrzewki przechowywane w [AppStore].
const String kWarmupStatusDone = 'done';
const String kWarmupStatusSkipped = 'skipped';

/// Dobiera partię (focus) rozgrzewki/rozciągania na podstawie ćwiczeń sesji.
WarmupFocus warmupFocusForSession(
  ActiveWorkoutSession session,
  List<Exercise> customExercises,
) {
  final groups = <MuscleGroup>[];
  for (final activeExercise in session.exercises) {
    final definition = ExerciseRepo.byId(activeExercise.exerciseId, customExercises);
    groups.addAll(definition.muscleGroups);
  }
  return WarmupLibrary.focusForMuscleGroups(groups);
}

/// Formatuje procedurę do czytelnego tekstu w oknie dialogowym.
String formatTrainingRoutine(TrainingRoutine routine) {
  final buffer = StringBuffer();
  for (var index = 0; index < routine.steps.length; index++) {
    final step = routine.steps[index];
    if (routine.numbered) {
      buffer.writeln('${index + 1}. $step');
    } else {
      buffer.writeln(step);
    }
  }
  return buffer.toString().trim();
}

/// Karta rozgrzewki pokazywana na początku aktywnego treningu.
/// Sugeruje rozgrzewkę zależnie od partii, pozwala oznaczyć ją jako
/// wykonaną albo pominąć, a także podejrzeć mobilizację.
class _WorkoutWarmupCard extends StatelessWidget {
  const _WorkoutWarmupCard({required this.session, required this.store});

  final ActiveWorkoutSession session;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focus = warmupFocusForSession(session, store.customExercises);
    final warmup = WarmupLibrary.warmupForFocus(focus);
    final mobility = WarmupLibrary.mobilityForFocus(focus);
    final status = store.warmupStatusForSession(session.id);

    if (status == kWarmupStatusDone || status == kWarmupStatusSkipped) {
      final done = status == kWarmupStatusDone;
      return Card(
        child: ListTile(
          leading: Icon(
            done ? Icons.check_circle_rounded : Icons.fast_forward_rounded,
            color: done ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(done ? 'Rozgrzewka wykonana' : 'Rozgrzewka pominięta'),
          subtitle: Text('Sugestia: ${warmup.title}'),
          trailing: TextButton(
            onPressed: () => showSmartTextDialog(
              context,
              warmup.title,
              formatTrainingRoutine(warmup),
            ),
            child: const Text('Pokaż'),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rozgrzewka przed treningiem',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sugestia pod partię: ${focus.label}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final step in warmup.steps.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $step', style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => showSmartTextDialog(
                    context,
                    warmup.title,
                    formatTrainingRoutine(warmup),
                  ),
                  child: const Text('Cała rozgrzewka'),
                ),
                OutlinedButton(
                  onPressed: () => showSmartTextDialog(
                    context,
                    mobility.title,
                    formatTrainingRoutine(mobility),
                  ),
                  child: const Text('Mobilność'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final markDone = FilledButton.icon(
                  onPressed: () => store.setWarmupStatus(session.id, kWarmupStatusDone),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Wykonana'),
                );
                final skip = OutlinedButton.icon(
                  onPressed: () => store.setWarmupStatus(session.id, kWarmupStatusSkipped),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Pomiń'),
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [markDone, const SizedBox(height: 8), skip],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: markDone),
                    const SizedBox(width: 10),
                    Expanded(child: skip),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Karta sugerowanego rozciągania pokazywana po zakończeniu treningu.
class _WorkoutStretchingCard extends StatelessWidget {
  const _WorkoutStretchingCard({required this.focus});

  final WarmupFocus focus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stretching = WarmupLibrary.stretchingForFocus(focus);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.self_improvement_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rozciąganie po treningu',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sugestia pod partię: ${focus.label}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final step in stretching.steps.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $step', style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => showSmartTextDialog(
                  context,
                  stretching.title,
                  formatTrainingRoutine(stretching),
                ),
                child: const Text('Całe rozciąganie'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveWorkoutHeader extends StatelessWidget {
  const _ActiveWorkoutHeader({
    required this.session,
    required this.elapsed,
    required this.onEditNote,
  });

  final ActiveWorkoutSession session;
  final Duration elapsed;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plannedSets = session.exercises.fold<int>(0, (sum, exercise) => sum + exercise.plannedSets);
    final progress = plannedSets == 0 ? 0.0 : session.completedSetCount / plannedSets;
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(session.planName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  tooltip: 'Notatka do sesji',
                  onPressed: onEditNote,
                  icon: Icon(session.note.isEmpty ? Icons.note_add_outlined : Icons.sticky_note_2_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${weekdayName(session.weekday)} · ${session.dayTitle}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (session.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(session.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text('Czas ${formatWorkoutDuration(elapsed)}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
                Text('${session.completedSetCount}/$plannedSets serii', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.clamp(0, 1)),
          ],
        ),
      ),
    );
  }
}

class _ActiveRestTimerCard extends StatelessWidget {
  const _ActiveRestTimerCard({
    required this.session,
    required this.recommendation,
  });

  final ActiveWorkoutSession session;
  final WorkoutRestRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final remaining = session.restSecondsRemaining();
    final total = math.max(session.restTimerTotalSeconds, 1);
    final progress = remaining / total;
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(child: Text('Przerwa między seriami', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                Text(formatWorkoutDuration(Duration(seconds: remaining)), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 4),
            Text(recommendation.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress.clamp(0, 1)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: session.isRestTimerPaused ? store.resumeActiveRestTimer : store.pauseActiveRestTimer,
                  icon: Icon(session.isRestTimerPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(session.isRestTimerPaused ? 'Wznów' : 'Pauza'),
                ),
                OutlinedButton(
                  onPressed: () => store.adjustActiveRestTimer(-30),
                  child: const Text('−30 s'),
                ),
                OutlinedButton(
                  onPressed: () => store.adjustActiveRestTimer(30),
                  child: const Text('+30 s'),
                ),
                TextButton.icon(
                  onPressed: store.skipActiveRestTimer,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Pomiń'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showActiveExerciseNoteSheet(BuildContext context) async {
  final store = AppScope.read(context);
  var note = store.activeWorkoutSession?.currentExercise?.note ?? '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(sheetContext).viewInsets.bottom + MediaQuery.of(sheetContext).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notatka do ćwiczenia', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: note,
            autofocus: true,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Np. kontroluj tempo, ustaw ławkę wyżej…'),
            onChanged: (value) => note = value,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await store.updateActiveExerciseNote(note);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Zapisz notatkę'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showActiveSessionNoteSheet(BuildContext context) async {
  final store = AppScope.read(context);
  var note = store.activeWorkoutSession?.note ?? '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(sheetContext).viewInsets.bottom + MediaQuery.of(sheetContext).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notatka do całej sesji', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: note,
            autofocus: true,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Np. słabszy sen, dobra energia, ból barku…'),
            onChanged: (value) => note = value,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await store.updateActiveSessionNote(note);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Zapisz notatkę'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showReplaceActiveExerciseSheet(BuildContext context) async {
  final store = AppScope.read(context);
  final session = store.activeWorkoutSession;
  final current = session?.currentExercise;
  if (current == null) return;
  final usedExerciseIds = session!.exercises.where((exercise) => exercise != current).map((exercise) => exercise.exerciseId).toSet();
  var query = '';
  final replacement = await showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final exercises = ExerciseRepo.combined(store.customExercises).where((exercise) {
          if (exercise.id == current.exerciseId || usedExerciseIds.contains(exercise.id) || store.isExerciseHidden(exercise.id)) return false;
          return query.isEmpty || exercise.name.toLowerCase().contains(query);
        }).toList();
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Zamień ćwiczenie', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      current.completedSets.isEmpty ? 'Wybierz ćwiczenie zastępcze.' : 'Zapisane serie pozostaną bez zmian i zostaną przypisane do zamiennika.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Szukaj po nazwie'),
                      onChanged: (value) => setSheetState(() => query = value.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: exercises.isEmpty
                    ? const Center(child: Text('Brak pasujących ćwiczeń'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: SizedBox(width: 48, height: 48, child: ExerciseVisual(exercise: exercise)),
                              title: Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${exercise.primaryMuscle} · ${exercise.equipment}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.swap_horiz_rounded),
                              onTap: () => Navigator.pop(sheetContext, exercise),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (replacement != null) await store.replaceActiveWorkoutExercise(replacement);
}

class _CurrentExerciseCard extends StatelessWidget {
  const _CurrentExerciseCard({
    required this.exercise,
    required this.activeExercise,
    required this.position,
    required this.total,
  });

  final Exercise exercise;
  final ActiveWorkoutExercise activeExercise;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommendation = workoutRestRecommendation(
      exercise,
      activeExercise,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 82, height: 82, child: ExerciseVisual(exercise: exercise)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ćwiczenie $position z $total', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${activeExercise.plannedSets} serie × ${activeExercise.plannedReps} powt. · ${recommendation.seconds} s przerwy', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedSetsCard extends StatelessWidget {
  const _CompletedSetsCard({required this.sets});

  final List<WorkoutSet> sets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Wykonane serie', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final set in sets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    CircleAvatar(radius: 15, child: Text('${set.order}')),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_formatPlanWeight(set.weightKg)} kg × ${set.repetitions} powt.')),
                    Text('RPE ${set.rpe}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveWorkoutExerciseTile extends StatelessWidget {
  const _ActiveWorkoutExerciseTile({
    required this.activeExercise,
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  final ActiveWorkoutExercise activeExercise;
  final Exercise exercise;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = activeExercise.completedSets.length >= activeExercise.plannedSets;
    return Card(
      color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          complete
              ? Icons.check_circle_rounded
              : activeExercise.isSkipped
                  ? Icons.skip_next_rounded
                  : Icons.radio_button_unchecked_rounded,
          color: complete || selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${activeExercise.completedSets.length}/${activeExercise.plannedSets} serii', maxLines: 1),
        trailing: selected ? const Icon(Icons.chevron_right_rounded) : null,
      ),
    );
  }
}

class WorkoutSummaryPage extends StatefulWidget {
  const WorkoutSummaryPage({
    super.key,
    required this.summary,
    this.stretchingFocus = WarmupFocus.general,
  });

  final CompletedWorkoutSummary summary;
  final WarmupFocus stretchingFocus;

  @override
  State<WorkoutSummaryPage> createState() => _WorkoutSummaryPageState();
}

class _WorkoutSummaryPageState extends State<WorkoutSummaryPage> {
  bool _aiLoading = false;
  String? _aiError;

  // Etap 31: ocena treningu, pytanie o ból, cofnięcie ukończenia.
  String? _rating;
  bool _painChecked = false;
  final TextEditingController _painCtrl = TextEditingController();
  bool _painSaved = false;
  bool _undone = false;

  static const List<(String, IconData)> _ratingOptions = [
    ('Łatwy', Icons.sentiment_satisfied_rounded),
    ('Średni', Icons.sentiment_neutral_rounded),
    ('Ciężki', Icons.sentiment_dissatisfied_rounded),
    ('Za ciężki', Icons.sentiment_very_dissatisfied_rounded),
  ];

  static const List<(IconData, String, String)> _afterTips = [
    (Icons.local_drink_outlined, 'Wypij wodę', 'Uzupełnij płyny po wysiłku.'),
    (Icons.egg_alt_outlined, 'Zjedz białko', 'Posiłek z białkiem wspiera regenerację mięśni.'),
    (Icons.self_improvement_rounded, 'Zrób stretching', 'Krótkie rozciąganie zmniejszy napięcie.'),
    (Icons.bedtime_outlined, 'Odpocznij', 'Sen i regeneracja budują formę.'),
  ];

  Widget _buildRatingCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jak oceniasz trening?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _ratingOptions)
                  ChoiceChip(
                    avatar: Icon(option.$2, size: 18),
                    label: Text(option.$1),
                    selected: _rating == option.$1,
                    onSelected: (_) => _selectRating(option.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.healing_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Czy coś bolało?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _painChecked,
              title: const Text('Tak, chcę zapisać dolegliwość'),
              onChanged: (value) => setState(() => _painChecked = value),
            ),
            if (_painChecked) ...[
              TextField(
                controller: _painCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Gdzie/co bolało?',
                  hintText: 'np. lewy bark przy wyciskaniu',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_painSaved)
                    Text('Zapisano w notatce sesji.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _savePain,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Zapisz uwagę'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Po treningu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (final tip in _afterTips)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Icon(tip.$1, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tip.$2, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text(tip.$3, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgramActionsCard(ThemeData theme, bool dayCompleted) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_available_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Postęp programu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _repeatDay,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Powtórz dzień'),
            ),
            if (dayCompleted && !_undone) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _undoCompletion,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Cofnij ukończenie dnia'),
              ),
            ] else if (_undone) ...[
              const SizedBox(height: 8),
              Text('Cofnięto ukończenie dnia.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _painCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectRating(String rating) async {
    setState(() => _rating = rating);
    await AppScope.read(context).appendWorkoutSessionNote(
      widget.summary.sessionId,
      'Ocena treningu: $rating',
    );
  }

  Future<void> _savePain() async {
    final text = _painCtrl.text.trim();
    if (text.isEmpty) return;
    await AppScope.read(context).appendWorkoutSessionNote(
      widget.summary.sessionId,
      'Ból/uwaga: $text',
    );
    if (mounted) setState(() => _painSaved = true);
  }

  Future<void> _undoCompletion() async {
    final store = AppScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cofnąć ukończenie dnia?'),
        content: const Text('Dzień przestanie być oznaczony jako ukończony, a postęp programu się zmniejszy. Zapisany trening w historii pozostanie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cofnij')),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.setPlanDayCompleted(widget.summary.planId, widget.summary.dayIndex, completed: false);
    if (mounted) setState(() => _undone = true);
  }

  void _repeatDay() {
    if (widget.summary.planId.isEmpty || widget.summary.dayIndex < 0) return;
    openWorkoutDayDetails(context, widget.summary.planId, widget.summary.dayIndex);
  }

  Future<void> _runAiAnalysis() async {
    final store = AppScope.of(context);
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      await store.analyzeCompletedWorkout(widget.summary);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Błąd AI: $e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final summary = widget.summary;
    final analysis = store.workoutAiAnalysisFor(summary.sessionId);
    final kcal = summary.trainingImpact?.estimatedBurnedKcal ?? 0;

    WorkoutPlan? programPlan;
    if (summary.planId.isNotEmpty) {
      for (final plan in store.plans) {
        if (plan.id == summary.planId) {
          programPlan = plan;
          break;
        }
      }
    }
    final dayCompleted = programPlan != null && summary.dayIndex >= 0 && programPlan.isDayCompleted(summary.dayIndex);
    final headerTitle = (summary.dayLabel.isNotEmpty && summary.dayIndex >= 0)
        ? '${summary.dayLabel} ukończony'
        : 'Trening zakończony';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Podsumowanie treningu'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // Etap 31: ekran sukcesu.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [theme.colorScheme.primaryContainer, theme.colorScheme.surfaceContainerHighest],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Icon(Icons.emoji_events_rounded, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 10),
                  Text(headerTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Dobra robota!', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(summary.name, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (programPlan != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('${programPlan.completedCount}/${programPlan.days.length} dni', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: programPlan.progress,
                              minHeight: 8,
                              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.12,
              children: [
                _WorkoutSummaryStat(label: 'Czas', value: formatWorkoutDuration(summary.duration), icon: Icons.timer_outlined),
                _WorkoutSummaryStat(label: 'Ćwiczenia', value: '${summary.exerciseCount}', icon: Icons.fitness_center_rounded),
                _WorkoutSummaryStat(label: 'Serie', value: '${summary.setCount}', icon: Icons.repeat_rounded),
                _WorkoutSummaryStat(label: 'Spalone', value: '$kcal kcal', icon: Icons.local_fire_department_outlined),
                _WorkoutSummaryStat(label: 'Objętość', value: '${summary.volume.round()} kg', icon: Icons.monitor_weight_outlined),
                _WorkoutSummaryStat(label: 'Pominięte', value: '${summary.skippedCount}', icon: Icons.skip_next_rounded),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('Średnie RPE'),
                trailing: Text(summary.averageRpe == 0 ? '—' : summary.averageRpe.toStringAsFixed(1), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 10),
            _buildRatingCard(theme),
            const SizedBox(height: 10),
            _buildPainCard(theme),
            const SizedBox(height: 10),
            _buildSuggestionsCard(theme),
            if (summary.planId.isNotEmpty && summary.dayIndex >= 0) ...[
              const SizedBox(height: 10),
              _buildProgramActionsCard(theme, dayCompleted),
            ],
            if (widget.summary.trainingImpact != null) ...[
              const SizedBox(height: 10),
              _TrainingImpactSummaryCard(impact: widget.summary.trainingImpact!),
            ],
            const SizedBox(height: 10),
            _WorkoutStretchingCard(focus: widget.stretchingFocus),
            const SizedBox(height: 10),
            // Etap 18: sugestie progresji per ćwiczenie
            _WorkoutProgressionSuggestionsCard(summary: widget.summary),
            const SizedBox(height: 10),
            // Etap 17: karta analizy AI
            _AiWorkoutAnalysisCard(
              analysis: analysis,
              loading: _aiLoading,
              error: _aiError,
              onAnalyze: _runAiAnalysis,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Gotowe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutProgressionSuggestionsCard extends StatelessWidget {
  const _WorkoutProgressionSuggestionsCard({required this.summary});

  final CompletedWorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);

    // Zbierz ćwiczenia z tej sesji
    final sessionLogs = store.logs.where((l) => l.sessionId == summary.sessionId).toList();
    final exerciseIds = sessionLogs.map((l) => l.exerciseId).toSet().toList();
    if (exerciseIds.isEmpty) return const SizedBox.shrink();

    final activePlan = store.activeWorkoutPlan;
    final suggestions = <MapEntry<String, ProgressionSuggestion>>[];
    for (final id in exerciseIds) {
      final planItem = activePlan?.days
          .expand((d) => d.items)
          .where((it) => it.exerciseId == id)
          .firstOrNull;
      final log = sessionLogs.firstWhere((l) => l.exerciseId == id);
      final s = progressionSuggestionForExercise(
        exerciseId: id,
        allLogs: store.logs,
        plannedReps: planItem?.reps ?? log.reps,
        plannedWeightKg: planItem?.suggestedWeightKg ?? log.weightKg,
      );
      if (s != null && s.action != ProgressionAction.maintain) {
        suggestions.add(MapEntry(id, s));
      }
    }

    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Sugestie progresji', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            for (final entry in suggestions) ...[
              _ProgressionSummaryRow(
                exerciseId: entry.key,
                suggestion: entry.value,
                activePlan: activePlan,
              ),
              if (entry != suggestions.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressionSummaryRow extends StatelessWidget {
  const _ProgressionSummaryRow({required this.exerciseId, required this.suggestion, required this.activePlan});

  final String exerciseId;
  final ProgressionSuggestion suggestion;
  final WorkoutPlan? activePlan;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final exercise = ExerciseRepo.byId(exerciseId, store.customExercises);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color color;
    switch (suggestion.action) {
      case ProgressionAction.increaseWeight:
      case ProgressionAction.increaseReps:
        color = Colors.green;
      case ProgressionAction.maintain:
        color = scheme.primary;
      case ProgressionAction.decreaseWeight:
        color = Colors.orange;
      case ProgressionAction.deload:
        color = Colors.deepOrange;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(suggestion.icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${exercise.name} — ${suggestion.label}',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(suggestion.reason, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
      ],
    );
  }
}

class _AiWorkoutAnalysisCard extends StatelessWidget {
  const _AiWorkoutAnalysisCard({
    required this.analysis,
    required this.loading,
    required this.error,
    required this.onAnalyze,
  });

  final WorkoutAiAnalysis? analysis;
  final bool loading;
  final String? error;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Analiza AI trenera', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                if (analysis != null && !loading)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Odśwież analizę',
                    onPressed: onAnalyze,
                    iconSize: 20,
                  ),
              ],
            ),
            if (analysis == null && !loading && error == null) ...[
              const SizedBox(height: 10),
              Text('Poproś AI o ocenę dzisiejszego treningu — co poszło dobrze, co poprawić i jaki jest następny krok.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAnalyze,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Analiza AI'),
              ),
            ],
            if (loading) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Text('AI analizuje Twój trening…', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (error != null && !loading) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(error!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onAnalyze,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
            if (analysis != null && !loading) ...[
              const SizedBox(height: 12),
              _AiAnalysisRow(icon: Icons.star_rounded, color: scheme.primary, label: 'Ocena', text: analysis!.rating.isNotEmpty ? analysis!.rating : '—'),
              _AiAnalysisRow(icon: Icons.thumb_up_rounded, color: Colors.green, label: 'Co poszło dobrze', text: analysis!.wentWell.isNotEmpty ? analysis!.wentWell : '—'),
              _AiAnalysisRow(icon: Icons.build_rounded, color: Colors.orange, label: 'Co poprawić', text: analysis!.improvable.isNotEmpty ? analysis!.improvable : '—'),
              _AiAnalysisRow(icon: Icons.trending_up_rounded, color: scheme.secondary, label: 'Czy zwiększyć ciężar', text: analysis!.increaseWeight.isNotEmpty ? analysis!.increaseWeight : '—'),
              if (analysis!.fatigueWarning.isNotEmpty)
                _AiAnalysisRow(icon: Icons.warning_amber_rounded, color: Colors.deepOrange, label: 'Zmęczenie / regeneracja', text: analysis!.fatigueWarning),
              _AiAnalysisRow(icon: Icons.arrow_forward_rounded, color: scheme.primary, label: 'Następny krok', text: analysis!.nextStep.isNotEmpty ? analysis!.nextStep : '—'),
              if (analysis!.rawSummary.isNotEmpty &&
                  analysis!.wentWell.isEmpty &&
                  analysis!.rating.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Text(analysis!.rawSummary, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ),
              ],
              const SizedBox(height: 6),
              Text('AI nie zmienia planu automatycznie. Zmiany wymagają Twojego potwierdzenia.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiAnalysisRow extends StatelessWidget {
  const _AiAnalysisRow({required this.icon, required this.color, required this.label, required this.text});

  final IconData icon;
  final Color color;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingImpactSummaryCard extends StatelessWidget {
  const _TrainingImpactSummaryCard({required this.impact});

  final TrainingImpact impact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Wpływ na Licznik Kalorii', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: impact.isTrainingDay ? 'Dzień treningowy' : 'Dzień bez treningu'),
                MiniTag(text: '${impact.estimatedBurnedKcal} kcal spalonych'),
                MiniTag(text: '+${impact.suggestedCalorieAdjustmentKcal} kcal sugestii'),
                MiniTag(text: '+${impact.suggestedExtraWaterMl} ml wody'),
                MiniTag(text: '+${impact.suggestedExtraProteinG} g białka'),
              ],
            ),
            const SizedBox(height: 10),
            Text(impact.postWorkoutMealSuggestion, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'Adapter lokalny: ${TrainerCalorieLocalAdapter.impactQueueKey}. Klucz anty-duplikacji: ${impact.deduplicationKey}.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutSummaryStat extends StatelessWidget {
  const _WorkoutSummaryStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatWorkoutDuration(Duration duration) {
  final safeSeconds = math.max(0, duration.inSeconds);
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class WorkoutPlanCard extends StatelessWidget {
  const WorkoutPlanCard({super.key, required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          MiniTag(text: plan.goal),
                          MiniTag(text: '${plan.days.length} dni'),
                          if (plan.isActive) const MiniTag(text: 'Aktywny'),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opcje planu',
                  onSelected: (value) async {
                    if (value == 'active') {
                      await store.setActiveWorkoutPlan(plan.id);
                    } else if (value == 'edit') {
                      if (context.mounted) await showWorkoutPlanEditor(context, plan: plan);
                    } else if (value == 'duplicate') {
                      final copy = await store.duplicateWorkoutPlan(plan.id);
                      if (context.mounted && copy != null) showError(context, 'Skopiowano cały tydzień jako „${copy.name}”.');
                    } else if (value == 'delete') {
                      if (context.mounted) await showDeleteWorkoutPlanDialog(context, plan);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!plan.isActive)
                      const PopupMenuItem(
                        value: 'active',
                        child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.bolt_outlined), title: Text('Ustaw jako aktywny')),
                      ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('Edytuj plan i dni')),
                    ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.copy_all_outlined), title: Text('Kopiuj cały tydzień')),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline), title: Text('Usuń plan')),
                    ),
                  ],
                ),
              ],
            ),
            if (plan.note.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(plan.note, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            if (!plan.isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () => store.setActiveWorkoutPlan(plan.id),
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('Ustaw jako aktywny'),
                ),
              ),
            if (plan.days.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                child: Text('Ten plan nie ma jeszcze dni treningowych.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              for (final day in plan.days) WorkoutPlanDayCard(plan: plan, day: day),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => showWorkoutPlanEditor(context, plan: plan),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Edytuj plan i dni'),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutPlanDayCard extends StatelessWidget {
  const WorkoutPlanDayCard({super.key, required this.plan, required this.day});

  final WorkoutPlan plan;
  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text('${day.weekday}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(weekdayName(day.weekday), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    Text('${day.title} · ${day.items.length} ćwiczeń', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kopiuj dzień',
                onPressed: () => showCopyWorkoutDaySheet(context, plan: plan, day: day),
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (day.items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Brak ćwiczeń. Dodaj je z lokalnej bazy.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            for (final item in day.items)
              _PlanExerciseTile(
                plan: plan,
                day: day,
                item: item,
                exercise: item.exerciseFrom(store.customExercises),
              ),
          FilledButton.tonalIcon(
            onPressed: () => showPlanExercisePicker(context, plan: plan, day: day),
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Dodaj ćwiczenie'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: day.items.isEmpty ? null : () => startWorkoutForDay(context, plan: plan, day: day),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Rozpocznij trening'),
          ),
        ],
      ),
    );
  }
}

@Deprecated('Użyj WorkoutPlanDayCard z jawnym planem.')
class PlanDayCard extends StatelessWidget {
  const PlanDayCard({super.key, required this.day});

  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    final plan = AppScope.of(context).activeWorkoutPlan;
    if (plan == null) return const SizedBox.shrink();
    return WorkoutPlanDayCard(plan: plan, day: day);
  }
}

// ============================================================================
// ETAP 28 — Profesjonalny widok programu treningowego (nagłówek, postęp,
// sekcja „Dzisiaj", lista dni z blokowaniem i statusami).
// ============================================================================

/// Szacunek dnia treningowego: liczba ćwiczeń, czas (min) i kalorie.
class PlanDayEstimate {
  const PlanDayEstimate({
    required this.exerciseCount,
    required this.minutes,
    required this.kcal,
  });

  final int exerciseCount;
  final int minutes;
  final int kcal;
}

/// Liczy szacunkowy czas i kalorie dnia na podstawie pozycji planu.
PlanDayEstimate estimatePlanDay(
  WorkoutDay day,
  List<Exercise> customExercises,
  double bodyWeightKg,
) {
  var totalMinutes = 0.0;
  var totalKcal = 0.0;
  for (final item in day.items) {
    final exercise = item.exerciseFrom(customExercises);
    final workSeconds = item.durationSec > 0
        ? item.sets * item.durationSec
        : item.sets * item.reps * 3;
    final restSeconds = item.sets * item.restSeconds;
    final minutes = math.max(1.0, (workSeconds + restSeconds) / 60);
    totalMinutes += minutes;
    totalKcal += estimateCalories(
      met: exercise.met,
      weightKg: bodyWeightKg,
      minutes: minutes,
    );
  }
  return PlanDayEstimate(
    exerciseCount: day.items.length,
    minutes: totalMinutes.round(),
    kcal: totalKcal.round(),
  );
}

Future<void> openWorkoutProgram(BuildContext context, String planId) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutProgramPage(planId: planId),
    ),
  );
}

class WorkoutProgramPage extends StatefulWidget {
  const WorkoutProgramPage({super.key, required this.planId});

  final String planId;

  @override
  State<WorkoutProgramPage> createState() => _WorkoutProgramPageState();
}

class _WorkoutProgramPageState extends State<WorkoutProgramPage> {
  bool _showCompleted = false;

  WorkoutPlan? _findPlan(AppStore store) {
    for (final plan in store.plans) {
      if (plan.id == widget.planId) return plan;
    }
    return null;
  }

  Future<void> _changeLevel(AppStore store, WorkoutPlan plan) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Poziom programu', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            for (final level in kTrainingLevels)
              ListTile(
                leading: Icon(
                  (plan.level.isNotEmpty && normalizeLevel(plan.level) == level)
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(level),
                onTap: () => Navigator.of(sheetContext).pop(level),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await store.setPlanLevel(plan.id, selected);
  }

  Future<void> _confirmReset(AppStore store, WorkoutPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zresetować postęp?'),
        content: const Text('Wszystkie dni zostaną oznaczone jako niewykonane. Tej operacji nie można cofnąć.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Zresetuj')),
        ],
      ),
    );
    if (confirmed == true) await store.resetPlanProgress(plan.id);
  }

  void _warnLocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ten dzień odblokuje się po ukończeniu poprzedniego treningu.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final plan = _findPlan(store);
    final theme = Theme.of(context);

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program treningowy')),
        body: const _ProgramEmptyState(),
      );
    }

    final days = plan.days;
    final completedIndexes = [
      for (var i = 0; i < days.length; i++)
        if (plan.isDayCompleted(i)) i,
    ];
    final hasHiddenCompleted = !_showCompleted && completedIndexes.isNotEmpty;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ProgramHeader(
            plan: plan,
            onBack: () => Navigator.of(context).maybePop(),
            menu: _buildMenu(store, plan),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (plan.note.trim().isNotEmpty) ...[
                  Text(
                    plan.note,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                ],
                _ProgramTodayCard(plan: plan, onWarnLocked: _warnLocked),
                const SizedBox(height: 18),
                if (days.isEmpty)
                  EmptyCard(
                    icon: Icons.event_note_rounded,
                    title: 'Brak dni w programie',
                    text: 'Dodaj dni i ćwiczenia w edytorze planu.',
                    buttonLabel: 'Edytuj program',
                    onPressed: () => showWorkoutPlanEditor(context, plan: plan),
                  )
                else ...[
                  Row(
                    children: [
                      Text('Dni programu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const Spacer(),
                      Text('${plan.completedCount}/${days.length}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (hasHiddenCompleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showCompleted = true),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: Text('Pokaż ukończone dni (${completedIndexes.length})'),
                      ),
                    ),
                  for (var i = 0; i < days.length; i++)
                    if (_showCompleted || !plan.isDayCompleted(i))
                      _ProgramDayCard(
                        plan: plan,
                        index: i,
                        onWarnLocked: _warnLocked,
                      ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(AppStore store, WorkoutPlan plan) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      tooltip: 'Opcje programu',
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await showWorkoutPlanEditor(context, plan: plan);
            break;
          case 'reset':
            await _confirmReset(store, plan);
            break;
          case 'level':
            await _changeLevel(store, plan);
            break;
          case 'showAll':
            setState(() => _showCompleted = !_showCompleted);
            break;
          case 'anyDay':
            await store.setPlanAllowAnyDay(plan.id, !plan.allowAnyDay);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('Edytuj program')),
        ),
        const PopupMenuItem(
          value: 'level',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.signal_cellular_alt_rounded), title: Text('Zmień poziom')),
        ),
        const PopupMenuItem(
          value: 'reset',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.restart_alt_rounded), title: Text('Zresetuj postęp')),
        ),
        CheckedPopupMenuItem(
          value: 'showAll',
          checked: _showCompleted,
          child: const Text('Pokaż wszystkie dni'),
        ),
        CheckedPopupMenuItem(
          value: 'anyDay',
          checked: plan.allowAnyDay,
          child: const Text('Trenuj dowolny dzień'),
        ),
      ],
    );
  }
}

class _ProgramEmptyState extends StatelessWidget {
  const _ProgramEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center_rounded, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('Brak aktywnego programu', textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'Utwórz plan w zakładce „Plany treningowe", aby zobaczyć go tutaj jako program z dniami i postępem.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Duży nagłówek programu: obraz/gradient w tle, nazwa, poziom, postęp.
class _ProgramHeader extends StatelessWidget {
  const _ProgramHeader({required this.plan, required this.onBack, required this.menu});

  final WorkoutPlan plan;
  final VoidCallback onBack;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = plan.level.trim();
    return SizedBox(
      height: 268,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tło: obraz (jeśli jest) albo gradient marki.
          if (plan.imageAsset != null && plan.imageAsset!.trim().isNotEmpty)
            buildExerciseMediaImage(
              plan.imageAsset!,
              fit: BoxFit.cover,
              fallback: _gradient(scheme),
            )
          else
            _gradient(scheme),
          // Scrim dla czytelności tekstu.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          // Pasek górny: powrót + menu.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    tooltip: 'Wstecz',
                  ),
                  const Spacer(),
                  menu,
                ],
              ),
            ),
          ),
          // Treść nagłówka.
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plan.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900, height: 1.05),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(icon: Icons.flag_rounded, label: plan.goal),
                    if (level.isNotEmpty) _HeaderChip(icon: Icons.signal_cellular_alt_rounded, label: level),
                    _HeaderChip(icon: Icons.calendar_month_rounded, label: '${plan.days.length} dni'),
                    if (plan.allowAnyDay) const _HeaderChip(icon: Icons.lock_open_rounded, label: 'Dowolny dzień'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '${plan.completedCount} / ${plan.days.length}',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 6),
                    const Text('dni ukończono', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: plan.progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradient(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.primaryContainer, scheme.surfaceContainerHighest],
          ),
        ),
      );
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Sekcja „Dzisiaj": co jest zaplanowane, ile potrwa, trening czy odpoczynek.
class _ProgramTodayCard extends StatelessWidget {
  const _ProgramTodayCard({required this.plan, required this.onWarnLocked});

  final WorkoutPlan plan;
  final VoidCallback onWarnLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context);

    if (plan.isProgramCompleted) {
      return Card(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: theme.colorScheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Program ukończony!', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('Świetna robota. Zresetuj postęp, aby zacząć od nowa.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (plan.days.isEmpty) return const SizedBox.shrink();

    final index = plan.currentDayIndex.clamp(0, plan.days.length - 1);
    final day = plan.days[index];
    final isRest = plan.isRestDay(day);
    final estimate = estimatePlanDay(day, store.customExercises, store.settings.bodyWeightKg);

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('DZISIAJ', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dzień ${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(isRest ? Icons.self_improvement_rounded : Icons.fitness_center_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isRest ? 'Dzień odpoczynku' : day.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isRest)
              Text('Odpocznij i zregeneruj się. Możesz zaliczyć ten dzień, aby przejść dalej.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _MetaPill(icon: Icons.timer_outlined, text: '~${estimate.minutes} min'),
                  _MetaPill(icon: Icons.format_list_numbered_rounded, text: '${estimate.exerciseCount} ćw.'),
                  _MetaPill(icon: Icons.local_fire_department_outlined, text: '${estimate.kcal} kcal'),
                ],
              ),
            const SizedBox(height: 14),
            if (isRest)
              FilledButton.tonalIcon(
                onPressed: () => store.setPlanDayCompleted(plan.id, index),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Zalicz dzień odpoczynku'),
              )
            else
              FilledButton.icon(
                onPressed: () => openWorkoutDayDetails(context, plan.id, index),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('START'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Karta pojedynczego dnia programu z numerem, czasem, liczbą ćwiczeń, kcal i statusem.
class _ProgramDayCard extends StatelessWidget {
  const _ProgramDayCard({required this.plan, required this.index, required this.onWarnLocked});

  final WorkoutPlan plan;
  final int index;
  final VoidCallback onWarnLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = AppScope.of(context);
    final day = plan.days[index];
    final status = plan.statusForDay(index);
    final isLocked = status == WorkoutDayStatus.locked;
    final isCompleted = status == WorkoutDayStatus.completed;
    final isRest = status == WorkoutDayStatus.rest || (isCompleted && plan.isRestDay(day));
    final isActive = status == WorkoutDayStatus.active;
    final estimate = estimatePlanDay(day, store.customExercises, store.settings.bodyWeightKg);

    final Color borderColor = isActive
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: 0.45);
    final Color bgColor = isActive
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.surfaceContainerHighest.withValues(alpha: isLocked ? 0.3 : 0.5);

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: isActive ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DayBadge(index: index, status: status),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: isLocked ? 0.65 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRest ? 'Dzień odpoczynku' : day.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      if (isRest)
                        Text('Regeneracja', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _MetaPill(icon: Icons.timer_outlined, text: '~${estimate.minutes} min'),
                            _MetaPill(icon: Icons.format_list_numbered_rounded, text: '${estimate.exerciseCount} ćw.'),
                            _MetaPill(icon: Icons.local_fire_department_outlined, text: '${estimate.kcal} kcal'),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusIcon(status: status),
            ],
          ),
          const SizedBox(height: 12),
          _buildAction(context, store, theme, status, day),
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: isLocked ? onWarnLocked : () => openWorkoutDayDetails(context, plan.id, index),
      child: card,
    );
  }

  Widget _buildAction(
    BuildContext context,
    AppStore store,
    ThemeData theme,
    WorkoutDayStatus status,
    WorkoutDay day,
  ) {
    switch (status) {
      case WorkoutDayStatus.locked:
        return Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Zablokowane — ukończ poprzedni dzień',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      case WorkoutDayStatus.completed:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openWorkoutDayDetails(context, plan.id, index),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Powtórz'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => store.setPlanDayCompleted(plan.id, index, completed: false),
              child: const Text('Cofnij'),
            ),
          ],
        );
      case WorkoutDayStatus.rest:
        return FilledButton.tonalIcon(
          onPressed: () => store.setPlanDayCompleted(plan.id, index),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Zalicz dzień odpoczynku'),
        );
      case WorkoutDayStatus.active:
      case WorkoutDayStatus.available:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => openWorkoutDayDetails(context, plan.id, index),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(status == WorkoutDayStatus.active ? 'START' : 'Rozpocznij trening'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => store.setPlanDayCompleted(plan.id, index),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Oznacz jako ukończony'),
              ),
            ),
          ],
        );
    }
  }
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.index, required this.status});

  final int index;
  final WorkoutDayStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = status == WorkoutDayStatus.active;
    final isCompleted = status == WorkoutDayStatus.completed;
    final bg = isCompleted
        ? scheme.primary
        : isActive
            ? scheme.primary
            : scheme.surfaceContainerHighest;
    final fg = (isCompleted || isActive) ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('DZIEŃ', style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text('${index + 1}', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900, height: 1)),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final WorkoutDayStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case WorkoutDayStatus.completed:
        return Icon(Icons.check_circle_rounded, color: scheme.primary);
      case WorkoutDayStatus.locked:
        return Icon(Icons.lock_rounded, color: scheme.onSurfaceVariant);
      case WorkoutDayStatus.rest:
        return Icon(Icons.local_cafe_rounded, color: scheme.onSurfaceVariant);
      case WorkoutDayStatus.active:
        return Icon(Icons.play_circle_fill_rounded, color: scheme.primary);
      case WorkoutDayStatus.available:
        return Icon(Icons.radio_button_unchecked_rounded, color: scheme.onSurfaceVariant);
    }
  }
}

// ============================================================================
// ETAP 29 — Ekran szczegółów dnia treningowego.
// ============================================================================

/// Wspólny wybór ćwiczenia z biblioteki (zwraca wybrane [Exercise] albo null).
/// Używane m.in. do podmiany ćwiczenia w dniu. Etap 29.
Future<Exercise?> pickExerciseFromLibrary(
  BuildContext context, {
  String title = 'Wybierz ćwiczenie',
  String? subtitle,
  Set<String> excludeIds = const {},
}) async {
  final store = AppScope.read(context);
  var query = '';
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final exercises = ExerciseRepo.combined(store.customExercises).where((exercise) {
          if (excludeIds.contains(exercise.id) || store.isExerciseHidden(exercise.id)) return false;
          return query.isEmpty || exercise.name.toLowerCase().contains(query);
        }).toList();
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Szukaj po nazwie'),
                      onChanged: (value) => setSheetState(() => query = value.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: exercises.isEmpty
                    ? const Center(child: Text('Brak pasujących ćwiczeń'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: SizedBox(width: 48, height: 48, child: ExerciseVisual(exercise: exercise)),
                              title: Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${exercise.primaryMuscle} · ${exercise.equipment}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.check_circle_outline_rounded),
                              onTap: () => Navigator.pop(sheetContext, exercise),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> openWorkoutDayDetails(BuildContext context, String planId, int dayIndex) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutDayDetailsPage(planId: planId, dayIndex: dayIndex),
    ),
  );
}

/// Ikona typu ćwiczenia: czasowe / siłowe / powtórzeniowe.
IconData planItemTypeIcon(PlanItem item, Exercise exercise) {
  if (item.suggestedWeightKg > 0) return Icons.fitness_center_rounded;
  if (item.durationSec > 0 || (exercise.defaultDurationSec > 0 && item.reps == 0)) {
    return Icons.timer_outlined;
  }
  return Icons.repeat_rounded;
}

/// Krótki opis parametrów pozycji planu (czas albo serie × powtórzenia [+ ciężar]).
String planItemMetaText(PlanItem item, Exercise exercise) {
  if (item.durationSec > 0) return '${item.sets} × ${item.durationSec}s';
  if (item.reps == 0 && exercise.defaultDurationSec > 0) {
    return '${item.sets} × ${exercise.defaultDurationSec}s';
  }
  final weight = item.suggestedWeightKg > 0 ? ' · ${_formatPlanWeight(item.suggestedWeightKg)} kg' : '';
  return '${item.sets} × ${item.reps} powt.$weight';
}

class WorkoutDayDetailsPage extends StatefulWidget {
  const WorkoutDayDetailsPage({super.key, required this.planId, required this.dayIndex});

  final String planId;
  final int dayIndex;

  @override
  State<WorkoutDayDetailsPage> createState() => _WorkoutDayDetailsPageState();
}

class _WorkoutDayDetailsPageState extends State<WorkoutDayDetailsPage> {
  bool _compact = false;

  WorkoutPlan? _findPlan(AppStore store) {
    for (final plan in store.plans) {
      if (plan.id == widget.planId) return plan;
    }
    return null;
  }

  Future<void> _swapItem(AppStore store, WorkoutPlan plan, WorkoutDay day, int itemIndex) async {
    final item = day.items[itemIndex];
    final picked = await pickExerciseFromLibrary(
      context,
      title: 'Zamień ćwiczenie',
      subtitle: 'Parametry serii/powtórzeń zostaną zachowane.',
      excludeIds: day.items.map((entry) => entry.exerciseId).toSet(),
    );
    if (picked == null) return;
    final items = [...day.items];
    items[itemIndex] = item.copyWith(exerciseId: picked.id);
    await store.updatePlanDayItems(plan.id, widget.dayIndex, items);
  }

  Future<void> _removeItem(AppStore store, WorkoutPlan plan, WorkoutDay day, int itemIndex) async {
    final items = [...day.items]..removeAt(itemIndex);
    await store.updatePlanDayItems(plan.id, widget.dayIndex, items);
  }

  void _openTechnique(Exercise exercise) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ExerciseDetailsPage(exerciseId: exercise.id)),
    );
  }

  Future<void> _openGuide(WorkoutPlan plan, WorkoutDay day) async {
    final store = AppScope.read(context);
    if (day.items.isEmpty) return;
    final exercise = await showModalBottomSheet<Exercise>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('Technika ćwiczeń', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in day.items)
                    Builder(builder: (context) {
                      final exercise = item.exerciseFrom(store.customExercises);
                      return ListTile(
                        leading: SizedBox(width: 44, height: 44, child: ExerciseVisual(exercise: exercise)),
                        title: Text(exercise.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(sheetContext, exercise),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (exercise != null && mounted) _openTechnique(exercise);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final plan = _findPlan(store);
    final theme = Theme.of(context);

    if (plan == null || widget.dayIndex < 0 || widget.dayIndex >= plan.days.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Szczegóły dnia')),
        body: const _ProgramEmptyState(),
      );
    }

    final day = plan.days[widget.dayIndex];
    final status = plan.statusForDay(widget.dayIndex);
    final isRest = status == WorkoutDayStatus.rest || (plan.isRestDay(day) && status != WorkoutDayStatus.completed);
    final isLocked = status == WorkoutDayStatus.locked;
    final estimate = estimatePlanDay(day, store.customExercises, store.settings.bodyWeightKg);

    final equipment = <EquipmentType>{};
    final muscles = <MuscleGroup>{};
    final dayExercises = <Exercise>[];
    for (final item in day.items) {
      final exercise = item.exerciseFrom(store.customExercises);
      dayExercises.add(exercise);
      equipment.addAll(exercise.equipmentTypes);
      muscles.addAll(exercise.muscleGroups);
    }
    final recoveryWarnings = recoveryWarningsForExercises(dayExercises, store.muscleRecoveryMap());

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _DayDetailsHeader(
            plan: plan,
            dayIndex: widget.dayIndex,
            estimate: estimate,
            status: status,
            isRest: isRest,
            onBack: () => Navigator.of(context).maybePop(),
            menu: _buildMenu(store, plan, day),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayGuideCard(
                  hasExercises: day.items.isNotEmpty,
                  onOpen: () => _openGuide(plan, day),
                ),
                const SizedBox(height: 16),
                if (isRest)
                  const _RestDayView()
                else if (day.items.isEmpty)
                  EmptyCard(
                    icon: Icons.fitness_center_rounded,
                    title: 'Brak ćwiczeń w tym dniu',
                    text: 'Dodaj ćwiczenia, aby rozpocząć trening.',
                    buttonLabel: 'Dodaj ćwiczenie',
                    onPressed: () => showPlanExercisePicker(context, plan: plan, day: day),
                  )
                else ...[
                  if (recoveryWarnings.isNotEmpty) ...[
                    RecoveryWarningBanner(warnings: recoveryWarnings),
                    const SizedBox(height: 14),
                  ],
                  if (equipment.isNotEmpty)
                    _TagSection(
                      icon: Icons.fitness_center_outlined,
                      title: 'Sprzęt potrzebny',
                      labels: equipment.map((type) => type.label).toList(),
                    ),
                  if (muscles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TagSection(
                      icon: Icons.accessibility_new_rounded,
                      title: 'Partie trenowane',
                      labels: muscles.map((group) => group.label).toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${day.items.length} ćwiczeń', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded, size: 18), label: Text('Lista')),
                        ButtonSegment(value: true, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('Kompakt')),
                      ],
                      selected: {_compact},
                      onSelectionChanged: (selection) => setState(() => _compact = selection.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < day.items.length; i++)
                    _DayExerciseTile(
                      exercise: day.items[i].exerciseFrom(store.customExercises),
                      item: day.items[i],
                      position: i + 1,
                      compact: _compact,
                      onTechnique: () => _openTechnique(day.items[i].exerciseFrom(store.customExercises)),
                      onSwap: () => _swapItem(store, plan, day, i),
                      onRemove: () => _removeItem(store, plan, day, i),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _DayStartBar(
        plan: plan,
        dayIndex: widget.dayIndex,
        day: day,
        status: status,
        isRest: isRest,
        isLocked: isLocked,
      ),
    );
  }

  Widget _buildMenu(AppStore store, WorkoutPlan plan, WorkoutDay day) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      tooltip: 'Opcje dnia',
      onSelected: (value) async {
        switch (value) {
          case 'add':
            await showPlanExercisePicker(context, plan: plan, day: day);
            break;
          case 'editPlan':
            await showWorkoutPlanEditor(context, plan: plan);
            break;
          case 'guide':
            await _openGuide(plan, day);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'add', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.playlist_add_rounded), title: Text('Dodaj ćwiczenie'))),
        PopupMenuItem(value: 'guide', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.menu_book_outlined), title: Text('Przewodnik / technika'))),
        PopupMenuItem(value: 'editPlan', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_calendar_outlined), title: Text('Edytuj plan'))),
      ],
    );
  }
}

/// Nagłówek szczegółów dnia: obraz/gradient, powrót, menu, program + poziom,
/// „Dzień X", czas, kcal, liczba ćwiczeń, status.
class _DayDetailsHeader extends StatelessWidget {
  const _DayDetailsHeader({
    required this.plan,
    required this.dayIndex,
    required this.estimate,
    required this.status,
    required this.isRest,
    required this.onBack,
    required this.menu,
  });

  final WorkoutPlan plan;
  final int dayIndex;
  final PlanDayEstimate estimate;
  final WorkoutDayStatus status;
  final bool isRest;
  final VoidCallback onBack;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = plan.level.trim();
    final day = plan.days[dayIndex];
    return SizedBox(
      height: 270,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (plan.imageAsset != null && plan.imageAsset!.trim().isNotEmpty)
            buildExerciseMediaImage(plan.imageAsset!, fit: BoxFit.cover, fallback: _gradient(scheme))
          else
            _gradient(scheme),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.74)],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), tooltip: 'Wstecz'),
                  const Spacer(),
                  menu,
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [plan.name, if (level.isNotEmpty) level].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Dzień ${dayIndex + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ),
                    _DayStatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isRest ? 'Dzień odpoczynku' : day.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: isRest
                      ? const [_HeaderChip(icon: Icons.self_improvement_rounded, label: 'Regeneracja')]
                      : [
                          _HeaderChip(icon: Icons.timer_outlined, label: '~${estimate.minutes} min'),
                          _HeaderChip(icon: Icons.local_fire_department_outlined, label: '${estimate.kcal} kcal'),
                          _HeaderChip(icon: Icons.format_list_numbered_rounded, label: '${estimate.exerciseCount} ćw.'),
                        ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradient(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.primaryContainer, scheme.surfaceContainerHighest],
          ),
        ),
      );
}

class _DayStatusBadge extends StatelessWidget {
  const _DayStatusBadge({required this.status});

  final WorkoutDayStatus status;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    switch (status) {
      case WorkoutDayStatus.completed:
        icon = Icons.check_circle_rounded;
        label = 'Ukończony';
        break;
      case WorkoutDayStatus.locked:
        icon = Icons.lock_rounded;
        label = 'Zablokowany';
        break;
      case WorkoutDayStatus.rest:
        icon = Icons.local_cafe_rounded;
        label = 'Odpoczynek';
        break;
      case WorkoutDayStatus.active:
        icon = Icons.bolt_rounded;
        label = 'Dostępny';
        break;
      case WorkoutDayStatus.available:
        icon = Icons.check_circle_outline_rounded;
        label = 'Dostępny';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Sekcja „Przewodnik": avatar trenera + opis + przejście do techniki.
class _DayGuideCard extends StatelessWidget {
  const _DayGuideCard({required this.hasExercises, required this.onOpen});

  final bool hasExercises;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasExercises ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.sports_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Przewodnik', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      hasExercises ? 'Instrukcje ćwiczeń i wideo trenera' : 'Dodaj ćwiczenia, aby zobaczyć instrukcje',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (hasExercises) Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sekcja z chipami (sprzęt / partie trenowane).
class _TagSection extends StatelessWidget {
  const _TagSection({required this.icon, required this.title, required this.labels});

  final IconData icon;
  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final label in labels) MiniTag(text: label)],
        ),
      ],
    );
  }
}

/// Miniatura ćwiczenia na liście dnia z bezpiecznym fallbackiem i znacznikiem mediów.
class _ExerciseListThumb extends StatelessWidget {
  const _ExerciseListThumb({required this.exercise, this.size = 56});

  final Exercise exercise;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMedia = exercise.hasMedia || exercise.hasVideo;
    final badgeIcon = exercise.animatedMediaPath != null
        ? Icons.gif_box_rounded
        : exercise.hasVideo
            ? Icons.movie_rounded
            : Icons.image_rounded;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ExerciseVisual(exercise: exercise),
            ),
          ),
          if (hasMedia)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(badgeIcon, size: 11, color: theme.colorScheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kafelek ćwiczenia na liście dnia (tryb listy i kompaktowy).
class _DayExerciseTile extends StatelessWidget {
  const _DayExerciseTile({
    required this.exercise,
    required this.item,
    required this.position,
    required this.compact,
    required this.onTechnique,
    required this.onSwap,
    required this.onRemove,
  });

  final Exercise exercise;
  final PlanItem item;
  final int position;
  final bool compact;
  final VoidCallback onTechnique;
  final VoidCallback onSwap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = planItemMetaText(item, exercise);
    final typeIcon = planItemTypeIcon(item, exercise);

    final menu = PopupMenuButton<String>(
      tooltip: 'Szybkie opcje',
      onSelected: (value) {
        switch (value) {
          case 'technique':
            onTechnique();
            break;
          case 'swap':
            onSwap();
            break;
          case 'remove':
            onRemove();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'technique', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.menu_book_outlined), title: Text('Zobacz technikę'))),
        PopupMenuItem(value: 'swap', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.swap_horiz_rounded), title: Text('Zamień ćwiczenie'))),
        PopupMenuItem(value: 'remove', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded), title: Text('Usuń z tego dnia'))),
      ],
    );

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _ExerciseListThumb(exercise: exercise, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$position. ${exercise.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Row(
                    children: [
                      Icon(typeIcon, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                    ],
                  ),
                ],
              ),
            ),
            menu,
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          _ExerciseListThumb(exercise: exercise, size: 60),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$position. ${exercise.name}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(typeIcon, size: 15, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (exercise.hasMedia || exercise.hasVideo) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.play_circle_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
                    ],
                  ],
                ),
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}

/// Ekran dnia odpoczynku zamiast listy ćwiczeń.
class _RestDayView extends StatelessWidget {
  const _RestDayView();

  @override
  Widget build(BuildContext context) {
    const tips = [
      (Icons.bedtime_outlined, 'Regeneracja', 'Daj mięśniom czas na odbudowę — sen i lekki dzień robią różnicę.'),
      (Icons.directions_walk_rounded, 'Spacer', 'Lekki spacer 20–30 min poprawia krążenie i przyspiesza regenerację.'),
      (Icons.self_improvement_rounded, 'Mobilność', 'Krótka sesja rozciągania/mobility utrzyma zakres ruchu.'),
      (Icons.local_drink_outlined, 'Nawodnienie', 'Pij wodę regularnie — wspiera regenerację i samopoczucie.'),
    ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dziś odpoczywasz', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Wykorzystaj ten dzień na regenerację, aby wrócić silniejszym.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        for (final tip in tips)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(tip.$1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tip.$2, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(tip.$3, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dolny, „przyklejony" pasek z głównym przyciskiem (START / odpoczynek / zablokowane).
class _DayStartBar extends StatelessWidget {
  const _DayStartBar({
    required this.plan,
    required this.dayIndex,
    required this.day,
    required this.status,
    required this.isRest,
    required this.isLocked,
  });

  final WorkoutPlan plan;
  final int dayIndex;
  final WorkoutDay day;
  final WorkoutDayStatus status;
  final bool isRest;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context);
    final isCompleted = status == WorkoutDayStatus.completed;

    Widget button;
    if (isLocked) {
      button = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Odblokuje się po ukończeniu poprzedniego dnia',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Zablokowane'),
          ),
        ],
      );
    } else if (isRest) {
      button = FilledButton.tonalIcon(
        onPressed: () async {
          await store.setPlanDayCompleted(plan.id, dayIndex);
          if (context.mounted) Navigator.of(context).maybePop();
        },
        icon: const Icon(Icons.check_rounded),
        label: const Text('Zalicz dzień odpoczynku'),
      );
    } else {
      button = FilledButton.icon(
        onPressed: day.items.isEmpty ? null : () => startWorkoutForDay(context, plan: plan, day: day, dayIndex: dayIndex),
        icon: Icon(isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded),
        label: Text(isCompleted ? 'Powtórz trening' : 'START'),
      );
    }

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: button,
          ),
        ),
      ),
    );
  }
}

class _PlanExerciseTile extends StatelessWidget {
  const _PlanExerciseTile({required this.plan, required this.day, required this.item, required this.exercise});

  final WorkoutPlan plan;
  final WorkoutDay day;
  final PlanItem item;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context);
    final weight = item.suggestedWeightKg > 0 ? '${_formatPlanWeight(item.suggestedWeightKg)} kg' : 'bez ciężaru';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          SizedBox(width: 48, height: 48, child: ExerciseVisual(exercise: exercise)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${item.sets} serie × ${item.reps} powt. · $weight · ${item.restSeconds} s przerwy', maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opcje ćwiczenia',
            onSelected: (value) async {
              if (value == 'edit') {
                await showPlanItemEditor(context, plan: plan, day: day, exercise: exercise, existing: item);
              } else if (value == 'delete') {
                await store.removePlanItem(planId: plan.id, weekday: day.weekday, exerciseId: item.exerciseId);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.tune_rounded), title: Text('Edytuj parametry'))),
              PopupMenuItem(value: 'delete', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline), title: Text('Usuń z dnia'))),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatPlanWeight(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

Future<void> showWorkoutPlanEditor(BuildContext context, {WorkoutPlan? plan}) async {
  final store = AppScope.read(context);
  var planName = plan?.name ?? '';
  var goal = normalizeWorkoutPlanGoal(plan?.goal ?? store.settings.goal);
  final selectedWeekdays = <int>{
    if (plan != null) ...plan.days.map((day) => day.weekday) else ...store.settings.trainingWeekdays,
  };
  if (selectedWeekdays.isEmpty) selectedWeekdays.addAll(const [1, 3, 5]);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(plan == null ? 'Nowy plan treningowy' : 'Edytuj plan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: planName,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nazwa planu'),
                onChanged: (value) => planName = value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: goal,
                decoration: const InputDecoration(labelText: 'Cel planu'),
                items: workoutPlanGoals.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => setSheetState(() => goal = value ?? goal),
              ),
              const SizedBox(height: 16),
              Text('Dni tygodnia', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    FilterChip(
                      label: Text(weekdayName(weekday)),
                      selected: selectedWeekdays.contains(weekday),
                      onSelected: (selected) {
                        setSheetState(() {
                          if (selected) {
                            selectedWeekdays.add(weekday);
                          } else {
                            selectedWeekdays.remove(weekday);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Usunięcie zaznaczenia dnia usunie go z planu razem z przypisanymi ćwiczeniami.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  final cleanedName = planName.trim();
                  if (cleanedName.isEmpty) {
                    showError(sheetContext, 'Wpisz nazwę planu.');
                    return;
                  }
                  if (selectedWeekdays.isEmpty) {
                    showError(sheetContext, 'Wybierz przynajmniej jeden dzień tygodnia.');
                    return;
                  }
                  final weekdays = selectedWeekdays.toList()..sort();
                  final days = <WorkoutDay>[];
                  for (final weekday in weekdays) {
                    WorkoutDay? existingDay;
                    if (plan != null) {
                      for (final day in plan.days) {
                        if (day.weekday == weekday) {
                          existingDay = day;
                          break;
                        }
                      }
                    }
                    days.add(existingDay ?? WorkoutDay(weekday: weekday, title: 'Trening', items: const []));
                  }
                  final updated = WorkoutPlan(
                    id: plan?.id ?? 'plan_${idNow()}',
                    name: cleanedName,
                    days: days,
                    note: plan?.note ?? 'Plan utworzony ręcznie.',
                    goal: goal,
                    isActive: plan?.isActive ?? store.plans.isEmpty,
                  );
                  if (plan == null) {
                    await store.addWorkoutPlan(updated);
                  } else {
                    await store.updateWorkoutPlan(updated);
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.save_outlined),
                label: Text(plan == null ? 'Utwórz plan' : 'Zapisz zmiany'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showDeleteWorkoutPlanDialog(BuildContext context, WorkoutPlan plan) async {
  final store = AppScope.read(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Usunąć plan?'),
      content: Text('Plan „${plan.name}” oraz wszystkie przypisane dni zostaną usunięte lokalnie.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Usuń')),
      ],
    ),
  );
  if (confirmed == true) await store.deleteWorkoutPlan(plan.id);
}

Future<void> showCopyWorkoutDaySheet(BuildContext context, {required WorkoutPlan plan, required WorkoutDay day}) async {
  final store = AppScope.read(context);
  final hostContext = context;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kopiuj ${weekdayName(day.weekday)}', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Wybierz dzień docelowy. Jeśli już istnieje, jego zawartość zostanie zastąpiona.', style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  if (weekday != day.weekday)
                    ListTile(
                      leading: CircleAvatar(child: Text('$weekday')),
                      title: Text(weekdayName(weekday)),
                      subtitle: Text(plan.days.any((entry) => entry.weekday == weekday) ? 'Zastąpi istniejący dzień' : 'Doda nowy dzień do planu'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final copied = await store.copyWorkoutDay(planId: plan.id, sourceWeekday: day.weekday, targetWeekday: weekday);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (hostContext.mounted && copied) showError(hostContext, 'Skopiowano dzień na ${weekdayName(weekday)}.');
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showPlanExercisePicker(BuildContext context, {required WorkoutPlan plan, required WorkoutDay day}) async {
  final store = AppScope.read(context);
  var query = '';
  final selected = await showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final exercises = ExerciseRepo.combined(store.customExercises).where((exercise) {
          if (store.isExerciseHidden(exercise.id)) return false;
          return query.isEmpty || exercise.name.toLowerCase().contains(query);
        }).toList();
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Dodaj ćwiczenie', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${plan.name} · ${weekdayName(day.weekday)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Szukaj po nazwie'),
                      onChanged: (value) => setSheetState(() => query = value.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: exercises.isEmpty
                    ? const Center(child: Text('Brak pasujących ćwiczeń'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          final alreadyAdded = day.items.any((item) => item.exerciseId == exercise.id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: SizedBox(width: 48, height: 48, child: ExerciseVisual(exercise: exercise)),
                              title: Text(exercise.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${exercise.primaryMuscle} · ${exercise.equipment}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: Icon(alreadyAdded ? Icons.tune_rounded : Icons.add_circle_outline_rounded),
                              onTap: () => Navigator.pop(sheetContext, exercise),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (!context.mounted || selected == null) return;
  PlanItem? existing;
  for (final item in day.items) {
    if (item.exerciseId == selected.id) {
      existing = item;
      break;
    }
  }
  await showPlanItemEditor(context, plan: plan, day: day, exercise: selected, existing: existing);
}

Future<void> showPlanItemEditor(
  BuildContext context, {
  required WorkoutPlan plan,
  required WorkoutDay day,
  required Exercise exercise,
  PlanItem? existing,
}) async {
  final store = AppScope.read(context);
  var setsValue = '${existing?.sets ?? exercise.defaultSets}';
  var repsValue = '${existing?.reps ?? (exercise.defaultReps > 0 ? exercise.defaultReps : 10)}';
  var weightValue = _formatPlanWeight(existing?.suggestedWeightKg ?? 0);
  var restValue = '${existing?.restSeconds ?? 90}';
  var noteValue = existing?.note ?? '';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(sheetContext).viewInsets.bottom + MediaQuery.of(sheetContext).viewPadding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(existing == null ? 'Dodaj do dnia' : 'Edytuj ćwiczenie', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${exercise.name} · ${weekdayName(day.weekday)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: setsValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Liczba serii'),
                    onChanged: (value) => setsValue = value,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: repsValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Powtórzenia'),
                    onChanged: (value) => repsValue = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: weightValue,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ciężar (kg)'),
                    onChanged: (value) => weightValue = value,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: restValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Przerwa (s)'),
                    onChanged: (value) => restValue = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: noteValue,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notatka (opcjonalnie)'),
              onChanged: (value) => noteValue = value,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final parsedSets = int.tryParse(setsValue.trim());
                final parsedReps = int.tryParse(repsValue.trim());
                final parsedWeight = double.tryParse(weightValue.trim().replaceAll(',', '.'));
                final parsedRest = int.tryParse(restValue.trim());
                if (parsedSets == null || parsedSets < 1 || parsedSets > 99) {
                  showError(sheetContext, 'Liczba serii musi mieścić się w zakresie 1–99.');
                  return;
                }
                if (parsedReps == null || parsedReps < 1 || parsedReps > 999) {
                  showError(sheetContext, 'Liczba powtórzeń musi mieścić się w zakresie 1–999.');
                  return;
                }
                if (parsedWeight == null || parsedWeight < 0 || parsedWeight > 9999) {
                  showError(sheetContext, 'Podaj poprawny sugerowany ciężar.');
                  return;
                }
                if (parsedRest == null || parsedRest < 0 || parsedRest > 3600) {
                  showError(sheetContext, 'Przerwa musi mieścić się w zakresie 0–3600 sekund.');
                  return;
                }
                await store.upsertPlanItem(
                  planId: plan.id,
                  weekday: day.weekday,
                  item: PlanItem(
                    exerciseId: exercise.id,
                    sets: parsedSets,
                    reps: parsedReps,
                    durationSec: existing?.durationSec ?? exercise.defaultDurationSec,
                    note: noteValue.trim(),
                    suggestedWeightKg: parsedWeight,
                    restSeconds: parsedRest,
                  ),
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(existing == null ? 'Dodaj ćwiczenie' : 'Zapisz parametry'),
            ),
          ],
        ),
      ),
    ),
  );
}

void showPlanGenerator(BuildContext context) {
  final store = AppScope.read(context);
  final goal = TextEditingController(text: store.settings.goal);
  final equipment = TextEditingController(text: store.settings.equipment);
  final limitations = TextEditingController(text: store.settings.limitations);
  int days = store.settings.trainingWeekdays.length.clamp(2, 6).toInt();
  var level = normalizeLevel(store.settings.level);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(builder: (context, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Generator planu AI', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(controller: goal, decoration: const InputDecoration(labelText: 'Cel')),
                const SizedBox(height: 10),
                TextField(controller: equipment, decoration: const InputDecoration(labelText: 'Sprzęt')),
                const SizedBox(height: 10),
                TextField(controller: limitations, maxLines: 3, decoration: const InputDecoration(labelText: 'Ograniczenia / kontuzje / uwagi')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: level,
                  decoration: const InputDecoration(labelText: 'Poziom planu'),
                  selectedItemBuilder: (context) => kTrainingLevels.map((v) => Align(alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                  items: kTrainingLevels.map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setSheet(() => level = v ?? level),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Dni w tygodniu'),
                    Expanded(child: Slider(value: days.toDouble(), min: 2, max: 6, divisions: 4, label: '$days', onChanged: (v) => setSheet(() => days = v.round()))),
                    Text('$days'),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: store.aiBusy
                      ? null
                      : () async {
                          try {
                            await store.updateSettings(store.settings.copyWith(level: level, equipment: equipment.text.trim(), limitations: limitations.text.trim(), backendUrl: kDefaultBackendUrl));
                            await store.generateAiPlan(goal: goal.text, days: days, equipment: equipment.text, limitations: limitations.text);
                            if (!context.mounted) return;
                            Navigator.pop(sheetContext);
                          } catch (e) {
                            if (!context.mounted) return;
                            showError(context, e.toString());
                          }
                        },
                  icon: store.aiBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                  label: const Text('Wygeneruj przez backend'),
                ),
              ],
            ),
          ),
        );
      });
    },
  ).whenComplete(() {
    goal.dispose();
    equipment.dispose();
    limitations.dispose();
  });
}

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final now = DateTime.now();
    final weekStart = startOfTrainingWeek(now);
    final monthStart = DateTime(now.year, now.month);
    final weekDays = List.generate(7, (index) => weekStart.add(Duration(days: index)));
    final weekLogs = store.logsBetween(weekStart, now);
    final monthLogs = store.logsBetween(monthStart, now);
    final weekTotals = DayTotals.from(weekLogs);
    final monthTotals = DayTotals.from(monthLogs);
    final weekWorkoutCount = workoutEntryCount(weekLogs);
    final monthWorkoutCount = workoutEntryCount(monthLogs);
    final weekVolumeValues = weekDays.map((day) => store.totalsForDay(day).volume).toList();
    final weekVolumeLabels = weekDays.map((day) => weekdayShortName(day.weekday)).toList();
    final recentWeekStarts = List.generate(4, (index) => weekStart.subtract(Duration(days: (3 - index) * 7)));
    final workoutCountValues = recentWeekStarts
        .map(
          (start) => workoutEntryCount(
            store.logsBetween(start, start.add(const Duration(days: 6))),
          ).toDouble(),
        )
        .toList();
    final workoutCountLabels = ['T-3', 'T-2', 'T-1', 'Teraz'];
    return PageFrame(
      title: 'Progres',
      subtitle: 'Podstawowe statystyki tygodnia i miesiąca',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressSummaryTiles(
            weekWorkoutCount: weekWorkoutCount,
            monthWorkoutCount: monthWorkoutCount,
            weekVolume: weekTotals.volume,
            monthVolume: monthTotals.volume,
            weekSets: completedWorkoutSetCount(weekLogs),
            monthSets: completedWorkoutSetCount(monthLogs),
          ),
          const SizedBox(height: 16),
          SimpleProgressBarChartCard(
            title: 'Objętość tygodniowa',
            subtitle: 'Suma ciężar × powtórzenia z każdego dnia bieżącego tygodnia',
            values: weekVolumeValues,
            labels: weekVolumeLabels,
            suffix: 'kg',
            icon: Icons.monitor_weight_outlined,
          ),
          const SizedBox(height: 12),
          SimpleProgressBarChartCard(
            title: 'Liczba treningów',
            subtitle: 'Unikalne sesje treningowe w ostatnich czterech tygodniach',
            values: workoutCountValues,
            labels: workoutCountLabels,
            suffix: 'tr.',
            icon: Icons.event_available_outlined,
          ),
          const SizedBox(height: 12),
          BasicMuscleFrequencyCard(logs: monthLogs, customExercises: store.customExercises),
        ],
      ),
    );
  }
}

class ProgressSummaryTiles extends StatelessWidget {
  const ProgressSummaryTiles({
    super.key,
    required this.weekWorkoutCount,
    required this.monthWorkoutCount,
    required this.weekVolume,
    required this.monthVolume,
    required this.weekSets,
    required this.monthSets,
  });

  final int weekWorkoutCount;
  final int monthWorkoutCount;
  final double weekVolume;
  final double monthVolume;
  final int weekSets;
  final int monthSets;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth >= 420
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_week_workouts'),
                label: 'Treningi tydzień',
                value: '$weekWorkoutCount',
                helper: 'unikalne sesje',
                icon: Icons.calendar_view_week_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_month_workouts'),
                label: 'Treningi miesiąc',
                value: '$monthWorkoutCount',
                helper: 'unikalne sesje',
                icon: Icons.calendar_month_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_week_volume'),
                label: 'Objętość tydzień',
                value: formatProgressVolume(weekVolume),
                helper: 'kg łącznie',
                icon: Icons.fitness_center_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_month_volume'),
                label: 'Objętość miesiąc',
                value: formatProgressVolume(monthVolume),
                helper: 'kg łącznie',
                icon: Icons.monitor_weight_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_week_sets'),
                label: 'Serie tydzień',
                value: '$weekSets',
                helper: 'wykonane serie',
                icon: Icons.repeat_rounded,
              ),
            ),
            SizedBox(
              width: width,
              child: ProgressMetricTile(
                key: const Key('progress_month_sets'),
                label: 'Serie miesiąc',
                value: '$monthSets',
                helper: 'wykonane serie',
                icon: Icons.checklist_rtl_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ProgressMetricTile extends StatelessWidget {
  const ProgressMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(helper, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleProgressBarChartCard extends StatelessWidget {
  const SimpleProgressBarChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.values,
    required this.labels,
    required this.suffix,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<double> values;
  final List<String> labels;
  final String suffix;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = values.isEmpty ? 0.0 : values.reduce(math.max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < values.length; index++) ...[
                    Expanded(
                      child: _ProgressBarColumn(
                        value: values[index],
                        max: max,
                        label: index < labels.length ? labels[index] : '',
                        suffix: suffix,
                      ),
                    ),
                    if (index < values.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              max == 0 ? 'Brak danych w tym okresie.' : 'Najwyższa wartość: ${max.round()} $suffix',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBarColumn extends StatelessWidget {
  const _ProgressBarColumn({
    required this.value,
    required this.max,
    required this.label,
    required this.suffix,
  });

  final double value;
  final double max;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 28,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value == 0 ? '0' : '${value.round()} $suffix', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: math.max(0.04, ratio),
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.55),
                      theme.colorScheme.primary,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class BasicMuscleFrequencyCard extends StatelessWidget {
  const BasicMuscleFrequencyCard({
    super.key,
    required this.logs,
    required this.customExercises,
  });

  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = muscleCounts(logs, customExercises);
    final most = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final least = counts.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final max = most.isEmpty ? 1 : most.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Partie mięśniowe', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 4),
            Text('Najczęściej i najrzadziej trenowane partie w bieżącym miesiącu.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (most.isEmpty)
              Text('Brak danych. Zakończ trening, a Trainer pokaże rozkład partii.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 520;
                  final frequent = _MuscleRankColumn(title: 'Najczęściej trenowane partie', entries: most.take(5).toList(), max: max);
                  final rare = _MuscleRankColumn(title: 'Najrzadziej trenowane partie', entries: least.take(5).toList(), max: max);
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        frequent,
                        const SizedBox(height: 14),
                        rare,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: frequent),
                      const SizedBox(width: 16),
                      Expanded(child: rare),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MuscleRankColumn extends StatelessWidget {
  const _MuscleRankColumn({
    required this.title,
    required this.entries,
    required this.max,
  });

  final String title;
  final List<MapEntry<String, int>> entries;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final entry in entries) ProgressTextBar(label: entry.key, value: entry.value.toDouble(), max: max.toDouble(), suffix: '${entry.value}×'),
      ],
    );
  }
}

class LegacyProgressPage extends StatelessWidget {
  const LegacyProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 13));
    final days = List.generate(14, (i) => DateTime(start.year, start.month, start.day).add(Duration(days: i)));
    final calories = days.map((d) => store.totalsForDay(d).calories).toList();
    final duration = days.map((d) => store.totalsForDay(d).durationSec / 60).toList();
    final volume = days.map((d) => store.totalsForDay(d).volume).toList();
    final all = store.logsBetween(start, end);
    final total = DayTotals.from(all);
    return PageFrame(
      title: 'Postęp',
      subtitle: 'Ostatnie 14 dni i suma treningów',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: StatCard(label: 'Kcal 14 dni', value: '${total.calories.round()}', icon: Icons.local_fire_department_outlined)),
            const SizedBox(width: 10),
            Expanded(child: StatCard(label: 'Czas 14 dni', value: '${(total.durationSec / 60).round()} min', icon: Icons.timer)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: StatCard(label: 'Objętość', value: '${total.volume.round()} kg', icon: Icons.monitor_weight)),
            const SizedBox(width: 10),
            Expanded(child: StatCard(label: 'Wpisy', value: '${total.sessions}', icon: Icons.checklist)),
          ]),
          const SizedBox(height: 16),
          ChartCard(title: 'Kalorie', values: calories, suffix: 'kcal'),
          const SizedBox(height: 12),
          ChartCard(title: 'Czas treningu', values: duration, suffix: 'min'),
          const SizedBox(height: 12),
          ChartCard(title: 'Objętość siłowa', values: volume, suffix: 'kg'),
          const SizedBox(height: 12),
          MuscleDistributionCard(logs: all, customExercises: store.customExercises),
        ],
      ),
    );
  }
}

class ChartCard extends StatelessWidget {
  final String title;
  final List<double> values;
  final String suffix;

  const ChartCard({super.key, required this.title, required this.values, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final max = values.isEmpty ? 0 : values.reduce(math.max);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: ProgressLineChart(values: values)),
            const SizedBox(height: 8),
            Text('Max: ${max.round()} $suffix', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class ProgressLineChart extends StatelessWidget {
  final List<double> values;

  const ProgressLineChart({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: ProgressLinePainter(values: values, color: Theme.of(context).colorScheme.primary), child: const SizedBox.expand());
  }
}

class ProgressLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  ProgressLinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color.withOpacity(0.13)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maxValue = math.max(1.0, values.reduce(math.max));
    final step = values.length == 1 ? size.width : size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxValue) * (size.height - 12) - 6;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..color = color.withOpacity(0.10)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxValue) * (size.height - 12) - 6;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant ProgressLinePainter oldDelegate) => oldDelegate.values != values || oldDelegate.color != color;
}

class MuscleDistributionCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;

  const MuscleDistributionCard({super.key, required this.logs, this.customExercises = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = <String, int>{};
    for (final log in logs) {
      for (final m in log.exerciseFrom(customExercises).muscles.take(2)) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Najczęściej trenowane partie', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text('Brak danych z ostatnich 14 dni.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              ...entries.take(8).map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key)),
                        Text('${e.value}×', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class BodyMeasurementsPage extends StatelessWidget {
  const BodyMeasurementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final measurements = [...store.bodyMeasurements]..sort((left, right) => right.date.compareTo(left.date));
    return PageFrame(
      title: 'Pomiary sylwetki',
      subtitle: 'Waga, obwody, notatki i lokalna historia zmian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BodyMeasurementFormCard(store: store),
          const SizedBox(height: 12),
          const ProgressPhotoPlaceholderCard(),
          const SizedBox(height: 12),
          if (measurements.isNotEmpty) ...[
            BodyMeasurementChartsCard(measurements: measurements),
            const SizedBox(height: 12),
          ],
          BodyMeasurementHistoryCard(measurements: measurements),
        ],
      ),
    );
  }
}

class BodyMeasurementFormCard extends StatefulWidget {
  const BodyMeasurementFormCard({super.key, required this.store});

  final AppStore store;

  @override
  State<BodyMeasurementFormCard> createState() => _BodyMeasurementFormCardState();
}

class _BodyMeasurementFormCardState extends State<BodyMeasurementFormCard> {
  late DateTime selectedDate;
  late final TextEditingController weight;
  late final TextEditingController waist;
  late final TextEditingController chest;
  late final TextEditingController arm;
  late final TextEditingController thigh;
  late final TextEditingController hips;
  late final TextEditingController calf;
  late final TextEditingController shoulders;
  late final TextEditingController note;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
    weight = TextEditingController();
    waist = TextEditingController();
    chest = TextEditingController();
    arm = TextEditingController();
    thigh = TextEditingController();
    hips = TextEditingController();
    calf = TextEditingController();
    shoulders = TextEditingController();
    note = TextEditingController();
  }

  @override
  void dispose() {
    weight.dispose();
    waist.dispose();
    chest.dispose();
    arm.dispose();
    thigh.dispose();
    hips.dispose();
    calf.dispose();
    shoulders.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data pomiaru',
    );
    if (picked == null || !mounted) return;
    setState(() => selectedDate = picked);
  }

  Future<void> save() async {
    final now = DateTime.now();
    final measurement = BodyMeasurement(
      id: 'measurement_${idNow()}',
      date: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, now.hour, now.minute),
      weightKg: parseBodyMeasurementValue(weight.text),
      waistCm: parseBodyMeasurementValue(waist.text),
      chestCm: parseBodyMeasurementValue(chest.text),
      armCm: parseBodyMeasurementValue(arm.text),
      thighCm: parseBodyMeasurementValue(thigh.text),
      hipsCm: parseBodyMeasurementValue(hips.text),
      calfCm: parseBodyMeasurementValue(calf.text),
      shouldersCm: parseBodyMeasurementValue(shoulders.text),
      note: note.text.trim(),
    );
    if (!measurement.hasAnyMeasurement && measurement.note.isEmpty) {
      showError(context, 'Dodaj przynajmniej jeden pomiar albo notatkę.');
      return;
    }
    await widget.store.addBodyMeasurement(measurement);
    if (!mounted) return;
    weight.clear();
    waist.clear();
    chest.clear();
    arm.clear();
    thigh.clear();
    hips.clear();
    calf.clear();
    shoulders.clear();
    note.clear();
    setState(() => selectedDate = DateTime.now());
    showError(context, 'Zapisano pomiar sylwetki.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = [
      _BodyMeasurementField(controller: weight, label: 'Waga kg', keyValue: 'measurement_weight'),
      _BodyMeasurementField(controller: waist, label: 'Pas cm', keyValue: 'measurement_waist'),
      _BodyMeasurementField(controller: chest, label: 'Klatka cm', keyValue: 'measurement_chest'),
      _BodyMeasurementField(controller: arm, label: 'Ramię cm', keyValue: 'measurement_arm'),
      _BodyMeasurementField(controller: thigh, label: 'Udo cm', keyValue: 'measurement_thigh'),
      _BodyMeasurementField(controller: hips, label: 'Biodra cm', keyValue: 'measurement_hips'),
      _BodyMeasurementField(controller: calf, label: 'Łydka cm', keyValue: 'measurement_calf'),
      _BodyMeasurementField(controller: shoulders, label: 'Barki cm', keyValue: 'measurement_shoulders'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.straighten_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Dodaj pomiar', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('measurement_date_button'),
              onPressed: pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text('Data: ${trainerHistoryFullDate(selectedDate)}'),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 660
                    ? (constraints.maxWidth - 20) / 3
                    : constraints.maxWidth >= 430
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final field in fields) SizedBox(width: fieldWidth, child: field),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('measurement_note'),
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notatka do pomiaru'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('save_body_measurement'),
              onPressed: save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Zapisz pomiar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyMeasurementField extends StatelessWidget {
  const _BodyMeasurementField({
    required this.controller,
    required this.label,
    required this.keyValue,
  });

  final TextEditingController controller;
  final String label;
  final String keyValue;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: Key(keyValue),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class ProgressPhotoPlaceholderCard extends StatelessWidget {
  const ProgressPhotoPlaceholderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.photo_camera_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zdjęcia progresu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    'Miejsce przygotowane pod przyszłe zdjęcia sylwetki. Na tym etapie zapisujemy strukturę w modelu, ale nie dodajemy wyboru plików ani analizy AI.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BodyMeasurementChartsCard extends StatelessWidget {
  const BodyMeasurementChartsCard({super.key, required this.measurements});

  final List<BodyMeasurement> measurements;

  @override
  Widget build(BuildContext context) {
    final chartMeasurements = measurements.reversed.take(8).toList();
    final labels = chartMeasurements.map((measurement) => shortDate(measurement.date)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SimpleProgressBarChartCard(
          title: 'Waga',
          subtitle: 'Zmiana masy ciała w czasie',
          values: chartMeasurements.map((measurement) => measurement.weightKg).toList(),
          labels: labels,
          suffix: 'kg',
          icon: Icons.monitor_weight_outlined,
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Pas',
          subtitle: 'Zmiana obwodu pasa',
          values: chartMeasurements.map((measurement) => measurement.waistCm).toList(),
          labels: labels,
          suffix: 'cm',
          icon: Icons.straighten_rounded,
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Ramię',
          subtitle: 'Zmiana obwodu ramienia',
          values: chartMeasurements.map((measurement) => measurement.armCm).toList(),
          labels: labels,
          suffix: 'cm',
          icon: Icons.fitness_center_outlined,
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Klatka',
          subtitle: 'Zmiana obwodu klatki piersiowej',
          values: chartMeasurements.map((measurement) => measurement.chestCm).toList(),
          labels: labels,
          suffix: 'cm',
          icon: Icons.accessibility_new_rounded,
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Udo',
          subtitle: 'Zmiana obwodu uda',
          values: chartMeasurements.map((measurement) => measurement.thighCm).toList(),
          labels: labels,
          suffix: 'cm',
          icon: Icons.directions_run_rounded,
        ),
      ],
    );
  }
}

class BodyMeasurementHistoryCard extends StatelessWidget {
  const BodyMeasurementHistoryCard({super.key, required this.measurements});

  final List<BodyMeasurement> measurements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Historia pomiarów', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            if (measurements.isEmpty)
              Text('Nie masz jeszcze zapisanych pomiarów sylwetki.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              ...measurements.map(
                (measurement) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BodyMeasurementHistoryTile(measurement: measurement),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BodyMeasurementHistoryTile extends StatelessWidget {
  const BodyMeasurementHistoryTile({super.key, required this.measurement});

  final BodyMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trainerHistoryFullDate(measurement.date), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: bodyMeasurementTags(measurement).map((tag) => MiniTag(text: tag)).toList(),
          ),
          if (measurement.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(measurement.note, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Text(
            measurement.progressPhotoPaths.isEmpty ? 'Zdjęcia progresu: placeholder' : 'Zdjęcia progresu: ${measurement.progressPhotoPaths.length}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class HealthConnectSettingsPage extends StatelessWidget {
  const HealthConnectSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final snapshot = store.latestHealthConnectSnapshot;
    return PageFrame(
      title: 'Health Connect',
      subtitle: 'Podstawowy odczyt, uprawnienia i diagnostyka bez automatycznego łączenia z kaloriami',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HealthConnectActionsCard(store: store),
          const SizedBox(height: 12),
          HealthConnectStatusCard(snapshot: snapshot, busy: store.healthConnectBusy),
          const SizedBox(height: 12),
          HealthConnectDailyDataCard(snapshot: snapshot),
          const SizedBox(height: 12),
          HealthConnectDiagnosticsCard(snapshot: snapshot),
          const SizedBox(height: 12),
          HealthConnectLocalHistoryCard(snapshots: store.healthConnectSnapshots),
        ],
      ),
    );
  }
}

class HealthConnectActionsCard extends StatelessWidget {
  const HealthConnectActionsCard({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Ustawienia i odczyt', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Na tym etapie Trainer tylko pokazuje dane z Health Connect i zapisuje lokalny snapshot diagnostyczny. Nie dopisuje ich jeszcze do kalorii.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: store.healthConnectBusy
                      ? null
                      : () => _runHealthConnectAction(
                            context,
                            store.checkHealthConnectStatus,
                            'Sprawdzono dostępność Health Connect.',
                          ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Sprawdź dostępność'),
                ),
                OutlinedButton.icon(
                  onPressed: store.healthConnectBusy
                      ? null
                      : () => _runHealthConnectAction(
                            context,
                            store.requestHealthConnectPermissions,
                            'Zaktualizowano uprawnienia Health Connect.',
                          ),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Poproś o uprawnienia'),
                ),
                OutlinedButton.icon(
                  onPressed: store.healthConnectBusy
                      ? null
                      : () => _runHealthConnectAction(
                            context,
                            store.readHealthConnectDailyData,
                            'Odczytano dzienne dane Health Connect.',
                          ),
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Odczytaj dzisiaj'),
                ),
              ],
            ),
            if (store.healthConnectBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runHealthConnectAction(
    BuildContext context,
    Future<TrainerHealthConnectSnapshot> Function() action,
    String successMessage,
  ) async {
    final snapshot = await action();
    if (!context.mounted) return;
    showError(
      context,
      snapshot.errorMessage.trim().isEmpty ? successMessage : snapshot.errorMessage,
    );
  }
}

class HealthConnectStatusCard extends StatelessWidget {
  const HealthConnectStatusCard({super.key, required this.snapshot, required this.busy});

  final TrainerHealthConnectSnapshot? snapshot;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  current?.isAvailable == true ? Icons.check_circle_outline : Icons.info_outline,
                  color: current?.isAvailable == true ? Colors.greenAccent : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Status połączenia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            if (current == null)
              Text(
                busy ? 'Sprawdzam Health Connect…' : 'Brak odczytu. Zacznij od sprawdzenia dostępności.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MiniTag(text: current.isAvailable ? 'Dostępny' : 'Niedostępny'),
                  MiniTag(text: 'SDK: ${current.sdkStatus}'),
                  MiniTag(text: current.permissionsGranted ? 'Uprawnienia OK' : 'Brak części uprawnień'),
                  MiniTag(text: 'Dzień: ${trainerHistoryFullDate(current.date)}'),
                  MiniTag(text: 'Sprawdzono: ${formatHealthConnectTimestamp(current.checkedAt)}'),
                ],
              ),
              if (current.errorMessage.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  current.errorMessage,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class HealthConnectDailyDataCard extends StatelessWidget {
  const HealthConnectDailyDataCard({super.key, required this.snapshot});

  final TrainerHealthConnectSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Dane dzienne', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            if (current == null)
              Text('Po odczycie pojawią się tutaj kroki, dystans, aktywne kcal, treningi, tętno i sen.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              HealthConnectMetricGrid(
                metrics: [
                  HealthConnectMetric('Kroki', '${current.steps}'),
                  HealthConnectMetric('Dystans', formatHealthConnectDistance(current.distanceKm)),
                  HealthConnectMetric('Aktywne kcal', current.activeKcal.toStringAsFixed(0)),
                  HealthConnectMetric('Treningi', '${current.workoutSessions} · ${current.workoutMinutes} min'),
                  HealthConnectMetric('Tętno', current.heartRateSamples == 0 ? '—' : '${current.averageHeartRate.toStringAsFixed(0)} bpm'),
                  HealthConnectMetric('Sen', current.sleepMinutes == 0 ? '—' : formatHealthConnectMinutes(current.sleepMinutes)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class HealthConnectDiagnosticsCard extends StatelessWidget {
  const HealthConnectDiagnosticsCard({super.key, required this.snapshot});

  final TrainerHealthConnectSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Diagnostyka', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            if (current == null)
              Text('Brak lokalnego snapshotu diagnostycznego.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else ...[
              HealthConnectTagGroup(title: 'Dostępne dane', values: current.availableData, emptyText: 'Brak danych z wybranego dnia'),
              const SizedBox(height: 10),
              HealthConnectTagGroup(title: 'Brakujące dane', values: current.missingData, emptyText: 'Nic nie brakuje'),
              const SizedBox(height: 10),
              HealthConnectTagGroup(title: 'Uprawnienia przyznane', values: current.grantedPermissions, emptyText: 'Brak przyznanych uprawnień'),
              const SizedBox(height: 10),
              HealthConnectTagGroup(title: 'Uprawnienia brakujące', values: current.missingPermissions, emptyText: 'Wszystkie wymagane uprawnienia są przyznane'),
            ],
          ],
        ),
      ),
    );
  }
}

class HealthConnectLocalHistoryCard extends StatelessWidget {
  const HealthConnectLocalHistoryCard({super.key, required this.snapshots});

  final List<TrainerHealthConnectSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = snapshots.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.save_alt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Lokalny zapis odczytów', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Text('Nie ma jeszcze zapisanego odczytu Health Connect.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              ...visible.map(
                (snapshot) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${trainerHistoryFullDate(snapshot.date)} · ${formatHealthConnectTimestamp(snapshot.checkedAt)}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            MiniTag(text: '${snapshot.steps} kroków'),
                            MiniTag(text: formatHealthConnectDistance(snapshot.distanceKm)),
                            MiniTag(text: '${snapshot.activeKcal.toStringAsFixed(0)} kcal'),
                            MiniTag(text: '${snapshot.workoutSessions} treningów'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HealthConnectMetricGrid extends StatelessWidget {
  const HealthConnectMetricGrid({super.key, required this.metrics});

  final List<HealthConnectMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 620;
        final width = wide ? (constraints.maxWidth - 16) / 3 : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width.clamp(130, constraints.maxWidth),
                  child: SmallMetric(label: metric.label, value: metric.value),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class HealthConnectTagGroup extends StatelessWidget {
  const HealthConnectTagGroup({
    super.key,
    required this.title,
    required this.values,
    required this.emptyText,
  });

  final String title;
  final List<String> values;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: values.isEmpty ? [MiniTag(text: emptyText)] : values.map((value) => MiniTag(text: value)).toList(),
        ),
      ],
    );
  }
}

class HealthConnectMetric {
  const HealthConnectMetric(this.label, this.value);

  final String label;
  final String value;
}

String formatHealthConnectDistance(double distanceKm) {
  if (distanceKm <= 0) return '0 km';
  if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
  return '${distanceKm.toStringAsFixed(2)} km';
}

String formatHealthConnectMinutes(int minutes) {
  if (minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours <= 0) return '$minutes min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

String formatHealthConnectTimestamp(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${trainerHistoryFullDate(local)} $hour:$minute';
}

double parseBodyMeasurementValue(String value) {
  return math.max(0, double.tryParse(value.replaceAll(',', '.')) ?? 0).toDouble();
}

String formatBodyMeasurementValue(double value, String suffix) {
  if (value <= 0) return '—';
  if (value == value.roundToDouble()) return '${value.round()} $suffix';
  return '${value.toStringAsFixed(1)} $suffix';
}

List<String> bodyMeasurementTags(BodyMeasurement measurement) {
  final tags = <String>[
    if (measurement.weightKg > 0) 'Waga ${formatBodyMeasurementValue(measurement.weightKg, 'kg')}',
    if (measurement.waistCm > 0) 'Pas ${formatBodyMeasurementValue(measurement.waistCm, 'cm')}',
    if (measurement.chestCm > 0) 'Klatka ${formatBodyMeasurementValue(measurement.chestCm, 'cm')}',
    if (measurement.armCm > 0) 'Ramię ${formatBodyMeasurementValue(measurement.armCm, 'cm')}',
    if (measurement.thighCm > 0) 'Udo ${formatBodyMeasurementValue(measurement.thighCm, 'cm')}',
    if (measurement.hipsCm > 0) 'Biodra ${formatBodyMeasurementValue(measurement.hipsCm, 'cm')}',
    if (measurement.calfCm > 0) 'Łydka ${formatBodyMeasurementValue(measurement.calfCm, 'cm')}',
    if (measurement.shouldersCm > 0) 'Barki ${formatBodyMeasurementValue(measurement.shouldersCm, 'cm')}',
  ];
  return tags.isEmpty ? ['Brak obwodów'] : tags;
}

class ActivityDeduplicationPage extends StatelessWidget {
  const ActivityDeduplicationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final decisions = store.activityCreditDecisionsForDay(store.selectedDate);
    return PageFrame(
      title: 'Anty-dublowanie aktywności',
      subtitle: 'Źródła aktywności, kcal i decyzje o pominięciu duplikatów',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActivityDeduplicationOverviewCard(decisions: decisions),
          const SizedBox(height: 12),
          ActivityCreditTiles(decisions: decisions),
          const SizedBox(height: 12),
          ActivityDiagnosticsCard(decisions: decisions),
        ],
      ),
    );
  }
}

class ActivityDeduplicationOverviewCard extends StatelessWidget {
  const ActivityDeduplicationOverviewCard({super.key, required this.decisions});

  final List<ActivityCreditDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creditedKcal = totalCreditedActivityKcal(decisions);
    final duplicates = decisions.where((decision) => decision.skippedAsDuplicate).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Reguły zaliczania kcal', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MiniTag(text: 'Zaliczone: $creditedKcal kcal'),
                MiniTag(text: 'Duplikaty: $duplicates'),
                const MiniTag(text: 'Kroki osobno'),
                const MiniTag(text: 'Bieg ≠ chód'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Trainer przyjmuje dane z: manual, Trainer, Health Connect, zegarek, kroki, bieg i chód mierzony. Na tym etapie to lokalna logika wejściowa — bez pełnej synchronizacji Health Connect.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityCreditTiles extends StatelessWidget {
  const ActivityCreditTiles({super.key, required this.decisions});

  final List<ActivityCreditDecision> decisions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 620;
        final width = wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: ActivityTypeCreditTile(
                title: 'Kroki',
                subtitle: 'Chód zwykły z kroków liczy się osobno',
                type: TrainerActivityType.ordinaryStepsWalk,
                icon: Icons.directions_walk_rounded,
                decisions: decisions,
              ),
            ),
            SizedBox(
              width: width,
              child: ActivityTypeCreditTile(
                title: 'Chód mierzony',
                subtitle: 'Nie może być jednocześnie biegiem',
                type: TrainerActivityType.measuredWalk,
                icon: Icons.hiking_rounded,
                decisions: decisions,
              ),
            ),
            SizedBox(
              width: width,
              child: ActivityTypeCreditTile(
                title: 'Bieg mierzony',
                subtitle: 'Nie może być liczony jako chód',
                type: TrainerActivityType.run,
                icon: Icons.directions_run_rounded,
                decisions: decisions,
              ),
            ),
            SizedBox(
              width: width,
              child: ActivityTypeCreditTile(
                title: 'Trening siłowy',
                subtitle: 'Sesje z Trainera po zakończeniu treningu',
                type: TrainerActivityType.strengthTraining,
                icon: Icons.fitness_center_rounded,
                decisions: decisions,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ActivityTypeCreditTile extends StatelessWidget {
  const ActivityTypeCreditTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
    required this.decisions,
  });

  final String title;
  final String subtitle;
  final TrainerActivityType type;
  final IconData icon;
  final List<ActivityCreditDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = decisions.where((decision) => decision.entry.type == type).toList();
    final creditedKcal = visible.fold<int>(0, (sum, decision) => sum + decision.creditedKcal);
    final duplicates = visible.where((decision) => decision.skippedAsDuplicate).length;
    final sources = visible.map((decision) => decision.entry.source.label).toSet().toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MiniTag(text: 'Kcal: $creditedKcal'),
                MiniTag(text: 'Duplikaty: $duplicates'),
                if (sources.isEmpty) const MiniTag(text: 'Brak źródła') else ...sources.map((source) => MiniTag(text: source)),
              ],
            ),
            const SizedBox(height: 10),
            if (visible.isEmpty) Text('Brak danych wejściowych dla tego typu.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)) else ...visible.map((decision) => ActivityDecisionCompactRow(decision: decision)),
          ],
        ),
      ),
    );
  }
}

class ActivityDiagnosticsCard extends StatelessWidget {
  const ActivityDiagnosticsCard({super.key, required this.decisions});

  final List<ActivityCreditDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.manage_search_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Diagnostyka aktywności', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 10),
            if (decisions.isEmpty)
              Text(
                'Brak aktywności dla wybranego dnia. Trening siłowy pojawi się po zakończeniu sesji w Trainerze, a kroki/bieg/chód można podać przez lokalne wejście activity_entries_v1.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              ...decisions.map((decision) => ActivityDecisionDetailRow(decision: decision)),
          ],
        ),
      ),
    );
  }
}

class ActivityDecisionCompactRow extends StatelessWidget {
  const ActivityDecisionCompactRow({super.key, required this.decision});

  final ActivityCreditDecision decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(decision.includedInCalories ? Icons.check_circle_rounded : Icons.block_rounded, size: 18, color: decision.includedInCalories ? Colors.green : theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${decision.entry.source.label}: ${decision.includedInCalories ? 'Zaliczono do kcal' : 'Pominięto jako duplikat'}',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityDecisionDetailRow extends StatelessWidget {
  const ActivityDecisionDetailRow({super.key, required this.decision});

  final ActivityCreditDecision decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(decision.includedInCalories ? Icons.check_circle_rounded : Icons.block_rounded, color: decision.includedInCalories ? Colors.green : theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(decision.entry.type.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MiniTag(text: 'Źródło: ${decision.entry.source.label}'),
              MiniTag(text: decision.includedInCalories ? 'Zaliczono do kcal' : 'Pominięto jako duplikat'),
              MiniTag(text: '${decision.creditedKcal} kcal'),
              if (decision.entry.steps > 0) MiniTag(text: '${decision.entry.steps} kroków'),
              if (decision.entry.durationMin > 0) MiniTag(text: '${decision.entry.durationMin} min'),
            ],
          ),
          const SizedBox(height: 8),
          Text(decision.reason, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (decision.duplicateOfKey.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Duplikat względem: ${decision.duplicateOfKey}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Etap 20: Backup, eksport i diagnostyka
// ============================================================

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final snapshot = store.latestHealthConnectSnapshot;
    final suspicious = store.suspiciousActivityEntries();
    final lastActivity = store.lastDataActivityAt;
    final aiAnalysesCount = store.logs.where((l) => store.workoutAiAnalysisFor(l.sessionId) != null).map((l) => l.sessionId).toSet().length;

    String fmt(DateTime? dt) {
      if (dt == null) return '—';
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostyka danych')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // Liczniki danych
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage_rounded, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Stan danych lokalnych', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DiagRow(label: 'Ćwiczenia (własne)', value: '${store.customExercises.length}'),
                    _DiagRow(label: 'Ćwiczenia (łącznie z bazą)', value: '${ExerciseRepo.combined(store.customExercises).length}'),
                    _DiagRow(label: 'Plany treningowe', value: '${store.plans.length}'),
                    _DiagRow(label: 'Wpisy treningowe', value: '${store.logs.length}'),
                    _DiagRow(label: 'Pomiary sylwetki', value: '${store.bodyMeasurements.length}'),
                    _DiagRow(label: 'Zarejestrowane aktywności', value: '${store.activityEntries.length}'),
                    _DiagRow(label: 'Wpływy na kalorie', value: '${store.trainingImpacts.length}'),
                    _DiagRow(label: 'Ostatnia aktywność danych', value: fmt(lastActivity)),
                    _DiagRow(label: 'Ostatnia kopia lokalna', value: fmt(store.lastBackupAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Status Health Connect
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.health_and_safety_outlined, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Health Connect', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (snapshot == null)
                      Text('Brak odczytu. Otwórz ekran Health Connect i sprawdź status.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                    else ...[
                      _DiagRow(label: 'Dostępność SDK', value: snapshot.isAvailable ? 'Dostępne' : 'Niedostępne'),
                      _DiagRow(label: 'Uprawnienia', value: snapshot.permissionsGranted ? 'Przyznane' : 'Brak / częściowe'),
                      _DiagRow(label: 'Ostatni odczyt', value: fmt(snapshot.checkedAt)),
                      _DiagRow(label: 'Dane dnia', value: snapshot.hasAnyDailyData ? 'Obecne' : 'Brak'),
                      if (snapshot.missingData.isNotEmpty)
                        _DiagRow(label: 'Brakujące dane', value: snapshot.missingData.length.toString()),
                      if (snapshot.errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Błąd: ${snapshot.errorMessage}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Status AI
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.smart_toy_outlined, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('AI Trainer', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DiagRow(label: 'Backend URL', value: store.settings.backendUrl),
                    _DiagRow(label: 'Status AI', value: store.aiBusy ? 'Zajęte' : 'Bezczynne'),
                    _DiagRow(label: 'Wiadomości w czacie', value: '${store.aiChatHistory.length}'),
                    _DiagRow(label: 'Analizy treningów AI', value: '$aiAnalysesCount'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Potencjalne błędne wpisy
            Card(
              color: suspicious.isEmpty ? null : scheme.errorContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(suspicious.isEmpty ? Icons.verified_rounded : Icons.warning_amber_rounded, color: suspicious.isEmpty ? Colors.green : Colors.deepOrange),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Potencjalne błędne wpisy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (suspicious.isEmpty)
                      Text('Nie wykryto podejrzanych aktywności.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                    else ...[
                      Text('${suspicious.length} ${suspicious.length == 1 ? 'wpis wymaga' : 'wpisów wymaga'} weryfikacji:', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      for (final entry in suspicious) _SuspiciousEntryTile(entry: entry),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuspiciousEntryTile extends StatelessWidget {
  const _SuspiciousEntryTile({required this.entry});
  final TrainerActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final dateLabel = '${entry.date.year}-${two(entry.date.month)}-${two(entry.date.day)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.source.label} · ${entry.type.label}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${entry.estimatedKcal} kcal${entry.steps > 0 ? ' · ${entry.steps} kroków' : ''}${entry.distanceKm > 0 ? ' · ${entry.distanceKm.toStringAsFixed(1)} km' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Usuń wpis',
            icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Usunąć błędny wpis?'),
                  content: Text('Wpis „${entry.source.label} · ${entry.type.label}" z dnia $dateLabel zostanie trwale usunięty z lokalnych danych.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                final removed = await store.removeActivityEntry(entry.id);
                if (context.mounted && removed) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usunięto błędny wpis.')));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class BackupRestoreCard extends StatelessWidget {
  const BackupRestoreCard({super.key, required this.store});
  final AppStore store;

  Future<void> _showImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import danych JSON'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wklej wcześniej wyeksportowane dane JSON. Obecne dane zostaną zastąpione.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(hintText: '{ "settings": ... }'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Importuj')),
        ],
      ),
    );
    if (json == null || json.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zastąpić obecne dane?'),
        content: const Text('Import nadpisze treningi, plany, ćwiczenia i ustawienia. Warto najpierw zrobić kopię lokalną.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zastąp')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final decoded = jsonDecode(json);
      Map<String, dynamic>? data;
      if (decoded is Map && decoded['data'] is Map) {
        data = Map<String, dynamic>.from(decoded['data'] as Map);
      } else if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
      if (data == null) {
        if (context.mounted) showError(context, 'Nieprawidłowy format danych.');
        return;
      }
      final ok = await store.importFullData(data);
      if (context.mounted) {
        showError(context, ok ? 'Import zakończony sukcesem.' : 'Nie udało się zaimportować danych.');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Błąd importu: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String fmt(DateTime? dt) {
      if (dt == null) return 'brak';
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Backup i bezpieczeństwo danych', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 4),
            Text('Ostatnia kopia: ${fmt(store.lastBackupAt)}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 520;
                final width = wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.save_outlined,
                        title: 'Kopia lokalna',
                        subtitle: 'Zapisz migawkę danych na urządzeniu',
                        onTap: () async {
                          final at = await store.createLocalBackup();
                          if (context.mounted) showError(context, 'Zapisano kopię (${fmt(at)}).');
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.restore_rounded,
                        title: 'Przywróć kopię',
                        subtitle: 'Odtwórz dane z lokalnej migawki',
                        onTap: () async {
                          final has = await store.hasLocalBackup();
                          if (!context.mounted) return;
                          if (!has) {
                            showError(context, 'Brak zapisanej kopii lokalnej.');
                            return;
                          }
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Przywrócić kopię?'),
                              content: const Text('Obecne dane zostaną zastąpione danymi z ostatniej kopii lokalnej.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Przywróć')),
                              ],
                            ),
                          );
                          if (ok != true || !context.mounted) return;
                          final restored = await store.restoreLocalBackup();
                          if (context.mounted) showError(context, restored ? 'Przywrócono dane z kopii.' : 'Nie udało się przywrócić kopii.');
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.history_edu_outlined,
                        title: 'Eksport historii CSV',
                        subtitle: 'Wszystkie treningi do arkusza',
                        onTap: () => showExportDialog(context, buildCsvExport(store)),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.insights_outlined,
                        title: 'Eksport progresu CSV',
                        subtitle: 'Rekordy i objętość per ćwiczenie',
                        onTap: () => showExportDialog(context, buildProgressCsvExport(store)),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.upload_file_outlined,
                        title: 'Import danych',
                        subtitle: 'Wczytaj dane z eksportu JSON',
                        onTap: () => _showImportDialog(context),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: FeatureActionTile(
                        icon: Icons.monitor_heart_outlined,
                        title: 'Diagnostyka',
                        subtitle: 'Stan danych, HC, AI i błędne wpisy',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Etap 21: karta z listą pozycji nawigacyjnych jednej sekcji menu „Więcej".
class _MoreNavCard extends StatelessWidget {
  const _MoreNavCard({required this.tiles});

  final List<FeatureActionTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i != tiles.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// Etap 25: karta „Wygląd aplikacji" — tryb nocny i kolor akcentu.
/// Zmiany zapisują się od razu (store.updateSettings) i działają na żywo.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Tryb nocny'),
              subtitle: const Text('Ciemny, premium styl podobny do aplikacji licznika'),
              value: store.settings.darkMode,
              onChanged: (v) => store.updateSettings(store.settings.copyWith(darkMode: v)),
            ),
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Kolor akcentu', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kAccentPalette.entries.map((entry) {
                  final selected = store.settings.accentColorValue == entry.value;
                  final color = Color(entry.value);
                  return ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: color, radius: 9),
                    label: Text(entry.key),
                    selected: selected,
                    onSelected: (_) => store.updateSettings(store.settings.copyWith(accentColorValue: entry.value)),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return PageFrame(
      title: 'Więcej',
      subtitle: 'Integracje, zdrowie, cele, wygląd i dane aplikacji',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trener AI — wyróżniony skrót (nie ukrywamy ważnej funkcji).
          _MoreNavCard(
            tiles: [
              FeatureActionTile(
                icon: Icons.smart_toy_rounded,
                title: 'AI Trainer',
                subtitle: 'Czat z trenerem AI i szybkie pytania',
                onTap: () => openTrainerSubPage(context, const AiTrainerPage(), title: 'AI Trainer'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // === 1. Integracje ===
          const SectionHeader(title: 'Integracje'),
          const SizedBox(height: 10),
          _MoreNavCard(
            tiles: [
              FeatureActionTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Health Connect / Samsung Health',
                subtitle: 'Połączenie, uprawnienia i dzienny odczyt',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthConnectSettingsPage())),
              ),
              FeatureActionTile(
                icon: Icons.public,
                title: 'Import z bazy ćwiczeń',
                subtitle: 'Szukaj w wger i zapisuj lokalnie',
                onTap: () => showWgerSearchSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // === 2. Zdrowie i aktywność ===
          const SectionHeader(title: 'Zdrowie i aktywność'),
          const SizedBox(height: 10),
          _MoreNavCard(
            tiles: [
              FeatureActionTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Dane Health Connect',
                subtitle: 'Kroki, dystans, aktywne kcal, sen i tętno',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthConnectSettingsPage())),
              ),
              FeatureActionTile(
                icon: Icons.straighten_rounded,
                title: 'Pomiary sylwetki',
                subtitle: 'Waga, obwody, historia i wykresy',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyMeasurementsPage())),
              ),
              FeatureActionTile(
                icon: Icons.rule_rounded,
                title: 'Anty-dublowanie aktywności',
                subtitle: 'Kroki, chód, bieg i trening siłowy osobno',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityDeduplicationPage())),
              ),
              FeatureActionTile(
                icon: Icons.history_rounded,
                title: 'Historia treningów',
                subtitle: 'Wszystkie zapisane treningi',
                onTap: () => openTrainerSubPage(context, const HistoryPage(), title: 'Historia treningów'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // === 3. Cele treningowe ===
          const SectionHeader(title: 'Cele treningowe'),
          const SizedBox(height: 10),
          SettingsCard(settings: store.settings, onSave: store.updateSettings),
          const SizedBox(height: 16),

          // === 4. Wygląd aplikacji ===
          const SectionHeader(title: 'Wygląd aplikacji'),
          const SizedBox(height: 10),
          AppearanceCard(store: store),
          const SizedBox(height: 16),

          // === 5. Dane i diagnostyka ===
          const SectionHeader(title: 'Dane i diagnostyka'),
          const SizedBox(height: 10),
          _MoreNavCard(
            tiles: [
              FeatureActionTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Diagnostyka',
                subtitle: 'Status zgód, dane dostępne/brakujące i błędy integracji',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BackupRestoreCard(store: store),
          const SizedBox(height: 12),
          ExportCard(),
          const SizedBox(height: 16),

          // === 6. Informacje o aplikacji ===
          const SectionHeader(title: 'Informacje o aplikacji'),
          const SizedBox(height: 10),
          AboutCard(),
          const SizedBox(height: 16),

          // Pełna lista funkcji i analiz (nie ukrywamy żadnej funkcji).
          const SectionHeader(title: 'Wszystkie funkcje i analizy'),
          const SizedBox(height: 10),
          TrainerFeaturesHub(store: store),
        ],
      ),
    );
  }
}

class SettingsCard extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings next) onSave;

  const SettingsCard({super.key, required this.settings, required this.onSave});

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  late final TextEditingController weight;
  late final TextEditingController height;
  late final TextEditingController age;
  late final TextEditingController goal;
  late final TextEditingController equipment;
  late final TextEditingController limitations;
  late String level;
  late String trainingMode;
  late int accentColorValue;

  @override
  void initState() {
    super.initState();
    weight = TextEditingController();
    height = TextEditingController();
    age = TextEditingController();
    goal = TextEditingController();
    equipment = TextEditingController();
    limitations = TextEditingController();
    _fillFrom(widget.settings);
  }

  @override
  void didUpdateWidget(covariant SettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) _fillFrom(widget.settings);
  }

  void _fillFrom(AppSettings s) {
    weight.text = s.bodyWeightKg.toStringAsFixed(0);
    height.text = s.heightCm.toStringAsFixed(0);
    age.text = '${s.age}';
    goal.text = s.goal;
    equipment.text = s.equipment;
    limitations.text = s.limitations;
    level = normalizeLevel(s.level);
    trainingMode = normalizeTrainingMode(s.trainingMode);
    accentColorValue = s.accentColorValue;
  }

  @override
  void dispose() {
    weight.dispose();
    height.dispose();
    age.dispose();
    goal.dispose();
    equipment.dispose();
    limitations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profil treningowy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Waga kg'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wzrost cm'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wiek')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: level,
              decoration: const InputDecoration(labelText: 'Poziom'),
              selectedItemBuilder: (context) => kTrainingLevels.map((v) => Align(alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              items: kTrainingLevels.map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => level = v ?? level),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: trainingMode,
              decoration: const InputDecoration(labelText: 'Tryb treningu'),
              selectedItemBuilder: (context) => kTrainingModes.map((v) => Align(alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              items: kTrainingModes.map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => trainingMode = v ?? trainingMode),
            ),
            const SizedBox(height: 10),
            TextField(controller: goal, maxLines: 2, decoration: const InputDecoration(labelText: 'Cel treningowy')),
            const SizedBox(height: 10),
            TextField(controller: equipment, maxLines: 2, decoration: const InputDecoration(labelText: 'Dostępny sprzęt')),
            const SizedBox(height: 10),
            TextField(controller: limitations, maxLines: 2, decoration: const InputDecoration(labelText: 'Kontuzje / ograniczenia / ból')),
            const SizedBox(height: 12),
            Text('Kolor akcentu', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAccentPalette.entries.map((entry) {
                final selected = accentColorValue == entry.value;
                return ChoiceChip(
                  selected: selected,
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 7, backgroundColor: Color(entry.value)),
                    const SizedBox(width: 6),
                    Text(entry.key),
                  ]),
                  onSelected: (_) => setState(() => accentColorValue = entry.value),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primaryContainer.withOpacity(0.55),
              child: const ListTile(
                leading: Icon(Icons.cloud_done_outlined),
                title: Text('Backend AI połączony na stałe'),
                subtitle: Text(kDefaultBackendUrl),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final next = widget.settings.copyWith(
                  backendUrl: kDefaultBackendUrl,
                  bodyWeightKg: double.tryParse(weight.text.replaceAll(',', '.')) ?? widget.settings.bodyWeightKg,
                  heightCm: double.tryParse(height.text.replaceAll(',', '.')) ?? widget.settings.heightCm,
                  age: int.tryParse(age.text) ?? widget.settings.age,
                  goal: goal.text.trim().isEmpty ? widget.settings.goal : goal.text.trim(),
                  equipment: equipment.text.trim().isEmpty ? widget.settings.equipment : equipment.text.trim(),
                  limitations: limitations.text.trim(),
                  level: level,
                  trainingMode: trainingMode,
                  accentColorValue: accentColorValue,
                );
                await widget.onSave(next);
                if (!context.mounted) return;
                showError(context, 'Zapisano profil Trainer');
              },
              icon: const Icon(Icons.save),
              label: const Text('Zapisz profil'),
            ),
          ],
        ),
      ),
    );
  }
}

class ExportCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final data = jsonEncode(buildFullExport(store));
    return Card(
      child: ExpansionTile(
        title: Text('Eksport danych JSON', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        subtitle: const Text('Do późniejszego importu albo debugowania'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(data, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status modułów Trainer', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('• Zdjęcia/wideo własnej techniki i analiza klatek.\n• Integracja z aplikacją kalorii: większe kcal w dni treningowe.\n• Baza własnych ćwiczeń z importem przez API wger i AI.\n• Timer interwałów i odpoczynku między seriami.\n• Plany PPL, FBW, góra/dół, brzuch z obciążeniem.'),
          ],
        ),
      ),
    );
  }
}

class TrainerFeaturesHub extends StatelessWidget {
  final AppStore store;

  const TrainerFeaturesHub({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month, 1);
    final monthLogs = store.logsBetween(startMonth, now);
    final weekLogs = store.logsBetween(now.subtract(const Duration(days: 6)), now);
    final monthTotals = DayTotals.from(monthLogs);
    final streak = workoutStreak(store.logs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.rocket_launch_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Centrum funkcji Trainer', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                          Text('Działające moduły zamiast listy pomysłów', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MiniTag(text: 'Streak: $streak dni'),
                    MiniTag(text: 'Miesiąc: ${monthTotals.sessions} wpisów'),
                    MiniTag(text: '${monthTotals.calories.round()} kcal'),
                    MiniTag(text: '${(monthTotals.durationSec / 60).round()} min'),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 520;
                    final width = wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.add_circle_outline, title: 'Dodaj trening', subtitle: 'Szybki wpis do dziennika', onTap: () => showAddWorkoutSheet(context))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.straighten_rounded, title: 'Pomiary sylwetki', subtitle: 'Waga, obwody, historia i wykresy', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyMeasurementsPage())))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.rule_rounded, title: 'Anty-dublowanie aktywności', subtitle: 'Kroki, chód, bieg i trening siłowy', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityDeduplicationPage())))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.health_and_safety_outlined, title: 'Health Connect', subtitle: 'Dostępność, uprawnienia i dzienny odczyt', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthConnectSettingsPage())))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.public, title: 'Import z bazy ćwiczeń', subtitle: 'Szukaj w wger i zapisuj lokalnie', onTap: () => showWgerSearchSheet(context))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.auto_awesome, title: 'Plan AI', subtitle: 'Poziom + sprzęt + ograniczenia', onTap: () => showPlanGenerator(context))),
                        SizedBox(
                            width: width,
                            child: FeatureActionTile(
                                icon: Icons.refresh,
                                title: 'Plan lokalny',
                                subtitle: 'Fallback bez internetu i AI',
                                onTap: () async {
                                  await store.generateLocalPlan();
                                  if (context.mounted) showError(context, 'Wygenerowano plan lokalny.');
                                })),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.download_outlined, title: 'Eksport CSV', subtitle: 'Dane treningowe do arkusza', onTap: () => showExportDialog(context, buildCsvExport(store)))),
                        SizedBox(width: width, child: FeatureActionTile(icon: Icons.code, title: 'Eksport JSON', subtitle: 'Pełna kopia danych', onTap: () => showExportDialog(context, prettyJson(buildFullExport(store))))),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        PersonalRecordsCard(logs: store.logs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        WeeklyBalanceCard(logs: weekLogs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        MonthlySummaryCard(logs: monthLogs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        RecoveryCoachCard(logs: weekLogs),
        const SizedBox(height: 12),
        StagnationDetectorCard(logs: store.logs),
        const SizedBox(height: 12),
        TrainingChecklistCard(),
        const SizedBox(height: 12),
        EquipmentAndLimitsCard(settings: store.settings),
        const SizedBox(height: 12),
        CalorieBridgeCard(store: store),
        const SizedBox(height: 12),
        SharedProfileBridgeCard(store: store),
        const SizedBox(height: 12),
        DailyPriorityCard(store: store),
        const SizedBox(height: 12),
        TrainingModeCard(settings: store.settings),
        const SizedBox(height: 12),
        FeelingJournalCard(),
        const SizedBox(height: 12),
        RestTimerCard(settings: store.settings),
        const SizedBox(height: 12),
        PlanTemplatesCard(settings: store.settings),
        const SizedBox(height: 12),
        TargetedPlanGeneratorsCard(settings: store.settings),
        const SizedBox(height: 12),
        MobilityAndStretchingCard(settings: store.settings),
        const SizedBox(height: 12),
        VolumeWarningsCard(logs: weekLogs),
        const SizedBox(height: 12),
        MuscleMapCard(logs: weekLogs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        SetsByMuscleChartCard(logs: weekLogs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        RpeChartCard(logs: weekLogs),
        const SizedBox(height: 12),
        StreakChartCard(logs: store.logs),
        const SizedBox(height: 12),
        ProgressByExerciseCard(logs: store.logs, customExercises: store.customExercises),
        const SizedBox(height: 12),
        PostWorkoutRecommendationCard(logs: weekLogs),
        const SizedBox(height: 12),
        OfflineModeCard(),
        const SizedBox(height: 12),
        ImplementedFeaturesCard(),
      ],
    );
  }
}

class FeatureActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const FeatureActionTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PersonalRecordsCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;

  const PersonalRecordsCard({super.key, required this.logs, required this.customExercises});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bestWeight = <String, WorkoutLog>{};
    final bestVolume = <String, WorkoutLog>{};
    for (final log in logs) {
      final w = bestWeight[log.exerciseId];
      if (w == null || log.weightKg > w.weightKg) bestWeight[log.exerciseId] = log;
      final v = bestVolume[log.exerciseId];
      if (v == null || log.volume > v.volume) bestVolume[log.exerciseId] = log;
    }
    final weightList = bestWeight.values.toList()..sort((a, b) => b.weightKg.compareTo(a.weightKg));
    final volumeList = bestVolume.values.toList()..sort((a, b) => b.volume.compareTo(a.volume));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.emoji_events_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Rekordy osobiste', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 10),
            if (logs.isEmpty)
              Text('Dodaj kilka treningów, a Trainer pokaże rekordy ciężaru i objętości.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else ...[
              Text('Największy ciężar', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              ...weightList.take(3).map((log) => RecordRow(log: log, customExercises: customExercises, value: '${log.weightKg.toStringAsFixed(1)} kg')),
              const SizedBox(height: 8),
              Text('Największa objętość', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              ...volumeList.take(3).map((log) => RecordRow(log: log, customExercises: customExercises, value: '${log.volume.round()} kg')),
            ],
          ],
        ),
      ),
    );
  }
}

class RecordRow extends StatelessWidget {
  final WorkoutLog log;
  final List<Exercise> customExercises;
  final String value;

  const RecordRow({super.key, required this.log, required this.customExercises, required this.value});

  @override
  Widget build(BuildContext context) {
    final e = log.exerciseFrom(customExercises);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class WeeklyBalanceCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;

  const WeeklyBalanceCard({super.key, required this.logs, required this.customExercises});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = muscleCounts(logs, customExercises);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final warning = entries.isEmpty ? 'Brak danych z tygodnia.' : balanceWarning(entries);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.balance_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Tygodniowy balans partii', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 10),
            Text(warning, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            ...entries.take(8).map((e) => ProgressTextBar(label: e.key, value: e.value.toDouble(), max: math.max(1, entries.first.value).toDouble(), suffix: '${e.value}×')),
          ],
        ),
      ),
    );
  }
}

class MonthlySummaryCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;

  const MonthlySummaryCard({super.key, required this.logs, required this.customExercises});

  @override
  Widget build(BuildContext context) {
    final totals = DayTotals.from(logs);
    final theme = Theme.of(context);
    final days = logs.map((e) => DateTime(e.date.year, e.date.month, e.date.day).toIso8601String()).toSet().length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.calendar_view_month_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Podsumowanie miesiąca', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SmallMetric(label: 'Dni', value: '$days')),
              const SizedBox(width: 8),
              Expanded(child: SmallMetric(label: 'Wpisy', value: '${totals.sessions}')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SmallMetric(label: 'Czas', value: '${(totals.durationSec / 60).round()} min')),
              const SizedBox(width: 8),
              Expanded(child: SmallMetric(label: 'Objętość', value: '${totals.volume.round()} kg')),
            ]),
          ],
        ),
      ),
    );
  }
}

class RecoveryCoachCard extends StatelessWidget {
  final List<WorkoutLog> logs;

  const RecoveryCoachCard({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avgRpe = logs.isEmpty ? 0.0 : logs.fold<double>(0, (a, e) => a + e.rpe) / logs.length;
    final minutes = logs.fold<int>(0, (a, e) => a + e.durationSec) ~/ 60;
    final advice = avgRpe >= 8.2 || minutes > 420
        ? 'W tym tygodniu intensywność jest wysoka. Rozważ lżejszą sesję, sen i mobilizację.'
        : avgRpe >= 6.5
            ? 'Obciążenie wygląda sensownie. Pilnuj progresji, ale nie dokładaj wszystkiego naraz.'
            : 'Tydzień wygląda lekko. To dobry moment na technikę, ruchomość albo spokojny progres.';
    return Card(
      child: ListTile(
        leading: Icon(Icons.self_improvement_outlined, color: theme.colorScheme.primary),
        title: const Text('Ocena regeneracji'),
        subtitle: Text('$advice\nŚrednie RPE: ${avgRpe.toStringAsFixed(1)} · czas tygodnia: $minutes min'),
        isThreeLine: true,
      ),
    );
  }
}

class StagnationDetectorCard extends StatelessWidget {
  final List<WorkoutLog> logs;

  const StagnationDetectorCard({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = DayTotals.from(logs.where((e) => !e.date.isBefore(now.subtract(const Duration(days: 6)))).toList());
    final prev = DayTotals.from(logs.where((e) => e.date.isBefore(now.subtract(const Duration(days: 6))) && !e.date.isBefore(now.subtract(const Duration(days: 13)))).toList());
    final theme = Theme.of(context);
    final text = prev.volume <= 0
        ? 'Potrzeba jeszcze danych z minimum dwóch tygodni, żeby ocenić stagnację.'
        : last.volume < prev.volume * 0.8
            ? 'Objętość spadła mocno względem poprzedniego tygodnia. Sprawdź sen, stres i plan.'
            : last.volume > prev.volume * 1.25
                ? 'Objętość mocno wzrosła. Uważaj na regenerację i technikę.'
                : 'Objętość tygodniowa jest stabilna. Możesz progresować małymi krokami.';
    return Card(
      child: ListTile(
        leading: Icon(Icons.trending_up_outlined, color: theme.colorScheme.primary),
        title: const Text('Wykrywanie stagnacji'),
        subtitle: Text(text),
      ),
    );
  }
}

class TrainingChecklistCard extends StatefulWidget {
  @override
  State<TrainingChecklistCard> createState() => _TrainingChecklistCardState();
}

class _TrainingChecklistCardState extends State<TrainingChecklistCard> {
  final before = <String, bool>{
    'Rozgrzewka 5–10 min': false,
    'Sprawdzenie bólu / ograniczeń': false,
    'Plan serii i ciężaru': false,
    'Woda pod ręką': false,
  };
  final after = <String, bool>{
    'Schłodzenie / spokojny oddech': false,
    'Notatka techniczna': false,
    'Ocena RPE': false,
    'Rozciąganie lub mobilizacja': false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget group(String title, Map<String, bool> data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
            ...data.keys.map((k) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: data[k],
                  title: Text(k),
                  onChanged: (v) => setState(() => data[k] = v ?? false),
                )),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.checklist_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Checklist treningowy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 10),
          group('Przed treningiem', before),
          const Divider(),
          group('Po treningu', after),
        ]),
      ),
    );
  }
}

class EquipmentAndLimitsCard extends StatelessWidget {
  final AppSettings settings;

  const EquipmentAndLimitsCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.build_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Sprzęt i ograniczenia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 10),
          Text('Sprzęt: ${settings.equipment.isEmpty ? 'brak danych' : settings.equipment}'),
          const SizedBox(height: 6),
          Text('Ograniczenia: ${settings.limitations.isEmpty ? 'brak zapisanych ograniczeń' : settings.limitations}'),
        ]),
      ),
    );
  }
}

class ImplementedFeaturesCard extends StatelessWidget {
  static const features = [
    'Automatyczne podbijanie kalorii w dni ciężkich treningów — karta pomostu kalorii',
    'Połączenie z Licznikiem Kalorii przez wspólny profil JSON',
    'Historia rekordów osobistych dla każdego ćwiczenia',
    'Wykres progresu ciężaru, powtórzeń i objętości',
    'Timer przerw zależny od celu treningu',
    'Gotowe plany FBW, PPL, góra/dół i brzuch z obciążeniem',
    'Tryb redukcja, rekompozycja, masa, kondycja',
    'Dziennik samopoczucia przed treningiem',
    'Ocena regeneracji po treningu',
    'Automatyczne deloady po spadku formy',
    'Notatki techniczne do każdego ćwiczenia',
    'Lista błędów technicznych do odhaczenia',
    'Biblioteka zamienników ćwiczeń',
    'Filtr ćwiczeń po sprzęcie',
    'Filtr ćwiczeń po bólu i ograniczeniach',
    'Kategorie początkujący, średniozaawansowany, zaawansowany',
    'Własne ćwiczenia użytkownika',
    'Import ćwiczeń z API i zapis lokalny',
    'Analiza treningu przez AI w czytelnych kartach',
    'Generator planu z wybranym sprzętem',
    'Generator planu pod konkretną partię',
    'Generator planu pod brzuch i core',
    'Generator rozgrzewki',
    'Generator schłodzenia',
    'Sugestie mobilizacji',
    'Sugestie rozciągania po treningu',
    'Ostrzeżenia przy zbyt dużej objętości',
    'Tygodniowy balans partii mięśniowych',
    'Mapa trenowanych partii',
    'Wykres serii na partię',
    'Wykres średniego RPE',
    'Wykres czasu treningu',
    'Wykres spalonych kalorii',
    'Wykres streaku treningowego',
    'Eksport JSON',
    'Eksport CSV',
    'Tryb premium dark',
    'Personalizacja koloru akcentu',
    'Widok dzisiejszego priorytetu',
    'Szybkie akcje treningowe',
    'Karty rekomendacji po treningu',
    'Checklist przed treningiem',
    'Checklist po treningu',
    'Tryb treningu bez internetu',
    'Fallback lokalny przy braku AI',
    'Zapis sprzętu dostępnego użytkownikowi',
    'Zapis kontuzji i ograniczeń',
    'Rekomendacje progresji tygodniowej',
    'Automatyczne wykrywanie stagnacji',
    'Ekran podsumowania miesiąca',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.done_all_outlined),
        title: Text('Wdrożone funkcje', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        subtitle: Text('${features.length} realnych modułów zamiast samego planu'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: features
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${e.key + 1}. ', style: const TextStyle(fontWeight: FontWeight.w900)),
                          Expanded(child: Text(e.value)),
                        ]),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class SmallMetric extends StatelessWidget {
  final String label;
  final String value;

  const SmallMetric({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class ProgressTextBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String suffix;

  const ProgressTextBar({super.key, required this.label, required this.value, required this.max, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)), Text(suffix, style: const TextStyle(fontWeight: FontWeight.w900))]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: theme.colorScheme.surfaceContainerHighest),
        ),
      ]),
    );
  }
}

Map<String, int> muscleCounts(List<WorkoutLog> logs, List<Exercise> customExercises) {
  final counts = <String, int>{};
  for (final log in logs) {
    for (final m in log.exerciseFrom(customExercises).muscles.take(3)) {
      counts[m] = (counts[m] ?? 0) + 1;
    }
  }
  return counts;
}

DateTime startOfTrainingWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String weekdayShortName(int weekday) {
  const names = {
    DateTime.monday: 'Pn',
    DateTime.tuesday: 'Wt',
    DateTime.wednesday: 'Śr',
    DateTime.thursday: 'Cz',
    DateTime.friday: 'Pt',
    DateTime.saturday: 'So',
    DateTime.sunday: 'Nd',
  };
  return names[weekday] ?? 'D';
}

int workoutEntryCount(List<WorkoutLog> logs) {
  final sorted = [...logs]..sort((a, b) => b.date.compareTo(a.date));
  return _groupTrainerWorkoutHistory(sorted).length;
}

int completedWorkoutSetCount(List<WorkoutLog> logs) {
  return logs.fold<int>(
    0,
    (sum, log) => sum + (log.workoutSets.isEmpty ? log.sets : log.workoutSets.where((set) => set.isCompleted).length),
  );
}

String formatProgressVolume(double volume) {
  if (volume >= 10000) return '${(volume / 1000).toStringAsFixed(1)}k kg';
  return '${volume.round()} kg';
}

String balanceWarning(List<MapEntry<String, int>> entries) {
  if (entries.length < 2) return 'Tydzień jednostronny albo za mało danych. Dodaj więcej partii do balansu.';
  final top = entries.first;
  final low = entries.last;
  if (top.value >= low.value * 3 && top.value >= 3) return 'Dominuje: ${top.key}. Najmniej: ${low.key}. Rozważ wyrównanie planu.';
  return 'Balans wygląda zdrowo. Pilnuj, żeby żadna partia nie znikała z planu na dłużej.';
}

int workoutStreak(List<WorkoutLog> logs) {
  final days = logs.map((e) => DateTime(e.date.year, e.date.month, e.date.day).toIso8601String()).toSet();
  var streak = 0;
  var d = DateTime.now();
  while (days.contains(DateTime(d.year, d.month, d.day).toIso8601String())) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

Map<String, dynamic> buildFullExport(AppStore store) => {
      'settings': store.settings.toJson(),
      'logs': store.logs.map((e) => e.toJson()).toList(),
      'plans': store.plans.map((e) => e.toJson()).toList(),
      'customExercises': store.customExercises.map((e) => e.toJson()).toList(),
      'bodyMeasurements': store.bodyMeasurements.map((e) => e.toJson()).toList(),
      'trainingImpacts': store.trainingImpacts.map((e) => e.toJson()).toList(),
      'activityEntries': store.activityEntries.map((e) => e.toJson()).toList(),
      'healthConnectSnapshots': store.healthConnectSnapshots.map((e) => e.toJson()).toList(),
      'activityCreditDiagnostics': store.activityCreditDecisionsForDay(store.selectedDate).map((decision) => decision.toJson()).toList(),
      'sharedCalorieProfile': buildSharedCalorieProfile(store),
    };

String buildCsvExport(AppStore store) {
  final buffer = StringBuffer('date,exercise,sets,reps,weightKg,durationMin,rpe,calories,volume,note\n');
  String cell(Object? value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    return '"$raw"';
  }

  for (final log in store.logs.reversed) {
    final e = log.exerciseFrom(store.customExercises);
    buffer.writeln([
      cell(log.date.toIso8601String()),
      cell(e.name),
      log.sets,
      log.reps,
      log.weightKg.toStringAsFixed(1),
      (log.durationSec / 60).round(),
      log.rpe,
      log.calories.round(),
      log.volume.round(),
      cell(log.note),
    ].join(','));
  }
  return buffer.toString();
}

/// Etap 20: eksport podstawowego progresu per ćwiczenie do CSV.
/// Dla każdego ćwiczenia: liczba sesji, max ciężar, łączna objętość, daty.
String buildProgressCsvExport(AppStore store) {
  final buffer = StringBuffer('exercise,sessions,maxWeightKg,totalVolume,bestVolumeSession,firstDate,lastDate\n');
  String cell(Object? value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    return '"$raw"';
  }

  final byExercise = <String, List<WorkoutLog>>{};
  for (final log in store.logs) {
    byExercise.putIfAbsent(log.exerciseId, () => []).add(log);
  }

  final rows = <List<Object>>[];
  byExercise.forEach((exerciseId, logs) {
    final exercise = ExerciseRepo.byId(exerciseId, store.customExercises);
    final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
    final maxWeight = logs.fold<double>(0, (m, l) => math.max(m, l.weightKg));
    final totalVolume = logs.fold<double>(0, (s, l) => s + l.volume);
    final bestVolume = logs.fold<double>(0, (m, l) => math.max(m, l.volume));
    rows.add([
      cell(exercise.name),
      logs.length,
      maxWeight.toStringAsFixed(1),
      totalVolume.round(),
      bestVolume.round(),
      cell(sorted.first.date.toIso8601String().substring(0, 10)),
      cell(sorted.last.date.toIso8601String().substring(0, 10)),
    ]);
  });

  rows.sort((a, b) => (b[3] as int).compareTo(a[3] as int));
  for (final row in rows) {
    buffer.writeln(row.join(','));
  }
  return buffer.toString();
}

void showExportDialog(BuildContext context, String data) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Eksport danych'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(data))),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}

bool equipmentMatchesSettings(Exercise exercise, String equipment) {
  final owned = equipment.toLowerCase();
  final need = exercise.equipment.toLowerCase();
  if (need.contains('masa ciała') || need.contains('mata')) return true;
  if (owned.trim().isEmpty) return true;
  for (final part in owned.split(RegExp(r'[,/;]+'))) {
    final token = part.trim();
    if (token.length >= 3 && need.contains(token)) return true;
  }
  return false;
}

bool limitationSafe(Exercise exercise, String limitations) {
  final l = limitations.toLowerCase();
  if (l.trim().isEmpty) return true;
  final text = '${exercise.name} ${exercise.category} ${exercise.muscles.join(' ')}'.toLowerCase();
  if ((l.contains('kolan') || l.contains('knee')) && (text.contains('nogi') || text.contains('squat') || text.contains('przysiad') || text.contains('lunge') || text.contains('wykrok'))) return false;
  if ((l.contains('bark') || l.contains('shoulder')) && (text.contains('barki') || text.contains('press') || text.contains('dipy') || text.contains('pomp'))) return false;
  if ((l.contains('plec') || l.contains('lędź') || l.contains('ledz') || l.contains('back')) && (text.contains('martwy') || text.contains('deadlift') || text.contains('row') || text.contains('wiosł'))) return false;
  return true;
}

int trainingDayCalorieBoost(DayTotals totals, AppSettings settings) {
  final mode = normalizeTrainingMode(settings.trainingMode);
  final minutes = totals.durationSec / 60;
  var boost = (totals.calories * 0.35 + totals.volume / 250 + minutes * 2).round();
  if (mode == 'Redukcja') boost = (boost * 0.55).round();
  if (mode == 'Masa') boost = (boost * 1.15).round();
  if (mode == 'Kondycja') boost = (boost + minutes * 2).round();
  return boost.clamp(0, 650).toInt();
}

TrainingImpact buildTrainingImpactForCompletedWorkout({
  required ActiveWorkoutSession session,
  required List<WorkoutLog> completedLogs,
  required AppSettings settings,
  required DateTime endedAt,
}) {
  final durationSeconds = math.max(0, endedAt.difference(session.startedAt).inSeconds);
  final durationMin = math.max(1, (durationSeconds + 59) ~/ 60);
  final loggedCalories = completedLogs.fold<double>(0, (sum, log) => sum + log.calories).round();
  final fallbackCalories = (durationMin * 5 + session.completedSetCount * 6 + session.volume / 600).round();
  final estimatedBurnedKcal = math.max(loggedCalories, fallbackCalories).clamp(0, 2200).toInt();
  final calorieAdjustment = suggestedCalorieAdjustmentForTraining(estimatedBurnedKcal, settings.trainingMode);
  final waterMl = suggestedExtraWaterForTraining(durationMin: durationMin, averageRpe: session.averageRpe);
  final proteinG = suggestedExtraProteinForTraining(settings: settings, setCount: session.completedSetCount, averageRpe: session.averageRpe, volume: session.volume);

  return TrainingImpact(
    id: 'impact_${session.id}',
    sessionId: session.id,
    sessionName: '${session.planName} · ${session.dayTitle}',
    date: endedAt,
    isTrainingDay: session.completedSetCount > 0,
    estimatedBurnedKcal: estimatedBurnedKcal,
    suggestedCalorieAdjustmentKcal: calorieAdjustment,
    suggestedExtraWaterMl: waterMl,
    suggestedExtraProteinG: proteinG,
    postWorkoutMealSuggestion: postWorkoutMealSuggestion(proteinG: proteinG, calorieAdjustmentKcal: calorieAdjustment, mode: settings.trainingMode),
    durationMin: durationMin,
    exerciseCount: session.completedExerciseCount,
    setCount: session.completedSetCount,
    volumeKg: session.volume,
    averageRpe: session.averageRpe,
    createdAt: DateTime.now(),
  );
}

int suggestedCalorieAdjustmentForTraining(int estimatedBurnedKcal, String trainingMode) {
  final mode = normalizeTrainingMode(trainingMode);
  var factor = 0.5;
  if (mode == 'Redukcja') factor = 0.35;
  if (mode == 'Masa') factor = 0.75;
  if (mode == 'Kondycja') factor = 0.65;
  return (estimatedBurnedKcal * factor).round().clamp(0, 700).toInt();
}

int suggestedExtraWaterForTraining({
  required int durationMin,
  required double averageRpe,
}) {
  final intensityBonus = averageRpe >= 8 ? 150 : 0;
  return (350 + durationMin * 8 + intensityBonus).clamp(350, 1800).toInt();
}

int suggestedExtraProteinForTraining({
  required AppSettings settings,
  required int setCount,
  required double averageRpe,
  required double volume,
}) {
  var protein = (settings.bodyWeightKg * 0.25).round();
  if (setCount >= 10) protein += 5;
  if (averageRpe >= 8) protein += 5;
  if (volume >= 12000) protein += 5;
  return protein.clamp(20, 45).toInt();
}

String postWorkoutMealSuggestion({
  required int proteinG,
  required int calorieAdjustmentKcal,
  required String mode,
}) {
  final normalizedMode = normalizeTrainingMode(mode);
  if (normalizedMode == 'Redukcja') {
    return 'Po treningu: $proteinG g białka, dużo płynów i lekki posiłek bez automatycznego podbijania kalorii ponad plan.';
  }
  if (calorieAdjustmentKcal >= 350) {
    return 'Po treningu: $proteinG g białka + porcja węglowodanów. Licznik Kalorii może potraktować to jako sugestię posiłku potreningowego.';
  }
  return 'Po treningu: $proteinG g białka i uzupełnienie płynów. Kalorie dodawać ostrożnie według celu dnia.';
}

Map<String, dynamic> buildSharedCalorieProfile(AppStore store) {
  final today = store.totalsForDay(store.selectedDate);
  final dayImpacts = store.trainingImpacts.where((impact) => sameDay(impact.date, store.selectedDate)).toList();
  final activityDecisions = store.activityCreditDecisionsForDay(store.selectedDate);
  return {
    'source': 'Trainer',
    'date': store.selectedDate.toIso8601String(),
    'training_mode': store.settings.trainingMode,
    'training_level': store.settings.level,
    'body_weight_kg': store.settings.bodyWeightKg,
    'goal': store.settings.goal,
    'equipment': store.settings.equipment,
    'limitations': store.settings.limitations,
    'today_training_calories': today.calories.round(),
    'suggested_calorie_boost': trainingDayCalorieBoost(today, store.settings),
    'today_volume_kg': today.volume.round(),
    'today_duration_min': (today.durationSec / 60).round(),
    'training_impacts': dayImpacts.map((impact) => impact.toCalorieBridgeJson()).toList(),
    'calorie_bridge_queue_key': TrainerCalorieLocalAdapter.impactQueueKey,
    'activity_credit_decisions': activityDecisions.map((decision) => decision.toJson()).toList(),
    'activity_credit_included_kcal': totalCreditedActivityKcal(activityDecisions),
  };
}

String buildWarmup(AppSettings settings) => '''Rozgrzewka 8-12 min
1. 2 min spokojnego cardio lub marszu.
2. Krążenia bioder, barków i nadgarstków po 30 s.
3. Aktywacja: glute bridge 2x12, dead bug 2x8/strona.
4. Serie wprowadzające pierwszego ćwiczenia: 2-3 lekkie serie.
Poziom: ${settings.level}. Tryb: ${settings.trainingMode}.''';

String buildCooldown(AppSettings settings) => '''Schłodzenie 6-10 min
1. 2-3 min spokojnego oddechu i marszu.
2. Rozluźnienie partii głównych z treningu.
3. Lekka mobilizacja bioder/klatki/barków.
4. Zapisz RPE, ból i jedną notatkę techniczną.
Przy ograniczeniach: ${settings.limitations.isEmpty ? 'brak zapisanych' : settings.limitations}.''';

String buildMobility(AppSettings settings) => '''Mobilizacja dobrana pod profil
- Biodra: 90/90, couch stretch, głęboki przysiad z oddechem.
- Barki: wall slides, face pull gumą, rotacje zewnętrzne.
- Plecy: cat-cow, oddech przeponowy, bird dog.
Sprzęt: ${settings.equipment}.''';

String buildStretching(AppSettings settings) => '''Rozciąganie po treningu
- Nogi/pośladki: 2x40 s na stronę.
- Klatka/barki: 2x30-40 s.
- Zginacze bioder: 2x40 s.
- Łydki po bieganiu/skakance: 2x45 s.
Nie rozciągaj agresywnie miejsca bólu.''';

String buildTargetPlan(String target, AppSettings settings) {
  final t = target.toLowerCase();
  if (t.contains('brzuch') || t.contains('core')) {
    return '''Plan brzuch + core z obciążeniem
1. Plank z obciążeniem 4x30-45 s
2. Unoszenie nóg 4x10-12
3. Russian twist z talerzem 3x20
4. Hollow hold 4x20-30 s
5. Farmer walk 4x40-60 m
Progresja: dodawaj 5 s lub 1-2 kg tygodniowo.''';
  }
  if (t.contains('nogi'))
    return '''Plan pod nogi
1. Przysiad / goblet squat 4x8-12
2. Martwy ciąg rumuński 4x8-10
3. Przysiad bułgarski 3x8/strona
4. Hip thrust 4x10
5. Wspięcia na palce 4x15-20''';
  if (t.contains('plecy'))
    return '''Plan pod plecy
1. Podciąganie lub ściąganie drążka 4x6-10
2. Wiosłowanie 4x8-12
3. Face pull 3x15
4. Martwy ciąg rumuński lekko 3x8
5. Uginanie ramion 3x12''';
  return '''Plan pod $target
1. Ćwiczenie główne 4x6-10
2. Wariant jednostronny 3x8-12
3. Akcesorium 3x12-15
4. Core/stabilizacja 3 serie
5. Schłodzenie i notatka techniczna.''';
}

String buildTemplatePlan(String template, AppSettings settings) {
  switch (template) {
    case 'FBW':
      return 'FBW 3-4 dni: Przysiad 4x8, Pompka/Wyciskanie 4x10, Wiosłowanie 4x10, RDL 3x8, Plank 3x45 s.';
    case 'PPL':
      return 'PPL: Push - wyciskanie, barki, triceps. Pull - podciąganie, wiosło, biceps. Legs - przysiad, RDL, hip thrust, łydki.';
    case 'Góra/Dół':
      return 'Góra/Dół: Góra - klatka, plecy, barki, ręce. Dół - przysiad, hinge, wykroki, core. Rotuj 4 dni w tygodniu.';
    default:
      return buildTargetPlan('brzuch i core', settings);
  }
}

String weeklyProgressionAdvice(List<WorkoutLog> logs) {
  if (logs.length < 3) return 'Zbieraj dane przez kilka treningów. Na start progresuj techniką i stałym zakresem ruchu.';
  final avgRpe = logs.fold<double>(0, (a, e) => a + e.rpe) / logs.length;
  if (avgRpe <= 7) return 'RPE jest pod kontrolą. Dodaj 1-2 powtórzenia albo 2,5-5 kg w jednym głównym ćwiczeniu.';
  if (avgRpe >= 8.5) return 'RPE wysokie. Zostań przy ciężarze, popraw technikę albo odejmij 10-15% objętości.';
  return 'Progresuj mało: jedna seria więcej na słabą partię albo minimalny ciężar w ćwiczeniu bazowym.';
}

String deloadAdvice(List<WorkoutLog> logs) {
  final now = DateTime.now();
  final last = DayTotals.from(logs.where((e) => !e.date.isBefore(now.subtract(const Duration(days: 6)))).toList());
  final prev = DayTotals.from(logs.where((e) => e.date.isBefore(now.subtract(const Duration(days: 6))) && !e.date.isBefore(now.subtract(const Duration(days: 13)))).toList());
  final avgRpe = logs.isEmpty ? 0.0 : logs.take(8).fold<double>(0, (a, e) => a + e.rpe) / math.min(8, logs.length);
  if (avgRpe >= 8.7 || (prev.volume > 0 && last.volume < prev.volume * 0.65)) return 'Sugerowany deload: 5-7 dni, objętość -30-40%, ciężar -10-15%, technika i sen jako priorytet.';
  return 'Deload nie jest teraz konieczny. Obserwuj RPE, sen, ból i spadek motywacji.';
}

void showSmartTextDialog(BuildContext context, String title, String text) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(text))),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}

class CalorieBridgeCard extends StatelessWidget {
  final AppStore store;
  const CalorieBridgeCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final totals = store.totalsForDay(store.selectedDate);
    final boost = trainingDayCalorieBoost(totals, store.settings);
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(Icons.local_fire_department_outlined, color: theme.colorScheme.primary),
        title: const Text('Podbicie kalorii w dzień ciężkiego treningu'),
        subtitle: Text('Dzisiaj: ${totals.calories.round()} kcal z treningu, ${totals.volume.round()} kg objętości. Sugestia dla Licznika Kalorii: +$boost kcal.'),
        trailing: Text('+$boost', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class SharedProfileBridgeCard extends StatelessWidget {
  final AppStore store;
  const SharedProfileBridgeCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sync_alt_outlined),
        title: const Text('Most profilu z Licznikiem Kalorii'),
        subtitle: const Text('Eksportuje wspólny profil JSON: tryb, cel, masa, trening dnia i sugerowane kcal.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showExportDialog(context, prettyJson(buildSharedCalorieProfile(store))),
      ),
    );
  }
}

class DailyPriorityCard extends StatelessWidget {
  final AppStore store;
  const DailyPriorityCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final totals = store.totalsForDay(store.selectedDate);
    final priority = totals.sessions == 0
        ? 'Dzisiaj priorytet: wykonaj plan albo krótki core + mobilizacja.'
        : totals.volume > 8000
            ? 'Dzisiaj priorytet: regeneracja, sen i jedzenie po ciężkim treningu.'
            : 'Dzisiaj priorytet: zapisz notatkę techniczną i oceń RPE.';
    return Card(child: ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Dzisiejszy priorytet'), subtitle: Text(priority)));
  }
}

class TrainingModeCard extends StatelessWidget {
  final AppSettings settings;
  const TrainingModeCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final mode = normalizeTrainingMode(settings.trainingMode);
    final text = mode == 'Redukcja'
        ? 'Priorytet: utrzymaj siłę, kontroluj objętość i nie tnij regeneracji.'
        : mode == 'Masa'
            ? 'Priorytet: progres ciężaru/objętości i dodatni bilans kalorii.'
            : mode == 'Kondycja'
                ? 'Priorytet: czas pracy, tętno, bieganie/rower/skakanka i stopniowa objętość.'
                : 'Priorytet: siła + sylwetka, umiarkowana objętość i stabilny progres.';
    return Card(child: ListTile(leading: const Icon(Icons.tune_outlined), title: Text('Tryb: $mode'), subtitle: Text(text)));
  }
}

class FeelingJournalCard extends StatefulWidget {
  @override
  State<FeelingJournalCard> createState() => _FeelingJournalCardState();
}

class _FeelingJournalCardState extends State<FeelingJournalCard> {
  double energy = 7;
  double stress = 4;
  double sleep = 7;

  @override
  Widget build(BuildContext context) {
    final score = ((energy + sleep + (10 - stress)) / 3).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [Icon(Icons.mood_outlined), SizedBox(width: 8), Expanded(child: Text('Dziennik samopoczucia przed treningiem', style: TextStyle(fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 8),
          Text('Gotowość: $score/10'),
          Slider(value: energy, min: 1, max: 10, divisions: 9, label: 'Energia ${energy.round()}', onChanged: (v) => setState(() => energy = v)),
          Slider(value: sleep, min: 1, max: 10, divisions: 9, label: 'Sen ${sleep.round()}', onChanged: (v) => setState(() => sleep = v)),
          Slider(value: stress, min: 1, max: 10, divisions: 9, label: 'Stres ${stress.round()}', onChanged: (v) => setState(() => stress = v)),
        ]),
      ),
    );
  }
}

class RestTimerCard extends StatefulWidget {
  final AppSettings settings;
  const RestTimerCard({super.key, required this.settings});

  @override
  State<RestTimerCard> createState() => _RestTimerCardState();
}

class _RestTimerCardState extends State<RestTimerCard> {
  Timer? timer;
  int remaining = 0;

  int get recommendedSeconds {
    final mode = normalizeTrainingMode(widget.settings.trainingMode);
    if (mode == 'Masa') return 120;
    if (mode == 'Kondycja') return 45;
    if (mode == 'Redukcja') return 60;
    return 90;
  }

  void start() {
    timer?.cancel();
    setState(() => remaining = recommendedSeconds);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remaining <= 1) {
        t.cancel();
        if (mounted) setState(() => remaining = 0);
      } else {
        if (mounted) setState(() => remaining--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final min = remaining ~/ 60;
    final sec = (remaining % 60).toString().padLeft(2, '0');
    return Card(child: ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Timer przerw zależny od celu'), subtitle: Text('Rekomendowana przerwa: $recommendedSeconds s · aktywnie: $min:$sec'), trailing: FilledButton(onPressed: start, child: const Text('Start'))));
  }
}

class PlanTemplatesCard extends StatelessWidget {
  final AppSettings settings;
  const PlanTemplatesCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gotowe plany', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: ['FBW', 'PPL', 'Góra/Dół', 'Brzuch z obciążeniem'].map((t) => FilledButton.tonal(onPressed: () => showSmartTextDialog(context, t, buildTemplatePlan(t, settings)), child: Text(t))).toList()),
        ]),
      ),
    );
  }
}

class TargetedPlanGeneratorsCard extends StatelessWidget {
  final AppSettings settings;
  const TargetedPlanGeneratorsCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Generatory planu', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: ['Nogi', 'Plecy', 'Klatka', 'Barki', 'Brzuch i core'].map((t) => OutlinedButton(onPressed: () => showSmartTextDialog(context, 'Plan: $t', buildTargetPlan(t, settings)), child: Text(t))).toList()),
        ]),
      ),
    );
  }
}

class MobilityAndStretchingCard extends StatelessWidget {
  final AppSettings settings;
  const MobilityAndStretchingCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rozgrzewka, schłodzenie, mobilizacja', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(onPressed: () => showSmartTextDialog(context, 'Rozgrzewka', buildWarmup(settings)), child: const Text('Rozgrzewka')),
            FilledButton.tonal(onPressed: () => showSmartTextDialog(context, 'Schłodzenie', buildCooldown(settings)), child: const Text('Schłodzenie')),
            FilledButton.tonal(onPressed: () => showSmartTextDialog(context, 'Mobilizacja', buildMobility(settings)), child: const Text('Mobilizacja')),
            FilledButton.tonal(onPressed: () => showSmartTextDialog(context, 'Rozciąganie', buildStretching(settings)), child: const Text('Rozciąganie')),
          ]),
        ]),
      ),
    );
  }
}

class VolumeWarningsCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  const VolumeWarningsCard({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    final totals = DayTotals.from(logs);
    final warning = totals.volume > 35000 || totals.durationSec > 420 * 60 ? 'Objętość tygodnia jest wysoka. Rozważ lżejszy dzień albo deload.' : 'Objętość tygodniowa wygląda bezpiecznie przy obecnych danych.';
    return Card(child: ListTile(leading: const Icon(Icons.warning_amber_outlined), title: const Text('Ostrzeżenia objętości'), subtitle: Text('$warning Objętość: ${totals.volume.round()} kg, czas: ${(totals.durationSec / 60).round()} min.')));
  }
}

class MuscleMapCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;
  const MuscleMapCard({super.key, required this.logs, required this.customExercises});
  @override
  Widget build(BuildContext context) {
    final counts = muscleCounts(logs, customExercises);
    final theme = Theme.of(context);
    final maxV = counts.values.isEmpty ? 1 : counts.values.reduce(math.max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.accessibility_new_outlined, color: theme.colorScheme.primary), const SizedBox(width: 8), const Expanded(child: Text('Mapa trenowanych partii', style: TextStyle(fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 12),
          SizedBox(height: 210, child: CustomPaint(painter: BodyHeatMapPainter(counts: counts, maxValue: maxV, color: theme.colorScheme.primary), child: const SizedBox.expand())),
        ]),
      ),
    );
  }
}

class BodyHeatMapPainter extends CustomPainter {
  final Map<String, int> counts;
  final int maxValue;
  final Color color;
  BodyHeatMapPainter({required this.counts, required this.maxValue, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(.16);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)), p);
    double a(String key) => ((counts.entries.where((e) => e.key.toLowerCase().contains(key)).fold<int>(0, (a, e) => a + e.value)) / math.max(1, maxValue)).clamp(.12, 1.0).toDouble();
    void part(Rect r, String key) => canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(30)), Paint()..color = color.withOpacity(a(key)));
    final w = size.width, h = size.height;
    part(Rect.fromCenter(center: Offset(w * .5, h * .18), width: 42, height: 42), '');
    part(Rect.fromCenter(center: Offset(w * .5, h * .37), width: 74, height: 92), 'brzuch');
    part(Rect.fromCenter(center: Offset(w * .31, h * .34), width: 44, height: 98), 'bark');
    part(Rect.fromCenter(center: Offset(w * .69, h * .34), width: 44, height: 98), 'bark');
    part(Rect.fromCenter(center: Offset(w * .4, h * .72), width: 48, height: 118), 'uda');
    part(Rect.fromCenter(center: Offset(w * .6, h * .72), width: 48, height: 118), 'uda');
  }

  @override
  bool shouldRepaint(covariant BodyHeatMapPainter oldDelegate) => oldDelegate.counts != counts || oldDelegate.color != color;
}

class SetsByMuscleChartCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;
  const SetsByMuscleChartCard({super.key, required this.logs, required this.customExercises});
  @override
  Widget build(BuildContext context) {
    final counts = muscleCounts(logs, customExercises);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxV = entries.isEmpty ? 1 : entries.first.value;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Wykres serii na partię', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 10), if (entries.isEmpty) const Text('Brak danych') else ...entries.take(8).map((e) => ProgressTextBar(label: e.key, value: e.value.toDouble(), max: maxV.toDouble(), suffix: '${e.value}x'))])));
  }
}

class RpeChartCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  const RpeChartCard({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    final values = logs.reversed.take(14).map((e) => e.rpe.toDouble()).toList();
    return ChartCard(title: 'Wykres średniego RPE', values: values.isEmpty ? [0] : values, suffix: 'RPE');
  }
}

class StreakChartCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  const StreakChartCard({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(14, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 13 - i)));
    final trained = logs.map((e) => DateTime(e.date.year, e.date.month, e.date.day).toIso8601String()).toSet();
    final values = days.map((d) => trained.contains(d.toIso8601String()) ? 1.0 : 0.0).toList();
    return ChartCard(title: 'Wykres streaku treningowego', values: values, suffix: 'dzień');
  }
}

class ProgressByExerciseCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  final List<Exercise> customExercises;
  const ProgressByExerciseCard({super.key, required this.logs, required this.customExercises});
  @override
  Widget build(BuildContext context) {
    final by = <String, List<WorkoutLog>>{};
    for (final l in logs) {
      by.putIfAbsent(l.exerciseId, () => []).add(l);
    }
    final entries = by.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Progres ćwiczenia: ciężar, powtórzenia, objętość', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                const Text('Brak danych')
              else
                ...entries.take(5).map((e) {
                  final ex = ExerciseRepo.byId(e.key, customExercises);
                  final best = e.value.reduce((a, b) => a.volume >= b.volume ? a : b);
                  return ListTile(contentPadding: EdgeInsets.zero, title: Text(ex.name), subtitle: Text('Najlepsza objętość: ${best.volume.round()} kg · ciężar ${best.weightKg.toStringAsFixed(1)} kg · powt. ${best.reps}'));
                })
            ])));
  }
}

class PostWorkoutRecommendationCard extends StatelessWidget {
  final List<WorkoutLog> logs;
  const PostWorkoutRecommendationCard({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    final totals = DayTotals.from(logs);
    final text = totals.sessions == 0
        ? 'Po treningu zobaczysz tu rekomendacje regeneracji, progresji i posiłku.'
        : totals.volume > 12000
            ? 'Po treningu: białko + węgle, spacer 10 min, sen 7-9 h, jutro lekki core/mobilizacja.'
            : 'Po treningu: zapisz notatkę techniczną, rozciągnij trenowane partie i utrzymaj nawodnienie.';
    return Card(child: ListTile(leading: const Icon(Icons.recommend_outlined), title: const Text('Rekomendacje po treningu'), subtitle: Text(text)));
  }
}

class OfflineModeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Card(child: ListTile(leading: Icon(Icons.wifi_off_outlined), title: Text('Tryb offline i lokalny fallback'), subtitle: Text('Baza ćwiczeń, dziennik, wykresy, plan lokalny, timer, checklisty i eksport działają bez internetu. AI i wger wymagają sieci.')));
  }
}

class TechniqueChecklistForExercise extends StatefulWidget {
  final Exercise exercise;
  const TechniqueChecklistForExercise({super.key, required this.exercise});
  @override
  State<TechniqueChecklistForExercise> createState() => _TechniqueChecklistForExerciseState();
}

class _TechniqueChecklistForExerciseState extends State<TechniqueChecklistForExercise> {
  final checked = <int, bool>{};
  @override
  Widget build(BuildContext context) {
    final items = [...widget.exercise.commonMistakes, 'Zapisz notatkę techniczną po serii', 'Nagrywaj serię roboczą, gdy coś boli'];
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Błędy techniczne do odhaczenia', style: TextStyle(fontWeight: FontWeight.w900)), ...items.asMap().entries.map((e) => CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: checked[e.key] ?? false, title: Text(e.value), onChanged: (v) => setState(() => checked[e.key] = v ?? false)))])));
  }
}

class ExerciseSubstitutionsCard extends StatelessWidget {
  final Exercise exercise;
  const ExerciseSubstitutionsCard({super.key, required this.exercise});
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final allExercises = ExerciseRepo.combined(store.customExercises);
    final resolved = <Exercise>[];
    for (final alternative in exercise.alternatives) {
      final normalized = alternative.toLowerCase();
      final match = allExercises.where(
        (candidate) => candidate.id != exercise.id && (candidate.name.toLowerCase().contains(normalized) || normalized.contains(candidate.name.toLowerCase())),
      );
      if (match.isNotEmpty) resolved.add(match.first);
    }
    final suggestions = allExercises
        .where(
          (candidate) => candidate.id != exercise.id && (candidate.category == exercise.category || candidate.muscles.any(exercise.muscles.contains)),
        )
        .where((candidate) => !resolved.any((item) => item.id == candidate.id))
        .take(3)
        .toList();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alternatywy',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...exercise.alternatives.map(
              (alternative) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(alternative)),
                  ],
                ),
              ),
            ),
            if (resolved.isNotEmpty || suggestions.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Podobne ćwiczenia w bazie',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              ...[...resolved, ...suggestions].take(4).map(
                    (candidate) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(candidate.name),
                      subtitle: Text(
                        '${candidate.primaryMuscle} · ${candidate.equipment}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => ExerciseDetailsPage(
                            exerciseId: candidate.id,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class ExerciseProgressHistorySection extends StatelessWidget {
  const ExerciseProgressHistorySection({
    super.key,
    required this.exercise,
    required this.logs,
  });

  final Exercise exercise;
  final List<WorkoutLog> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = buildExerciseProgressData(exerciseId: exercise.id, logs: logs);
    if (!progress.hasHistory) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Historia progresu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Brak zapisanych serii dla tego ćwiczenia. Po wykonaniu treningu zobaczysz tutaj ciężar, objętość, 1RM i sugestię progresji.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OneRepMaxCalculatorCard(initialWeight: 0, initialReps: math.max(1, exercise.defaultReps)),
            ],
          ),
        ),
      );
    }

    final points = progress.points.takeLast(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Historia progresu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lokalna analiza ostatnich wykonań tego ćwiczenia.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                _ExerciseProgressMetricGrid(progress: progress),
                const SizedBox(height: 14),
                _ExerciseProgressStatusBox(progress: progress),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Ciężar w czasie',
          subtitle: 'Największy ciężar użyty w kolejnych wykonaniach ćwiczenia',
          values: points.map((point) => point.bestWeight).toList(),
          labels: points.map((point) => shortDate(point.date)).toList(),
          suffix: 'kg',
          icon: Icons.fitness_center_outlined,
        ),
        const SizedBox(height: 12),
        SimpleProgressBarChartCard(
          title: 'Objętość w czasie',
          subtitle: 'Objętość ćwiczenia: ciężar × powtórzenia w zapisanych seriach',
          values: points.map((point) => point.volume).toList(),
          labels: points.map((point) => shortDate(point.date)).toList(),
          suffix: 'kg',
          icon: Icons.stacked_bar_chart_rounded,
        ),
        const SizedBox(height: 12),
        OneRepMaxCalculatorCard(
          initialWeight: progress.bestSet?.weightKg ?? progress.lastUsedWeight,
          initialReps: math.max(1, progress.bestSet?.repetitions ?? progress.lastRepetitions),
        ),
      ],
    );
  }
}

class _ExerciseProgressMetricGrid extends StatelessWidget {
  const _ExerciseProgressMetricGrid({required this.progress});

  final ExerciseProgressData progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 600
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth >= 420
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
        final bestSet = progress.bestSet;
        final tiles = [
          _ExerciseProgressMetric(label: 'Ostatni ciężar', value: formatProgressWeight(progress.lastUsedWeight)),
          _ExerciseProgressMetric(label: 'Najlepszy ciężar', value: formatProgressWeight(progress.bestWeight)),
          _ExerciseProgressMetric(label: 'Najlepsza seria', value: bestSet == null ? '—' : '${formatProgressWeight(bestSet.weightKg)} × ${bestSet.repetitions}'),
          _ExerciseProgressMetric(label: 'Objętość łącznie', value: formatProgressVolume(progress.totalVolume)),
          _ExerciseProgressMetric(label: 'Ostatnio', value: progress.lastPerformedAt == null ? '—' : trainerHistoryFullDate(progress.lastPerformedAt!)),
          _ExerciseProgressMetric(label: 'Szac. 1RM', value: formatProgressWeight(progress.estimatedOneRepMax)),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _ExerciseProgressMetric extends StatelessWidget {
  const _ExerciseProgressMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ExerciseProgressStatusBox extends StatelessWidget {
  const _ExerciseProgressStatusBox({required this.progress});

  final ExerciseProgressData progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = progress.isStagnating ? theme.colorScheme.tertiary : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(progress.isStagnating ? Icons.pause_circle_outline_rounded : Icons.trending_up_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(progress.stagnationMessage, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 10),
          Text('Sugestia: ${progress.suggestionTitle}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(progress.suggestionDetails, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
        ],
      ),
    );
  }
}

class OneRepMaxCalculatorCard extends StatefulWidget {
  const OneRepMaxCalculatorCard({
    super.key,
    required this.initialWeight,
    required this.initialReps,
  });

  final double initialWeight;
  final int initialReps;

  @override
  State<OneRepMaxCalculatorCard> createState() => _OneRepMaxCalculatorCardState();
}

class _OneRepMaxCalculatorCardState extends State<OneRepMaxCalculatorCard> {
  late final TextEditingController weight;
  late final TextEditingController reps;

  @override
  void initState() {
    super.initState();
    weight = TextEditingController(text: widget.initialWeight <= 0 ? '' : widget.initialWeight.toStringAsFixed(1));
    reps = TextEditingController(text: '${widget.initialReps.clamp(1, 99)}');
  }

  @override
  void dispose() {
    weight.dispose();
    reps.dispose();
    super.dispose();
  }

  double get estimatedOneRm {
    final parsedWeight = double.tryParse(weight.text.replaceAll(',', '.')) ?? 0;
    final parsedReps = int.tryParse(reps.text) ?? 1;
    return estimateOneRepMax(parsedWeight, parsedReps);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Kalkulator 1RM', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  TextField(
                    key: const Key('one_rm_weight'),
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ciężar kg'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    key: const Key('one_rm_reps'),
                    controller: reps,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Powtórzenia'),
                    onChanged: (_) => setState(() {}),
                  ),
                ];
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      fields.first,
                      const SizedBox(height: 10),
                      fields.last,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fields.first),
                    const SizedBox(width: 10),
                    Expanded(child: fields.last),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('Szacowane 1RM', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900))),
                  Text(formatProgressWeight(estimatedOneRm), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('Wzór Epleya: ciężar × (1 + powtórzenia / 30). To szacunek, nie zalecenie maksowania.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class ExerciseProgressPoint {
  const ExerciseProgressPoint({
    required this.date,
    required this.bestWeight,
    required this.bestReps,
    required this.volume,
    required this.averageRpe,
    required this.bestSet,
  });

  final DateTime date;
  final double bestWeight;
  final int bestReps;
  final double volume;
  final double averageRpe;
  final WorkoutSet bestSet;
}

class ExerciseProgressData {
  const ExerciseProgressData({
    required this.points,
    required this.lastUsedWeight,
    required this.lastRepetitions,
    required this.bestWeight,
    required this.bestSet,
    required this.totalVolume,
    required this.lastPerformedAt,
    required this.estimatedOneRepMax,
    required this.isStagnating,
    required this.stagnationMessage,
    required this.suggestionTitle,
    required this.suggestionDetails,
  });

  final List<ExerciseProgressPoint> points;
  final double lastUsedWeight;
  final int lastRepetitions;
  final double bestWeight;
  final WorkoutSet? bestSet;
  final double totalVolume;
  final DateTime? lastPerformedAt;
  final double estimatedOneRepMax;
  final bool isStagnating;
  final String stagnationMessage;
  final String suggestionTitle;
  final String suggestionDetails;

  bool get hasHistory => points.isNotEmpty;
}

ExerciseProgressData buildExerciseProgressData({
  required String exerciseId,
  required List<WorkoutLog> logs,
}) {
  final exerciseLogs = logs.where((log) => log.exerciseId == exerciseId).toList()..sort((left, right) => left.date.compareTo(right.date));
  final points = <ExerciseProgressPoint>[];
  for (final log in exerciseLogs) {
    final sets = progressSetsForLog(log);
    if (sets.isEmpty) continue;
    final bestSet = sets.reduce(preferBetterProgressSet);
    final bestWeight = sets.fold<double>(0, (maxWeight, set) => math.max(maxWeight, set.weightKg));
    final bestReps = sets.fold<int>(0, (maxReps, set) => math.max(maxReps, set.repetitions));
    final averageRpe = sets.fold<int>(0, (sum, set) => sum + set.rpe) / sets.length;
    points.add(
      ExerciseProgressPoint(
        date: log.date,
        bestWeight: bestWeight,
        bestReps: bestReps,
        volume: log.volume,
        averageRpe: averageRpe,
        bestSet: bestSet,
      ),
    );
  }

  if (points.isEmpty) {
    return const ExerciseProgressData(
      points: [],
      lastUsedWeight: 0,
      lastRepetitions: 0,
      bestWeight: 0,
      bestSet: null,
      totalVolume: 0,
      lastPerformedAt: null,
      estimatedOneRepMax: 0,
      isStagnating: false,
      stagnationMessage: 'Brak danych progresu',
      suggestionTitle: 'Utrzymaj',
      suggestionDetails: 'Zapisz kilka treningów tego ćwiczenia, a Trainer pokaże lokalną sugestię progresji.',
    );
  }

  final bestSet = points.map((point) => point.bestSet).reduce(preferBetterProgressSet);
  final isStagnating = detectExerciseProgressStagnation(points);
  final suggestion = exerciseProgressSuggestion(points, isStagnating);
  return ExerciseProgressData(
    points: points,
    lastUsedWeight: points.last.bestWeight,
    lastRepetitions: points.last.bestReps,
    bestWeight: points.fold<double>(0, (maxWeight, point) => math.max(maxWeight, point.bestWeight)),
    bestSet: bestSet,
    totalVolume: points.fold<double>(0, (sum, point) => sum + point.volume),
    lastPerformedAt: points.last.date,
    estimatedOneRepMax: estimateOneRepMax(bestSet.weightKg, bestSet.repetitions),
    isStagnating: isStagnating,
    stagnationMessage: isStagnating ? 'Możliwa stagnacja' : 'Progres wygląda aktywnie',
    suggestionTitle: suggestion.$1,
    suggestionDetails: suggestion.$2,
  );
}

List<WorkoutSet> progressSetsForLog(WorkoutLog log) {
  final completed = log.workoutSets.where((set) => set.isCompleted).toList();
  if (completed.isNotEmpty) return completed;
  if (log.sets <= 0 || log.reps <= 0) return const [];
  return [
    WorkoutSet(
      id: '${log.id}_aggregate',
      order: 1,
      repetitions: log.reps,
      weightKg: log.weightKg,
      durationSec: 0,
      rpe: log.rpe,
      isCompleted: true,
    ),
  ];
}

WorkoutSet preferBetterProgressSet(WorkoutSet left, WorkoutSet right) {
  final leftOneRm = estimateOneRepMax(left.weightKg, left.repetitions);
  final rightOneRm = estimateOneRepMax(right.weightKg, right.repetitions);
  if ((rightOneRm - leftOneRm).abs() > 0.05) return rightOneRm > leftOneRm ? right : left;
  return right.volume > left.volume ? right : left;
}

double estimateOneRepMax(double weightKg, int repetitions) {
  if (weightKg <= 0 || repetitions <= 0) return 0;
  if (repetitions == 1) return weightKg;
  return weightKg * (1 + repetitions / 30);
}

bool detectExerciseProgressStagnation(List<ExerciseProgressPoint> points) {
  if (points.length < 3) return false;
  final recent = points.sublist(points.length - 3);
  final first = recent.first;
  final last = recent.last;
  final weightImproved = last.bestWeight > first.bestWeight + 0.25;
  final repsImproved = last.bestReps > first.bestReps;
  final volumeImproved = last.volume > first.volume + 0.5;
  return !(weightImproved || repsImproved || volumeImproved);
}

(String, String) exerciseProgressSuggestion(List<ExerciseProgressPoint> points, bool isStagnating) {
  if (points.isEmpty) {
    return ('Utrzymaj', 'Najpierw zapisz kilka serii, żeby sugestia miała sens.');
  }
  final last = points.last;
  if (last.averageRpe >= 9) {
    return ('Zrób lżejszy tydzień', 'Ostatnie serie są bardzo ciężkie. Obniż obciążenie o 5–10% albo zmniejsz liczbę serii.');
  }
  if (isStagnating && last.averageRpe <= 7.5) {
    return ('Zwiększ ciężar', 'Przez kilka wykonań nie widać wzrostu, a zapas siły jest dobry. Dodaj najmniejszy dostępny ciężar.');
  }
  if (isStagnating) {
    return ('Zwiększ powtórzenia', 'Ciężar stoi w miejscu, więc dołóż 1–2 powtórzenia w seriach roboczych zamiast od razu zwiększać kg.');
  }
  if (last.averageRpe <= 7) {
    return ('Zwiększ ciężar', 'Ostatnie wykonanie wygląda lekko. Dodaj niewielki ciężar, jeśli technika była stabilna.');
  }
  if (last.averageRpe <= 8.5) {
    return ('Utrzymaj', 'Progres jest widoczny. Powtórz ciężar i spróbuj poprawić technikę albo jedną serię.');
  }
  return ('Zrób lżejszy tydzień', 'Intensywność jest wysoka. Lżejszy tydzień pomoże wrócić do progresji.');
}

String formatProgressWeight(double weight) {
  if (weight <= 0) return '0 kg';
  if (weight == weight.roundToDouble()) return '${weight.round()} kg';
  return '${weight.toStringAsFixed(1)} kg';
}

extension _TakeLastItems<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}

class ExerciseProgressionCard extends StatelessWidget {
  final Exercise exercise;
  const ExerciseProgressionCard({super.key, required this.exercise});
  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(leading: const Icon(Icons.stacked_line_chart_outlined), title: const Text('Rekomendacja progresji tygodniowej'), subtitle: Text('Dla ${exercise.name}: gdy wszystkie serie są techniczne przy RPE <=7, dodaj 1-2 powtórzenia albo najmniejszy dostępny ciężar. Gdy RPE >=9, utrzymaj lub odejmij 10%.')));
  }
}

Future<void> showCreateExerciseSheet(
  BuildContext context, {
  Exercise? exercise,
}) async {
  final store = AppScope.read(context);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: CreateExerciseSheetContent(
        store: store,
        exercise: exercise,
      ),
    ),
  );
}

class CreateExerciseSheetContent extends StatefulWidget {
  const CreateExerciseSheetContent({
    super.key,
    required this.store,
    this.exercise,
  });

  final AppStore store;
  final Exercise? exercise;

  @override
  State<CreateExerciseSheetContent> createState() => _CreateExerciseSheetContentState();
}

class _CreateExerciseSheetContentState extends State<CreateExerciseSheetContent> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController category;
  late final TextEditingController primaryMuscle;
  late final TextEditingController supportingMuscles;
  late final TextEditingController equipment;
  late final TextEditingController description;
  late final TextEditingController tips;
  late final TextEditingController commonMistakes;
  late final TextEditingController avoidWhen;
  late final TextEditingController alternatives;
  late String level;
  final selectedGoals = <TrainingGoal>{};

  // Etap 27: robocza, edytowalna lista multimediów ćwiczenia.
  late List<ExerciseMedia> mediaItems;
  bool _mediaExpanded = false;
  final ImagePicker _mediaPicker = ImagePicker();

  // Partie mięśniowe (muscle → rola) używane do regeneracji. Etap regeneracji.
  late Map<BodyMuscle, MuscleRole> _muscleRoles;
  bool _musclesExpanded = false;

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;
    mediaItems = List<ExerciseMedia>.from(exercise?.mediaItems ?? const <ExerciseMedia>[]);
    _mediaExpanded = mediaItems.isNotEmpty;
    _muscleRoles = {
      for (final impact in (exercise?.effectiveMuscleImpacts ?? const <ExerciseMuscleImpact>[]))
        impact.muscleGroup: impact.role,
    };
    _musclesExpanded = _muscleRoles.isNotEmpty;
    name = TextEditingController(text: exercise?.name ?? '');
    category = TextEditingController(text: exercise?.category ?? 'Inne');
    primaryMuscle = TextEditingController(
      text: exercise?.primaryMuscle ?? 'całe ciało',
    );
    supportingMuscles = TextEditingController(
      text: exercise?.supportingMuscles.join(', ') ?? '',
    );
    equipment = TextEditingController(
      text: exercise?.equipment ?? 'masa ciała',
    );
    description = TextEditingController(text: exercise?.description ?? '');
    tips = TextEditingController(text: exercise?.tips.join('\n') ?? '');
    commonMistakes = TextEditingController(
      text: exercise?.commonMistakes.join('\n') ?? '',
    );
    avoidWhen = TextEditingController(
      text: exercise?.avoidWhen.join('\n') ?? '',
    );
    alternatives = TextEditingController(
      text: exercise?.alternatives.join('\n') ?? '',
    );
    level = normalizeLevel(exercise?.level ?? 'Początkujący');
    selectedGoals.addAll(
      exercise?.typedTrainingGoals ?? const <TrainingGoal>{},
    );
    if (selectedGoals.isEmpty) {
      selectedGoals.addAll({
        TrainingGoal.strength,
        TrainingGoal.muscleGain,
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    category.dispose();
    primaryMuscle.dispose();
    supportingMuscles.dispose();
    equipment.dispose();
    description.dispose();
    tips.dispose();
    commonMistakes.dispose();
    avoidWhen.dispose();
    alternatives.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final original = widget.exercise;
    final supporting = _splitExerciseField(supportingMuscles.text);
    final primary = primaryMuscle.text.trim();
    final parsedTips = _splitExerciseField(tips.text);
    final parsedMistakes = _splitExerciseField(commonMistakes.text);
    final parsedAvoidWhen = _splitExerciseField(avoidWhen.text);
    final parsedAlternatives = _splitExerciseField(alternatives.text);
    final exerciseId = original?.id ?? 'custom_${idNow()}';
    // Etap 27: przypisz multimedia do tego ćwiczenia (spójne exerciseId).
    final savedMedia = mediaItems
        .map((media) => media.copyWith(exerciseId: exerciseId))
        .toList();
    final ex = Exercise(
      id: exerciseId,
      name: name.text.trim(),
      category: category.text.trim().isEmpty ? 'Inne' : category.text.trim(),
      muscles: [
        primary,
        ...supporting.where(
          (muscle) => muscle.toLowerCase() != primary.toLowerCase(),
        ),
      ],
      equipment: equipment.text.trim().isEmpty ? 'masa ciała' : equipment.text.trim(),
      level: level,
      illustrationType: original?.illustrationType ?? 'generic',
      description: description.text.trim().isEmpty ? 'Własne ćwiczenie użytkownika.' : description.text.trim(),
      tips: parsedTips.isEmpty
          ? const [
              'Zacznij od lekkiej wersji.',
              'Kontroluj ruch w całym zakresie.',
            ]
          : parsedTips,
      commonMistakes: parsedMistakes.isEmpty
          ? const [
              'Za szybkie tempo.',
              'Za duży ciężar.',
              'Brak kontroli zakresu.',
            ]
          : parsedMistakes,
      defaultSets: original?.defaultSets ?? 3,
      defaultReps: original?.defaultReps ?? 10,
      defaultDurationSec: original?.defaultDurationSec ?? 0,
      met: original?.met ?? 4.5,
      trainingGoals: selectedGoals.map((goal) => goal.label).toList(),
      avoidWhen: parsedAvoidWhen,
      alternatives: parsedAlternatives,
      executionSteps: original?.executionSteps ?? const [],
      breathing: original?.breathing ?? '',
      tempo: original?.tempo ?? '',
      easierVersion: original?.easierVersion ?? '',
      harderVersion: original?.harderVersion ?? '',
      imageUrl: original?.imageUrl,
      imagePath: original?.imagePath,
      thumbnailPath: original?.thumbnailPath,
      gifPath: original?.gifPath,
      animationAssetPath: original?.animationAssetPath,
      videoPath: original?.videoPath,
      videoUrl: original?.videoUrl,
      mediaItems: savedMedia,
      muscleImpacts: [
        for (final entry in _muscleRoles.entries)
          ExerciseMuscleImpact(muscleGroup: entry.key, role: entry.value),
      ],
      source: original == null
          ? 'custom'
          : original.source == 'local'
              ? 'edited'
              : original.source,
    );
    await widget.store.addCustomExercise(ex);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ===== Etap 27: zarządzanie multimediami w formularzu =====

  void _showMediaError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Dodaje nowe medium do listy roboczej. Pierwsze dodane staje się główne.
  void _appendMedia({
    String? localPath,
    String? remoteUrl,
    required MediaType type,
    String title = '',
  }) {
    var resolved = type;
    final lowerLocal = localPath?.toLowerCase() ?? '';
    // Drobne dostrojenie: jeśli „zdjęcie" jest faktycznie GIF-em, oznacz jako animację.
    if (resolved == MediaType.image && lowerLocal.endsWith('.gif')) {
      resolved = MediaType.gif;
    }
    final media = ExerciseMedia(
      id: 'media_${idNow()}_${mediaItems.length}',
      exerciseId: widget.exercise?.id ?? '',
      type: resolved,
      localPath: localPath,
      remoteUrl: remoteUrl,
      title: title,
      isPrimary: mediaItems.isEmpty,
      createdAt: DateTime.now(),
    );
    setState(() {
      mediaItems.add(media);
      _mediaExpanded = true;
    });
  }

  Future<void> _pickImageMedia({
    required ImageSource source,
    required MediaType type,
    required String title,
  }) async {
    try {
      final XFile? file = await _mediaPicker.pickImage(source: source, imageQuality: 85);
      if (file == null) return; // Użytkownik anulował wybór — nic nie robimy.
      _appendMedia(localPath: file.path, type: type, title: title);
    } catch (_) {
      _showMediaError('Nie udało się dodać medium. Sprawdź uprawnienia.');
    }
  }

  Future<void> _pickVideoMedia() async {
    try {
      final XFile? file = await _mediaPicker.pickVideo(source: ImageSource.gallery);
      if (file == null) return; // anulowano
      _appendMedia(localPath: file.path, type: MediaType.video, title: 'Wideo z galerii');
    } catch (_) {
      _showMediaError('Nie udało się dodać wideo. Sprawdź uprawnienia.');
    }
  }

  Future<void> _addVideoLink() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Link do wideo'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Adres URL',
              hintText: 'https://...',
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Podaj link do wideo.';
              if (!text.startsWith('http://') && !text.startsWith('https://')) {
                return 'Link musi zaczynać się od http(s).';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return; // anulowano / puste
    _appendMedia(remoteUrl: url, type: MediaType.url, title: 'Wideo (link)');
  }

  Future<void> _addAssetPlaceholder() async {
    final selected = await showModalBottomSheet<({String path, MediaType type, String title})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Wbudowane multimedia', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            for (final asset in kBuiltInExerciseMediaAssets)
              ListTile(
                leading: Icon(mediaTypeIcon(asset.type)),
                title: Text(asset.title),
                subtitle: Text(asset.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(sheetContext).pop(asset),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return; // anulowano
    _appendMedia(localPath: selected.path, type: selected.type, title: selected.title);
  }

  void _setPrimaryMedia(String id) {
    setState(() {
      mediaItems = [
        for (final media in mediaItems) media.copyWith(isPrimary: media.id == id),
      ];
    });
  }

  void _deleteMedia(String id) {
    setState(() {
      final removed = mediaItems.where((media) => media.id == id).toList();
      final wasPrimary = removed.isNotEmpty && removed.first.isPrimary;
      mediaItems.removeWhere((media) => media.id == id);
      // Jeśli usunęliśmy główne medium — wypromuj pierwsze z pozostałych.
      if (wasPrimary && mediaItems.isNotEmpty && !mediaItems.any((media) => media.isPrimary)) {
        mediaItems[0] = mediaItems[0].copyWith(isPrimary: true);
      }
    });
  }

  Future<void> _openAddMediaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget option(IconData icon, String label, Future<void> Function() action) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await action();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Dodaj multimedia', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
              option(Icons.photo_library_outlined, 'Zdjęcie z galerii',
                  () => _pickImageMedia(source: ImageSource.gallery, type: MediaType.image, title: 'Zdjęcie z galerii')),
              option(Icons.photo_camera_outlined, 'Zrób zdjęcie aparatem',
                  () => _pickImageMedia(source: ImageSource.camera, type: MediaType.image, title: 'Zdjęcie z aparatu')),
              option(Icons.gif_box_outlined, 'GIF z galerii',
                  () => _pickImageMedia(source: ImageSource.gallery, type: MediaType.gif, title: 'GIF z galerii')),
              option(Icons.movie_outlined, 'Wideo z galerii', _pickVideoMedia),
              option(Icons.link_rounded, 'Link do wideo', _addVideoLink),
              option(Icons.collections_bookmark_outlined, 'Asset / placeholder', _addAssetPlaceholder),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAddMuscleSheet() async {
    final available = BodyMuscle.values.where((m) => !_muscleRoles.containsKey(m)).toList();
    final picked = await showModalBottomSheet<BodyMuscle>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        List<BodyMuscle> onSide(BodyMuscleSide side) =>
            available.where((m) => musclesOnSide(side).contains(m)).toList();
        Widget group(String title, List<BodyMuscle> muscles) {
          if (muscles.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              for (final muscle in muscles)
                ListTile(
                  dense: true,
                  title: Text(muscle.label),
                  onTap: () => Navigator.of(sheetContext).pop(muscle),
                ),
            ],
          );
        }

        return FractionallySizedBox(
          heightFactor: 0.86,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Dodaj partię mięśniową', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              group('Przód', onSide(BodyMuscleSide.front)),
              group('Tył', onSide(BodyMuscleSide.back)),
              if (available.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Wszystkie partie już dodane.'))),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _muscleRoles[picked] = MuscleRole.primary;
        _musclesExpanded = true;
      });
    }
  }

  Widget _buildMuscleRow(ThemeData theme, BodyMuscle muscle, MuscleRole role) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(muscle.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          DropdownButton<MuscleRole>(
            value: role,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: (value) {
              if (value != null) setState(() => _muscleRoles[muscle] = value);
            },
            items: [
              for (final r in MuscleRole.values) DropdownMenuItem(value: r, child: Text(r.label)),
            ],
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Usuń',
            onPressed: () => setState(() => _muscleRoles.remove(muscle)),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMuscleSection(ThemeData theme) {
    final entries = _muscleRoles.entries.toList();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _musclesExpanded = !_musclesExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.accessibility_new_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Partie mięśniowe', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  if (entries.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text('${entries.length}', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  Icon(_musclesExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          if (_musclesExpanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (entries.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Brak przypisanych partii mięśniowych — ćwiczenie nie będzie liczone do regeneracji.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'Główna 1.0 · Pomocnicza 0.5 · Stabilizacja 0.25',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in entries) _buildMuscleRow(theme, entry.key, entry.value),
                  ],
                  const SizedBox(height: 6),
                  FilledButton.tonalIcon(
                    onPressed: _openAddMuscleSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Dodaj partię'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _mediaExpanded = !_mediaExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.perm_media_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Multimedia ćwiczenia',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (mediaItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${mediaItems.length}',
                        style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  Icon(_mediaExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          if (_mediaExpanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mediaItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Brak multimediów — dodaj zdjęcie, GIF albo wideo, aby ćwiczenie było czytelniejsze',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final media in mediaItems) _buildMediaTile(theme, media),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _openAddMediaSheet,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Dodaj medium'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaTile(ThemeData theme, ExerciseMedia media) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ExerciseMediaThumbnail(media: media, size: 52),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  media.title.isEmpty ? media.type.label : media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      media.type.label,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (media.isPrimary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Główne',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: media.isPrimary ? 'Główne medium' : 'Ustaw jako główne',
            onPressed: media.isPrimary ? null : () => _setPrimaryMedia(media.id),
            icon: Icon(
              media.isPrimary ? Icons.star_rounded : Icons.star_border_rounded,
              color: media.isPrimary ? theme.colorScheme.primary : null,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Usuń',
            onPressed: () => _deleteMedia(media.id),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.exercise != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Icon(
                      editing ? Icons.edit_rounded : Icons.add_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editing ? 'Edytuj ćwiczenie' : 'Dodaj własne ćwiczenie',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Dane zostaną zapisane lokalnie.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nazwa'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Podaj nazwę ćwiczenia.' : null,
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 620 ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: width,
                        child: TextFormField(
                          controller: primaryMuscle,
                          decoration: const InputDecoration(
                            labelText: 'Główna partia mięśniowa',
                          ),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Podaj główną partię.' : null,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: TextFormField(
                          controller: supportingMuscles,
                          decoration: const InputDecoration(
                            labelText: 'Partie pomocnicze',
                            hintText: 'np. triceps, barki',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: TextFormField(
                          controller: equipment,
                          decoration: const InputDecoration(labelText: 'Sprzęt'),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Podaj sprzęt lub „masa ciała”.' : null,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: DropdownButtonFormField<String>(
                          initialValue: level,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Poziom trudności',
                          ),
                          items: kTrainingLevels
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() => level = value ?? level),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: category,
                decoration: const InputDecoration(
                  labelText: 'Kategoria w bazie',
                  hintText: 'np. Nogi, Plecy, Kardio',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Cel treningowy',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TrainingGoal.values
                    .map(
                      (goal) => FilterChip(
                        label: Text(goal.label),
                        selected: selectedGoals.contains(goal),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedGoals.add(goal);
                            } else {
                              selectedGoals.remove(goal);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: description,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Opis techniki'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Dodaj krótki opis techniki.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: tips,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Wskazówki techniczne',
                  hintText: 'Każda wskazówka w nowej linii',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: commonMistakes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Najczęstsze błędy',
                  hintText: 'Każdy błąd w nowej linii',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: avoidWhen,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Kiedy unikać ćwiczenia',
                  hintText: 'Każda sytuacja w nowej linii',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: alternatives,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Alternatywy',
                  hintText: 'Każda alternatywa w nowej linii',
                ),
              ),
              const SizedBox(height: 14),
              _buildMuscleSection(theme),
              const SizedBox(height: 14),
              _buildMediaSection(theme),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: save,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  editing ? 'Zapisz zmiany' : 'Dodaj ćwiczenie',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> _splitExerciseField(String value) {
  return value.split(RegExp(r'[\n,;]+')).map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
}

Future<void> showAddWorkoutSheet(BuildContext context, {Exercise? exercise, WorkoutLog? existing, PlanItem? fromPlan}) async {
  final store = AppScope.read(context);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AddWorkoutSheetContent(store: store, exercise: exercise, existing: existing, fromPlan: fromPlan),
  );
}

class AddWorkoutSheetContent extends StatefulWidget {
  final AppStore store;
  final Exercise? exercise;
  final WorkoutLog? existing;
  final PlanItem? fromPlan;

  const AddWorkoutSheetContent({super.key, required this.store, this.exercise, this.existing, this.fromPlan});

  @override
  State<AddWorkoutSheetContent> createState() => _AddWorkoutSheetContentState();
}

class _AddWorkoutSheetContentState extends State<AddWorkoutSheetContent> {
  late Exercise selectedExercise;
  late final TextEditingController sets;
  late final TextEditingController reps;
  late final TextEditingController weight;
  late final TextEditingController duration;
  late final TextEditingController calories;
  late final TextEditingController note;
  late int rpe;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    selectedExercise = widget.exercise ?? widget.existing?.exerciseFrom(store.customExercises) ?? ExerciseRepo.all.first;
    sets = TextEditingController(text: '${widget.existing?.sets ?? widget.fromPlan?.sets ?? selectedExercise.defaultSets}');
    reps = TextEditingController(text: '${widget.existing?.reps ?? widget.fromPlan?.reps ?? selectedExercise.defaultReps}');
    weight = TextEditingController(text: (widget.existing?.weightKg ?? 0).toStringAsFixed(1));
    duration = TextEditingController(text: '${((widget.existing?.durationSec ?? widget.fromPlan?.durationSec ?? selectedExercise.defaultDurationSec) / 60).round()}');
    calories = TextEditingController(text: widget.existing?.calories.toStringAsFixed(0) ?? '');
    note = TextEditingController(text: widget.existing?.note ?? widget.fromPlan?.note ?? '');
    rpe = widget.existing?.rpe ?? 7;
  }

  @override
  void dispose() {
    sets.dispose();
    reps.dispose();
    weight.dispose();
    duration.dispose();
    calories.dispose();
    note.dispose();
    super.dispose();
  }

  void recalcCalories() {
    final minutes = double.tryParse(duration.text.replaceAll(',', '.')) ?? _estimateMinutes(selectedExercise, sets.text, reps.text);
    final kcal = estimateCalories(met: selectedExercise.met, weightKg: store.settings.bodyWeightKg, minutes: minutes);
    setState(() => calories.text = kcal.toStringAsFixed(0));
  }

  Future<void> save() async {
    final minutes = double.tryParse(duration.text.replaceAll(',', '.')) ?? _estimateMinutes(selectedExercise, sets.text, reps.text);
    final log = WorkoutLog(
      id: widget.existing?.id ?? idNow(),
      exerciseId: selectedExercise.id,
      date: store.selectedDate,
      sets: int.tryParse(sets.text) ?? selectedExercise.defaultSets,
      reps: int.tryParse(reps.text) ?? selectedExercise.defaultReps,
      weightKg: double.tryParse(weight.text.replaceAll(',', '.')) ?? 0,
      durationSec: (minutes * 60).round(),
      rpe: rpe,
      calories: double.tryParse(calories.text.replaceAll(',', '.')) ?? estimateCalories(met: selectedExercise.met, weightKg: store.settings.bodyWeightKg, minutes: minutes),
      note: note.text.trim(),
      aiConfidence: widget.existing?.aiConfidence ?? 0,
    );
    if (widget.existing == null) {
      await store.addLog(log);
    } else {
      await store.updateLog(log);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ExerciseRepo.combined(store.customExercises);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Dodaj ćwiczenie' : 'Edytuj ćwiczenie', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(width: 92, height: 92, child: ExerciseVisual(exercise: selectedExercise)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: exercises.any((e) => e.id == selectedExercise.id) ? selectedExercise.id : exercises.first.id,
                    decoration: const InputDecoration(labelText: 'Ćwiczenie'),
                    selectedItemBuilder: (context) => exercises.map((x) => Align(alignment: Alignment.centerLeft, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    items: exercises.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        selectedExercise = ExerciseRepo.byId(id, store.customExercises);
                        sets.text = '${selectedExercise.defaultSets}';
                        reps.text = '${selectedExercise.defaultReps}';
                        duration.text = '${(selectedExercise.defaultDurationSec / 60).round()}';
                      });
                      recalcCalories();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: sets, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Serie'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: reps, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Powt.'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ciężar kg'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Czas min'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: calories, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kalorie'))),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'RPE'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(value: rpe, isExpanded: true, items: List.generate(10, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('$v/10'))).toList(), onChanged: (v) => setState(() => rpe = v ?? rpe)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Notatka')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: recalcCalories, icon: const Icon(Icons.calculate), label: const Text('Przelicz kalorie lokalnie')),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save),
              label: Text(widget.existing == null ? 'Dodaj do dziennika' : 'Zapisz zmiany'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

double _estimateMinutes(Exercise e, String setsText, String repsText) {
  if (e.defaultDurationSec > 0) {
    final sets = int.tryParse(setsText) ?? e.defaultSets;
    return (sets * e.defaultDurationSec) / 60;
  }
  final sets = int.tryParse(setsText) ?? e.defaultSets;
  final reps = int.tryParse(repsText) ?? e.defaultReps;
  return math.max(3.0, sets * reps * 3 / 60 + sets * 1.25);
}

double estimateCalories({required double met, required double weightKg, required double minutes}) {
  return met * 3.5 * weightKg / 200 * minutes;
}

/// Duży podgląd multimediów ćwiczenia w ekranie szczegółów.
/// Pokazuje GIF/zdjęcie z bezpiecznym fallbackiem i znacznikiem typu mediów.
class _ExerciseMediaHero extends StatelessWidget {
  const _ExerciseMediaHero({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnimated = exercise.animatedMediaPath != null;
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: ExerciseMediaPreview(exercise: exercise, fit: BoxFit.contain, fallbackSize: 200),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isAnimated ? Icons.gif_box_outlined : Icons.image_outlined, size: 16, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 4),
                  Text(
                    isAnimated ? 'Animacja' : 'Zdjęcie',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crash-safe budowniczy multimediów ćwiczenia.
/// Obsługuje GIF/obraz lokalny (asset) i zdalny (URL), z bezpiecznym fallbackiem,
/// jeśli plik nie istnieje albo nie da się go wczytać.
///
/// Priorytet podglądu: animacja (GIF) > obraz statyczny (lokalny/zdalny) > fallback.
/// Etap 23: estetyczny placeholder ćwiczenia bez multimediów.
/// Zastępuje stare „patyczakowe" ilustracje czystą, themowaną grafiką
/// (gradient + ikona dobrana do partii/kategorii). Skaluje się do kontenera,
/// bez rozciągania ikony.
class ExercisePlaceholder extends StatelessWidget {
  const ExercisePlaceholder({super.key, required this.exercise, this.size});

  final Exercise exercise;
  final double? size;

  static IconData iconForExercise(Exercise exercise) {
    final text = '${exercise.category} ${exercise.muscles.join(' ')} ${exercise.illustrationType} ${exercise.name}'.toLowerCase();
    bool has(List<String> keys) => keys.any(text.contains);
    if (has(['bieg', 'run', 'cardio', 'skip', 'interwa', 'hiit'])) return Icons.directions_run_rounded;
    if (has(['rower', 'bike', 'cykl'])) return Icons.directions_bike_rounded;
    if (has(['brzuch', 'core', 'plank', 'deska', 'abs'])) return Icons.self_improvement_rounded;
    if (has(['plec', 'back', 'pull', 'wiosł', 'podciąg', 'row'])) return Icons.rowing_rounded;
    if (has(['bark', 'shoulder', 'arnold', 'ohp'])) return Icons.accessibility_new_rounded;
    if (has(['noga', 'nogi', 'leg', 'przysiad', 'squat', 'wykrok', 'lunge', 'udo', 'łyd', 'lyd', 'pośladk', 'posladk'])) return Icons.sports_gymnastics_rounded;
    if (has(['biceps', 'triceps', 'rami', 'arm', 'uginan', 'curl'])) return Icons.sports_mma_rounded;
    if (has(['rozcią', 'rozciag', 'mobil', 'stretch', 'joga', 'yoga']) ) return Icons.spa_rounded;
    return Icons.fitness_center_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final icon = iconForExercise(exercise);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh]
              : [scheme.primaryContainer.withValues(alpha: 0.55), scheme.surfaceContainerHighest],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Ikona ~42% mniejszego wymiaru, ograniczona do rozsądnego zakresu.
          final base = math.min(
            constraints.hasBoundedWidth ? constraints.maxWidth : (size ?? 96),
            constraints.hasBoundedHeight ? constraints.maxHeight : (size ?? 96),
          );
          final iconSize = (base * 0.42).clamp(16.0, 120.0);
          return Center(
            child: Icon(icon, size: iconSize, color: scheme.primary.withValues(alpha: isDark ? 0.85 : 0.7)),
          );
        },
      ),
    );
  }
}

/// Neutralny stan ładowania medium (sieciowego) — spójny z motywem. Etap 32.
class _MediaLoadingBox extends StatelessWidget {
  const _MediaLoadingBox();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
      ),
    );
  }
}

/// Crash-safe budowniczy obrazu/GIF-a z dowolnego źródła:
/// * URL (`http`/`https`) → [Image.network] (ze stanem ładowania i błędu),
/// * asset (`assets/...`) → [Image.asset],
/// * ścieżka pliku z dysku (np. z galerii/aparatu) → [Image.file].
///
/// Każdy wariant ma `errorBuilder`, więc brak pliku / błędna ścieżka / usunięty plik /
/// pusty URL / brak uprawnień nie crashują aplikacji — pokazywany jest [fallback].
/// [loading] to stan ładowania dla zasobów sieciowych (domyślnie spinner).
/// [cacheWidth] ogranicza rozmiar dekodowanej bitmapy (cache miniatur → mniej pamięci).
/// Etap 27, rozszerzone w etapie 32.
Widget buildExerciseMediaImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  required Widget fallback,
  Widget? loading,
  int? cacheWidth,
}) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return fallback;
  final lower = trimmed.toLowerCase();
  final loadingWidget = loading ?? const _MediaLoadingBox();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return Image.network(
      trimmed,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (context, child, progress) => progress == null ? child : loadingWidget,
    );
  }
  if (trimmed.startsWith('assets/')) {
    return Image.asset(
      trimmed,
      fit: fit,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
  // Plik lokalny (galeria/aparat). Na web brak dart:io → fallback.
  if (kIsWeb) return fallback;
  return Image.file(
    File(trimmed),
    fit: fit,
    gaplessPlayback: true,
    cacheWidth: cacheWidth,
    errorBuilder: (_, __, ___) => fallback,
  );
}

class ExerciseMediaPreview extends StatelessWidget {
  const ExerciseMediaPreview({
    super.key,
    required this.exercise,
    this.fit = BoxFit.cover,
    this.fallbackSize,
  });

  final Exercise exercise;
  final BoxFit fit;
  final double? fallbackSize;

  Widget _fallback() => ExercisePlaceholder(exercise: exercise, size: fallbackSize);

  @override
  Widget build(BuildContext context) {
    // Najpierw animacja (GIF), potem obraz statyczny.
    final animated = exercise.animatedMediaPath;
    final staticPath = exercise.staticMediaPath;
    final path = animated ?? staticPath;
    if (path == null) return _fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: buildExerciseMediaImage(path, fit: fit, fallback: _fallback()),
    );
  }
}

/// Miniatura pojedynczego medium ([ExerciseMedia]) — używana na liście w formularzu
/// i w poziomej galerii w szczegółach ćwiczenia. Crash-safe; dla wideo/linku
/// pokazuje kafelek z ikoną odtwarzania (odtwarzacz pojawi się w kolejnym etapie).
class ExerciseMediaThumbnail extends StatelessWidget {
  const ExerciseMediaThumbnail({
    super.key,
    required this.media,
    this.size = 64,
    this.borderRadius = 14,
  });

  final ExerciseMedia media;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final iconTile = _iconTile(theme);
    // Cache miniatur: dekoduj bitmapę najwyżej do ~3× rozmiaru kafelka (mniej pamięci).
    final cacheWidth = (size * 3).round();

    Widget content;
    if (media.type.isVideo) {
      // Wideo/link: nie da się renderować jako obraz — tło z miniatury (jeśli jest)
      // + nakładka z ikoną play. `effectivePath` to plik/URL wideo, więc go nie używamy.
      final explicitThumb = media.thumbnailPath?.trim();
      final hasThumb = explicitThumb != null && explicitThumb.isNotEmpty;
      content = Stack(
        fit: StackFit.expand,
        children: [
          if (hasThumb)
            buildExerciseMediaImage(explicitThumb, fallback: iconTile, cacheWidth: cacheWidth)
          else
            iconTile,
          Container(
            color: Colors.black.withValues(alpha: 0.28),
            alignment: Alignment.center,
            child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
          ),
        ],
      );
    } else {
      final thumb = media.thumbnail;
      content = thumb != null
          ? buildExerciseMediaImage(thumb, fallback: iconTile, cacheWidth: cacheWidth)
          : iconTile;
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }

  Widget _iconTile(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        mediaTypeIcon(media.type),
        color: theme.colorScheme.primary,
        size: size * 0.42,
      ),
    );
  }
}

/// Wbudowane wideo instruktażowe do wyboru w formularzu ćwiczenia (Etap 33).
/// Pozwala przypisać dowolny dołączony klip do nowo dodanego ćwiczenia.
const List<({String path, MediaType type, String title})> kBuiltInExerciseMediaAssets = [
  (path: 'assets/exercises/videos/bench_press.mp4', type: MediaType.video, title: 'Wyciskanie sztangi leżąc'),
  (path: 'assets/exercises/videos/bicep_curl.mp4', type: MediaType.video, title: 'Uginanie ramion (biceps)'),
  (path: 'assets/exercises/videos/bulgarian_split_squat.mp4', type: MediaType.video, title: 'Przysiad bułgarski'),
  (path: 'assets/exercises/videos/crunch.mp4', type: MediaType.video, title: 'Brzuszki klasyczne'),
  (path: 'assets/exercises/videos/deadlift.mp4', type: MediaType.video, title: 'Martwy ciąg ze sztangą'),
  (path: 'assets/exercises/videos/deadlift_alt.mp4', type: MediaType.video, title: 'Martwy ciąg (ujęcie 2)'),
  (path: 'assets/exercises/videos/hip_thrust.mp4', type: MediaType.video, title: 'Hip thrust ze sztangą'),
  (path: 'assets/exercises/videos/lat_pulldown.mp4', type: MediaType.video, title: 'Ściąganie drążka'),
  (path: 'assets/exercises/videos/lateral_raise.mp4', type: MediaType.video, title: 'Unoszenie bokiem hantlami'),
  (path: 'assets/exercises/videos/leg_raise.mp4', type: MediaType.video, title: 'Unoszenie nóg leżąc'),
  (path: 'assets/exercises/videos/lunge.mp4', type: MediaType.video, title: 'Wykroki z hantlami'),
  (path: 'assets/exercises/videos/mountain_climber.mp4', type: MediaType.video, title: 'Wspinaczka górska'),
  (path: 'assets/exercises/videos/nozyce.mp4', type: MediaType.video, title: 'Nożyce (brzuch)'),
  (path: 'assets/exercises/videos/pushup.mp4', type: MediaType.video, title: 'Pompki klasyczne'),
  (path: 'assets/exercises/videos/row.mp4', type: MediaType.video, title: 'Wiosłowanie sztangą'),
  (path: 'assets/exercises/videos/row_dumbbell.mp4', type: MediaType.video, title: 'Wiosłowanie hantlą'),
  (path: 'assets/exercises/videos/rowerki.mp4', type: MediaType.video, title: 'Rowerki / twist brzucha'),
  (path: 'assets/exercises/videos/rozpietki.mp4', type: MediaType.video, title: 'Rozpiętki hantlami'),
  (path: 'assets/exercises/videos/russian_twist.mp4', type: MediaType.video, title: 'Ruskie skręty z hantlem'),
  (path: 'assets/exercises/videos/shoulder_press.mp4', type: MediaType.video, title: 'Wyciskanie hantli (barki)'),
  (path: 'assets/exercises/videos/shoulder_press_alt.mp4', type: MediaType.video, title: 'Wyciskanie hantli (ujęcie 2)'),
  (path: 'assets/exercises/videos/triceps_extension.mp4', type: MediaType.video, title: 'Prostowanie ramion (triceps)'),
];

/// Ikona dobrana do typu medium.
IconData mediaTypeIcon(MediaType type) {
  switch (type) {
    case MediaType.image:
      return Icons.image_outlined;
    case MediaType.gif:
      return Icons.gif_box_outlined;
    case MediaType.video:
      return Icons.movie_outlined;
    case MediaType.url:
      return Icons.link_rounded;
    case MediaType.asset:
      return Icons.collections_bookmark_outlined;
    case MediaType.none:
      return Icons.image_not_supported_outlined;
  }
}

/// Pełnoekranowy podgląd pojedynczego medium. Dla obrazów/GIF-ów pokazuje
/// powiększalny obraz; dla wideo/linku pokazuje informację i link (player w kolejnym etapie).
Future<void> showExerciseMediaPreviewDialog(BuildContext context, ExerciseMedia media) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final path = media.effectivePath;
      Widget body;
      if (media.type.isVideo) {
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mediaTypeIcon(media.type), size: 64, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              media.title.isEmpty ? media.type.label : media.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                path ?? 'Brak źródła wideo.',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Odtwarzacz wideo pojawi się w kolejnym etapie.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        );
      } else if (path != null) {
        body = InteractiveViewer(
          maxScale: 4,
          child: buildExerciseMediaImage(
            path,
            fit: BoxFit.contain,
            fallback: const Icon(Icons.broken_image_outlined, size: 64, color: Colors.white70),
          ),
        );
      } else {
        body = const Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.white70);
      }
      return Stack(
        children: [
          Center(child: body),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
                tooltip: 'Zamknij',
              ),
            ),
          ),
          if (media.title.isNotEmpty && !media.type.isVideo)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Text(
                  media.title,
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Galeria multimediów ćwiczenia: główne medium na górze, pozostałe w poziomej liście.
/// Pokazywana w szczegółach ćwiczenia, gdy ćwiczenie ma [Exercise.mediaItems]. Etap 27.
class ExerciseMediaGallery extends StatelessWidget {
  const ExerciseMediaGallery({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = exercise.mediaItems.where((media) => media.hasContent).toList();
    if (items.isEmpty) {
      // Brak listy mediów — pokaż klasyczny hero (ścieżki imagePath/gifPath itd.).
      return _ExerciseMediaHero(exercise: exercise);
    }
    final primary = exercise.primaryMedia ?? items.first;
    final others = items.where((media) => media.id != primary.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Główne medium na górze.
        GestureDetector(
          onTap: () => showExerciseMediaPreviewDialog(context, primary),
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: primary.type.isVideo
                      ? ExerciseMediaThumbnail(media: primary, size: 224, borderRadius: 18)
                      : buildExerciseMediaImage(
                          primary.effectivePath ?? '',
                          fit: BoxFit.contain,
                          fallback: ExercisePlaceholder(exercise: exercise, size: 200),
                        ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _MediaTypeBadge(type: primary.type),
                ),
              ],
            ),
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final media = others[index];
                return GestureDetector(
                  onTap: () => showExerciseMediaPreviewDialog(context, media),
                  child: ExerciseMediaThumbnail(media: media, size: 76),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _MediaTypeBadge extends StatelessWidget {
  const _MediaTypeBadge({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mediaTypeIcon(type), size: 16, color: theme.colorScheme.onPrimary),
          const SizedBox(width: 4),
          Text(
            type.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

class ExerciseVisual extends StatelessWidget {
  final Exercise exercise;

  const ExerciseVisual({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    // Obsługa GIF / obrazu lokalnego / zdalnego z bezpiecznym fallbackiem.
    if (exercise.hasMedia) {
      return ExerciseMediaPreview(exercise: exercise);
    }
    return ExercisePlaceholder(exercise: exercise);
  }
}

class ExerciseHeroVisual extends StatelessWidget {
  final Exercise exercise;

  const ExerciseHeroVisual({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(colors: [theme.colorScheme.primaryContainer, theme.colorScheme.surfaceContainerHighest]),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: exercise.hasMedia
                  ? ExerciseMediaPreview(exercise: exercise, fit: BoxFit.contain, fallbackSize: 230)
                  : Center(child: ExercisePlaceholder(exercise: exercise, size: 230)),
            ),
          ),
          // Znacznik animacji, gdy ćwiczenie ma GIF.
          if (exercise.animatedMediaPath != null)
            Positioned(
              right: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gif_box_outlined, size: 16, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 4),
                    Text('Animacja', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary)),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 16,
            right: 16,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [MiniTag(text: exercise.category), MiniTag(text: normalizeLevel(exercise.level)), MiniTag(text: exercise.equipment)],
            ),
          ),
        ],
      ),
    );
  }
}

class HumanExerciseImage extends StatelessWidget {
  final String type;
  final double? size;
  final Color? lineColor;
  final Color? backgroundColor;

  const HumanExerciseImage({super.key, required this.type, this.size, this.lineColor, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return HumanExerciseFrame(
      type: type,
      size: size,
      progress: 0.55,
      lineColor: lineColor,
      backgroundColor: backgroundColor,
    );
  }
}

class HumanExerciseFrame extends StatelessWidget {
  final String type;
  final double progress;
  final double? size;
  final Color? lineColor;
  final Color? backgroundColor;

  const HumanExerciseFrame({super.key, required this.type, required this.progress, this.size, this.lineColor, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = CustomPaint(
      painter: HumanExercisePainter(
        type: type,
        progress: progress.clamp(0.0, 1.0),
        bodyColor: lineColor ?? theme.colorScheme.primary,
        backgroundColor: backgroundColor ?? theme.colorScheme.primaryContainer.withOpacity(0.45),
        accentColor: theme.colorScheme.tertiary,
      ),
      child: const SizedBox.expand(),
    );
    if (size != null) return SizedBox(width: size, height: size, child: child);
    return child;
  }
}

class HumanExercisePainter extends CustomPainter {
  final String type;
  final double progress;
  final Color bodyColor;
  final Color backgroundColor;
  final Color accentColor;

  HumanExercisePainter({required this.type, required this.progress, required this.bodyColor, required this.backgroundColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final offset = Offset((size.width - s) / 2, (size.height - s) / 2);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)), Paint()..color = backgroundColor);

    final floor = Paint()
      ..color = bodyColor.withOpacity(0.18)
      ..strokeWidth = s * 0.018
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * .15, s * .88), Offset(s * .88, s * .88), floor);

    Offset o(double x, double y) => Offset(x * s, y * s);
    void limb(Offset a, Offset b, {double w = 0.075, Color? color}) {
      final p = Paint()
        ..color = color ?? bodyColor
        ..strokeWidth = s * w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(a, b, p);
    }

    void torso(Offset neck, Offset hip) {
      final p = Paint()..color = bodyColor;
      final rect = Rect.fromCenter(center: Offset((neck.dx + hip.dx) / 2, (neck.dy + hip.dy) / 2), width: s * 0.16, height: (hip - neck).distance + s * 0.10);
      canvas.save();
      final angle = math.atan2(hip.dy - neck.dy, hip.dx - neck.dx) - math.pi / 2;
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(angle);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height), Radius.circular(s * 0.08)), p);
      canvas.restore();
    }

    void head(Offset c) {
      canvas.drawCircle(c, s * .07, Paint()..color = bodyColor);
      canvas.drawCircle(c.translate(s * .025, -s * .012), s * .012, Paint()..color = Colors.white.withOpacity(0.75));
    }

    void dumbbell(Offset c) {
      final p = Paint()
        ..color = accentColor
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c.translate(-s * .05, 0), c.translate(s * .05, 0), p);
      canvas.drawCircle(c.translate(-s * .065, 0), s * .025, Paint()..color = accentColor);
      canvas.drawCircle(c.translate(s * .065, 0), s * .025, Paint()..color = accentColor);
    }

    final t = progress;
    late Offset h, n, hip, ls, rs, le, re, lh, rh, lk, rk, lf, rf;
    bool bar = false;
    bool db = false;
    bool bike = false;

    final lower = type.toLowerCase();
    if (lower.contains('pushup') || lower.contains('plank') || lower.contains('mountain')) {
      final down = lower.contains('pushup') ? t * .14 : 0.0;
      h = o(.22, .45 + down);
      n = o(.30, .49 + down);
      hip = o(.68, .57 + (lower.contains('mountain') ? 0 : down * .6));
      ls = o(.38, .50 + down);
      rs = o(.42, .53 + down);
      le = o(.33, .74);
      re = o(.45, .74);
      lh = o(.28, .82);
      rh = o(.50, .82);
      lk = lower.contains('mountain') ? o(.55 + .18 * t, .78) : o(.78, .78);
      rk = lower.contains('mountain') ? o(.86 - .22 * t, .80) : o(.86, .80);
      lf = o(.60 + .18 * t, .84);
      rf = o(.90 - .18 * t, .84);
    } else if (lower.contains('lunge')) {
      final down = t * .10;
      h = o(.50, .23 + down);
      n = o(.50, .34 + down);
      hip = o(.50, .56 + down);
      ls = o(.43, .38 + down);
      rs = o(.57, .38 + down);
      le = o(.34, .50 + down);
      re = o(.66, .50 + down);
      lh = o(.30, .60 + down);
      rh = o(.70, .60 + down);
      lk = o(.34, .70 + down);
      rk = o(.70, .70);
      lf = o(.24, .88);
      rf = o(.84, .88);
    } else if (lower.contains('deadlift') || lower.contains('row')) {
      final bend = .18 + t * .16;
      h = o(.45 + bend, .25 + bend * .5);
      n = o(.50 + bend, .36 + bend * .3);
      hip = o(.56 + bend, .58);
      ls = o(.48 + bend, .40);
      rs = o(.60 + bend, .43);
      le = o(.34 + t * .08, .62);
      re = o(.74 - t * .08, .62);
      lh = o(.28 + t * .12, .76);
      rh = o(.80 - t * .12, .76);
      lk = o(.44, .72);
      rk = o(.68, .72);
      lf = o(.38, .88);
      rf = o(.74, .88);
      db = true;
    } else if (lower.contains('pull')) {
      h = o(.50, .38 - t * .13);
      n = o(.50, .48 - t * .12);
      hip = o(.50, .68 - t * .08);
      ls = o(.42, .48 - t * .12);
      rs = o(.58, .48 - t * .12);
      le = o(.35, .28 + t * .03);
      re = o(.65, .28 + t * .03);
      lh = o(.30, .16);
      rh = o(.70, .16);
      lk = o(.44, .80 - t * .05);
      rk = o(.58, .80 - t * .05);
      lf = o(.40, .88);
      rf = o(.62, .88);
      bar = true;
    } else if (lower.contains('bench')) {
      h = o(.30, .62);
      n = o(.38, .64);
      hip = o(.66, .66);
      ls = o(.45, .62);
      rs = o(.57, .62);
      le = o(.42, .48 - t * .18);
      re = o(.64, .48 - t * .18);
      lh = o(.34, .43 - t * .18);
      rh = o(.72, .43 - t * .18);
      lk = o(.75, .72);
      rk = o(.84, .76);
      lf = o(.74, .88);
      rf = o(.88, .88);
      bar = true;
      canvas.drawLine(
          o(.18, .76),
          o(.86, .76),
          Paint()
            ..color = bodyColor.withOpacity(.25)
            ..strokeWidth = s * .035
            ..strokeCap = StrokeCap.round);
    } else if (lower.contains('bike')) {
      bike = true;
      h = o(.52, .30);
      n = o(.51, .39);
      hip = o(.50, .57);
      ls = o(.47, .42);
      rs = o(.56, .42);
      le = o(.58, .48);
      re = o(.64, .50);
      lh = o(.66, .50);
      rh = o(.72, .50);
      lk = o(.44, .73);
      rk = o(.63, .70);
      lf = o(.35, .76);
      rf = o(.68, .76);
    } else if (lower.contains('run') || lower.contains('highknees')) {
      h = o(.50, .22);
      n = o(.50, .32);
      hip = o(.50, .57);
      ls = o(.43, .38);
      rs = o(.57, .38);
      le = o(.36 + .12 * t, .50);
      re = o(.64 - .12 * t, .50);
      lh = o(.30 + .12 * t, .63);
      rh = o(.70 - .12 * t, .63);
      lk = o(.36 + .18 * t, .72 - .18 * t);
      rk = o(.66 - .18 * t, .72 + .05 * t);
      lf = o(.30, .88);
      rf = o(.74 - .16 * t, .88);
    } else if (lower.contains('squat')) {
      final down = t;
      h = o(.50, .24 + down * .08);
      n = o(.50, .34 + down * .08);
      hip = o(.50, .55 + down * .14);
      ls = o(.43, .40 + down * .05);
      rs = o(.57, .40 + down * .05);
      le = o(.34, .50 + down * .04);
      re = o(.66, .50 + down * .04);
      lh = o(.28, .58 + down * .04);
      rh = o(.72, .58 + down * .04);
      lk = o(.36, .70 + down * .02);
      rk = o(.64, .70 + down * .02);
      lf = o(.28, .88);
      rf = o(.72, .88);
    } else {
      final move = (t - .5) * .10;
      h = o(.50, .23);
      n = o(.50, .34);
      hip = o(.50, .58);
      ls = o(.42, .40);
      rs = o(.58, .40);
      le = o(.34 + move, .54 - t * .10);
      re = o(.66 - move, .54 - t * .10);
      lh = o(.30 + move, .68 - t * .14);
      rh = o(.70 - move, .68 - t * .14);
      lk = o(.42 + move, .75);
      rk = o(.58 - move, .75);
      lf = o(.36 + move, .88);
      rf = o(.64 - move, .88);
      db = lower.contains('curl') || lower.contains('raise') || lower.contains('press');
    }

    if (bike) {
      final wheel = Paint()
        ..color = bodyColor.withOpacity(.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .035;
      canvas.drawCircle(o(.32, .77), s * .13, wheel);
      canvas.drawCircle(o(.72, .77), s * .13, wheel);
      limb(o(.32, .77), o(.50, .57), w: .035, color: bodyColor.withOpacity(.45));
      limb(o(.50, .57), o(.72, .77), w: .035, color: bodyColor.withOpacity(.45));
      limb(o(.44, .50), o(.62, .50), w: .035, color: bodyColor.withOpacity(.45));
    }
    if (bar) limb(o(.22, .16), o(.78, .16), w: .035, color: accentColor);

    limb(ls, le);
    limb(le, lh);
    limb(rs, re);
    limb(re, rh);
    limb(hip, lk);
    limb(lk, lf);
    limb(hip, rk);
    limb(rk, rf);
    torso(n, hip);
    head(h);
    if (db) {
      dumbbell(lh);
      dumbbell(rh);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HumanExercisePainter oldDelegate) => oldDelegate.type != type || oldDelegate.progress != progress || oldDelegate.bodyColor != bodyColor || oldDelegate.backgroundColor != backgroundColor || oldDelegate.accentColor != accentColor;
}

// ============================================================
// Etap 18: Widget sugestii progresji
// ============================================================

class ProgressionSuggestionCard extends StatelessWidget {
  const ProgressionSuggestionCard({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    required this.logs,
    required this.plannedReps,
    required this.plannedWeightKg,
    this.planId,
    this.weekday,
    this.onApplied,
  });

  final String exerciseId;
  final String exerciseName;
  final List<WorkoutLog> logs;
  final int plannedReps;
  final double plannedWeightKg;
  final String? planId;
  final int? weekday;
  final VoidCallback? onApplied;

  Color _actionColor(ProgressionAction action, ColorScheme scheme) {
    switch (action) {
      case ProgressionAction.increaseWeight:
      case ProgressionAction.increaseReps:
        return Colors.green;
      case ProgressionAction.maintain:
        return scheme.primary;
      case ProgressionAction.decreaseWeight:
        return Colors.orange;
      case ProgressionAction.deload:
        return Colors.deepOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = progressionSuggestionForExercise(
      exerciseId: exerciseId,
      allLogs: logs,
      plannedReps: plannedReps,
      plannedWeightKg: plannedWeightKg,
    );
    if (suggestion == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _actionColor(suggestion.action, scheme);
    final store = AppScope.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(suggestion.icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion.label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(suggestion.reason, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
            if (suggestion.hasNewValues && planId != null && weekday != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sugerowany ciężar', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(
                          suggestion.suggestedWeightKg > 0
                              ? '${_formatPlanWeight(suggestion.suggestedWeightKg)} kg'
                              : 'bez ciężaru',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sugerowane powtórzenia', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text('${suggestion.suggestedReps}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Zastosować sugestię dla „$exerciseName"?'),
                      content: Text(
                        'Ciężar w planie zmieni się z ${_formatPlanWeight(suggestion.currentWeightKg)} kg'
                        ' na ${_formatPlanWeight(suggestion.suggestedWeightKg)} kg'
                        ', powtórzenia: ${suggestion.currentReps} → ${suggestion.suggestedReps}.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zastosuj')),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  // Zachowaj istniejące dane planu, zmień tylko ciężar i powtórzenia
                  final activePlan = store.activeWorkoutPlan;
                  final existingItem = activePlan?.days
                      .where((d) => d.weekday == weekday)
                      .expand((d) => d.items)
                      .where((it) => it.exerciseId == exerciseId)
                      .firstOrNull;
                  await store.upsertPlanItem(
                    planId: planId!,
                    weekday: weekday!,
                    item: PlanItem(
                      exerciseId: exerciseId,
                      sets: existingItem?.sets ?? 3,
                      reps: suggestion.suggestedReps,
                      durationSec: existingItem?.durationSec ?? 0,
                      note: existingItem?.note ?? '',
                      suggestedWeightKg: suggestion.suggestedWeightKg,
                      restSeconds: existingItem?.restSeconds ?? 90,
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Zaktualizowano „$exerciseName" w planie.')),
                    );
                    onApplied?.call();
                  }
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Zastosuj sugestię'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Etap 16: AI Trainer — czat
// ============================================================

const List<String> _kQuickQuestions = [
  'Co trenować dzisiaj?',
  'Czy zwiększyć ciężar?',
  'Czy potrzebuję odpoczynku?',
  'Jak poprawić technikę?',
  'Co zrobić, gdy nie mam siły?',
];

class AiTrainerPage extends StatefulWidget {
  const AiTrainerPage({super.key});

  @override
  State<AiTrainerPage> createState() => _AiTrainerPageState();
}

class _AiTrainerPageState extends State<AiTrainerPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(String text) {
    final store = AppScope.of(context);
    final trimmed = text.trim();
    if (trimmed.isEmpty || store.aiChatBusy) return;
    _controller.clear();
    store.chatWithAi(trimmed);
    Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.smart_toy_rounded, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Trainer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Asystent treningowy — zadaj pytanie', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (store.aiChatHistory.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Wyczyść historię',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Wyczyścić historię?'),
                        content: const Text('Wszystkie wiadomości zostaną usunięte.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyczyść')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) AppScope.of(context).clearAiChatHistory();
                  },
                ),
            ],
          ),
        ),

        // Disclaimer
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withOpacity(.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI nie zastępuje lekarza ani fizjoterapeuty. W razie bólu lub kontuzji skonsultuj się ze specjalistą.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),

        // Quick questions
        if (store.aiChatHistory.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Szybkie pytania', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kQuickQuestions
                      .map(
                        (q) => ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 12)),
                          onPressed: store.aiChatBusy ? null : () => _send(q),
                          avatar: const Icon(Icons.flash_on_rounded, size: 14),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),

        // Messages
        Expanded(
          child: store.aiChatHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 48, color: scheme.onSurfaceVariant.withOpacity(.4)),
                      const SizedBox(height: 12),
                      Text('Zadaj pierwsze pytanie', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: store.aiChatHistory.length + (store.aiChatBusy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == store.aiChatHistory.length && store.aiChatBusy) {
                      return const _TypingIndicator();
                    }
                    final msg = store.aiChatHistory[i];
                    return _ChatBubble(message: msg, isDark: isDark);
                  },
                ),
        ),

        // Quick questions (when history not empty — smaller strip)
        if (store.aiChatHistory.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: _kQuickQuestions
                  .map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(q, style: const TextStyle(fontSize: 11)),
                        onPressed: store.aiChatBusy ? null : () => _send(q),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

        // Input
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !store.aiChatBusy,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Napisz pytanie do trenera AI…',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      suffixIcon: store.aiChatBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: store.aiChatBusy ? null : () => _send(_controller.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isDark});

  final AiChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final isError = message.role == 'error';

    final bubbleColor = isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : isDark
                ? const Color(0xFF1E2A22)
                : scheme.surfaceContainerHighest;

    final textColor = isError
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isError ? scheme.errorContainer : scheme.primaryContainer,
              foregroundColor: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
              child: Icon(isError ? Icons.warning_rounded : Icons.smart_toy_rounded, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(message.content, style: TextStyle(color: textColor, fontSize: 14, height: 1.45)),
            ),
          ),
          if (isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.smart_toy_rounded, size: 14),
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) {
                        final phase = (_ctrl.value + i * 0.3) % 1.0;
                        final size = 6.0 + 3.0 * math.sin(phase * math.pi);
                        return SizedBox(
                          width: size,
                          height: size,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant.withOpacity(.7),
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
