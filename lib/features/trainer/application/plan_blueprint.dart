/// Budowa zestawu z „planu na zestaw" (blueprint) — czysty Dart.
///
/// Etap: „Nowa opcja tworzenia własnego zestawu" (tryby A/B/C).
///
/// [PlanBlueprint] to komplet odpowiedzi z kreatora: cel, priorytetowe partie,
/// liczba dni, dostępny czas, sprzęt, preferencje i zakres pomocy AI.
/// [buildPlanFromBlueprint] zamienia to na gotowy [WorkoutPlan] — deterministycznie,
/// z realnej bazy ćwiczeń, z poszanowaniem sprzętu, ograniczeń i limitów objętości.
///
/// Ten sam builder obsługuje tryb „w całości przez AI" (pełny blueprint) oraz
/// „ręcznie z pomocą AI" (uzupełnia WYŁĄCZNIE zaznaczone zakresy — patrz
/// `plan_ai_advisor.dart`).
library;

import 'dart:math' as math;

import '../domain/equipment_profile.dart';
import '../domain/exercise.dart';
import '../domain/trainer_enums.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_volume_limits.dart';
import 'equipment_program_filter.dart';
import 'plan_quality_analyzer.dart';

/// Preferowany podział tygodnia.
enum PlanSplitStyle {
  auto('auto', 'Dobierz automatycznie'),
  fullBody('fullBody', 'Full Body'),
  upperLower('upperLower', 'Upper / Lower'),
  pushPullLegs('pushPullLegs', 'Push / Pull / Legs'),
  bodyPart('bodyPart', 'Podział na partie');

  const PlanSplitStyle(this.key, this.label);

  final String key;
  final String label;

  static PlanSplitStyle fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final style in PlanSplitStyle.values) {
      if (style.key == key || style.name == key) return style;
    }
    return PlanSplitStyle.auto;
  }
}

/// Jak mocno wybrane partie mają rządzić zestawem.
///
/// To pytanie rozstrzyga sytuację, która wcześniej myliła użytkowników:
/// zaznaczenie „Core" nie może kończyć się zestawem pełnym pompek i przysiadów.
enum PlanFocusScope {
  onlySelected(
    'onlySelected',
    'Tylko wybrane partie',
    'Zestaw ćwiczy wyłącznie zaznaczone partie — nic poza nimi.',
  ),
  priorityFirst(
    'priorityFirst',
    'Priorytet + uzupełnienie',
    'Wybrane partie dostają najwięcej pracy, reszta ciała mniej.',
  ),
  balanced(
    'balanced',
    'Całe ciało równomiernie',
    'Wszystkie partie traktowane tak samo.',
  );

  const PlanFocusScope(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PlanFocusScope fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final scope in PlanFocusScope.values) {
      if (scope.key == key || scope.name == key) return scope;
    }
    return PlanFocusScope.balanced;
  }
}

/// Preferowana długość przerw między seriami.
enum PlanRestPreference {
  auto('auto', 'Dobierz automatycznie', 0),
  short('short', 'Krótkie (~45 s)', 45),
  medium('medium', 'Średnie (~90 s)', 90),
  long('long', 'Długie (~150 s)', 150);

  const PlanRestPreference(this.key, this.label, this.seconds);

  final String key;
  final String label;

  /// 0 = zostaw decyzję automatowi (cel + typ ćwiczenia).
  final int seconds;

  static PlanRestPreference fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final item in PlanRestPreference.values) {
      if (item.key == key || item.name == key) return item;
    }
    return PlanRestPreference.auto;
  }
}

/// Cel zestawu wybierany w kroku 1 kreatora.
enum PlanPurpose {
  muscle('muscle', 'Masa mięśniowa', 'Masa'),
  strength('strength', 'Siła', 'Siła'),
  fatLoss('fatLoss', 'Redukcja', 'Redukcja'),
  recomposition('recomposition', 'Rekompozycja', 'Sylwetka'),
  conditioning('conditioning', 'Kondycja', 'Kondycja'),
  mobility('mobility', 'Mobilność', 'Sylwetka'),
  generalFitness('generalFitness', 'Ogólna sprawność', 'Sylwetka'),
  comeback('comeback', 'Powrót po przerwie', 'Sylwetka'),
  recovery('recovery', 'Trening regeneracyjny', 'Sylwetka'),
  custom('custom', 'Własny cel', 'Sylwetka');

  const PlanPurpose(this.key, this.label, this.planGoal);

  final String key;
  final String label;

