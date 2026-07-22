import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/data/trainer_calorie_adapter.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WorkoutPlan buildProgram() => buildWorkoutProgram(
        'program_core',
        resolveExercise: ExerciseRepo.byId,
      );

  group('applyProgramVariant — ochrona postępu', () {
    test('zachowuje id, ukończone dni i dni wcześniejsze niż start wariantu', () {
      final base = buildProgram().copyWith(completedDays: {0, 1, 2});
      final variant = defaultVariantsForProgram('program_core')
          .firstWhere((v) => v.difficulty == ProgramDifficulty.advanced);
      final updated = applyProgramVariant(base, variant, fromDayIndex: 3);

      // Żadnego nowego identyfikatora programu, postęp nietknięty.
      expect(updated.id, base.id);
      expect(updated.completedDays, {0, 1, 2});
      expect(updated.currentDayIndex, base.currentDayIndex);
      expect(updated.days.length, base.days.length);
      // Ukończone dni nie są przeliczane wstecz — bajt w bajt te same.
      for (var i = 0; i < 3; i++) {
        expect(jsonEncode(updated.days[i].toJson()),
            jsonEncode(base.days[i].toJson()),
            reason: 'dzień ${i + 1} zmieniony wstecz');
      }
    });

    test('modyfikatory działają od wskazanego dnia (serie/powtórzenia/przerwy)', () {
      final base = buildProgram();
      final variant = ProgramVariant(
        id: 'test_variant',
        programId: 'program_core',
        name: 'Test',
        difficulty: ProgramDifficulty.advanced,
        setsDelta: 1,
        repsDelta: 2,
        restDeltaSeconds: -5,
      );
      final updated = applyProgramVariant(base, variant, fromDayIndex: 5);
      // Znajdź dzień treningowy >= 5 i porównaj pozycje.
      for (var d = 5; d < base.days.length; d++) {
        if (base.days[d].items.isEmpty) continue;
        final before = base.days[d].items.first;
        final after = updated.days[d].items.first;
        expect(after.sets, (before.sets + 1).clamp(1, 10));
        if (before.reps > 0) expect(after.reps, (before.reps + 2).clamp(3, 40));
        expect(after.restSeconds, (before.restSeconds - 5).clamp(5, 600));
        break;
      }
    });

    test('wariant krótki ogranicza liczbę ćwiczeń bez usuwania dni', () {
      final base = buildProgram();
      final short = defaultVariantsForProgram('program_core')
          .firstWhere((v) => v.goalAdaptation == ProgramGoalAdaptation.short);
      final updated = applyProgramVariant(base, short);
      expect(updated.days.length, base.days.length);
      for (final day in updated.days) {
        expect(day.items.length, lessThanOrEqualTo(short.maxExercisesPerDay),
            reason: 'dzień przekracza limit wariantu krótkiego');
      }
    });

    test('warianty domyślne pokrywają poziomy, środowisko i strategie', () {
      final variants = defaultVariantsForProgram('program_core');
      final adaptations = variants.map((v) => v.goalAdaptation).toSet();
      expect(variants.map((v) => v.difficulty).toSet(),
          containsAll(ProgramDifficulty.values));
      expect(
        adaptations,
        containsAll([
          ProgramGoalAdaptation.standard,
          ProgramGoalAdaptation.short,
          ProgramGoalAdaptation.intensive,
          ProgramGoalAdaptation.recomposition,
          ProgramGoalAdaptation.fatLoss,
          ProgramGoalAdaptation.muscleGain,
        ]),
      );
      // Warianty to różnice na wspólnym szablonie, nie kopie programu.
      for (final variant in variants) {
        expect(variant.isModifierBased, isTrue);
      }
    });
  });

  group('Walidacja wariantu (w tym AI)', () {
    test('wykrywa nieistniejące ćwiczenia, nierealne serie i brak regeneracji', () {
      final days = [
        for (var i = 0; i < 7; i++)
          WorkoutDay(weekday: i + 1, title: 'Dzień ${i + 1} · Brzuch', items: [
            const PlanItem(
              exerciseId: 'nie_ma_takiego',
              sets: 12,
              reps: 10,
              durationSec: 0,
              note: '',
              restSeconds: 2,
            ),
            const PlanItem(
              exerciseId: 'nie_ma_takiego',
              sets: 3,
              reps: 10,
              durationSec: 0,
              note: '',
              restSeconds: 60,
            ),
          ]),
      ];
      final variant = ProgramVariant(
        id: 'ai_bad',
        programId: 'program_core',
        name: 'Zły wariant AI',
        difficulty: ProgramDifficulty.intermediate,
        explicitDays: days,
        isAiGenerated: true,
      );
      final problems = validateProgramVariant(
        variant,
        exerciseExists: (id) => id == 'crunch',
      );
      expect(problems.join(' '), contains('nieistniejące ćwiczenie'));
      expect(problems.join(' '), contains('nierealna liczba serii'));
      expect(problems.join(' '), contains('powtórzone ćwiczenie'));
      expect(problems.join(' '), contains('dni regeneracyjnych'));
      expect(problems.join(' '), contains('tę samą partię dzień po dniu'));
    });

    test('poprawny wariant modyfikatorowy przechodzi walidację', () {
      final variant = defaultVariantsForProgram('program_core').first;
      expect(
        validateProgramVariant(variant, exerciseExists: (_) => true),
        isEmpty,
      );
    });
  });

  group('ProgramMedia — okładka programu', () {
    test('nowa okładka czeka na zatwierdzenie; stara żyje do decyzji', () {
      const media = ProgramMedia(localPath: '/covers/old.png');
      final withPending = media.copyWith(pendingLocalPath: '/covers/new.png');
      // Stara okładka wciąż aktywna.
      expect(withPending.effectivePath, '/covers/old.png');
      expect(withPending.hasPending, isTrue);
      // Zatwierdzenie podmienia; odrzucenie zostawia starą.
      final approved = withPending.approvePending();
      expect(approved.effectivePath, '/covers/new.png');
      expect(approved.hasPending, isFalse);
      final rejected = withPending.rejectPending();
      expect(rejected.effectivePath, '/covers/old.png');
      expect(rejected.hasPending, isFalse);
    });

    test('media serializują się w planie (osobne pole, nie obrazy ćwiczeń)', () {
      final plan = buildProgram().copyWith(
        media: ProgramMedia(
          localPath: '/covers/a.png',
          generatedPrompt: 'prompt',
          generationProvider: 'openai',
          generatedAt: DateTime(2026, 7, 12),
          isAiGenerated: true,
        ),
      );
      final restored = WorkoutPlan.fromJson(plan.toJson());
      expect(restored.media?.localPath, '/covers/a.png');
      expect(restored.media?.isAiGenerated, isTrue);
      expect(restored.media?.generationProvider, 'openai');
      // Pozycje dni (ćwiczenia) pozostały nietknięte.
      expect(restored.days.length, plan.days.length);
    });

    test('prompt okładki zawiera dane programu i styl aplikacji, bez tekstu', () {
      final prompt = buildProgramCoverPrompt(
        programName: '30 dni — Atletyczna góra ciała',
        physiqueLabel: 'Atletyczna',
        strategyLabel: 'Rekompozycja',
        trainingFocusLabel: 'Siła i hipertrofia',
        difficultyLabel: 'Średniozaawansowany',
        mainMuscles: const ['Barki', 'Plecy'],
        equipment: const ['Hantle'],
      );
      expect(prompt, contains('Atletyczna góra ciała'));
      expect(prompt, contains('Barki'));
      expect(prompt, contains('Rekompozycja'));
      expect(prompt, contains('graphite'));
      expect(prompt, contains('mint'));
      expect(prompt, contains('no text'));
    });
  });

  group('Ochrona postępów przy migracji i moście (sekcja 38)', () {
    Map<String, Object> prefsWithProgress() {
      final plan = buildProgram().copyWith(
        completedDays: {0, 1, 2, 3, 4},
        isActive: true,
      );
      final log = {
        'id': 'log_1',
        'date': '2026-07-10T10:00:00.000',
        'exerciseId': 'crunch',
        'sets': 3,
        'reps': 12,
        'weightKg': 10.0,
        'durationSec': 0,
        'rpe': 8,
        'calories': 50.0,
        'note': '',
        'aiConfidence': 0.0,
      };
      return {
        'workout_plans_v1': jsonEncode([plan.toJson()]),
        'workout_logs_v1': jsonEncode([log]),
        // Stare ustawienia sprzed centralnego profilu (do migracji).
        'workout_settings_v1': jsonEncode({
          'bodyWeightKg': 95.3,
          'heightCm': 185,
          'age': 28,
          'trainingMode': 'Rekompozycja',
          'goal': 'stary cel',
          'level': 'Średniozaawansowany',
          'equipment': 'hantle',
          'limitations': '',
          'backendUrl': '',
          'darkMode': true,
          'accentColorValue': 0xFF24D6A3,
          'trainingWeekdays': [1, 2, 3, 4, 5],
          'targetSilhouette': 'recomposition',
        }),
      };
    }

    test('1. migracja profilu celu nie zmienia bieżącego dnia programu', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      // Migracja zaszła (stara sylwetka „rekompozycja" → profil).
      expect(store.bodyGoalProfile, isNotNull);
      expect(store.bodyGoalProfile!.bodyCompositionStrategy,
          BodyCompositionStrategy.recomposition);
      expect(store.bodyGoalProfile!.goalSource, GoalSource.migrated);
      // Postęp programu NIETKNIĘTY.
      final plan = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      expect(plan.completedDays, {0, 1, 2, 3, 4});
      expect(plan.currentDayIndex, 5);
    });

    test('2. zmiana strategii z rekompozycji na redukcję nie zeruje programu', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      final before = store.plans
          .firstWhere((p) => p.id.startsWith('program_core'))
          .completedDays;
      await store.updateBodyGoalProfile(
        store.bodyGoalProfile!.copyWith(
          bodyCompositionStrategy: BodyCompositionStrategy.fatLoss,
        ),
        phaseChangeReason: 'test',
      );
      final after = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      expect(after.completedDays, before);
      expect(after.currentDayIndex, 5);
      // Historia etapów: stary etap zamknięty, nowy otwarty (bez nadpisania).
      expect(store.goalPhases.length, greaterThanOrEqualTo(2));
      expect(store.goalPhases[store.goalPhases.length - 2].isActive, isFalse);
      expect(store.goalPhases.last.strategy, BodyCompositionStrategy.fatLoss);
    });

    test('3. zmiana typu treningu nie usuwa ukończonych ćwiczeń (logów)', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      final logCount = store.logs.length;
      await store.updateBodyGoalProfile(
        store.bodyGoalProfile!.copyWith(trainingFocus: TrainingFocus.strength),
      );
      expect(store.logs.length, logCount);
      expect(
        store.plans
            .firstWhere((p) => p.id.startsWith('program_core'))
            .completedDays,
        {0, 1, 2, 3, 4},
      );
    });

    test('4. aktualizacja mostu do Kalorii nie zmienia postępu programu', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      await store.publishDailyAdjustmentsBridge();
      final plan = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      expect(plan.completedDays, {0, 1, 2, 3, 4});
      // Most opublikował cele z centralnego profilu (rekompozycja).
      final payload = await const TrainerCalorieLocalAdapter().loadDailyAdjustmentsPayload();
      expect(payload, isNotEmpty);
      final targets = payload.first['nutritionTargets'] as Map?;
      expect(targets, isNotNull);
      expect(targets!['strategyId'], 'recomposition');
      expect(targets['goalSync'], isNotNull);
    });

    test('5.–6. zmiana modelu danych + restart zachowują serie/RPE i postęp', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final first = AppStore();
      await first.load();
      await first.updateBodyGoalProfile(
        first.bodyGoalProfile!.copyWith(
          bodyCompositionStrategy: BodyCompositionStrategy.fatLoss,
        ),
      );
      // Restart aplikacji (nowy store na tych samych prefs).
      final second = AppStore();
      await second.load();
      final plan = second.plans.firstWhere((p) => p.id.startsWith('program_core'));
      expect(plan.completedDays, {0, 1, 2, 3, 4});
      expect(second.logs, hasLength(1));
      expect(second.logs.single.rpe, 8);
      expect(second.logs.single.reps, 12);
      expect(second.logs.single.weightKg, 10.0);
      expect(second.bodyGoalProfile!.bodyCompositionStrategy,
          BodyCompositionStrategy.fatLoss);
      expect(second.goalPhases.length, greaterThanOrEqualTo(2));
    });

    test('7.–8. synchronizacja chmurowa nie duplikuje programu i nie cofa postępu', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      final plansBefore = store.plans.length;
      final planBefore = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      // „Starsza kopia z chmury": ten sam program z mniejszym postępem.
      final olderExport = {
        'plans': [
          planBefore.copyWith(completedDays: {0}).toJson(),
        ],
      };
      final added = await store.mergeFullData(olderExport);
      expect(added['plans'], 0, reason: 'ten sam id nie tworzy kopii');
      expect(store.plans.length, plansBefore);
      final planAfter = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      expect(planAfter.completedDays, {0, 1, 2, 3, 4},
          reason: 'starsza wersja danych nie nadpisuje nowszego postępu');
    });

    test('9. uszkodzony zapis profilu celu nie psuje startu ani postępu', () async {
      final prefs = prefsWithProgress();
      prefs['user_body_goal_profile_v1'] = '{uszkodzony json';
      SharedPreferences.setMockInitialValues(prefs);
      final store = AppStore();
      await store.load();
      // Fallback: migracja ze starych ustawień (kopia zapasowa zachowania).
      expect(store.bodyGoalProfile, isNotNull);
      expect(
        store.plans
            .firstWhere((p) => p.id.startsWith('program_core'))
            .completedDays,
        {0, 1, 2, 3, 4},
      );
    });

    test('10. nowy wariant nie zmienia historii poprzedniego wariantu', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      final planId = store.plans.firstWhere((p) => p.id.startsWith('program_core')).id;
      final variants = defaultVariantsForProgram('program_core');
      await store.applyVariantToPlan(planId, variants[0]);
      final historyAfterFirst = store.plans
          .firstWhere((p) => p.id == planId)
          .variantHistory
          .map((c) => c.toJson())
          .toList();
      await store.applyVariantToPlan(planId, variants[2]);
      final plan = store.plans.firstWhere((p) => p.id == planId);
      expect(plan.variantHistory.length, 2);
      // Pierwszy wpis historii niezmieniony.
      expect(jsonEncode(plan.variantHistory.first.toJson()),
          jsonEncode(historyAfterFirst.first));
      expect(plan.activeVariantId, variants[2].id);
      // Postęp wciąż nietknięty.
      expect(plan.completedDays, {0, 1, 2, 3, 4});
      // Historia wariantów przeżywa restart.
      final restarted = AppStore();
      await restarted.load();
      expect(
        restarted.plans.firstWhere((p) => p.id == planId).variantHistory.length,
        2,
      );
    });

    test('zmiana masy/celu wagowego nie dotyka programów', () async {
      SharedPreferences.setMockInitialValues(prefsWithProgress());
      final store = AppStore();
      await store.load();
      await store.updateSettings(store.settings.copyWith(bodyWeightKg: 92, targetWeightKg: 86));
      expect(
        store.plans
            .firstWhere((p) => p.id.startsWith('program_core'))
            .completedDays,
        {0, 1, 2, 3, 4},
      );
    });
  });

  group('Integracja profilu celu z mostem (sekcja 35)', () {
    test('zmiana strategii podbija rewizję i zmienia changeId (bez pętli)', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateBodyGoalProfile(
        UserBodyGoalProfile(
          desiredPhysique: DesiredPhysique.athletic,
          bodyCompositionStrategy: BodyCompositionStrategy.recomposition,
          trainingFocus: TrainingFocus.strengthHypertrophy,
          goalSource: GoalSource.manual,
          updatedAt: DateTime.now(),
        ),
      );
      final rev1 = store.bodyGoalProfile!.revision;
      final change1 = store.bodyGoalProfile!.changeId;
      // Ta sama treść → BEZ nowej rewizji (Trainer nie wysyła tej samej zmiany).
      await store.updateBodyGoalProfile(store.bodyGoalProfile!);
      expect(store.bodyGoalProfile!.revision, rev1);
      expect(store.bodyGoalProfile!.changeId, change1);
      // Realna zmiana → nowa rewizja + nowy changeId.
      await store.updateBodyGoalProfile(
        store.bodyGoalProfile!.copyWith(
          bodyCompositionStrategy: BodyCompositionStrategy.fatLoss,
        ),
      );
      expect(store.bodyGoalProfile!.revision, rev1 + 1);
      expect(store.bodyGoalProfile!.changeId, isNot(change1));
      // Payload mostu niesie nową strategię i metadane.
      final payload = await const TrainerCalorieLocalAdapter().loadDailyAdjustmentsPayload();
      final targets = payload.first['nutritionTargets'] as Map;
      expect(targets['strategyId'], 'fat_loss');
      expect((targets['goalSync'] as Map)['revision'], rev1 + 1);
    });

    test('wyłączenie automatycznej publikacji zdejmuje cele z mostu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateBodyGoalProfile(
        UserBodyGoalProfile(
          desiredPhysique: DesiredPhysique.athletic,
          bodyCompositionStrategy: BodyCompositionStrategy.maintenance,
          trainingFocus: TrainingFocus.generalFitness,
          autoPublishToCalories: false,
          goalSource: GoalSource.manual,
          updatedAt: DateTime.now(),
        ),
      );
      await store.publishDailyAdjustmentsBridge();
      final payload = await const TrainerCalorieLocalAdapter().loadDailyAdjustmentsPayload();
      for (final row in payload) {
        expect(row['nutritionTargets'], isNull,
            reason: 'cele nie powinny jechać mostem po wyłączeniu publikacji');
      }
    });

    test('blokada celu kalorycznego jedzie w payloadzie mostu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.load();
      await store.updateBodyGoalProfile(
        UserBodyGoalProfile(
          desiredPhysique: DesiredPhysique.athletic,
          bodyCompositionStrategy: BodyCompositionStrategy.recomposition,
          trainingFocus: TrainingFocus.strengthHypertrophy,
          calorieTargetLocked: true,
          goalSource: GoalSource.manual,
          updatedAt: DateTime.now(),
        ),
      );
      final payload = await const TrainerCalorieLocalAdapter().loadDailyAdjustmentsPayload();
      final targets = payload.first['nutritionTargets'] as Map;
      expect(targets['calorieTargetLocked'], isTrue);
    });
  });
}
