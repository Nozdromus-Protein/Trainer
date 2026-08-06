import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/ai_reply_exercise_extractor.dart';
import 'package:licznik_treningu/features/trainer/domain/ai_structured_reply.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise _exercise(String id, String name, List<String> muscles) => Exercise(
      id: id,
      name: name,
      category: muscles.first,
      muscles: muscles,
      equipment: 'masa ciała',
      level: 'Początkujący',
      illustrationType: 'generic',
      description: '',
      tips: const [],
      commonMistakes: const [],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: 0,
      met: 4.5,
    );

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Karty ćwiczeń z tekstu odpowiedzi AI', () {
    final library = [
      _exercise('pushup', 'Pompki', ['klatka piersiowa']),
      _exercise('squat', 'Przysiad', ['czworogłowe uda']),
      _exercise('bulgarian', 'Przysiad bułgarski', ['czworogłowe uda']),
      _exercise('plank', 'Deska', ['brzuch']),
    ];

    test('rozpoznaje ćwiczenia z listy punktowanej', () {
      const reply = '''
Na klatkę polecam dziś:
- Pompki — 3 serie po 12 powtórzeń
- Deska w podporze przodem, 3×40 s
''';
      final mentions = findExerciseMentions(reply, library_: library);
      final names = mentions.map((m) => m.name).toList();
      expect(names, contains('Pompki'));
      expect(mentions.every((m) => m.fromListItem), isTrue);

      // „Pompki" trafia w bazę, „Deska w podporze przodem" nie — i właśnie
      // dlatego zostaje kartą NOWEGO ćwiczenia, zamiast być na siłę
      // dopasowaną do „Deski". Kartę i tak da się dodać do bazy.
      final pushups = mentions.firstWhere((m) => m.name == 'Pompki');
      expect(pushups.exercise?.id, 'pushup');
      expect(mentions.any((m) => !m.isInDatabase), isTrue);
    });

    test('rozpoznaje listę numerowaną i pogrubienia markdown', () {
      const reply = '''
1. **Przysiad** – rozgrzej się serią bez obciążenia
2. **Pompki** – trzy serie
''';
      final mentions = findExerciseMentions(reply, library_: library);
      expect(mentions, hasLength(2));
      expect(mentions.map((m) => m.exercise?.id), containsAll(['squat', 'pushup']));
    });

    test('dłuższa nazwa wygrywa — jedna karta zamiast dwóch', () {
      const reply = '- Przysiad bułgarski, 3×10 na nogę';
      final mentions = findExerciseMentions(reply, library_: library);
      expect(mentions, hasLength(1));
      expect(mentions.single.exercise?.id, 'bulgarian');
    });

    test('pojedyncza wzmianka w zdaniu NIE tworzy karty', () {
      const reply = 'Dziś odpuść nogi, więc przysiad zostaw na jutro.';
      expect(findExerciseMentions(reply, library_: library), isEmpty);
    });

    test('dwa różne ćwiczenia w zdaniu już wystarczają', () {
      const reply =
          'Możesz połączyć pompki z deską w jednej sesji obwodowej.';
      final mentions = findExerciseMentions(reply, library_: library);
      expect(mentions, hasLength(2));
    });

    test('tekst bez ćwiczeń nie daje kart', () {
      expect(
        findExerciseMentions('Dziś odpocznij i wyśpij się.',
            library_: library),
        isEmpty,
      );
      expect(findExerciseMentions('', library_: library), isEmpty);
    });

    test('buduje pełne karty z werdyktem regeneracji', () {
      const reply = '- Pompki\n- Deska';
      final cards = extractExerciseSuggestionsFromText(
        reply,
        library_: library,
        recoveryVerdict: (_) => (
          label: 'Dobre na dzisiaj',
          compatibility: AiRecoveryCompatibility.good,
        ),
      );
      expect(cards, hasLength(2));
      expect(cards.first.exerciseId, 'pushup');
      expect(cards.first.alreadyInDatabase, isTrue);
      expect(cards.first.recoveryNote, 'Dobre na dzisiaj');
      expect(cards.first.recoveryCompatibility, AiRecoveryCompatibility.good);
    });
  });

  group('Rozpoznanie prośby o analizę zestawu', () {
    const names = ['Push', 'Pull', 'Nogi i pośladki'];

    test('rozpoznaje nazwę zestawu wprost', () {
      expect(
        detectPlanAnalysisRequest('Przeanalizuj mój zestaw Push',
            planNames: names),
        'Push',
      );
      expect(
        detectPlanAnalysisRequest('Dopasuj zestaw Nogi i pośladki do sprzętu',
            planNames: names),
        'Nogi i pośladki',
      );
    });

    test('bez nazwy używa zestawu zapasowego (aktywnego)', () {
      expect(
        detectPlanAnalysisRequest('Co poprawiłbyś w tym zestawie?',
            planNames: names, fallbackName: 'Push'),
        'Push',
      );
    });

    test('zwykłe pytania nie uruchamiają analizy', () {
      expect(
        detectPlanAnalysisRequest('Jakie ćwiczenia na klatkę?',
            planNames: names, fallbackName: 'Push'),
        '',
      );
      expect(
        detectPlanAnalysisRequest('Czy robię progres?',
            planNames: names, fallbackName: 'Push'),
        '',
      );
      expect(detectPlanAnalysisRequest('', planNames: names), '');
    });
  });

  group('AppStore — karty z tekstu i wskazanie analizy', () {
    test('exerciseCardsFromReplyText działa na realnej bazie', () async {
      final store = await _freshStore();
      const reply = '''
Na klatkę możesz zrobić:
- Pompki
- Przysiad
''';
      final cards = store.exerciseCardsFromReplyText(reply);
      expect(cards, isNotEmpty);
      expect(cards.every((card) => card.exerciseId.isNotEmpty), isTrue);
      expect(cards.every((card) => card.alreadyInDatabase), isTrue);
    });

    test('withPlanAnalysisHint wskazuje istniejący zestaw', () async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'push-plan',
        name: 'Push',
        note: '',
        days: [],
      ));
      const base = TrainerAiStructuredReply(message: 'ok');

      final hinted =
          store.withPlanAnalysisHint(base, 'Przeanalizuj mój zestaw Push');
      expect(hinted.planAnalysisPlanId, 'push-plan');
      expect(hinted.planAnalysisPlanName, 'Push');
      expect(hinted.hasStructuredData, isTrue);

      final untouched =
          store.withPlanAnalysisHint(base, 'Ile mam dziś kroków?');
      expect(untouched.planAnalysisPlanId, isEmpty);
    });

    test('setSuggestion i wskazanie analizy przeżywają zapis historii',
        () async {
      final store = await _freshStore();
      store.aiChatHistory.add(AiChatMessage(
        role: 'assistant',
        content: 'Propozycja zestawu:',
        timestamp: DateTime(2026, 8, 5),
        messageId: 'msg-set',
        structured: const TrainerAiStructuredReply(
          message: 'Propozycja zestawu:',
          planAnalysisPlanId: 'push-plan',
          planAnalysisPlanName: 'Push',
          setSuggestion: AiSetSuggestion(
            name: 'Full Body 2×',
            days: [
              AiSetSuggestionDay(
                title: 'Dzień A',
                exercises: [
                  AiExerciseSuggestion(name: 'Pompki', exerciseId: 'pushup'),
                ],
              ),
            ],
          ),
        ),
      ));
      await store.saveAiChatHistory();

      final restored = AppStore();
      await restored.load();
      final structured = restored.aiChatHistory.last.structured;
      expect(structured, isNotNull);
      expect(structured!.setSuggestion?.name, 'Full Body 2×');
      expect(structured.setSuggestion?.allExercises, hasLength(1));
      expect(structured.planAnalysisPlanId, 'push-plan');
    });
  });

  group('UI: propozycja zestawu i przycisk analizy w czacie', () {
    testWidgets('karta propozycji zestawu tworzy zestaw po kliknięciu',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: TrainerAiStructuredReply(
                message: 'Propozycja:',
                setSuggestion: AiSetSuggestion(
                  name: 'Full Body 2×',
                  days: [
                    AiSetSuggestionDay(
                      title: 'Dzień A',
                      exercises: [
                        AiExerciseSuggestion(
                            name: 'Przysiad', exerciseId: 'squat'),
                        AiExerciseSuggestion(
                            name: 'Pompki', exerciseId: 'pushup'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Full Body 2×'), findsOneWidget);
      expect(find.text('Dzień A'), findsOneWidget);
      expect(store.plans, isEmpty);

      await tester.tap(find.byKey(const Key('ai_set_suggestion_create')));
      await tester.pumpAndSettle();

      expect(store.plans, hasLength(1));
      final plan = store.plans.single;
      expect(plan.name, 'Full Body 2×');
      expect(plan.days.single.items, hasLength(2));
      expect(plan.origin.creationMode, PlanCreationMode.fullyAiGenerated);
      expect(plan.origin.sourceType, PlanSourceType.aiChat);
      expect(tester.takeException(), isNull);
    });

    testWidgets('przycisk analizy pojawia się i otwiera wybór trybu',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'push-plan',
        name: 'Push',
        note: '',
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
      ));
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: TrainerAiStructuredReply(
                message: 'Jasne, mogę to sprawdzić.',
                planAnalysisPlanId: 'push-plan',
                planAnalysisPlanName: 'Push',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_open_plan_analysis')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai_open_plan_analysis')));
      await tester.pumpAndSettle();

      expect(find.text('Analiza stałego dopasowania'), findsOneWidget);
      expect(find.text('Analiza na dzisiaj'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('usunięty zestaw nie zostawia martwego przycisku',
        (tester) async {
      final store = await _freshStore();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(
        store,
        const Scaffold(
          body: SingleChildScrollView(
            child: AiExerciseSuggestionsBlock(
              reply: TrainerAiStructuredReply(
                message: 'ok',
                planAnalysisPlanId: 'juz-nie-istnieje',
                planAnalysisPlanName: 'Stary zestaw',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_open_plan_analysis')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
