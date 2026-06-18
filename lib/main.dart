import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


const String kAppName = 'Trainer';
const String kDefaultBackendUrl = 'https://licznik-kalorii.onrender.com';
const List<String> kTrainingLevels = ['Początkujący', 'Średniozaawansowany', 'Zaawansowany'];

String normalizeLevel(String value) {
  final v = value.trim().toLowerCase();
  if (v.contains('zaaw')) return 'Zaawansowany';
  if (v.contains('śred') || v.contains('sred') || v.contains('inter') || v.contains('mid')) return 'Średniozaawansowany';
  return 'Początkujący';
}

String stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
}

class AppStore extends ChangeNotifier {
  final List<WorkoutLog> logs = [];
  final List<WorkoutPlan> plans = [];
  final List<Exercise> customExercises = [];
  AppSettings settings = AppSettings.defaults();
  DateTime selectedDate = DateTime.now();
  String? lastAiMessage;
  bool aiBusy = false;

  static const _logsKey = 'workout_logs_v1';
  static const _plansKey = 'workout_plans_v1';
  static const _settingsKey = 'workout_settings_v1';
  static const _customExercisesKey = 'workout_custom_exercises_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLogs = prefs.getString(_logsKey);
    if (rawLogs != null && rawLogs.isNotEmpty) {
      try {
        logs
          ..clear()
          ..addAll((jsonDecode(rawLogs) as List).map((e) => WorkoutLog.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }

    final rawPlans = prefs.getString(_plansKey);
    if (rawPlans != null && rawPlans.isNotEmpty) {
      try {
        plans
          ..clear()
          ..addAll((jsonDecode(rawPlans) as List).map((e) => WorkoutPlan.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }

    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null && rawSettings.isNotEmpty) {
      try {
        settings = AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawSettings)));
      } catch (_) {}
    }



    final rawCustomExercises = prefs.getString(_customExercisesKey);
    if (rawCustomExercises != null && rawCustomExercises.isNotEmpty) {
      try {
        customExercises
          ..clear()
          ..addAll((jsonDecode(rawCustomExercises) as List).map((e) => Exercise.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }

    if (plans.isEmpty) {
      plans.add(WorkoutPlan.localDefault(settings));
      await savePlans();
    }
  }

  Future<void> saveAll() async {
    await saveLogs();
    await savePlans();
    await saveSettings();
    await saveCustomExercises();
  }

  Future<void> saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logsKey, jsonEncode(logs.map((e) => e.toJson()).toList()));
  }

  Future<void> savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plansKey, jsonEncode(plans.map((e) => e.toJson()).toList()));
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> saveCustomExercises() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customExercisesKey, jsonEncode(customExercises.map((e) => e.toJson()).toList()));
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
        'user': settings.toAiProfile(),
      });
      lastAiMessage = prettyJson(result);
      final plan = WorkoutPlan.fromAi(result, goal);
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
      ..add(WorkoutPlan.localDefault(settings));
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
    'training_weekdays': trainingWeekdays,
  };
}

class Exercise {
  final String id;
  final String name;
  final String category;
  final List<String> muscles;
  final String equipment;
  final String level;
  final String illustrationType;
  final String description;
  final List<String> tips;
  final List<String> commonMistakes;
  final int defaultSets;
  final int defaultReps;
  final int defaultDurationSec;
  final double met;
  final String? imageUrl;
  final String source;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscles,
    required this.equipment,
    required this.level,
    required this.illustrationType,
    required this.description,
    required this.tips,
    required this.commonMistakes,
    required this.defaultSets,
    required this.defaultReps,
    required this.defaultDurationSec,
    required this.met,
    this.imageUrl,
    this.source = 'local',
  });

  Exercise copyWith({
    String? id,
    String? name,
    String? category,
    List<String>? muscles,
    String? equipment,
    String? level,
    String? illustrationType,
    String? description,
    List<String>? tips,
    List<String>? commonMistakes,
    int? defaultSets,
    int? defaultReps,
    int? defaultDurationSec,
    double? met,
    String? imageUrl,
    String? source,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      muscles: muscles ?? this.muscles,
      equipment: equipment ?? this.equipment,
      level: normalizeLevel(level ?? this.level),
      illustrationType: illustrationType ?? this.illustrationType,
      description: description ?? this.description,
      tips: tips ?? this.tips,
      commonMistakes: commonMistakes ?? this.commonMistakes,
      defaultSets: defaultSets ?? this.defaultSets,
      defaultReps: defaultReps ?? this.defaultReps,
      defaultDurationSec: defaultDurationSec ?? this.defaultDurationSec,
      met: met ?? this.met,
      imageUrl: imageUrl ?? this.imageUrl,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'muscles': muscles,
    'equipment': equipment,
    'level': level,
    'illustrationType': illustrationType,
    'description': description,
    'tips': tips,
    'commonMistakes': commonMistakes,
    'defaultSets': defaultSets,
    'defaultReps': defaultReps,
    'defaultDurationSec': defaultDurationSec,
    'met': met,
    'imageUrl': imageUrl,
    'source': source,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id']?.toString() ?? 'custom_${idNow()}',
    name: json['name']?.toString() ?? 'Ćwiczenie',
    category: json['category']?.toString() ?? 'Inne',
    muscles: ((json['muscles'] as List?) ?? const ['całe ciało']).map((e) => e.toString()).toList(),
    equipment: json['equipment']?.toString() ?? 'brak danych',
    level: normalizeLevel(json['level']?.toString() ?? 'Początkujący'),
    illustrationType: json['illustrationType']?.toString() ?? 'generic',
    description: json['description']?.toString() ?? '',
    tips: ((json['tips'] as List?) ?? const <String>[]).map((e) => e.toString()).toList(),
    commonMistakes: ((json['commonMistakes'] as List?) ?? const <String>[]).map((e) => e.toString()).toList(),
    defaultSets: (json['defaultSets'] as num?)?.toInt() ?? 3,
    defaultReps: (json['defaultReps'] as num?)?.toInt() ?? 10,
    defaultDurationSec: (json['defaultDurationSec'] as num?)?.toInt() ?? 0,
    met: (json['met'] as num?)?.toDouble() ?? 4.5,
    imageUrl: (json['imageUrl']?.toString().trim().isEmpty ?? true) ? null : json['imageUrl'].toString(),
    source: json['source']?.toString() ?? 'custom',
  );
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
  ];

  static List<Exercise> combined([List<Exercise> custom = const []]) => [...all, ...custom];

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
}

