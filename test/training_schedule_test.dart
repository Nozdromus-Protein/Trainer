import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';

void main() {
  // 2026-01-05 to poniedziałek.
  final monday = DateTime(2026, 1, 5);
  // Ten plik opisuje ROZKŁAD DWUTOROWY (partia główna + dodatek). Domyślną
  // strategią aplikacji jest Push / Pull / Legs, więc podajemy ją tu wprost.
  const twoTrack = TrainingSplitStrategy.twoTrack;
  const config = TrainingScheduleConfig(
    enabled: true,
    trainingWeekdays: [1, 2, 3, 4, 5, 6],
    strategy: twoTrack,
  );

  TrainingFocusArea? areaOn(DateTime date) =>
      buildSchedule(config, date, 1).single.area;

  group('Rozkład jest deterministyczny', () {
    test('ten sam wynik przy każdym wywołaniu', () {
      final a = buildSchedule(config, monday, 21);
      final b = buildSchedule(config, monday, 21);
      expect(a.map((d) => d.area).toList(), b.map((d) => d.area).toList());
      expect(a.map((d) => d.secondaryArea).toList(),
          b.map((d) => d.secondaryArea).toList());
    });

    test('każdy dzień tygodnia ma STAŁY obszar, powtarzany co tydzień', () {
      // To była istota problemu: tydzień się przestawiał.
      for (var week = 0; week < 4; week++) {
        final offset = Duration(days: week * 7);
        expect(areaOn(monday.add(offset)), TrainingFocusArea.chestTriceps);
        expect(areaOn(monday.add(offset + const Duration(days: 1))),
            TrainingFocusArea.backBiceps);
        expect(areaOn(monday.add(offset + const Duration(days: 2))),
            TrainingFocusArea.legs);
        expect(areaOn(monday.add(offset + const Duration(days: 3))),
            TrainingFocusArea.core);
      }
    });

    test('da się policzyć dowolną datę w przyszłości', () {
      expect(areaOn(monday.add(const Duration(days: 21))),
          TrainingFocusArea.chestTriceps);
      expect(areaOn(monday.add(const Duration(days: 182))), isNotNull);
    });

    test('niedziela poza dniami treningowymi jest wolna', () {
      final sunday =
          buildSchedule(config, monday.add(const Duration(days: 6)), 1).single;
      expect(sunday.isRest, isTrue);
      expect(sunday.area, isNull);
      expect(sunday.secondaryArea, isNull);
    });

    test('niedzielę da się dołożyć do rozkładu', () {
      final withSunday = TrainingScheduleConfig(
        enabled: true,
        weekdayPlans: {
          ...defaultWeekPlan(const [1, 2, 3, 4, 5, 6], strategy: twoTrack),
          7: const TrainingDayPlan(
              primary: TrainingFocusArea.legs,
              secondary: TrainingFocusArea.cardio),
        },
      );
      final sunday =
          buildSchedule(withSunday, monday.add(const Duration(days: 6)), 1)
              .single;
      expect(sunday.isRest, isFalse);
      expect(sunday.area, TrainingFocusArea.legs);
      expect(sunday.secondaryArea, TrainingFocusArea.cardio);
    });

    test('daty przed startem też się liczą (bez wyjątków)', () {
      final before =
          buildSchedule(config, monday.subtract(const Duration(days: 7)), 7);
      expect(before, hasLength(7));
      expect(before.where((d) => !d.isRest), isNotEmpty);
    });
  });

  group('Dwa tory: partia główna + dodatek dnia', () {
    test('domyślny rozkład daje każdemu dniu obie kolumny', () {
      final week = buildSchedule(config, monday, 6);
      expect(week.every((d) => d.area != null), isTrue);
      expect(week.every((d) => d.secondaryArea != null), isTrue);
    });

    test('tor pierwszorzędny bierze tylko duże partie', () {
      for (final day in buildSchedule(config, monday, 14)) {
        if (day.isRest) continue;
        expect(kPrimaryFocusAreas, contains(day.area));
      }
    });

    test('tor drugorzędny bierze tylko partie dodatkowe', () {
      for (final day in buildSchedule(config, monday, 14)) {
        final extra = day.secondaryArea;
        if (extra == null) continue;
        expect(kSecondaryFocusAreas, contains(extra));
      }
    });

    test('etykieta dnia łączy oba tory', () {
      final day = buildSchedule(config, monday, 1).single;
      expect(day.label, contains(TrainingFocusArea.chestTriceps.label));
      expect(day.label, contains('+'));
    });

    test('dzień wolny zeruje obie kolumny', () {
      final withFreeMonday = config.copyWith(
          weekdayPlans: weekPlanWithDay(config, 1, TrainingDayPlan.rest));
      final day = buildSchedule(withFreeMonday, monday, 1).single;
      expect(day.isRest, isTrue);
      expect(withFreeMonday.activeWeekdays, isNot(contains(1)));
    });
  });

  group('Przestawianie pod regenerację', () {
    test('niezregenerowana partia ustępuje miejsca gotowej', () {
      final base = buildSchedule(config, monday, 7);
      final legsDay = monday.add(const Duration(days: 2)); // środa = nogi

      double readiness(TrainingFocusArea area, DateTime date) {
        if (area == TrainingFocusArea.legs && date == legsDay) return 30;
        return 100;
      }

      final resolved = resolveScheduleWithRecovery(base, readiness);
      final wednesday = resolved.firstWhere((d) => d.date == legsDay);

      expect(wednesday.area, isNot(TrainingFocusArea.legs),
          reason: 'nogi nie powinny wypaść w dniu, w którym się regenerują');
      expect(wednesday.moved, isTrue);
      expect(wednesday.note.toLowerCase(), contains('regeneruje'));

      // Częstotliwość zachowana — nogi nadal są w tygodniu, tylko później.
      final legsLater = resolved.where((d) => d.area == TrainingFocusArea.legs);
      expect(legsLater, hasLength(1));
      expect(legsLater.single.date.isAfter(legsDay), isTrue);
    });

    test('zmęczony dodatek dnia odpada, ale nie przestawia rozkładu', () {
      final base = buildSchedule(config, monday, 7);
      final extra = base.first.secondaryArea!;

      final resolved = resolveScheduleWithRecovery(
        base,
        (area, date) => area == extra ? 20 : 100,
      );

      expect(resolved.first.area, base.first.area,
          reason: 'partia główna zostaje na swoim dniu');
      expect(resolved.first.secondaryArea, isNull);
      expect(resolved.first.note.toLowerCase(), contains('pomijamy'));
    });

    test('gdy wszystko jest gotowe, rozkład zostaje nietknięty', () {
      final base = buildSchedule(config, monday, 7);
      final resolved = resolveScheduleWithRecovery(base, (area, date) => 100);
      expect(resolved.map((d) => d.area).toList(),
          base.map((d) => d.area).toList());
      expect(resolved.map((d) => d.secondaryArea).toList(),
          base.map((d) => d.secondaryArea).toList());
      expect(resolved.every((d) => !d.moved), isTrue);
    });
  });

  group('Domyślny plan tygodnia', () {
    test('każda duża partia wypada co najmniej raz', () {
      final plan = defaultWeekPlan(const [1, 2, 3, 4, 5, 6], strategy: twoTrack);
      final primaries = plan.values.map((p) => p.primary).toSet();
      for (final area in kPrimaryFocusAreas) {
        expect(primaries, contains(area));
      }
    });

    test('przy 7 dniach trzy duże partie wypadają dwa razy', () {
      const week = TrainingScheduleConfig(
        enabled: true,
        trainingWeekdays: [1, 2, 3, 4, 5, 6, 7],
        strategy: twoTrack,
      );
      final twice = [
        for (final area in kPrimaryFocusAreas)
          if (week.occurrencesOf(area) >= 2) area,
      ];
      expect(twice, hasLength(3));
    });

    test('skrajne wartości nie wysypują funkcji', () {
      expect(defaultWeekPlan(const [], strategy: twoTrack).values.every((p) => p.isRest), isTrue);
      expect(defaultWeekPlan(const [1, 2, 3, 4, 5, 6, 7, 9], strategy: twoTrack), hasLength(7));
    });
  });

  group('Edycja planu per dzień tygodnia', () {
    test('mapa dzień → obszar odpowiada rozkładowi', () {
      final map = rotationByWeekday(config);
      expect(map[1], TrainingFocusArea.chestTriceps);
      expect(map[3], TrainingFocusArea.legs);
      expect(map[7], isNull, reason: 'niedziela nie jest dniem treningowym');
    });

    test('mapa dodatków dnia jest osobna', () {
      final map = secondaryByWeekday(config);
      expect(kSecondaryFocusAreas, contains(map[1]));
      expect(map[7], isNull);
    });

    test('przypisanie obszaru do dnia zmienia właśnie ten dzień', () {
      final updated = config.copyWith(
        weekdayPlans: weekPlanWithDay(
            config, 1, const TrainingDayPlan(primary: TrainingFocusArea.legs)),
      );
      final map = rotationByWeekday(updated);
      expect(map[1], TrainingFocusArea.legs, reason: 'poniedziałek zmieniony');
      expect(map[2], TrainingFocusArea.backBiceps,
          reason: 'pozostałe dni bez zmian');
      // Zmiana jest trwała także w kolejnych tygodniach.
      expect(
        buildSchedule(updated, monday.add(const Duration(days: 14)), 1)
            .single
            .area,
        TrainingFocusArea.legs,
      );
    });
  });

  group('Serializacja konfiguracji', () {
    test('round-trip zachowuje plan tygodnia i dni', () {
      final cfg = TrainingScheduleConfig(
        enabled: true,
        strategy: twoTrack,
        anchor: DateTime(2026, 7, 21),
        weekdayPlans: const {
          1: TrainingDayPlan(
              primary: TrainingFocusArea.legs,
              secondary: TrainingFocusArea.forearms),
          3: TrainingDayPlan(primary: TrainingFocusArea.chestTriceps),
        },
        trainingWeekdays: const [1, 3, 5],
      );
      final back = TrainingScheduleConfig.fromJson(cfg.toJson());
      expect(back.anchor, DateTime(2026, 7, 21));
      expect(back.trainingWeekdays, const [1, 3, 5]);
      expect(back.planForWeekday(1).primary, TrainingFocusArea.legs);
      expect(back.planForWeekday(1).secondary, TrainingFocusArea.forearms);
      expect(back.planForWeekday(3).secondary, isNull);
      expect(back.planForWeekday(2).isRest, isTrue);
    });

    test('stary zapis rotacji nie przepada (migracja)', () {
      const legacy = TrainingScheduleConfig(
        enabled: true,
        strategy: twoTrack,
        rotationKeys: ['legs', 'chestTriceps'],
        trainingWeekdays: [1, 3],
      );
      expect(legacy.planForWeekday(1).primary, TrainingFocusArea.legs);
      expect(legacy.planForWeekday(3).primary, TrainingFocusArea.chestTriceps);
      expect(legacy.planForWeekday(2).isRest, isTrue);
      // Migracja dokłada też dodatki dnia, żeby oba tory od razu działały.
      expect(legacy.planForWeekday(1).secondary, isNotNull);
    });

    test('stary obszar z niewłaściwego toru jest przenoszony bez utraty', () {
      const legacy = TrainingScheduleConfig(
        enabled: true,
        strategy: twoTrack,
        rotationKeys: ['shoulders', 'legs'],
        trainingWeekdays: [1, 3],
      );

      final monday = legacy.planForWeekday(1);
      expect(kPrimaryFocusAreas, contains(monday.primary));
      expect(monday.secondary, TrainingFocusArea.shoulders);
      expect(legacy.planForWeekday(3).primary, TrainingFocusArea.legs);
    });

    test('zamienione tory w planie dnia są automatycznie naprawiane', () {
      const config = TrainingScheduleConfig(
        strategy: twoTrack,
        weekdayPlans: {
          1: TrainingDayPlan(
            primary: TrainingFocusArea.shoulders,
            secondary: TrainingFocusArea.legs,
          ),
        },
      );

      final monday = config.planForWeekday(1);
      expect(monday.primary, TrainingFocusArea.legs);
      expect(monday.secondary, TrainingFocusArea.shoulders);
    });
  });
}
