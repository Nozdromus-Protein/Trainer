import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/equipment_program_filter.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise.dart';
import 'package:licznik_treningu/features/trainer/domain/program_exercises.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_enums.dart';

/// Rozbudowa bazy ćwiczeń: spójność danych i poprawne tagowanie sprzętu, żeby
/// ćwiczenia na maszynie/wyciągu NIE pojawiały się bez zaznaczonego sprzętu.
void main() {
  test('id ćwiczeń w puli są unikalne', () {
    final ids = <String>{};
    for (final exercise in kProgramExercises) {
      expect(ids.add(exercise.id), isTrue, reason: 'duplikat id: ${exercise.id}');
    }
  });

  test('każde ćwiczenie ma partię główną i nieprzezroczysty opis', () {
    for (final exercise in kProgramExercises) {
      final hasPrimary = exercise.effectiveMuscleImpacts
          .any((impact) => impact.role == MuscleRole.primary);
      expect(hasPrimary, isTrue, reason: '${exercise.id}: brak partii głównej');
      expect(exercise.name.trim(), isNotEmpty, reason: exercise.id);
      expect(exercise.description.trim(), isNotEmpty, reason: exercise.id);
    }
  });

  test('ćwiczenia na maszynie/wyciągu są niedostępne bez tego sprzętu', () {
    // Sprzęt typowego domu: masa ciała, hantle, guma, ławka, drążek — BEZ
    // maszyny i wyciągu.
    const homeGym = <EquipmentType>{
      EquipmentType.bodyweight,
      EquipmentType.dumbbell,
      EquipmentType.resistanceBand,
      EquipmentType.bench,
      EquipmentType.pullUpBar,
      EquipmentType.kettlebell,
      EquipmentType.mat,
    };
    for (final id in const [
      'machine_chest_press',
      'machine_lat_pulldown',
      'cable_crossover',
      'cable_curl',
      'cable_pushdown',
      'cable_woodchopper',
    ]) {
      final exercise = kProgramExercises.firstWhere((e) => e.id == id);
      expect(isExerciseAvailable(exercise, homeGym), isFalse,
          reason: '$id nie powinno być dostępne bez maszyny/wyciągu');
    }
  });

  test('ćwiczenia z masy ciała są dostępne dla każdego', () {
    const nothing = <EquipmentType>{EquipmentType.bodyweight};
    for (final id in const [
      'wide_pushup',
      'archer_pushup',
      'close_grip_pushup',
      'v_up',
      'nordic_curl',
      'frog_pump',
    ]) {
      final Exercise exercise = kProgramExercises.firstWhere((e) => e.id == id);
      expect(isExerciseAvailable(exercise, nothing), isTrue,
          reason: '$id powinno być dostępne z samej masy ciała');
    }
  });

  test('dla każdej dużej partii jest co najmniej 5 ćwiczeń w puli', () {
    int countFor(MuscleGroup group) => kProgramExercises
        .where((e) => e.effectiveMuscleImpacts.any((impact) =>
            impact.role == MuscleRole.primary &&
            MuscleGroup.fromText(impact.muscleGroup.label) == group))
        .length;
    for (final group in const [
      MuscleGroup.chest,
      MuscleGroup.back,
      MuscleGroup.shoulders,
      MuscleGroup.biceps,
      MuscleGroup.triceps,
      MuscleGroup.quadriceps,
      MuscleGroup.hamstrings,
      MuscleGroup.glutes,
      MuscleGroup.calves,
    ]) {
      expect(countFor(group), greaterThanOrEqualTo(5),
          reason: 'za mało ćwiczeń na partię: ${group.label}');
    }
  });
}
