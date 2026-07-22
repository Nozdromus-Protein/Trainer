import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutLog _log(DateTime date) => WorkoutLog(
      id: 'log_${date.microsecondsSinceEpoch}',
      exerciseId: 'squat',
      date: date,
      sets: 3,
      reps: 10,
      weightKg: 40,
      durationSec: 900,
      rpe: 8,
      calories: 120,
      note: '',
      aiConfidence: 0,
      sessionId: 'session',
      sessionName: 'Trening',
    );

Future<AppStore> _store({bool deloadNow = false}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  if (deloadNow) await store.startDeloadNow();
  return store;
}

Widget _wrap(AppStore store, Widget child) => AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kontekst deloadu w regeneracji', () {
    testWidgets('milczy, gdy deload jest daleko', (tester) async {
      final store = await _store();
      await tester.pumpWidget(_wrap(store, const DeloadRecoveryContextCard()));
      await tester.pump();
      expect(find.byKey(const Key('recovery_deload_context')), findsNothing);
    });

    testWidgets('tłumaczy lepszą regenerację w tygodniu deloadu',
        (tester) async {
      final store = await _store(deloadNow: true);
      await tester.pumpWidget(_wrap(store, const DeloadRecoveryContextCard()));
      await tester.pump();
      expect(find.byKey(const Key('recovery_deload_context')), findsOneWidget);
      expect(find.textContaining('Tydzień deloadu'), findsOneWidget);
    });
  });

  group('Podsumowanie cyklu dla trenera', () {
    test('tekst zawiera fazę, intensywność i rozpiskę tygodni', () async {
      final store = await _store(deloadNow: true);
      final text = buildTrainingCycleSummaryText(store);
      expect(text, contains('podsumowanie cyklu'));
      expect(text, contains('DELOAD'));
      expect(text, contains('Intensywność dziś: 55%'));
      expect(text, contains('Tydzień 1'));
    });

    test('rozpiska bloku startuje mocno i słabnie ku końcowi', () async {
      final store = await _store(deloadNow: true);
      final weeks = cycleIntensityByWeek(store);
      expect(weeks, hasLength(5)); // 35 dni = 5 tygodni
      expect(weeks.first.percent, 100);
      expect(weeks.last.percent, lessThan(weeks.first.percent));
      expect(weeks.last.percent, greaterThanOrEqualTo(85));
    });

    testWidgets('strona pozwala skopiować podsumowanie', (tester) async {
      final store = await _store(deloadNow: true);
      // Schowek idzie przez kanał platformy — w teście trzeba go obsłużyć.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: TrainingCycleSummaryPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Intensywność tydzień po tygodniu'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cycle_summary_copy')));
      await tester.pumpAndSettle();
      expect(find.text('Podsumowanie skopiowane do schowka.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Historia mezocykli', () {
    testWidgets('ukryta bez danych, widoczna z objętością', (tester) async {
      final empty = await _store();
      await tester.pumpWidget(_wrap(empty, const MesocycleHistoryCard()));
      await tester.pump();
      expect(find.byKey(const Key('mesocycle_history')), findsNothing);

      final withLogs = await _store();
      withLogs.logs.add(_log(DateTime.now()));
      await tester.pumpWidget(_wrap(withLogs, const MesocycleHistoryCard()));
      await tester.pump();
      expect(find.byKey(const Key('mesocycle_history')), findsOneWidget);
      expect(find.text('Historia mezocykli'), findsOneWidget);
    });
  });
}
