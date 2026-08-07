import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AppStore store, Widget child, {bool dark = true}) => MaterialApp(
      theme: buildTheme(const Color(0xFF24D6A3), dark),
      home: AppScope(store: store, child: child),
    );

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  store.plans.clear();
  return store;
}

WorkoutPlan _ownPlan({String id = 'own-1', String name = 'Mój zestaw'}) =>
    WorkoutPlan(
      id: id,
      name: name,
      note: '',
      origin: const PlanOrigin(creationMode: PlanCreationMode.manual),
      days: const [
        WorkoutDay(weekday: 1, title: 'A', items: [
          PlanItem(
              exerciseId: 'pushup',
              sets: 3,
              reps: 10,
              durationSec: 0,
              note: ''),
        ]),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ustawienie trybu kafelka', () {
    test('domyślnie ikony, zapis i odczyt trybu tła', () async {
      final store = await _freshStore();
      expect(normalizeTileVisual(store.settings.tileVisual), 'icon');

      await store.updateSettings(
          store.settings.copyWith(tileVisual: 'background'));
      final restored = AppStore();
      await restored.load();
      expect(normalizeTileVisual(restored.settings.tileVisual), 'background');
    });

    test('nieznana wartość spada do ikon', () {
      expect(normalizeTileVisual('cokolwiek'), 'icon');
      expect(normalizeTileVisual(''), 'icon');
      expect(normalizeTileVisual('background'), 'background');
    });
  });

  group('Okładki zestawów rdzennych', () {
    test('okładka zapisuje się per kafelek i przeżywa restart', () async {
      final store = await _freshStore();
      await store.setTileCover('program_core', '/tmp/core.jpg');
      await store.setTileCover('cardio_hiit', '/tmp/hiit.jpg');

      expect(store.coverForTile('program_core'), '/tmp/core.jpg');
      expect(store.coverForTile('cardio_hiit'), '/tmp/hiit.jpg');
      expect(store.coverForTile('warmup_chest'), isEmpty);

      final restored = AppStore();
      await restored.load();
      expect(restored.coverForTile('program_core'), '/tmp/core.jpg');
      expect(restored.coverForTile('cardio_hiit'), '/tmp/hiit.jpg');
    });

    test('okładka planu ma pierwszeństwo przed okładką kafelka', () async {
      final store = await _freshStore();
      await store.setTileCover('program_core', '/tmp/wlasna.jpg');

      expect(
        store.coverForTile('program_core', planCover: '/tmp/z-planu.jpg'),
        '/tmp/z-planu.jpg',
      );
      // Pusta okładka planu nie przykrywa własnej.
      expect(store.coverForTile('program_core', planCover: '  '),
          '/tmp/wlasna.jpg');
    });

    test('pusta ścieżka usuwa okładkę', () async {
      final store = await _freshStore();
      await store.setTileCover('program_core', '/tmp/core.jpg');
      await store.setTileCover('program_core', '');

      expect(store.coverForTile('program_core'), isEmpty);
      expect(store.tileCoverOverrides, isEmpty);

      final restored = AppStore();
      await restored.load();
      expect(restored.coverForTile('program_core'), isEmpty);
    });
  });

  group('Kolejność: rdzenne przed własnymi', () {
    testWidgets('ekran Trening pokazuje programy nad moimi zestawami',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_ownPlan());
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          _app(store, const Scaffold(body: PlanPage())));
      await tester.pumpAndSettle();

      final programs =
          tester.getTopLeft(find.text('Programy 30-dniowe')).dy;
      final own = tester.getTopLeft(find.text('Moje zestawy')).dy;
      expect(programs, lessThan(own),
          reason: 'sekcja rdzenna musi być nad własnymi zestawami');
      expect(tester.takeException(), isNull);
    });

    testWidgets('lista zestawów stawia programy wbudowane na górze',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_ownPlan(id: 'own-a', name: 'Aaa mój'));
      await store.addWorkoutPlan(const WorkoutPlan(
        id: 'sys-z',
        name: 'Zzz program',
        note: '',
        origin: PlanOrigin(creationMode: PlanCreationMode.systemProgram),
        days: [WorkoutDay(weekday: 1, title: 'D', items: [])],
      ));
      await tester.binding.setSurfaceSize(const Size(1700, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(store, const MyPlansPage()));
      await tester.pumpAndSettle();

      // Mimo sortowania po nazwie „Zzz program" (rdzenny) jest nad „Aaa mój".
      await tester.tap(find.byKey(const Key('my_plans_sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nazwa').last);
      await tester.pumpAndSettle();

      final core = tester.getTopLeft(find.text('Zzz program')).dy;
      final own = tester.getTopLeft(find.text('Aaa mój')).dy;
      expect(core, lessThan(own));
      expect(tester.takeException(), isNull);
    });
  });

  group('Renderowanie kafelków w obu trybach', () {
    testWidgets('tryb tła i tryb ikon rysują się bez wyjątków',
        (tester) async {
      final store = await _freshStore();
      await store.addWorkoutPlan(_ownPlan());
      await store.setTileCover('plan_own-1', 'assets/exercises/squat.png');
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final visual in ['icon', 'background']) {
        await store
            .updateSettings(store.settings.copyWith(tileVisual: visual));
        for (final dark in [true, false]) {
          await tester.pumpWidget(_app(
            store,
            const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: CreateOwnPlanCard(),
              ),
            ),
            dark: dark,
          ));
          await tester.pumpAndSettle();
          expect(find.text('Mój zestaw'), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'tryb=$visual ciemny=$dark');
        }
      }
    });

    testWidgets('kafelki rdzenne rysują się w trybie tła', (tester) async {
      final store = await _freshStore();
      await store
          .updateSettings(store.settings.copyWith(tileVisual: 'background'));
      await store.setTileCover(
          'program_${kWorkoutProgramCatalog.first.id}',
          'assets/exercises/squat.png');
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          _app(store, const Scaffold(body: PlanPage())));
      await tester.pumpAndSettle();

      expect(find.text(kWorkoutProgramCatalog.first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
