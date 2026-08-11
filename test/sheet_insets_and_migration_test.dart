import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/recommendation_engine.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC 18 — arkusze nie mogą chować się pod systemowym paskiem nawigacji,
/// także na małych ekranach; SPEC 31 — stare zapisy muszą się wczytywać.

const _plank = Exercise(
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

const _rx = SessionPrescription(
  base: Prescription(
      sets: 3, reps: 0, weightKg: 0, durationSec: 30, restSeconds: 60),
  recommended: Prescription(
      sets: 3, reps: 0, weightKg: 0, durationSec: 50, restSeconds: 60),
  reason: 'Poprzedni czas utrzymany stabilnie — dokładamy 5 s.',
  dataSource: 'history',
  hasEnoughHistory: true,
  decisionKey: 'PROGRESS',
  reasonBullets: [
    '+Poprzedni trening ukończony w całości',
    '+Brzuch: gotowość 91%',
    '-Krótki sen tej nocy',
  ],
  confidence: 0.78,
  targetRir: 2,
  previousSummary: '45 s · RPE 7',
  deltaSummary: '+5 s względem ostatniego treningu',
  limitingMuscleLabel: 'Brzuch',
  limitingReadinessPercent: 91,
);

Widget _host(AppStore store, Widget child) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(store: store, child: child),
    );

