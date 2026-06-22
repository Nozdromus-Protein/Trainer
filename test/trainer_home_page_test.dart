import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Trainer home renders all foundation tiles on a narrow screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          store: store,
          child: Scaffold(
            body: TrainerHomePage(
              onToday: () {},
              onExercises: () {},
              onHistory: () {},
              onPlans: () {},
              onProgress: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dzisiejszy trening'), findsOneWidget);
    expect(find.text('Baza ćwiczeń'), findsOneWidget);
    expect(find.text('Historia'), findsOneWidget);
    expect(find.text('Plany treningowe'), findsOneWidget);
    expect(find.text('Progres'), findsOneWidget);
    expect(find.text('Ustawienia Trainera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
