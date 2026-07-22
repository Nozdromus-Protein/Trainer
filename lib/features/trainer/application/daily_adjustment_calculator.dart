import 'dart:math' as math;

import '../domain/activity_credit.dart';
import '../domain/daily_adjustment.dart';
import '../domain/health_connect_snapshot.dart';
import '../domain/training_impact.dart';

/// Współczynniki zaufania dla SPORTU — jedno miejsce, konfigurowalne.
///
/// To nie jest twierdzenie o rzeczywistym spalaniu, tylko korekta chroniąca
/// przed zawyżaniem przez zegarek, podwójnym liczeniem (sesja + aktywne kcal
/// + kroki) i kompensacją aktywności w ciągu dnia. Te same wartości ma
/// Licznik Kalorii (`SportCreditFactors`), żeby obie aplikacje pokazywały
/// identyczną liczbę.
class SportCreditFactors {
  const SportCreditFactors({
    this.strength = 0.60,
    this.running = 0.70,
    this.cycling = 0.65,
    this.otherCardio = 0.60,
    this.measuredWalk = 0.60,
  });

  static const SportCreditFactors defaults = SportCreditFactors();

  final double strength;
  final double running;
  final double cycling;
  final double otherCardio;
  final double measuredWalk;
}

/// Kcal ze sportu po korekcie zaufania. Zwykłe kroki i praca NIE wchodzą.
int creditedSportKcal({
  int strengthKcal = 0,
  int runKcal = 0,
  int walkKcal = 0,
  int otherCardioKcal = 0,
  SportCreditFactors factors = SportCreditFactors.defaults,
}) {
  final total = math.max(0, strengthKcal) * factors.strength +
      math.max(0, runKcal) * factors.running +
      math.max(0, walkKcal) * factors.measuredWalk +
      math.max(0, otherCardioKcal) * factors.otherCardio;
  if (!total.isFinite || total <= 0) return 0;
  return total.round();
}