class WorkoutLog {
  final String id;
  final String exerciseId;
  final DateTime date;
  final int sets;
  final int reps;
  final double weightKg;
  final int durationSec;
  final int rpe;
  final double calories;
  final String note;
  final double aiConfidence;

  const WorkoutLog({
    required this.id,
    required this.exerciseId,
    required this.date,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.durationSec,
    required this.rpe,
    required this.calories,
    required this.note,
    required this.aiConfidence,
  });

  Exercise get exercise => ExerciseRepo.byId(exerciseId);

  Exercise exerciseFrom(List<Exercise> custom) => ExerciseRepo.byId(exerciseId, custom);

  double get volume => sets * reps * weightKg;

  WorkoutLog copyWith({
    String? id,
    String? exerciseId,
    DateTime? date,
    int? sets,
    int? reps,
    double? weightKg,
    int? durationSec,
    int? rpe,
    double? calories,
    String? note,
    double? aiConfidence,
  }) {
    return WorkoutLog(
      id: id ?? this.id,
      exerciseId: exerciseId ?? this.exerciseId,
      date: date ?? this.date,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weightKg: weightKg ?? this.weightKg,
      durationSec: durationSec ?? this.durationSec,
      rpe: rpe ?? this.rpe,
      calories: calories ?? this.calories,
      note: note ?? this.note,
      aiConfidence: aiConfidence ?? this.aiConfidence,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'date': date.toIso8601String(),
    'sets': sets,
    'reps': reps,
    'weightKg': weightKg,
    'durationSec': durationSec,
    'rpe': rpe,
    'calories': calories,
    'note': note,
    'aiConfidence': aiConfidence,
  };

  factory WorkoutLog.fromJson(Map<String, dynamic> json) => WorkoutLog(
    id: json['id']?.toString() ?? idNow(),
    exerciseId: json['exerciseId']?.toString() ?? ExerciseRepo.all.first.id,
    date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
    sets: (json['sets'] as num?)?.toInt() ?? 0,
    reps: (json['reps'] as num?)?.toInt() ?? 0,
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
    durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
    rpe: (json['rpe'] as num?)?.toInt() ?? 7,
    calories: (json['calories'] as num?)?.toDouble() ?? 0,
    note: json['note']?.toString() ?? '',
    aiConfidence: (json['aiConfidence'] as num?)?.toDouble() ?? 0,
  );
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

class WorkoutPlan {
  final String id;
  final String name;
  final List<PlanDay> days;
  final String note;

  const WorkoutPlan({required this.id, required this.name, required this.days, required this.note});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'days': days.map((e) => e.toJson()).toList(),
    'note': note,
  };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
    id: json['id']?.toString() ?? idNow(),
    name: json['name']?.toString() ?? 'Plan',
    days: ((json['days'] as List?) ?? []).map((e) => PlanDay.fromJson(Map<String, dynamic>.from(e))).toList(),
    note: json['note']?.toString() ?? '',
  );

  factory WorkoutPlan.localDefault(AppSettings settings) {
    final days = <PlanDay>[];
    final level = normalizeLevel(settings.level);
    final cycle = level == 'Początkujący'
        ? [
      ['incline_pushup', 'goblet_squat', 'assisted_pullup', 'plank'],
      ['lat_pulldown', 'reverse_lunge', 'face_pull', 'crunch'],
      ['pushup', 'squat', 'bicep_curl', 'side_plank'],
      ['bike', 'mountain_climber', 'calf_raise', 'triceps_extension'],
    ]
        : level == 'Zaawansowany'
        ? [
      ['front_squat', 'pullup', 'bench_press', 'hollow_hold'],
      ['deadlift', 'dips', 'row', 'leg_raise'],
      ['bulgarian_split_squat', 'shoulder_press', 'jump_rope', 'russian_twist'],
      ['pistol_squat', 'burpee', 'pullup', 'plank'],
      ['run', 'hip_thrust', 'lateral_raise', 'face_pull'],
    ]
        : [
      ['squat', 'lunge', 'crunch', 'plank'],
      ['pushup', 'pullup', 'shoulder_press', 'bicep_curl'],
      ['deadlift', 'hip_thrust', 'mountain_climber', 'side_plank'],
      ['bench_press', 'row', 'lateral_raise', 'triceps_extension'],
      ['jumping_jack', 'burpee', 'leg_raise', 'russian_twist'],
    ];
    for (var i = 0; i < settings.trainingWeekdays.length; i++) {
      final weekday = settings.trainingWeekdays[i];
      final exerciseIds = cycle[i % cycle.length];
      days.add(PlanDay(
        weekday: weekday,
        title: level == 'Początkujący'
            ? (i.isEven ? 'Fundament techniki' : 'Lekka siła + core')
            : level == 'Zaawansowany'
            ? (i.isEven ? 'Siła / hipertrofia' : 'Moc + kondycja')
            : (i.isEven ? 'Siła + brzuch' : 'Góra ciała + kondycja'),
        items: exerciseIds.map((id) {
          final e = ExerciseRepo.byId(id);
          final setModifier = level == 'Początkujący' ? -1 : level == 'Zaawansowany' ? 1 : 0;
          return PlanItem(
            exerciseId: id,
            sets: math.max(2, e.defaultSets + setModifier).toInt(),
            reps: e.defaultReps,
            durationSec: e.defaultDurationSec,
            note: e.defaultDurationSec > 0 ? 'czas pracy · poziom $level' : 'kontrolowane tempo · poziom $level',
          );
        }).toList(),
      ));
    }
    return WorkoutPlan(
      id: idNow(),
      name: 'Plan lokalny $level: ${settings.goal}',
      days: days,
      note: 'Plan lokalny dopasowany do poziomu: $level. Możesz go nadpisać planem AI przez Twój backend.',
    );
  }

