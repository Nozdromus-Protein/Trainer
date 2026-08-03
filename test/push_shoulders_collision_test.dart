import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/body_muscle.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_enums.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/features/trainer/domain/workout_volume_limits.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KOLIZJA PUSH ↔ BARKI / RAMIONA W PLANIE DNIA.
///
/// Zgłoszenie z użycia: Planer przełożył Push na jutro (klatka jeszcze się
/// regenerowała) i dał dziś Pull. Po wykonaniu zestawu BARKÓW aplikacja:
///  1. pokazała dziś Push zamiast Pull — przestawienie się cofnęło,
///  2. oznaczyła Push jako WYKONANY, więc zniknął pierwszorzędny zestaw dnia.
///
/// Oba objawy miały jeden korzeń: przedni bark DEFINIOWAŁ blok Push, a pierwszy
/// zapisany dziś trening blokował dzień przed przestawianiem (i przez to
/// przywracał pierwotną rotację).
Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  return store;
}

Future<void> _log(
  AppStore store,
  String exerciseId, {
  required int hoursAgo,
  int sets = 5,
}) async {
  final at = DateTime.now().subtract(Duration(hours: hoursAgo));
  await store.addLog(WorkoutLog(
    id: 'log_${exerciseId}_$hoursAgo',
    exerciseId: exerciseId,
    date: DateTime(at.year, at.month, at.day),
    sets: sets,
    reps: 10,
    weightKg: 60,
    durationSec: 1800,
    rpe: 9,
    calories: 250,
    note: '',
    aiConfidence: 0,
    sessionId: 'sess_${exerciseId}_$hoursAgo',
    sessionName: 'Trening',
    performedAt: at,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Barki boczne to BARKI, nie skośne brzucha', () {
    test('opis „barki boczne" mapuje się na przedni akton naramiennego', () {
      expect(BodyMuscle.fromText('barki boczne'), BodyMuscle.frontShoulders);
      expect(BodyMuscle.fromText('barki'), BodyMuscle.frontShoulders);
      expect(BodyMuscle.fromText('bark tył'), BodyMuscle.rearShoulders);
      // Skośne brzucha nadal działają — poprawka nie może ich przejąć.
      expect(BodyMuscle.fromText('skośne brzucha'), BodyMuscle.obliques);
      expect(
          BodyMuscle.fromText('boczne mięśnie brzucha'), BodyMuscle.obliques);
    });

    test('unoszenie bokiem liczy się do barków w limitach objętości', () {
      expect(primaryMuscleGroupOf(ExerciseRepo.byId('lateral_raise')),
          MuscleGroup.shoulders);
    });
  });

  group('Push i barki nie wykluczają się nawzajem', () {
    test('blok Push definiuje wyłącznie klatka', () {
      expect(TrainingFocusArea.push.signatureMuscles, [BodyMuscle.chest]);
      // Przedni bark nadal PRACUJE w pchaniu (regeneracja to widzi)…
      expect(TrainingFocusArea.push.muscles,
          contains(BodyMuscle.frontShoulders));
      // …ale należy do sygnatury barków, nie pchania.
      expect(TrainingFocusArea.shoulders.signatureMuscles,
          contains(BodyMuscle.frontShoulders));
    });

    test('zrobienie barków NIE zamyka pierwszorzędnego bloku Push', () async {
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(
          weekday,
          const TrainingDayPlan(
              primary: TrainingFocusArea.push,
              secondary: TrainingFocusArea.shoulders));

      await _log(store, 'shoulder_press', hoursAgo: 1);

      final blocks = store.todayTrainingBlocks();
      expect(blocks, isNotEmpty);
      final push = blocks.firstWhere((b) => b.area == TrainingFocusArea.push);
      final shoulders =
          blocks.firstWhere((b) => b.area == TrainingFocusArea.shoulders);
      expect(shoulders.isDone, isTrue, reason: 'barki faktycznie zrobione');
      expect(push.isDone, isFalse,
          reason: 'wyciskanie nad głowę nie jest dniem klatki');
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.push,
          reason: 'pierwszorzędny zestaw musi zostać do zrobienia');
      expect(store.isTodayTrainingClosed(), isFalse);
    });

    test('zrobienie klatki NIE zamyka dodatku „Barki" tego samego dnia',
        () async {
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(
          weekday,
          const TrainingDayPlan(
              primary: TrainingFocusArea.push,
              secondary: TrainingFocusArea.shoulders));

      await _log(store, 'bench_press', hoursAgo: 1);

      final blocks = store.todayTrainingBlocks();
      final push = blocks.firstWhere((b) => b.area == TrainingFocusArea.push);
      final shoulders =
          blocks.firstWhere((b) => b.area == TrainingFocusArea.shoulders);
      expect(push.isDone, isTrue);
      expect(shoulders.isDone, isFalse,
          reason: 'klatka nie może odhaczyć barków — to osobny zestaw dnia');
      expect(store.nextTrainingBlockToday()?.area, TrainingFocusArea.shoulders);
    });
  });

  group('Przestawienie dnia nie cofa się po zapisaniu treningu', () {
    /// Rozkład: dziś Push + barki, jutro Pull. Klatka wczoraj mocno zmęczona,
    /// więc Planer ma przełożyć Push i dać dziś Pull.
    Future<AppStore> withMovedDay() async {
      final store = await _store();
      final today = DateTime.now().weekday;
      final tomorrow = today == 7 ? 1 : today + 1;
      await store.setWeekdayPlan(
          today,
          const TrainingDayPlan(
              primary: TrainingFocusArea.push,
              secondary: TrainingFocusArea.shoulders));
      await store.setWeekdayPlan(
          tomorrow,
          const TrainingDayPlan(
              primary: TrainingFocusArea.pull,
              secondary: TrainingFocusArea.arms));
      // Ciężka klatka kilka godzin temu (wczorajszy wieczór).
      await _log(store, 'bench_press', hoursAgo: 14, sets: 8);
      return store;
    }

    test('dzień zostaje przestawiony także PO wykonaniu zestawu barków',
        () async {
      final store = await withMovedDay();
      final before = store.todayScheduled;
      expect(before, isNotNull);

      // Trening barków — dokładnie to, co zrobił użytkownik.
      await _log(store, 'shoulder_press', hoursAgo: 0);

      final after = store.todayScheduled;
      expect(after, isNotNull);
      expect(after!.area, before!.area,
          reason: 'zapisany zestaw nie może zmienić partii dnia');
      expect(after.moved, before.moved,
          reason: 'przestawienie dnia nie może się cofnąć po treningu');
      expect(after.secondaryArea, before.secondaryArea);
    });

    test('kalendarz i „Dzisiejszy trening" zgadzają się także po treningu',
        () async {
      final store = await withMovedDay();
      await _log(store, 'shoulder_press', hoursAgo: 0);

      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final fromCalendar =
          store.trainingScheduleFor(from: monday, days: 7)[now.weekday - 1];
      final fromToday = store.todayScheduled;

      expect(fromToday!.area, fromCalendar.area);
      expect(fromToday.moved, fromCalendar.moved);
      expect(fromToday.labelWithLoad, fromCalendar.labelWithLoad);
    });

    test('wykonanie WŁASNEGO zestawu dnia nie przeplanowuje tego dnia',
        () async {
      // Zabezpieczenie, które wcześniej dawała blokada dnia: świeżo zmęczona
      // partia nie może wyrzucić własnego dnia z rozkładu.
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(
          weekday,
          const TrainingDayPlan(
              primary: TrainingFocusArea.push,
              secondary: TrainingFocusArea.core));

      expect(store.todayScheduled?.area, TrainingFocusArea.push);
      await _log(store, 'bench_press', hoursAgo: 0, sets: 8);
      expect(store.todayScheduled?.area, TrainingFocusArea.push,
          reason: 'zrobiony dzień klatki zostaje dniem klatki');
      expect(store.todayScheduled?.moved, isFalse);
    });
  });
}
