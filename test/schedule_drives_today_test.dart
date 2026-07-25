import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise_intensity.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rozkład, w którym DZIŚ jest dniem nóg, a jutro dniem klatki — punkt
/// odniesienia dla „co pokazuje aplikacja na dzisiaj".
Future<AppStore> _storeWithLegDayToday() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  final today = DateTime.now().weekday;
  await store.setWeekdayPlan(
    today,
    const TrainingDayPlan(
      primary: TrainingFocusArea.legs,
      secondary: TrainingFocusArea.forearms,
    ),
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('To ROZKŁAD wyznacza dzisiejszy trening, nie ostatnio otwarty zestaw',
      () {
    test('dziś jest dzień z rotacji, także po obejrzeniu innego programu',
        () async {
      final store = await _storeWithLegDayToday();

      // Użytkownik przegląda program barków — trafia on na listę planów
      // i staje się aktywny (to właśnie podmieniało zaplanowany dzień).
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_shoulders',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));
      expect(store.activeWorkoutPlan?.id, startsWith('program_shoulders'),
          reason: 'test ma sens tylko, gdy barki faktycznie są aktywne');

      // Dzień nadal jest dniem nóg.
      expect(store.todayScheduled?.area, TrainingFocusArea.legs);
      expect(store.todayScheduled?.secondaryArea, TrainingFocusArea.forearms);
      expect(store.planForToday, isNull,
          reason: 'program barków nie może przejąć dnia nóg');
      expect(store.weeklyTrainingAdvice().todayHeadline,
          contains(TrainingFocusArea.legs.label));
    });

    test('program zgodny z rozkładem zostaje planem dnia', () async {
      final store = await _storeWithLegDayToday();
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ));
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_shoulders',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));

      expect(store.planForToday?.id, startsWith('program_legs'));
    });

    test('kalendarz na kolejne tygodnie idzie rotacją, nie jednym zestawem',
        () async {
      final store = await _storeWithLegDayToday();
      final schedule = store.trainingScheduleFor(days: 21);

      expect(schedule, hasLength(21));
      // Ten sam dzień tygodnia ma ten sam plan także za trzy tygodnie.
      expect(schedule[0].area, schedule[7].area);
      expect(schedule[7].area, schedule[14].area);
      // A w tygodniu wypada więcej niż jedna partia.
      final areas = {
        for (final day in schedule.take(7))
          if (day.area != null) day.area!,
      };
      expect(areas.length, greaterThan(1),
          reason: 'tydzień nie może być jedną partią w kółko');
    });

    test('bez żadnego pasującego planu zestaw i tak nazywa się jak dzień '
        'rozkładu', () async {
      final store = await _storeWithLegDayToday();
      for (final plan in [...store.plans]) {
        await store.deleteWorkoutPlan(plan.id);
      }

      final planned = store.plannedWorkoutForToday();
      expect(planned.title, contains(TrainingFocusArea.legs.label));
      expect(planned.exercises, isNotEmpty,
          reason: 'Planer ma złożyć zestaw pod zaplanowaną partię');
    });

    test('tor drugorzędny z własnym programem jest OSOBNYM blokiem dnia',
        () async {
      final store = await _storeWithLegDayToday();
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_forearms',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ));

      final blocks = store.todayTrainingBlocks();
      expect(blocks, hasLength(2),
          reason: 'dzień dwutorowy to dwa zestawy do wykonania');
      expect(blocks.first.area, TrainingFocusArea.legs);
      expect(blocks.first.isPrimary, isTrue);
      expect(blocks.first.exerciseCount, greaterThan(0),
          reason: 'blok ma pokazywać PEŁNĄ zawartość zestawu');
      expect(blocks.last.area, TrainingFocusArea.forearms);
      expect(blocks.last.isPrimary, isFalse);
      expect(blocks.last.exerciseCount, greaterThan(0));

      // Dopóki nic nie zrobiono, na kolei jest tor pierwszorzędny.
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.legs);
      expect(store.isTodayTrainingClosed(), isFalse);
      expect(store.plannedWorkoutForToday().programId,
          startsWith('program_legs'));
    });

    test('po ukończeniu toru głównego na kolei jest tor drugorzędny', () async {
      final store = await _storeWithLegDayToday();
      final legs = buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true);
      await store.addWorkoutPlan(legs);
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_forearms',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ));

      // Zapis treningu z programu nóg — tak jak robi to zakończenie sesji.
      final now = DateTime.now();
      await store.addLog(WorkoutLog(
        id: 'log_legs',
        exerciseId: legs.days.first.items.first.exerciseId,
        date: DateTime(now.year, now.month, now.day),
        sets: 3,
        reps: 8,
        weightKg: 40,
        durationSec: 900,
        rpe: 7,
        calories: 120,
        note: '',
        aiConfidence: 0,
        sessionId: 'sess_legs',
        sessionName: legs.name,
        performedAt: now,
        planId: legs.id,
        dayIndex: 0,
      ));

      final blocks = store.todayTrainingBlocks();
      expect(blocks.first.isDone, isTrue,
          reason: 'zestaw nóg został dziś wykonany');
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.forearms,
          reason: 'po torze głównym idzie drugorzędny, nie ten sam zestaw');
      expect(store.isTodayTrainingClosed(), isFalse);
      expect(store.plannedWorkoutForToday().programId,
          startsWith('program_forearms'));
    });

    test('dzień wolny nie proponuje treningu', () async {
      final store = await _storeWithLegDayToday();
      await store.setWeekdayPlan(DateTime.now().weekday, TrainingDayPlan.rest);

      expect(store.todayScheduled?.isRest, isTrue);
      expect(store.planForToday, isNull);
      expect(store.weeklyTrainingAdvice().todayHeadline,
          contains('dzień wolny'));
    });
  });

  group('Zestawy są ciężkie z założenia', () {
    test('dzień klatki zaczyna się od ciężkiego boju i ma pracę z obciążeniem',
        () {
      bool usesLoad(String id) {
        final equipment = ExerciseRepo.byId(id).equipment.toLowerCase();
        return equipment.contains('sztang') ||
            equipment.contains('hant') ||
            equipment.contains('obciąż');
      }

      final plan = buildWorkoutProgram('program_chest',
          resolveExercise: (id) => ExerciseRepo.byId(id));
      for (final day in plan.days) {
        final first = ExerciseRepo.byId(day.items.first.exerciseId);
        expect(exerciseIntensityTier(first).rank,
            greaterThanOrEqualTo(ExerciseIntensityTier.heavy.rank),
            reason: '„${day.title}": dzień zaczyna się od lekkiej pracy '
                '(${first.name})');
        expect(day.items.where((item) => usesLoad(item.exerciseId)).length,
            greaterThanOrEqualTo(2),
            reason: '„${day.title}": za mało pracy z obciążeniem zewnętrznym');
      }
    });

    test('żaden dzień siłowy nie składa się z samej pracy lekkiej', () {
      for (final meta in kWorkoutProgramCatalog) {
        if (meta.id == 'program_core') continue; // brzuch jest czasowy
        final plan = buildWorkoutProgram(meta.id,
            resolveExercise: (id) => ExerciseRepo.byId(id));
        for (final day in plan.days) {
          final heavy = day.items.where((item) =>
              exerciseIntensityTier(ExerciseRepo.byId(item.exerciseId)).rank >=
              ExerciseIntensityTier.moderate.rank);
          expect(heavy, isNotEmpty,
              reason: '${meta.id} „${day.title}": dzień bez pracy ciężkiej');
        }
      }
    });

    test('początkujący też dostaje ćwiczenia z obciążeniem', () {
      final plan = buildWorkoutProgram('program_chest',
          level: 'Początkujący', resolveExercise: (id) => ExerciseRepo.byId(id));
      final loaded = plan.days.first.items.where((item) {
        final equipment = ExerciseRepo.byId(item.exerciseId).equipment.toLowerCase();
        return equipment.contains('sztang') || equipment.contains('hant');
      });
      expect(loaded, isNotEmpty);
    });
  });
}
