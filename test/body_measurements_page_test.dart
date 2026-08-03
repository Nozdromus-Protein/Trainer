import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'body measurements page saves locally and renders history without overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: BodyMeasurementsPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pomiar sylwetki'), findsOneWidget);
    // Cel wagowy i migawka sylwetki mieszkają teraz TU (przeniesione z Postępu).
    expect(find.byKey(const Key('body_snapshot_card')), findsOneWidget);
    expect(find.byKey(const Key('weight_goal_card')), findsOneWidget);
    // Cała funkcja analizy sylwetki na początku strony: trzy okna zdjęć
    // (przód/bok/tył) obok siebie + cel + przycisk analizy.
    expect(find.text('Zdjęcia progresu'), findsOneWidget);
    expect(find.byKey(const Key('progress_photo_slot_front')), findsOneWidget);
    expect(find.byKey(const Key('progress_photo_slot_side')), findsOneWidget);
    expect(find.byKey(const Key('progress_photo_slot_back')), findsOneWidget);
    expect(find.byKey(const Key('silhouette_goal_button')), findsOneWidget);
    expect(find.byKey(const Key('analyze_body_button')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('measurement_weight')), '98.4');
    await tester.enterText(find.byKey(const Key('measurement_waist')), '92');
    await tester.enterText(find.byKey(const Key('measurement_chest')), '112');
    await tester.enterText(find.byKey(const Key('measurement_arm')), '39.5');
    await tester.enterText(find.byKey(const Key('measurement_thigh')), '64');
    await tester.enterText(find.byKey(const Key('measurement_hips')), '105');
    await tester.enterText(find.byKey(const Key('measurement_calf')), '41');
    await tester.enterText(
        find.byKey(const Key('measurement_shoulders')), '128');
    await tester.enterText(
        find.byKey(const Key('measurement_note')), 'Pomiar rano');
    await tester.ensureVisible(find.byKey(const Key('save_body_measurement')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_body_measurement')));
    await tester.pumpAndSettle();

    expect(store.bodyMeasurements, hasLength(1));
    expect(store.bodyMeasurements.single.weightKg, 98.4);
    expect(store.bodyMeasurements.single.waistCm, 92);
    expect(store.bodyMeasurements.single.progressPhotoPaths, isEmpty);

    final restored = AppStore();
    await restored.load();
    expect(restored.bodyMeasurements.single.note, 'Pomiar rano');
    expect(restored.bodyMeasurements.single.shouldersCm, 128);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: restored,
          child: const Scaffold(body: BodyMeasurementsPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Waga'), findsOneWidget);
    expect(find.text('Pas'), findsOneWidget);
    expect(find.text('Ramię'), findsOneWidget);
    expect(find.text('Klatka'), findsOneWidget);
    expect(find.text('Udo'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Historia pomiarów'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Historia pomiarów'), findsOneWidget);
    expect(find.text('Pomiar rano'), findsOneWidget);
    expect(find.text('Bez zdjęć progresu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body analysis runs locally without photos and saves to history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    // Profil domyślny (masa+wzrost) wystarcza do lokalnego szacunku;
    // wybrany cel podpina się do wyniku analizy.
    await store
        .updateSettings(store.settings.copyWith(targetSilhouette: 'v_taper'));
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: BodyMeasurementsPage()),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('analyze_body_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('analyze_body_button')));
    await tester.pumpAndSettle();

    // Analiza (lokalna — brak zdjęć i kluczy AI) zapisała się i otworzyła szczegóły.
    expect(store.bodyAnalyses, hasLength(1));
    final analysis = store.bodyAnalyses.single;
    expect(analysis.source, 'local');
    expect(analysis.composition.hasData, isTrue);
    expect(analysis.targetSilhouetteId, 'v_taper');
    // Nowy model analizy: FFM z masy i BF, zakres niepewności, walidacja.
    expect(analysis.schemaVersion, 2);
    expect(analysis.lowReliability, isFalse);
    expect(analysis.bodyFatRangeMaxPercent, greaterThan(0));
    expect(find.text('Analiza sylwetki'), findsOneWidget);
    expect(find.text('Skład ciała (szacunek)'), findsOneWidget);
    // Strona jest dłuższa (sekcje 1–6) — sekcja celu wymaga przewinięcia.
    await tester.scrollUntilVisible(
      find.textContaining('Droga do celu'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Droga do celu'), findsOneWidget);

    // Wynik przetrwał restart (persystencja w SharedPreferences).
    final restored = AppStore();
    await restored.load();
    expect(restored.bodyAnalyses, hasLength(1));
    expect(restored.bodyAnalyses.single.composition.bodyFatPercent,
        analysis.composition.bodyFatPercent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more page exposes body measurements screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: const MaterialApp(
          home: Scaffold(
            body: MorePage(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Pomiar sylwetki'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pomiar sylwetki'));
    await tester.pumpAndSettle();

    expect(find.text('Dodaj pomiar'), findsOneWidget);
    expect(find.text('Historia pomiarów'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