  /// Odpowiadający cel planu w dotychczasowym słowniku ([workoutPlanGoals]).
  final String planGoal;

  static PlanPurpose fromKey(Object? value) {
    final key = value?.toString().trim() ?? '';
    for (final purpose in PlanPurpose.values) {
      if (purpose.key == key || purpose.name == key) return purpose;
    }
    return PlanPurpose.recomposition;
  }
}

/// Komplet decyzji użytkownika z kreatora zestawu.
class PlanBlueprint {
  const PlanBlueprint({
    this.name = '',
    this.purpose = PlanPurpose.recomposition,
    this.customPurposeText = '',
    this.priorityMuscles = const <MuscleGroup>[],
    this.focusScope = PlanFocusScope.balanced,
    this.restPreference = PlanRestPreference.auto,
    this.exercisesPerDay = 0,
    this.daysPerWeek = 3,
    this.weekdays = const <int>[],
    this.flexibleSchedule = true,
    this.minutesPerSession = 45,
    this.equipment = const EquipmentProfile(),
    this.limitations = const LimitationProfile(),
    this.preferredExerciseIds = const <String>[],
    this.excludedExerciseIds = const <String>[],
    this.intensity = WorkoutIntensityLevel.moderate,
    this.split = PlanSplitStyle.auto,
    this.includeCardio = false,
    this.includeWarmup = true,
    this.includeCooldown = true,
    this.includeMobility = false,
    this.level = 'Średniozaawansowany',
    this.aiScopes = const <AiAssistanceScope>{},
    this.creationMode = PlanCreationMode.manual,
  });

  final String name;
  final PlanPurpose purpose;
  final String customPurposeText;

  /// Partie priorytetowe. Pusta lista = całe ciało.
  final List<MuscleGroup> priorityMuscles;

  /// Jak mocno [priorityMuscles] mają zawężać zestaw.
  final PlanFocusScope focusScope;

  /// Preferowana długość przerw (0 = automat na podstawie celu i ćwiczenia).
  final PlanRestPreference restPreference;

  /// Ręcznie narzucona liczba ćwiczeń na dzień (0 = wylicz z dostępnego czasu).
  final int exercisesPerDay;

  final int daysPerWeek;

  /// Konkretne dni tygodnia (1=pn…7=nd). Pusta lista + [flexibleSchedule]
  /// = plan elastyczny bez przypisania do dni kalendarza.
  final List<int> weekdays;
  final bool flexibleSchedule;

  final int minutesPerSession;
  final EquipmentProfile equipment;
  final LimitationProfile limitations;
  final List<String> preferredExerciseIds;
  final List<String> excludedExerciseIds;
  final WorkoutIntensityLevel intensity;
  final PlanSplitStyle split;
  final bool includeCardio;
  final bool includeWarmup;
  final bool includeCooldown;
  final bool includeMobility;
  final String level;

  /// Zakres, w jakim użytkownik dopuścił pomoc AI (tryb „ręcznie z AI").
  final Set<AiAssistanceScope> aiScopes;

  final PlanCreationMode creationMode;

  /// Cel planu w słowniku aplikacji.
  String get planGoal => purpose.planGoal;

  /// Tekstowy opis celu — trafia do notatki zestawu.
  String get purposeText => purpose == PlanPurpose.custom &&
          customPurposeText.trim().isNotEmpty
      ? customPurposeText.trim()
      : purpose.label;

