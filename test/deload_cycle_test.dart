import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/deload_cycle.dart';
import 'package:licznik_treningu/features/trainer/domain/workout_plan.dart';

void main() {
  final anchor = DateTime(2026, 1, 1);
  DeloadCycle cycle({int t = 35, int d = 7}) =>
      DeloadCycle(enabled: true, anchor: anchor, trainingDays: t, deloadDays: d);
  DateTime plus(int days) => anchor.add(Duration(days: days));

  group('Faza cyklu deloadu', () {
    test('wyłączony albo bez kotwicy → brak fazy', () {
      expect(deloadStatusForDate(const DeloadCycle(enabled: false), plus(40)).phase,
          DeloadPhase.none);
      expect(
          deloadStatusForDate(const DeloadCycle(enabled: true, anchor: null), plus(40))
              .phase,
          DeloadPhase.none);
    });

    test('dzień kotwicy to trening z pełnym odliczaniem do deloadu', () {
      final s = deloadStatusForDate(cycle(), anchor);
      expect(s.phase, DeloadPhase.training);
      expect(s.daysUntilDeload, 35);
      expect(s.windowStart, plus(35));
      expect(s.windowEnd, plus(41));
    });

    test('ostatni dzień bloku treningowego → 1 dzień do deloadu', () {
      final s = deloadStatusForDate(cycle(), plus(34));
      expect(s.phase, DeloadPhase.training);
      expect(s.daysUntilDeload, 1);
    });

    test('pierwszy i ostatni dzień okna deloadu', () {
      final first = deloadStatusForDate(cycle(), plus(35));
      expect(first.phase, DeloadPhase.deload);
      expect(first.deloadDayNumber, 1);
      expect(first.deloadTotalDays, 7);

      final last = deloadStatusForDate(cycle(), plus(41));
      expect(last.phase, DeloadPhase.deload);
      expect(last.deloadDayNumber, 7);
    });

    test('cykl jest periodyczny (drugi blok i drugi deload)', () {
      // Dzień po deloadzie → znów trening, pełne odliczanie.
      final backToTraining = deloadStatusForDate(cycle(), plus(42));
      expect(backToTraining.phase, DeloadPhase.training);
      expect(backToTraining.daysUntilDeload, 35);

      // Drugie okno deloadu zaczyna się 42 dni po pierwszym.
      final secondDeload = deloadStatusForDate(cycle(), plus(35 + 42));
      expect(secondDeload.phase, DeloadPhase.deload);
      expect(secondDeload.deloadDayNumber, 1);
    });

    test('isDeloadDay zaznacza dokładnie dni okna', () {
      final c = cycle();
      for (var i = 0; i < 42; i++) {
        final expected = i >= 35 && i <= 41;
        expect(isDeloadDay(c, plus(i)), expected, reason: 'dzień +$i');
      }
    });
  });

  group('Intensywność bloku', () {
    test('mocno zaraz po deloadzie, łagodniej ku końcowi, nisko w deloadzie', () {
      final c = cycle();
      final first = deloadStatusForDate(c, anchor).intensityFactor;
      final mid = deloadStatusForDate(c, plus(17)).intensityFactor;
      final last = deloadStatusForDate(c, plus(34)).intensityFactor;
      expect(first, closeTo(1.0, 0.001));
      expect(last, lessThan(first));
      expect(last, greaterThanOrEqualTo(0.84)); // „nie za mało"
      expect(mid, lessThan(first));
      expect(mid, greaterThan(last));

      // W deloadzie wyraźnie niżej.
      expect(deloadStatusForDate(c, plus(37)).intensityFactor, lessThan(0.7));

      // Po deloadzie znów mocno.
      expect(deloadStatusForDate(c, plus(42)).intensityFactor, closeTo(1.0, 0.001));
    });
  });

  group('Adaptacyjne przesunięcie', () {
    test('reanchorDeloadStart sprawia, że deload rusza w wybranym dniu', () {
      final pulled = reanchorDeloadStart(cycle(), plus(20));
      final s = deloadStatusForDate(pulled, plus(20));
      expect(s.phase, DeloadPhase.deload);
      expect(s.deloadDayNumber, 1);
      // Dzień wcześniej to jeszcze trening.
      expect(deloadStatusForDate(pulled, plus(19)).phase, DeloadPhase.training);
    });
  });

  group('Transformacja pozycji pod deload', () {
    test('seria na powtórzenia: mniej serii, dłuższa przerwa, adnotacja', () {
      const item = PlanItem(
          exerciseId: 'db_bench_press',
          sets: 4,
          reps: 10,
          durationSec: 0,
          note: 'Seria główna',
          restSeconds: 90);
      final d = deloadPlanItem(item);
      expect(d.sets, lessThan(item.sets));
      expect(d.sets, greaterThanOrEqualTo(1));
      expect(d.reps, lessThanOrEqualTo(item.reps));
      expect(d.restSeconds, greaterThan(item.restSeconds));
      expect(d.note.toLowerCase(), contains('deload'));
    });

    test('pozycja czasowa: mniej serii, krótszy czas', () {
      const item = PlanItem(
          exerciseId: 'plank',
          sets: 3,
          reps: 0,
          durationSec: 40,
          note: 'Core',
          restSeconds: 20);
      final d = deloadPlanItem(item);
      expect(d.sets, lessThan(item.sets));
      expect(d.durationSec, lessThanOrEqualTo(item.durationSec));
      expect(d.reps, 0);
      expect(d.note.toLowerCase(), contains('deload'));
    });

    test('deloadWorkoutDay łagodzi wszystkie pozycje, zachowuje tytuł', () {
      const day = WorkoutDay(
        weekday: 1,
        title: 'Dzień 1 · Siła A — ciężka',
        kind: WorkoutDayKind.strength,
        items: [
          PlanItem(
              exerciseId: 'db_bench_press',
              sets: 4,
              reps: 6,
              durationSec: 0,
              note: 'Seria główna',
              restSeconds: 150),
        ],
      );
      final d = deloadWorkoutDay(day);
      expect(d.title, day.title);
      expect(d.kind, WorkoutDayKind.strength);
      expect(d.items.single.sets, lessThan(4));
      expect(d.items.single.note.toLowerCase(), contains('deload'));
    });
  });

  group('Ile dni po deloadzie', () {
    test('liczy dni od końca poprzedniego okna', () {
      final c = cycle();
      // Pierwszy dzień po deloadzie (okno 35..41).
      final first = deloadStatusForDate(c, plus(42));
      expect(first.phase, DeloadPhase.training);
      expect(first.daysAfterDeload, 1);
      expect(first.previousWindowEnd, plus(41));

      expect(deloadStatusForDate(c, plus(45)).daysAfterDeload, 4);

      // Przed pierwszym deloadem nie ma „po deloadzie".
      final before = deloadStatusForDate(c, plus(10));
      expect(before.daysAfterDeload, 0);
      expect(before.previousWindowEnd, isNull);
    });
  });

  group('Podgląd intensywności', () {
    const item = PlanItem(
        exerciseId: 'db_bench_press',
        sets: 4,
        reps: 8,
        durationSec: 0,
        note: 'Seria główna',
        restSeconds: 120);

    test('etykiety intensywności', () {
      expect(intensityLabel(1.0), 'Bardzo mocna');
      expect(intensityLabel(0.94), 'Mocna');
      expect(intensityLabel(0.86), 'Umiarkowana');
      expect(intensityLabel(0.55), 'Lekka (deload)');
    });

    test('blok treningowy: objętość zostaje, ciężar opisany procentem', () {
      final full = previewPlanItemAtIntensity(item, 1.0);
      expect(full.sets, item.sets);
      expect(full.reps, item.reps);
      expect(full.note, contains('100%'));

      final easier = previewPlanItemAtIntensity(item, 0.85);
      expect(easier.sets, item.sets);
      expect(easier.note, contains('85%'));
    });

    test('deload: realne odciążenie zamiast procentu', () {
      final light = previewPlanItemAtIntensity(item, 0.55);
      expect(light.sets, lessThan(item.sets));
      expect(light.note.toLowerCase(), contains('deload'));
    });

    test('previewDayAtIntensity przelicza wszystkie pozycje', () {
      const day = WorkoutDay(
          weekday: 1, title: 'Dzień 1', items: [item], kind: WorkoutDayKind.strength);
      final preview = previewDayAtIntensity(day, 0.9);
      expect(preview.items.single.note, contains('90%'));
      expect(preview.title, day.title);
    });
  });

  group('Serializacja', () {
    test('round-trip JSON zachowuje konfigurację', () {
      final c = DeloadCycle(
          enabled: true,
          anchor: DateTime(2026, 7, 21),
          trainingDays: 28,
          deloadDays: 5,
          adaptive: false);
      final back = DeloadCycle.fromJson(c.toJson());
      expect(back.enabled, true);
      expect(back.anchor, DateTime(2026, 7, 21));
      expect(back.trainingDays, 28);
      expect(back.deloadDays, 5);
      expect(back.adaptive, false);
    });

    test('domyślne wartości przy pustym JSON', () {
      final c = DeloadCycle.fromJson(const {});
      expect(c.enabled, true);
      expect(c.anchor, isNull);
      expect(c.trainingDays, 35);
      expect(c.deloadDays, 7);
      expect(c.isConfigured, isFalse);
    });
  });
}