/// Ustawia REALNY systemowy inset dolny (pasek nawigacji / obszar gestów).
///
/// Musi iść przez `tester.view`, a nie przez lokalne `MediaQuery`: arkusze
/// modalne żyją w `Navigator` NAD drzewem `home`, więc lokalnej nakładki
/// w ogóle by nie zobaczyły — a to właśnie tam objawiał się błąd.
void _setSystemNavBar(WidgetTester tester, double logicalPixels) {
  final dpr = tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(bottom: logicalPixels * dpr);
  tester.view.viewPadding = FakeViewPadding(bottom: logicalPixels * dpr);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> store() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  group('Systemowy pasek nawigacji nie zasłania arkuszy', () {
    testWidgets('arkusz rekomendacji zostawia miejsce na pasek nawigacji',
        (tester) async {
      const navBar = 48.0;
      final appStore = await store();
      // Mały ekran + pasek nawigacji — najgorszy przypadek.
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _setSystemNavBar(tester, navBar);
      addTearDown(tester.view.reset);

      late BuildContext hostContext;
      await tester.pumpWidget(_host(
        appStore,
        Builder(builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      showRecommendationExplainSheet(hostContext, _plank, _rx);
      await tester.pumpAndSettle();

      // Główna rekomendacja jest na wierzchu i widoczna.
      expect(find.byKey(const Key('recommendation_headline')), findsOneWidget);

      // Przewijamy na sam dół i sprawdzamy, że ostatnia treść kończy się
      // NAD obszarem paska nawigacji.
      final scrollable = find.byType(Scrollable).last;
      await tester.drag(scrollable, const Offset(0, -1200));
      await tester.pumpAndSettle();

      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      final detailsToggle =
          find.byKey(const Key('recommendation_details_toggle'));
      expect(detailsToggle, findsOneWidget);
      expect(tester.getRect(detailsToggle).bottom,
          lessThanOrEqualTo(screenHeight - navBar),
          reason: 'ostatni element arkusza chowa się pod paskiem nawigacji');
      expect(tester.takeException(), isNull);
    });

    testWidgets('arkusz gotowości partii też respektuje pasek nawigacji',
        (tester) async {
      const navBar = 56.0;
      final appStore = await store();
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _setSystemNavBar(tester, navBar);
      addTearDown(tester.view.reset);

      late BuildContext hostContext;
      await tester.pumpWidget(_host(
        appStore,
        Builder(builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      // Bez `await` — arkusz zamyka dopiero użytkownik, a test tylko go rysuje.
      unawaited(showMuscleRecoverySheet(hostContext, BodyMuscle.chest, null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('muscle_readiness_percent')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('arkusz ostrzeżenia o gotowości mieści się na małym ekranie',
        (tester) async {
      const navBar = 48.0;
      final appStore = await store();
      await tester.binding.setSurfaceSize(const Size(320, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _setSystemNavBar(tester, navBar);
      addTearDown(tester.view.reset);

      const block = TodayTrainingBlock(
        order: 2,
        area: TrainingFocusArea.shoulders,
        catalogProgramId: 'program_shoulders',
        readinessPercent: 54,
        readinessWarning:
            'Przedni akton barków otrzymał już duży bodziec podczas Push. '
            'Możesz kontynuować trening, ale Trainer rekomenduje zmniejszenie '
            'intensywności lub objętości.',
        fatiguedMuscles: [
          (label: 'Barki przód', percent: 54.0),
          (label: 'Triceps', percent: 58.0),
        ],
      );

      late BuildContext hostContext;
      await tester.pumpWidget(_host(
        appStore,
        Builder(builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      unawaited(showBlockReadinessWarningSheet(hostContext, block));
      await tester.pumpAndSettle();

      final startAnyway = find.byKey(const Key('warning_start_anyway'));
      expect(startAnyway, findsOneWidget);
      // Arkusz jest przewijalny (treść ostrzeżenia bywa długa) — dojeżdżamy do
      // przycisku, a dopiero potem sprawdzamy, czy nie wpada pod pasek.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      expect(tester.getRect(startAnyway).bottom,
          lessThanOrEqualTo(screenHeight - navBar),
          reason: 'przycisk akcji nie może wpaść pod pasek nawigacji');
      expect(tester.takeException(), isNull);
    });
  });

  group('Zgodność wsteczna zapisów (spec 31)', () {
    test('recepta sesji sprzed wytłumaczalności wczytuje się bez strat', () {
      // Dokładnie taki JSON zapisywały wcześniejsze wersje aplikacji.
      final legacy = <String, dynamic>{
        'base': {
          'sets': 3,
          'reps': 10,
          'weightKg': 40.0,
          'durationSec': 0,
          'restSeconds': 90,
        },
        'recommended': {
          'sets': 3,
          'reps': 10,
          'weightKg': 42.5,
          'durationSec': 0,
          'restSeconds': 90,
        },
        'reason': 'Dwie stabilne sesje z rzędu.',
        'dataSource': 'history',
        'hasEnoughHistory': true,
        'isCalibrating': false,
      };
      final restored = SessionPrescription.fromJson(legacy);
      expect(restored.recommended.weightKg, 42.5);
      expect(restored.decisionKey, isEmpty);
      expect(restored.reasonBullets, isEmpty);
      expect(restored.confidence, 0);
      expect(restored.targetRir, 0);
      expect(restored.hasExplanation, isFalse);
      // Round-trip nowego formatu nie gubi wyjaśnień.
      final modern = SessionPrescription.fromJson(_rx.toJson());
      expect(modern.decisionKey, 'PROGRESS');
      expect(modern.reasonBullets, hasLength(3));
      expect(modern.positiveReasons, hasLength(2));
      expect(modern.negativeReasons, hasLength(1));
      expect(modern.targetRir, 2);
      expect(modern.confidence, closeTo(0.78, 0.001));
      expect(RecommendationDecision.fromKey(modern.decisionKey),
          RecommendationDecision.progress);
    });

    test('nieznana decyzja nie wywala parsera', () {
      expect(RecommendationDecision.fromKey('COS_NOWEGO'),
          RecommendationDecision.maintain);
      expect(RecommendationDecision.fromKey(null),
          RecommendationDecision.maintain);
    });

    test('stara sesja treningowa bez recepty nadal działa', () {
      final legacy = <String, dynamic>{
        'exerciseId': 'plank',
        'plannedSets': 3,
        'plannedReps': 0,
        'suggestedWeightKg': 0,
        'restSeconds': 60,
        'note': '',
        'completedSets': <dynamic>[],
      };
      final restored = ActiveWorkoutExercise.fromJson(legacy);
      expect(restored.prescription, isNull);
      // Bez recepty timer bierze czas bazowy ćwiczenia.
      expect(restored.effectiveDurationSec(45), 45);
    });

    test('uszkodzona migawka regeneracji jest po prostu pomijana', () {
      expect(RecoverySnapshot.fromJson(<String, dynamic>{}), isNull);
      expect(
          RecoverySnapshot.fromJson(<String, dynamic>{'muscle': 'nieistniejacy'}),
          isNull);
    });
  });
}