  factory WorkoutPlan.fromAi(Map<String, dynamic> json, String goal) {
    final rawDays = (json['days'] as List?) ?? (json['week_plan'] as List?) ?? [];
    final days = <PlanDay>[];
    for (final raw in rawDays) {
      final map = Map<String, dynamic>.from(raw as Map);
      final weekdayRaw = map['weekday'] ?? map['day'] ?? 1;
      final weekday = weekdayRaw is num ? weekdayRaw.toInt() : _weekdayFromText(weekdayRaw.toString());
      final rawItems = (map['items'] as List?) ?? (map['exercises'] as List?) ?? [];
      final items = <PlanItem>[];
      for (final x in rawItems) {
        final m = Map<String, dynamic>.from(x as Map);
        final name = (m['exercise'] ?? m['name'] ?? '').toString().toLowerCase();
        final found = ExerciseRepo.all.firstWhere(
              (e) => name.contains(e.name.toLowerCase()) || e.name.toLowerCase().contains(name),
          orElse: () => ExerciseRepo.all.first,
        );
        items.add(PlanItem(
          exerciseId: found.id,
          sets: (m['sets'] as num?)?.toInt() ?? found.defaultSets,
          reps: (m['reps'] as num?)?.toInt() ?? found.defaultReps,
          durationSec: (m['duration_sec'] as num?)?.toInt() ?? found.defaultDurationSec,
          note: (m['note'] ?? m['reason'] ?? '').toString(),
        ));
      }
      days.add(PlanDay(weekday: weekday, title: map['title']?.toString() ?? 'Trening', items: items));
    }
    if (days.isEmpty) return WorkoutPlan.localDefault(AppSettings.defaults());
    return WorkoutPlan(
      id: idNow(),
      name: json['name']?.toString() ?? 'Plan AI: $goal',
      days: days,
      note: json['note']?.toString() ?? 'Plan utworzony przez backend AI.',
    );
  }

  static int _weekdayFromText(String text) {
    final t = text.toLowerCase();
    if (t.contains('wt')) return 2;
    if (t.contains('ś') || t.contains('sr')) return 3;
    if (t.contains('czw')) return 4;
    if (t.contains('pt')) return 5;
    if (t.contains('sob')) return 6;
    if (t.contains('niedz')) return 7;
    return 1;
  }
}

class PlanDay {
  final int weekday;
  final String title;
  final List<PlanItem> items;

  const PlanDay({required this.weekday, required this.title, required this.items});

  Map<String, dynamic> toJson() => {'weekday': weekday, 'title': title, 'items': items.map((e) => e.toJson()).toList()};

  factory PlanDay.fromJson(Map<String, dynamic> json) => PlanDay(
    weekday: (json['weekday'] as num?)?.toInt() ?? 1,
    title: json['title']?.toString() ?? 'Trening',
    items: ((json['items'] as List?) ?? []).map((e) => PlanItem.fromJson(Map<String, dynamic>.from(e))).toList(),
  );
}

class PlanItem {
  final String exerciseId;
  final int sets;
  final int reps;
  final int durationSec;
  final String note;

  const PlanItem({required this.exerciseId, required this.sets, required this.reps, required this.durationSec, required this.note});

  Exercise get exercise => ExerciseRepo.byId(exerciseId);

  Exercise exerciseFrom(List<Exercise> custom) => ExerciseRepo.byId(exerciseId, custom);

  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'sets': sets,
    'reps': reps,
    'durationSec': durationSec,
    'note': note,
  };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
    exerciseId: json['exerciseId']?.toString() ?? ExerciseRepo.all.first.id,
    sets: (json['sets'] as num?)?.toInt() ?? 3,
    reps: (json['reps'] as num?)?.toInt() ?? 10,
    durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
    note: json['note']?.toString() ?? '',
  );
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
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 35));
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayPage(),
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
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Dzisiaj'),
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
          DateSwitcher(date: day, onChanged: store.setSelectedDate),
          const SizedBox(height: 14),
          DailyHero(totals: totals),
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
            child: AnimatedExerciseIllustration(type: 'burpee', lineColor: theme.colorScheme.onPrimary, backgroundColor: theme.colorScheme.onPrimary.withOpacity(0.12)),
          ),
        ],
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
              const SizedBox(height: 10),
              SelectableText(store.lastAiMessage!, style: theme.textTheme.bodySmall),
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
    builder: (_) => AlertDialog(
      title: const Text('Wynik AI'),
      content: SingleChildScrollView(child: SelectableText(prettyJson(result))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
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
  String category = 'Wszystkie';
  String level = 'Wszystkie';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final categories = ExerciseRepo.categories(store.customExercises);
    if (!categories.contains(category)) category = 'Wszystkie';
    final items = ExerciseRepo.search(search.text, category, level, store.customExercises);
    return PageFrame(
      title: 'Baza ćwiczeń',
      subtitle: '${items.length} ćwiczeń · poziomy, lokalna baza i import z wger',
      actions: [
        IconButton.filledTonal(onPressed: () => showWgerSearchSheet(context), icon: const Icon(Icons.cloud_download_outlined)),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: () => showAddWorkoutSheet(context), icon: const Icon(Icons.add)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Szukaj po nazwie, mięśniu, sprzęcie albo poziomie'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = categories[i];
                return ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c));
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: const ['Wszystkie', ...kTrainingLevels].length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final levels = const ['Wszystkie', ...kTrainingLevels];
                final l = levels[i];
                return FilterChip(label: Text(l), selected: level == l, onSelected: (_) => setState(() => level = l));
              },
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Darmowa baza online'),
              subtitle: const Text('Szukaj ćwiczeń w wger i dodawaj je do lokalnej bazy Trainer.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showWgerSearchSheet(context),
            ),
          ),
          const SizedBox(height: 14),
          ...items.map((e) => ExerciseCard(exercise: e)),
        ],
      ),
    );
  }
}

