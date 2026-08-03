import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/features/trainer/domain/workout_volume_limits.dart';
import 'package:licznik_treningu/main.dart';

/// INTENSYWNOŚĆ ↔ LIMITY OBJĘTOŚCI.
///
/// Wcześniej limity były od intensywności całkowicie niezależne, więc „lekka"
/// i „bardzo wysoka" projektowały dokładnie ten sam zestaw. Teraz intensywność
/// przesuwa zakres (ćwiczenia, serie, powtórzenia, przerwy), a odchylenie od
/// niego jest nazwane: w limicie ▸ nieznacznie ▸ znacznie.
Exercise _resolve(String id) => ExerciseRepo.byId(id);

PlanItem _item(String id, {int sets = 3, int reps = 10}) => PlanItem(
      exerciseId: id,
      sets: sets,
      reps: reps,
      durationSec: 0,
      note: '',
    );

void main() {
  group('Intensywność przesuwa limity objętości', () {
    test('poziomy wynikają z kroków gałki intensywności', () {
      expect(WorkoutIntensityLevel.fromSteps(-6), WorkoutIntensityLevel.light);
      expect(WorkoutIntensityLevel.fromSteps(-3), WorkoutIntensityLevel.light);
      expect(
          WorkoutIntensityLevel.fromSteps(0), WorkoutIntensityLevel.moderate);
      expect(WorkoutIntensityLevel.fromSteps(2), WorkoutIntensityLevel.high);
      expect(
          WorkoutIntensityLevel.fromSteps(6), WorkoutIntensityLevel.veryHigh);
    });

    test('wyższa intensywność = szerszy zakres ćwiczeń i serii', () {
      final light = volumeLimitsFor(MuscleGroup.chest,
          intensity: WorkoutIntensityLevel.light);
      final moderate = volumeLimitsFor(MuscleGroup.chest);
      final veryHigh = volumeLimitsFor(MuscleGroup.chest,
          intensity: WorkoutIntensityLevel.veryHigh);

      expect(light.exercises.max, lessThan(moderate.exercises.max));
      expect(veryHigh.exercises.max, greaterThan(moderate.exercises.max));
      expect(veryHigh.sets.max, greaterThanOrEqualTo(moderate.sets.max));
      expect(light.sets.max, lessThan(moderate.sets.max));
      // Górna granica serii roboczych rośnie z intensywnością.
      expect(veryHigh.maxWorkingSets, greaterThan(moderate.maxWorkingSets));
      expect(light.maxWorkingSets, lessThan(moderate.maxWorkingSets));
    });

    test('lekki dzień idzie wyżej w powtórzeniach, bardzo wysoki niżej', () {
      final light = volumeLimitsFor(MuscleGroup.chest,
          intensity: WorkoutIntensityLevel.light);
      final veryHigh = volumeLimitsFor(MuscleGroup.chest,
          intensity: WorkoutIntensityLevel.veryHigh);
      expect(light.reps.max, greaterThan(veryHigh.reps.max));
    });

    test('domyślne wywołanie (bez intensywności) nic nie zmienia', () {
      final withDefault =
          volumeLimitsFor(MuscleGroup.back, level: 'Zaawansowany');
      final explicit = volumeLimitsFor(MuscleGroup.back,
          level: 'Zaawansowany', intensity: WorkoutIntensityLevel.moderate);
      expect(withDefault.exercises, explicit.exercises);
      expect(withDefault.sets, explicit.sets);
      expect(withDefault.reps, explicit.reps);
    });

    test('przerwy rosną wraz z intensywnością', () {
      expect(WorkoutIntensityLevel.light.restFactor, lessThan(1.0));
      expect(WorkoutIntensityLevel.veryHigh.restFactor, greaterThan(1.0));
      final light = buildWorkoutProgram('program_chest',
          resolveExercise: _resolve, intensity: WorkoutIntensityLevel.light);
      final heavy = buildWorkoutProgram('program_chest',
          resolveExercise: _resolve, intensity: WorkoutIntensityLevel.veryHigh);
      int longestRest(WorkoutPlan plan) {
        var best = 0;
        for (final day in plan.days) {
          for (final item in day.items) {
            if (item.restSeconds > best) best = item.restSeconds;
          }
        }
        return best;
      }

      expect(longestRest(heavy), greaterThan(longestRest(light)));
    });
  });

  group('Pasmo objętości nazywa odchylenie', () {
    test('zestaw w zakresie ma status „w limicie"', () {
      final limits = volumeLimitsFor(MuscleGroup.chest);
      // Tyle ćwiczeń i serii, żeby wpaść w środek pasma.
      // Wszystkie trzy pozycje mają klatkę jako partię GŁÓWNĄ, więc pasmo
      // liczy się z jednego zestawu limitów.
      const chestIds = ['bench_press', 'pushup', 'db_fly'];
      final items = [
        for (var i = 0; i < limits.exercises.min; i++)
          _item(chestIds[i % chestIds.length], sets: limits.sets.min),
      ];
      final band = describeWorkoutVolumeBand(items: items, resolve: _resolve);
      expect(band.hasData, isTrue);
      expect(band.status, VolumeBandStatus.within);
      expect(band.deviationLabel, isEmpty);
    });

    test('duże przekroczenie to „znacznie powyżej" z liczbą serii', () {
      final items = [
        _item('bench_press', sets: 12),
        _item('pushup', sets: 12),
        _item('db_fly', sets: 12),
      ];
      final band = describeWorkoutVolumeBand(items: items, resolve: _resolve);
      expect(band.status, VolumeBandStatus.farAbove);
      expect(band.status.isSevere, isTrue);
      expect(band.setsOverMax, greaterThan(0));
      expect(band.deviationLabel, contains('Przekroczono górny limit'));
      expect(band.currentLabel, contains('Aktualna objętość'));
      expect(band.recommendedLabel, contains('Zalecany zakres'));
    });

    test('zbyt mała objętość to „poniżej" z procentem', () {
      final band = describeWorkoutVolumeBand(
        items: [_item('bench_press', sets: 1)],
        resolve: _resolve,
      );
      expect(band.status.isBelow, isTrue);
      expect(band.setsUnderMin, greaterThan(0));
      expect(band.deviationPercent, greaterThan(0));
      expect(band.deviationLabel, contains('niższa niż dolna granica'));
    });

    test(
        'to samo obciążenie może być w limicie lub poza nim — zależnie '
        'od intensywności', () {
      final items = [
        _item('bench_press', sets: 5),
        _item('pushup', sets: 5),
        _item('db_fly', sets: 5),
      ];
      final light = describeWorkoutVolumeBand(
          items: items,
          resolve: _resolve,
          intensity: WorkoutIntensityLevel.light);
      final veryHigh = describeWorkoutVolumeBand(
          items: items,
          resolve: _resolve,
          intensity: WorkoutIntensityLevel.veryHigh);
      expect(veryHigh.recommendedMax, greaterThan(light.recommendedMax));
      expect(light.status.index, greaterThanOrEqualTo(veryHigh.status.index),
          reason: 'przy lekkiej intensywności ten sam zestaw jest „wyżej" '
              'względem zalecanego zakresu');
    });

    test('pusty zestaw nie udaje danych', () {
      final band =
          describeWorkoutVolumeBand(items: const [], resolve: _resolve);
      expect(band.hasData, isFalse);
      expect(band.workingSets, 0);
    });
  });

  group('Generator uzupełnia zestaw do limitu', () {
    test('każdy dzień siłowy spełnia minimum ćwiczeń partii wiodącej', () {
      for (final meta in kWorkoutProgramCatalog) {
        if (meta.id == 'program_core') continue; // obwód ma inną strukturę
        final plan = buildWorkoutProgram(meta.id, resolveExercise: _resolve);
        for (final day in plan.days) {
          if (!day.kind.isHeavy) continue;
          final report = analyzeWorkoutVolume(
            items: day.items,
            resolve: _resolve,
          );
          // Partia wiodąca dnia nie może być poniżej minimum ćwiczeń.
          final leading = report.counts.values.isEmpty
              ? null
              : report.counts.values
                  .reduce((a, b) => a.exerciseCount >= b.exerciseCount ? a : b);
          if (leading == null) continue;
          expect(leading.exerciseCount,
              greaterThanOrEqualTo(leading.limits.exercises.min),
              reason: '${meta.id} „${day.title}": partia wiodąca '
                  '${leading.group.label} ma za mało ćwiczeń');
        }
      }
    });

    test('wyższa intensywność daje zestawy o nie mniejszej objętości', () {
      int workingSets(WorkoutPlan plan) {
        var total = 0;
        for (final day in plan.days) {
          for (final item in day.items) {
            if (isWorkingVolumeItem(item, _resolve(item.exerciseId))) {
              total += item.sets;
            }
          }
        }
        return total;
      }

      final light = buildWorkoutProgram('program_back',
          resolveExercise: _resolve, intensity: WorkoutIntensityLevel.light);
      final heavy = buildWorkoutProgram('program_back',
          resolveExercise: _resolve, intensity: WorkoutIntensityLevel.veryHigh);
      expect(workingSets(heavy), greaterThan(workingSets(light)));
    });
  });
}
