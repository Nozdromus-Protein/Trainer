import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

// Testy rozdzielenia czasów aktywnego treningu: aktywny / pauza / tło / brutto,
// oraz podziału na części po długiej przerwie. Czas w tle NIE może być liczony
// jako aktywny wysiłek.
void main() {
  final t0 = DateTime(2026, 7, 14, 18, 0, 0);
  ActiveWorkoutSession base() => ActiveWorkoutSession(
        id: 'w1',
        planId: 'p',
        planName: 'Plan',
        weekday: 1,
        dayTitle: 'Dzień',
        startedAt: t0,
        activeSegmentStartedAt: t0,
        currentExerciseIndex: 0,
        exercises: const [],
      );

  test('aktywny czas rośnie, brutto = od startu', () {
    final s = base();
    final now = t0.add(const Duration(minutes: 10));
    expect(s.netActiveSeconds(now), 600);
    expect(s.grossSeconds(now), 600);
    expect(s.totalPauseSeconds(now), 0);
  });

  test('pauza zamraża aktywny czas, liczy pauzę', () {
    final paused = base().pausedNow(now: t0.add(const Duration(minutes: 5)));
    expect(paused.isPaused, isTrue);
    expect(paused.accumulatedActiveSeconds, 300);
    // 3 min później: aktywny nadal 300, pauza 180, brutto 480.
    final now = t0.add(const Duration(minutes: 8));
    expect(paused.netActiveSeconds(now), 300);
    expect(paused.totalPauseSeconds(now), 180);
    expect(paused.grossSeconds(now), 480);
  });

  test('wznowienie dolicza pauzę i wznawia aktywny odcinek', () {
    var s = base().pausedNow(now: t0.add(const Duration(minutes: 5)));
    s = s.resumedNow(now: t0.add(const Duration(minutes: 8)));
    expect(s.isPaused, isFalse);
    expect(s.accumulatedPauseSeconds, 180);
    expect(s.partCount, 1); // krótka przerwa — bez podziału
    // Po kolejnych 2 min aktywnego: 300 (przed) + 120 = 420.
    final now = t0.add(const Duration(minutes: 10));
    expect(s.netActiveSeconds(now), 420);
    expect(s.totalPauseSeconds(now), 180);
  });

  test('długa przerwa zwiększa liczbę części treningu', () {
    var s = base().pausedNow(now: t0.add(const Duration(minutes: 28)));
    // 47 minut przerwy → długa → nowa część.
    s = s.resumedNow(now: t0.add(const Duration(minutes: 75)));
    expect(s.partCount, 2);
    expect(s.accumulatedPauseSeconds, 47 * 60);
    expect(s.accumulatedActiveSeconds, 28 * 60);
  });

  test('zamrożenie po restarcie NIE dolicza nieznanej luki do aktywnego', () {
    final s = base();
    // Aplikacja żyła 5 min, potem zniknęła; restart „teraz" = t0+3h.
    final frozen = s.frozenOnRestart(now: t0.add(const Duration(hours: 3)));
    expect(frozen.isPaused, isTrue);
    expect(frozen.pausedByBackground, isTrue);
    // Aktywny czas NIE urósł o 3h — luka nie jest wysiłkiem.
    expect(frozen.accumulatedActiveSeconds, 0);
    expect(frozen.netActiveSeconds(t0.add(const Duration(hours: 3))), 0);
  });

  test('tło: pauza w tle, potem wznowienie', () {
    var s = base()
        .pausedNow(byBackground: true, now: t0.add(const Duration(minutes: 4)));
    expect(s.pausedByBackground, isTrue);
    s = s.resumedNow(now: t0.add(const Duration(minutes: 6)));
    expect(s.pausedByBackground, isFalse);
    expect(s.accumulatedActiveSeconds, 240);
    expect(s.accumulatedPauseSeconds, 120);
  });

  test('round-trip JSON zachowuje czasy i pauzę', () {
    final s = base()
        .pausedNow(byBackground: true, now: t0.add(const Duration(minutes: 5)));
    final restored = ActiveWorkoutSession.fromJson(s.toJson());
    expect(restored.isPaused, isTrue);
    expect(restored.pausedByBackground, isTrue);
    expect(restored.accumulatedActiveSeconds, 300);
    expect(restored.pauseStartedAt, isNotNull);
  });

  test('migracja: starszy zapis bez pól czasu — aktywny liczy od startedAt',
      () {
    final legacy = {
      'id': 'w1',
      'planId': 'p',
      'planName': 'Plan',
      'weekday': 1,
      'dayTitle': 'Dzień',
      'startedAt': t0.toIso8601String(),
      'currentExerciseIndex': 0,
      'exercises': <dynamic>[],
    };
    final s = ActiveWorkoutSession.fromJson(legacy);
    expect(s.isPaused, isFalse);
    expect(s.partCount, 1);
    expect(s.netActiveSeconds(t0.add(const Duration(minutes: 5))), 300);
  });
}