  PlanBlueprint copyWith({
    String? name,
    PlanPurpose? purpose,
    String? customPurposeText,
    List<MuscleGroup>? priorityMuscles,
    PlanFocusScope? focusScope,
    PlanRestPreference? restPreference,
    int? exercisesPerDay,
    int? daysPerWeek,
    List<int>? weekdays,
    bool? flexibleSchedule,
    int? minutesPerSession,
    EquipmentProfile? equipment,
    LimitationProfile? limitations,
    List<String>? preferredExerciseIds,
    List<String>? excludedExerciseIds,
    WorkoutIntensityLevel? intensity,
    PlanSplitStyle? split,
    bool? includeCardio,
    bool? includeWarmup,
    bool? includeCooldown,
    bool? includeMobility,
    String? level,
    Set<AiAssistanceScope>? aiScopes,
    PlanCreationMode? creationMode,
  }) {
    return PlanBlueprint(
      name: name ?? this.name,
      purpose: purpose ?? this.purpose,
      customPurposeText: customPurposeText ?? this.customPurposeText,
      priorityMuscles: priorityMuscles ?? this.priorityMuscles,
      focusScope: focusScope ?? this.focusScope,
      restPreference: restPreference ?? this.restPreference,
      exercisesPerDay: exercisesPerDay ?? this.exercisesPerDay,
      daysPerWeek: daysPerWeek ?? this.daysPerWeek,
      weekdays: weekdays ?? this.weekdays,
      flexibleSchedule: flexibleSchedule ?? this.flexibleSchedule,
      minutesPerSession: minutesPerSession ?? this.minutesPerSession,
      equipment: equipment ?? this.equipment,
      limitations: limitations ?? this.limitations,
      preferredExerciseIds: preferredExerciseIds ?? this.preferredExerciseIds,
      excludedExerciseIds: excludedExerciseIds ?? this.excludedExerciseIds,
      intensity: intensity ?? this.intensity,
      split: split ?? this.split,
      includeCardio: includeCardio ?? this.includeCardio,
      includeWarmup: includeWarmup ?? this.includeWarmup,
      includeCooldown: includeCooldown ?? this.includeCooldown,
      includeMobility: includeMobility ?? this.includeMobility,
      level: level ?? this.level,
      aiScopes: aiScopes ?? this.aiScopes,
      creationMode: creationMode ?? this.creationMode,
    );
  }

  /// Efektywny podział — „auto" rozstrzygamy liczbą dni i priorytetami.
  PlanSplitStyle get effectiveSplit {
    // Zestaw zawężony do wybranych partii nie jest ani Push/Pull, ani Upper/
    // Lower — każdy dzień pracuje na tych samych grupach.
    if (focusScope == PlanFocusScope.onlySelected &&
        priorityMuscles.isNotEmpty) {
      return PlanSplitStyle.bodyPart;
    }
    if (split != PlanSplitStyle.auto) return split;
    if (daysPerWeek <= 2) return PlanSplitStyle.fullBody;
    if (daysPerWeek == 3) {
      return priorityMuscles.isEmpty
          ? PlanSplitStyle.fullBody
          : PlanSplitStyle.pushPullLegs;
    }
    if (daysPerWeek == 4) return PlanSplitStyle.upperLower;
    return PlanSplitStyle.pushPullLegs;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'purpose': purpose.key,
        if (customPurposeText.isNotEmpty)
          'customPurposeText': customPurposeText,
        'priorityMuscles': priorityMuscles.map((m) => m.name).toList(),
        'focusScope': focusScope.key,
        'restPreference': restPreference.key,
        if (exercisesPerDay > 0) 'exercisesPerDay': exercisesPerDay,
        'daysPerWeek': daysPerWeek,
        'weekdays': weekdays,
        'flexibleSchedule': flexibleSchedule,
        'minutesPerSession': minutesPerSession,
        'equipment': equipment.toJson(),
        'limitationFlags': limitations.flags.map((f) => f.key).toList(),
        'preferredExerciseIds': preferredExerciseIds,
        'excludedExerciseIds': excludedExerciseIds,
        'intensity': intensity.key,
        'split': split.key,
        'includeCardio': includeCardio,
        'includeWarmup': includeWarmup,
        'includeCooldown': includeCooldown,
        'includeMobility': includeMobility,
        'level': level,
        'aiScopes': aiScopes.map((s) => s.key).toList(),
        'creationMode': creationMode.key,
      };
}

/// Nazwy dni dla poszczególnych podziałów.
const Map<PlanSplitStyle, List<String>> _kSplitDayTitles = {
  PlanSplitStyle.fullBody: ['Całe ciało A', 'Całe ciało B', 'Całe ciało C'],
  PlanSplitStyle.upperLower: ['Góra A', 'Dół A', 'Góra B', 'Dół B'],
  PlanSplitStyle.pushPullLegs: ['Push', 'Pull', 'Nogi'],
  PlanSplitStyle.bodyPart: [
    'Klatka i triceps',
    'Plecy i biceps',
    'Nogi',
    'Barki i core',
  ],
};

