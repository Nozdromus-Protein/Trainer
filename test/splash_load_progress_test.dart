import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/presentation/splash_screen.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ekran ładowania: pasek jest OKREŚLONY (procent + krok małym druczkiem),
// a AppStore.load raportuje postęp rosnąco aż do 100% i rozgrzewa ciężkie
// zbiory, żeby pierwsze wejście w zakładkę nie doczytywało danych.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load raportuje rosnący postęp i kończy na 100%', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();

    final steps = <double>[];
    final labels = <String>[];
    await store.load(onProgress: (progress, label) {
      steps.add(progress);
      labels.add(label);
    });

    expect(steps, isNotEmpty);
    expect(steps.first, lessThan(0.2));
    expect(steps.last, 1.0);
    // Postęp nigdy się nie cofa — pasek ma iść tylko w prawo.
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThanOrEqualTo(steps[i - 1]),
          reason: 'krok $i cofnął pasek: ${steps[i - 1]} → ${steps[i]}');
    }
    expect(labels.every((label) => label.trim().isNotEmpty), isTrue);
    expect(labels.last, 'Gotowe');
  });

  test('load rozgrzewa bazę ćwiczeń i katalog programów', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    expect(store.warmedExerciseCount, 0);

    await store.load();

    expect(store.warmedExerciseCount, greaterThan(0));
    expect(store.warmedProgramCount, greaterThan(0));
  });

  testWidgets('splash pokazuje procent i nazwę kroku', (tester) async {
    final progress = ValueNotifier<AppLoadProgress>(
        const AppLoadProgress(0.4, 'Wczytuję ustawienia…'));
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(home: TrainerSplashScreen(progress: progress)),
    );
    await tester.pump();

    expect(find.text('40% · Wczytuję ustawienia…'), findsOneWidget);

    progress.value = const AppLoadProgress(1, 'Gotowe');
    // Bez pumpAndSettle: logo pulsuje w pętli, więc splash nigdy się nie
    // „uspokaja" — pompujemy tyle, ile trwa dojazd paska.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('100% · Gotowe'), findsOneWidget);
  });

  testWidgets('splash bez postępu nie pokazuje procentu', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TrainerSplashScreen()));
    await tester.pump();

    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
