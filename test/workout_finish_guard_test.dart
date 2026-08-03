import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ZAWIESZANIE PO „GOTOWE".
///
/// Przycisk wołał `Navigator.pop()` bez żadnego zabezpieczenia, a ekran pod
/// spodem (odtwarzacz z zakończoną sesją) planował własny `pop()` w
/// `addPostFrameCallback` — bez sprawdzenia, czy w ogóle jest na wierzchu.
/// Dwa szybkie kliknięcia albo jedno tyknięcie timera zdejmowały ekran za
/// dużo i zostawiały martwy, nieklikalny widok.
const _program = WorkoutPlan(
  id: 'guard_prog',
  name: 'Program testowy',
  note: '',
  goal: 'Sylwetka',
  isActive: true,
  days: [
    WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
      PlanItem(
          exerciseId: 'pushup', sets: 1, reps: 10, durationSec: 0, note: ''),
    ]),
  ],
);

Future<(AppStore, CompletedWorkoutSummary)> _finishedWorkout() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.addWorkoutPlan(_program);
  final plan = store.plans.firstWhere((p) => p.id == 'guard_prog');
  await store.startActiveWorkout(plan: plan, day: plan.days[0], dayIndex: 0);
  await store.saveActiveWorkoutSet(weightKg: 20, repetitions: 10, rpe: 7);
  final summary = await store.finishActiveWorkout();
  return (store, summary!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('„Gotowe" zamyka podsumowanie dokładnie raz', (tester) async {
    final (store, summary) = await _finishedWorkout();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // AppScope NAD MaterialApp — inaczej trasy pchane przez Navigator stoją
    // poza zasięgiem sklepu (Navigator jest wyżej niż `home`).
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => WorkoutSummaryPage(summary: summary)),
                  ),
                  child: const Text('otwórz'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();
    expect(find.text('Podsumowanie treningu'), findsOneWidget);

    final done = find.byKey(const Key('workout_summary_done'));
    await tester.scrollUntilVisible(done, 300,
        scrollable: find.byType(Scrollable).first);

    // Trzy szybkie kliknięcia pod rząd — tak wygląda nerwowe tapnięcie.
    await tester.tap(done);
    await tester.pump();
    await tester.tap(done, warnIfMissed: false);
    await tester.pump();
    await tester.tap(done, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Wracamy DOKŁADNIE na ekran pod spodem, a nie „poza" nawigację.
    expect(find.text('otwórz'), findsOneWidget);
    expect(find.text('Podsumowanie treningu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('przycisk blokuje się po pierwszym kliknięciu', (tester) async {
    final (store, summary) = await _finishedWorkout();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), false),
          // Bez trasy pod spodem `pop()` nie ma czego zdjąć — zostaje sam stan
          // przycisku, który po kliknięciu musi być wyłączony.
          home: WorkoutSummaryPage(summary: summary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final done = find.byKey(const Key('workout_summary_done'));
    await tester.scrollUntilVisible(done, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(done);
    await tester.pump();

    // Klucz siedzi wprost na przycisku (FilledButton.icon to fabryka
    // FilledButton), więc czytamy go bez szukania przodka.
    final button = tester.widget<FilledButton>(done);
    expect(button.onPressed, isNull,
        reason: 'druga operacja kończenia nie może wystartować');
    expect(find.text('Zamykam…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('trening jest zapisany LOKALNIE zanim pokaże się podsumowanie',
      () async {
    final (store, summary) = await _finishedWorkout();
    // Brak sieci nie może blokować zamknięcia — wpis już jest w historii.
    expect(store.logs.any((log) => log.sessionId == summary.sessionId), isTrue);
    expect(store.activeWorkoutSession, isNull);
    expect(summary.completionStatus, 'completed');
  });
}
