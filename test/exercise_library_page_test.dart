import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all starter exercises expose complete stage 2 metadata', () {
    for (final exercise in ExerciseRepo.all) {
      expect(exercise.name, isNotEmpty, reason: exercise.id);
      expect(exercise.primaryMuscle, isNotEmpty, reason: exercise.id);
      expect(exercise.equipment, isNotEmpty, reason: exercise.id);
      expect(exercise.description, isNotEmpty, reason: exercise.id);
      expect(exercise.commonMistakes, isNotEmpty, reason: exercise.id);
      expect(exercise.avoidWhen, isNotEmpty, reason: exercise.id);
      expect(exercise.alternatives, isNotEmpty, reason: exercise.id);
      expect(exercise.trainingGoals, isNotEmpty, reason: exercise.id);
      expect(exercise.executionSteps, isNotEmpty, reason: exercise.id);
      expect(exercise.breathing, isNotEmpty, reason: exercise.id);
      expect(exercise.tempo, isNotEmpty, reason: exercise.id);
      expect(exercise.easierVersion, isNotEmpty, reason: exercise.id);
      expect(exercise.harderVersion, isNotEmpty, reason: exercise.id);
    }
  });

  test('favorite, hidden and edited exercise survive local reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final editedSquat = ExerciseRepo.byId('squat').copyWith(
      description: 'Lokalnie zmieniona technika.',
      source: 'edited',
    );

    await store.addCustomExercise(editedSquat);
    await store.toggleExerciseFavorite('squat');
    await store.setExerciseHidden('run', true);

    final restored = AppStore();
    await restored.load();

    expect(restored.isExerciseFavorite('squat'), isTrue);
    expect(restored.isExerciseHidden('run'), isTrue);
    expect(
      ExerciseRepo.byId('squat', restored.customExercises).description,
      'Lokalnie zmieniona technika.',
    );
  });

  testWidgets('exercise library has no overflow on a narrow dark screen',
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
          child: const Scaffold(body: SafeArea(child: ExercisesPage())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Baza ćwiczeń'), findsOneWidget);
    expect(find.text('Partia mięśniowa'), findsOneWidget);
    expect(find.text('Sprzęt'), findsOneWidget);
    expect(find.text('Poziom trudności'), findsOneWidget);
    expect(find.text('Cel treningowy'), findsOneWidget);
    expect(find.text('Przysiad'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
