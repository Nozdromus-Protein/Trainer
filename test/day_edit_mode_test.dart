import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanItem _item(String id) =>
    PlanItem(exerciseId: id, sets: 3, reps: 10, durationSec: 0, note: '');

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  final plan = WorkoutPlan(
    id: 'edit-plan',
    name: 'Program testowy',
    note: 'Opis',
    goal: 'Sylwetka',
    isActive: true,
    level: 'Średniozaawansowany',
    days: [
      WorkoutDay(
        weekday: 1,
        title: 'Trening A',
        items: [_item('squat'), _item('pushup'), _item('plank')],
      ),
    ],
  );
  await store.addWorkoutPlan(plan);
  return store;
}

Widget _wrap(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(
        store: store,
        child: const WorkoutDayDetailsPage(planId: 'edit-plan', dayIndex: 0),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edycja: ostrzeżenie, minusy, przycisk dodania i usuwanie',
      (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Przed edycją: brak minusów i przycisku dodawania.
    expect(find.byKey(const Key('day_add_exercise')), findsNothing);
    expect(find.byKey(const Key('remove_exercise_0')), findsNothing);

    // Wejście w edycję pokazuje OSTRZEŻENIE o zmianie przemyślanego zestawu.
    await tester.tap(find.byKey(const Key('day_edit_start')));
    await tester.pumpAndSettle();
    expect(find.text('Zmieniasz przemyślany zestaw'), findsOneWidget);

    // Potwierdzenie włącza tryb edycji.
    await tester.tap(find.widgetWithText(FilledButton, 'Edytuj'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_add_exercise')), findsOneWidget);
    expect(find.byKey(const Key('remove_exercise_0')), findsOneWidget);
    expect(find.byKey(const Key('day_edit_done')), findsOneWidget);

    // Usunięcie pierwszego ćwiczenia utrwala się w planie (3 → 2).
    expect(store.plans.firstWhere((p) => p.id == 'edit-plan').days.first.items.length, 3);
    await tester.tap(find.byKey(const Key('remove_exercise_0')));
    await tester.pumpAndSettle();
    expect(store.plans.firstWhere((p) => p.id == 'edit-plan').days.first.items.length, 2);
    expect(
      store.plans.firstWhere((p) => p.id == 'edit-plan').days.first.items.any((i) => i.exerciseId == 'squat'),
      isFalse,
    );

    // Wyjście z trybu edycji.
    await tester.tap(find.byKey(const Key('day_edit_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_add_exercise')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anulowanie ostrzeżenia nie włącza edycji', (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('day_edit_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_add_exercise')), findsNothing);
  });
}