/// Partie, na których skupia się dany typ dnia.
const Map<String, List<MuscleGroup>> _kDayFocus = {
  'Push': [MuscleGroup.chest, MuscleGroup.shoulders, MuscleGroup.triceps],
  'Pull': [MuscleGroup.back, MuscleGroup.biceps, MuscleGroup.forearms],
  'Nogi': [
    MuscleGroup.quadriceps,
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.calves,
  ],
  'Góra A': [
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.triceps,
  ],
  'Góra B': [
    MuscleGroup.back,
    MuscleGroup.chest,
    MuscleGroup.biceps,
    MuscleGroup.shoulders,
  ],
  'Dół A': [
    MuscleGroup.quadriceps,
    MuscleGroup.glutes,
    MuscleGroup.hamstrings,
    MuscleGroup.core,
  ],
  'Dół B': [
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.quadriceps,
    MuscleGroup.calves,
  ],
  'Całe ciało A': [
    MuscleGroup.quadriceps,
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.core,
  ],
  'Całe ciało B': [
    MuscleGroup.hamstrings,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.core,
  ],
  'Całe ciało C': [
    MuscleGroup.glutes,
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.core,
  ],
  'Klatka i triceps': [MuscleGroup.chest, MuscleGroup.triceps],
  'Plecy i biceps': [MuscleGroup.back, MuscleGroup.biceps],
  'Barki i core': [MuscleGroup.shoulders, MuscleGroup.core],
};

/// Wynik budowy zestawu — plan + czytelne uzasadnienie decyzji.
class BuiltPlan {
  const BuiltPlan({
    required this.plan,
    required this.decisions,
    this.unavailablePriorities = const <MuscleGroup>[],
  });

  final WorkoutPlan plan;

  /// Krótkie zdania „dlaczego tak" — pokazywane w podglądzie przed zapisem.
  final List<String> decisions;

  /// Partie priorytetowe, których nie dało się obsłużyć dostępnym sprzętem.
  final List<MuscleGroup> unavailablePriorities;
}

