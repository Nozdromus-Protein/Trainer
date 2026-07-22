import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/equipment_program_filter.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

// Testy filtra sprzętowego programów 30-dniowych: żadne ćwiczenie wymagające
// niedostępnego sprzętu nie może przejść bez zamiennika, a postępy programu
// nie mogą zostać naruszone.
void main() {
  Exercise resolve(String id) => ExerciseRepo.byId(id);

  const noLimits = LimitationProfile();

  WorkoutPlan buildFor(String programId) =>
      buildWorkoutProgram(programId, resolveExercise: resolve);

  EquipmentFilteredPlan filterFor(String programId, EquipmentProfile profile,
          {LimitationProfile limits = noLimits}) =>
      applyEquipmentToPlan(buildFor(programId), profile, limits, resolve);

  /// Zestaw wszystkich programów do przebiegu przekrojowego.
  const programIds = [
    'program_core',
    'program_chest',
    'program_arms',
    'program_shoulders',
    'program_back',
    'program_forearms',
    'program_legs',
  ];

  group('EquipmentType — nowe typy', () {
    test('rozpoznaje rack/stojaki i step/podwyższenie', () {
      expect(EquipmentType.fromText('stojaki'), contains(EquipmentType.rack));
      expect(
          EquipmentType.fromText('power rack'), contains(EquipmentType.rack));
      expect(EquipmentType.fromText('step'), contains(EquipmentType.step));
      expect(
          EquipmentType.fromText('podwyższenie'), contains(EquipmentType.step));
    });

    test('„klatka piersiowa" NIE jest mylona z rackiem', () {
      expect(EquipmentType.fromText('klatka piersiowa'),
          isNot(contains(EquipmentType.rack)));
    });
  });

  group('EquipmentProfile', () {
    test('tryby dają oczekiwane zestawy sprzętu', () {
      expect(
        const EquipmentProfile(mode: EquipmentMode.bodyweight).resolveOwned(),
        {EquipmentType.bodyweight, EquipmentType.mat},
      );
      final dumbbell = const EquipmentProfile(mode: EquipmentMode.dumbbellBench)
          .resolveOwned();
      expect(dumbbell, contains(EquipmentType.dumbbell));
      expect(dumbbell, contains(EquipmentType.bench));
      expect(dumbbell, isNot(contains(EquipmentType.barbell)));

      final barbell =
          const EquipmentProfile(mode: EquipmentMode.barbellDumbbellBench)
              .resolveOwned();
      expect(barbell, contains(EquipmentType.barbell));
      expect(barbell, contains(EquipmentType.dumbbell));
      expect(barbell, contains(EquipmentType.bench));
      // rack NIE jest automatyczny w tym trybie.
      expect(barbell, isNot(contains(EquipmentType.rack)));

      expect(
        const EquipmentProfile(mode: EquipmentMode.fullGym).resolveOwned(),
        containsAll(<EquipmentType>[
          EquipmentType.machine,
          EquipmentType.cable,
          EquipmentType.rack,
          EquipmentType.pullUpBar,
        ]),
      );
    });

    test('migracja ze starego tekstu — hantle/drążek', () {
      final profile =
          EquipmentProfile.fromLegacyText('masa ciała, hantle, drążek, mata');
      final owned = profile.resolveOwned();
      expect(owned, contains(EquipmentType.dumbbell));
      expect(owned, contains(EquipmentType.pullUpBar));
      expect(owned, isNot(contains(EquipmentType.barbell)));
      expect(owned, isNot(contains(EquipmentType.machine)));
    });

    test('migracja — „siłownia" => pełna siłownia', () {
      final profile = EquipmentProfile.fromLegacyText('mam dostęp do siłowni');
      expect(profile.mode, EquipmentMode.fullGym);
    });

    test('resolve preferuje nowe pola nad starym tekstem', () {
      final profile = EquipmentProfile.resolve(
        modeKey: EquipmentMode.bodyweight.key,
        legacyText: 'sztanga, hantle, wyciąg',
      );
      expect(profile.mode, EquipmentMode.bodyweight);
      expect(profile.resolveOwned(), isNot(contains(EquipmentType.barbell)));
    });
  });

  group('Filtr — żadnego niedostępnego sprzętu', () {
    for (final mode in [
      EquipmentMode.bodyweight,
      EquipmentMode.dumbbellBench,
      EquipmentMode.barbellDumbbellBench,
      EquipmentMode.fullGym,
    ]) {
      test('tryb ${mode.label}: każdy program przechodzi walidację', () {
        final profile = EquipmentProfile(mode: mode);
        for (final id in programIds) {
          final filtered = filterFor(id, profile);
          final issues =
              validatePlanEquipment(filtered.plan, profile, noLimits, resolve);
          expect(issues, isEmpty,
              reason: '$id / ${mode.label}: '
                  '${issues.map((i) => '${i.exerciseId}(${i.reason})').join(', ')}');
        }
      });
    }

    test('masa ciała: brak sztangi, hantli, ławki, drążka, wyciągu', () {
      const profile = EquipmentProfile(mode: EquipmentMode.bodyweight);
      for (final id in programIds) {
        final filtered = filterFor(id, profile);
        expect(
          filtered.report.usedEquipment,
          isNot(anyElement(isIn(<EquipmentType>[
            EquipmentType.barbell,
            EquipmentType.dumbbell,
            EquipmentType.bench,
            EquipmentType.pullUpBar,
            EquipmentType.cable,
            EquipmentType.machine,
            EquipmentType.rack,
          ]))),
          reason: '$id używa niedozwolonego sprzętu w trybie masy ciała',
        );
      }
    });

    test('sztanga+hantle+ławka: bez racka, maszyn, wyciągów, drążka', () {
      const profile =
          EquipmentProfile(mode: EquipmentMode.barbellDumbbellBench);
      for (final id in programIds) {
        final filtered = filterFor(id, profile);
        expect(
          filtered.report.usedEquipment,
          isNot(anyElement(isIn(<EquipmentType>[
            EquipmentType.rack,
            EquipmentType.machine,
            EquipmentType.cable,
            EquipmentType.pullUpBar,
          ]))),
          reason: '$id używa sprzętu spoza trybu (rack/maszyna/wyciąg/drążek)',
        );
      }
    });
  });

  group('Filtr — konkretne braki sprzętu', () {
    test('bez drążka: podciąganie/dipy zamienione', () {
      // Własny zestaw: sztanga+hantle+ławka+rack, ale BEZ drążka.
      const profile =
          EquipmentProfile(mode: EquipmentMode.custom, customOwned: {
        EquipmentType.dumbbell,
        EquipmentType.barbell,
        EquipmentType.bench,
        EquipmentType.rack,
      });
      final filtered = filterFor('program_back', profile);
      final ids =
          filtered.plan.days.expand((d) => d.items).map((i) => i.exerciseId);
      expect(ids, isNot(contains('pullup')));
      expect(ids, isNot(contains('chin_up')));
      expect(ids, isNot(contains('dead_hang')));
      expect(validatePlanEquipment(filtered.plan, profile, noLimits, resolve),
          isEmpty);
    });

    test('bez wyciągu i maszyn: lat pulldown zamieniony', () {
      const profile = EquipmentProfile(mode: EquipmentMode.dumbbellBench);
      final filtered = filterFor('program_back', profile);
      final ids =
          filtered.plan.days.expand((d) => d.items).map((i) => i.exerciseId);
      expect(ids, isNot(contains('lat_pulldown')));
      expect(ids, isNot(contains('face_pull')));
    });

    test('bez racka: przysiad ze sztangą zamieniony', () {
      // Hantle + ławka + sztanga, ale bez stojaków.
      const profile =
          EquipmentProfile(mode: EquipmentMode.barbellDumbbellBench);
      final filtered = filterFor('program_legs', profile);
      final ids = filtered.plan.days
          .expand((d) => d.items)
          .map((i) => i.exerciseId)
          .toSet();
      expect(ids, isNot(contains('squat')));
      expect(ids, isNot(contains('front_squat')));
      // deadlift (bez racka) może zostać.
    });
  });

  group('Zamienniki — trafność', () {
    test('zamiennik istnieje jako realne ćwiczenie i jest dostępny', () {
      const profile = EquipmentProfile(mode: EquipmentMode.bodyweight);
      final validIds = ExerciseRepo.combined().map((e) => e.id).toSet();
      for (final id in programIds) {
        final filtered = filterFor(id, profile);
        for (final day in filtered.plan.days) {
          for (final item in day.items) {
            expect(validIds.contains(item.exerciseId), isTrue,
                reason: '$id: nieznane ćwiczenie ${item.exerciseId}');
          }
        }
      }
    });

    test('podmieniona pozycja ma notatkę archiwalną o oryginale', () {
      const profile = EquipmentProfile(mode: EquipmentMode.bodyweight);
      final filtered = filterFor('program_chest', profile);
      final swapped = filtered.plan.days
          .expand((d) => d.items)
          .where((i) => i.note.contains('zamiennik za:'));
      expect(swapped, isNotEmpty);
      expect(filtered.report.substitutedCount, greaterThan(0));
    });
  });

  group('Ograniczenia', () {
    test('bez podskoków: brak burpee/pajaców/skoków', () {
      const profile = EquipmentProfile(mode: EquipmentMode.fullGym);
      const limits = LimitationProfile(flags: {TrainingLimitation.noJumps});
      final filtered = filterFor('program_core', profile, limits: limits);
      final ids =
          filtered.plan.days.expand((d) => d.items).map((i) => i.exerciseId);
      expect(ids, isNot(contains('burpee')));
      expect(ids, isNot(contains('jumping_jack')));
      expect(ids, isNot(contains('high_knees')));
      expect(validatePlanEquipment(filtered.plan, profile, limits, resolve),
          isEmpty);
    });

    test('ochrona kolan: brak przysiadów/wykroków ciężkich', () {
      const profile = EquipmentProfile(mode: EquipmentMode.fullGym);
      const limits = LimitationProfile(flags: {TrainingLimitation.knees});
      final filtered = filterFor('program_legs', profile, limits: limits);
      final issues =
          validatePlanEquipment(filtered.plan, profile, limits, resolve);
      expect(issues, isEmpty);
    });
  });

  group('Ochrona postępu', () {
    test('fromDayIndex zostawia wcześniejsze dni bajt w bajt', () {
      const profile = EquipmentProfile(mode: EquipmentMode.bodyweight);
      final base = buildFor('program_legs');
      final filtered = applyEquipmentToPlan(base, profile, noLimits, resolve,
          fromDayIndex: 10);
      for (var i = 0; i < 10; i++) {
        expect(
          filtered.plan.days[i].items.map((e) => e.exerciseId).toList(),
          base.days[i].items.map((e) => e.exerciseId).toList(),
          reason: 'dzień $i został zmieniony mimo fromDayIndex=10',
        );
      }
    });

    test('filtr nie dotyka completedDays ani id planu', () {
      const profile = EquipmentProfile(mode: EquipmentMode.bodyweight);
      final base = buildFor('program_chest')
          .copyWith(completedDays: {0, 1, 2}, id: 'plan_x');
      final filtered = applyEquipmentToPlan(base, profile, noLimits, resolve);
      expect(filtered.plan.completedDays, {0, 1, 2});
      expect(filtered.plan.id, 'plan_x');
    });
  });

  group('Pełna siłownia — nic nie znika bez potrzeby', () {
    test('program nie jest okrajany, gdy sprzęt jest kompletny', () {
      const profile = EquipmentProfile(mode: EquipmentMode.fullGym);
      for (final id in programIds) {
        final base = buildFor(id);
        final filtered = filterFor(id, profile);
        expect(filtered.report.substitutedCount, 0,
            reason: '$id: niepotrzebne zamiany przy pełnej siłowni');
        expect(filtered.report.removedCount, 0);
        for (var i = 0; i < base.days.length; i++) {
          expect(filtered.plan.days[i].items.length, base.days[i].items.length,
              reason: '$id dzień $i skrócony przy pełnej siłowni');
        }
      }
    });
  });
}
