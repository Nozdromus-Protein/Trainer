import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise_intensity.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

// Limity objętości zestawu: dolna i górna granica liczby ćwiczeń, serii
// i powtórzeń NA PARTIĘ MIĘŚNIOWĄ. Limity opisują BUDOWĘ zestawu — ręczne
// podkręcanie intensywności celowo działa poza nimi.

PlanItem _item(String id, {int sets = 3, int reps = 10, String note = ''}) =>
    PlanItem(
        exerciseId: id, sets: sets, reps: reps, durationSec: 0, note: note);

Exercise _resolve(String id) => ExerciseRepo.byId(id);

void main() {
  group('Zakresy min–max', () {
    test('przycinanie i zawieranie', () {
      const bounds = VolumeBounds(3, 6);
      expect(bounds.clampValue(1), 3);
      expect(bounds.clampValue(9), 6);
      expect(bounds.clampValue(4), 4);
      expect(bounds.contains(3), isTrue);
      expect(bounds.contains(7), isFalse);
      expect(bounds.label, '3–6');
    });

    test('część wspólna z zakresem celu; rozłączne zakresy → wygrywa twardy',
        () {
      const hard = VolumeBounds(4, 20);
      expect(hard.intersect(const VolumeBounds(8, 12)),
          const VolumeBounds(8, 12));
      // Zakres celu całkowicie poza limitem — limit twardy zostaje.
      expect(hard.intersect(const VolumeBounds(30, 40)), hard);
    });
  });

  group('Limity efektywne (poziom + cel)', () {
    test('początkujący dostaje węższy zestaw niż zaawansowany', () {
      final beginner = volumeLimitsFor(MuscleGroup.chest,
          level: 'Początkujący');
      final advanced = volumeLimitsFor(MuscleGroup.chest,
          level: 'Zaawansowany');
      expect(beginner.exercises.max, lessThan(advanced.exercises.max));
      expect(beginner.sets.max, lessThan(advanced.sets.max));
    });

    test('„średniozaawansowany" NIE jest czytany jako „zaawansowany"', () {
      final mid = volumeLimitsFor(MuscleGroup.chest,
          level: 'Średniozaawansowany');
      final advanced =
          volumeLimitsFor(MuscleGroup.chest, level: 'Zaawansowany');
      expect(mid.exercises.max, lessThan(advanced.exercises.max));
    });

    test('cel zawęża powtórzenia w granicach twardego limitu', () {
      final strength = volumeLimitsFor(MuscleGroup.chest, goal: 'Siła');
      final mass = volumeLimitsFor(MuscleGroup.chest, goal: 'Masa');
      expect(strength.reps, const VolumeBounds(4, 6));
      expect(mass.reps, const VolumeBounds(8, 12));
    });

    test('nadpisanie użytkownika ma pierwszeństwo przed domyślnym', () {
      const custom = MuscleVolumeLimits(
        exercises: VolumeBounds(5, 10),
        sets: VolumeBounds(4, 8),
        reps: VolumeBounds(10, 20),
      );
      final config = const VolumeLimitsConfig()
          .withGroup(MuscleGroup.biceps, custom);
      expect(config.rawFor(MuscleGroup.biceps), custom);
      // Zapis i odczyt zachowują nadpisanie.
      final restored = VolumeLimitsConfig.fromJson(config.toJson());
      expect(restored.rawFor(MuscleGroup.biceps), custom);
      // Partia bez nadpisania nadal bierze wartość domyślną.
      expect(restored.rawFor(MuscleGroup.chest),
          kDefaultMuscleVolumeLimits[MuscleGroup.chest]);
    });
  });

  group('Analiza zestawu', () {
    test('liczy tylko partię GŁÓWNĄ i pozycje robocze', () {
      final report = analyzeWorkoutVolume(
        items: [
          _item('bench_press'),
          _item('pushup'),
          _item('arm_circles', sets: 1, reps: 0, note: 'Rozgrzewka'),
        ],
        resolve: _resolve,
      );
      // Rozgrzewka nie wchodzi do objętości roboczej.
      final chest = report.counts[MuscleGroup.chest];
      expect(chest, isNotNull);
      expect(chest!.exerciseIds, isNot(contains('arm_circles')));
    });

    test('zgłasza niedobór ćwiczeń partii', () {
      final report = analyzeWorkoutVolume(
        items: [_item('bench_press')],
        resolve: _resolve,
      );
      expect(report.isValid, isFalse);
      expect(
        report.issues.any((i) => i.kind == VolumeIssueKind.exercisesBelowMin),
        isTrue,
      );
      expect(report.groupsNeedingMore, contains(MuscleGroup.chest));
    });

    test('zgłasza zbyt małą i zbyt dużą liczbę serii', () {
      final low = analyzeWorkoutVolume(
        items: [_item('bench_press', sets: 1)],
        resolve: _resolve,
      );
      expect(low.issues.any((i) => i.kind == VolumeIssueKind.setsBelowMin),
          isTrue);
      final high = analyzeWorkoutVolume(
        items: [_item('bench_press', sets: 12)],
        resolve: _resolve,
      );
      expect(high.issues.any((i) => i.kind == VolumeIssueKind.setsAboveMax),
          isTrue);
    });
  });

  group('Egzekwowanie limitów', () {
    test('przycina serie i powtórzenia do granic partii', () {
      final clamped = clampPlanItemToLimits(
        _item('bench_press', sets: 12, reps: 40),
        _resolve('bench_press'),
      );
      final limits = volumeLimitsFor(MuscleGroup.chest);
      expect(clamped.sets, limits.sets.max);
      expect(clamped.reps, limits.reps.max);
    });

    test('wyłączona konfiguracja niczego nie przycina', () {
      final item = _item('bench_press', sets: 12, reps: 40);
      final clamped = clampPlanItemToLimits(
        item,
        _resolve('bench_press'),
        config: const VolumeLimitsConfig(enabled: false),
      );
      expect(clamped.sets, 12);
      expect(clamped.reps, 40);
    });

    test('usuwa nadmiar ćwiczeń partii — odpada najlżejsze', () {
      const limits = MuscleVolumeLimits(
        exercises: VolumeBounds(1, 2),
        sets: VolumeBounds(1, 6),
        reps: VolumeBounds(1, 30),
      );
      final config =
          const VolumeLimitsConfig().withGroup(MuscleGroup.chest, limits);
      final result = enforceVolumeLimits(
        [_item('bench_press'), _item('db_bench_press'), _item('pushup')],
        _resolve,
        config: config,
        weightOf: exerciseIntensityScore,
      );
      expect(result, hasLength(2));
      // Pompki (bez obciążenia zewnętrznego) są najlżejsze — one wypadają.
      expect(result.map((i) => i.exerciseId), isNot(contains('pushup')));
    });

    test('uzupełnianie dobiera ćwiczenia TEJ partii i nie duplikuje', () {
      final additions = topUpToMinimumExercises(
        items: [_item('bench_press')],
        pool: const [
          'bench_press', // już w zestawie
          'squat', // inna partia
          'db_bench_press',
          'incline_bench_press',
        ],
        resolve: _resolve,
        group: MuscleGroup.chest,
      );
      expect(additions, isNot(contains('bench_press')));
      expect(additions, isNot(contains('squat')));
      expect(additions, isNotEmpty);
    });
  });

  group('Programy katalogu respektują limity', () {
    test('żadne ćwiczenie dnia siłowego nie ma serii spoza limitu', () {
      for (final meta in kWorkoutProgramCatalog) {
        if (meta.id == 'program_core') continue; // obwód — inna struktura
        final plan =
            buildWorkoutProgram(meta.id, resolveExercise: ExerciseRepo.byId);
        for (final day in plan.days) {
          final report = analyzeWorkoutVolume(
            items: day.items,
            resolve: ExerciseRepo.byId,
            level: 'Średniozaawansowany',
          );
          final setIssues = report.issues.where((i) =>
              i.kind == VolumeIssueKind.setsAboveMax ||
              i.kind == VolumeIssueKind.setsBelowMin);
          expect(setIssues, isEmpty,
              reason: '${meta.id} „${day.title}": ${setIssues.map((i) => i.message)}');
        }
      }
    });

    test('partia wiodąca dnia ma co najmniej minimum ćwiczeń', () {
      final plan =
          buildWorkoutProgram('program_chest', resolveExercise: ExerciseRepo.byId);
      final day = plan.days.first;
      final report = analyzeWorkoutVolume(
        items: day.items,
        resolve: ExerciseRepo.byId,
        level: 'Średniozaawansowany',
      );
      final chest = report.counts[MuscleGroup.chest];
      expect(chest, isNotNull);
      expect(chest!.exerciseCount,
          greaterThanOrEqualTo(chest.limits.exercises.min));
    });
  });
}