/// Buduje kompletny zestaw z blueprintu.
///
/// [library_] to pełna baza ćwiczeń (wbudowane + własne użytkownika).
/// [planId] pozwala nadać stabilny identyfikator (testy, ponowne generowanie).
BuiltPlan buildPlanFromBlueprint(
  PlanBlueprint blueprint, {
  required List<Exercise> library_,
  required String planId,
  DateTime? now,
  String createdByUserId = '',
  String sourceConversationId = '',
  VolumeLimitsConfig volumeLimits = VolumeLimitsConfig.standard,
}) {
  final timestamp = now ?? DateTime.now();
  final owned = blueprint.equipment.resolveOwned();
  final excluded = blueprint.excludedExerciseIds.toSet();
  final decisions = <String>[];

  // Pula ćwiczeń: dostępny sprzęt, brak kolizji z ograniczeniami, poziom
  // nie wyższy niż o jeden stopień ponad użytkownika, bez wykluczonych.
  final userRank = trainingLevelRank(blueprint.level);
  final pool = <Exercise>[
    for (final exercise in library_)
      if (!excluded.contains(exercise.id) &&
          isExerciseAvailable(exercise, owned) &&
          !exerciseViolatesLimitation(exercise, blueprint.limitations) &&
          trainingLevelRank(exercise.level) <= userRank + 1)
        exercise,
  ];
  decisions.add('Pula ćwiczeń: ${pool.length} pozycji pasujących do sprzętu '
      '(${blueprint.equipment.ownedSummary}) i Twojego poziomu.');

  final split = blueprint.effectiveSplit;
  final dayTitles =
      _resolveDayTitles(split, blueprint.daysPerWeek, blueprint: blueprint);
  if (blueprint.focusScope == PlanFocusScope.onlySelected &&
      blueprint.priorityMuscles.isNotEmpty) {
    decisions.add('Zakres: TYLKO wybrane partie '
        '(${blueprint.priorityMuscles.map((g) => g.label.toLowerCase()).join(', ')}) '
        '— nic poza nimi nie trafia do zestawu.');
  } else {
    decisions.add('Podział: ${split.label} na ${blueprint.daysPerWeek} '
        '${_dayWord(blueprint.daysPerWeek)} w tygodniu.');
  }

  // Ile ćwiczeń zmieści się w dostępnym czasie (rozgrzewka/schłodzenie osobno).
  final workMinutes = (blueprint.minutesPerSession -
          (blueprint.includeWarmup ? 6 : 0) -
          (blueprint.includeCooldown ? 5 : 0))
      .clamp(10, 180);
  final targetExercises = _targetExerciseCount(
    workMinutes,
    blueprint.intensity,
    override: blueprint.exercisesPerDay,
  );
  decisions.add(blueprint.exercisesPerDay > 0
      ? 'Ręcznie ustawione $targetExercises '
          '${_exerciseWord(targetExercises)} na dzień.'
      : 'Czas $workMinutes min pracy → około $targetExercises '
          '${_exerciseWord(targetExercises)} na dzień.');

  final weekdays = _resolveWeekdays(blueprint, dayTitles.length);
  final usedGlobally = <String>{};
  final days = <WorkoutDay>[];
  final unavailablePriorities = <MuscleGroup>{};

  for (var index = 0; index < dayTitles.length; index++) {
    final title = dayTitles[index];
    final focus = _focusForDay(title, blueprint);
    final items = <PlanItem>[];
    final usedInDay = <String>{};

    // Najpierw ćwiczenia PREFEROWANE przez użytkownika, które pasują do dnia.
    for (final id in blueprint.preferredExerciseIds) {
      if (items.length >= targetExercises) break;
      if (usedInDay.contains(id)) continue;
      final matches = pool.where((e) => e.id == id);
      if (matches.isEmpty) continue;
      final exercise = matches.first;
      final group = primaryMuscleGroupOf(exercise);
      if (!focus.contains(group) && focus.isNotEmpty) continue;
      if (items.length >= targetExercises) break;
      items.add(_itemFor(exercise, blueprint, volumeLimits));
      usedInDay.add(id);
      usedGlobally.add(id);
    }

    // Potem kolejne partie dnia — po jednym najlepszym ruchu na partię,
    // dokładając kolejne rundy, dopóki mieścimy się w czasie.
    // Liczba rund musi rosnąć, gdy partii jest mało — zestaw „tylko brzuch"
    // ma jedną grupę, a i tak powinien uzbierać komplet ćwiczeń.
    final maxRounds = focus.isEmpty
        ? 0
        : math.max(3, (targetExercises / focus.length).ceil() + 1);
    var round = 0;
    while (items.length < targetExercises && round < maxRounds) {
      for (final group in focus) {
        if (items.length >= targetExercises) break;
        final candidate = _pickExercise(
          pool: pool,
          group: group,
          usedInDay: usedInDay,
          usedGlobally: usedGlobally,
          preferCompound: round == 0,
          level: blueprint.level,
        );
        if (candidate == null) {
          if (round == 0 && blueprint.priorityMuscles.contains(group)) {
            unavailablePriorities.add(group);
          }
          continue;
        }
        items.add(_itemFor(candidate, blueprint, volumeLimits));
        usedInDay.add(candidate.id);
        usedGlobally.add(candidate.id);
      }
      round++;
    }

    // Mobilność / cardio jako dopięcie dnia, gdy użytkownik o to poprosił.
    if (blueprint.includeMobility && items.length < targetExercises + 1) {
      final mobility = _pickByPredicate(
        pool,
        usedInDay,
        (e) => e.entryType == ExerciseEntryType.mobility,
      );
      if (mobility != null) {
        items.add(_itemFor(mobility, blueprint, volumeLimits));
        usedInDay.add(mobility.id);
      }
    }
    if (blueprint.includeCardio && index.isEven) {
      final cardio = _pickByPredicate(
        pool,
        usedInDay,
        (e) => primaryMuscleGroupOf(e) == MuscleGroup.cardio,
      );
      if (cardio != null) {
        items.add(_itemFor(cardio, blueprint, volumeLimits));
        usedInDay.add(cardio.id);
      }
    }

    // Kolejność: najpierw ruchy złożone, na końcu izolacja i core.
    items.sort((a, b) {
      final left = _orderRank(_resolveFromPool(pool, a.exerciseId));
      final right = _orderRank(_resolveFromPool(pool, b.exerciseId));
      return left.compareTo(right);
    });

    days.add(WorkoutDay(
      weekday: weekdays[index],
      title: title,
      items: items,
      kind: WorkoutDayKind.strength,
    ));
  }

  if (unavailablePriorities.isNotEmpty) {
    decisions.add('Uwaga: dla partii '
        '${unavailablePriorities.map((g) => g.label.toLowerCase()).join(', ')} '
        'nie znalazłem ćwiczeń pasujących do Twojego sprzętu.');
  }
  if (blueprint.includeWarmup) {
    decisions.add('Rozgrzewkę prowadzi osobny moduł rozgrzewek — nie zajmuje '
        'miejsca w dniu treningowym.');
  }

  final planName = blueprint.name.trim().isNotEmpty
      ? blueprint.name.trim()
      : _defaultName(blueprint);

  final plan = WorkoutPlan(
    id: planId,
    name: planName,
    days: days,
    note: 'Cel: ${blueprint.purposeText}. Intensywność: '
        '${blueprint.intensity.label.toLowerCase()}. '
        'Czas sesji: ${blueprint.minutesPerSession} min.',
    goal: blueprint.planGoal,
    level: blueprint.level,
    allowAnyDay: blueprint.flexibleSchedule,
    origin: PlanOrigin(
      creationMode: blueprint.creationMode,
      aiAssistanceScopes: blueprint.aiScopes,
      sourceType: blueprint.creationMode == PlanCreationMode.manual
          ? PlanSourceType.manual
          : PlanSourceType.wizard,
      createdAt: timestamp,
      updatedAt: timestamp,
      createdByUserId: createdByUserId,
      sourceConversationId: sourceConversationId,
      aiEngine: blueprint.creationMode.isAiInvolved ? 'Trener AI' : '',
    ),
  );

  return BuiltPlan(
    plan: plan,
    decisions: decisions,
    unavailablePriorities: unavailablePriorities.toList(),
  );
}

