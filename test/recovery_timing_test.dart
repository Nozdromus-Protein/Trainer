import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

/// Ćwiczenie nóg z jawnym przypisaniem partii.
final _squat = Exercise(
  id: 'back_squat',
  name: 'Przysiad ze sztangą',
  category: 'Nogi',
  muscles: const ['czworogłowe uda', 'pośladki'],
  equipment: 'sztanga',
  level: 'Średniozaawansowany',
  illustrationType: 'squat',
  description: '',
  tips: const [],
  commonMistakes: const [],
  defaultSets: 4,
  defaultReps: 8,
  defaultDurationSec: 0,
  met: 5,
  muscleImpacts: const [
    ExerciseMuscleImpact(muscleGroup: BodyMuscle.quads, role: MuscleRole.primary),
    ExerciseMuscleImpact(
        muscleGroup: BodyMuscle.glutes, role: MuscleRole.secondary),
  ],
);

WorkoutLog _log({
  required DateTime day,
  DateTime? sessionStartedAt,
  DateTime? sessionEndedAt,
  DateTime? performedAt,
}) =>
    WorkoutLog(
      id: 'l1',
      exerciseId: _squat.id,
      date: DateTime(day.year, day.month, day.day),
      sets: 4,
      reps: 10,
      weightKg: 80,
      durationSec: 1200,
      rpe: 8,
      calories: 260,
      note: '',
      aiConfidence: 0,
      sessionId: 's1',
      sessionStartedAt: sessionStartedAt,
      sessionEndedAt: sessionEndedAt,
      performedAt: performedAt,
    );

