import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/equipment_program_filter.dart';
import 'package:licznik_treningu/features/trainer/application/plan_ai_advisor.dart';
import 'package:licznik_treningu/features/trainer/domain/ai_structured_reply.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AppStore store, Widget child, {bool dark = true}) {
  return MaterialApp(
    theme: buildTheme(const Color(0xFF24D6A3), dark),
    home: AppScope(store: store, child: child),
  );
}

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  store.plans.clear();
  return store;
}


/// Kliknięcie chipa kategorii (na szerokim ekranie wszystkie są widoczne).
Future<void> _tapCategory(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key('plan_category_$key')));
  await tester.pumpAndSettle();
}

/// Przewija leniwą listę, aż [finder] zostanie zbudowany i pokazany.
Future<void> _revealInList(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}


/// Przycisk analizy leży pod zgięciem ekranu — przewiń, potem kliknij.
Future<void> _runAnalysis(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('run_plan_analysis')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const Key('run_plan_analysis')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kreator własnych zestawów', () {
    testWidgets('karta wejściowa pokazuje trzy tryby tworzenia',
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
      await tester.tap(find.byKey(const Key('create_own_plan_card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_mode_manual')), findsOneWidget);
      expect(find.byKey(const Key('plan_mode_manual_ai')), findsOneWidget);
      expect(find.byKey(const Key('plan_mode_full_ai')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tryb ręczny: kreator bez kroku pomocy AI, zapis jako manual',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.manual),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Krok 1 z 8'), findsOneWidget);
      expect(find.text('Jaki jest cel tego zestawu?'), findsOneWidget);

      // Przejdź przez wszystkie kroki aż do podglądu.
      for (var step = 0; step < 7; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Podgląd zestawu'), findsOneWidget);
      // Tryb ręczny nie pokazuje checklisty pomocy AI.
      expect(find.text('W czym ma pomóc AI?'), findsNothing);

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      expect(store.plans, hasLength(1));
      final plan = store.plans.single;
      expect(plan.origin.creationMode, PlanCreationMode.manual);
      expect(plan.origin.createdManually, isTrue);
      // Tryb ręczny NIE wstawia ćwiczeń za użytkownika.
      expect(plan.days.every((day) => day.items.isEmpty), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tryb z pomocą AI: checklista zakresów i zapis wyboru',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.manualWithAi),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Krok 1 z 9'), findsOneWidget);
      for (var step = 0; step < 7; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('W czym ma pomóc AI?'), findsOneWidget);
      expect(find.textContaining('Krok 8 z 9'), findsOneWidget);

      // Odznacz jeden domyślny zakres i zaznacz inny.
      final restKey = Key('ai_scope_${AiAssistanceScope.rest.key}');
      await tester.scrollUntilVisible(find.byKey(restKey), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(restKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      expect(store.plans, hasLength(1));
      final plan = store.plans.single;
      expect(plan.origin.creationMode, PlanCreationMode.manualWithAi);
      expect(plan.origin.aiAssisted, isTrue);
      // Odznaczony zakres nie trafił do metadanych.
      expect(plan.origin.aiAssistanceScopes,
          isNot(contains(AiAssistanceScope.rest)));
      expect(plan.origin.aiAssistanceScopes,
          contains(AiAssistanceScope.fillMissingExercises));
      expect(tester.takeException(), isNull);
    });

    testWidgets('zaznaczenie partii zawęża zestaw — koniec pompek w brzuchu',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.fullyAiGenerated),
      ));
      await tester.pumpAndSettle();

      // Krok 1 → nazwa zestawu, potem krok 2 z partiami.
      await tester.enterText(
          find.byType(TextField).first, 'Ćwiczenia na brzuch');
      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      // Zaznaczenie partii ma od razu ustawić zakres „tylko wybrane".
      await tester.tap(find.byKey(const Key('priority_core')));
      await tester.pumpAndSettle();
      expect(find.text('Zakres zestawu'), findsOneWidget);
      expect(find.text('Tylko wybrane partie'), findsOneWidget);

      for (var step = 0; step < 6; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Podgląd zestawu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      final plan = store.plans.single;
      expect(plan.name, 'Ćwiczenia na brzuch');
      final groups = <MuscleGroup>{
        for (final day in plan.days)
          for (final item in day.items)
            primaryMuscleGroupOf(
                ExerciseRepo.byId(item.exerciseId, store.customExercises)),
      };
      expect(groups, {MuscleGroup.core},
          reason: 'zestaw na brzuch nie może zawierać innych partii');
      expect(plan.days.first.title, contains('Core'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('bez zaznaczonych partii zakres nie jest pokazywany',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.fullyAiGenerated),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      expect(find.text('Zakres zestawu'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('krok ograniczeń pozwala wybrać poziom i wykluczenia',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.fullyAiGenerated),
      ));
      await tester.pumpAndSettle();
      for (var step = 0; step < 5; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }

      expect(find.text('Czego mamy unikać?'), findsOneWidget);
      await tester.tap(
          find.byKey(Key('limitation_${TrainingLimitation.knees.key}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('level_Zaawansowany')));
      await tester.pumpAndSettle();

      for (var step = 0; step < 2; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      final plan = store.plans.single;
      expect(plan.level, 'Zaawansowany');
      // Żadne ćwiczenie nie może kolidować z ochroną kolan.
      const limits =
          LimitationProfile(flags: {TrainingLimitation.knees});
      for (final day in plan.days) {
        for (final item in day.items) {
          final exercise =
              ExerciseRepo.byId(item.exerciseId, store.customExercises);
          expect(exerciseViolatesLimitation(exercise, limits), isFalse,
              reason: '${exercise.name} koliduje z ochroną kolan');
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tryb z AI bez zakresu „uzupełnij ćwiczenia" daje pusty szkielet',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.manualWithAi),
      ));
      await tester.pumpAndSettle();
      for (var step = 0; step < 7; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('W czym ma pomóc AI?'), findsOneWidget);

      // Odznacz „uzupełnij brakujące ćwiczenia" (domyślnie zaznaczone).
      final fillKey =
          Key('ai_scope_${AiAssistanceScope.fillMissingExercises.key}');
      await tester.scrollUntilVisible(find.byKey(fillKey), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(fillKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI nie dobiera ćwiczeń'), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      final plan = store.plans.single;
      expect(plan.days.every((day) => day.items.isEmpty), isTrue);
      // Tryb i zakres pomocy zostają zapisane zgodnie z wyborem użytkownika.
      expect(plan.origin.creationMode, PlanCreationMode.manualWithAi);
      expect(plan.origin.aiAssistanceScopes,
          isNot(contains(AiAssistanceScope.fillMissingExercises)));
      expect(plan.origin.aiAssistanceScopes, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tryb pełnego AI: podgląd z oceną i realnymi ćwiczeniami',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanCreatorPage(mode: PlanCreationMode.fullyAiGenerated),
      ));
      await tester.pumpAndSettle();

      for (var step = 0; step < 7; step++) {
        await tester.tap(find.byKey(const Key('plan_creator_next')));
        await tester.pumpAndSettle();
      }

      expect(find.text('Podgląd zestawu'), findsOneWidget);
      expect(find.byKey(const Key('plan_quality_score')), findsOneWidget);
      expect(find.text('Ocena zestawu'), findsOneWidget);
      // Podgląd niczego jeszcze nie zapisał.
      expect(store.plans, isEmpty);
      expect(find.text('Nic nie zostało jeszcze zapisane.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan_creator_next')));
      await tester.pumpAndSettle();

      expect(store.plans, hasLength(1));
      final plan = store.plans.single;
      expect(plan.origin.creationMode, PlanCreationMode.fullyAiGenerated);
      final exerciseCount =
          plan.days.fold<int>(0, (sum, day) => sum + day.items.length);
      expect(exerciseCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('Lista moich zestawów', () {
    Future<AppStore> storeWithMixedPlans() async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'm1',
        name: 'Ręczny zestaw',
        note: '',
        days: [],
        origin: PlanOrigin(creationMode: PlanCreationMode.manual),
      ));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'm2',
        name: 'Zestaw z AI',
        note: '',
        days: [],
        origin: PlanOrigin(creationMode: PlanCreationMode.manualWithAi),
      ));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'm3',
        name: 'Zestaw wygenerowany',
        note: '',
        days: [],
        origin: PlanOrigin(creationMode: PlanCreationMode.fullyAiGenerated),
      ));
      return store;
    }

    testWidgets('filtruje zestawy po sposobie utworzenia', (tester) async {
      final store = await storeWithMixedPlans();
      await tester.binding.setSurfaceSize(const Size(1700, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(store, const MyPlansPage()));
      await tester.pumpAndSettle();

      expect(find.text('Ręczny zestaw'), findsOneWidget);
      expect(find.text('Zestaw z AI'), findsOneWidget);
      expect(find.text('Zestaw wygenerowany'), findsOneWidget);

      await _tapCategory(tester, 'manual');
      expect(find.text('Ręczny zestaw'), findsOneWidget);
      expect(find.text('Zestaw z AI'), findsNothing);
      expect(find.text('Zestaw wygenerowany'), findsNothing);

      await _tapCategory(tester, 'aiGenerated');
      expect(find.text('Zestaw wygenerowany'), findsOneWidget);
      expect(find.text('Ręczny zestaw'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wyszukiwanie i ulubione działają', (tester) async {
      final store = await storeWithMixedPlans();
      await tester.binding.setSurfaceSize(const Size(1700, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(store, const MyPlansPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('my_plans_search')), 'wygenerowany');
      await tester.pumpAndSettle();
      expect(find.text('Zestaw wygenerowany'), findsOneWidget);
      expect(find.text('Ręczny zestaw'), findsNothing);

      await tester.enterText(find.byKey(const Key('my_plans_search')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan_fav_m1')));
      await tester.pumpAndSettle();
      expect(
        store.plans.firstWhere((p) => p.id == 'm1').origin.isFavorite,
        isTrue,
      );

      await _tapCategory(tester, 'favorites');
      expect(find.text('Ręczny zestaw'), findsOneWidget);
      expect(find.text('Zestaw z AI'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderuje się bez wyjątków w jasnym i ciemnym motywie',
        (tester) async {
      final store = await storeWithMixedPlans();
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final dark in [true, false]) {
        await tester.pumpWidget(_app(store, const MyPlansPage(), dark: dark));
        await tester.pumpAndSettle();
        expect(find.text('Moje zestawy'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Karty ćwiczeń w rozmowie z AI', () {
    TrainerAiStructuredReply reply({int count = 1, bool full = true}) {
      return TrainerAiStructuredReply(
        message: 'Propozycje:',
        exerciseSuggestions: [
          for (var i = 0; i < count; i++)
            AiExerciseSuggestion(
              name: full ? 'Wyciskanie hantli $i' : 'Ćwiczenie bez danych $i',
              exerciseId: '',
              description: full ? 'Klasyczny ruch pchający.' : '',
              primaryMuscles: full ? const ['klatka piersiowa'] : const [],
              secondaryMuscles: full ? const ['triceps'] : const [],
              equipment: full ? 'hantle i ławka' : '',
              difficulty: full ? 'Średniozaawansowany' : '',
              reasonRecommended: full ? 'Pasuje do sprzętu.' : '',
              recoveryCompatibility: full
                  ? AiRecoveryCompatibility.good
                  : AiRecoveryCompatibility.unknown,
              recoveryNote: full ? 'Dobre na dzisiaj' : '',
            ),
        ],
      );
    }

    testWidgets('karta pokazuje szczegóły i komplet akcji', (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(reply: reply()),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Proponowane ćwiczenia (1)'), findsOneWidget);
      expect(find.text('Wyciskanie hantli 0'), findsOneWidget);
      expect(find.text('klatka piersiowa'), findsOneWidget);
      expect(find.text('hantle i ławka'), findsOneWidget);
      expect(find.text('Dobre na dzisiaj'), findsOneWidget);
      expect(find.text('Zobacz'), findsOneWidget);
      expect(find.text('Dodaj do bazy'), findsOneWidget);
      expect(find.text('Dodaj do zestawu'), findsOneWidget);
      expect(find.text('Rozpocznij'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('karta bez danych nie pokazuje pustych sekcji i nie pada',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(reply: reply(full: false)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ćwiczenie bez danych 0'), findsOneWidget);
      // Brak sprzętu/mięśni/opisu → żadnych pustych etykiet.
      expect(find.text('Dobre na dzisiaj'), findsNothing);
      expect(find.textContaining('Dlaczego:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blok da się zwinąć, a tryb wyboru odsłania akcje zbiorcze',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(reply: reply(count: 3)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Wyciskanie hantli 0'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai_cards_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Wyciskanie hantli 0'), findsNothing);

      await tester.tap(find.byKey(const Key('ai_cards_toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai_cards_selection_mode')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_cards_bulk_to_base')), findsOneWidget);
      expect(find.byKey(const Key('ai_cards_bulk_to_plan')), findsOneWidget);
      expect(find.byKey(const Key('ai_cards_bulk_new_plan')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai_cards_select_all')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dodanie do bazy pokazuje podgląd i zapisuje po zatwierdzeniu',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final before = store.customExercises.length;

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: const TrainerAiStructuredReply(
                message: 'ok',
                exerciseSuggestions: [
                  AiExerciseSuggestion(
                    name: 'Ćwiczenie testowe QQZX',
                    primaryMuscles: ['przedramiona'],
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dodaj do bazy'));
      await tester.pumpAndSettle();

      expect(find.text('Nowe ćwiczenie'), findsOneWidget);
      expect(find.textContaining('Źródło: Trener AI'), findsOneWidget);
      // Nic nie zapisano, dopóki użytkownik nie kliknie.
      expect(store.customExercises.length, before);

      await tester.tap(find.byKey(const Key('new_exercise_confirm')));
      await tester.pumpAndSettle();

      expect(store.customExercises.length, before + 1);
      final added = store.customExercises.first;
      expect(added.name, 'Ćwiczenie testowe QQZX');
      expect(added.source, startsWith('ai_chat'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplikat pokazuje ostrzeżenie z opcjami', (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: const TrainerAiStructuredReply(
                message: 'ok',
                exerciseSuggestions: [
                  // „Przysiad" jest w bazie wbudowanej.
                  AiExerciseSuggestion(
                    name: 'Przysiad',
                    primaryMuscles: ['czworogłowe uda'],
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dodaj do bazy'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('duplicate_warning')), findsOneWidget);
      expect(find.byKey(const Key('duplicate_open_existing')), findsOneWidget);
      expect(find.byKey(const Key('duplicate_add_variant')), findsOneWidget);
      expect(find.byKey(const Key('duplicate_add_anyway')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('czat renderuje karty w dymku AI bez overflow (2 motywy)',
        (tester) async {
      final store = await _freshStore();
      store.aiChatHistory.add(AiChatMessage(
        role: 'assistant',
        content: 'Oto ćwiczenia na klatkę:',
        timestamp: DateTime(2026, 8, 5),
        messageId: 'msg-1',
        structured: const TrainerAiStructuredReply(
          message: 'Oto ćwiczenia na klatkę:',
          exerciseSuggestions: [
            AiExerciseSuggestion(
              name: 'Wyciskanie hantli na ławce skośnej dodatnio',
              exerciseId: 'incline_db_press',
              primaryMuscles: ['klatka piersiowa'],
              secondaryMuscles: ['triceps', 'przedni bark'],
              equipment: 'hantle i ławka regulowana',
              difficulty: 'Średniozaawansowany',
              reasonRecommended:
                  'Uzupełnia górną część klatki, której brakuje w zestawie.',
              recoveryCompatibility: AiRecoveryCompatibility.good,
              recoveryNote: 'Dobre na dzisiaj',
              alreadyInDatabase: true,
            ),
          ],
        ),
      ));

      // Wąski telefon — najostrzejszy test na przepełnienia.
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final dark in [true, false]) {
        await tester.pumpWidget(
            _app(store, const Scaffold(body: AiTrainerPage()), dark: dark));
        await tester.pumpAndSettle();

        expect(find.text('AI Trainer'), findsOneWidget);
        expect(find.text('Proponowane ćwiczenia (1)'), findsOneWidget);
        expect(find.text('Wyciskanie hantli na ławce skośnej dodatnio'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('zwykła wiadomość tekstowa nie pokazuje żadnych kart',
        (tester) async {
      final store = await _freshStore();
      store.aiChatHistory.add(AiChatMessage(
        role: 'assistant',
        content: 'Dziś lepiej odpocznij.',
        timestamp: DateTime(2026, 8, 5),
      ));
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(store, const Scaffold(body: AiTrainerPage())));
      await tester.pumpAndSettle();

      expect(find.text('Dziś lepiej odpocznij.'), findsOneWidget);
      expect(find.textContaining('Proponowane ćwiczenia'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dodanie do zestawu prowadzi przez wybór zestawu i dnia',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'target-plan',
        name: 'Zestaw docelowy',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Dzień A', items: []),
          WorkoutDay(weekday: 3, title: 'Dzień B', items: []),
        ],
      ));
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: const TrainerAiStructuredReply(
                message: 'ok',
                exerciseSuggestions: [
                  AiExerciseSuggestion(
                    name: 'Przysiad',
                    exerciseId: 'squat',
                    alreadyInDatabase: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dodaj do zestawu'));
      await tester.pumpAndSettle();

      expect(find.text('Wybierz zestaw'), findsOneWidget);
      await tester.tap(find.byKey(const Key('picker_plan_target-plan')));
      await tester.pumpAndSettle();

      expect(find.text('Wybierz dzień'), findsOneWidget);
      await tester.tap(find.byKey(const Key('picker_day_1')));
      await tester.pumpAndSettle();

      // Jeżeli analiza kolizji coś wykryła, aplikacja pyta przed dodaniem —
      // nie blokuje, tylko wyjaśnia. Potwierdzamy świadomie.
      if (find.text('Dodaj mimo to').evaluate().isNotEmpty) {
        expect(find.text('Sprawdź przed dodaniem'), findsOneWidget);
        await tester.tap(find.text('Dodaj mimo to'));
        await tester.pumpAndSettle();
      }

      final plan = store.plans.firstWhere((p) => p.id == 'target-plan');
      expect(plan.days[0].items, isEmpty);
      expect(plan.days[1].items, hasLength(1));
      expect(plan.days[1].items.single.exerciseId, 'squat');
      expect(tester.takeException(), isNull);
    });
  });

  group('Analiza AI zestawu', () {
    Future<AppStore> storeWithPlan() async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'analyze-me',
        name: 'Zestaw bazowy',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'pushup',
                sets: 1,
                reps: 30,
                durationSec: 0,
                note: '',
                restSeconds: 400),
            PlanItem(
                exerciseId: 'squat',
                sets: 1,
                reps: 30,
                durationSec: 0,
                note: '',
                restSeconds: 400),
          ]),
        ],
      ));
      return store;
    }

    testWidgets('analiza pokazuje ocenę, podstawę decyzji i propozycje',
        (tester) async {
      final store = await storeWithPlan();
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanAiAnalysisPage(
            planId: 'analyze-me', mode: PlanAnalysisMode.permanent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Zestaw bazowy'), findsOneWidget);
      expect(find.text('Co AI może zmienić?'), findsOneWidget);

      await _runAnalysis(tester);

      await _revealInList(tester, find.byKey(const Key('plan_quality_score')));
      expect(find.byKey(const Key('plan_quality_score')), findsOneWidget);
      await _revealInList(
          tester, find.byKey(const Key('analysis_confidence')));
      expect(find.byKey(const Key('analysis_confidence')), findsOneWidget);
      expect(find.textContaining('Analiza została przygotowana'),
          findsOneWidget);
      await _revealInList(tester, find.textContaining('Proponowane poprawki'));
      expect(find.textContaining('Proponowane poprawki'), findsOneWidget);
      // Analiza sama z siebie NIC nie zapisała.
      expect(store.plans.single.versions, isEmpty);
      expect(store.plans, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('zapis wariantu nie rusza zestawu bazowego', (tester) async {
      final store = await storeWithPlan();
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanAiAnalysisPage(
            planId: 'analyze-me', mode: PlanAnalysisMode.permanent),
      ));
      await tester.pumpAndSettle();
      await _runAnalysis(tester);

      // Zaakceptuj wszystkie bezpieczne zmiany.
      await tester.scrollUntilVisible(
        find.byKey(const Key('accept_safe_changes')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('accept_safe_changes')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('save_as_variant')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('save_as_variant')));
      await tester.pumpAndSettle();

      expect(store.plans, hasLength(2));
      final original = store.plans.firstWhere((p) => p.id == 'analyze-me');
      expect(original.days.single.items, hasLength(2));
      expect(original.days.single.items.first.sets, 1);
      final variant = store.plans.firstWhere((p) => p.id != 'analyze-me');
      expect(variant.origin.basePlanId, 'analyze-me');
      expect(variant.name, contains('mój wariant AI'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('bez blokady AI proponuje zamianę niedostępnego ćwiczenia',
        (tester) async {
      final store = await _freshStore();
      await store.updateSettings(store.settings.copyWith(
        equipmentModeKey: EquipmentMode.bodyweight.key,
      ));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'locked-plan',
        name: 'Zestaw ze sztangą',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench_press',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      ));
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanAiAnalysisPage(
            planId: 'locked-plan', mode: PlanAnalysisMode.permanent),
      ));
      await tester.pumpAndSettle();

      // Bez blokady analiza proponuje zamianę ćwiczenia wymagającego sztangi.
      await _runAnalysis(tester);
      await _revealInList(tester, find.textContaining('Zamień „Wyciskanie'));
      expect(find.textContaining('Zamień „Wyciskanie'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('po zablokowaniu ćwiczenia AI już go nie proponuje zmienić',
        (tester) async {
      final store = await _freshStore();
      await store.updateSettings(store.settings.copyWith(
        equipmentModeKey: EquipmentMode.bodyweight.key,
      ));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'locked-plan',
        name: 'Zestaw ze sztangą',
        note: '',
        days: [
          WorkoutDay(weekday: 1, title: 'Push', items: [
            PlanItem(
                exerciseId: 'bench_press',
                sets: 3,
                reps: 8,
                durationSec: 0,
                note: ''),
          ]),
        ],
      ));
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const PlanAiAnalysisPage(
            planId: 'locked-plan', mode: PlanAnalysisMode.permanent),
      ));
      await tester.pumpAndSettle();

      // Najpierw blokada, dopiero potem analiza. Sekcja blokad leży pod
      // listą zakresów, więc trzeba do niej przewinąć.
      await _revealInList(
          tester, find.byKey(const Key('toggle_locked_picker')));
      await tester.tap(find.byKey(const Key('toggle_locked_picker')));
      await tester.pumpAndSettle();
      await _revealInList(tester, find.byKey(const Key('lock_bench_press')));
      await tester.tap(find.byKey(const Key('lock_bench_press')));
      await tester.pumpAndSettle();
      expect(find.text('Zablokowane: 1'), findsOneWidget);

      await _runAnalysis(tester);
      await _revealInList(tester, find.textContaining('Proponowane poprawki'));

      // Zablokowane ćwiczenie nie pojawia się w żadnej propozycji.
      expect(find.textContaining('Zamień „Wyciskanie'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tryb analizy oferuje stałe dopasowanie i wariant na dzisiaj',
        (tester) async {
      final store = await storeWithPlan();
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => openPlanAiAnalysis(context, 'analyze-me'),
                child: const Text('Analizuj'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analizuj'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('analysis_mode_permanent')), findsOneWidget);
      expect(find.byKey(const Key('analysis_mode_today')), findsOneWidget);
      expect(find.text('Analiza stałego dopasowania'), findsOneWidget);
      expect(find.text('Analiza na dzisiaj'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