/// Tworzy pusty zestaw pod tryb w pełni ręczny — użytkownik sam dokłada dni
/// i ćwiczenia, nic nie jest za niego wybierane.
WorkoutPlan buildEmptyManualPlan(
  PlanBlueprint blueprint, {
  required String planId,
  DateTime? now,
  String createdByUserId = '',
}) {
  final timestamp = now ?? DateTime.now();
  final titles = _resolveDayTitles(
    blueprint.split == PlanSplitStyle.auto
        ? PlanSplitStyle.fullBody
        : blueprint.split,
    blueprint.daysPerWeek,
    blueprint: blueprint,
  );
  final weekdays = _resolveWeekdays(blueprint, titles.length);
  return WorkoutPlan(
    id: planId,
    name: blueprint.name.trim().isNotEmpty
        ? blueprint.name.trim()
        : _defaultName(blueprint),
    days: [
      for (var index = 0; index < titles.length; index++)
        WorkoutDay(
          weekday: weekdays[index],
          title: titles[index],
          items: const <PlanItem>[],
          kind: WorkoutDayKind.strength,
        ),
    ],
    note: 'Cel: ${blueprint.purposeText}.',
    goal: blueprint.planGoal,
    level: blueprint.level,
    allowAnyDay: blueprint.flexibleSchedule,
    // Szkielet dni powstaje też w trybie „ręcznie z pomocą AI" (gdy użytkownik
    // NIE zlecił AI dobierania ćwiczeń) — tryb i zakres pomocy muszą wtedy
    // zostać zapisane zgodnie z jego wyborem, a nie zawsze jako „ręczny".
    origin: PlanOrigin(
      creationMode: blueprint.creationMode == PlanCreationMode.fullyAiGenerated
          ? PlanCreationMode.manualWithAi
          : blueprint.creationMode,
      aiAssistanceScopes: blueprint.aiScopes,
      sourceType: blueprint.creationMode == PlanCreationMode.manual
          ? PlanSourceType.manual
          : PlanSourceType.wizard,
      createdAt: timestamp,
      updatedAt: timestamp,
      createdByUserId: createdByUserId,
      aiEngine: blueprint.creationMode.isAiInvolved ? 'Trener AI' : '',
    ),
  );
}

// ============================================================================
// Pomocnicze
// ============================================================================

List<String> _resolveDayTitles(
  PlanSplitStyle split,
  int days, {
  PlanBlueprint? blueprint,
}) {
  final count = days.clamp(1, 7);

  // Zestaw zawężony do wybranych partii dostaje nazwy dni OD TYCH PARTII —
  // „Push" w zestawie na brzuch byłby mylący.
  final priorities = blueprint?.priorityMuscles ?? const <MuscleGroup>[];
  if (blueprint?.focusScope == PlanFocusScope.onlySelected &&
      priorities.isNotEmpty) {
    final label = priorities.length <= 2
        ? priorities.map((group) => group.label).join(' i ')
        : 'Wybrane partie';
    if (count == 1) return <String>[label];
    return <String>[
      for (var i = 0; i < count; i++)
        '$label ${String.fromCharCode(65 + (i % 26))}',
    ];
  }

  final base =
      _kSplitDayTitles[split] ?? _kSplitDayTitles[PlanSplitStyle.fullBody]!;
  final titles = <String>[];
  for (var i = 0; i < count; i++) {
    final label = base[i % base.length];
    // Przy powtórzeniu cyklu dokładamy numer, żeby dni miały różne nazwy.
    final repeat = i ~/ base.length;
    titles.add(repeat == 0 ? label : '$label ${repeat + 1}');
  }
  return titles;
}

