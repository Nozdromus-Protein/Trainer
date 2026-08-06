import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/exercise_duplicate_detector.dart';
import 'package:licznik_treningu/features/trainer/application/plan_ai_advisor.dart';
import 'package:licznik_treningu/features/trainer/application/plan_blueprint.dart';
import 'package:licznik_treningu/features/trainer/application/equipment_program_filter.dart';
import 'package:licznik_treningu/features/trainer/application/plan_quality_analyzer.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/ai_structured_reply.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise _exercise({
  required String id,
  required String name,
  required List<String> muscles,
  String equipment = 'masa ciała',
  String level = 'Początkujący',
  int defaultDurationSec = 0,
  String illustrationType = 'generic',
}) {
  return Exercise(
    id: id,
    name: name,
    category: muscles.first,
    muscles: muscles,
    equipment: equipment,
    level: level,
    illustrationType: illustrationType,
    description: '',
    tips: const [],
    commonMistakes: const [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: defaultDurationSec,
    met: 4.5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Metadane pochodzenia zestawu', () {
    test('nowy zestaw serializuje i odczytuje pełny PlanOrigin', () {
      final now = DateTime(2026, 8, 5, 12, 30);
      final plan = WorkoutPlan(
        id: 'p1',
        name: 'Mój Push',
        days: const [],
        note: '',
        origin: PlanOrigin(
          creationMode: PlanCreationMode.manualWithAi,
          aiAssistanceScopes: const {
            AiAssistanceScope.setsAndReps,
            AiAssistanceScope.rest,
          },
          sourceType: PlanSourceType.aiChat,
          createdAt: now,
          updatedAt: now,
          createdByUserId: 'user-1',
          sourceConversationId: 'conv-9',
          sourceMessageId: 'msg-4',
          version: 3,
          isFavorite: true,
          lastUsedAt: now,
          basePlanId: 'base-1',
          basePlanName: 'Push bazowy',
        ),
      );

      final restored = WorkoutPlan.fromJson(plan.toJson());

      expect(restored.origin.creationMode, PlanCreationMode.manualWithAi);
      expect(restored.origin.aiAssisted, isTrue);
      expect(restored.origin.aiAssistanceScopes,
          {AiAssistanceScope.setsAndReps, AiAssistanceScope.rest});
      expect(restored.origin.sourceType, PlanSourceType.aiChat);
      expect(restored.origin.sourceConversationId, 'conv-9');
      expect(restored.origin.sourceMessageId, 'msg-4');
      expect(restored.origin.version, 3);
      expect(restored.origin.isFavorite, isTrue);
      expect(restored.origin.createdByUserId, 'user-1');
      expect(restored.origin.isPersonalizedVariant, isTrue);
      expect(restored.origin.basePlanName, 'Push bazowy');
    });

    test('starszy zapis bez pola origin dostaje tryb legacy, nie losowy', () {
      // Dokładnie taki JSON zapisywały wcześniejsze wersje aplikacji.
      final legacyJson = <String, dynamic>{
        'id': 'stary-plan',
        'name': 'Plan sprzed migracji',
        'note': 'Zapisany przed etapem własnych zestawów.',
        'goal': 'Masa',
        'isActive': true,
        'completedDays': [0, 1],
        'days': [
          {
            'weekday': 1,
            'title': 'Dzień 1',
            'items': [
              {
                'exerciseId': 'pushup',
                'sets': 3,
                'reps': 12,
                'durationSec': 0,
                'note': '',
              },
            ],
          },
        ],
      };

      final plan = WorkoutPlan.fromJson(legacyJson);

      expect(plan.origin.creationMode, PlanCreationMode.legacy);
      // Cała dotychczasowa treść i postęp przetrwały odczyt.
      expect(plan.name, 'Plan sprzed migracji');
      expect(plan.completedDays, {0, 1});
      expect(plan.days.single.items.single.exerciseId, 'pushup');
      expect(plan.versions, isEmpty);
    });

    test('migawka wersji odtwarza dokładnie tę samą treść dni', () {
      const plan = WorkoutPlan(
        id: 'p2',
        name: 'Wersjonowany',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'A', items: [
            PlanItem(
                exerciseId: 'squat',
                sets: 4,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final snapshot = PlanVersionSnapshot(
        version: 1,
        label: 'Przed zmianą',
        createdAt: DateTime(2026, 8, 1),
        planJson: plan.toJson(),
      );
      final decoded = PlanVersionSnapshot.fromJson(snapshot.toJson());
      expect(decoded, isNotNull);
      final restored = WorkoutPlan.fromJson(decoded!.planJson);
      expect(restored.days.single.items.single.sets, 4);
      expect(restored.days.single.items.single.reps, 8);
    });
  });

  group('Strukturalna odpowiedź Trenera AI', () {
    test('parsuje listę ćwiczeń z pełnymi polami', () {
      final reply = TrainerAiStructuredReply.parse(
        {
          'message': 'Oto propozycje na klatkę:',
          'confidence': 88,
          'reasoningSummary': 'Sprzęt: hantle i ławka.',
          'warnings': ['Triceps ma niską regenerację.'],
          'exerciseSuggestions': [
            {
              'name': 'Wyciskanie hantli na ławce',
              'exerciseId': 'db_bench_press',
              'primaryMuscles': ['klatka'],
              'secondaryMuscles': ['triceps', 'przedni bark'],
              'equipment': 'hantle i ławka',
              'difficulty': 'średni',
              'reasonRecommended': 'Pasuje do Twojego sprzętu.',
              'recoveryCompatibility': 'good',
              'confidence': 0.9,
            },
          ],
        },
        fallbackMessage: 'nieużyte',
      );

      expect(reply.message, 'Oto propozycje na klatkę:');
      // Pewność podana jako procent zamienia się na 0..1.
      expect(reply.confidence, closeTo(0.88, 0.001));
      expect(reply.warnings.single, contains('Triceps'));
      expect(reply.exerciseSuggestions, hasLength(1));
      final suggestion = reply.exerciseSuggestions.single;
      expect(suggestion.name, 'Wyciskanie hantli na ławce');
      expect(suggestion.exerciseId, 'db_bench_press');
      expect(suggestion.secondaryMuscles, ['triceps', 'przedni bark']);
      expect(
          suggestion.recoveryCompatibility, AiRecoveryCompatibility.good);
      expect(reply.hasStructuredData, isTrue);
    });

    test('backend bez struktury → sam tekst, czat nadal działa', () {
      final reply = TrainerAiStructuredReply.parse(
        {'reply': 'Dziś odpocznij.'},
        fallbackMessage: 'Dziś odpocznij.',
      );
      expect(reply.message, 'Dziś odpocznij.');
      expect(reply.exerciseSuggestions, isEmpty);
      expect(reply.hasStructuredData, isFalse);
    });

    test('błąd/śmieci w odpowiedzi nie wywracają parsera', () {
      final fromString = TrainerAiStructuredReply.parse(
        'to nie jest mapa',
        fallbackMessage: 'zapasowa treść',
      );
      expect(fromString.message, 'zapasowa treść');
      expect(fromString.exerciseSuggestions, isEmpty);

      final broken = TrainerAiStructuredReply.parse(
        {
          'message': 'ok',
          'exerciseSuggestions': [
            {'brak_nazwy': true}, // odrzucone
            'Pompki', // sama nazwa → nadal użyteczna karta
            42, // ignorowane
          ],
        },
        fallbackMessage: '',
      );
      expect(broken.exerciseSuggestions, hasLength(1));
      expect(broken.exerciseSuggestions.single.name, 'Pompki');
      expect(broken.exerciseSuggestions.single.hasAnyDetail, isFalse);
    });

    test('duplikaty kart w odpowiedzi są scalane', () {
      final reply = TrainerAiStructuredReply.parse(
        {
          'exerciseSuggestions': [
            {'name': 'Pompki', 'exerciseId': 'pushup'},
            {'name': 'Pompki', 'exerciseId': 'pushup'},
          ],
        },
        fallbackMessage: '',
      );
      expect(reply.exerciseSuggestions, hasLength(1));
    });
  });

  group('Analiza jakości zestawu', () {
    final library = [
      _exercise(
          id: 'bench',
          name: 'Wyciskanie sztangi',
          muscles: ['klatka piersiowa', 'triceps'],
          equipment: 'sztanga, ławka'),
      _exercise(
          id: 'row',
          name: 'Wiosłowanie sztangą',
          muscles: ['plecy', 'biceps'],
          equipment: 'sztanga'),
      _exercise(
          id: 'squat2',
          name: 'Przysiad ze sztangą',
          muscles: ['czworogłowe uda', 'pośladki'],
          equipment: 'sztanga, stojaki'),
      _exercise(
          id: 'curl',
          name: 'Uginanie ramion',
          muscles: ['biceps'],
          equipment: 'hantle'),
    ];
    Exercise resolve(String id) =>
        library.firstWhere((e) => e.id == id, orElse: () => library.first);

    test('wykrywa powtórzone ćwiczenie w dniu', () {
      const plan = WorkoutPlan(
        id: 'q1',
        name: 'Test',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final report = analyzePlanQuality(
        plan,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
      );
      expect(
        report.issues.any((note) => note.text.contains('powtarza się')),
        isTrue,
      );
      expect(report.score, lessThan(100));
    });

    test('wykrywa ćwiczenie wymagające niedostępnego sprzętu', () {
      const plan = WorkoutPlan(
        id: 'q2',
        name: 'Test',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final report = analyzePlanQuality(
        plan,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.bodyweight),
      );
      expect(
        report.issues.any((note) =>
            note.severity == PlanNoteSeverity.critical &&
            note.text.contains('sprzętu')),
        isTrue,
      );
    });

    test('wykrywa brak ćwiczenia na wybrany priorytet', () {
      const plan = WorkoutPlan(
        id: 'q3',
        name: 'Test',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'row',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final report = analyzePlanQuality(
        plan,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        priorityMuscles: const [MuscleGroup.glutes],
      );
      expect(
        report.issues.any((note) => note.text.contains('priorytet')),
        isTrue,
      );
    });

    test('zbalansowany zestaw dostaje zaletę Push/Pull i wyższą ocenę', () {
      const balanced = WorkoutPlan(
        id: 'q4',
        name: 'Test',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Full', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'row',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'squat2',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final report = analyzePlanQuality(
        balanced,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
      );
      expect(
        report.strengths.any((note) => note.text.contains('Push/Pull')),
        isTrue,
      );
      expect(report.totalExercises, 3);
      expect(report.totalSets, 9);
      expect(report.estimatedMinutes, greaterThan(0));
    });

    test('rozpoznaje wzorce ruchowe i zgłasza brakujące', () {
      expect(
        movementPatternOf(_exercise(
            id: 'x', name: 'Podciąganie', muscles: ['plecy'])),
        MovementPattern.verticalPull,
      );
      expect(
        movementPatternOf(_exercise(
            id: 'x', name: 'Martwy ciąg', muscles: ['dwugłowe uda'])),
        MovementPattern.hinge,
      );
      expect(
        movementPatternOf(
            _exercise(id: 'x', name: 'Pompki', muscles: ['klatka'])),
        MovementPattern.horizontalPush,
      );

      const pushOnly = WorkoutPlan(
        id: 'q5',
        name: 'Test',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'curl',
                sets: 3,
                reps: 10,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'bench',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'curl',
                sets: 3,
                reps: 10,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final report = analyzePlanQuality(
        pushOnly,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
      );
      expect(report.missingPatterns, contains(MovementPattern.squat));
      expect(report.missingPatterns, contains(MovementPattern.hinge));
    });
  });

  group('Wykrywanie duplikatów ćwiczeń', () {
    final library = [
      _exercise(id: 'pushup', name: 'Pompki', muscles: ['klatka piersiowa']),
      _exercise(
          id: 'bench',
          name: 'Wyciskanie sztangi',
          muscles: ['klatka piersiowa'],
          equipment: 'sztanga, ławka'),
    ];

    test('identyczna nazwa = dopasowanie dokładne', () {
      final matches =
          findExerciseDuplicates(name: 'pompki', library_: library);
      expect(matches, isNotEmpty);
      expect(matches.first.strength, DuplicateMatchStrength.exact);
      expect(hasLikelyDuplicate(matches), isTrue);
    });

    test('ten sam identyfikator = dopasowanie dokładne', () {
      final matches = findExerciseDuplicates(
        name: 'Zupełnie inna nazwa',
        exerciseId: 'bench',
        library_: library,
      );
      expect(matches.first.strength, DuplicateMatchStrength.exact);
      expect(matches.first.exercise.id, 'bench');
    });

    test('nazwa zawierająca się w innej = dopasowanie mocne', () {
      final matches = findExerciseDuplicates(
        name: 'Wyciskanie sztangi leżąc',
        library_: library,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.strength, DuplicateMatchStrength.strong);
    });

    test('zupełnie nowe ćwiczenie nie zgłasza duplikatu', () {
      final matches = findExerciseDuplicates(
        name: 'Wypychanie ciężaru nogami',
        library_: library,
        muscles: const ['czworogłowe uda'],
      );
      expect(hasLikelyDuplicate(matches), isFalse);
    });
  });

  group('Budowa zestawu z blueprintu', () {
    final library = [
      _exercise(
          id: 'bench',
          name: 'Wyciskanie sztangi',
          muscles: ['klatka piersiowa', 'triceps'],
          equipment: 'sztanga, ławka'),
      _exercise(
          id: 'pushup', name: 'Pompki', muscles: ['klatka piersiowa']),
      _exercise(
          id: 'row_db',
          name: 'Wiosłowanie hantlem',
          muscles: ['plecy', 'biceps'],
          equipment: 'hantle'),
      _exercise(
          id: 'goblet',
          name: 'Goblet squat',
          muscles: ['czworogłowe uda', 'pośladki'],
          equipment: 'hantel'),
      _exercise(
          id: 'ohp_db',
          name: 'Wyciskanie hantli nad głowę',
          muscles: ['barki', 'triceps'],
          equipment: 'hantle'),
      _exercise(id: 'plank', name: 'Deska', muscles: ['brzuch'],
          defaultDurationSec: 45),
      _exercise(id: 'crunch', name: 'Brzuszki', muscles: ['brzuch']),
      _exercise(id: 'leg_raise', name: 'Unoszenie nóg', muscles: ['brzuch']),
      _exercise(id: 'russian', name: 'Russian twist', muscles: ['brzuch']),
      _exercise(
          id: 'curl_db',
          name: 'Uginanie ramion z hantlami',
          muscles: ['biceps'],
          equipment: 'hantle'),
      _exercise(
          id: 'rdl',
          name: 'Martwy ciąg na prostych nogach',
          muscles: ['dwugłowe uda', 'pośladki'],
          equipment: 'hantle'),
    ];

    test('respektuje sprzęt: bez sztangi nie wchodzi wyciskanie sztangi', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          daysPerWeek: 2,
          minutesPerSession: 45,
          equipment: EquipmentProfile(
            mode: EquipmentMode.custom,
            customOwned: {EquipmentType.dumbbell},
          ),
          creationMode: PlanCreationMode.fullyAiGenerated,
        ),
        library_: library,
        planId: 'built-1',
      );
      final ids = <String>{
        for (final day in built.plan.days)
          for (final item in day.items) item.exerciseId,
      };
      expect(ids, isNot(contains('bench')));
      expect(built.plan.days, hasLength(2));
      expect(built.plan.origin.creationMode,
          PlanCreationMode.fullyAiGenerated);
      expect(built.plan.origin.aiGenerated, isTrue);
      expect(built.decisions, isNotEmpty);
    });

    test('respektuje wykluczone ćwiczenia', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          daysPerWeek: 3,
          excludedExerciseIds: ['pushup', 'bench'],
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'built-2',
      );
      final ids = <String>{
        for (final day in built.plan.days)
          for (final item in day.items) item.exerciseId,
      };
      expect(ids, isNot(contains('pushup')));
      expect(ids, isNot(contains('bench')));
    });

    test('krótszy czas sesji = mniej ćwiczeń na dzień', () {
      const base = PlanBlueprint(
        daysPerWeek: 1,
        equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
      );
      final short = buildPlanFromBlueprint(
        base.copyWith(minutesPerSession: 20),
        library_: library,
        planId: 'short',
      );
      final long = buildPlanFromBlueprint(
        base.copyWith(minutesPerSession: 90),
        library_: library,
        planId: 'long',
      );
      expect(short.plan.days.single.items.length,
          lessThan(long.plan.days.single.items.length));
    });

    test('ZAKRES „tylko wybrane partie" nie wpuszcza obcych ćwiczeń', () {
      // Zgłoszony błąd: użytkownik wybrał Core, a dostawał pompki i przysiady,
      // bo priorytety jedynie przestawiały kolejność partii z podziału.
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          name: 'Ćwiczenia na brzuch',
          priorityMuscles: [MuscleGroup.core],
          focusScope: PlanFocusScope.onlySelected,
          daysPerWeek: 3,
          minutesPerSession: 45,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'core-only',
      );

      final groups = <MuscleGroup>{
        for (final day in built.plan.days)
          for (final item in day.items)
            primaryMuscleGroupOf(
              library.firstWhere((e) => e.id == item.exerciseId),
            ),
      };
      expect(groups, {MuscleGroup.core});

      final ids = <String>{
        for (final day in built.plan.days)
          for (final item in day.items) item.exerciseId,
      };
      expect(ids, isNot(contains('pushup')));
      expect(ids, isNot(contains('bench')));
      expect(ids, isNot(contains('goblet')));
      // Nazwy dni idą za partią, nie za podziałem Push/Pull.
      expect(built.plan.days.first.title, contains('Core'));
      expect(
        built.decisions.any((line) => line.contains('TYLKO wybrane partie')),
        isTrue,
      );
    });

    test('ZAKRES „priorytet + uzupełnienie" zostawia resztę ciała', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          priorityMuscles: [MuscleGroup.core],
          focusScope: PlanFocusScope.priorityFirst,
          daysPerWeek: 1,
          minutesPerSession: 60,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'core-first',
      );
      final groups = <MuscleGroup>{
        for (final item in built.plan.days.single.items)
          primaryMuscleGroupOf(
            library.firstWhere((e) => e.id == item.exerciseId),
          ),
      };
      expect(groups, contains(MuscleGroup.core));
      expect(groups.length, greaterThan(1));
    });

    test('ZAKRES „całe ciało" ignoruje priorytety w doborze partii', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          priorityMuscles: [MuscleGroup.core],
          focusScope: PlanFocusScope.balanced,
          daysPerWeek: 1,
          minutesPerSession: 60,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'balanced',
      );
      final groups = <MuscleGroup>{
        for (final item in built.plan.days.single.items)
          primaryMuscleGroupOf(
            library.firstWhere((e) => e.id == item.exerciseId),
          ),
      };
      expect(groups.length, greaterThan(1));
    });

    test('ręcznie ustawiona liczba ćwiczeń wygrywa z wyliczeniem z czasu', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          daysPerWeek: 1,
          minutesPerSession: 90,
          exercisesPerDay: 3,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'fixed-count',
      );
      expect(built.plan.days.single.items, hasLength(3));
    });

    test('preferencja przerw nadpisuje automat', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          daysPerWeek: 1,
          minutesPerSession: 45,
          restPreference: PlanRestPreference.short,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'short-rest',
      );
      final rests =
          built.plan.days.single.items.map((item) => item.restSeconds).toSet();
      expect(rests, {PlanRestPreference.short.seconds});
    });

    test('tryb ręczny tworzy pusty szkielet dni bez ćwiczeń', () {
      final plan = buildEmptyManualPlan(
        const PlanBlueprint(daysPerWeek: 3, name: 'Mój plan'),
        planId: 'manual-1',
      );
      expect(plan.days, hasLength(3));
      expect(plan.days.every((day) => day.items.isEmpty), isTrue);
      expect(plan.origin.creationMode, PlanCreationMode.manual);
      expect(plan.origin.createdManually, isTrue);
      expect(plan.name, 'Mój plan');
    });

    test('priorytety trafiają na początek listy partii dnia', () {
      final built = buildPlanFromBlueprint(
        const PlanBlueprint(
          daysPerWeek: 1,
          minutesPerSession: 30,
          priorityMuscles: [MuscleGroup.back],
          // Priorytety działają na dobór partii tylko wtedy, gdy zakres na to
          // pozwala — „całe ciało równomiernie" celowo je ignoruje.
          focusScope: PlanFocusScope.priorityFirst,
          split: PlanSplitStyle.fullBody,
          equipment: EquipmentProfile(mode: EquipmentMode.fullGym),
        ),
        library_: library,
        planId: 'prio',
      );
      final ids =
          built.plan.days.single.items.map((item) => item.exerciseId).toList();
      expect(ids, contains('row_db'));
    });
  });

  group('Doradca AI — propozycje zmian', () {
    final library = [
      _exercise(
          id: 'bench',
          name: 'Wyciskanie sztangi',
          muscles: ['klatka piersiowa', 'triceps'],
          equipment: 'sztanga, ławka'),
      _exercise(
          id: 'pushup', name: 'Pompki', muscles: ['klatka piersiowa']),
      _exercise(
          id: 'row_db',
          name: 'Wiosłowanie hantlem',
          muscles: ['plecy', 'biceps'],
          equipment: 'hantle'),
      _exercise(
          id: 'goblet',
          name: 'Goblet squat',
          muscles: ['czworogłowe uda'],
          equipment: 'hantel'),
    ];
    Exercise resolve(String id) =>
        library.firstWhere((e) => e.id == id, orElse: () => library.first);

    const plan = WorkoutPlan(
      id: 'a1',
      name: 'Push testowy',
      note: '',
      days: [
        WorkoutDay(weekday: 1, title: 'Push', items: [
          PlanItem(
              exerciseId: 'bench',
              sets: 1,
              reps: 8,
              durationSec: 0,
              note: '',
              restSeconds: 300),
          PlanItem(
              exerciseId: 'row_db',
              sets: 3,
              reps: 12,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );

    test('bez sprzętu proponuje ZAMIANĘ, nie usunięcie ćwiczenia', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.equipmentCheck},
        equipment: const EquipmentProfile(mode: EquipmentMode.bodyweight),
      );
      final swaps = result.proposals
          .where((p) => p.kind == PlanChangeKind.swapExercise)
          .toList();
      expect(swaps, isNotEmpty);
      expect(swaps.first.exerciseId, 'bench');
      expect(swaps.first.reason, contains('sprzęt'));
      expect(
        result.proposals.any((p) => p.kind == PlanChangeKind.removeExercise),
        isFalse,
      );
    });

    test('zablokowane ćwiczenie NIE trafia do propozycji zamiany', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.equipmentCheck},
        equipment: const EquipmentProfile(mode: EquipmentMode.bodyweight),
        lockedExerciseIds: const {'bench'},
      );
      expect(
        result.proposals.any((p) => p.exerciseId == 'bench'),
        isFalse,
      );
    });

    test('zakres ogranicza AI — bez scope „rest" nie ma zmian przerw', () {
      final withRest = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.rest},
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        goal: 'Redukcja',
      );
      expect(
        withRest.proposals.any((p) => p.kind == PlanChangeKind.adjustRest),
        isTrue,
      );

      final withoutRest = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.exerciseOrder},
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        goal: 'Redukcja',
      );
      expect(
        withoutRest.proposals.any((p) => p.kind == PlanChangeKind.adjustRest),
        isFalse,
      );
    });

    test('propozycje serii są oznaczone jako bezpieczne', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.setsAndReps},
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Średniozaawansowany',
        goal: 'Masa',
      );
      final setProposals = result.proposals
          .where((p) => p.kind == PlanChangeKind.adjustSets)
          .toList();
      expect(setProposals, isNotEmpty);
      expect(setProposals.every((p) => p.isSafe), isTrue);
      expect(result.safeProposals, isNotEmpty);
    });

    test('akceptacja pojedynczej zmiany zmienia TYLKO ją', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.setsAndReps},
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Średniozaawansowany',
        goal: 'Masa',
      );
      final first = result.proposals
          .firstWhere((p) => p.kind == PlanChangeKind.adjustSets);
      final applied = applyPlanProposals(
        plan,
        [first],
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
      );
      final changed = applied.plan.days.single.items
          .firstWhere((item) => item.exerciseId == first.exerciseId);
      expect(changed.sets, first.newSets);
      // Reszta zestawu bez zmian.
      expect(applied.plan.days.single.items.length, 2);
      expect(applied.diff.setChanges, hasLength(1));
      expect(applied.diff.removedExercises, isEmpty);
    });

    test('blokada wygrywa nawet gdy propozycja trafi do akceptacji', () {
      const proposal = PlanChangeProposal(
        id: 'x',
        kind: PlanChangeKind.removeExercise,
        dayIndex: 0,
        exerciseId: 'bench',
        title: 'Usuń',
        reason: 'test',
      );
      final applied = applyPlanProposals(
        plan,
        const [proposal],
        resolve: resolve,
        lockedExerciseIds: const {'bench'},
      );
      expect(
        applied.plan.days.single.items.any((i) => i.exerciseId == 'bench'),
        isTrue,
      );
      expect(applied.diff.removedExercises, isEmpty);
    });

    test('rozpoczęty program: dni sprzed currentDayIndex są nietykalne', () {
      const started = WorkoutPlan(
        id: 'a2',
        name: 'Rozpoczęty',
        note: '',
        completedDays: {0},
        days: [
          WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 1,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
          WorkoutDay(weekday: 2, title: 'Dzień 2', items: [
            PlanItem(
                exerciseId: 'bench',
                sets: 1,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      final result = analyzePlanForUser(
        started,
        resolve: resolve,
        library_: library,
        scopes: const {AiAssistanceScope.setsAndReps},
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Średniozaawansowany',
        goal: 'Masa',
        fromDayIndex: started.currentDayIndex,
      );
      expect(result.proposals.every((p) => p.dayIndex >= 1), isTrue);

      // Nawet gdyby propozycja dotyczyła dnia 0, apply ją odrzuci.
      const sneaky = PlanChangeProposal(
        id: 'sneaky',
        kind: PlanChangeKind.removeExercise,
        dayIndex: 0,
        exerciseId: 'bench',
        title: 'Usuń z ukończonego dnia',
        reason: 'test',
      );
      final applied = applyPlanProposals(
        started,
        const [sneaky],
        resolve: resolve,
        fromDayIndex: 1,
      );
      expect(applied.plan.days.first.items, hasLength(1));
    });

    test('porównanie przed/po zawiera realne różnice', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        scopes: const {
          AiAssistanceScope.setsAndReps,
          AiAssistanceScope.fillMissingExercises,
        },
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Średniozaawansowany',
        goal: 'Masa',
      );
      final applied = applyPlanProposals(
        plan,
        result.proposals,
        resolve: resolve,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Średniozaawansowany',
        goal: 'Masa',
      );
      expect(applied.diff.before.totalSets,
          isNot(equals(applied.diff.after.totalSets)));
      expect(applied.diff.setDelta, isNot(0));
    });

    test('podstawa analizy i pewność są raportowane', () {
      final result = analyzePlanForUser(
        plan,
        resolve: resolve,
        library_: library,
        equipment: const EquipmentProfile(mode: EquipmentMode.fullGym),
        level: 'Zaawansowany',
        goal: 'Masa',
        availableMinutes: 60,
        hasHistory: false,
      );
      expect(result.basis, contains('poziom: zaawansowany'));
      expect(result.basis, contains('dostępny czas: 60 min'));
      expect(result.confidence, lessThan(1.0));
      expect(result.limitedAccuracyReason, contains('brakuje historii'));
    });
  });

  group('AppStore — zestawy i pochodzenie', () {
    test('migracja starszych zestawów nadaje tryb wg realnego źródła',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      // Zestaw własny (bez origin) + program katalogowy (bez origin).
      store.plans
        ..clear()
        ..add(WorkoutPlan.fromJson({
          'id': 'wlasny-plan',
          'name': 'Mój stary plan',
          'note': '',
          'days': [],
        }))
        ..add(WorkoutPlan.fromJson({
          'id': '${kWorkoutProgramCatalog.first.id}_123',
          'name': kWorkoutProgramCatalog.first.title,
          'note': '',
          'days': [],
        }));

      expect(store.plans.every(
          (p) => p.origin.creationMode == PlanCreationMode.legacy), isTrue);

      final changed = store.migrateLegacyPlanOrigins();
      expect(changed, isTrue);
      expect(
        store.plans.firstWhere((p) => p.id == 'wlasny-plan').origin.creationMode,
        PlanCreationMode.manual,
      );
      expect(
        store.plans.last.origin.creationMode,
        PlanCreationMode.systemProgram,
      );

      // Ponowna migracja niczego już nie rusza (idempotencja).
      expect(store.migrateLegacyPlanOrigins(), isFalse);
    });

    test('migracja NIE nadpisuje świadomie nadanego trybu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans
        ..clear()
        ..add(const WorkoutPlan(
          id: 'ai-plan',
          name: 'Wygenerowany',
          note: '',
          days: [],
          origin: PlanOrigin(
              creationMode: PlanCreationMode.fullyAiGenerated),
        ));
      expect(store.migrateLegacyPlanOrigins(), isFalse);
      expect(store.plans.single.origin.creationMode,
          PlanCreationMode.fullyAiGenerated);
    });

    test('ulubione, archiwum i ostatnie użycie zapisują się lokalnie',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-fav',
        name: 'Ulubiony',
        note: '',
        days: [],
        origin: PlanOrigin(creationMode: PlanCreationMode.manual),
      ));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-other',
        name: 'Drugi zestaw',
        note: '',
        days: [],
        origin: PlanOrigin(creationMode: PlanCreationMode.manual),
      ));

      await store.setPlanFavorite('p-fav', true);
      await store.markPlanUsed('p-fav', at: DateTime(2026, 8, 4));
      await store.setPlanArchived('p-fav', true);

      final restored = AppStore();
      await restored.load();
      final plan = restored.plans.firstWhere((p) => p.id == 'p-fav');
      expect(plan.origin.isFavorite, isTrue);
      expect(plan.origin.isArchived, isTrue);
      expect(plan.origin.lastUsedAt, DateTime(2026, 8, 4));
      // Archiwizacja nie może zostawić zestawu aktywnym — także po restarcie
      // aplikacji, gdy naprawiany jest niezmiennik „jeden aktywny zestaw".
      expect(plan.isActive, isFalse);
      expect(
        restored.plans.firstWhere((p) => p.id == 'p-other').isActive,
        isTrue,
      );
    });

    test('wersjonowanie: zapis wersji i przywrócenie treści bez utraty postępu',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-ver',
        name: 'Wersjonowany',
        note: '',
        completedDays: {0},
        days: [
          WorkoutDay(weekday: 1, title: 'A', items: [
            PlanItem(
                exerciseId: 'pushup',
                sets: 3,
                reps: 10,
                durationSec: 0,
                note: ''),
          ]),
        ],
      ));

      await store.savePlanVersion('p-ver', label: 'Wersja bazowa');
      // Zmiana treści po zapisaniu migawki.
      await store.updatePlanDayItems('p-ver', 0, const [
        PlanItem(
            exerciseId: 'squat', sets: 5, reps: 5, durationSec: 0, note: ''),
      ]);
      expect(store.plans.single.days.single.items.single.exerciseId, 'squat');

      final ok = await store.restorePlanVersion('p-ver', 1);
      expect(ok, isTrue);
      expect(store.plans.single.days.single.items.single.exerciseId, 'pushup');
      // Postęp NIE pochodzi z migawki — zostaje bieżący.
      expect(store.plans.single.completedDays, {0});
      // Wersja sprzed cofnięcia też została zachowana.
      expect(store.plans.single.versions.length, greaterThanOrEqualTo(2));
    });

    test('spersonalizowany wariant nie rusza zestawu bazowego', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      const base = WorkoutPlan(
        id: 'base-plan',
        name: 'Push bazowy',
        note: '',
        completedDays: {0, 1},
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'pushup',
                sets: 3,
                reps: 10,
                durationSec: 0,
                note: ''),
          ]),
        ],
      );
      await store.addWorkoutPlan(base);

      final variant = await store.createPersonalizedVariant(
        base,
        name: 'Push — mój wariant AI',
        days: const [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'squat',
                sets: 4,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
        scopes: const {AiAssistanceScope.equipmentCheck},
        reason: 'dopasowanie do sprzętu',
      );

      final original = store.plans.firstWhere((p) => p.id == 'base-plan');
      expect(original.days.single.items.single.exerciseId, 'pushup');
      expect(original.completedDays, {0, 1});
      expect(variant.id, isNot('base-plan'));
      expect(variant.origin.basePlanId, 'base-plan');
      expect(variant.origin.basePlanName, 'Push bazowy');
      expect(variant.origin.creationMode, PlanCreationMode.manualWithAi);
      // Wariant startuje bez fałszywego postępu.
      expect(variant.completedDays, isEmpty);
    });

    test('applyAnalysisToPlan zachowuje postęp i zapisuje poprzednią wersję',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-apply',
        name: 'Program',
        note: '',
        completedDays: {0},
        origin: PlanOrigin(creationMode: PlanCreationMode.systemProgram),
        days: [
          WorkoutDay(weekday: 1, title: 'A', items: []),
          WorkoutDay(weekday: 2, title: 'B', items: []),
        ],
      ));

      await store.applyAnalysisToPlan(
        'p-apply',
        const [
          WorkoutDay(weekday: 1, title: 'A', items: []),
          WorkoutDay(weekday: 2, title: 'B', items: [
            PlanItem(
                exerciseId: 'squat',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
        versionLabel: 'Dopasowanie do profilu',
        reason: 'dodano 1',
        scopes: const {AiAssistanceScope.fillMissingExercises},
      );

      final plan = store.plans.single;
      expect(plan.completedDays, {0});
      expect(plan.days[1].items, hasLength(1));
      expect(plan.versions, hasLength(1));
      expect(plan.origin.version, 2);
      // Program systemowy nie zmienia się w „AI wspomagany" typ zestawu.
      expect(plan.origin.creationMode, PlanCreationMode.systemProgram);
      expect(plan.origin.aiAssistanceScopes,
          contains(AiAssistanceScope.fillMissingExercises));
    });

    test('dodanie ćwiczenia do dnia nie tworzy duplikatu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-add',
        name: 'Zestaw',
        note: '',
        days: [WorkoutDay(weekday: 1, title: 'A', items: [])],
      ));

      final first = await store.addExerciseToPlanDay(
          planId: 'p-add', dayIndex: 0, exerciseId: 'pushup');
      final second = await store.addExerciseToPlanDay(
          planId: 'p-add', dayIndex: 0, exerciseId: 'pushup');

      expect(first, isTrue);
      expect(second, isFalse);
      expect(store.plans.single.days.single.items, hasLength(1));
      // Parametry pochodzą z automatycznego systemu prowadzenia.
      final item = store.plans.single.days.single.items.single;
      expect(item.sets, greaterThan(0));
      expect(item.restSeconds, greaterThan(0));
    });

    test('sugestia AI → szkic ćwiczenia z pełnymi wartościami domyślnymi',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      // Skrajny przypadek: AI podało SAMĄ nazwę.
      final draft = store.exerciseDraftFromSuggestion(
        const AiExerciseSuggestion(name: 'Rozpiętki na bramie'),
        conversationMessageId: 'msg-1',
      );
      expect(draft.name, 'Rozpiętki na bramie');
      expect(draft.muscles, isNotEmpty);
      expect(draft.equipment, isNotEmpty);
      expect(draft.defaultSets, greaterThan(0));
      expect(draft.source, 'ai_chat:msg-1');
      expect(draft.id, startsWith('ai_'));
    });

    test('wzbogacanie sugestii rozpoznaje ćwiczenie z bazy', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      const reply = TrainerAiStructuredReply(
        message: 'ok',
        exerciseSuggestions: [
          AiExerciseSuggestion(name: 'Przysiad'),
          AiExerciseSuggestion(name: 'Zupełnie nowe ćwiczenie XYZ'),
        ],
      );
      final enriched = store.enrichAiSuggestions(reply);
      expect(enriched.exerciseSuggestions, hasLength(2));
      final known = enriched.exerciseSuggestions.first;
      expect(known.alreadyInDatabase, isTrue);
      expect(known.exerciseId, isNotEmpty);
      final unknown = enriched.exerciseSuggestions.last;
      expect(unknown.alreadyInDatabase, isFalse);
    });

    test('lokalne karty ćwiczeń działają offline i respektują sprzęt',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateSettings(store.settings.copyWith(
        equipmentModeKey: EquipmentMode.bodyweight.key,
      ));

      final reply = store.localExerciseSuggestions(
          'Jakie ćwiczenia mogę zrobić na klatkę?');
      expect(reply, isNotNull);
      expect(reply!.exerciseSuggestions, isNotEmpty);
      final owned = store.settings.equipmentProfile.resolveOwned();
      for (final suggestion in reply.exerciseSuggestions) {
        final exercise =
            ExerciseRepo.byId(suggestion.exerciseId, store.customExercises);
        expect(isExerciseAvailable(exercise, owned), isTrue,
            reason: '${exercise.name} wymaga niedostępnego sprzętu');
      }

      // Pytanie spoza tematu nie generuje kart.
      expect(store.localExerciseSuggestions('Czy robię progres?'), isNull);
    });

    test('analiza zestawu przez store działa na realnych danych', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'p-analyze',
        name: 'Zestaw do analizy',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'A', items: [
            PlanItem(
                exerciseId: 'pushup',
                sets: 1,
                reps: 30,
                durationSec: 0,
                note: '',
                restSeconds: 400),
          ]),
        ],
      ));

      final result = store.analyzePlan(store.plans.single);
      expect(result.report.score, inInclusiveRange(0, 100));
      expect(result.basis, isNotEmpty);
      expect(result.confidence, greaterThan(0));

      final quality = store.planQuality(store.plans.single);
      expect(quality.totalExercises, 1);
    });

    test('historia czatu zachowuje karty ćwiczeń po ponownym wczytaniu',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.aiChatHistory.add(AiChatMessage(
        role: 'assistant',
        content: 'Propozycje:',
        timestamp: DateTime(2026, 8, 5),
        messageId: 'msg-77',
        structured: const TrainerAiStructuredReply(
          message: 'Propozycje:',
          exerciseSuggestions: [
            AiExerciseSuggestion(
              name: 'Pompki',
              exerciseId: 'pushup',
              equipment: 'masa ciała',
              alreadyInDatabase: true,
            ),
          ],
        ),
      ));
      await store.saveAiChatHistory();

      final restored = AppStore();
      await restored.load();
      final message = restored.aiChatHistory.last;
      expect(message.messageId, 'msg-77');
      expect(message.hasExerciseCards, isTrue);
      expect(message.structured!.exerciseSuggestions.single.exerciseId,
          'pushup');
    });

    test('istniejące dane użytkownika przetrwały cały etap', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      store.plans.clear();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'stary',
        name: 'Historyczny zestaw',
        note: 'notatka',
        goal: 'Siła',
        completedDays: {0, 2},
        days: [
          WorkoutDay(weekday: 1, title: 'A', items: [
            PlanItem(
                exerciseId: 'squat',
                sets: 5,
                reps: 5,
                durationSec: 0,
                note: 'ciężko',
                suggestedWeightKg: 82.5,
                restSeconds: 180),
          ]),
          WorkoutDay(weekday: 3, title: 'B', items: []),
          WorkoutDay(weekday: 5, title: 'C', items: []),
        ],
      ));
      await store.addCustomExercise(_exercise(
          id: 'wlasne', name: 'Moje ćwiczenie', muscles: ['klatka']));

      final restored = AppStore();
      await restored.load();
      final plan = restored.plans.firstWhere((p) => p.id == 'stary');
      expect(plan.name, 'Historyczny zestaw');
      expect(plan.note, 'notatka');
      expect(plan.goal, 'Siła');
      expect(plan.completedDays, {0, 2});
      final item = plan.days.first.items.single;
      expect(item.suggestedWeightKg, 82.5);
      expect(item.restSeconds, 180);
      expect(item.note, 'ciężko');
      expect(
        restored.customExercises.any((e) => e.id == 'wlasne'),
        isTrue,
      );
    });
  });
}
