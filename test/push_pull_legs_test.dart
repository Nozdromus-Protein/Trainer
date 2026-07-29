import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

// Strategia Push / Pull / Legs: dzień to CAŁY wzorzec ruchu (blok główny +
// dodatek), a o kolejności bloków w tygodniu decyduje regeneracja.
// Hierarchia obciążenia jest sztywna: Deload ▸ Regeneracja ▸ Zestaw ćwiczeń.

DateTime _d(int day) => DateTime(2026, 8, day);

void main() {
  group('Rozkład Push / Pull / Legs', () {
    test('domyślny tydzień rotuje trzy bloki, każdy 2× przy 6 dniach', () {
      final plan = defaultWeekPlan(const [1, 2, 3, 4, 5, 6],
          strategy: TrainingSplitStrategy.pushPullLegs);
      final primaries = [
        for (var weekday = 1; weekday <= 6; weekday++) plan[weekday]!.primary,
      ];
      expect(primaries.where((a) => a == TrainingFocusArea.push).length, 2);
      expect(primaries.where((a) => a == TrainingFocusArea.pull).length, 2);
      expect(primaries.where((a) => a == TrainingFocusArea.legs).length, 2);
      expect(plan[7]!.isRest, isTrue);
    });

    test('dzień ma blok główny I dodatek (dwa zestawy w jednym dniu)', () {
      final plan = defaultWeekPlan(const [1, 2, 3],
          strategy: TrainingSplitStrategy.pushPullLegs);
      for (var weekday = 1; weekday <= 3; weekday++) {
        expect(plan[weekday]!.primary, isNotNull);
        expect(plan[weekday]!.secondary, isNotNull);
        expect(plan[weekday]!.primary, isNot(plan[weekday]!.secondary));
      }
    });

    test('blok Push obejmuje klatkę, przedni bark i triceps', () {
      expect(TrainingFocusArea.push.muscles, contains(BodyMuscle.chest));
      expect(
          TrainingFocusArea.push.muscles, contains(BodyMuscle.frontShoulders));
      expect(TrainingFocusArea.push.muscles, contains(BodyMuscle.triceps));
    });

    test('blok Pull obejmuje plecy, tylny bark, biceps i przedramiona', () {
      expect(TrainingFocusArea.pull.muscles, contains(BodyMuscle.lats));
      expect(TrainingFocusArea.pull.muscles, contains(BodyMuscle.rearShoulders));
      expect(TrainingFocusArea.pull.muscles, contains(BodyMuscle.biceps));
      expect(
          TrainingFocusArea.pull.muscles, contains(BodyMuscle.forearmsFront));
    });

    test('brzuch jest dozwolonym dodatkiem TYLKO w PPL', () {
      expect(secondaryAreasFor(TrainingSplitStrategy.pushPullLegs),
          contains(TrainingFocusArea.core));
      expect(secondaryAreasFor(TrainingSplitStrategy.twoTrack),
          isNot(contains(TrainingFocusArea.core)));
    });

    test('normalizacja nie kasuje bloku push/pull ani dodatku „brzuch"', () {
      const plan = TrainingDayPlan(
          primary: TrainingFocusArea.push, secondary: TrainingFocusArea.core);
      final normalized = normalizeTrainingDayPlan(plan,
          weekday: 1, strategy: TrainingSplitStrategy.pushPullLegs);
      expect(normalized.primary, TrainingFocusArea.push);
      expect(normalized.secondary, TrainingFocusArea.core);
    });

    test('strategia przeżywa zapis i odczyt konfiguracji', () {
      const config =
          TrainingScheduleConfig(strategy: TrainingSplitStrategy.twoTrack);
      final restored = TrainingScheduleConfig.fromJson(config.toJson());
      expect(restored.strategy, TrainingSplitStrategy.twoTrack,
          reason: 'świadomy wybór dwutorowego musi przetrwać zapis');
      // Push / Pull / Legs jest strategią DOMYŚLNĄ — także dla zapisów
      // sprzed wprowadzenia tego pola.
      expect(TrainingScheduleConfig.fromJson(const {}).strategy,
          TrainingSplitStrategy.pushPullLegs);
      expect(const TrainingScheduleConfig().strategy,
          TrainingSplitStrategy.pushPullLegs);
    });

    test('plan dwutorowy przechodzi na bloki ruchu, a nie na dzień wolny', () {
      // Zapisany tydzień „klatka / plecy / nogi" po przejściu na PPL ma być
      // czytany jako push / pull / legs — nikt nie traci ułożonego tygodnia.
      const saved = TrainingScheduleConfig(
        strategy: TrainingSplitStrategy.pushPullLegs,
        trainingWeekdays: [1, 2, 3],
        weekdayPlans: {
          1: TrainingDayPlan(
              primary: TrainingFocusArea.chestTriceps,
              secondary: TrainingFocusArea.shoulders),
          2: TrainingDayPlan(
              primary: TrainingFocusArea.backBiceps,
              secondary: TrainingFocusArea.arms),
          3: TrainingDayPlan(
              primary: TrainingFocusArea.legs,
              secondary: TrainingFocusArea.core),
        },
      );
      expect(saved.planForWeekday(1).primary, TrainingFocusArea.push);
      expect(saved.planForWeekday(2).primary, TrainingFocusArea.pull);
      expect(saved.planForWeekday(3).primary, TrainingFocusArea.legs);
      // Dodatki dnia zostają nietknięte.
      expect(saved.planForWeekday(2).secondary, TrainingFocusArea.arms);
      expect(saved.planForWeekday(3).secondary, TrainingFocusArea.core);
    });

    test('rozkład buduje się z bloków PPL', () {
      const config = TrainingScheduleConfig(
        strategy: TrainingSplitStrategy.pushPullLegs,
        trainingWeekdays: [1, 2, 3, 4, 5, 6],
      );
      final schedule = buildSchedule(config, _d(3), 6); // 3.08.2026 = pon.
      expect(schedule, hasLength(6));
      expect(schedule.first.area, TrainingFocusArea.push);
      expect(schedule[1].area, TrainingFocusArea.pull);
      expect(schedule[2].area, TrainingFocusArea.legs);
    });
  });

  group('Regeneracja decyduje o rotacji bloków', () {
    test('niezregenerowany blok zamienia się miejscami z gotowym', () {
      const config = TrainingScheduleConfig(
        strategy: TrainingSplitStrategy.pushPullLegs,
        trainingWeekdays: [1, 2, 3, 4, 5, 6],
      );
      final schedule = buildSchedule(config, _d(3), 3);
      // Push jeszcze odpoczywa (40%), reszta gotowa.
      double readiness(TrainingFocusArea area, DateTime date) {
        if (area != TrainingFocusArea.push) return 90;
        // Push dochodzi do siebie dopiero na trzeci dzień.
        return date.day >= 5 ? 85 : 40;
      }

      final resolved = resolveScheduleWithRecovery(schedule, readiness);
      expect(resolved.first.area, isNot(TrainingFocusArea.push),
          reason: 'blok w regeneracji nie może zostać na dzisiaj');
      expect(resolved.any((d) => d.area == TrainingFocusArea.push), isTrue,
          reason: 'blok nie może wypaść z tygodnia — ma być przesunięty');
      expect(resolved.first.moved, isTrue);
      expect(resolved.first.note, isNotEmpty);
    });

    test('gdy nie ma z czym zamienić — zestaw idzie w LŻEJSZEJ wersji', () {
      final schedule = [
        ScheduledDay(date: _d(3), area: TrainingFocusArea.push),
      ];
      final resolved = applyLoadHierarchy(
        schedule,
        (area, date) => 45, // wszystko poniżej progu
      );
      final day = resolved.single;
      expect(day.loadTier, DayLoadTier.recovery);
      expect(day.intensityScale, lessThan(1.0));
      expect(day.intensityScale, greaterThanOrEqualTo(0.65));
      expect(day.labelWithLoad, contains('lżejszy'));
      expect(day.labelWithLoad, contains('45%'));
    });

    test('DELOAD ma pierwszeństwo przed regeneracją', () {
      final schedule = [
        ScheduledDay(date: _d(3), area: TrainingFocusArea.push, isDeload: true),
      ];
      final resolved = applyLoadHierarchy(
        schedule,
        (area, date) => 30,
        deloadScale: 0.55,
      );
      final day = resolved.single;
      expect(day.loadTier, DayLoadTier.deload);
      expect(day.intensityScale, 0.55);
      expect(day.labelWithLoad, contains('deload'));
      expect(day.labelWithLoad, isNot(contains('regeneracja')));
    });

    test('pełna gotowość = pełny zestaw, bez dopisku w nazwie', () {
      final schedule = [
        ScheduledDay(date: _d(3), area: TrainingFocusArea.legs),
      ];
      final day = applyLoadHierarchy(schedule, (area, date) => 95).single;
      expect(day.loadTier, DayLoadTier.full);
      expect(day.intensityScale, 1.0);
      expect(day.labelWithLoad, day.label);
      expect(day.isLightened, isFalse);
    });

    test('im niższa gotowość, tym mocniejsze odciążenie zestawu', () {
      ScheduledDay lighten(double percent) => applyLoadHierarchy(
            [ScheduledDay(date: _d(3), area: TrainingFocusArea.pull)],
            (area, date) => percent,
          ).single;
      expect(lighten(30).intensityScale, lessThan(lighten(55).intensityScale));
    });

    test('poziom obciążenia trafia do planera razem z nazwą dnia', () {
      final day = applyLoadHierarchy(
        [ScheduledDay(date: _d(3), area: TrainingFocusArea.push)],
        (area, date) => 40,
      ).single;
      final focus = day.toFocusDay();
      expect(focus.loadSuffix, contains('lżejszy'));
      expect(focus.intensityScale, day.intensityScale);
      expect(focus.label, contains('Push'));
      expect(focus.label, contains('lżejszy'));
    });
  });
}