List<int> _resolveWeekdays(PlanBlueprint blueprint, int dayCount) {
  if (blueprint.weekdays.isNotEmpty) {
    final sorted = blueprint.weekdays.toSet().toList()..sort();
    return [
      for (var i = 0; i < dayCount; i++) sorted[i % sorted.length],
    ];
  }
  // Rozkład domyślny: rozłożone równomiernie w tygodniu (pn, śr, pt, …).
  const spread = {
    1: [1],
    2: [1, 4],
    3: [1, 3, 5],
    4: [1, 2, 4, 5],
    5: [1, 2, 3, 5, 6],
    6: [1, 2, 3, 4, 5, 6],
    7: [1, 2, 3, 4, 5, 6, 7],
  };
  final chosen = spread[dayCount.clamp(1, 7)] ?? const [1, 3, 5];
  return [for (var i = 0; i < dayCount; i++) chosen[i % chosen.length]];
}

List<MuscleGroup> _focusForDay(String title, PlanBlueprint blueprint) {
  final priorities = blueprint.priorityMuscles;

  // „Tylko wybrane partie" ZAWĘŻA zestaw do zaznaczonych grup. Bez tego
  // zaznaczenie „Core" kończyło się dniem pełnym pompek i przysiadów, bo
  // priorytety jedynie przestawiały kolejność partii z podziału.
  if (blueprint.focusScope == PlanFocusScope.onlySelected &&
      priorities.isNotEmpty) {
    return List<MuscleGroup>.of(priorities);
  }

  final base = _kDayFocus[title] ??
      _kDayFocus[title.replaceAll(RegExp(r' \d+$'), '')] ??
      const <MuscleGroup>[
        MuscleGroup.chest,
        MuscleGroup.back,
        MuscleGroup.quadriceps,
        MuscleGroup.core,
      ];
  if (priorities.isEmpty || blueprint.focusScope == PlanFocusScope.balanced) {
    return base;
  }

  // „Priorytet + uzupełnienie": wybrane partie wchodzą ZAWSZE (nawet gdy dany
  // dzień ich nie obejmuje) i idą pierwsze, reszta dnia zostaje jako dodatek.
  final ordered = <MuscleGroup>[
    ...priorities,
    ...base.where((group) => !priorities.contains(group)),
  ];
  return ordered;
}

int _targetExerciseCount(
  int workMinutes,
  WorkoutIntensityLevel intensity, {
  int override = 0,
}) {
  // Ręczne ustawienie użytkownika wygrywa z wyliczeniem z czasu.
  if (override > 0) return override.clamp(1, 12);
  // ~7 min na ćwiczenie przy umiarkowanej intensywności (serie + przerwy).
  final perExercise = switch (intensity) {
    WorkoutIntensityLevel.light => 5,
    WorkoutIntensityLevel.moderate => 7,
    WorkoutIntensityLevel.high => 8,
    WorkoutIntensityLevel.veryHigh => 9,
  };
  return (workMinutes ~/ perExercise).clamp(2, 9);
}

Exercise? _pickExercise({
  required List<Exercise> pool,
  required MuscleGroup group,
  required Set<String> usedInDay,
  required Set<String> usedGlobally,
  required bool preferCompound,
  required String level,
}) {
  final candidates = pool
      .where((e) =>
          !usedInDay.contains(e.id) && primaryMuscleGroupOf(e) == group)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    // 1. Złożone przed izolacją (albo odwrotnie w kolejnych rundach).
    final compoundA = _isCompound(a) ? 0 : 1;
    final compoundB = _isCompound(b) ? 0 : 1;
    final compound =
        preferCompound ? compoundA.compareTo(compoundB) : compoundB.compareTo(compoundA);
    if (compound != 0) return compound;
    // 2. Nieużyte w innych dniach mają pierwszeństwo (różnorodność zestawu).
    final freshA = usedGlobally.contains(a.id) ? 1 : 0;
    final freshB = usedGlobally.contains(b.id) ? 1 : 0;
    if (freshA != freshB) return freshA.compareTo(freshB);
    // 3. Poziom bliżej użytkownika.
    final rank = trainingLevelRank(level);
    final distA = (trainingLevelRank(a.level) - rank).abs();
    final distB = (trainingLevelRank(b.level) - rank).abs();
    if (distA != distB) return distA.compareTo(distB);
    return a.name.compareTo(b.name);
  });
  return candidates.first;
}

