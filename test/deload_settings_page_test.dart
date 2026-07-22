import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AppStore store) => AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: const Scaffold(body: DeloadSettingsPage()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ustawienia deloadu: rytm, długość, wyłączenie', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Domyślnie: włączony, 5 tyg. treningu, 7 dni deloadu.
    expect(find.text('Deload włączony'), findsOneWidget);
    expect(store.deloadCycle.trainingDays, 35);
    expect(store.deloadCycle.deloadDays, 7);

    // Zmiana rytmu na 4 tygodnie.
    await tester.tap(find.widgetWithText(ChoiceChip, '4 tyg.'));
    await tester.pumpAndSettle();
    expect(store.deloadCycle.trainingDays, 28);

    // Zmiana długości deloadu na 5 dni.
    await tester.tap(find.widgetWithText(ChoiceChip, '5 dni'));
    await tester.pumpAndSettle();
    expect(store.deloadCycle.deloadDays, 5);

    // Wyłączenie ukrywa podustawienia.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Deload włączony'));
    await tester.pumpAndSettle();
    expect(store.deloadCycle.enabled, isFalse);
    expect(find.text('Rytm'), findsNothing);
  });
}
