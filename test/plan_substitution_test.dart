import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/plan_substitution.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AppStore store, Widget child) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(store: store, child: child),
    );

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  store.plans.clear();
  return store;
}

/// Zestaw wyłącznie na brzuch (ćwiczenia z realnej bazy aplikacji).
WorkoutPlan _corePlan({String id = 'my-core', String name = 'Mój brzuch'}) =>
    WorkoutPlan(
      id: id,
      name: name,
      note: '',
      origin: const PlanOrigin(creationMode: PlanCreationMode.fullyAiGenerated),
      days: const [
        WorkoutDay(weekday: 1, title: 'Core A', items: [
          PlanItem(
              exerciseId: 'plank',
              sets: 3,
              reps: 0,
              durationSec: 45,
              note: ''),
          PlanItem(
              exerciseId: 'leg_raise',
              sets: 3,
              reps: 12,
              durationSec: 0,
              note: ''),
          PlanItem(
              exerciseId: 'russian_twist',
              sets: 3,
              reps: 20,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );

/// Zestaw na klatkę — nie może zastąpić dnia brzucha.
WorkoutPlan _chestPlan() => const WorkoutPlan(
      id: 'my-chest',
      name: 'Mój push',
      note: '',
      origin: PlanOrigin(creationMode: PlanCreationMode.manual),
      days: [
        WorkoutDay(weekday: 1, title: 'Push', items: [
          PlanItem(
              exerciseId: 'pushup',
              sets: 4,
              reps: 12,
              durationSec: 0,
              note: ''),
          PlanItem(
              exerciseId: 'bench_press',
              sets: 4,
              reps: 8,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Zgodność zestawu z obszarem rozkładu', () {
    test('zestaw na brzuch pasuje pod dzień core', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());

      final verdict = store.evaluateSubstitution(
        store.plans.single,
        TrainingFocusArea.core,
      );
      expect(verdict.canSubstitute, isTrue);
      expect(verdict.fit, PlanSubstitutionFit.perfect);
      expect(verdict.focusRatio, greaterThan(0.9));
      expect(verdict.foreignMuscles, isEmpty);
    });

    test('zestaw na klatkę NIE pasuje pod dzień core', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_chestPlan());

      final verdict = store.evaluateSubstitution(
        store.plans.single,
        TrainingFocusArea.core,
      );
      expect(verdict.canSubstitute, isFalse);
      expect(verdict.fit, PlanSubstitutionFit.incompatible);
    });

    test('zestaw na klatkę pasuje pod dzień klatki', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_chestPlan());

      final verdict = store.evaluateSubstitution(
        store.plans.single,
        TrainingFocusArea.chestTriceps,
      );
      expect(verdict.canSubstitute, isTrue);
      expect(verdict.coveredMuscles, isNotEmpty);
    });

    test('lista kandydatów odsiewa zestawy o innych partiach', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.addWorkoutPlan(_chestPlan());

      final forCore =
          store.substitutionCandidatesForArea(TrainingFocusArea.core);
      expect(forCore.map((c) => c.plan.id), ['my-core']);

      final forChest =
          store.substitutionCandidatesForArea(TrainingFocusArea.chestTriceps);
      expect(forChest.map((c) => c.plan.id), ['my-chest']);
    });

    test('archiwum i puste zestawy nie są kandydatami', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'empty',
        name: 'Pusty',
        note: '',
        days: [WorkoutDay(weekday: 1, title: 'A', items: [])],
        origin: PlanOrigin(creationMode: PlanCreationMode.manual),
      ));
      await store.setPlanArchived('my-core', true);

      expect(
        store.substitutionCandidatesForArea(TrainingFocusArea.core),
        isEmpty,
      );
    });

    test('pusty zestaw dostaje jasny werdykt zamiast wyjątku', () {
      const empty = WorkoutPlan(
        id: 'e',
        name: 'Pusty',
        note: '',
        days: [WorkoutDay(weekday: 1, title: 'A', items: [])],
      );
      final verdict = evaluatePlanSubstitution(
        plan: empty,
        areaSignature: TrainingFocusArea.core.signatureMuscles.toSet(),
        resolve: (id) => ExerciseRepo.byId(id),
      );
      expect(verdict.canSubstitute, isFalse);
      expect(verdict.warnings.single, contains('nie ma jeszcze'));
    });
  });

  group('Podmiana zestawu w planie dnia', () {
    test('podmiana zapisuje się i przeżywa restart aplikacji', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');

      expect(store.substitutedPlanForArea(TrainingFocusArea.core)?.id,
          'my-core');
      // Znacznik użycia trafia do metadanych zestawu.
      expect(store.plans.single.origin.lastUsedAt, isNotNull);

      final restored = AppStore();
      await restored.load();
      expect(restored.substitutedPlanForArea(TrainingFocusArea.core)?.id,
          'my-core');
    });

    test('podmiana kieruje dzisiejszy plan na własny zestaw', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');

      expect(store.scheduledPlanForArea(TrainingFocusArea.core)?.id,
          'my-core');
      // Podmiana dotyczy WYŁĄCZNIE wskazanego obszaru — reszta rozkładu
      // pozostaje bez podstawienia.
      expect(store.substitutedPlanForArea(TrainingFocusArea.legs), isNull);
      expect(store.substitutedPlanForArea(TrainingFocusArea.chestTriceps),
          isNull);
      expect(store.planAreaSubstitutions.keys,
          [TrainingFocusArea.core.name]);
    });

    test('wąski zestaw nie wskakuje na dzień innej partii', () async {
      final store = await _freshStore();
      // Jedyny własny zestaw trenuje SAM brzuch i jest aktywny.
      await store.addWorkoutPlan(_corePlan());
      expect(store.plans.single.isActive, isTrue);

      // Dzień brzucha — plan pasuje.
      expect(store.planCoversArea(store.plans.single, TrainingFocusArea.core),
          isTrue);
      // Dzień nóg — nie ma w nim ani jednego ćwiczenia na nogi, więc nie może
      // zostać planem tego dnia (dzień składa Planer).
      expect(store.planCoversArea(store.plans.single, TrainingFocusArea.legs),
          isFalse);
      expect(store.scheduledPlanForArea(TrainingFocusArea.legs), isNull);
      expect(store.scheduledPlanForArea(TrainingFocusArea.chestTriceps),
          isNull);
    });

    test('plan rozpisujący cały tydzień nadal obsługuje każdy dzień', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'full-body',
        name: 'Full Body',
        note: '',
        origin: PlanOrigin(creationMode: PlanCreationMode.manual),
        days: [
          WorkoutDay(weekday: 1, title: 'Całe ciało', items: [
            PlanItem(
                exerciseId: 'squat',
                sets: 3,
                reps: 10,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'pushup',
                sets: 3,
                reps: 12,
                durationSec: 0,
                note: ''),
            PlanItem(
                exerciseId: 'plank',
                sets: 3,
                reps: 0,
                durationSec: 45,
                note: ''),
          ]),
        ],
      ));

      for (final area in [
        TrainingFocusArea.legs,
        TrainingFocusArea.chestTriceps,
        TrainingFocusArea.core,
      ]) {
        expect(store.planCoversArea(store.plans.single, area), isTrue,
            reason: 'plan całego ciała pokrywa ${area.label}');
      }
      expect(store.scheduledPlanForArea(TrainingFocusArea.legs)?.id,
          'full-body');
    });

    test('kafelek dzisiejszego treningu pokazuje podstawiony zestaw',
        () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      // Rozkład na dziś ustawiamy na dzień brzucha.
      final today = DateTime.now();
      await store.updateSettings(store.settings.copyWith(
        trainingSchedule: store.trainingScheduleConfig.copyWith(
          enabled: true,
          weekdayPlans: {
            ...store.trainingScheduleConfig.weekdayPlans,
            today.weekday:
                const TrainingDayPlan(primary: TrainingFocusArea.core),
          },
        ),
      ));
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');

      final blocks = store.todayTrainingBlocks(today);
      final coreBlock =
          blocks.where((b) => b.area == TrainingFocusArea.core).toList();
      expect(coreBlock, hasLength(1));
      expect(coreBlock.single.planId, 'my-core',
          reason: 'kafelek dnia musi iść za podmianą, nie za zestawem bazowym');
      expect(coreBlock.single.planName, 'Mój brzuch');
      expect(coreBlock.single.exerciseCount, 3);
    });

    test('przywrócenie bazowego czyści podmianę', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');
      await store.clearPlanForArea(TrainingFocusArea.core);

      expect(store.substitutedPlanForArea(TrainingFocusArea.core), isNull);
      final restored = AppStore();
      await restored.load();
      expect(restored.substitutedPlanForArea(TrainingFocusArea.core), isNull);
    });

    test('usunięcie zestawu sprząta podmianę', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');
      await store.deleteWorkoutPlan('my-core');

      expect(store.substitutedPlanForArea(TrainingFocusArea.core), isNull);
      expect(store.planAreaSubstitutions, isEmpty);
    });

    test('zarchiwizowany zestaw przestaje rządzić dniem', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.addWorkoutPlan(_chestPlan());
      await store.setPlanForArea(TrainingFocusArea.core, 'my-core');
      await store.setPlanArchived('my-core', true);

      expect(store.substitutedPlanForArea(TrainingFocusArea.core), isNull);
    });
  });

  group('UI podmiany', () {
    testWidgets('arkusz pokazuje kandydata, sprawdzenie AI i podmienia',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPlanSubstitutionSheet(
                    context, TrainingFocusArea.core),
                child: const Text('Zamień'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zamień'));
      await tester.pumpAndSettle();

      expect(find.text('Zamień zestaw na własny'), findsOneWidget);
      expect(find.text('Mój brzuch'), findsOneWidget);
      expect(find.text(PlanSubstitutionFit.perfect.label), findsOneWidget);

      // Sprawdzenie AI liczy się na żądanie i nic nie zapisuje.
      await tester.tap(find.byKey(const Key('substitution_check_my-core')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('substitution_ai_score')), findsOneWidget);
      expect(store.planAreaSubstitutions, isEmpty);

      await tester.tap(find.byKey(const Key('substitution_apply_my-core')));
      await tester.pumpAndSettle();

      expect(store.substitutedPlanForArea(TrainingFocusArea.core)?.id,
          'my-core');
      expect(tester.takeException(), isNull);
    });

    testWidgets('brak pasujących zestawów tłumaczy, co zrobić',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_chestPlan());
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPlanSubstitutionSheet(
                    context, TrainingFocusArea.core),
                child: const Text('Zamień'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zamień'));
      await tester.pumpAndSettle();

      expect(find.text('Brak pasujących zestawów'), findsOneWidget);
      expect(find.byKey(const Key('substitution_create_plan')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kafelki własnych zestawów na ekranie Trening', () {
    testWidgets('sekcja pokazuje własne zestawy pod nagłówkiem',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await store.addWorkoutPlan(_chestPlan());
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: CreateOwnPlanCard(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Moje zestawy'), findsOneWidget);
      expect(find.text('Mój brzuch'), findsOneWidget);
      expect(find.text('Mój push'), findsOneWidget);
      expect(find.byKey(const Key('own_plan_tile_my-core')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kafelek pozwala oznaczyć ulubiony i renderuje się w obu motywach',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_corePlan());
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final dark in [true, false]) {
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), dark),
          home: AppScope(
            store: store,
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: CreateOwnPlanCard(),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const Key('own_plan_fav_my-core')));
      await tester.pumpAndSettle();
      expect(store.plans.single.origin.isFavorite, isTrue);
    });

    testWidgets('bez własnych zestawów sekcja kafelków się nie pokazuje',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: CreateOwnPlanCard(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Utwórz własny zestaw'), findsOneWidget);
      expect(find.byType(OwnPlanTile), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
