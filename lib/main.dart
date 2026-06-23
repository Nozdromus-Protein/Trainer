import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'features/trainer/application/exercise_library_filter.dart';
import 'features/trainer/application/workout_plan_factory.dart';
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
  AppStore({TrainerLocalRepository? trainerRepository}) : _trainerRepository = trainerRepository ?? TrainerLocalRepository();

  final TrainerLocalRepository _trainerRepository;
  final List<WorkoutLog> logs = [];
  final List<WorkoutPlan> plans = [];
  final List<Exercise> customExercises = [];
  ExerciseLibraryPreferences exerciseLibraryPreferences = const ExerciseLibraryPreferences();
  ActiveWorkoutSession? activeWorkoutSession;
  AppSettings settings = AppSettings.defaults();
  DateTime selectedDate = DateTime.now();
  String? lastAiMessage;
  bool aiBusy = false;

  static const _settingsKey = 'workout_settings_v1';

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

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> saveCustomExercises() async {
    await _trainerRepository.saveCustomExercises(customExercises);
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

  Future<bool> startActiveWorkout({
    required WorkoutPlan plan,
    required WorkoutDay day,
  }) async {
    if (day.items.isEmpty) return false;
    activeWorkoutSession = ActiveWorkoutSession(
      id: 'workout_${idNow()}',
      planId: plan.id,
      planName: plan.name,
      weekday: day.weekday,
      dayTitle: day.title,
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
    exercises[index] = exercise.copyWith(
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
    activeWorkoutSession = session.copyWith(exercises: exercises);
    await saveActiveWorkoutSession();
    notifyListeners();
    return true;
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
        ),
      );
    }

    logs.removeWhere((log) => log.sessionId == session.id);
    logs.insertAll(0, completedLogs);
    await saveLogs();
    final summary = CompletedWorkoutSummary(
      sessionId: session.id,
      name: sessionName,
      startedAt: session.startedAt,
      endedAt: endedAt,
      exerciseCount: session.completedExerciseCount,
      setCount: session.completedSetCount,
      volume: session.volume,
      averageRpe: session.averageRpe,
    );
    activeWorkoutSession = null;
    await saveActiveWorkoutSession();
    notifyListeners();
    return summary;
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
  ].map(_withLibraryMetadata).toList(growable: false);

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

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  void openStandalonePage(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            title: const Text(kAppName),
          ),
          body: SafeArea(child: page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TrainerHomePage(
        onToday: () => openStandalonePage(const TodayPage()),
        onExercises: () => setState(() => index = 1),
        onHistory: () => openStandalonePage(const HistoryPage()),
        onPlans: () => setState(() => index = 2),
        onProgress: () => setState(() => index = 3),
        onSettings: () => setState(() => index = 4),
      ),
      const ExercisesPage(),
      const PlanPage(),
      const ProgressPage(),
      const MorePage(),
    ];
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Start'),
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Ćwiczenia'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Plan'),
            NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Postęp'),
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
    final tiles = [
      TrainerHomeTileData(
        title: 'Dzisiejszy trening',
        subtitle: todayPlan == null ? 'Brak treningu w planie na dziś' : '${todayPlan.title} · ${todayPlan.items.length} ćwiczeń',
        icon: Icons.today_rounded,
        onTap: onToday,
      ),
      TrainerHomeTileData(
        title: 'Baza ćwiczeń',
        subtitle: '${ExerciseRepo.combined(store.customExercises).length} ćwiczeń dostępnych lokalnie',
        icon: Icons.fitness_center_rounded,
        onTap: onExercises,
      ),
      TrainerHomeTileData(
        title: 'Historia',
        subtitle: '${store.logs.length} zapisanych wpisów treningowych',
        icon: Icons.history_rounded,
        onTap: onHistory,
      ),
      TrainerHomeTileData(
        title: 'Plany treningowe',
        subtitle: '${store.plans.length} ${store.plans.length == 1 ? 'aktywny plan' : 'zapisanych planów'}',
        icon: Icons.calendar_month_rounded,
        onTap: onPlans,
      ),
      TrainerHomeTileData(
        title: 'Progres',
        subtitle: 'Podsumowanie zapisanych treningów',
        icon: Icons.trending_up_rounded,
        onTap: onProgress,
      ),
      TrainerHomeTileData(
        title: 'Ustawienia Trainera',
        subtitle: 'Profil, wygląd i dane lokalne',
        icon: Icons.tune_rounded,
        onTap: onSettings,
      ),
    ];

    return PageFrame(
      title: 'Trainer',
      subtitle: 'Twój trening w jednym miejscu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.directions_run_rounded, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todayLogs.isEmpty ? 'Gotowy na dzisiejszy trening?' : 'Dzisiejszy trening zapisany',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          todayLogs.isEmpty ? 'Otwórz plan lub dodaj pierwszy wpis.' : '${todayLogs.length} ${todayLogs.length == 1 ? 'wpis' : 'wpisy'} w historii dnia.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 430
                      ? 2
                      : 1;
              final tileWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
              final tileHeight = columns == 1 ? 156.0 : 180.0;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiles.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: tileWidth / tileHeight,
                ),
                itemBuilder: (context, index) => TrainerHomeTile(data: tiles[index]),
              );
            },
          ),
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class TrainerHomeTile extends StatelessWidget {
  const TrainerHomeTile({super.key, required this.data});

  final TrainerHomeTileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  data.icon,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
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
    final duration = first.sessionStartedAt != null && first.sessionEndedAt != null
        ? first.sessionEndedAt!.difference(first.sessionStartedAt!)
        : Duration(seconds: logs.fold<int>(0, (sum, log) => sum + log.durationSec));
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
                      Text(first.sessionName.isEmpty ? 'Trening z planu' : first.sessionName,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(exerciseNames.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
    final logs = store.logsForDay(day);
    final totals = store.totalsForDay(day);
    return PageFrame(
      title: kAppName,
      subtitle: 'Dziennik, plan, AI i postęp',
      actions: [
        IconButton.filledTonal(
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
                    Text('${store.activeWorkoutSession!.planName} · ${store.activeWorkoutSession!.dayTitle}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
          const SizedBox(height: 14),
          DailyHero(totals: totals),
          const SizedBox(height: 14),
          TrainingInsightCard(logs: store.logs, selectedDay: day),
          const SizedBox(height: 14),
          WorkoutTimerCard(),
          const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Dzisiejsze ćwiczenia',
            actionLabel: 'Dodaj',
            onAction: () => showAddWorkoutSheet(context),
          ),
          const SizedBox(height: 10),
          if (logs.isEmpty)
            EmptyCard(
              icon: Icons.fitness_center,
              title: 'Nie masz jeszcze wpisu',
              text: 'Dodaj ćwiczenie ręcznie albo opisz trening w AI. Aplikacja policzy czas, objętość i spalone kalorie.',
              buttonLabel: 'Dodaj ćwiczenie',
              onPressed: () => showAddWorkoutSheet(context),
            )
          else
            ...logs.map((log) => WorkoutLogCard(log: log)),
          const SizedBox(height: 16),
          QuickWorkoutActionsCard(),
          const SizedBox(height: 12),
          AiQuickCard(),
        ],
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
            Text(top.isEmpty ? 'Dodaj kilka treningów, a pokażę najczęstsze ćwiczenie i kierunek progresu.' : 'Najczęściej ostatnio: $top',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                    Text('${log.sets} serie × ${log.reps == 0 ? '-' : log.reps} powt. · ${log.weightKg.toStringAsFixed(1)} kg',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('${log.calories.round()} kcal · RPE ${log.rpe} · ${(log.durationSec / 60).round()} min',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  showHidden ? 'Ukryte ćwiczenia' : 'Ćwiczenia',
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

  bool get _hasActiveFilters =>
      muscleGroup != 'Wszystkie' || equipmentType != 'Wszystkie' || level != 'Wszystkie' || trainingGoal != 'Wszystkie' || onlyFavorites || showHidden || onlyAvailableEquipment || avoidLimitations;
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
  });

  final bool showingHidden;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              showingHidden ? Icons.visibility_outlined : Icons.search_off_rounded,
              size: 46,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              showingHidden ? 'Brak ukrytych ćwiczeń' : 'Brak ćwiczeń dla wybranych filtrów',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              showingHidden ? 'Ukryte pozycje pojawią się tutaj i będzie można je przywrócić.' : 'Wyczyść filtry albo dodaj własne ćwiczenie.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
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
            Text('Najlepiej działa po angielsku: squat, push up, row, curl, deadlift. Po dodaniu ćwiczenie trafia do lokalnej bazy.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              Container(
                width: 78,
                height: 92,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ExerciseVisual(exercise: exercise),
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
            Row(children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
            ]),
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
            TextField(
                controller: note, maxLines: 4, decoration: const InputDecoration(hintText: 'Opisz, co czujesz albo nagraj opis: np. przy przysiadzie czuję lędźwie, kolana uciekają do środka...')),
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
                      Text('${plan.goal} · ${plan.days.length} dni · $exerciseCount ćwiczeń', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => startWorkoutFromActivePlan(context, plan),
              icon: Icon(AppScope.of(context).activeWorkoutSession == null ? Icons.play_arrow_rounded : Icons.play_circle_outline_rounded),
              label: Text(AppScope.of(context).activeWorkoutSession == null ? 'Rozpocznij trening' : 'Wznów trening'),
            ),
          ],
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
  final started = await store.startActiveWorkout(plan: plan, day: day);
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
    final summary = await store.finishActiveWorkout();
    if (!mounted || summary == null) return;
    leaving = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryPage(summary: summary),
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
              _ActiveWorkoutHeader(session: session, elapsed: elapsed),
              const SizedBox(height: 12),
              _CurrentExerciseCard(
                exercise: exercise,
                activeExercise: activeExercise,
                position: session.currentExerciseIndex + 1,
                total: session.exercises.length,
              ),
              const SizedBox(height: 12),
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

class _ActiveWorkoutHeader extends StatelessWidget {
  const _ActiveWorkoutHeader({required this.session, required this.elapsed});

  final ActiveWorkoutSession session;
  final Duration elapsed;

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
            Text(session.planName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${weekdayName(session.weekday)} · ${session.dayTitle}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                  Text('${activeExercise.plannedSets} serie × ${activeExercise.plannedReps} powt. · ${activeExercise.restSeconds} s przerwy',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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

class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({super.key, required this.summary});

  final CompletedWorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Podsumowanie treningu'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Icon(Icons.emoji_events_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Trening zakończony', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(summary.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
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
                _WorkoutSummaryStat(label: 'Objętość', value: '${summary.volume.round()} kg', icon: Icons.monitor_weight_outlined),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('Średnie RPE'),
                trailing: Text(summary.averageRpe == 0 ? '—' : summary.averageRpe.toStringAsFixed(1), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
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
                    Text('${day.title} · ${day.items.length} ćwiczeń',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                Text('${item.sets} serie × ${item.reps} powt. · $weight · ${item.restSeconds} s przerwy',
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              Text('Usunięcie zaznaczenia dnia usunie go z planu razem z przypisanymi ćwiczeniami.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          Text('Wybierz dzień docelowy. Jeśli już istnieje, jego zawartość zostanie zastąpiona.',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
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
                    Text('${plan.name} · ${weekdayName(day.weekday)}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            Text('${exercise.name} · ${weekdayName(day.weekday)}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
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

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return PageFrame(
      title: 'Więcej',
      subtitle: 'Profil, poziomy, motyw, eksport i stały backend AI',
      child: Column(
        children: [
          SettingsCard(settings: store.settings, onSave: store.updateSettings),
          const SizedBox(height: 12),
          ExportCard(),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Tryb nocny'),
              subtitle: const Text('Ciemny, premium styl podobny do aplikacji licznika'),
              value: store.settings.darkMode,
              onChanged: (v) => store.updateSettings(store.settings.copyWith(darkMode: v)),
            ),
          ),
          const SizedBox(height: 12),
          TrainerFeaturesHub(store: store),
          const SizedBox(height: 12),
          AboutCard(),
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
            const Text(
                '• Zdjęcia/wideo własnej techniki i analiza klatek.\n• Integracja z aplikacją kalorii: większe kcal w dni treningowe.\n• Baza własnych ćwiczeń z importem przez API wger i AI.\n• Timer interwałów i odpoczynku między seriami.\n• Plany PPL, FBW, góra/dół, brzuch z obciążeniem.'),
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
                        SizedBox(
                            width: width,
                            child: FeatureActionTile(icon: Icons.add_circle_outline, title: 'Dodaj trening', subtitle: 'Szybki wpis do dziennika', onTap: () => showAddWorkoutSheet(context))),
                        SizedBox(
                            width: width,
                            child: FeatureActionTile(icon: Icons.public, title: 'Import z bazy ćwiczeń', subtitle: 'Szukaj w wger i zapisuj lokalnie', onTap: () => showWgerSearchSheet(context))),
                        SizedBox(
                            width: width, child: FeatureActionTile(icon: Icons.auto_awesome, title: 'Plan AI', subtitle: 'Poziom + sprzęt + ograniczenia', onTap: () => showPlanGenerator(context))),
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
                        SizedBox(
                            width: width,
                            child: FeatureActionTile(
                                icon: Icons.download_outlined, title: 'Eksport CSV', subtitle: 'Dane treningowe do arkusza', onTap: () => showExportDialog(context, buildCsvExport(store)))),
                        SizedBox(
                            width: width,
                            child:
                                FeatureActionTile(icon: Icons.code, title: 'Eksport JSON', subtitle: 'Pełna kopia danych', onTap: () => showExportDialog(context, prettyJson(buildFullExport(store))))),
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
            Row(children: [
              Icon(Icons.emoji_events_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Rekordy osobiste', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
            ]),
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
            Row(children: [
              Icon(Icons.balance_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Tygodniowy balans partii', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
            ]),
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
            Row(children: [
              Icon(Icons.calendar_view_month_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Podsumowanie miesiąca', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
            ]),
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
          Row(children: [
            Icon(Icons.checklist_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Checklist treningowy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
          ]),
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
          Row(children: [
            Icon(Icons.build_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Sprzęt i ograniczenia', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))
          ]),
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
  if ((l.contains('plec') || l.contains('lędź') || l.contains('ledz') || l.contains('back')) &&
      (text.contains('martwy') || text.contains('deadlift') || text.contains('row') || text.contains('wiosł'))) return false;
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

Map<String, dynamic> buildSharedCalorieProfile(AppStore store) {
  final today = store.totalsForDay(store.selectedDate);
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
    return Card(
        child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Timer przerw zależny od celu'),
            subtitle: Text('Rekomendowana przerwa: $recommendedSeconds s · aktywnie: $min:$sec'),
            trailing: FilledButton(onPressed: start, child: const Text('Start'))));
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
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['FBW', 'PPL', 'Góra/Dół', 'Brzuch z obciążeniem']
                  .map((t) => FilledButton.tonal(onPressed: () => showSmartTextDialog(context, t, buildTemplatePlan(t, settings)), child: Text(t)))
                  .toList()),
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
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Nogi', 'Plecy', 'Klatka', 'Barki', 'Brzuch i core']
                  .map((t) => OutlinedButton(onPressed: () => showSmartTextDialog(context, 'Plan: $t', buildTargetPlan(t, settings)), child: Text(t)))
                  .toList()),
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
    final warning =
        totals.volume > 35000 || totals.durationSec > 420 * 60 ? 'Objętość tygodnia jest wysoka. Rozważ lżejszy dzień albo deload.' : 'Objętość tygodniowa wygląda bezpiecznie przy obecnych danych.';
    return Card(
        child: ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Ostrzeżenia objętości'),
            subtitle: Text('$warning Objętość: ${totals.volume.round()} kg, czas: ${(totals.durationSec / 60).round()} min.')));
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
          Row(children: [
            Icon(Icons.accessibility_new_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Mapa trenowanych partii', style: TextStyle(fontWeight: FontWeight.w900)))
          ]),
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
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Wykres serii na partię', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              if (entries.isEmpty) const Text('Brak danych') else ...entries.take(8).map((e) => ProgressTextBar(label: e.key, value: e.value.toDouble(), max: maxV.toDouble(), suffix: '${e.value}x'))
            ])));
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
                  return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ex.name),
                      subtitle: Text('Najlepsza objętość: ${best.volume.round()} kg · ciężar ${best.weightKg.toStringAsFixed(1)} kg · powt. ${best.reps}'));
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
    return const Card(
        child: ListTile(
            leading: Icon(Icons.wifi_off_outlined),
            title: Text('Tryb offline i lokalny fallback'),
            subtitle: Text('Baza ćwiczeń, dziennik, wykresy, plan lokalny, timer, checklisty i eksport działają bez internetu. AI i wger wymagają sieci.')));
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
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Błędy techniczne do odhaczenia', style: TextStyle(fontWeight: FontWeight.w900)),
              ...items.asMap().entries.map((e) =>
                  CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: checked[e.key] ?? false, title: Text(e.value), onChanged: (v) => setState(() => checked[e.key] = v ?? false)))
            ])));
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

class ExerciseProgressionCard extends StatelessWidget {
  final Exercise exercise;
  const ExerciseProgressionCard({super.key, required this.exercise});
  @override
  Widget build(BuildContext context) {
    return Card(
        child: ListTile(
            leading: const Icon(Icons.stacked_line_chart_outlined),
            title: const Text('Rekomendacja progresji tygodniowej'),
            subtitle: Text('Dla ${exercise.name}: gdy wszystkie serie są techniczne przy RPE <=7, dodaj 1-2 powtórzenia albo najmniejszy dostępny ciężar. Gdy RPE >=9, utrzymaj lub odejmij 10%.')));
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

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;
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
    final ex = Exercise(
      id: original?.id ?? 'custom_${idNow()}',
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
                    child: DropdownButton<int>(
                        value: rpe,
                        isExpanded: true,
                        items: List.generate(10, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('$v/10'))).toList(),
                        onChanged: (v) => setState(() => rpe = v ?? rpe)),
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

class ExerciseVisual extends StatelessWidget {
  final Exercise exercise;

  const ExerciseVisual({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final image = exercise.imageUrl;
    if (image != null && image.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => HumanExerciseImage(type: exercise.illustrationType),
          loadingBuilder: (context, child, progress) => progress == null ? child : HumanExerciseImage(type: exercise.illustrationType),
        ),
      );
    }
    return HumanExerciseImage(type: exercise.illustrationType);
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
              child: exercise.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.network(
                        exercise.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(child: HumanExerciseImage(type: exercise.illustrationType, size: 230)),
                      ),
                    )
                  : Center(child: HumanExerciseImage(type: exercise.illustrationType, size: 230)),
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
  bool shouldRepaint(covariant HumanExercisePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.progress != progress || oldDelegate.bodyColor != bodyColor || oldDelegate.backgroundColor != backgroundColor || oldDelegate.accentColor != accentColor;
}
