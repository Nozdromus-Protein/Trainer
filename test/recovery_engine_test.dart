import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/recovery_personalization.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

/// TESTY SILNIKA GOTOWOŚCI — całkowicie bez UI (spec: punkt 29/30).
///
/// Model regeneracji musi być testowalny w oderwaniu od widgetów; liczenie
/// gotowości nie ma prawa siedzieć w `build()`.

Exercise _exercise(
  String id, {
  List<ExerciseMuscleImpact> impacts = const [
    ExerciseMuscleImpact(muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
  ],
  String equipment = 'sztanga',
  String entryTypeKey = '',
  int defaultDurationSec = 0,
  double met = 4.5,
}) =>
    Exercise(
      id: id,
      name: id,
      category: 'Test',
      muscles: const ['klatka piersiowa'],
      equipment: equipment,
      level: 'Średniozaawansowany',
      illustrationType: 'generic',
      description: '',
      tips: const [],
      commonMistakes: const [],
      defaultSets: 3,
      defaultReps: 10,
      defaultDurationSec: defaultDurationSec,
      met: met,
      entryTypeKey: entryTypeKey,
      muscleImpacts: impacts,
    );

WorkoutLog _log({
  required String exerciseId,
  required DateTime at,
  int sets = 3,
  int reps = 10,
  double weightKg = 60,
  int rpe = 8,
  String sessionId = 'sess',
  List<WorkoutSet> workoutSets = const [],
}) =>
    WorkoutLog(
      id: 'log_${exerciseId}_${at.millisecondsSinceEpoch}_$sessionId',
      exerciseId: exerciseId,
      date: DateTime(at.year, at.month, at.day),
      sets: sets,
      reps: reps,
      weightKg: weightKg,
      durationSec: 0,
      rpe: rpe,
      calories: 0,
      note: '',
      aiConfidence: 0,
      sessionId: sessionId,
      performedAt: at,
      workoutSets: workoutSets,
    );

WorkoutSet _set(int order, {required int reps, required double weight, int rpe = 8}) =>
    WorkoutSet(
      id: 'set_$order',
      order: order,
      repetitions: reps,
      weightKg: weight,
      durationSec: 0,
      rpe: rpe,
      isCompleted: true,
      rpeSource: 'user',
    );

void main() {
  final now = DateTime(2026, 8, 10, 18);

  Map<BodyMuscle, MuscleRecoveryState> compute(
    List<WorkoutLog> logs, {
    Exercise Function(String)? resolve,
    RecoveryEnvironment environment = RecoveryEnvironment.unknown,
    RecoveryCalibrationProfile calibration = RecoveryCalibrationProfile.empty,
    DateTime? at,
  }) =>
      RecoveryCalculator(environment: environment, calibration: calibration)
          .compute(
        logs: logs,
        resolveExercise: resolve ?? (id) => _exercise(id),
        now: at ?? now,
      );

  group('Brak danych kontekstowych nie psuje silnika (spec 10 i 31)', () {
    test('bez danych o odżywianiu silnik nadal liczy gotowość', () {
      final map = compute([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 6))),
      ]);
      final chest = map[BodyMuscle.chest];
      expect(chest, isNotNull);
      expect(chest!.hasData, isTrue);
      expect(chest.recoveryPercent, isNotNull);
      expect(chest.readiness!.confidence, greaterThan(0));
    });

    test('bez danych o śnie silnik nadal liczy gotowość', () {
      const noSleep = RecoveryEnvironment(bodyWeightKg: 80);
      expect(noSleep.hasSleepData, isFalse);
      expect(noSleep.sleepFactor, 1.0, reason: 'brak danych = neutralnie');
      final map = compute(
        [_log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 6)))],
        environment: noSleep,
      );
      expect(map[BodyMuscle.chest]?.hasData, isTrue);
    });

    test('brak danych obniża PEWNOŚĆ, a nie gotowość', () {
      final logs = [
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 6))),
      ];
      final without = compute(logs)[BodyMuscle.chest]!;
      final with_ = compute(
        logs,
        environment: const RecoveryEnvironment(
          sleepMinutes: 450,
          intakeKcal: 2600,
          targetKcal: 2600,
          proteinG: 150,
          carbsG: 300,
          bodyWeightKg: 80,
        ),
      )[BodyMuscle.chest]!;
      expect(with_.readiness!.confidence,
          greaterThan(without.readiness!.confidence));
    });

    test('starszy zapis bez serii i bez RPE nadal działa (migracja)', () {
      final legacy = WorkoutLog(
        id: 'legacy',
        exerciseId: 'bench',
        date: DateTime(now.year, now.month, now.day),
        sets: 4,
        reps: 8,
        weightKg: 70,
        durationSec: 0,
        rpe: 0, // brak oceny wysiłku
        calories: 0,
        note: '',
        aiConfidence: 0,
      );
      final map = compute([legacy]);
      expect(map[BodyMuscle.chest], isNotNull);
      expect(map[BodyMuscle.chest]!.recoveryPercent, isNotNull);
      // Brak RPE = mniejsza pewność niż przy pełnych danych serii.
      final withSets = compute([
        _log(
          exerciseId: 'bench',
          at: now.subtract(const Duration(hours: 12)),
          workoutSets: [
            for (var i = 0; i < 4; i++) _set(i, reps: 8, weight: 70),
          ],
        ),
      ]);
      expect(withSets[BodyMuscle.chest]!.readiness!.confidence,
          greaterThan(map[BodyMuscle.chest]!.readiness!.confidence));
    });
  });

  group('Bliskość upadku (spec 1B, badania 4–6)', () {
    test('sesja do upadku męczy bardziej niż porównywalna bez upadku', () {
      final at = now.subtract(const Duration(hours: 10));
      final toFailure = compute([
        _log(exerciseId: 'bench', at: at, rpe: 10),
      ])[BodyMuscle.chest]!;
      final inReserve = compute([
        _log(exerciseId: 'bench', at: at, rpe: 7),
      ])[BodyMuscle.chest]!;
      expect(toFailure.recoveryPercent!, lessThan(inReserve.recoveryPercent!),
          reason:
              'ta sama objętość do upadku musi kosztować więcej niż z zapasem');
      // Różnica dotyczy przede wszystkim osi NERWOWO-MIĘŚNIOWEJ.
      expect(toFailure.readiness!.neuromuscular,
          lessThan(inReserve.readiness!.neuromuscular));
    });

    test('skala bliskości upadku jest CIĄGŁA, nie skokowa', () {
      final at = now.subtract(const Duration(hours: 10));
      double readinessAtRpe(int rpe) =>
          compute([_log(exerciseId: 'bench', at: at, rpe: rpe)])[
                  BodyMuscle.chest]!
              .recoveryPercent!;
      final rpe7 = readinessAtRpe(7); // 3 RIR
      final rpe8 = readinessAtRpe(8); // 2 RIR
      final rpe9 = readinessAtRpe(9); // 1 RIR
      final rpe10 = readinessAtRpe(10); // upadek
      expect(rpe7, greaterThan(rpe8));
      expect(rpe8, greaterThan(rpe9));
      expect(rpe9, greaterThan(rpe10));
      // Żaden krok nie jest „schodkiem" typu failure = +24 h.
      expect((rpe9 - rpe10).abs(), lessThan(30));
    });
  });

  group('Udział partii w ćwiczeniu (spec 4)', () {
    test('partia pomocnicza dostaje CZĘŚCIOWY bodziec, nie zerowy i nie pełny',
        () {
      Exercise resolve(String id) => _exercise(id, impacts: const [
            ExerciseMuscleImpact(
                muscleGroup: BodyMuscle.chest, role: MuscleRole.primary),
            ExerciseMuscleImpact(
                muscleGroup: BodyMuscle.frontShoulders,
                role: MuscleRole.secondary),
            ExerciseMuscleImpact(
                muscleGroup: BodyMuscle.triceps, role: MuscleRole.secondary),
          ]);
      final map = compute(
        [_log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 4)))],
        resolve: resolve,
      );
      final chest = map[BodyMuscle.chest]!.recoveryPercent!;
      final shoulders = map[BodyMuscle.frontShoulders]!.recoveryPercent!;
      expect(shoulders, greaterThan(chest),
          reason: 'bark pracuje w pchaniu, ale mniej niż klatka');
      expect(shoulders, lessThan(100),
          reason: 'bark NIE jest nietknięty po dniu pchania');
      expect(map[BodyMuscle.triceps], isNotNull);
    });
  });

  group('Lekki bodziec vs. ciężka sesja (spec 21)', () {
    test('lekka sesja regeneracyjna nie zachowuje się jak ciężki trening', () {
      final at = now.subtract(const Duration(hours: 4));
      final heavy = compute([
        _log(exerciseId: 'bench', at: at, sets: 5, reps: 10, rpe: 9),
      ])[BodyMuscle.chest]!;
      final light = compute(
        [_log(exerciseId: 'mob', at: at, sets: 2, reps: 10, weightKg: 0, rpe: 4)],
        resolve: (id) => _exercise(id,
            equipment: 'masa ciała',
            entryTypeKey: 'mobility',
            defaultDurationSec: 30),
      )[BodyMuscle.chest]!;
      expect(light.recoveryPercent!, greaterThan(heavy.recoveryPercent! + 25));
      expect(light.status, isNot(RecoveryStatus.freshFatigue));
    });
  });

  group('Gotowość zależy od RODZAJU planowanego bodźca (spec 3)', () {
    test('lekka praca jest możliwa wcześniej niż maksymalna siła', () {
      final map = compute([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 20))),
      ]);
      final readiness = map[BodyMuscle.chest]!.readiness!;
      final recovery = readiness.readinessFor(TrainingStimulusKind.activeRecovery);
      final technique = readiness.readinessFor(TrainingStimulusKind.technique);
      final moderate = readiness.readinessFor(TrainingStimulusKind.moderate);
      final hypertrophy =
          readiness.readinessFor(TrainingStimulusKind.hypertrophy);
      final maxStrength =
          readiness.readinessFor(TrainingStimulusKind.maxStrength);
      expect(recovery, greaterThan(technique));
      expect(technique, greaterThan(moderate));
      expect(moderate, greaterThan(hypertrophy));
      expect(hypertrophy, greaterThan(maxStrength));
    });
  });

  group('Oswojenie z bodźcem / repeated-bout effect (spec 5)', () {
    test('brak historii to NIEPEWNOŚĆ, a nie „nowe ćwiczenie"', () {
      final familiarity = buildFamiliarityMap([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(days: 1))),
      ], now: now);
      expect(familiarity['bench']!.known, isFalse);
      expect(familiarity['bench']!.structuralModifier, 1.0,
          reason: 'nie karzemy za bodziec, o którym nic nie wiemy');
      expect(familiarity['bench']!.confidencePenalty, greaterThan(0));
    });

    test('powtarzanie ćwiczenia podnosi oswojenie i obniża modyfikator', () {
      List<WorkoutLog> history(int sessions) => [
            for (var i = 0; i < sessions; i++)
              _log(
                exerciseId: 'bench',
                at: now.subtract(Duration(days: sessions - i)),
                sessionId: 'sess_$i',
              ),
            // Dodatkowe sesje innych ćwiczeń, żeby historia była wiarygodna.
            for (var i = 0; i < 3; i++)
              _log(
                exerciseId: 'row',
                at: now.subtract(Duration(days: 10 + i)),
                sessionId: 'other_$i',
              ),
          ];
      final rookie = buildFamiliarityMap(history(1), now: now)['bench']!;
      final veteran = buildFamiliarityMap(history(8), now: now)['bench']!;
      expect(veteran.score, greaterThan(rookie.score));
      expect(veteran.structuralModifier, lessThan(rookie.structuralModifier));
      expect(veteran.confidencePenalty,
          lessThanOrEqualTo(rookie.confidencePenalty));
    });

    test('nowe ćwiczenie w ugruntowanej historii daje większy koszt struktury',
        () {
      final base = [
        for (var i = 0; i < 5; i++)
          _log(
            exerciseId: 'bench',
            at: now.subtract(Duration(days: 20 - i * 3)),
            sessionId: 'sess_$i',
          ),
      ];
      final familiar = buildFamiliarityMap(base, now: now)['bench']!;
      final novel = buildFamiliarityMap(
        [...base, _log(exerciseId: 'newLift', at: now, sessionId: 'fresh')],
        now: now,
      )['newLift']!;
      expect(novel.known, isTrue);
      expect(novel.structuralModifier, greaterThan(familiar.structuralModifier));
    });

    test('długa przerwa częściowo cofa adaptację', () {
      const fresh = ExerciseFamiliarity(
          sessions: 8, daysSinceLast: 3, known: true);
      const stale = ExerciseFamiliarity(
          sessions: 8, daysSinceLast: 60, known: true);
      expect(stale.score, lessThan(fresh.score));
      expect(stale.structuralModifier, greaterThan(fresh.structuralModifier));
    });
  });

  group('Sen i odżywianie jako MODYFIKATORY (spec 9 i 10)', () {
    test('krótki sen obniża gotowość, ale w ograniczonym zakresie', () {
      final logs = [
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 18))),
      ];
      final rested = compute(logs,
          environment: const RecoveryEnvironment(
              sleepMinutes: 480, bodyWeightKg: 80))[BodyMuscle.chest]!;
      final deprived = compute(logs,
          environment: const RecoveryEnvironment(
              sleepMinutes: 240, bodyWeightKg: 80))[BodyMuscle.chest]!;
      expect(deprived.recoveryPercent!, lessThan(rested.recoveryPercent!));
      // Bez absurdów typu „5 h snu = +24 h regeneracji dla wszystkiego".
      expect(rested.recoveryPercent! - deprived.recoveryPercent!, lessThan(25));
    });

    test('deficyt energetyczny obniża odbudowę zasobów, nie kasuje jej', () {
      const deficit = RecoveryEnvironment(
          intakeKcal: 1400, targetKcal: 2600, bodyWeightKg: 80, carbsG: 90);
      const fed = RecoveryEnvironment(
          intakeKcal: 2700, targetKcal: 2600, bodyWeightKg: 80, carbsG: 340);
      expect(deficit.energyFactor, lessThan(fed.energyFactor));
      expect(deficit.energyFactor, greaterThan(0.8));
    });

    test('podaż białka opisana jest ZALEŻNOŚCIĄ, nie progiem 20 g', () {
      const low = RecoveryEnvironment(proteinG: 50, bodyWeightKg: 80);
      const mid = RecoveryEnvironment(proteinG: 90, bodyWeightKg: 80);
      const high = RecoveryEnvironment(proteinG: 150, bodyWeightKg: 80);
      expect(low.proteinFactor, lessThan(mid.proteinFactor));
      expect(mid.proteinFactor, lessThan(high.proteinFactor));
      expect(high.proteinFactor, lessThan(1.1));
    });

    test('DOMS obniża wynik subiektywny, ale nigdy nie zeruje gotowości', () {
      const sore = RecoveryEnvironment(sorenessLevel: 10, wellbeingLevel: 2);
      expect(sore.subjectiveScore, greaterThanOrEqualTo(0.7));
    });
  });

  group('Obciążenie ostre vs. przewlekłe (spec 26)', () {
    test('bez wystarczającej historii nie ma normy — brak kary', () {
      const unknown = AcuteChronicLoad(acuteUnits: 12, hasBaseline: false);
      expect(unknown.ratio, 1.0);
      expect(unknown.isSpike, isFalse);
      expect(unknown.readinessModifier, 1.0);
    });

    test('nagły skok objętości obniża gotowość ostrożnościowo', () {
      const spike = AcuteChronicLoad(
          acuteUnits: 25, chronicUnitsPerWeek: 11, hasBaseline: true);
      expect(spike.isSpike, isTrue);
      expect(spike.readinessModifier, lessThan(1.0));
      expect(spike.readinessModifier, greaterThanOrEqualTo(0.85));
    });
  });

  group('Kalibracja indywidualna (spec 6)', () {
    const service = RecoveryPersonalizationService();

    test('pojedyncza obserwacja nie przestawia profilu', () {
      const start = MuscleRecoveryCalibration();
      final after = start.updated(error: 1.0, weight: 1.0);
      expect(after.observations, 1);
      expect(after.isActive, isFalse, reason: 'za mało obserwacji');
      expect((after.effectiveScale - 1.0).abs(), lessThan(0.02));
    });

    test('korekta jest ograniczona nawet przy serii skrajnych obserwacji', () {
      var calibration = const MuscleRecoveryCalibration();
      for (var i = 0; i < 200; i++) {
        calibration = calibration.updated(error: 5.0, weight: 1.0);
      }
      expect(calibration.tauScale,
          lessThanOrEqualTo(MuscleRecoveryCalibration.maxScale));
      expect(calibration.effectiveScale, lessThanOrEqualTo(1.4));
    });

    test('zbyt konserwatywna prognoza skraca stałe czasowe', () {
      const observation = ReadinessObservation(
        muscle: BodyMuscle.chest,
        predictedReadiness: 60, // model straszył zmęczeniem…
        performanceDelta: 0.02, // …a wynik był lepszy niż poprzednio
        rpeDelta: 0,
        confidence: 0.9,
      );
      expect(observation.error, lessThan(0));
      final profile = service.apply(
          RecoveryCalibrationProfile.empty, [observation], at: now);
      expect(profile.forMuscle(BodyMuscle.chest).tauScale, lessThan(1.0));
    });

    test('zbyt optymistyczna prognoza wydłuża stałe czasowe', () {
      const observation = ReadinessObservation(
        muscle: BodyMuscle.chest,
        predictedReadiness: 95, // model obiecywał świeżość…
        performanceDelta: -0.2, // …a wydajność wyraźnie spadła
        rpeDelta: 1.5,
        confidence: 0.9,
      );
      expect(observation.error, greaterThan(0));
      final profile = service.apply(
          RecoveryCalibrationProfile.empty, [observation], at: now);
      expect(profile.forMuscle(BodyMuscle.chest).tauScale, greaterThan(1.0));
    });

    test('brak wyraźnego sygnału nie uczy modelu niczego', () {
      const observation = ReadinessObservation(
        muscle: BodyMuscle.chest,
        predictedReadiness: 82,
        performanceDelta: 0.0,
        rpeDelta: 0.2,
        confidence: 0.9,
      );
      expect(observation.error, 0);
      final profile = service.apply(
          RecoveryCalibrationProfile.empty, [observation], at: now);
      expect(profile.isEmpty, isTrue);
    });

    test('kalibracja przeżywa zapis i odczyt', () {
      final profile = RecoveryCalibrationProfile.empty.withMuscle(
        BodyMuscle.quads,
        MuscleRecoveryCalibration(
            tauScale: 1.12, observations: 7, lastUpdated: now),
      );
      final restored =
          RecoveryCalibrationProfile.fromJson(profile.toJson());
      expect(restored.forMuscle(BodyMuscle.quads).observations, 7);
      expect(restored.forMuscle(BodyMuscle.quads).tauScale, closeTo(1.12, 0.001));
    });

    test('kalibracja realnie zmienia tempo regeneracji', () {
      final logs = [
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 20))),
      ];
      final baseline = compute(logs)[BodyMuscle.chest]!.recoveryPercent!;
      final slower = compute(
        logs,
        calibration: RecoveryCalibrationProfile.empty.withMuscle(
          BodyMuscle.chest,
          const MuscleRecoveryCalibration(tauScale: 1.35, observations: 40),
        ),
      )[BodyMuscle.chest]!
          .recoveryPercent!;
      expect(slower, lessThan(baseline));
    });
  });

  group('Migawki stanu (spec 25)', () {
    test('migawka zapisuje się i odczytuje bez utraty składowych', () {
      final map = compute([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 3))),
      ]);
      final snapshot = RecoverySnapshot.from(
        map[BodyMuscle.chest]!.readiness!,
        timestamp: now,
      );
      final restored = RecoverySnapshot.fromJson(snapshot.toJson());
      expect(restored, isNotNull);
      expect(restored!.muscle, BodyMuscle.chest);
      expect(restored.readiness, closeTo(snapshot.readiness, 0.01));
      expect(restored.localFatigue, closeTo(snapshot.localFatigue, 0.01));
      expect(restored.confidence, closeTo(snapshot.confidence, 0.01));
    });
  });

  group('Prognoza czasu do wysokiej gotowości', () {
    test('świeżo zmęczona partia ma dodatni czas, wypoczęta zerowy', () {
      final fresh = compute([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(minutes: 20))),
      ])[BodyMuscle.chest]!;
      expect(fresh.estimatedHoursRemaining, greaterThan(0));

      final old = compute([
        _log(exerciseId: 'bench', at: now.subtract(const Duration(hours: 80))),
      ])[BodyMuscle.chest]!;
      expect(old.estimatedHoursRemaining, 0);
    });
  });
}
