import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutLog _log(DateTime date) {
  return WorkoutLog(
    id: 'log_${date.microsecondsSinceEpoch}',
    exerciseId: 'pushup',
    date: date,
    sets: 3,
    reps: 10,
    weightKg: 40,
    durationSec: 900,
    rpe: 7,
    calories: 100,
    note: '',
    aiConfidence: 0,
    sessionId: 'session_${date.day}',
    sessionName: 'Trening dnia ${date.day}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('kafelek kalendarza: nagłówek z dniem, kalendarz miesiąca i przejście do historii', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final now = DateTime.now();
    final trainedDay = DateTime(now.year, now.month, now.day, 18);
    store.logs.add(_log(trainedDay));
    // Wyższa powierzchnia: podgląd dnia to lista — kafelek historii musi
    // znaleźć się w zbudowanym zakresie.
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: TrainingWeekCalendarCard()),
        ),
      ),
    );
    await tester.pump();

    // Nagłówek nazywa aktywny dzień słownie; strzałek zmiany dnia nie ma.
    expect(find.text(weekdayName(now.weekday)), findsOneWidget);
    expect(find.text(trainerHistoryFullDate(now)), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // Pasek tygodnia pokazuje skrót dnia + ikonę + dzień zestawu z rozkładu
    // (tak samo jak w „Treningu"), także dla dnia aktywnego.
    const dayLetters = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
    expect(find.text(dayLetters[now.weekday - 1]), findsOneWidget);

    // Dotknięcie nagłówka otwiera kalendarz miesiąca z dniem treningu.
    await tester.tap(find.byKey(const Key('training_calendar_header')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('calendar_trained_day_${now.day}')), findsOneWidget);
    expect(find.byKey(const Key('calendar_prev_month')), findsOneWidget);

    // Dotknięcie dnia otwiera PODGLĄD DNIA (faza cyklu + intensywność zestawu),
    // a z niego wchodzi się w historię tego dnia.
    await tester.tap(find.byKey(Key('calendar_trained_day_${now.day}')));
    await tester.pumpAndSettle();
    expect(find.text('Podgląd dnia'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('preview_open_history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview_open_history')));
    await tester.pumpAndSettle();
    expect(find.text('Historia treningów'), findsOneWidget);
    expect(find.text('Trening dnia ${now.day}'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kalendarz miesiąca przełącza miesiące i zamyka się bez wyboru', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: TrainingWeekCalendarCard()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('training_calendar_header')));
    await tester.pumpAndSettle();

    // Zmiana miesiąca działa (chevrony żyją wewnątrz dialogu).
    await tester.tap(find.byKey(const Key('calendar_prev_month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_next_month')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zamknij'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar_prev_month')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
