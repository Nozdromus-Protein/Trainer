import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise.dart';
import 'package:licznik_treningu/features/trainer/domain/muscle_recovery.dart';

MuscleRecoveryState _state(BodyMuscle muscle, double percent, {int hoursRemaining = 24}) {
  return MuscleRecoveryState(
    muscleGroup: muscle,
    recoveryPercent: percent,
    fatiguePercent: 100 - percent,
    estimatedHoursRemaining: hoursRemaining,
    status: recoveryStatusForPercent(percent),
  );
}

Exercise _exercise(
  String id,
  String level,
  List<ExerciseMuscleImpact> impacts, {
  double met = 5,
}) {
  return Exercise(
    id: id,
    name: id,
    category: 'Test',
    muscles: const [],
    equipment: 'brak',
    level: level,
    illustrationType: 'generic',
    description: '',
    tips: const [],
    commonMistakes: const [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: met,
    muscleImpacts: impacts,
  );
}

void main() {
  // Poniedziałek — stały punkt odniesienia dla symulacji tygodnia.
  final monday = DateTime(2026, 7, 6, 9);

  // Klatka / plecy / przednie barki zmęczone, brzuch częściowo — nogi (100%)
  // są jedynym w pełni gotowym obszarem siłowym.
  final tiredUpperBody = <BodyMuscle, MuscleRecoveryState>{
    BodyMuscle.chest: _state(BodyMuscle.chest, 50),
    BodyMuscle.lats: _state(BodyMuscle.lats, 50),
    BodyMuscle.frontShoulders: _state(BodyMuscle.frontShoulders, 50),
    BodyMuscle.abs: _state(BodyMuscle.abs, 70),
  };

  test('areaReadiness zwraca posortowany ranking obszarów z cardio', () {
    final advice = buildWeeklyTrainingAdvice(
      recovery: tiredUpperBody,
      recentLogs: const [],
      recentActivities: const [],
      goal: 'Masa',
      level: 'Początkujący',
      trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      now: monday,
    );

    // Obszary siłowe (oba tory) + cardio.
    expect(advice.areaReadiness, hasLength(kStrengthFocusAreas.length + 1));
    // Ranking malejący.
    for (var i = 1; i < advice.areaReadiness.length; i++) {
      expect(
        advice.areaReadiness[i].percent,
        lessThanOrEqualTo(advice.areaReadiness[i - 1].percent),
      );
    }
    expect(advice.areaReadiness.first.percent, 100);
    final chestArea = advice.areaReadiness
        .firstWhere((area) => area.area == TrainingFocusArea.chestTriceps);
    expect(chestArea.percent, 50);
    final legsArea = advice.areaReadiness
        .firstWhere((area) => area.area == TrainingFocusArea.legs);
    expect(legsArea.percent, 100);
  });

  test('todayExercises proponuje ćwiczenia najlepszego obszaru pod poziom użytkownika', () {
    final catalog = [
      _exercise('squat_test', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
      ]),
      // Za trudne dla początkującego — odpada.
      _exercise('front_squat_test', 'Zaawansowany', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
      ]),
      // Inna partia (klatka, w dodatku zmęczona) — odpada.
      _exercise('bench_test', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
      ]),
      _exercise('lunge_test', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.glutes, role: MuscleRole.primary),
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.secondary),
      ]),
      _exercise('quad_iso_1', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
      ]),
      // Trzecie ćwiczenie na czworogłowe — odpada (maks. 2 na partię).
      _exercise('quad_iso_2', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
      ]),
    ];

    final advice = buildWeeklyTrainingAdvice(
      recovery: tiredUpperBody,
      recentLogs: const [],
      recentActivities: const [],
      goal: 'Masa',
      level: 'Początkujący',
      trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      exercises: catalog,
      now: monday,
    );

    // Kolejność: najpierw partia WIODĄCA obszaru (dla nóg — czworogłowe),
    // potem reszta. Dzięki tej regule dzień klatki nie wypełnia się tricepsem
    // ani przodem barków, mimo że należą do tego samego obszaru.
    expect(
      advice.todayExercises.map((suggestion) => suggestion.exerciseId).toList(),
      ['squat_test', 'quad_iso_1', 'lunge_test'],
    );
    // Uzasadnienie zawiera gotowość partii.
    expect(advice.todayExercises.first.reason, contains('gotowość'));
  });

  test('dzień programu na dziś wyłącza własne propozycje ćwiczeń planera', () {
    final catalog = [
      _exercise('squat_test', 'Początkujący', const [
        ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
      ]),
    ];

    final advice = buildWeeklyTrainingAdvice(
      recovery: tiredUpperBody,
      recentLogs: const [],
      recentActivities: const [],
      goal: 'Masa',
      level: 'Początkujący',
      trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      exercises: catalog,
      upcomingProgramDays: const [
        PlannedProgramDay(dayNumber: 5, title: 'Nogi', muscles: []),
      ],
      now: monday,
    );

    expect(advice.todayHeadline, contains('Dzień 5 programu'));
    expect(advice.todayExercises, isEmpty);
  });

  test('tydzień z celem redukcji planuje jeden dzień cardio i liczy podsumowanie', () {
    final advice = buildWeeklyTrainingAdvice(
      recovery: const {},
      recentLogs: const [],
      recentActivities: const [],
      goal: 'Redukcja',
      level: 'Średniozaawansowany',
      trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      now: monday,
    );

    expect(advice.week, hasLength(7));
    expect(advice.cardioDays, 1);
    expect(advice.strengthDays, 6);
    expect(advice.lightDays, 0);
    expect(advice.restDays, 0);
    final cardioDay = advice.week.firstWhere((day) => day.isCardio);
    expect(cardioDay.title, contains('Cardio'));
    expect(cardioDay.isRest, isFalse);
    expect(cardioDay.isLight, isFalse);
  });

  test('dni poza dniami treningowymi są wolne w podsumowaniu', () {
    final advice = buildWeeklyTrainingAdvice(
      recovery: const {},
      recentLogs: const [],
      recentActivities: const [],
      goal: 'Masa',
      level: 'Początkujący',
      // Tylko poniedziałek jest dniem treningowym.
      trainingWeekdays: const [1],
      now: monday,
    );

    expect(advice.restDays, 6);
    expect(advice.strengthDays, 1);
  });

  group('Stały rozkład tygodnia ma pierwszeństwo', () {
    List<ScheduledFocusDay> scheduleFrom(DateTime start) => [
          for (var i = 0; i < 7; i++)
            ScheduledFocusDay(
              date: start.add(Duration(days: i)),
              primary: i == 6
                  ? null
                  : kPrimaryFocusAreas[i % kPrimaryFocusAreas.length],
              secondary: i == 6 ? null : TrainingFocusArea.shoulders,
              isRest: i == 6,
            ),
        ];

    test('tydzień jest przepisany z rozkładu, nie wymyślony od nowa', () {
      final schedule = scheduleFrom(DateTime(2026, 7, 6));
      final advice = buildWeeklyTrainingAdvice(
        recovery: tiredUpperBody,
        recentLogs: const [],
        recentActivities: const [],
        goal: 'Masa',
        level: 'Początkujący',
        trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
        fixedSchedule: schedule,
        now: monday,
      );

      expect(advice.week, hasLength(7));
      for (var i = 0; i < 6; i++) {
        expect(advice.week[i].title,
            contains(kPrimaryFocusAreas[i % kPrimaryFocusAreas.length].label),
            reason: 'dzień ${i + 1} nie odpowiada rozkładowi');
        expect(advice.week[i].title, contains(TrainingFocusArea.shoulders.label),
            reason: 'dodatek dnia powinien być widoczny w tytule');
      }
      expect(advice.week.last.isRest, isTrue);
    });

    test('nagłówek na dziś mówi o partii z rozkładu, nie o najlepiej '
        'zregenerowanej', () {
      // Klatka jest zmęczona (50%), nogi w 100% — mimo to poniedziałek jest
      // dniem klatki, bo tak ustawił użytkownik.
      final advice = buildWeeklyTrainingAdvice(
        recovery: tiredUpperBody,
        recentLogs: const [],
        recentActivities: const [],
        goal: 'Masa',
        level: 'Początkujący',
        trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
        fixedSchedule: scheduleFrom(DateTime(2026, 7, 6)),
        now: monday,
      );

      expect(advice.todayHeadline, contains('planu tygodnia'));
      expect(advice.todayHeadline,
          contains(TrainingFocusArea.chestTriceps.label));
      expect(advice.todayHeadline, isNot(contains('Dobry dzień na trening')));
    });

    test('propozycje ćwiczeń celują w partię z rozkładu', () {
      final exercises = [
        _exercise('wyciskanie', 'Początkujący',
            [ExerciseMuscleImpact(muscleGroup: BodyMuscle.chest, role: MuscleRole.primary)]),
        _exercise('przysiad', 'Początkujący',
            [ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary)]),
      ];
      final advice = buildWeeklyTrainingAdvice(
        recovery: const {},
        recentLogs: const [],
        recentActivities: const [],
        goal: 'Masa',
        level: 'Początkujący',
        trainingWeekdays: const [1, 2, 3, 4, 5, 6, 7],
        fixedSchedule: scheduleFrom(DateTime(2026, 7, 6)),
        exercises: exercises,
        now: monday,
      );

      expect(advice.todayExercises.map((e) => e.exerciseId),
          contains('wyciskanie'));
      expect(advice.todayExercises.map((e) => e.exerciseId),
          isNot(contains('przysiad')));
    });

    test('dzień wolny z rozkładu zostaje dniem wolnym', () {
      final sunday = DateTime(2026, 7, 12, 9);
      final advice = buildWeeklyTrainingAdvice(
        recovery: const {},
        recentLogs: const [],
        recentActivities: const [],
        goal: 'Masa',
        level: 'Początkujący',
        trainingWeekdays: const [1, 2, 3, 4, 5, 6],
        fixedSchedule: [
          ScheduledFocusDay(date: sunday, isRest: true),
        ],
        now: sunday,
      );

      expect(advice.todayHeadline, contains('dzień wolny'));
      expect(advice.todayExercises, isEmpty);
    });
  });
}
