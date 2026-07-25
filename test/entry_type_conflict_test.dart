import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

void main() {
  group('Typ wpisu nie kłóci się z zawartością ćwiczenia', () {
    test('„Wykroki chodzone" to ćwiczenie na powtórzenia, nie cardio', () {
      final exercise = ExerciseRepo.byId('walking_lunge', const []);
      expect(exercise.name, contains('Wykroki'));
      expect(exercise.entryType.showsReps, isTrue,
          reason: 'karta pokazuje serie i powtórzenia — panel wpisu też musi');
      expect(exercise.entryType.showsDistance, isFalse);
      expect(exercise.entryType, isNot(ExerciseEntryType.cardioDistanceTime));
    });

    test('twarde dane ćwiczenia biją heurystykę z nazwy', () {
      // Powtórzenia > 0 i brak czasu domyślnego → ćwiczenie powtórzeniowe,
      // niezależnie od tego, jakie słowo padnie w nazwie.
      expect(
        deriveEntryType(
          name: 'Marsz farmera z hantlami',
          category: 'Przedramiona',
          equipment: 'hantle',
          defaultDurationSec: 0,
          defaultReps: 10,
        ),
        ExerciseEntryType.repsWeight,
      );
      expect(
        deriveEntryType(
          name: 'Wykroki chodzone',
          category: 'Nogi',
          equipment: 'masa ciała / hantle',
          defaultDurationSec: 0,
          defaultReps: 12,
        ).showsReps,
        isTrue,
      );
    });

    test('prawdziwe cardio (czasowe) dalej dostaje panel dystansu', () {
      expect(
        deriveEntryType(
          name: 'Bieg ciągły',
          category: 'Cardio',
          equipment: 'brak',
          defaultDurationSec: 900,
          defaultReps: 0,
        ),
        ExerciseEntryType.cardioDistanceTime,
      );
    });

    test('krótkie drille w obwodzie nie dostają pola „Dystans"', () {
      // „C(run)ches" łapało się na słowie „run", a 40-sekundowy „Bieg z piętami
      // do pośladków" na „bieg" — oba dostawały panel cardio z kilometrami.
      for (final id in const [
        'side_crunch_left',
        'crunch_90_90',
        'butt_kicks',
        'jumping_jack',
        'skater_hops',
      ]) {
        final exercise = ExerciseRepo.byId(id, const []);
        expect(exercise.entryType.showsDistance, isFalse,
            reason: '$id (${exercise.name}) nie jest cardio z dystansem');
        expect(exercise.entryType.showsDuration, isTrue,
            reason: '$id prowadzi się czasem');
      }
    });

    test('prawdziwe locomotion nadal jest cardio z dystansem', () {
      expect(ExerciseRepo.byId('march_steady', const []).entryType,
          ExerciseEntryType.cardioDistanceTime);
      expect(ExerciseRepo.byId('run', const []).entryType.showsDistance, isTrue);
      expect(
          ExerciseRepo.byId('bike', const []).entryType.showsDistance, isTrue);
    });

    test('żadne ćwiczenie z puli programów nie miesza jednostek', () {
      for (final exercise in ExerciseRepo.combined(const [])) {
        final type = exercise.entryType;
        // Ćwiczenie opisane powtórzeniami i bez czasu domyślnego nie może
        // dostać panelu, który powtórzeń w ogóle nie zna.
        if (exercise.defaultReps > 0 && exercise.defaultDurationSec == 0) {
          expect(type.showsReps, isTrue,
              reason: '${exercise.id} (${exercise.name}) ma '
                  '${exercise.defaultReps} powtórzeń, a typ wpisu ${type.key} '
                  'ich nie pokazuje');
        }
        // I odwrotnie: pole dystansu ma sens tylko przy realnym locomotion.
        if (type.showsDistance) {
          expect(exercise.defaultDurationSec, greaterThanOrEqualTo(300),
              reason: '${exercise.id} (${exercise.name}) dostaje pole dystansu '
                  'przy ${exercise.defaultDurationSec} s');
        }
      }
    });

    test('pozycja planu nigdy nie kłóci się z panelem wpisu ćwiczenia', () {
      Exercise resolve(String id) => ExerciseRepo.byId(id, const []);
      for (final meta in kWorkoutProgramCatalog) {
        final plan =
            buildWorkoutProgram(meta.id, resolveExercise: resolve);
        for (final day in plan.days) {
          for (final item in day.items) {
            final exercise = resolve(item.exerciseId);
            final type = exercise.entryType;
            final timeBased = type.showsDuration && !type.showsReps;
            if (timeBased) {
              expect(item.durationSec, greaterThan(0),
                  reason: '${meta.id}/${exercise.id}: ćwiczenie czasowe bez '
                      'czasu w planie');
              expect(item.reps, 0,
                  reason: '${meta.id}/${exercise.id}: ćwiczenie czasowe '
                      'z powtórzeniami w planie');
            } else {
              expect(item.reps, greaterThan(0),
                  reason: '${meta.id}/${exercise.id}: ćwiczenie powtórzeniowe '
                      'bez powtórzeń w planie');
              expect(item.durationSec, 0,
                  reason: '${meta.id}/${exercise.id}: ćwiczenie powtórzeniowe '
                      'z czasem serii w planie');
            }
          }
        }
      }
    });
  });
}