Exercise? _pickByPredicate(
  List<Exercise> pool,
  Set<String> usedInDay,
  bool Function(Exercise) test,
) {
  for (final exercise in pool) {
    if (usedInDay.contains(exercise.id)) continue;
    if (test(exercise)) return exercise;
  }
  return null;
}

bool _isCompound(Exercise exercise) {
  final pattern = movementPatternOf(exercise);
  return pattern != MovementPattern.core &&
      pattern != MovementPattern.carryOrOther &&
      exercise.effectiveMuscleImpacts.length > 1;
}

int _orderRank(Exercise? exercise) {
  if (exercise == null) return 5;
  final pattern = movementPatternOf(exercise);
  if (pattern == MovementPattern.squat ||
      pattern == MovementPattern.hinge) {
    return 0;
  }
  if (pattern == MovementPattern.horizontalPush ||
      pattern == MovementPattern.verticalPull) {
    return 1;
  }
  if (pattern == MovementPattern.horizontalPull ||
      pattern == MovementPattern.verticalPush) {
    return 2;
  }
  if (pattern == MovementPattern.lunge) return 3;
  if (_isCompound(exercise)) return 4;
  if (pattern == MovementPattern.core) return 6;
  return 5;
}

Exercise? _resolveFromPool(List<Exercise> pool, String id) {
  for (final exercise in pool) {
    if (exercise.id == id) return exercise;
  }
  return null;
}

/// Parametry pojedynczej pozycji: serie/powtórzenia/czas/przerwa z limitów
/// objętości, celu i intensywności. Ciężar zostaje 0 — dobiera go dopiero
/// automatyczny system prowadzenia (`recommendSet`) na podstawie historii.
PlanItem _itemFor(
  Exercise exercise,
  PlanBlueprint blueprint,
  VolumeLimitsConfig config,
) {
  final group = primaryMuscleGroupOf(exercise);
  final limits = volumeLimitsFor(
    group,
    level: blueprint.level,
    goal: blueprint.planGoal,
    config: config,
    intensity: blueprint.intensity,
  );
  final entryType = exercise.entryType;
  final sets = ((limits.sets.min + limits.sets.max) / 2).round().clamp(1, 8);

  if (entryType.showsDuration && !entryType.showsReps) {
    final duration = exercise.defaultDurationSec > 0
        ? exercise.defaultDurationSec
        : 40;
    return PlanItem(
      exerciseId: exercise.id,
      sets: sets,
      reps: 0,
      durationSec: duration,
      note: '',
      restSeconds: entryType == ExerciseEntryType.mobility ? 30 : 60,
    );
  }

  final reps = ((limits.reps.min + limits.reps.max) / 2).round().clamp(1, 40);
  final rest = _restFor(exercise, blueprint);
  return PlanItem(
    exerciseId: exercise.id,
    sets: sets,
    reps: reps,
    durationSec: 0,
    note: '',
    restSeconds: rest,
  );
}

int _restFor(Exercise exercise, PlanBlueprint blueprint) {
  // Jawny wybór użytkownika wygrywa z automatem — poza mobilnością, gdzie
  // długa przerwa nie ma sensu.
  if (blueprint.restPreference != PlanRestPreference.auto &&
      exercise.entryType != ExerciseEntryType.mobility) {
    return blueprint.restPreference.seconds;
  }
  final compound = _isCompound(exercise);
  final base = switch (blueprint.purpose) {
    PlanPurpose.strength => compound ? 180 : 120,
    PlanPurpose.muscle => compound ? 120 : 90,
    PlanPurpose.fatLoss || PlanPurpose.conditioning => compound ? 75 : 45,
    PlanPurpose.mobility || PlanPurpose.recovery => 30,
    _ => compound ? 105 : 75,
  };
  return base;
}

String _defaultName(PlanBlueprint blueprint) {
  final priorities = blueprint.priorityMuscles;
  if (priorities.length == 1) {
    return '${priorities.first.label} — ${blueprint.purpose.label}';
  }
  if (blueprint.focusScope == PlanFocusScope.onlySelected &&
      priorities.length == 2) {
    return '${priorities.map((g) => g.label).join(' i ')} — '
        '${blueprint.purpose.label}';
  }
  return '${blueprint.effectiveSplit.label} — ${blueprint.purpose.label}';
}

String _dayWord(int count) {
  if (count == 1) return 'dzień';
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'dni';
  return 'dni';
}

String _exerciseWord(int count) {
  if (count == 1) return 'ćwiczenie';
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'ćwiczenia';
  }
  return 'ćwiczeń';
}
