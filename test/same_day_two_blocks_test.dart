import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// „Dzisiejszy trening" nie może zamykać dnia po pierwszym zestawie tylko
// dlatego, że blok główny zmęczył partie WSPÓLNE z dodatkiem. Klatka i barki
// (albo push / pull / legs w rotacji) dzielą przedni bark i triceps — to normalny
// trening, a nie powód do skasowania drugiego zestawu.

Future<AppStore> _storeWithDay(
  TrainingFocusArea primary,
  TrainingFocusArea secondary, {
  TrainingSplitStrategy strategy = TrainingSplitStrategy.twoTrack,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.updateTrainingSchedule(
      store.settings.trainingSchedule.copyWith(strategy: strategy));
  await store.setWeekdayPlan(
    DateTime.now().weekday,
    TrainingDayPlan(primary: primary, secondary: secondary),
  );
  return store;
}

Future<void> _logExercise(AppStore store, String exerciseId) async {
  final now = DateTime.now();
  await store.addLog(WorkoutLog(
    id: 'log_$exerciseId',
    exerciseId: exerciseId,
    date: DateTime(now.year, now.month, now.day),
    sets: 4,
    reps: 8,
    weightKg: 60,
    durationSec: 1200,
    rpe: 8,
    calories: 200,
    note: '',
    aiConfidence: 0,
    sessionId: 'sess_$exerciseId',
    sessionName: 'Trening',
    performedAt: now,
  ));
}

TodayTrainingBlock _block(AppStore store, TrainingFocusArea area) =>
    store.todayTrainingBlocks().firstWhere((b) => b.area == area);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('barki po klatce zostają w dniu — zestaw klatki ich nie kasuje',
      () async {
    final store = await _storeWithDay(
        TrainingFocusArea.chestTriceps, TrainingFocusArea.shoulders);

    // Ciężki zestaw klatki: przedni bark i triceps pracują jako pomocnicze.
    await _logExercise(store, 'bench_press');

    final blocks = store.todayTrainingBlocks();
    expect(blocks, hasLength(2),
        reason: 'dodatek dnia nie może zniknąć po zestawie głównym');
    expect(_block(store, TrainingFocusArea.chestTriceps).isDone, isTrue);
    expect(_block(store, TrainingFocusArea.shoulders).isDone, isFalse,
        reason: 'wyciskanie leżąc to nie jest wykonany zestaw barków');
    expect(store.isTodayTrainingClosed(), isFalse);
    expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.shoulders);
  });

  test('klatka po barkach: zestaw barków nie odhacza klatki', () async {
    final store = await _storeWithDay(
        TrainingFocusArea.chestTriceps, TrainingFocusArea.shoulders);

    // Najpierw barki (wyciskanie nad głowę — partia główna to barki).
    await _logExercise(store, 'shoulder_press');

    expect(_block(store, TrainingFocusArea.shoulders).isDone, isTrue);
    expect(_block(store, TrainingFocusArea.chestTriceps).isDone, isFalse,
        reason: 'przedni bark w dniu barków nie oznacza zrobionej klatki');
    expect(store.isTodayTrainingClosed(), isFalse);
  });

  test('dzień zamyka się dopiero, gdy OBA zestawy są zrobione', () async {
    final store = await _storeWithDay(
        TrainingFocusArea.chestTriceps, TrainingFocusArea.shoulders);
    await _logExercise(store, 'bench_press');
    expect(store.isTodayTrainingClosed(), isFalse);
    await _logExercise(store, 'shoulder_press');
    expect(store.isTodayTrainingClosed(), isTrue);
  });

  test('zrobiony dzień NIE jest przestawiany przez własne zmęczenie', () async {
    final store = await _storeWithDay(
        TrainingFocusArea.chestTriceps, TrainingFocusArea.shoulders);
    // Jutro w rozkładzie są nogi — kandydat do podmiany.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await store.setWeekdayPlan(
      tomorrow.weekday,
      const TrainingDayPlan(
          primary: TrainingFocusArea.legs,
          secondary: TrainingFocusArea.forearms),
    );

    // Już po PIERWSZYM zestawie dzień jest w trakcie realizacji.
    await _logExercise(store, 'bench_press');
    expect(store.todayScheduled?.area, TrainingFocusArea.chestTriceps,
        reason: 'dzień w trakcie nie może zmienić partii pod nosem');

    await _logExercise(store, 'shoulder_press');

    final today = store.todayScheduled;
    expect(today, isNotNull);
    expect(today!.area, TrainingFocusArea.chestTriceps,
        reason: 'zrobiona klatka nie może zamienić się w nogi tylko dlatego, '
            'że po treningu jest zmęczona');
    expect(today.moved, isFalse);
    expect(today.loadTier, DayLoadTier.full,
        reason: 'wykonanego dnia nie odchudzamy „pod regenerację"');
    expect(store.isScheduleDayDone(today), isTrue);
    expect(store.isTodayTrainingClosed(), isTrue);
  });

  test('dodatek zostaje, gdy zmęczona jest tylko połowa jego partii', () {
    final now = DateTime(2026, 8, 3);
    final recovery = {
      // Po dniu pchania: triceps na dnie, biceps świeży.
      BodyMuscle.triceps: const MuscleRecoveryState(
        muscleGroup: BodyMuscle.triceps,
        recoveryPercent: 20,
        status: RecoveryStatus.freshFatigue,
      ),
      BodyMuscle.biceps: const MuscleRecoveryState(
        muscleGroup: BodyMuscle.biceps,
        recoveryPercent: 96,
        status: RecoveryStatus.recovered,
      ),
    };
    // Najsłabsza partia wyrzuciłaby „Ramiona" z dnia…
    expect(
      scheduleReadiness(TrainingFocusArea.arms, now, now, recovery),
      lessThan(60),
    );
    // …ale dodatek oceniamy NAJLEPSZĄ partią: biceps jest gotowy, więc jest co
    // trenować i zestaw zostaje w dniu.
    expect(
      scheduleReadiness(TrainingFocusArea.arms, now, now, recovery,
          bestMuscle: true),
      greaterThanOrEqualTo(60),
    );
    // Gdy zmęczone jest WSZYSTKO, dodatek nadal odpada.
    final allTired = {
      for (final muscle in TrainingFocusArea.arms.signatureMuscles)
        muscle: MuscleRecoveryState(
          muscleGroup: muscle,
          recoveryPercent: 25,
          status: RecoveryStatus.freshFatigue,
        ),
    };
    expect(
      scheduleReadiness(TrainingFocusArea.arms, now, now, allTired,
          bestMuscle: true),
      lessThan(60),
    );
  });

  group('Rotacja push / pull / legs nie blokuje się sama', () {
    test('sygnatury bloków PPL nie zachodzą na siebie', () {
      final push = TrainingFocusArea.push.signatureMuscles.toSet();
      final pull = TrainingFocusArea.pull.signatureMuscles.toSet();
      final legs = TrainingFocusArea.legs.signatureMuscles.toSet();
      expect(push.intersection(pull), isEmpty);
      expect(push.intersection(legs), isEmpty);
      expect(pull.intersection(legs), isEmpty);
    });

    test('zmęczony triceps po push nie przesuwa dnia pull ani push', () {
      final now = DateTime(2026, 8, 3);
      final recovery = {
        // Po dniu pchania: triceps i przedni bark na dnie, klatka średnio.
        BodyMuscle.triceps: const MuscleRecoveryState(
          muscleGroup: BodyMuscle.triceps,
          recoveryPercent: 20,
          status: RecoveryStatus.freshFatigue,
        ),
        BodyMuscle.frontShoulders: const MuscleRecoveryState(
          muscleGroup: BodyMuscle.frontShoulders,
          recoveryPercent: 25,
          status: RecoveryStatus.freshFatigue,
        ),
        BodyMuscle.lats: const MuscleRecoveryState(
          muscleGroup: BodyMuscle.lats,
          recoveryPercent: 95,
          status: RecoveryStatus.recovered,
        ),
      };
      // Dzień ciągnięcia jest gotowy mimo zmasakrowanego tricepsa.
      expect(
        scheduleReadiness(TrainingFocusArea.pull, now, now, recovery),
        greaterThanOrEqualTo(60),
      );
      // Dzień klatki NIE jest blokowany przez sam pomocniczy triceps.
      expect(
        scheduleReadiness(TrainingFocusArea.chestTriceps, now, now, recovery),
        greaterThanOrEqualTo(60),
      );
    });

    test('gotowość liczy partie definiujące, nie pomocnicze', () {
      final now = DateTime(2026, 8, 3);
      final recovery = {
        BodyMuscle.chest: const MuscleRecoveryState(
          muscleGroup: BodyMuscle.chest,
          recoveryPercent: 30,
          status: RecoveryStatus.heavyFatigue,
        ),
      };
      // Zmęczona partia DEFINIUJĄCA nadal blokuje — o to chodzi.
      expect(
        scheduleReadiness(TrainingFocusArea.chestTriceps, now, now, recovery),
        lessThan(60),
      );
      // …ale można ją pominąć, gdy blok główny dnia i tak ją dziś trenuje.
      expect(
        scheduleReadiness(TrainingFocusArea.chestTriceps, now, now, recovery,
            ignoreMuscles: const [BodyMuscle.chest]),
        100,
      );
    });
  });

  test('dodatek dnia przeżywa zmęczenie partii wspólnych z blokiem głównym',
      () {
    final date = DateTime(2026, 8, 3);
    final schedule = [
      ScheduledDay(
        date: date,
        area: TrainingFocusArea.chestTriceps,
        secondaryArea: TrainingFocusArea.shoulders,
      ),
    ];
    // Przedni bark (wspólny z klatką) leży, tył barku i kaptury są świeże.
    double readiness(TrainingFocusArea area, DateTime d) =>
        area == TrainingFocusArea.shoulders ? 30 : 90;
    double readinessIgnoring(
      TrainingFocusArea area,
      DateTime d,
      Iterable<BodyMuscle> ignore,
    ) =>
        area == TrainingFocusArea.shoulders &&
                ignore.contains(BodyMuscle.frontShoulders)
            ? 88
            : readiness(area, d);

    // Dodatek dnia ZOSTAJE w obu wariantach (spec 12 — regeneracja ostrzega,
    // nie kasuje zestawu). Różnica jest w OSTRZEŻENIU: bez wyłączenia partii
    // wspólnych barki wyglądają na wykończone i dostają czerwony trójkąt…
    final naive = resolveScheduleWithRecovery(schedule, readiness);
    expect(naive.single.secondaryArea, TrainingFocusArea.shoulders);
    expect(naive.single.hasSecondaryWarning, isTrue);

    // …a po wyłączeniu partii, które i tak obciąża dziś blok główny, dodatek
    // idzie bez żadnej uwagi.
    final fixed = resolveScheduleWithRecovery(schedule, readiness,
        readinessIgnoring: readinessIgnoring);
    expect(fixed.single.secondaryArea, TrainingFocusArea.shoulders);
    expect(fixed.single.hasSecondaryWarning, isFalse);
  });
}