/// Liczy dzienną korektę aktywności ([TrainerDailyAdjustment]) na podstawie:
///  - zaliczonych kredytów aktywności (już po deduplikacji bieg/chód/sesje),
///  - snapshotu Health Connect (kroki, dystans, aktywne kcal),
///  - wpływów treningów ([TrainingImpact] — woda/białko z sesji Trainera).
///
/// Zasady antyduplikacyjne:
///  - kcal aktywności pochodzą wyłącznie z ZALICZONYCH kredytów
///    (odrzucone duplikaty mają 0 kcal),
///  - kroki pokryte przez zarejestrowany bieg/chód są odejmowane od kroków
///    z Health Connect przed szacowaniem kcal z kroków,
///  - część zdrowotna to max(aktywne kcal z zegarka, suma szacunków),
///    bo zegarek w aktywnych kcal ma już kroki, biegi i chód.
TrainerDailyAdjustment buildTrainerDailyAdjustment({
  required DateTime day,
  required List<ActivityCreditDecision> decisions,
  required List<TrainingImpact> impactsForDay,
  TrainerHealthConnectSnapshot? snapshot,
  double bodyWeightKg = 100,
  String workIntensity = 'none',
  double workHoursPerDay = 0,
  List<int> workWeekdays = const <int>[],
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final safeWeight =
      bodyWeightKg.isFinite ? bodyWeightKg.clamp(40.0, 220.0) : 100.0;

  var workoutKcal = 0;
  var runKcal = 0;
  var walkKcal = 0;
  var otherKcal = 0;
  var creditedStepsEntryKcal = 0;
  var coveredSteps = 0;
  var entryMinutes = 0;
  var entryDistanceKm = 0.0;
  var sweatLossMl = 0;
  final includedKeys = <String>[];

  for (final decision in decisions) {
    if (!decision.includedInCalories) continue;
    final entry = decision.entry;
    includedKeys.add(entry.deduplicationKey);
    entryMinutes += math.max(0, entry.durationMin);
    entryDistanceKm += math.max(0.0, entry.distanceKm);
    sweatLossMl += math.max(0, entry.sweatLossMl);
    final kcal = math.max(0, entry.estimatedKcal);
    switch (entry.type) {
      case TrainerActivityType.strengthTraining:
        workoutKcal += kcal;
        break;
      case TrainerActivityType.run:
        runKcal += kcal;
        coveredSteps += math.max(0, entry.steps);
        break;
      case TrainerActivityType.measuredWalk:
        walkKcal += kcal;
        coveredSteps += math.max(0, entry.steps);
        break;
      case TrainerActivityType.ordinaryStepsWalk:
        creditedStepsEntryKcal += kcal;
        coveredSteps += math.max(0, entry.steps);
        break;
      case TrainerActivityType.bike:
      case TrainerActivityType.otherCardio:
        otherKcal += kcal;
        break;
    }
  }

  // Kroki i dystans dnia — z Health Connect, z bezpiecznym parsowaniem.
  final snapshotSteps = math.max(0, snapshot?.steps ?? 0);
  final snapshotDistance = math.max(0.0, snapshot?.distanceKm ?? 0.0);
  final healthActiveKcal = math.max(0, (snapshot?.activeKcal ?? 0).round());

  // Szacunek kcal ze zwykłych kroków: ok. 0.00045 kcal na krok i kg masy
  // (10 000 kroków ≈ 315 kcal przy 70 kg). Jeżeli istnieje ręczny wpis
  // "chód zwykły z kroków" z kcal, używamy go zamiast szacunku.
  final effectiveSteps = math.max(0, snapshotSteps - coveredSteps);
  final estimatedStepsKcal = (effectiveSteps * 0.00045 * safeWeight).round();
  final stepsKcal =
      creditedStepsEntryKcal > 0 ? creditedStepsEntryKcal : estimatedStepsKcal;

  // Praca jest wartością netto ponad spoczynek i pokrywa się ze zwykłymi
  // krokami, dlatego wybieramy wyższy szacunek zamiast je sumować.
  final workMet = switch (workIntensity.trim().toLowerCase()) {
    'sedentary' => 1.4,
    'light' => 1.8,
    'moderate' => 2.4,
    'heavy' => 3.2,
    _ => 1.0,
  };
  final safeWorkHours =
      workHoursPerDay.isFinite ? workHoursPerDay.clamp(0.0, 16.0) : 0.0;
  final workKcal =
      workWeekdays.contains(day.weekday) && workMet > 1 && safeWorkHours > 0
          ? ((workMet - 1.0) * safeWeight * safeWorkHours).round()
          : 0;
  final generalMovementKcal = math.max(stepsKcal, workKcal);

  // ── PODZIAŁ NA DWIE PULE ────────────────────────────────────────────────
  //
  // BAZA (praca + zwykłe kroki) to energia, którą Licznik Kalorii ma już
  // zaszytą w bazowym zerze — wysyłamy ją wyłącznie informacyjnie. Doliczanie
  // jej do celu dnia oznaczało, że 5 godzin sprzątania podbijało cel drugi raz
  // (stąd „korekta +867 kcal" w dniu bez ciężkiego treningu).
  //
  // SPORT (trening siłowy, bieg, zmierzony chód, inne cardio) to jedyna część,
  // którą wolno doliczyć — po korekcie zaufania z [kSportCreditFactors].
  final baselineActivityKcal = generalMovementKcal;
  final sportKcal = creditedSportKcal(
    strengthKcal: workoutKcal,
    runKcal: runKcal,
    walkKcal: walkKcal,
    otherCardioKcal: otherKcal,
  );

  // Health Connect active calories may already contain the strength workout.
  // One max across the whole day prevents workout/watch double counting.
  final estimatedHealthKcal =
      generalMovementKcal + runKcal + walkKcal + otherKcal;
  final totalAdjustmentKcal =
      math.max(healthActiveKcal, workoutKcal + estimatedHealthKcal);
  final healthDerivedKcal = math.max(0, totalAdjustmentKcal - workoutKcal);

  // Dodatki z samych treningów Trainera (Licznik Kalorii ich nie widzi
  // we własnym Health Connect, więc może je doliczać zawsze).
  var workoutWaterMl = 0;
  var workoutProteinG = 0;
  for (final impact in impactsForDay) {
    workoutWaterMl += math.max(0, impact.suggestedExtraWaterMl);
    workoutProteinG += math.max(0, impact.suggestedExtraProteinG);
  }
  workoutWaterMl = workoutWaterMl.clamp(0, 2000).toInt();
  workoutProteinG = workoutProteinG.clamp(0, 60).toInt();
  final workoutCarbsG =
      workoutKcal >= 150 ? (workoutKcal / 8).round().clamp(0, 120).toInt() : 0;

  // Dodatki z aktywności dziennej (kroki/bieg/chód): ~0.7 ml wody na kcal,
  // ale jeżeli aktywności mają oszacowaną utratę wody przez pot (czas ×
  // intensywność z tętna × masa ciała), używamy większej z wartości —
  // bieg 11 km z potem ~1500 ml realnie podnosi cel nawodnienia.
  final kcalBasedWaterMl = (healthDerivedKcal * 0.7).round();
  final healthWaterMl =
      math.max(kcalBasedWaterMl, sweatLossMl).clamp(0, 2200).toInt();
  final activityMinutes = math.max(entryMinutes, snapshot?.workoutMinutes ?? 0);
  final meaningfulActivity = healthDerivedKcal >= 250 || activityMinutes >= 25;
  final healthCarbsG = meaningfulActivity
      ? (healthDerivedKcal / 8.5).round().clamp(0, 130).toInt()
      : 0;

  final extraWaterMl = (workoutWaterMl + healthWaterMl).clamp(0, 2500).toInt();
  final extraCarbsG = (workoutCarbsG + healthCarbsG).clamp(0, 200).toInt();
  final extraProteinG = workoutProteinG;

  final sources = <String>[
    if (workoutKcal > 0) 'trainer_workout',
    if (stepsKcal > 0) 'trainer_steps',
    if (runKcal > 0) 'trainer_run',
    if (walkKcal > 0) 'trainer_walk',
    if (workKcal > 0) 'trainer_work_fallback',
    if (otherKcal > 0) 'trainer_other',
    if (snapshot != null && snapshot.hasAnyDailyData) 'health_connect',
  ];

  String dataStatus;
  if (snapshot == null) {
    dataStatus = includedKeys.isEmpty
        ? TrainerDailyAdjustment.statusNone
        : TrainerDailyAdjustment.statusPartial;
  } else if (!snapshot.permissionsGranted ||
      snapshot.missingData.isNotEmpty ||
      !snapshot.isAvailable) {
    dataStatus = TrainerDailyAdjustment.statusPartial;
  } else {
    dataStatus = TrainerDailyAdjustment.statusFull;
  }

  String two(int value) => value.toString().padLeft(2, '0');
  final dateKey = '${day.year}-${two(day.month)}-${two(day.day)}';

  return TrainerDailyAdjustment(
    id: 'daily_adjustment_$dateKey',
    date: DateTime(day.year, day.month, day.day),
    workoutKcal: workoutKcal,
    stepsKcal: stepsKcal,
    runKcal: runKcal,
    walkKcal: walkKcal,
    workKcal: workKcal,
    otherKcal: otherKcal,
    healthActiveKcal: healthActiveKcal,
    healthDerivedKcal: healthDerivedKcal,
    totalAdjustmentKcal: totalAdjustmentKcal,
    sportKcal: sportKcal,
    baselineActivityKcal: baselineActivityKcal,
    extraWaterMl: extraWaterMl,
    extraCarbsG: extraCarbsG,
    extraProteinG: extraProteinG,
    workoutExtraWaterMl: workoutWaterMl,
    workoutExtraCarbsG: workoutCarbsG,
    workoutExtraProteinG: workoutProteinG,
    steps: snapshotSteps,
    distanceKm: snapshotDistance > 0 ? snapshotDistance : entryDistanceKm,
    activityMinutes: activityMinutes,
    sources: sources,
    dataStatus: dataStatus,
    includedKeys: includedKeys,
    createdAt: reference,
    updatedAt: reference,
  );
}
