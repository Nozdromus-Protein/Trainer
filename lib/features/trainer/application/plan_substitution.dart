/// Podmiana zaplanowanego zestawu na własny (czysty Dart).
///
/// Etap: „Mój zestaw zamiast bazowego w dzisiejszym planie".
///
/// Rozkład tygodnia przypisuje dniom OBSZARY ([TrainingFocusArea]) — dzień
/// brzucha, dzień klatki, dzień nóg. Użytkownik chce móc podstawić pod taki
/// dzień własny zestaw, ale WYŁĄCZNIE gdy ten zestaw robi to samo:
/// brzuch za brzuch, klatka za klatkę. Inaczej podmiana po cichu zmieniłaby
/// cały plan tygodnia i rozjechała regenerację.
///
/// Ten moduł liczy zgodność i zwraca czytelny werdykt — decyzję o podmianie
/// podejmuje użytkownik, a zapis robi warstwa aplikacji.
library;

import '../domain/equipment_profile.dart';
import '../domain/exercise.dart';
import '../domain/muscle_recovery.dart';
import '../domain/workout_plan.dart';
import 'equipment_program_filter.dart';

/// Na ile zestaw nadaje się do podmiany pod zaplanowany obszar.
enum PlanSubstitutionFit {
  /// Zestaw robi dokładnie to, co zaplanowany dzień.
  perfect('Pasuje do dzisiejszego planu'),

  /// Zestaw pokrywa obszar, ale ma zauważalny dodatek spoza niego.
  partial('Pasuje częściowo — ma pracę spoza dzisiejszego obszaru'),

  /// Zestaw trenuje co innego — podmiana zmieniłaby plan.
  incompatible('Nie pasuje — trenuje inne partie niż dzisiejszy plan');

  const PlanSubstitutionFit(this.label);

  final String label;

  bool get allowsSubstitution => this != PlanSubstitutionFit.incompatible;
}

/// Werdykt podmiany: dopasowanie + wszystko, co użytkownik powinien wiedzieć.
class PlanSubstitutionVerdict {
  const PlanSubstitutionVerdict({
    required this.fit,
    required this.coveredMuscles,
    required this.missingMuscles,
    required this.foreignMuscles,
    required this.coverageRatio,
    required this.focusRatio,
    this.warnings = const <String>[],
    this.notes = const <String>[],
  });

  final PlanSubstitutionFit fit;

  /// Partie definiujące obszar, które zestaw realnie trenuje.
  final Set<BodyMuscle> coveredMuscles;

  /// Partie obszaru, których w zestawie brakuje.
  final Set<BodyMuscle> missingMuscles;

  /// Partie spoza obszaru, które zestaw dokłada.
  final Set<BodyMuscle> foreignMuscles;

  /// Ile z partii obszaru zestaw pokrywa (0..1).
  final double coverageRatio;

  /// Jaka część pracy zestawu trafia w zaplanowany obszar (0..1).
  final double focusRatio;

  /// Rzeczy blokujące albo wymagające uwagi (sprzęt, ograniczenia, regeneracja).
  final List<String> warnings;

  /// Neutralne spostrzeżenia (np. „zestaw ma więcej serii niż plan").
  final List<String> notes;

  bool get canSubstitute => fit.allowsSubstitution;
}

/// Partie GŁÓWNE trenowane przez zestaw, z liczbą serii przypadającą na każdą.
///
/// Liczy się wyłącznie rola [MuscleRole.primary] — triceps pracuje przy
/// wyciskaniu, ale to nie czyni z zestawu klatki „zestawu na triceps".
Map<BodyMuscle, int> planPrimaryMuscleLoad(
  WorkoutPlan plan, {
  required Exercise Function(String id) resolve,
  int? onlyDayIndex,
}) {
  final load = <BodyMuscle, int>{};
  for (var index = 0; index < plan.days.length; index++) {
    if (onlyDayIndex != null && index != onlyDayIndex) continue;
    for (final item in plan.days[index].items) {
      final exercise = resolve(item.exerciseId);
      final sets = item.sets <= 0 ? 1 : item.sets;
      for (final impact in exercise.effectiveMuscleImpacts) {
        if (impact.role != MuscleRole.primary) continue;
        load[impact.muscleGroup] = (load[impact.muscleGroup] ?? 0) + sets;
      }
    }
  }
  return load;
}