void showWgerSearchSheet(BuildContext context) {
  final store = AppScope.of(context);
  final query = TextEditingController();
  var busy = false;
  var message = '';
  var results = <Exercise>[];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(builder: (context, setSheet) {
        Future<void> runSearch() async {
          if (query.text.trim().isEmpty) return;
          setSheet(() {
            busy = true;
            message = '';
          });
          try {
            final found = await WgerService().searchExercises(query.text);
            if (!context.mounted) return;
            setSheet(() {
              results = found;
              message = found.isEmpty ? 'Brak wyników. Spróbuj angielskiej nazwy, np. squat, row, bench press.' : 'Znaleziono ${found.length} ćwiczeń.';
            });
          } catch (e) {
            if (!context.mounted) return;
            setSheet(() => message = 'Błąd API: $e');
          } finally {
            if (context.mounted) setSheet(() => busy = false);
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Import ćwiczeń z wger', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Najlepiej działa po angielsku: squat, push up, row, curl, deadlift.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_search),
                  label: const Text('Szukaj w darmowej bazie'),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(message),
                ],
                const SizedBox(height: 12),
                ...results.map((exercise) => Card(
                  child: ListTile(
                    leading: SizedBox(width: 54, height: 54, child: ExerciseVisual(exercise: exercise)),
                    title: Text(exercise.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${exercise.category} · ${exercise.equipment}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: FilledButton(
                      onPressed: () async {
                        await store.addCustomExercise(exercise);
                        if (!context.mounted) return;
                        showError(context, 'Dodano do bazy: ${exercise.name}');
                      },
                      child: const Text('Dodaj'),
                    ),
                  ),
                )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      });
    },
  ).whenComplete(query.dispose);
}

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;

  const ExerciseCard({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExerciseDetailsPage(exercise: exercise))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(width: 92, height: 92, child: ExerciseVisual(exercise: exercise)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(exercise.category, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(exercise.muscles.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        MiniTag(text: normalizeLevel(exercise.level)),
                        MiniTag(text: exercise.equipment),
                        if (exercise.source != 'local') MiniTag(text: exercise.source),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
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
  final Exercise exercise;

  const ExerciseDetailsPage({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name), actions: [IconButton(onPressed: () => showAddWorkoutSheet(context, exercise: exercise), icon: const Icon(Icons.add))]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ExerciseHeroVisual(exercise: exercise),
          const SizedBox(height: 16),
          ExerciseStoryboard(exercise: exercise),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.description, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [MiniTag(text: exercise.category), MiniTag(text: exercise.equipment), MiniTag(text: normalizeLevel(exercise.level)), if (exercise.source != 'local') MiniTag(text: exercise.source)]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          InfoListCard(title: 'Wskazówki techniczne', icon: Icons.check_circle_outline, items: exercise.tips),
          const SizedBox(height: 12),
          InfoListCard(title: 'Najczęstsze błędy', icon: Icons.warning_amber_rounded, items: exercise.commonMistakes),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => showAddWorkoutSheet(context, exercise: exercise), icon: const Icon(Icons.add), label: const Text('Dodaj do dziennika')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => analyzeFormDialog(context, exercise),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Analiza techniki przez backend'),
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
                final store = AppScope.of(context);
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
    final plan = store.plans.isNotEmpty ? store.plans.first : WorkoutPlan.localDefault(store.settings);
    return PageFrame(
      title: 'Plan tygodnia',
      subtitle: 'Lokalny albo generowany przez backend AI',
      actions: [IconButton.filledTonal(onPressed: () => showPlanGenerator(context), icon: const Icon(Icons.auto_awesome))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(plan.note, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(onPressed: store.generateLocalPlan, icon: const Icon(Icons.refresh), label: const Text('Lokalny'))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton.icon(onPressed: () => showPlanGenerator(context), icon: const Icon(Icons.auto_awesome), label: const Text('AI'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...plan.days.map((d) => PlanDayCard(day: d)),
        ],
      ),
    );
  }
}

class PlanDayCard extends StatelessWidget {
  final PlanDay day;

  const PlanDayCard({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${weekdayName(day.weekday)} · ${day.title}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...day.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(width: 56, height: 56, child: AnimatedExerciseIllustration(type: item.exercise.illustrationType)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.exercise.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(item.durationSec > 0 ? '${item.sets} × ${item.durationSec}s · ${item.note}' : '${item.sets} × ${item.reps} · ${item.note}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => showAddWorkoutSheet(context, exercise: item.exercise, fromPlan: item), icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

void showPlanGenerator(BuildContext context) {
  final store = AppScope.of(context);
  final goal = TextEditingController(text: store.settings.goal);
  final equipment = TextEditingController(text: 'masa ciała, hantle, drążek, mata');
  final limitations = TextEditingController();
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
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom)
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
              value: level,
              decoration: const InputDecoration(labelText: 'Poziom planu'),
              items: kTrainingLevels.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
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
                  await store.updateSettings(store.settings.copyWith(level: level, backendUrl: kDefaultBackendUrl));
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
    final grid = Paint()..color = color.withOpacity(0.13)..strokeWidth = 1;
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
    canvas.drawPath(fill, Paint()..color = color.withOpacity(0.10)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
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
  late String level;

  @override
  void initState() {
    super.initState();
    weight = TextEditingController();
    height = TextEditingController();
    age = TextEditingController();
    goal = TextEditingController();
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
    level = normalizeLevel(s.level);
  }

  @override
  void dispose() {
    weight.dispose();
    height.dispose();
    age.dispose();
    goal.dispose();
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
            Row(children: [
              Expanded(child: TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wiek'))),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: level,
                  decoration: const InputDecoration(labelText: 'Poziom'),
                  items: kTrainingLevels.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => level = v ?? level),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: goal, maxLines: 2, decoration: const InputDecoration(labelText: 'Cel treningowy')),
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
                  level: level,
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
    final data = jsonEncode({'settings': store.settings.toJson(), 'logs': store.logs.map((e) => e.toJson()).toList(), 'plans': store.plans.map((e) => e.toJson()).toList()});
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
            Text('Co można dodać dalej', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('• Zdjęcia/wideo własnej techniki i analiza klatek.\n• Integracja z aplikacją kalorii: większe kcal w dni treningowe.\n• Baza własnych ćwiczeń z importem przez API wger i AI.\n• Timer interwałów i odpoczynku między seriami.\n• Plany PPL, FBW, góra/dół, brzuch z obciążeniem.'),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddWorkoutSheet(BuildContext context, {Exercise? exercise, WorkoutLog? existing, PlanItem? fromPlan}) async {
  final store = AppScope.of(context);
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
                    value: exercises.any((e) => e.id == selectedExercise.id) ? selectedExercise.id : exercises.first.id,
                    decoration: const InputDecoration(labelText: 'Ćwiczenie'),
                    items: exercises.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))).toList(),
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
          errorBuilder: (_, __, ___) => AnimatedExerciseIllustration(type: exercise.illustrationType),
          loadingBuilder: (context, child, progress) => progress == null ? child : AnimatedExerciseIllustration(type: exercise.illustrationType),
        ),
      );
    }
    return AnimatedExerciseIllustration(type: exercise.illustrationType);
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
                  errorBuilder: (_, __, ___) => Center(child: AnimatedExerciseIllustration(type: exercise.illustrationType, size: 230)),
                ),
              )
                  : Center(child: AnimatedExerciseIllustration(type: exercise.illustrationType, size: 230)),
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

class ExerciseStoryboard extends StatefulWidget {
  final Exercise exercise;

  const ExerciseStoryboard({super.key, required this.exercise});

  @override
  State<ExerciseStoryboard> createState() => _ExerciseStoryboardState();
}

class _ExerciseStoryboardState extends State<ExerciseStoryboard> {
  final controller = PageController(viewportFraction: 0.82);
  int index = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const frames = 8;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.view_carousel_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Slajdy ruchu krok po kroku', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                Text('${index + 1}/$frames', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: PageView.builder(
                controller: controller,
                itemCount: frames,
                onPageChanged: (v) => setState(() => index = v),
                itemBuilder: (_, i) {
                  final t = frames == 1 ? 0.0 : i / (frames - 1);
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: CustomPaint(
                                painter: ExercisePainter(
                                  type: widget.exercise.illustrationType,
                                  t: Curves.easeInOut.transform(t),
                                  lineColor: theme.colorScheme.primary,
                                  backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.30),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Text(_frameCaption(i, frames), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text('To są lokalne, autorskie slajdy techniczne w aplikacji. Dla ćwiczeń z API aplikacja próbuje też pokazać obraz z bazy, a slajdy generuje według rozpoznanego typu ruchu.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  String _frameCaption(int i, int frames) {
    if (i == 0) return 'Pozycja startowa i ustawienie ciała';
    if (i == frames - 1) return 'Powrót do pozycji startowej bez utraty kontroli';
    if (i < frames / 2) return 'Faza opuszczania / przygotowania ruchu';
    return 'Faza pracy i napięcia mięśniowego';
  }
}

class AnimatedExerciseIllustration extends StatefulWidget {
  final String type;
  final double? size;
  final Color? lineColor;
  final Color? backgroundColor;

  const AnimatedExerciseIllustration({super.key, required this.type, this.size, this.lineColor, this.backgroundColor});

  @override
  State<AnimatedExerciseIllustration> createState() => _AnimatedExerciseIllustrationState();
}

class _AnimatedExerciseIllustrationState extends State<AnimatedExerciseIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.lineColor ?? theme.colorScheme.primary;
    final bg = widget.backgroundColor ?? theme.colorScheme.primaryContainer.withOpacity(0.45);
    final child = AnimatedBuilder(
      animation: controller,
      builder: (_, __) => CustomPaint(
        painter: ExercisePainter(type: widget.type, t: Curves.easeInOut.transform(controller.value), lineColor: line, backgroundColor: bg),
      ),
    );
    if (widget.size != null) return SizedBox(width: widget.size, height: widget.size, child: child);
    return child;
  }
}

class ExercisePainter extends CustomPainter {
  final String type;
  final double t;
  final Color lineColor;
  final Color backgroundColor;

  ExercisePainter({required this.type, required this.t, required this.lineColor, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final offset = Offset((size.width - s) / 2, (size.height - s) / 2);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)), Paint()..color = backgroundColor);
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = s * 0.045
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final jointPaint = Paint()..color = lineColor;

    void line(double x1, double y1, double x2, double y2) => canvas.drawLine(Offset(x1 * s, y1 * s), Offset(x2 * s, y2 * s), paint);
    void circle(double x, double y, double r, {PaintingStyle style = PaintingStyle.stroke}) {
      final p = Paint()
        ..color = lineColor
        ..strokeWidth = s * 0.045
        ..style = style
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(Offset(x * s, y * s), r * s, p);
    }
    void joint(double x, double y) => canvas.drawCircle(Offset(x * s, y * s), s * 0.018, jointPaint);

    switch (type) {
      case 'squat':
        _drawSquat(line, circle, joint, s);
        break;
      case 'pushup':
        _drawPushup(line, circle, joint, s);
        break;
      case 'plank':
        _drawPlank(line, circle, joint, s);
        break;
      case 'lunge':
        _drawLunge(line, circle, joint, s);
        break;
      case 'deadlift':
        _drawDeadlift(line, circle, joint, s);
        break;
      case 'crunch':
        _drawCrunch(line, circle, joint, s);
        break;
      case 'jumpingJack':
        _drawJumpingJack(line, circle, joint, s);
        break;
      case 'pullUp':
        _drawPullUp(line, circle, joint, s);
        break;
      case 'shoulderPress':
        _drawShoulderPress(line, circle, joint, s);
        break;
      case 'bicepCurl':
        _drawBicepCurl(line, circle, joint, s);
        break;
      case 'burpee':
        _drawBurpee(line, circle, joint, s);
        break;
      case 'mountainClimber':
        _drawMountainClimber(line, circle, joint, s);
        break;
      case 'hipThrust':
        _drawHipThrust(line, circle, joint, s);
        break;
      case 'calfRaise':
        _drawCalfRaise(line, circle, joint, s);
        break;
      case 'benchPress':
        _drawBenchPress(line, circle, joint, s);
        break;
      case 'dips':
        _drawDips(line, circle, joint, s);
        break;
      case 'row':
        _drawRow(line, circle, joint, s);
        break;
      case 'lateralRaise':
        _drawLateralRaise(line, circle, joint, s);
        break;
      case 'tricepsExtension':
        _drawTricepsExtension(line, circle, joint, s);
        break;
      case 'legRaise':
        _drawLegRaise(line, circle, joint, s);
        break;
      case 'russianTwist':
        _drawRussianTwist(line, circle, joint, s);
        break;
      case 'hollowHold':
        _drawHollowHold(line, circle, joint, s);
        break;
      case 'highKnees':
        _drawHighKnees(line, circle, joint, s);
        break;
      case 'run':
        _drawRun(line, circle, joint, s);
        break;
      case 'bike':
        _drawBike(line, circle, joint, s);
        break;
      case 'generic':
        _drawGeneric(line, circle, joint, s);
        break;
      default:
        _drawGeneric(line, circle, joint, s);
    }
    canvas.restore();
  }

  void _drawSquat(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final down = t;
    final headY = 0.25 + down * 0.08;
    final hipY = 0.50 + down * 0.17;
    final kneeY = 0.68 + down * 0.03;
    final hipX = 0.50;
    circle(0.50, headY, 0.07);
    line(0.50, headY + 0.07, hipX, hipY);
    line(0.50, 0.37 + down * 0.06, 0.32, 0.47 + down * 0.05);
    line(0.50, 0.37 + down * 0.06, 0.68, 0.47 + down * 0.05);
    line(hipX, hipY, 0.36, kneeY);
    line(0.36, kneeY, 0.30, 0.86);
    line(hipX, hipY, 0.64, kneeY);
    line(0.64, kneeY, 0.70, 0.86);
    line(0.18, 0.88, 0.82, 0.88);
    for (final p in [Offset(hipX, hipY), const Offset(0.36, 0.68), const Offset(0.64, 0.68)]) joint(p.dx, p.dy);
  }

  void _drawPushup(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final y = 0.44 + t * 0.18;
    circle(0.25, y - 0.05, 0.055);
    line(0.30, y, 0.72, y + 0.10);
    line(0.39, y + 0.02, 0.36, 0.78);
    line(0.39, y + 0.02, 0.47, 0.78);
    line(0.72, y + 0.10, 0.88, 0.80);
    line(0.72, y + 0.10, 0.80, 0.82);
    line(0.14, 0.82, 0.92, 0.82);
  }

  void _drawPlank(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    circle(0.22, 0.43, 0.055);
    line(0.28, 0.46, 0.74, 0.54);
    line(0.38, 0.48, 0.33, 0.78);
    line(0.33, 0.78, 0.45, 0.78);
    line(0.74, 0.54, 0.88, 0.78);
    line(0.74, 0.54, 0.78, 0.80);
    line(0.14, 0.82, 0.92, 0.82);
  }

  void _drawLunge(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final d = t;
    circle(0.50, 0.22 + d * 0.04, 0.06);
    line(0.50, 0.29 + d * 0.04, 0.50, 0.52 + d * 0.10);
    line(0.50, 0.38, 0.34, 0.48);
    line(0.50, 0.38, 0.66, 0.48);
    line(0.50, 0.52 + d * 0.10, 0.34, 0.64 + d * 0.08);
    line(0.34, 0.64 + d * 0.08, 0.24, 0.86);
    line(0.50, 0.52 + d * 0.10, 0.68, 0.70);
    line(0.68, 0.70, 0.82, 0.86);
    line(0.16, 0.88, 0.88, 0.88);
  }

  void _drawDeadlift(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final bend = t;
    circle(0.50 + bend * 0.06, 0.21 + bend * 0.08, 0.06);
    line(0.50, 0.29 + bend * 0.08, 0.58 + bend * 0.12, 0.53 + bend * 0.05);
    line(0.56, 0.40 + bend * 0.05, 0.34, 0.62 + bend * 0.10);
    line(0.60, 0.41 + bend * 0.06, 0.70, 0.62 + bend * 0.10);
    line(0.58 + bend * 0.12, 0.53 + bend * 0.05, 0.42, 0.86);
    line(0.58 + bend * 0.12, 0.53 + bend * 0.05, 0.70, 0.86);
    line(0.25, 0.72 + bend * 0.12, 0.78, 0.72 + bend * 0.12);
    line(0.16, 0.88, 0.88, 0.88);
  }

  void _drawCrunch(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t;
    circle(0.35 + up * 0.08, 0.58 - up * 0.12, 0.055);
    line(0.40 + up * 0.08, 0.62 - up * 0.10, 0.62, 0.70);
    line(0.48, 0.67, 0.36, 0.75);
    line(0.48, 0.67, 0.36, 0.63);
    line(0.62, 0.70, 0.78, 0.78);
    line(0.62, 0.70, 0.80, 0.68);
    line(0.18, 0.82, 0.88, 0.82);
  }

  void _drawJumpingJack(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final open = t;
    circle(0.50, 0.22, 0.06);
    line(0.50, 0.29, 0.50, 0.55);
    line(0.50, 0.37, 0.35 - open * 0.12, 0.46 - open * 0.22);
    line(0.50, 0.37, 0.65 + open * 0.12, 0.46 - open * 0.22);
    line(0.50, 0.55, 0.42 - open * 0.18, 0.86);
    line(0.50, 0.55, 0.58 + open * 0.18, 0.86);
    line(0.18, 0.88, 0.88, 0.88);
  }

  void _drawPullUp(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t;
    line(0.22, 0.16, 0.78, 0.16);
    circle(0.50, 0.39 - up * 0.12, 0.06);
    line(0.50, 0.45 - up * 0.12, 0.50, 0.68 - up * 0.08);
    line(0.50, 0.48 - up * 0.12, 0.34, 0.18 + up * 0.04);
    line(0.50, 0.48 - up * 0.12, 0.66, 0.18 + up * 0.04);
    line(0.50, 0.68 - up * 0.08, 0.42, 0.86);
    line(0.50, 0.68 - up * 0.08, 0.58, 0.86);
  }

  void _drawShoulderPress(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final press = t;
    circle(0.50, 0.26, 0.06);
    line(0.50, 0.33, 0.50, 0.58);
    line(0.50, 0.40, 0.34, 0.42 - press * 0.22);
    line(0.50, 0.40, 0.66, 0.42 - press * 0.22);
    line(0.34, 0.42 - press * 0.22, 0.30, 0.38 - press * 0.26);
    line(0.66, 0.42 - press * 0.22, 0.70, 0.38 - press * 0.26);
    line(0.50, 0.58, 0.40, 0.86);
    line(0.50, 0.58, 0.60, 0.86);
    line(0.16, 0.88, 0.88, 0.88);
  }

  void _drawBicepCurl(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final curl = t;
    circle(0.50, 0.24, 0.06);
    line(0.50, 0.31, 0.50, 0.58);
    line(0.50, 0.40, 0.35, 0.52);
    line(0.35, 0.52, 0.30 + curl * 0.10, 0.68 - curl * 0.22);
    line(0.50, 0.40, 0.65, 0.52);
    line(0.65, 0.52, 0.70 - curl * 0.10, 0.68 - curl * 0.22);
    line(0.50, 0.58, 0.42, 0.86);
    line(0.50, 0.58, 0.58, 0.86);
    line(0.16, 0.88, 0.88, 0.88);
  }

  void _drawBurpee(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    if (t < 0.5) {
      final d = t * 2;
      circle(0.50, 0.22 + d * 0.15, 0.055);
      line(0.50, 0.30 + d * 0.15, 0.50, 0.55 + d * 0.12);
      line(0.50, 0.42 + d * 0.12, 0.35, 0.58 + d * 0.12);
      line(0.50, 0.42 + d * 0.12, 0.65, 0.58 + d * 0.12);
      line(0.50, 0.55 + d * 0.12, 0.36, 0.86);
      line(0.50, 0.55 + d * 0.12, 0.64, 0.86);
    } else {
      final d = (t - 0.5) * 2;
      circle(0.22, 0.48 - d * 0.06, 0.05);
      line(0.28, 0.50 - d * 0.06, 0.72, 0.58 - d * 0.10);
      line(0.39, 0.52 - d * 0.06, 0.34, 0.82);
      line(0.72, 0.58 - d * 0.10, 0.86, 0.82);
    }
    line(0.14, 0.88, 0.92, 0.88);
  }

  void _drawMountainClimber(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final swap = t;
    circle(0.22, 0.42, 0.05);
    line(0.28, 0.45, 0.70, 0.54);
    line(0.38, 0.47, 0.32, 0.80);
    line(0.38, 0.47, 0.45, 0.80);
    line(0.70, 0.54, 0.50 + swap * 0.18, 0.80);
    line(0.70, 0.54, 0.86 - swap * 0.22, 0.80);
    line(0.14, 0.84, 0.92, 0.84);
  }


  void _drawHipThrust(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t;
    circle(0.28, 0.58 - up * 0.08, 0.055);
    line(0.34, 0.60 - up * 0.08, 0.68, 0.62 - up * 0.18);
    line(0.68, 0.62 - up * 0.18, 0.82, 0.78);
    line(0.68, 0.62 - up * 0.18, 0.50, 0.78);
    line(0.38, 0.62 - up * 0.08, 0.28, 0.78);
    line(0.18, 0.80, 0.90, 0.80);
  }

  void _drawCalfRaise(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t * 0.06;
    circle(0.50, 0.23 - up, 0.06);
    line(0.50, 0.30 - up, 0.50, 0.58 - up);
    line(0.50, 0.40 - up, 0.35, 0.52 - up);
    line(0.50, 0.40 - up, 0.65, 0.52 - up);
    line(0.50, 0.58 - up, 0.43, 0.86 - up);
    line(0.50, 0.58 - up, 0.57, 0.86 - up);
    line(0.18, 0.88, 0.88, 0.88);
  }

  void _drawBenchPress(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final press = t;
    line(0.18, 0.74, 0.84, 0.74);
    circle(0.30, 0.60, 0.055);
    line(0.36, 0.62, 0.70, 0.62);
    line(0.48, 0.62, 0.42, 0.48 - press * 0.18);
    line(0.58, 0.62, 0.64, 0.48 - press * 0.18);
    line(0.30, 0.42 - press * 0.18, 0.76, 0.42 - press * 0.18);
    line(0.70, 0.62, 0.82, 0.72);
  }

  void _drawDips(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final down = t * 0.12;
    line(0.28, 0.36, 0.28, 0.84);
    line(0.72, 0.36, 0.72, 0.84);
    circle(0.50, 0.25 + down, 0.055);
    line(0.50, 0.32 + down, 0.50, 0.58 + down);
    line(0.50, 0.42 + down, 0.28, 0.42);
    line(0.50, 0.42 + down, 0.72, 0.42);
    line(0.50, 0.58 + down, 0.43, 0.82);
    line(0.50, 0.58 + down, 0.57, 0.82);
  }

  void _drawRow(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final pull = t;
    circle(0.42, 0.32, 0.055);
    line(0.46, 0.38, 0.62, 0.60);
    line(0.50, 0.45, 0.32 + pull * 0.12, 0.65 - pull * 0.10);
    line(0.54, 0.48, 0.74 - pull * 0.12, 0.65 - pull * 0.10);
    line(0.62, 0.60, 0.44, 0.86);
    line(0.62, 0.60, 0.72, 0.86);
    line(0.22, 0.72, 0.82, 0.72);
  }

  void _drawLateralRaise(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t;
    circle(0.50, 0.24, 0.06);
    line(0.50, 0.31, 0.50, 0.58);
    line(0.50, 0.40, 0.35 - up * 0.12, 0.58 - up * 0.22);
    line(0.50, 0.40, 0.65 + up * 0.12, 0.58 - up * 0.22);
    line(0.50, 0.58, 0.42, 0.86);
    line(0.50, 0.58, 0.58, 0.86);
    line(0.16, 0.88, 0.88, 0.88);
  }

  void _drawTricepsExtension(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final extend = t;
    circle(0.50, 0.24, 0.06);
    line(0.50, 0.31, 0.50, 0.58);
    line(0.50, 0.38, 0.38, 0.44);
    line(0.38, 0.44, 0.34, 0.62 - extend * 0.22);
    line(0.50, 0.38, 0.62, 0.44);
    line(0.62, 0.44, 0.66, 0.62 - extend * 0.22);
    line(0.50, 0.58, 0.42, 0.86);
    line(0.50, 0.58, 0.58, 0.86);
  }

  void _drawLegRaise(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final up = t;
    circle(0.22, 0.68, 0.052);
    line(0.28, 0.70, 0.60, 0.72);
    line(0.42, 0.72, 0.34, 0.62);
    line(0.60, 0.72, 0.82, 0.72 - up * 0.36);
    line(0.60, 0.72, 0.78, 0.78 - up * 0.32);
    line(0.14, 0.82, 0.90, 0.82);
  }

  void _drawRussianTwist(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final twist = (t - 0.5) * 0.22;
    circle(0.50 + twist, 0.32, 0.055);
    line(0.50 + twist, 0.39, 0.50 - twist, 0.62);
    line(0.50 - twist, 0.48, 0.32 + twist, 0.58);
    line(0.50 - twist, 0.48, 0.68 + twist, 0.58);
    line(0.50 - twist, 0.62, 0.38, 0.82);
    line(0.50 - twist, 0.62, 0.68, 0.82);
  }

  void _drawHollowHold(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final lift = t * 0.08;
    circle(0.25, 0.60 - lift, 0.052);
    line(0.31, 0.62 - lift, 0.58, 0.68 - lift);
    line(0.34, 0.62 - lift, 0.18, 0.48 - lift);
    line(0.58, 0.68 - lift, 0.84, 0.55 - lift);
    line(0.14, 0.82, 0.90, 0.82);
  }

  void _drawHighKnees(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    final swap = t;
    circle(0.50, 0.22, 0.06);
    line(0.50, 0.29, 0.50, 0.56);
    line(0.50, 0.38, 0.36 + swap * 0.12, 0.50);
    line(0.50, 0.38, 0.64 - swap * 0.12, 0.50);
    line(0.50, 0.56, 0.36 + swap * 0.18, 0.72 - swap * 0.18);
    line(0.36 + swap * 0.18, 0.72 - swap * 0.18, 0.30, 0.88);
    line(0.50, 0.56, 0.66 - swap * 0.18, 0.88);
  }

  void _drawRun(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    _drawHighKnees(line, circle, joint, s);
    line(0.14, 0.88, 0.92, 0.88);
  }

  void _drawBike(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    circle(0.32, 0.76, 0.13);
    circle(0.72, 0.76, 0.13);
    line(0.32, 0.76, 0.50, 0.56);
    line(0.50, 0.56, 0.72, 0.76);
    line(0.45, 0.50, 0.60, 0.50);
    circle(0.52, 0.30, 0.05);
    line(0.52, 0.36, 0.50, 0.56);
    line(0.50, 0.44, 0.64, 0.50);
    line(0.50, 0.56, 0.44, 0.74);
    line(0.50, 0.56, 0.62, 0.70);
  }

  void _drawGeneric(void Function(double, double, double, double) line, void Function(double, double, double, {PaintingStyle style}) circle, void Function(double, double) joint, double s) {
    circle(0.50, 0.23, 0.06);
    line(0.50, 0.30, 0.50, 0.58);
    line(0.50, 0.40, 0.34 + t * 0.08, 0.52 - t * 0.08);
    line(0.50, 0.40, 0.66 - t * 0.08, 0.52 - t * 0.08);
    line(0.50, 0.58, 0.40 + t * 0.07, 0.86);
    line(0.50, 0.58, 0.60 - t * 0.07, 0.86);
    line(0.16, 0.88, 0.88, 0.88);
  }

  @override
  bool shouldRepaint(covariant ExercisePainter oldDelegate) => oldDelegate.t != t || oldDelegate.type != type || oldDelegate.lineColor != lineColor || oldDelegate.backgroundColor != backgroundColor;
}
