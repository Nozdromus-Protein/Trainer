import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ekran limitów objętości: zmiana granicy zapisuje się w magazynie i przeżywa
// ponowne wczytanie ustawień.

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  return store;
}

Widget _wrap(AppStore store) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), true),
      home: AppScope(
        store: store,
        child: const Scaffold(body: VolumeLimitsSettingsPage()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('podniesienie minimum ćwiczeń zapisuje się i wraca po restarcie',
      (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    final before = store.volumeLimits.rawFor(MuscleGroup.chest).exercises.min;
    final row = find.byKey(const Key('limit_exercises_chest'));
    expect(row, findsOneWidget);
    // Pierwszy „+" w wierszu podnosi MINIMUM (drugi — maksimum).
    final plus = find
        .descendant(of: row, matching: find.byIcon(Icons.add_rounded))
        .first;
    await tester.tap(plus);
    await tester.pumpAndSettle();

    expect(store.volumeLimits.rawFor(MuscleGroup.chest).exercises.min,
        before + 1);

    // Nowy magazyn czyta zapisane nadpisanie z tych samych preferencji.
    final reloaded = AppStore();
    await reloaded.load();
    expect(reloaded.volumeLimits.rawFor(MuscleGroup.chest).exercises.min,
        before + 1);
  });

  testWidgets('wyłączenie limitów przestaje przycinać zestaw', (tester) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('volume_limits_enabled')));
    await tester.pumpAndSettle();
    expect(store.volumeLimits.enabled, isFalse);

    const item = PlanItem(
        exerciseId: 'bench_press',
        sets: 12,
        reps: 40,
        durationSec: 0,
        note: '');
    final clamped = clampPlanItemToLimits(
      item,
      ExerciseRepo.byId('bench_press'),
      config: store.volumeLimits,
    );
    expect(clamped.sets, 12);
    expect(clamped.reps, 40);
  });
}
