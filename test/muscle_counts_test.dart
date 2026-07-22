import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

/// Statystyka „Partie mięśniowe" (najczęściej/najrzadziej trenowane) liczyła
/// się po SUROWYCH etykietach `muscles`, więc warianty tej samej partii
/// („Triceps (głowa długa)", „triceps", fragmenty typu „boczna") pojawiały się
/// jako osobne pozycje — użytkownik widział np. „Triceps (głowa długa)" 2×.
/// Po poprawce liczymy po kanonicznym [BodyMuscle], więc duplikaty znikają.
void main() {
  Exercise custom(String id, List<String> muscles) => Exercise(
        id: id,
        name: id,
        category: 'Test',
        muscles: muscles,
        equipment: 'masa ciała',
        level: 'Początkujący',
        illustrationType: 'generic',
        description: '',
        tips: const [],
        commonMistakes: const [],
        defaultSets: 3,
        defaultReps: 10,
        defaultDurationSec: 0,
        met: 4,
        source: 'custom',
      );

  WorkoutLog log(String exerciseId) => WorkoutLog(
        id: 'l_$exerciseId',
        exerciseId: exerciseId,
        date: DateTime(2026, 7, 16),
        sets: 3,
        reps: 10,
        weightKg: 20,
        durationSec: 0,
        rpe: 7,
        calories: 40,
        note: '',
        aiConfidence: 0,
      );

  test('warianty etykiety tej samej partii liczą się jako JEDNA partia', () {
    final customExercises = [
      custom('ex_a', ['Triceps (głowa długa)']),
      custom('ex_b', ['triceps']),
      custom('ex_c', ['trójgłowe ramienia']),
    ];
    final counts = muscleCounts(
      [log('ex_a'), log('ex_b'), log('ex_c')],
      customExercises,
    );
    // Trzy różne zapisy → jedna kanoniczna partia „Triceps" policzona 3×.
    expect(counts.keys.where((k) => k.toLowerCase().contains('triceps')).length,
        1);
    expect(counts['Triceps'], 3);
  });

  test('ta sama partia w jednym ćwiczeniu nie jest liczona podwójnie', () {
    final customExercises = [
      custom('ex_dup', ['triceps', 'Triceps (głowa boczna)']),
    ];
    final counts = muscleCounts([log('ex_dup')], customExercises);
    expect(counts['Triceps'], 1);
  });

  test('różne partie zostają rozróżnione', () {
    final customExercises = [
      custom('ex_chest', ['klatka piersiowa']),
      custom('ex_back', ['najszerszy grzbietu']),
    ];
    final counts = muscleCounts(
      [log('ex_chest'), log('ex_back')],
      customExercises,
    );
    expect(counts['Klatka piersiowa'], 1);
    expect(counts['Najszerszy grzbietu'], 1);
    expect(counts.length, 2);
  });

  test('brak logów → pusta mapa', () {
    expect(muscleCounts(const [], const []), isEmpty);
  });
}
