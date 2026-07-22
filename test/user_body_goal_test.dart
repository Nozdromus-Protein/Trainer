import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

void main() {
  UserBodyGoalProfile profile({
    DesiredPhysique physique = DesiredPhysique.athletic,
    BodyCompositionStrategy strategy = BodyCompositionStrategy.recomposition,
    TrainingFocus focus = TrainingFocus.strengthHypertrophy,
    List<TrainingFocus> secondary = const [],
    List<PhysiquePriority> priorities = const [],
    bool locked = false,
    int revision = 1,
  }) {
    return UserBodyGoalProfile(
      desiredPhysique: physique,
      physiquePriorities: priorities,
      bodyCompositionStrategy: strategy,
      trainingFocus: focus,
      secondaryTrainingFocuses: secondary,
      calorieTargetLocked: locked,
      goalSource: GoalSource.trainer,
      updatedAt: DateTime(2026, 7, 12),
      revision: revision,
      changeId: 'change_$revision',
    );
  }

  GoalNutritionTargets? targetsFor(UserBodyGoalProfile? p,
      {double weightKg = 95.3, double ffm = 0}) {
    return computeGoalNutritionTargets(
      profile: p,
      weightKg: weightKg,
      heightCm: 185,
      age: 28,
      sex: 'Mężczyzna',
      trainingDaysPerWeek: 5,
      fatFreeMassKg: ffm,
    );
  }

  group('Konfiguracje profilu (sekcja 34, 1–5)', () {
    test('1. atletyczna + rekompozycja + hipertrofia', () {
      final p = profile(
        physique: DesiredPhysique.athletic,
        strategy: BodyCompositionStrategy.recomposition,
        focus: TrainingFocus.hypertrophy,
      );
      expect(p.desiredPhysique.label, 'Atletyczna');
      expect(p.bodyCompositionStrategy, BodyCompositionStrategy.recomposition);
      expect(p.trainingFocus, TrainingFocus.hypertrophy);
      final t = targetsFor(p)!;
      expect(t.strategy, BodyCompositionStrategy.recomposition);
      expect(t.phaseLabel, 'Rekompozycja');
    });

    test('2. umięśniona + redukcja + siła', () {
      final p = profile(
        physique: DesiredPhysique.muscular,
        strategy: BodyCompositionStrategy.fatLoss,
        focus: TrainingFocus.strength,
      );
      final t = targetsFor(p)!;
      // Kalorie ze STRATEGII (deficyt), mimo „masowej" sylwetki.
      expect(t.goalKcal, lessThan(t.tdeeKcal));
      expect(t.phaseLabel, 'Redukcja');
      expect(p.trainingFocus, TrainingFocus.strength);
    });

    test('3. biegowa + utrzymanie + wytrzymałość', () {
      final p = profile(
        physique: DesiredPhysique.runner,
        strategy: BodyCompositionStrategy.maintenance,
        focus: TrainingFocus.endurance,
      );
      final t = targetsFor(p)!;
      expect((t.goalKcal - t.tdeeKcal).abs(), lessThanOrEqualTo(10));
      expect(t.phaseLabel, 'Utrzymanie');
    });

    test('4. mocno umięśniona + masa + hipertrofia', () {
      final p = profile(
        physique: DesiredPhysique.veryMuscular,
        strategy: BodyCompositionStrategy.muscleGain,
        focus: TrainingFocus.hypertrophy,
      );
      final t = targetsFor(p)!;
      expect(t.goalKcal, greaterThan(t.tdeeKcal));
      expect(t.phaseLabel, 'Nadwyżka (masa)');
    });

    test('5. rekompozycja + siła i hipertrofia + bieganie (dodatkowe)', () {
      final p = profile(
        strategy: BodyCompositionStrategy.recomposition,
        focus: TrainingFocus.strengthHypertrophy,
        secondary: const [TrainingFocus.running],
      );
      expect(p.secondaryTrainingFocuses, contains(TrainingFocus.running));
      // Bieganie NIE zmienia strategii na redukcję.
      expect(p.bodyCompositionStrategy, BodyCompositionStrategy.recomposition);
      final t = targetsFor(p)!;
      expect(t.strategy, BodyCompositionStrategy.recomposition);
    });
  });

  group('Rozdzielenie trzech pojęć (6–7)', () {
    test('6. zmiana strategii bez zmiany docelowej sylwetki', () {
      final before = profile(strategy: BodyCompositionStrategy.recomposition);
      final after = before.copyWith(
        bodyCompositionStrategy: BodyCompositionStrategy.fatLoss,
      );
      expect(after.desiredPhysique, before.desiredPhysique);
      expect(after.trainingFocus, before.trainingFocus);
      expect(after.signature, isNot(before.signature));
    });

    test('7. zmiana treningu bez zmiany strategii', () {
      final before = profile(focus: TrainingFocus.hypertrophy);
      final after = before.copyWith(trainingFocus: TrainingFocus.strength);
      expect(after.bodyCompositionStrategy, before.bodyCompositionStrategy);
      expect(after.desiredPhysique, before.desiredPhysique);
      expect(after.signature, isNot(before.signature));
    });

    test('typ treningu nie zawiera strategii składu ciała', () {
      // Redukcja/masa/rekompozycja/utrzymanie NIE są typem treningu.
      expect(TrainingFocus.fromLegacyText('redukcja'), isNull);
      expect(TrainingFocus.fromLegacyText('masa'), isNull);
      expect(TrainingFocus.fromLegacyText('rekompozycja'), isNull);
      expect(TrainingFocus.fromLegacyText('utrzymanie'), isNull);
      // Prawdziwe typy treningu mapują się poprawnie.
      expect(TrainingFocus.fromLegacyText('hipertrofia'),
          TrainingFocus.hypertrophy);
      expect(TrainingFocus.fromLegacyText('siła'), TrainingFocus.strength);
      expect(TrainingFocus.fromLegacyText('bieganie'), TrainingFocus.running);
    });
  });

  group('Migracja starych ustawień (8–10)', () {
    test('8. stary tryb „Redukcja" → BodyCompositionStrategy.fatLoss', () {
      final migrated = migrateLegacyGoalProfile(
        legacyTrainingMode: 'Redukcja',
        legacyTargetSilhouette: 'athletic',
      );
      expect(migrated.bodyCompositionStrategy, BodyCompositionStrategy.fatLoss);
      expect(migrated.goalSource, GoalSource.migrated);
      expect(migrated.revision, 1);
      expect(migrated.changeId, isNotEmpty);
    });

    test('9. stary tryb „Masa" → BodyCompositionStrategy.muscleGain', () {
      final migrated = migrateLegacyGoalProfile(
        legacyTrainingMode: 'Masa',
        legacyTargetSilhouette: 'muscular',
      );
      expect(
          migrated.bodyCompositionStrategy, BodyCompositionStrategy.muscleGain);
      expect(migrated.desiredPhysique, DesiredPhysique.veryMuscular);
    });

    test(
        '10. stara sylwetka „rekompozycja" → sylwetka atletyczna + strategia rekompozycji',
        () {
      final migrated = migrateLegacyGoalProfile(
        legacyTrainingMode: 'Rekompozycja',
        legacyTargetSilhouette: 'recomposition',
        legacyTargetWeightKg: 88,
      );
      // Rekompozycja NIE jest sylwetką — rozdzielona na dwa pola.
      expect(migrated.desiredPhysique, DesiredPhysique.athletic);
      expect(migrated.bodyCompositionStrategy,
          BodyCompositionStrategy.recomposition);
      expect(migrated.targetWeightKg, 88);
    });

    test('mapowanie „utrzymanie" i „kondycja"', () {
      expect(strategyFromLegacyTrainingMode('Utrzymanie'),
          BodyCompositionStrategy.maintenance);
      expect(strategyFromLegacyTrainingMode('Kondycja'),
          BodyCompositionStrategy.performance);
    });

    test('profil przeżywa serializację (zapis lokalny/chmurowy)', () {
      final original = profile(
        priorities: const [
          PhysiquePriority.biggerShoulders,
          PhysiquePriority.visibleAbs
        ],
        secondary: const [TrainingFocus.running],
        locked: true,
        revision: 7,
      ).copyWith(targetBodyFatMinPercent: 12, targetBodyFatMaxPercent: 15);
      final restored = UserBodyGoalProfile.fromJson(original.toJson());
      expect(restored.signature, original.signature);
      expect(restored.revision, 7);
      expect(restored.calorieTargetLocked, isTrue);
      expect(restored.targetBodyFatMinPercent, 12);
      expect(restored.targetBodyFatMaxPercent, 15);
      expect(restored.physiquePriorities, original.physiquePriorities);
    });
  });

  group('Kalorie ze strategii, nie z nazwy sylwetki (11, 25–27)', () {
    test('ta sama strategia + różne sylwetki = te same kalorie', () {
      final athletic = targetsFor(profile(
        physique: DesiredPhysique.athletic,
        strategy: BodyCompositionStrategy.fatLoss,
      ))!;
      final muscular = targetsFor(profile(
        physique: DesiredPhysique.veryMuscular,
        strategy: BodyCompositionStrategy.fatLoss,
      ))!;
      expect(athletic.goalKcal, muscular.goalKcal);
      expect(athletic.proteinG, muscular.proteinG);
    });

    test('11. konflikt: strategia redukcja + kcal w nadwyżce', () {
      final conflicts = detectGoalConflicts(
        strategy: BodyCompositionStrategy.fatLoss,
        goalKcal: 3600,
        tdeeKcal: 3000,
      );
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.message, contains('redukcja'));
      expect(conflicts.first.suggestion, isNotEmpty);
    });

    test('konflikt: strategia masa + duży deficyt', () {
      final conflicts = detectGoalConflicts(
        strategy: BodyCompositionStrategy.muscleGain,
        goalKcal: 2200,
        tdeeKcal: 3000,
      );
      expect(conflicts, isNotEmpty);
    });

    test('brak konfliktu przy spójnej konfiguracji', () {
      final conflicts = detectGoalConflicts(
        strategy: BodyCompositionStrategy.recomposition,
        goalKcal: 2900,
        tdeeKcal: 3000,
      );
      expect(conflicts, isEmpty);
    });

    test('jedna baza bez aktywności dla dnia treningowego i regeneracyjnego',
        () {
      final t = targetsFor(profile())!;
      expect(t.kcalMin, lessThan(t.goalKcal));
      expect(t.kcalMax, greaterThan(t.goalKcal));
      expect(t.trainingDayKcal, t.goalKcal);
      expect(t.restDayKcal, t.goalKcal);
      expect(t.rationale, isNotEmpty);
    });

    test('Mifflin dla 96 kg, 185 cm i 30 lat nie zawiera treningu', () {
      final t = computeGoalNutritionTargets(
        profile: profile(strategy: BodyCompositionStrategy.recomposition),
        weightKg: 96,
        heightCm: 185,
        age: 30,
        sex: 'Mężczyzna',
        trainingDaysPerWeek: 6,
      )!;
      expect(t.bmrKcal, 1971);
      expect(t.tdeeKcal, 2190);
      expect(t.goalKcal, 2040);
      expect(t.proteinG, 190);
      expect(t.fatG, 79);
      expect(t.carbsG, 140);
      expect(t.sugarLimitG, 51);
      expect(t.fiberGoalG, 29);
      expect(t.saturatedFatLimitG, 22);
      expect(t.saltLimitG, 5);

      final macroKcal = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
      expect((macroKcal - t.goalKcal).abs(), lessThanOrEqualTo(20));
      final fatShare = t.fatG * 9 / t.goalKcal;
      expect(fatShare, inInclusiveRange(0.20, 0.35));

      final withoutPlannedTraining = computeGoalNutritionTargets(
        profile: profile(strategy: BodyCompositionStrategy.recomposition),
        weightKg: 96,
        heightCm: 185,
        age: 30,
        sex: 'Mężczyzna',
        trainingDaysPerWeek: 0,
      )!;
      expect(withoutPlannedTraining.goalKcal, t.goalKcal);
    });

    test('białko z FFM, gdy jest znana (nie % kalorii)', () {
      final withFfm = targetsFor(profile(), ffm: 73.4)!;
      final withoutFfm = targetsFor(profile())!;
      // 73.4 kg FFM × 2.4 g/kg (rekompozycja) ≈ 175 g.
      expect(withFfm.proteinG, closeTo(73.4 * 2.4, 6));
      expect(withFfm.proteinMinG, lessThan(withFfm.proteinG));
      expect(withFfm.proteinMaxG, greaterThan(withFfm.proteinG));
      expect(withoutFfm.proteinG, closeTo(95.3 * 2.0, 6));
    });

    test('kcal nigdy poniżej ~BMR (bezpieczny deficyt)', () {
      final t = targetsFor(
        profile(strategy: BodyCompositionStrategy.fatLoss),
        weightKg: 55,
      )!;
      expect(t.goalKcal, greaterThanOrEqualTo(t.bmrKcal));
    });

    test('brak profilu / brak danych → null (Kalorie zostają przy swoich)', () {
      expect(targetsFor(null), isNull);
      expect(
        computeGoalNutritionTargets(
          profile: profile(),
          weightKg: 0,
          heightCm: 185,
          age: 28,
          sex: 'M',
          trainingDaysPerWeek: 5,
        ),
        isNull,
      );
    });
  });

  group('Payload mostu (12, 24, 35)', () {
    test('12. brak połączenia = zapis lokalny; payload jest samowystarczalny',
        () {
      final t = targetsFor(profile(revision: 4))!;
      final json = t.toJson();
      // Klucze v1 — starsze Kalorie dalej działają.
      expect(json['goalKcal'], t.goalKcal);
      expect(json['nutritionModelVersion'], 3);
      expect(json['proteinG'], t.proteinG);
      expect(json['carbsG'], t.carbsG);
      expect(json['fatG'], t.fatG);
      expect(json['sugarLimitG'], t.sugarLimitG);
      expect(json['fiberGoalG'], t.fiberGoalG);
      expect(json['saturatedFatLimitG'], t.saturatedFatLimitG);
      expect(json['saltLimitG'], t.saltLimitG);
      expect(json['silhouetteLabel'], isNotEmpty);
      expect(json['phaseLabel'], isNotEmpty);
      // Rozszerzenie v2 — strategia, zakresy, metadane synchronizacji.
      expect(json['strategyId'], 'recomposition');
      expect(json['kcalMin'], t.kcalMin);
      expect(json['trainingDayKcal'], t.trainingDayKcal);
      expect(json['restDayKcal'], t.restDayKcal);
      final sync = json['goalSync'] as Map<String, dynamic>;
      expect(sync['revision'], 4);
      expect(sync['changeId'], 'change_4');
      expect(sync['sourceApp'], 'trainer');
      expect(DateTime.tryParse(sync['updatedAt'].toString()), isNotNull);
    });

    test('13. ręcznie zablokowany cel kalorii jedzie w payloadzie', () {
      final t = targetsFor(profile(locked: true))!;
      expect(t.calorieTargetLocked, isTrue);
      expect(t.toJson()['calorieTargetLocked'], isTrue);
    });

    test(
        'Kalorie nie muszą liczyć z nazwy sylwetki — payload niesie gotowe wartości',
        () {
      final t = targetsFor(profile(physique: DesiredPhysique.custom))!;
      // Nawet sylwetka „niestandardowa" ma komplet wartości ze strategii.
      expect(t.goalKcal, greaterThan(0));
      expect(t.proteinG, greaterThan(0));
    });
  });

  group('Synchronizacja i antypętla (15–16, 30)', () {
    test('15. starsza rewizja nie nadpisuje nowszej', () {
      expect(
        GoalSyncMetadata.shouldApplyIncoming(
          incomingRevision: 3,
          incomingChangeId: 'change_3',
          lastAppliedRevision: 5,
          lastAppliedChangeId: 'change_5',
        ),
        isFalse,
      );
    });

    test('16. powtórne odebranie tego samego changeId jest ignorowane', () {
      expect(
        GoalSyncMetadata.shouldApplyIncoming(
          incomingRevision: 5,
          incomingChangeId: 'change_5',
          lastAppliedRevision: 5,
          lastAppliedChangeId: 'change_5',
        ),
        isFalse,
      );
    });

    test('nowsza rewizja z nowym changeId przechodzi', () {
      expect(
        GoalSyncMetadata.shouldApplyIncoming(
          incomingRevision: 6,
          incomingChangeId: 'change_6',
          lastAppliedRevision: 5,
          lastAppliedChangeId: 'change_5',
        ),
        isTrue,
      );
    });

    test('metadane synchronizacji przeżywają serializację', () {
      final meta = GoalSyncMetadata(
        sourceApp: 'trainer',
        revision: 9,
        updatedAt: DateTime(2026, 7, 12, 10, 30),
        changeId: 'abc',
      );
      final restored = GoalSyncMetadata.fromJson(meta.toJson());
      expect(restored.revision, 9);
      expect(restored.changeId, 'abc');
      expect(restored.sourceApp, 'trainer');
    });
  });

  group('Masa, BF i rekomendacje (17–19)', () {
    test('17. zmiana masy bez zmiany celu: profil bez zmian, kcal przeliczone',
        () {
      final p = profile();
      final before = targetsFor(p, weightKg: 95.3)!;
      final after = targetsFor(p, weightKg: 90.0)!;
      expect(after.goalKcal, isNot(before.goalKcal));
      // Profil (rewizja/sygnatura) nietknięty — masa nie jest częścią celu.
      expect(p.signature, profile().signature);
    });

    test('18. zmiana BF wpływa na FFM i rekomendację strategii', () {
      final highBf = recommendBodyCompositionStrategy(
        bodyFatPercent: 29,
        bodyFatConfidencePercent: 80,
        isFemale: false,
        trainingDaysPerWeek: 4,
      )!;
      expect(highBf.strategy, BodyCompositionStrategy.fatLoss);
      final lowBf = recommendBodyCompositionStrategy(
        bodyFatPercent: 10,
        bodyFatConfidencePercent: 80,
        isFemale: false,
        trainingDaysPerWeek: 4,
      )!;
      expect(lowBf.strategy, BodyCompositionStrategy.muscleGain);
      final midBf = recommendBodyCompositionStrategy(
        bodyFatPercent: 21,
        bodyFatConfidencePercent: 80,
        isFemale: false,
        trainingDaysPerWeek: 4,
        ffmi: 21,
      )!;
      expect(midBf.strategy, BodyCompositionStrategy.recomposition);
      // FFM przelicza się z masy i BF.
      final ffmHigh = computeBodyCompositionBreakdown(
          bodyWeightKg: 95.3, bodyFatPercent: 29)!;
      final ffmLow = computeBodyCompositionBreakdown(
          bodyWeightKg: 95.3, bodyFatPercent: 10)!;
      expect(ffmLow.fatFreeMassKg, greaterThan(ffmHigh.fatFreeMassKg));
    });

    test('19. niska pewność BF blokuje kategoryczną rekomendację', () {
      final rec = recommendBodyCompositionStrategy(
        bodyFatPercent: 29,
        bodyFatConfidencePercent: 30,
        isFemale: false,
        trainingDaysPerWeek: 4,
      )!;
      expect(rec.categorical, isFalse);
      expect(rec.reason, contains('niska'));
    });

    test('14. rekomendacja zawsze wymaga zatwierdzenia (nigdy automatyczna)',
        () {
      final rec = recommendBodyCompositionStrategy(
        bodyFatPercent: 23,
        bodyFatConfidencePercent: 70,
        isFemale: false,
        trainingDaysPerWeek: 5,
      )!;
      expect(rec.requiresConfirmation, isTrue);
    });

    test(
        'strategia „automatyczna" liczy kalorie jak utrzymanie do czasu zatwierdzenia',
        () {
      final t =
          targetsFor(profile(strategy: BodyCompositionStrategy.automatic))!;
      expect(t.strategy, BodyCompositionStrategy.maintenance);
    });
  });

  group('Ocena postępu zależna od strategii (20–21)', () {
    test('20. rekompozycja oceniana po talii i sile, nie tylko po masie', () {
      final assessment = assessStrategyProgress(
        strategy: BodyCompositionStrategy.recomposition,
        weightChangeKg: -0.1, // masa prawie bez zmian
        waistChangeCm: -1.5,
        strengthChangePercent: 4,
      );
      expect(assessment, contains('rekompozycj'));
      expect(assessment, contains('talii'));
    });

    test('mała zmiana w granicach błędu nie alarmuje', () {
      final assessment = assessStrategyProgress(
        strategy: BodyCompositionStrategy.fatLoss,
        bodyFatChangePp: -0.6,
        changesWithinErrorMargin: true,
      );
      expect(assessment, contains('marginesie błędu'));
      expect(assessment, contains('trendu'));
    });

    test('redukcja: spadek masy przy zachowanej sile = prawidłowo', () {
      final assessment = assessStrategyProgress(
        strategy: BodyCompositionStrategy.fatLoss,
        weightChangeKg: -0.5,
        strengthChangePercent: 0,
      );
      expect(assessment, contains('prawidłowo'));
    });
  });

  group('Historia etapów celu (22)', () {
    test('zamknięcie etapu nie nadpisuje danych startowych', () {
      final phase = GoalPhase(
        strategy: BodyCompositionStrategy.fatLoss,
        startDate: DateTime(2026, 5, 1),
        startWeightKg: 98,
        startBodyFatPercent: 26,
        startWaistCm: 96,
        reason: 'Start redukcji',
      );
      final closed = phase.closed(
        endDate: DateTime(2026, 7, 1),
        endWeightKg: 93,
        endBodyFatPercent: 21,
        endWaistCm: 91,
      );
      expect(closed.startWeightKg, 98);
      expect(closed.startBodyFatPercent, 26);
      expect(closed.endWeightKg, 93);
      expect(closed.isActive, isFalse);
      expect(phase.isActive, isTrue, reason: 'oryginał niezmutowany');
      final restored = GoalPhase.fromJson(closed.toJson());
      expect(restored.endBodyFatPercent, 21);
      expect(restored.reason, 'Start redukcji');
    });
  });

  group('Docelowy zakres BF (20)', () {
    test('sugestia zależy od sylwetki i płci, ale jest tylko podpowiedzią', () {
      final male =
          suggestedBodyFatRange(DesiredPhysique.shredded, isFemale: false);
      final female =
          suggestedBodyFatRange(DesiredPhysique.shredded, isFemale: true);
      expect(female.min, greaterThan(male.min));
      expect(male.min, lessThan(male.max));
      // Zakres jest edytowalny w profilu — nie ma sztywnego przypisania.
      final p = profile().copyWith(
        targetBodyFatMinPercent: 9,
        targetBodyFatMaxPercent: 11,
      );
      expect(p.targetBodyFatPercent, 10);
    });
  });
}
