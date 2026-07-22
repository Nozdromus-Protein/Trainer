import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutLog _todayLog(String id, String sessionId) {
  final now = DateTime.now();
  return WorkoutLog(
    id: id,
    exerciseId: 'pushup',
    date: DateTime(now.year, now.month, now.day, 10),
    sets: 3,
    reps: 10,
    weightKg: 40,
    durationSec: 900,
    rpe: 7,
    calories: 100,
    note: '',
    aiConfidence: 0,
    sessionId: sessionId,
    sessionName: 'Trening $sessionId',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('badge liczy nowości per ikona i znika po odhaczeniu', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    final now = DateTime.now();

    // Bez danych — żadna ikona nie świeci.
    for (final key in const ['run', 'walk', 'training', 'sleep', 'heart']) {
      expect(store.activityIconBadgeCount(key), 0, reason: 'ikona $key bez danych');
    }

    // Trening dziś → plakietka na ikonie Trening.
    store.logs.add(_todayLog('log-1', 'session-1'));
    expect(store.activityIconBadgeCount('training'), 1);

    // Wejście w ikonę odhacza nowości (jak przeczytanie wiadomości).
    await store.markActivityIconSeen('training');
    expect(store.activityIconBadgeCount('training'), 0);

    // Kolejna sesja tego dnia → plakietka wraca.
    store.logs.add(_todayLog('log-2', 'session-2'));
    expect(store.activityIconBadgeCount('training'), 1);

    // Bieg dziś → plakietka na ikonie Bieg.
    store.activityEntries.add(TrainerActivityEntry.fromJson({
      'id': 'run-1',
      'date': DateTime(now.year, now.month, now.day, 8).toIso8601String(),
      'type': 'run',
      'durationMin': 30,
      'estimatedKcal': 300,
    }));
    expect(store.activityIconBadgeCount('run'), 1);
    await store.markActivityIconSeen('run');
    expect(store.activityIconBadgeCount('run'), 0);

    // Snapshot Health Connect: kroki (2 progi), sen i tętno.
    store.healthConnectSnapshots.add(TrainerHealthConnectSnapshot.fromJson({
      'id': 'snap-1',
      'date': DateTime(now.year, now.month, now.day).toIso8601String(),
      'checkedAt': now.toIso8601String(),
      'steps': 11500,
      'sleepMinutes': 420,
      'averageHeartRate': 62,
    }));
    expect(store.activityIconBadgeCount('walk'), 2); // progi 5000 i 10000
    expect(store.activityIconBadgeCount('sleep'), 1);
    expect(store.activityIconBadgeCount('heart'), 1);

    // Odhaczenie przetrwa restart (prefs).
    await store.markActivityIconSeen('sleep');
    final restored = AppStore();
    await restored.load();
    restored.healthConnectSnapshots.addAll(store.healthConnectSnapshots);
    expect(restored.activityIconBadgeCount('sleep'), 0);
  });

  testWidgets('pasek ikon Dzisiaj pokazuje plakietkę i czyści ją po wejściu', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();
    store.logs.add(_todayLog('log-1', 'session-1'));

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF24D6A3), true),
          home: const Scaffold(body: ActivityIconBar()),
        ),
      ),
    );
    await tester.pump();

    // Plakietka „1" na ikonie Trening.
    final badge = tester.widget<Badge>(find.byKey(const Key('activity_icon_badge_training')));
    expect(badge.isLabelVisible, isTrue);
    expect(find.text('1'), findsOneWidget);

    // Wejście w ikonę odhacza nowości.
    await tester.tap(find.byIcon(Icons.fitness_center_rounded));
    await tester.pumpAndSettle();
    expect(store.activityIconBadgeCount('training'), 0);
    expect(tester.takeException(), isNull);
  });
}
