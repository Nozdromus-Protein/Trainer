import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.updateSettings(
        store.settings.copyWith(trainingWeekdays: [1, 2, 3, 4, 5, 6]));
    return store;
  }

  Widget wrap(AppStore store) => AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: TrainingRotationPage()),
        ),
      );

  testWidgets('pokazuje obie kolumny dla wszystkich siedmiu dni',
      (tester) async {
    final store = await makeStore();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    // Niedziela też jest na liście — można ją włączyć do rozkładu.
    for (final weekday in [1, 2, 3, 4, 5, 6, 7]) {
      expect(find.byKey(Key('rotation_day_$weekday')), findsOneWidget);
      expect(find.byKey(Key('rotation_second_$weekday')), findsOneWidget);
    }
  });

  testWidgets('otwiera stary plan z obszarami zapisanymi w złych kolumnach',
      (tester) async {
    final store = await makeStore();
    await store.updateSettings(store.settings.copyWith(
      trainingSchedule: const TrainingScheduleConfig(
        // Stary zapis pochodzi z rozkładu dwutorowego — tak też go czytamy.
        strategy: TrainingSplitStrategy.twoTrack,
        weekdayPlans: {
          1: TrainingDayPlan(
            primary: TrainingFocusArea.shoulders,
            secondary: TrainingFocusArea.legs,
          ),
        },
        trainingWeekdays: [1],
      ),
    ));
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.trainingScheduleConfig.planForWeekday(1).primary,
        TrainingFocusArea.legs);
    expect(store.trainingScheduleConfig.planForWeekday(1).secondary,
        TrainingFocusArea.shoulders);
  });

  testWidgets('zmiana partii głównej zapisuje się i trzyma na przyszłość',
      (tester) async {
    final store = await makeStore();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rotation_day_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TrainingFocusArea.legs.label).last);
    await tester.pumpAndSettle();

    expect(rotationByWeekday(store.trainingScheduleConfig)[1],
        TrainingFocusArea.legs);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dodatek dnia zapisuje się osobno od partii głównej',
      (tester) async {
    final store = await makeStore();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    final before = rotationByWeekday(store.trainingScheduleConfig)[2];
    await tester.tap(find.byKey(const Key('rotation_second_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TrainingFocusArea.arms.label).last);
    await tester.pumpAndSettle();

    expect(secondaryByWeekday(store.trainingScheduleConfig)[2],
        TrainingFocusArea.arms);
    expect(rotationByWeekday(store.trainingScheduleConfig)[2], before,
        reason: 'partia główna dnia nie może się zmienić przy edycji dodatku');
  });

  testWidgets('dzień wolny znika z dni treningowych', (tester) async {
    final store = await makeStore();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rotation_day_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dzień wolny').last);
    await tester.pumpAndSettle();

    expect(store.trainingScheduleConfig.planForWeekday(3).isRest, isTrue);
    expect(store.settings.trainingWeekdays, isNot(contains(3)));
  });

  testWidgets('reset przywraca domyślny rozkład', (tester) async {
    final store = await makeStore();
    await store.setWeekdayPlan(1, TrainingDayPlan.rest);
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(store));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('rotation_reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rotation_reset')));
    await tester.pumpAndSettle();

    // Każdy dzień treningowy znów ma obie kolumny wypełnione.
    final config = store.trainingScheduleConfig;
    for (final weekday in store.settings.trainingWeekdays) {
      expect(config.planForWeekday(weekday).primary, isNotNull);
      expect(config.planForWeekday(weekday).secondary, isNotNull);
    }
  });
}
