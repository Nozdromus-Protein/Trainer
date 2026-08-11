import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy UI rekomendacji sesji: plan pokazany PRZED wykonaniem (z ikoną AI
/// i arkuszem „dlaczego") oraz dolny margines listy podsumowania.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kafelki kolejki i odpoczynku', _tileVisibilityTests);

  const plank = Prescription(
      sets: 2, reps: 0, weightKg: 0, durationSec: 45, restSeconds: 60);
  const plankRecommended = Prescription(
      sets: 2, reps: 0, weightKg: 0, durationSec: 50, restSeconds: 60);

  Widget wrap(AppStore store, Widget child, {double bottomInset = 0}) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: MediaQuery(
        data: MediaQueryData(
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: AppScope(store: store, child: child),
      ),
    );
  }

  // ===========================================================================
  // 2. Ekran ćwiczenia pokazuje rekomendację od razu + ikona AI + „dlaczego"
  // ===========================================================================

  group('Linia planu sesji na ekranie ćwiczenia', () {
    testWidgets('pokazuje wartości rekomendowane, nie bazowe', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      await tester.pumpWidget(wrap(
        store,
        const Scaffold(
          body: SessionPlanLine(
            exercise: _plankExercise,
            prescription: SessionPrescription(
              base: plank,
              recommended: plankRecommended,
              reason: 'Poprzedni czas utrzymany stabilnie — dokładamy 5 s.',
              dataSource: 'history',
              hasEnoughHistory: true,
            ),
          ),
        ),
      ));
      await tester.pump();

      // Rekomendacja (50 s), a nie plan bazowy (45 s).
      expect(find.text('2 × 50 s · przerwa 60 s'), findsOneWidget);
      expect(find.text('2 × 45 s · przerwa 60 s'), findsNothing);
      // Ikona AI, bo rekomendacja zmieniła plan bazowy.
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bez zmiany względem bazy NIE pokazuje ikony AI',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      await tester.pumpWidget(wrap(
        store,
        const Scaffold(
          body: SessionPlanLine(
            exercise: _plankExercise,
            prescription: SessionPrescription(
              base: plank,
              recommended: plank, // identyczna z bazą
              reason: '',
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('2 × 45 s · przerwa 60 s'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    });

    testWidgets('klik otwiera arkusz z bazą, rekomendacją i powodem',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      await tester.pumpWidget(wrap(
        store,
        const Scaffold(
          body: SessionPlanLine(
            exercise: _plankExercise,
            prescription: SessionPrescription(
              base: plank,
              recommended: plankRecommended,
              reason: 'Poprzedni czas utrzymany stabilnie — dokładamy 5 s.',
              dataSource: 'history',
              hasEnoughHistory: true,
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('2 × 50 s · przerwa 60 s'));
      await tester.pumpAndSettle();

      expect(find.text('Rekomendacja Trainera'), findsOneWidget);
      // GŁÓWNA rekomendacja na wierzchu (spec 19): jedna liczba, duża.
      expect(find.byKey(const Key('recommendation_headline')), findsOneWidget);
      expect(find.text('2 × 50 s'), findsOneWidget);
      // Powód widoczny od razu (sekcja „Dlaczego?" startuje rozwinięta).
      expect(find.text('Dlaczego?'), findsOneWidget);
      expect(
        find.text('Poprzedni czas utrzymany stabilnie — dokładamy 5 s.'),
        findsOneWidget,
      );

      // Szczegóły są ZWINIĘTE — użytkownik nie jest zalewany danymi.
      expect(find.text('Wartość bazowa'), findsNothing);
      await tester.tap(find.byKey(const Key('recommendation_details_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Wartość bazowa'), findsOneWidget);
      expect(find.text('Rekomendacja'), findsOneWidget);
      expect(find.text('2 × 45 s · przerwa 60 s'), findsOneWidget); // baza
      expect(find.text('Oparto na Twojej historii tego ćwiczenia.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('arkusz informuje o braku wystarczającej historii',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      await tester.pumpWidget(wrap(
        store,
        const Scaffold(
          body: SessionPlanLine(
            exercise: _plankExercise,
            prescription: SessionPrescription(
              base: plank,
              recommended: plankRecommended,
              reason: 'Ostrożny start.',
              dataSource: 'calibration',
              isCalibrating: true,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('2 × 50 s · przerwa 60 s'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recommendation_details_toggle')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Za mało wykonań'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // 14. Ostatni element podsumowania nie jest zasłonięty przez dolny pasek
  // ===========================================================================

  group('Podsumowanie treningu', () {
    final summary = CompletedWorkoutSummary(
      sessionId: 'summary-pad',
      name: 'Plan · Dzień 1',
      startedAt: DateTime(2026, 7, 16, 18),
      endedAt: DateTime(2026, 7, 16, 18, 45),
      exerciseCount: 2,
      setCount: 4,
      volume: 1200,
      averageRpe: 7,
    );

    // Wymaganie: ostatni element podsumowania musi być w całości widoczny nad
    // systemowym paskiem nawigacji. Obszar paska odsuwa SafeArea wokół listy —
    // ten test pilnuje, żeby ta ochrona nie zniknęła przy zmianach layoutu.
    testWidgets('ostatni element listy nie chowa się za paskiem nawigacji',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      const navBar = 48.0;
      await tester.pumpWidget(
        wrap(store, WorkoutSummaryPage(summary: summary), bottomInset: navBar),
      );
      await tester.pump();

      // Przewiń na sam dół listy (kilka razy, aż do końca zakresu).
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
      }
      final position = tester
          .state<ScrollableState>(find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)))
          .position;
      // Bez dojechania do końca test nie badałby tego, co trzeba.
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0),
          reason: 'Lista musi być przewinięta do końca');

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final doneButton = find.widgetWithText(FilledButton, 'Gotowe');
      expect(doneButton, findsOneWidget);
      final buttonBottom = tester.getRect(doneButton).bottom;
      // Przycisk musi kończyć się nad obszarem systemowego paska nawigacji.
      expect(buttonBottom, lessThanOrEqualTo(screenHeight - navBar),
          reason: 'Ostatni element jest zasłonięty przez pasek nawigacji');
      expect(tester.takeException(), isNull);
    });

    testWidgets('nie pokazuje sekcji rozciągania ani danych technicznych',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();

      await tester
          .pumpWidget(wrap(store, WorkoutSummaryPage(summary: summary)));
      await tester.pump();

      // Punkt 8: brak osobnych sekcji rozciągania.
      expect(find.text('Rozciąganie po treningu'), findsNothing);
      expect(find.text('Całe rozciąganie'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Deska jako stała definicja — czasowe ćwiczenie z masy ciała.
const _plankExercise = Exercise(
  id: 'plank',
  name: 'Deska',
  category: 'Brzuch',
  muscles: ['brzuch'],
  equipment: 'masa ciała',
  level: 'Początkujący',
  illustrationType: 'plank',
  description: '',
  tips: [],
  commonMistakes: [],
  defaultSets: 3,
  defaultReps: 0,
  defaultDurationSec: 45,
  met: 3.0,
  entryTypeKey: 'bodyweight_time',
);

/// Ikona rekomendacji i plan efektywny muszą być widoczne także POZA
/// wykonywaniem ćwiczenia — w kolejce i na ekranie odpoczynku.
void _tileVisibilityTests() {
  testWidgets('kompaktowa linia planu pokazuje rekomendację i ikonę AI',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(
        store: store,
        child: const Scaffold(
          body: SessionPlanLine(
            exercise: _plankExercise,
            compact: true,
            prescription: SessionPrescription(
              base: Prescription(
                  sets: 2,
                  reps: 0,
                  weightKg: 0,
                  durationSec: 45,
                  restSeconds: 60),
              recommended: Prescription(
                  sets: 2,
                  reps: 0,
                  weightKg: 0,
                  durationSec: 50,
                  restSeconds: 60),
              reason: 'Stabilnie — +5 s.',
              dataSource: 'history',
              hasEnoughHistory: true,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Wartość rekomendowana (50 s), nie bazowa (45 s) — tak jak wystartuje timer.
    expect(find.text('2 × 50 s · przerwa 60 s'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
