import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Health Connect settings page renders diagnostics without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    await store.upsertHealthConnectSnapshot(
      TrainerHealthConnectSnapshot(
        id: 'health_connect_2026_6_24',
        date: DateTime(2026, 6, 24),
        checkedAt: DateTime(2026, 6, 24, 12, 30),
        sdkStatus: 'sdkAvailable',
        isAvailable: true,
        permissionsGranted: false,
        grantedPermissions: const ['Kroki', 'Dystans', 'Aktywne kcal'],
        missingPermissions: const ['Tętno', 'Sen'],
        steps: 8420,
        distanceKm: 5.7,
        activeKcal: 320,
        workoutSessions: 1,
        workoutMinutes: 46,
        averageHeartRate: 122,
        heartRateSamples: 18,
        sleepMinutes: 420,
        availableData: const ['Kroki', 'Dystans', 'Aktywne kcal', 'Sesje treningowe'],
        missingData: const ['Sen'],
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF24D6A3), true),
        home: AppScope(
          store: store,
          child: const Scaffold(body: HealthConnectSettingsPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Health Connect'), findsWidgets);
    expect(find.text('Sprawdź dostępność'), findsOneWidget);
    expect(find.text('Poproś o uprawnienia'), findsOneWidget);
    expect(find.text('Odczytaj dzisiaj'), findsOneWidget);
    expect(find.text('Dane dzienne'), findsOneWidget);
    expect(find.text('Diagnostyka'), findsOneWidget);
    expect(find.text('Lokalny zapis odczytów'), findsOneWidget);
    expect(find.text('8420'), findsOneWidget);
    expect(find.text('5.70 km'), findsWidgets);
    expect(find.text('320'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
