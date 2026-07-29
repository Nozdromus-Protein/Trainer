import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ostrożna progresja musi trafiać do RECEPTY SESJI, nie tylko do karty
// z wyjaśnieniem. Inaczej aplikacja mówiłaby „pół kroku", a proponowała pełny.

WorkoutSet _set({
  required int order,
  required double weight,
  int reps = 12,
  int restBefore = 0,
  int plannedRest = 0,
  bool restVerified = false,
}) =>
    WorkoutSet(
      id: 'set_${order}_$weight',
      order: order,
      repetitions: reps,
      weightKg: weight,
      durationSec: 0,
      rpe: 7,
      isCompleted: true,
      rpeSource: 'user',
      restBeforeSec: restBefore,
      plannedRestSec: plannedRest,
      isRestVerified: restVerified,
    );

WorkoutLog _log({
  required String id,
  required DateTime date,
  required double weight,
  int reps = 12,
  List<WorkoutSet>? sets,
}) =>
    WorkoutLog(
      id: id,
      exerciseId: 'bench_press',
      date: date,
      sets: 3,
      reps: reps,
      weightKg: weight,
      durationSec: 0,
      rpe: 7,
      calories: 0,
      note: '',
      aiConfidence: 0,
      sessionId: 'session_$id',
      workoutSets: sets ??
          [
            for (var order = 1; order <= 3; order++)
              _set(order: order, weight: weight, reps: reps),
          ],
    );

Future<AppStore> _storeWithHistory(List<WorkoutLog> history) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  for (final log in history) {
    await store.addLog(log);
  }
  return store;
}

SessionPrescription _prescriptionFor(AppStore store) =>
    store.buildSessionPrescription(
      ExerciseRepo.byId('bench_press'),
      baseSets: 3,
      baseReps: 12,
      baseWeightKg: 0,
      baseRestSeconds: 90,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stabilna historia w tym samym ciężarze → pełny krok trenera', () async {
    final now = DateTime.now();
    final store = await _storeWithHistory([
      for (var i = 5; i >= 1; i--)
        _log(
            id: 'h$i',
            date: now.subtract(Duration(days: i * 3)),
            weight: 40),
    ]);

    final rx = _prescriptionFor(store);
    expect(rx.recommended.weightKg, greaterThan(40),
        reason: 'po serii udanych sesji trener podnosi ciężar');
    final step = store.cautiousProgressionForExercise('bench_press');
    expect(step, isNotNull);
    expect(step!.isDampened, isFalse);
  });

  test('ciężar podniesiony w OSTATNIEJ sesji nie jest dokładany drugi raz',
      () async {
    final now = DateTime.now();
    final store = await _storeWithHistory([
      for (var i = 5; i >= 2; i--)
        _log(
            id: 'h$i',
            date: now.subtract(Duration(days: i * 3)),
            weight: 40),
      // Ostatnia sesja: ciężar już poszedł w górę.
      _log(id: 'h1', date: now.subtract(const Duration(days: 3)), weight: 45),
    ]);

    final step = store.cautiousProgressionForExercise('bench_press');
    expect(step, isNotNull);
    expect(step!.reasons.join(' '), contains('ręcznie'));

    final rx = _prescriptionFor(store);
    // Krok jest stłumiony: nie dokładamy pełnych 2,5 kg na świeżo podniesiony
    // ciężar. Rekomendacja zostaje przy 45 kg albo dokłada mniej niż pełny krok.
    expect(rx.recommended.weightKg, lessThan(47.5));
    expect(rx.recommended.weightKg, greaterThanOrEqualTo(45));
  });

  test('skrócone przerwy tłumią krok w recepcie i w wyjaśnieniu', () async {
    final now = DateTime.now();
    final shortRestSets = [
      for (var order = 1; order <= 3; order++)
        _set(
          order: order,
          weight: 40,
          restBefore: order == 1 ? 0 : 40,
          plannedRest: order == 1 ? 0 : 90,
          restVerified: order != 1,
        ),
    ];
    final store = await _storeWithHistory([
      for (var i = 5; i >= 2; i--)
        _log(
            id: 'h$i',
            date: now.subtract(Duration(days: i * 3)),
            weight: 40),
      _log(
        id: 'h1',
        date: now.subtract(const Duration(days: 3)),
        weight: 40,
        sets: shortRestSets,
      ),
    ]);

    final pace = store.paceForExercise('bench_press');
    expect(pace.shortensRest, isTrue);

    final step = store.cautiousProgressionForExercise('bench_press');
    expect(step!.isDampened, isTrue);
    expect(step.reasons.join(' '), contains('krócej'));
    expect(step.restAdviceSec, greaterThan(0));

    final rx = _prescriptionFor(store);
    // Pełny krok to +2,5 kg; ostrożny musi być mniejszy.
    expect(rx.recommended.weightKg, lessThan(42.5));
    expect(rx.reason, contains('ostrożny'));
  });
}
