import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/deload_cycle.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AppStore store) => AppScope(
      store: store,
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: const Scaffold(
          body: SingleChildScrollView(child: DeloadHeadlineBanner()),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('baner ukryty, gdy deload jest daleko', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load(); // domyślny cykl zakotwiczony na dziś → deload za 35 dni
    await tester.pumpWidget(_wrap(store));
    await tester.pump();
    expect(find.byKey(const Key('deload_headline_banner')), findsNothing);
  });

  testWidgets('baner pokazuje TRWAJĄCY deload i opis po dotknięciu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.startDeloadNow(); // dziś = dzień 1 deloadu

    await tester.pumpWidget(_wrap(store));
    await tester.pump();

    expect(find.byKey(const Key('deload_headline_banner')), findsOneWidget);
    expect(find.textContaining('Trwa deload'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deload_headline_banner')));
    await tester.pumpAndSettle();
    expect(find.text('Deload — tydzień odciążenia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('baner ostrzega o ZBLIŻAJĄCYM się deloadzie', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Ustaw start deloadu za 5 dni.
    await store.updateDeloadCycle(
      reanchorDeloadStart(store.deloadCycle, today.add(const Duration(days: 5))),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pump();

    expect(find.byKey(const Key('deload_headline_banner')), findsOneWidget);
    expect(find.textContaining('Zbliża się deload'), findsOneWidget);
  });
}
