import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GĘSTOŚĆ INTERFEJSU + KREATOR PROFILU.
///
/// Ustawienie „Gęstość UI" sterowało wcześniej tylko [VisualDensity]
/// i paddingiem przycisków — kafelki i odstępy zostawały identyczne. Teraz
/// jedna skala przechodzi przez odstępy, paddingi i rozmiary, ale obszary
/// dotykowe mają własną podłogę 44 px.
Future<AppStore> _store({String density = 'normal'}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  await store.updateSettings(store.settings.copyWith(uiDensity: density));
  return store;
}

/// Pomiar wysokości paska ikon aktywności przy danej gęstości.
Future<double> _activityBarHeight(WidgetTester tester, String density) async {
  final store = await _store(density: density);
  await tester.pumpWidget(
    AppScope(
      store: store,
      child: MaterialApp(
        theme:
            buildTheme(const Color(0xFF24D6A3), true, settings: store.settings),
        home: const Scaffold(body: SafeArea(child: ActivityIconBar())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(ActivityIconBar)).height;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gęstość interfejsu działa realnie', () {
    test('skala odstępów zależy od trybu', () {
      expect(uiDensityScaleFor('compact'), lessThan(1.0));
      expect(uiDensityScaleFor('normal'), 1.0);
      expect(uiDensityScaleFor('large'), greaterThan(1.0));
      // Nieznana / stara wartość nie może wyłączyć skalowania po cichu.
      expect(uiDensityScaleFor('cokolwiek'), 1.0);
      expect(normalizeUiDensity('COMPACT'), 'compact');
      expect(normalizeUiDensity(''), 'normal');
    });

    testWidgets('tryb kompaktowy realnie zmniejsza pasek ikon aktywności',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final compact = await _activityBarHeight(tester, 'compact');
      final normal = await _activityBarHeight(tester, 'normal');
      final large = await _activityBarHeight(tester, 'large');

      expect(compact, lessThan(normal));
      expect(large, greaterThan(normal));
      expect(tester.takeException(), isNull);
    });

    testWidgets('obszar dotykowy nie schodzi poniżej bezpiecznego minimum',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(density: 'compact');

      await tester.pumpWidget(
        AppScope(
          store: store,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF24D6A3), true,
                settings: store.settings),
            home: const Scaffold(body: SafeArea(child: ActivityIconBar())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Każde koło ikony musi zostać klikalne mimo trybu kompaktowego.
      final circles = find.descendant(
        of: find.byType(ActivityIconBar),
        matching: find.byType(InkWell),
      );
      expect(circles, findsWidgets);
      for (var i = 0; i < tester.widgetList(circles).length; i++) {
        final size = tester.getSize(circles.at(i));
        expect(size.height, greaterThanOrEqualTo(44.0));
        expect(size.width, greaterThanOrEqualTo(44.0));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tryb kompaktowy nie powoduje przepełnień na małym ekranie',
        (tester) async {
      // Mały telefon + tryb kompaktowy — najbardziej ściśnięty przypadek.
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(density: 'compact');

      await tester.pumpWidget(
        AppScope(
          store: store,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF24D6A3), true,
                settings: store.settings),
            home: const Scaffold(body: SafeArea(child: ActivityIconBar())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('gęstość zapisuje się i wraca po restarcie', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateSettings(store.settings.copyWith(uiDensity: 'compact'));

      final restored = AppStore();
      await restored.load();
      expect(restored.settings.uiDensity, 'compact');
    });
  });

  group('Kreator profilu i migracja', () {
    test('świeża instalacja startuje z nieukończonym profilem', () {
      expect(AppSettings.defaults().onboardingCompleted, isFalse);
    });

    test('istniejący profil (zapis bez pola) NIE dostaje kreatora', () {
      // Zapis sprzed tego etapu nie ma klucza `onboardingCompleted`.
      final legacy = AppSettings.fromJson(<String, dynamic>{
        'bodyWeightKg': 90.0,
        'level': 'Średniozaawansowany',
      });
      expect(legacy.onboardingCompleted, isTrue,
          reason: 'kreator nie może zaskoczyć kogoś, kto już używa aplikacji');
    });

    test('pola profilu przeżywają zapis i odczyt', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateSettings(store.settings.copyWith(
        displayName: 'Dawid',
        aboutMe: 'Wracam po przerwie',
        avatarIconKey: 'bolt',
        favoriteActivities: const ['Siłownia', 'Bieganie'],
        preferredIntensity: 'high',
        preferredRestSeconds: 120,
        preferredWorkoutMinutes: 75,
        experienceMonths: 30,
        profileStatsPrivate: true,
        onboardingCompleted: true,
        trainingStartDate: DateTime(2024, 3, 1),
      ));

      final restored = AppStore();
      await restored.load();
      final s = restored.settings;
      expect(s.displayName, 'Dawid');
      expect(s.aboutMe, 'Wracam po przerwie');
      expect(s.avatarIconKey, 'bolt');
      expect(s.favoriteActivities, containsAll(['Siłownia', 'Bieganie']));
      expect(s.preferredIntensity, 'high');
      expect(s.preferredRestSeconds, 120);
      expect(s.preferredWorkoutMinutes, 75);
      expect(s.experienceMonths, 30);
      expect(s.profileStatsPrivate, isTrue);
      expect(s.trainingStartDate?.year, 2024);
      // Postępy i ustawienia sprzed zmiany zostają nietknięte.
      expect(s.trainingWeekdays, isNotEmpty);
    });

    testWidgets('kreator pokazuje pasek postępu i pozwala dokończyć później',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store
          .updateSettings(store.settings.copyWith(onboardingCompleted: false));

      await tester.pumpWidget(
        AppScope(
          store: store,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF24D6A3), true),
            home: const ProfileSetupWizardPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wizard_progress')), findsOneWidget);
      expect(find.text('Dane podstawowe'), findsOneWidget);
      expect(find.text('Etap 1 z 8'), findsOneWidget);

      // Wpisane dane zapisują się przy przejściu dalej.
      await tester.enterText(find.byKey(const Key('wizard_name')), 'Dawid');
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();
      expect(store.settings.displayName, 'Dawid');
      expect(find.text('Etap 2 z 8'), findsOneWidget);

      // Cofanie działa i nie gubi danych.
      await tester.tap(find.byKey(const Key('wizard_back')));
      await tester.pumpAndSettle();
      expect(find.text('Etap 1 z 8'), findsOneWidget);

      // „Później" domyka kreator, ale zostawia to, co już wpisano.
      await tester.tap(find.byKey(const Key('wizard_finish_later')));
      await tester.pumpAndSettle();
      expect(store.settings.onboardingCompleted, isTrue);
      expect(store.settings.displayName, 'Dawid');
      expect(tester.takeException(), isNull);
    });

    testWidgets('karta profilu pokazuje awatar i statystyki', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateSettings(store.settings
          .copyWith(displayName: 'Dawid', avatarIconKey: 'trophy'));

      await tester.pumpWidget(
        AppScope(
          store: store,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF24D6A3), false),
            home: const Scaffold(body: UserProfileCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user_profile_card')), findsOneWidget);
      expect(find.byKey(const Key('trainer_profile_avatar')), findsOneWidget);
      expect(find.text('Dawid'), findsOneWidget);
      expect(find.byKey(const Key('profile_stats_private')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