void main() {
  const calculator = RecoveryCalculator(
    profile: RecoveryProfile(bodyWeightKg: 95, age: 34, level: 'Zaawansowany'),
  );

  group('Regeneracja liczy się od godziny treningu, nie od północy', () {
    test('wieczorny trening tuż po zakończeniu realnie męczy partię', () {
      final now = DateTime(2026, 7, 22, 22, 10);
      final map = calculator.compute(
        logs: [
          _log(
            day: now,
            sessionStartedAt: DateTime(2026, 7, 22, 21, 5),
            sessionEndedAt: DateTime(2026, 7, 22, 22, 5),
          ),
        ],
        resolveExercise: (_) => _squat,
        now: now,
      );

      final quads = map[BodyMuscle.quads];
      expect(quads, isNotNull, reason: 'partia główna musi mieć stan');
      // Wcześniej bodziec był datowany na 00:00 tego samego dnia, więc pięć
      // minut po treningu wyglądał na sprzed 22 godzin i mapa pokazywała
      // „zregenerowane" mimo świeżo wykonanej pracy.
      expect(quads!.recoveryPercent, lessThan(50));
      expect(quads.status, isNot(RecoveryStatus.recovered));
    });

    test('regeneracja rośnie z upływem godzin od treningu', () {
      final logs = [
        _log(
          day: DateTime(2026, 7, 22),
          sessionStartedAt: DateTime(2026, 7, 22, 21, 5),
          sessionEndedAt: DateTime(2026, 7, 22, 22, 5),
        ),
      ];
      double at(DateTime moment) =>
          calculator
              .compute(
                logs: logs,
                resolveExercise: (_) => _squat,
                now: moment,
              )[BodyMuscle.quads]
              ?.recoveryPercent ??
          100;

      final justAfter = at(DateTime(2026, 7, 22, 22, 10));
      final nextDay = at(DateTime(2026, 7, 23, 22, 10));
      final twoDays = at(DateTime(2026, 7, 24, 22, 10));

      expect(nextDay, greaterThan(justAfter));
      expect(twoDays, greaterThan(nextDay));
      expect(twoDays, greaterThan(90),
          reason: 'po dwóch dobach ciężki dzień nóg ma być odregenerowany');
    });

    test('wpis ręczny z jawnym momentem też liczy się od tej godziny', () {
      final now = DateTime(2026, 7, 22, 20, 30);
      final map = calculator.compute(
        logs: [_log(day: now, performedAt: DateTime(2026, 7, 22, 20, 0))],
        resolveExercise: (_) => _squat,
        now: now,
      );
      expect(map[BodyMuscle.quads]!.recoveryPercent, lessThan(50));
    });

    test('starszy zapis bez godzin nadal jest analizowany (dzień treningowy)',
        () {
      final map = calculator.compute(
        logs: [_log(day: DateTime(2026, 7, 22))],
        resolveExercise: (_) => _squat,
        now: DateTime(2026, 7, 22, 12),
      );
      expect(map[BodyMuscle.quads], isNotNull,
          reason: 'brak godziny nie może wywalać wpisu z analizy');
    });

    test('czas PRZERW nie liczy się jak czas pracy w ćwiczeniu czasowym', () {
      final plank = Exercise(
        id: 'plank',
        name: 'Deska',
        category: 'Brzuch',
        muscles: const ['brzuch'],
        equipment: 'masa ciała',
        level: 'Początkujący',
        illustrationType: 'plank',
        description: '',
        tips: const [],
        commonMistakes: const [],
        defaultSets: 3,
        defaultReps: 0,
        defaultDurationSec: 40,
        met: 3,
        entryTypeKey: 'bodyweight_time',
        muscleImpacts: const [
          ExerciseMuscleImpact(
              muscleGroup: BodyMuscle.abs, role: MuscleRole.primary),
        ],
      );
      final now = DateTime(2026, 7, 22, 20, 30);
      // 3 × 40 s pracy, ale zapis ćwiczenia obejmuje też 2 × 60 s przerwy.
      final log = WorkoutLog(
        id: 'plank1',
        exerciseId: 'plank',
        date: DateTime(2026, 7, 22),
        sets: 3,
        reps: 0,
        weightKg: 0,
        durationSec: 240,
        rpe: 7,
        calories: 30,
        note: '',
        aiConfidence: 0,
        performedAt: DateTime(2026, 7, 22, 20, 25),
        workoutSets: [
          for (var i = 0; i < 3; i++)
            WorkoutSet(
              id: 'set_$i',
              order: i,
              repetitions: 0,
              weightKg: 0,
              durationSec: 40,
              rpe: 7,
              isCompleted: true,
            ),
        ],
      );
      final map = calculator.compute(
        logs: [log],
        resolveExercise: (_) => plank,
        now: now,
      );
      final abs = map[BodyMuscle.abs]!;
      // 120 s pracy to punkt odniesienia (bodziec ≈ 1), nie podwójna dawka.
      expect(abs.intensityLabel, isNot(TrainingIntensity.veryHard.label));
      expect(abs.recoveryPercent, greaterThan(20));
    });

    test('realna sesja nóg + barków wyraźnie rusza mapę regeneracji', () {
      final press = Exercise(
        id: 'shoulder_press',
        name: 'Wyciskanie żołnierskie',
        category: 'Barki',
        muscles: const ['barki przód'],
        equipment: 'sztanga',
        level: 'Średniozaawansowany',
        illustrationType: 'press',
        description: '',
        tips: const [],
        commonMistakes: const [],
        defaultSets: 3,
        defaultReps: 10,
        defaultDurationSec: 0,
        met: 5,
        muscleImpacts: const [
          ExerciseMuscleImpact(
              muscleGroup: BodyMuscle.frontShoulders,
              role: MuscleRole.primary),
        ],
      );
      final started = DateTime(2026, 7, 22, 21, 10);
      final ended = DateTime(2026, 7, 22, 22, 0);
      final logs = [
        for (var i = 0; i < 5; i++)
          WorkoutLog(
            id: 'legs_$i',
            exerciseId: _squat.id,
            date: DateTime(2026, 7, 22),
            sets: 3,
            reps: 10,
            weightKg: 50,
            durationSec: 480,
            rpe: 7,
            calories: 80,
            note: '',
            aiConfidence: 0,
            sessionId: 'sess',
            sessionStartedAt: started,
            sessionEndedAt: ended,
          ),
        for (var i = 0; i < 5; i++)
          WorkoutLog(
            id: 'sh_$i',
            exerciseId: press.id,
            date: DateTime(2026, 7, 22),
            sets: 3,
            reps: 10,
            weightKg: 20,
            durationSec: 480,
            rpe: 7,
            calories: 60,
            note: '',
            aiConfidence: 0,
            sessionId: 'sess',
            sessionStartedAt: started,
            sessionEndedAt: ended,
          ),
      ];
      final map = calculator.compute(
        logs: logs,
        resolveExercise: (id) => id == press.id ? press : _squat,
        now: DateTime(2026, 7, 22, 22, 7),
      );

      // Dokładnie sytuacja ze zgłoszenia: ~50 min, 10 ćwiczeń, sprawdzenie mapy
      // kilka minut po treningu. Obie partie MUSZĄ być wyraźnie obciążone.
      expect(map[BodyMuscle.quads]!.recoveryPercent, lessThan(20));
      expect(map[BodyMuscle.frontShoulders]!.recoveryPercent, lessThan(20));
      expect(map[BodyMuscle.quads]!.status, RecoveryStatus.freshFatigue);
    });

    test('partia pomocnicza męczy się mniej niż główna', () {
      final now = DateTime(2026, 7, 22, 22, 10);
      final map = calculator.compute(
        logs: [
          _log(
            day: now,
            sessionStartedAt: DateTime(2026, 7, 22, 21, 5),
            sessionEndedAt: DateTime(2026, 7, 22, 22, 5),
          ),
        ],
        resolveExercise: (_) => _squat,
        now: now,
      );
      expect(map[BodyMuscle.glutes]!.recoveryPercent!,
          greaterThan(map[BodyMuscle.quads]!.recoveryPercent!));
    });
  });
}
