import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Dolne menu ma PŁYWAĆ, a nie tylko tak wyglądać: treść musi sięgać do dołu
// ekranu i przewijać się pod paskiem. Sprawdzamy to po `extendBody` Scaffolda
// (bez niego pasek dostaje własny pas, a w szczelinach widać tło Scaffolda)
// oraz po tym, że PageFrame rezerwuje na pasek dolny odstęp.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeShell rozciąga treść pod pływające menu', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppStore store = AppStore();
    await store.load();

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final Scaffold shell = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(
      shell.extendBody,
      isTrue,
      reason: 'bez extendBody menu leży na własnym pasie, a nie pływa',
    );
    expect(shell.bottomNavigationBar, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PageFrame rezerwuje dolny odstęp na pasek', (tester) async {
    // MediaQuery z dolnym marginesem udaje wysokość pływającego menu —
    // dokładnie to, co Scaffold z `extendBody` podaje treści.
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 84)),
          child: Scaffold(
            body: PageFrame(title: 'Test', subtitle: 'podtytuł'),
          ),
        ),
      ),
    );
    await tester.pump();

    final Iterable<SizedBox> spacers = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => box.height == 84);
    expect(
      spacers,
      isNotEmpty,
      reason: 'PageFrame nie dołożył zapasu na pływające menu',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bez pływającego menu PageFrame nie dokłada pustki',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(),
          child: Scaffold(
            body: PageFrame(title: 'Test', subtitle: 'podtytuł'),
          ),
        ),
      ),
    );
    await tester.pump();

    // Zapas schodzi do zera — na podstronach bez menu nie zostaje pusty pas.
    // (PageFrame ma własne drobne odstępy, więc patrzymy tylko na duże.)
    final Iterable<SizedBox> spacers = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => (box.height ?? 0) >= 40);
    expect(spacers, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
