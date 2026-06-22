import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adding exercise to a plan persists and prevents duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final plan = store.plans.first;
    final day = plan.days.first;
    final exercise = ExerciseRepo.all.firstWhere(
      (item) => !day.items.any((planItem) => planItem.exerciseId == item.id),
    );

    final firstAdd = await store.addExerciseToPlan(
      exerciseId: exercise.id,
      planId: plan.id,
      weekday: day.weekday,
    );
    final secondAdd = await store.addExerciseToPlan(
      exerciseId: exercise.id,
      planId: plan.id,
      weekday: day.weekday,
    );

    final restored = AppStore();
    await restored.load();
    final restoredDay = restored.plans
        .firstWhere((item) => item.id == plan.id)
        .days
        .firstWhere((item) => item.weekday == day.weekday);

    expect(firstAdd, isTrue);
    expect(secondAdd, isFalse);
    expect(
      restoredDay.items.where((item) => item.exerciseId == exercise.id),
      hasLength(1),
    );
  });

  testWidgets('exercise details stay overflow-free on a narrow dark screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Colors.teal, false),
        darkTheme: buildTheme(Colors.teal, true),
        themeMode: ThemeMode.dark,
        home: AppScope(
          store: store,
          child: const ExerciseDetailsPage(exerciseId: 'squat'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Przysiad'), findsOneWidget);
    expect(find.text('Dodaj do planu'), findsOneWidget);
    expect(find.text('Dodaj do ulubionych'), findsOneWidget);
    expect(find.text('Mapa zaangażowanych mięśni'), findsOneWidget);
    expect(find.text('Dodaj do dziennika'), findsNothing);
    expect(find.text('Analiza techniki przez backend'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Wykonanie krok po kroku'),
      300,
    );
    expect(find.text('Wykonanie krok po kroku'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Oddychanie'), 300);
    expect(find.text('Oddychanie'), findsOneWidget);
    expect(find.text('Tempo ruchu'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Warianty trudności'), 300);
    expect(find.text('Łatwiejsza wersja'), findsOneWidget);
    expect(find.text('Trudniejsza wersja'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add to plan button opens local day picker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          store: store,
          child: const ExerciseDetailsPage(exerciseId: 'goblet_squat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj do planu'));
    await tester.pumpAndSettle();

    expect(find.text('Wybierz dzień dla: Goblet squat'), findsOneWidget);
    expect(find.text(weekdayName(store.plans.first.days.first.weekday)),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite action saves from the details screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          store: store,
          child: const ExerciseDetailsPage(exerciseId: 'squat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj do ulubionych'));
    await tester.pumpAndSettle();

    final restored = AppStore();
    await restored.load();
    expect(restored.isExerciseFavorite('squat'), isTrue);
    expect(find.text('Usuń z ulubionych'), findsOneWidget);
  });
}
