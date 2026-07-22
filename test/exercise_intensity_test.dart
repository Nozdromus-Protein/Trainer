import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise_intensity.dart';
import 'package:licznik_treningu/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int scoreOf(String id) =>
      exerciseIntensityScore(ExerciseRepo.byId(id));
  ExerciseIntensityTier tierOf(String id) =>
      exerciseIntensityTier(ExerciseRepo.byId(id));

  group('Skala trudności ćwiczeń', () {
    test('wyciskanie sztangi jest cięższe od pompek', () {
      expect(scoreOf('bench_press'), greaterThan(scoreOf('pushup')));
      expect(
          isHarderThan(
              ExerciseRepo.byId('bench_press'), ExerciseRepo.byId('pushup')),
          isTrue);
    });

    test('warianty tego samego ruchu układają się rosnąco', () {
      // Pompki < pompki z nogami na podwyższeniu < wyciskanie hantli < sztanga.
      expect(scoreOf('decline_pushup'), greaterThan(scoreOf('pushup')));
      expect(scoreOf('db_bench_press'), greaterThan(scoreOf('decline_pushup')));
      expect(scoreOf('incline_bench_press'),
          greaterThanOrEqualTo(scoreOf('db_bench_press')));
    });

    test('rozciąganie i rozgrzewka to mobilność, boje to góra skali', () {
      expect(tierOf('child_pose'), ExerciseIntensityTier.mobility);
      expect(tierOf('arm_circles'), ExerciseIntensityTier.mobility);
      expect(tierOf('bench_press').rank,
          greaterThanOrEqualTo(ExerciseIntensityTier.heavy.rank));
    });

    test('cięższe warianty pompek zawierają realne boje ze sztangą', () {
      final pool = ExerciseRepo.combined();
      final harder = alternativesByIntensity(ExerciseRepo.byId('pushup'), pool,
          harder: true);
      expect(harder, isNotEmpty);
      // Wszystkie propozycje są faktycznie cięższe...
      for (final exercise in harder) {
        expect(exerciseIntensityScore(exercise), greaterThan(scoreOf('pushup')));
      }
      // ...i pierwsza jest najbliższym krokiem, a nie największym skokiem.
      expect(exerciseIntensityScore(harder.first),
          lessThanOrEqualTo(exerciseIntensityScore(harder.last)));
      expect(harder.map((e) => e.id), contains('bench_press'));
    });

    test('lżejsze warianty nie proponują rozciągania', () {
      final pool = ExerciseRepo.combined();
      final easier = alternativesByIntensity(
          ExerciseRepo.byId('bench_press'), pool,
          harder: false);
      for (final exercise in easier) {
        expect(exerciseIntensityTier(exercise),
            isNot(ExerciseIntensityTier.mobility));
        expect(exerciseIntensityScore(exercise),
            lessThan(scoreOf('bench_press')));
      }
    });

    test('propozycje trzymają się tej samej partii głównej', () {
      final pool = ExerciseRepo.combined();
      final current = ExerciseRepo.byId('pushup');
      final primary = current.effectiveMuscleImpacts.first.muscleGroup;
      for (final exercise
          in alternativesByIntensity(current, pool, harder: true)) {
        expect(exercise.effectiveMuscleImpacts.first.muscleGroup, primary);
      }
    });
  });
}