/// Ocenia, czy [plan] może zastąpić zaplanowany dzień o partiach
/// [areaSignature] (partie DEFINIUJĄCE obszar, np. sam brzuch dla dnia core).
///
/// [otherAreaSignatures] to partie definiujące POZOSTAŁE obszary rozkładu —
/// po nich poznajemy, że zestaw „wychodzi" poza dzisiejszy dzień.
PlanSubstitutionVerdict evaluatePlanSubstitution({
  required WorkoutPlan plan,
  required Set<BodyMuscle> areaSignature,
  required Exercise Function(String id) resolve,
  Set<BodyMuscle> otherAreaSignatures = const <BodyMuscle>{},
  EquipmentProfile equipment = const EquipmentProfile(),
  LimitationProfile limitations = const LimitationProfile(),
  Map<BodyMuscle, MuscleRecoveryState> recovery =
      const <BodyMuscle, MuscleRecoveryState>{},
  int? onlyDayIndex,
}) {
  final load = planPrimaryMuscleLoad(
    plan,
    resolve: resolve,
    onlyDayIndex: onlyDayIndex,
  );
  final warnings = <String>[];
  final notes = <String>[];

  if (load.isEmpty || areaSignature.isEmpty) {
    return PlanSubstitutionVerdict(
      fit: PlanSubstitutionFit.incompatible,
      coveredMuscles: const <BodyMuscle>{},
      missingMuscles: areaSignature,
      foreignMuscles: const <BodyMuscle>{},
      coverageRatio: 0,
      focusRatio: 0,
      warnings: [
        if (load.isEmpty) 'Zestaw nie ma jeszcze żadnych ćwiczeń.',
      ],
    );
  }

  final covered = <BodyMuscle>{};
  final foreign = <BodyMuscle>{};
  var areaSets = 0;
  var totalSets = 0;
  load.forEach((muscle, sets) {
    totalSets += sets;
    if (areaSignature.contains(muscle)) {
      covered.add(muscle);
      areaSets += sets;
    } else if (otherAreaSignatures.contains(muscle)) {
      // Partia definiująca INNY dzień rozkładu — to ona psuje podmianę.
      foreign.add(muscle);
    }
  });
  final missing = areaSignature.difference(covered);

  final coverageRatio =
      areaSignature.isEmpty ? 0.0 : covered.length / areaSignature.length;
  final focusRatio = totalSets == 0 ? 0.0 : areaSets / totalSets;

  // --- Dopasowanie ---
  final PlanSubstitutionFit fit;
  if (covered.isEmpty || focusRatio < 0.5) {
    fit = PlanSubstitutionFit.incompatible;
  } else if (coverageRatio >= 0.99 && foreign.isEmpty && focusRatio >= 0.8) {
    fit = PlanSubstitutionFit.perfect;
  } else {
    fit = PlanSubstitutionFit.partial;
  }

  // --- Ostrzeżenia praktyczne (nie blokują, informują) ---
  final owned = equipment.resolveOwned();
  final missingEquipment = <String>{};
  final limitationHits = <String>{};
  for (var index = 0; index < plan.days.length; index++) {
    if (onlyDayIndex != null && index != onlyDayIndex) continue;
    for (final item in plan.days[index].items) {
      final exercise = resolve(item.exerciseId);
      if (!isExerciseAvailable(exercise, owned)) {
        missingEquipment.add(exercise.name);
      }
      if (exerciseViolatesLimitation(exercise, limitations)) {
        limitationHits.add(exercise.name);
      }
    }
  }
  if (missingEquipment.isNotEmpty) {
    warnings.add('Wymaga sprzętu spoza profilu: '
        '${missingEquipment.take(3).join(', ')}.');
  }
  if (limitationHits.isNotEmpty) {
    warnings.add('Koliduje z ograniczeniami: '
        '${limitationHits.take(3).join(', ')}.');
  }
  if (recovery.isNotEmpty) {
    for (final muscle in covered) {
      final state = recovery[muscle];
      final percent = state?.recoveryPercent;
      if (state == null || !state.hasData || percent == null) continue;
      if (percent < 55) {
        warnings.add('${muscle.label}: ${percent.round()}% regeneracji — '
            'rozważ niższą intensywność.');
      }
    }
  }

  // --- Notatki ---
  if (missing.isNotEmpty) {
    notes.add('Nie obejmuje: '
        '${missing.map((m) => m.label.toLowerCase()).join(', ')}.');
  }
  if (foreign.isNotEmpty) {
    notes.add('Dokłada partie spoza dzisiejszego dnia: '
        '${foreign.map((m) => m.label.toLowerCase()).join(', ')}.');
  }
  notes.add('${(focusRatio * 100).round()}% pracy zestawu trafia '
      'w dzisiejszy obszar.');

  return PlanSubstitutionVerdict(
    fit: fit,
    coveredMuscles: covered,
    missingMuscles: missing,
    foreignMuscles: foreign,
    coverageRatio: coverageRatio,
    focusRatio: focusRatio,
    warnings: warnings,
    notes: notes,
  );
}
