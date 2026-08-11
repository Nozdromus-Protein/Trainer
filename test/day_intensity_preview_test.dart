import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/deload_cycle.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanItem _item(String id) =>
    PlanItem(exerciseId: id, sets: 4, reps: 8, durationSec: 0, note: 'Seria główna');

Future<AppStore> _store(DateTime deloadStart) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  // Trenujemy każdego dnia tygodnia — rzutowanie dnia programu zawsze wypada.
  await store.updateSettings(
      store.settings.copyWith(trainingWeekdays: [1, 2, 3, 4, 5, 6, 7]));
  // Rozkład PINUJEMY na NOGI w każdym dniu tygodnia. Bez tego test zależał od
  // dnia, w którym jest uruchamiany: w domyślnej rotacji Push/Pull/Legs data
  // „dziś + 10" wypadała czasem na dzień CIĄGNIĘCIA, którego zestaw z tego
  // testu (przysiad + pompka) w ogóle nie pokrywa — wtedy podgląd dnia nie miał
  // czego pokazać i asercje leciały bez związku ze zmianą w kodzie.
  for (var weekday = 1; weekday <= 7; weekday++) {
    await store.setWeekdayPlan(
        weekday, const TrainingDayPlan(primary: TrainingFocusArea.legs));
  }
  await store.addWorkoutPlan(WorkoutPlan(
    id: 'preview-plan',
    name: 'Program testowy',
    note: '',
    goal: 'Masa',
    isActive: true,
    level: 'Średniozaawansowany',
    days: [
      for (var i = 0; i < 30; i++)
        WorkoutDay(
          weekday: (i % 7) + 1,
          title: 'Dzień ${i + 1} · Siła A — ciężka',
          items: [_item('squat'), _item('pushup')],
        ),
    ],
  ));
  await store.updateDeloadCycle(
      reanchorDeloadStart(store.deloadCycle, deloadStart));
  return store;
}

Widget _wrap(AppStore store, DateTime date) => AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: Scaffold(body: DayIntensityPreviewPage(date: date)),
      ),
    );

String _percentText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('preview_intensity_percent')))
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final deloadStart = today.add(const Duration(days: 10));

  testWidgets('dzień deloadu: faza, niska intensywność i lżejszy zestaw',
      (tester) async {
    final store = await _store(deloadStart);
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store, deloadStart));
    await tester.pumpAndSettle();

    expect(find.textContaining('Deload — dzień 1/7'), findsOneWidget);
    expect(_percentText(tester), '55%');
    expect(find.textContaining('Lekka (deload)'), findsOneWidget);
    // Zestaw na ten dzień jest pokazany i opisany jako deload.
    expect(find.byKey(const Key('preview_day_title')), findsOneWidget);
    expect(find.textContaining('deload'), findsWidgets);
  });

  testWidgets('dzień po deloadzie: mocne wejście i zestaw na 100%',
      (tester) async {
    final store = await _store(deloadStart);
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Okno deloadu: +10..+16, więc +17 to pierwszy dzień po nim.
    await tester.pumpWidget(_wrap(store, today.add(const Duration(days: 17))));
    await tester.pumpAndSettle();

    expect(find.textContaining('1. dzień po deloadzie'), findsOneWidget);
    expect(_percentText(tester), '100%');
    expect(find.textContaining('Bardzo mocna'), findsOneWidget);
    expect(find.byKey(const Key('preview_day_title')), findsOneWidget);
    // Pozycje zestawu opisane procentem ciężaru roboczego.
    expect(find.textContaining('≈100% ciężaru'), findsWidgets);
  });

  testWidgets('legenda jest uporządkowana, a długi opis rozwija się kliknięciem',
      (tester) async {
    final store = await _store(deloadStart);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store, today.add(const Duration(days: 17))));
    await tester.pumpAndSettle();

    // Legenda jako osobny, poukładany blok.
    expect(find.byKey(const Key('preview_legend')), findsOneWidget);
    expect(find.text('Co znaczą opisy pod ćwiczeniami'), findsOneWidget);
    expect(find.text('Seria główna'), findsOneWidget);
    expect(find.text('≈X% ciężaru roboczego'), findsOneWidget);

    // Opis pod ćwiczeniem startuje zwinięty (1 linia) i rozwija się po kliknięciu.
    final noteFinder = find.textContaining('≈100% ciężaru roboczego').first;
    expect(tester.widget<Text>(noteFinder).maxLines, 1);

    await tester.ensureVisible(noteFinder);
    await tester.pumpAndSettle();
    await tester.tap(noteFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.textContaining('≈100% ciężaru roboczego').first).maxLines,
        isNull, reason: 'po rozwinięciu opis nie jest już przycinany');
    expect(tester.takeException(), isNull);
  });

  testWidgets('koniec bloku: intensywność niższa, ale nie za niska',
      (tester) async {
    final store = await _store(deloadStart);
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Ostatni dzień bloku przed kolejnym deloadem (+17 start bloku, +51 koniec).
    await tester.pumpWidget(_wrap(store, today.add(const Duration(days: 51))));
    await tester.pumpAndSettle();

    final percent = int.parse(_percentText(tester).replaceAll('%', ''));
    expect(percent, lessThan(100));
    expect(percent, greaterThanOrEqualTo(85));
  });
}
