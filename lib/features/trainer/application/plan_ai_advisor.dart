/// Doradca AI dla istniejących zestawów (czysty Dart, bez Fluttera).
///
/// Etap: „Analiza AI istniejących zestawów bazowych" + tryb „ręcznie z pomocą AI".
///
/// TWARDA ZASADA CAŁEGO MODUŁU: analiza NICZEGO nie zapisuje.
/// [analyzePlanForUser] zwraca listę PROPOZYCJI ([PlanChangeProposal]) —
/// dopiero [applyPlanProposals] (wywołane po kliknięciu użytkownika) buduje
/// nową wersję zestawu. Ćwiczenia zablokowane przez użytkownika
/// ([lockedExerciseIds]) nigdy nie są usuwane ani zamieniane, a AI działa
/// wyłącznie w zakresach, które użytkownik zaznaczył ([scopes]).
library;

import '../domain/equipment_profile.dart';
import '../domain/exercise.dart';
import '../domain/muscle_recovery.dart';
import '../domain/trainer_enums.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_volume_limits.dart';
import 'equipment_program_filter.dart';
import 'plan_quality_analyzer.dart';

/// Rodzaj analizy zestawu.
enum PlanAnalysisMode {
  /// Stałe dopasowanie zestawu do profilu (zapisywane jako nowy wariant).
  permanent(
    'permanent',
    'Analiza stałego dopasowania',
    'AI dopasowuje cały zestaw do Twojego profilu i zapisuje go jako '
        'spersonalizowany wariant.',
  ),

  /// Jednorazowy wariant na dzisiaj (regeneracja, czas, sprzęt na dziś).
  today(
    'today',
    'Analiza na dzisiaj',
    'AI sprawdza, czy zestaw pasuje do dzisiejszego stanu — bez trwałej '
        'zmiany konstrukcji.',
  );

  const PlanAnalysisMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;
}

/// Rodzaj proponowanej zmiany.
enum PlanChangeKind {
  addExercise('Dodaj ćwiczenie'),
  removeExercise('Usuń ćwiczenie'),
  swapExercise('Zamień ćwiczenie'),
  reorder('Zmień kolejność'),
  adjustSets('Zmień liczbę serii'),
  adjustReps('Zmień zakres powtórzeń'),
  adjustDuration('Zmień czas ćwiczenia'),
  adjustRest('Zmień długość przerwy');

  const PlanChangeKind(this.label);

  final String label;
}

/// Pojedyncza propozycja zmiany — zawsze z powodem i przewidywanym wpływem.
class PlanChangeProposal {
  const PlanChangeProposal({
    required this.id,
    required this.kind,
    required this.dayIndex,
    required this.title,
    required this.reason,
    this.exerciseId = '',
    this.replacementExerciseId = '',
    this.newItem,
    this.newSets = 0,
    this.newReps = 0,
    this.newDurationSec = 0,
    this.newRestSeconds = 0,
    this.newOrder = const <String>[],
    this.impact = '',
    this.isSafe = false,
    this.scope,
  });

  /// Stabilny identyfikator propozycji (zaznaczanie, akceptacja pojedynczo).
  final String id;
  final PlanChangeKind kind;

  /// Dzień, którego dotyczy zmiana.
  final int dayIndex;
  final String title;
  final String reason;

  /// Ćwiczenie, którego zmiana dotyczy (usuwane / zamieniane / strojone).
  final String exerciseId;

  /// Dla [PlanChangeKind.swapExercise] — ćwiczenie wchodzące w miejsce starego.
  final String replacementExerciseId;

  /// Dla [PlanChangeKind.addExercise] — gotowa pozycja do wstawienia.
  final PlanItem? newItem;

  final int newSets;
  final int newReps;
  final int newDurationSec;
  final int newRestSeconds;

  /// Dla [PlanChangeKind.reorder] — docelowa kolejność identyfikatorów ćwiczeń.
  final List<String> newOrder;

  /// Przewidywany wpływ (objętość, czas, regeneracja) — pokazywany na karcie.
  final String impact;

  /// Czy zmiana jest „bezpieczna" — nie usuwa ćwiczeń użytkownika i nie zmienia
  /// charakteru zestawu. Zasila przycisk „Zastosuj wszystkie bezpieczne zmiany".
  final bool isSafe;

  /// Zakres pomocy AI, z którego wynika ta propozycja.
  final AiAssistanceScope? scope;

  bool get removesUserExercise =>
      kind == PlanChangeKind.removeExercise ||
      kind == PlanChangeKind.swapExercise;
}

/// Wynik analizy zestawu: raport jakości + propozycje + podstawa decyzji.
class PlanAnalysisResult {
  const PlanAnalysisResult({
    required this.mode,
    required this.report,
    required this.proposals,
    required this.basis,
    required this.confidence,
    this.limitedAccuracyReason = '',
  });

  final PlanAnalysisMode mode;
  final PlanQualityReport report;
  final List<PlanChangeProposal> proposals;

  /// Na jakich danych oparto analizę (poziom, cel, sprzęt, regeneracja…).
  final List<String> basis;
  final double confidence;

  /// Wypełnione, gdy brakuje danych i dokładność jest ograniczona.
  final String limitedAccuracyReason;

  List<PlanChangeProposal> get safeProposals =>
      proposals.where((p) => p.isSafe).toList();

  bool get hasProposals => proposals.isNotEmpty;
}

/// Porównanie zestawu przed i po zastosowaniu zmian.
class PlanDiff {
  const PlanDiff({
    required this.before,
    required this.after,
    required this.addedExercises,
    required this.removedExercises,
    required this.swappedExercises,
    required this.setChanges,
    required this.reorderedDays,
  });

  final PlanQualityReport before;
  final PlanQualityReport after;
  final List<String> addedExercises;
  final List<String> removedExercises;

  /// Pary „stare → nowe".
  final List<(String, String)> swappedExercises;

  /// Opisy zmian serii/powtórzeń/przerw.
  final List<String> setChanges;
  final List<String> reorderedDays;

  int get exerciseDelta => after.totalExercises - before.totalExercises;
  int get setDelta => after.totalSets - before.totalSets;
  int get minuteDelta => after.estimatedMinutes - before.estimatedMinutes;
  int get scoreDelta => after.score - before.score;
}

/// Analiza zestawu i przygotowanie propozycji.
///
/// [fromDayIndex] chroni rozpoczęte programy: dni wcześniejsze (ukończone)
/// nigdy nie trafiają do propozycji. [lockedExerciseIds] to ćwiczenia
/// oznaczone przez użytkownika jako „Nie zmieniaj tego ćwiczenia".
PlanAnalysisResult analyzePlanForUser(
  WorkoutPlan plan, {
  required Exercise Function(String id) resolve,
  required List<Exercise> library_,
  PlanAnalysisMode mode = PlanAnalysisMode.permanent,
  Set<AiAssistanceScope> scopes = const <AiAssistanceScope>{},
  Set<String> lockedExerciseIds = const <String>{},
  EquipmentProfile equipment = const EquipmentProfile(),
  LimitationProfile limitations = const LimitationProfile(),
  String level = '',
  String goal = '',
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
  VolumeLimitsConfig volumeLimits = VolumeLimitsConfig.standard,
  Map<BodyMuscle, MuscleRecoveryState> recovery =
      const <BodyMuscle, MuscleRecoveryState>{},
  int availableMinutes = 0,
  List<MuscleGroup> priorityMuscles = const <MuscleGroup>[],
  List<String> excludedExerciseIds = const <String>[],
  bool hasHistory = true,
  int fromDayIndex = 0,
}) {
  // Pusty zbiór zakresów = użytkownik nie zawęził niczego → analizujemy całość.
  final active = scopes.isEmpty ? AiAssistanceScope.values.toSet() : scopes;
  final owned = equipment.resolveOwned();
  final excluded = excludedExerciseIds.toSet();

  final report = analyzePlanQuality(
    plan,
    resolve: resolve,
    equipment: equipment,
    limitations: limitations,
    level: level,
    goal: goal,
    intensity: intensity,
    volumeLimits: volumeLimits,
    recovery: recovery,
    availableMinutes: availableMinutes,
    priorityMuscles: priorityMuscles,
    hasHistory: hasHistory,
  );

  final proposals = <PlanChangeProposal>[];
  var counter = 0;
  String nextId(String prefix) => '${prefix}_${counter++}';

  for (var dayIndex = fromDayIndex;
      dayIndex < plan.days.length;
      dayIndex++) {
    final day = plan.days[dayIndex];
    if (day.items.isEmpty) continue;
    final stats = report.dayStats[dayIndex];

    // --- Zgodność ze sprzętem / ograniczeniami → ZAMIANA (nie usunięcie) ---
    if (active.contains(AiAssistanceScope.equipmentCheck) ||
        active.contains(AiAssistanceScope.limitationCheck) ||
        active.contains(AiAssistanceScope.substitutions)) {
      for (final item in day.items) {
        if (lockedExerciseIds.contains(item.exerciseId)) continue;
        final exercise = resolve(item.exerciseId);
        final missingEquipment = !isExerciseAvailable(exercise, owned);
        final violatesLimit =
            exerciseViolatesLimitation(exercise, limitations);
        if (!missingEquipment && !violatesLimit) continue;

        final substituteId = bestSubstituteId(
          exercise,
          owned,
          limitations,
          resolve,
          exclude: {
            ...excluded,
            ...day.items.map((entry) => entry.exerciseId),
          },
        );
        if (substituteId == null) continue;
        final substitute = resolve(substituteId);
        proposals.add(PlanChangeProposal(
          id: nextId('swap'),
          kind: PlanChangeKind.swapExercise,
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          replacementExerciseId: substituteId,
          title: 'Zamień „${exercise.name}" na „${substitute.name}"',
          reason: missingEquipment
              ? 'Profil nie zawiera sprzętu potrzebnego do ćwiczenia '
                  '„${exercise.name}" (${exercise.equipment}).'
              : 'Ćwiczenie „${exercise.name}" koliduje z Twoimi '
                  'ograniczeniami treningowymi.',
          impact: 'Ta sama partia (${primaryMuscleGroupOf(substitute).label}), '
              'sprzęt: ${substitute.equipment}.',
          isSafe: false,
          scope: missingEquipment
              ? AiAssistanceScope.equipmentCheck
              : AiAssistanceScope.limitationCheck,
        ));
      }
    }

    // --- Zbędne / powtarzające się ćwiczenia → USUNIĘCIE ---
    if (active.contains(AiAssistanceScope.removeRedundant)) {
      final seen = <String>{};
      for (final item in day.items) {
        if (!seen.add(item.exerciseId)) {
          if (lockedExerciseIds.contains(item.exerciseId)) continue;
          final exercise = resolve(item.exerciseId);
          proposals.add(PlanChangeProposal(
            id: nextId('remove'),
            kind: PlanChangeKind.removeExercise,
            dayIndex: dayIndex,
            exerciseId: item.exerciseId,
            title: 'Usuń powtórzone „${exercise.name}"',
            reason: 'To ćwiczenie występuje w dniu „${day.title}" dwa razy.',
            impact: '−${item.sets} serii, '
                '−${estimatePlanItemMinutes(item, exercise)} min.',
            isSafe: false,
            scope: AiAssistanceScope.removeRedundant,
          ));
        }
      }
      // Nadmiar objętości na jedną partię.
      stats.setsByMuscle.forEach((group, sets) {
        if (!kLimitedMuscleGroups.contains(group)) return;
        final limits = volumeLimitsFor(
          group,
          level: level,
          goal: goal,
          config: volumeLimits,
          intensity: intensity,
        );
        if (sets <= limits.maxWorkingSets) return;
        // Usuwamy NAJMNIEJ wartościowy ruch tej partii — izolację z końca dnia.
        PlanItem? candidate;
        for (final item in day.items.reversed) {
          if (lockedExerciseIds.contains(item.exerciseId)) continue;
          final exercise = resolve(item.exerciseId);
          if (primaryMuscleGroupOf(exercise) != group) continue;
          if (movementPatternOf(exercise) == MovementPattern.core) continue;
          candidate = item;
          break;
        }
        if (candidate == null) return;
        final exercise = resolve(candidate.exerciseId);
        proposals.add(PlanChangeProposal(
          id: nextId('remove'),
          kind: PlanChangeKind.removeExercise,
          dayIndex: dayIndex,
          exerciseId: candidate.exerciseId,
          title: 'Usuń „${exercise.name}"',
          reason: 'W dniu „${day.title}" ${group.label.toLowerCase()} dostaje '
              '$sets serii przy limicie ${limits.maxWorkingSets}.',
          impact: '−${candidate.sets} serii dla '
              '${group.label.toLowerCase()}.',
          isSafe: false,
          scope: AiAssistanceScope.removeRedundant,
        ));
      });
    }

    // --- Serie / powtórzenia / przerwy ---
    for (final item in day.items) {
      final exercise = resolve(item.exerciseId);
      final group = primaryMuscleGroupOf(exercise);
      final limits = volumeLimitsFor(
        group,
        level: level,
        goal: goal,
        config: volumeLimits,
        intensity: intensity,
      );
      final entryType = exercise.entryType;

      if (active.contains(AiAssistanceScope.setsAndReps)) {
        if (item.sets < limits.sets.min) {
          proposals.add(PlanChangeProposal(
            id: nextId('sets'),
            kind: PlanChangeKind.adjustSets,
            dayIndex: dayIndex,
            exerciseId: item.exerciseId,
            newSets: limits.sets.min,
            title: 'Zwiększ serie w „${exercise.name}" '
                'do ${limits.sets.min}',
            reason: 'Przy intensywności „${intensity.label.toLowerCase()}" '
                'minimum dla ${group.label.toLowerCase()} to '
                '${limits.sets.min} serii na ćwiczenie.',
            impact: '+${limits.sets.min - item.sets} serii.',
            isSafe: true,
            scope: AiAssistanceScope.setsAndReps,
          ));
        } else if (item.sets > limits.sets.max) {
          proposals.add(PlanChangeProposal(
            id: nextId('sets'),
            kind: PlanChangeKind.adjustSets,
            dayIndex: dayIndex,
            exerciseId: item.exerciseId,
            newSets: limits.sets.max,
            title: 'Zmniejsz serie w „${exercise.name}" '
                'do ${limits.sets.max}',
            reason: 'To powyżej górnej granicy objętości dla '
                '${group.label.toLowerCase()}.',
            impact: '−${item.sets - limits.sets.max} serii.',
            isSafe: true,
            scope: AiAssistanceScope.setsAndReps,
          ));
        }

        if (entryType.showsReps && item.reps > 0) {
          final target = item.reps.clamp(limits.reps.min, limits.reps.max);
          if (target != item.reps) {
            proposals.add(PlanChangeProposal(
              id: nextId('reps'),
              kind: PlanChangeKind.adjustReps,
              dayIndex: dayIndex,
              exerciseId: item.exerciseId,
              newReps: target,
              title: 'Ustaw $target powtórzeń w „${exercise.name}"',
              reason: 'Cel „$goal" celuje w zakres '
                  '${limits.reps.min}–${limits.reps.max} powtórzeń.',
              impact: 'Zakres powtórzeń zgodny ze strategią.',
              isSafe: true,
              scope: AiAssistanceScope.setsAndReps,
            ));
          }
        }
      }

      if (active.contains(AiAssistanceScope.rest)) {
        final recommended = _recommendedRest(exercise, goal);
        if ((item.restSeconds - recommended).abs() >= 30) {
          proposals.add(PlanChangeProposal(
            id: nextId('rest'),
            kind: PlanChangeKind.adjustRest,
            dayIndex: dayIndex,
            exerciseId: item.exerciseId,
            newRestSeconds: recommended,
            title: 'Ustaw przerwę $recommended s w „${exercise.name}"',
            reason: item.restSeconds > recommended
                ? 'Przerwa ${item.restSeconds} s wydłuża trening bez korzyści '
                    'przy tym celu.'
                : 'Przerwa ${item.restSeconds} s jest za krótka, żeby '
                    'utrzymać jakość serii.',
            impact: 'Zmiana czasu dnia o około '
                '${(((recommended - item.restSeconds) * item.sets) / 60).round()} min.',
            isSafe: true,
            scope: AiAssistanceScope.rest,
          ));
        }
      }
    }

    // --- Kolejność ćwiczeń ---
    if (active.contains(AiAssistanceScope.exerciseOrder) &&
        day.items.length > 2) {
      final desired = _preferredOrder(day, resolve);
      final current = day.items.map((item) => item.exerciseId).toList();
      if (!_sameOrder(desired, current)) {
        proposals.add(PlanChangeProposal(
          id: nextId('order'),
          kind: PlanChangeKind.reorder,
          dayIndex: dayIndex,
          newOrder: desired,
          title: 'Popraw kolejność w dniu „${day.title}"',
          reason: 'Duże ruchy złożone powinny iść przed izolacją i core — '
              'na świeżo są bezpieczniejsze i mocniejsze.',
          impact: 'Ta sama objętość, lepszy rozkład zmęczenia.',
          isSafe: true,
          scope: AiAssistanceScope.exerciseOrder,
        ));
      }
    }

    // --- Czas dnia ponad limit ---
    if (active.contains(AiAssistanceScope.timeFit) &&
        availableMinutes > 0 &&
        stats.estimatedMinutes > availableMinutes + 10) {
      final trimmable = _lastTrimmableItem(day, resolve, lockedExerciseIds);
      if (trimmable != null) {
        final exercise = resolve(trimmable.exerciseId);
        proposals.add(PlanChangeProposal(
          id: nextId('time'),
          kind: PlanChangeKind.adjustSets,
          dayIndex: dayIndex,
          exerciseId: trimmable.exerciseId,
          newSets: (trimmable.sets - 1).clamp(1, 10),
          title: 'Zetnij serię w „${exercise.name}"',
          reason: 'Dzień „${day.title}" trwa około '
              '${stats.estimatedMinutes} min, a masz $availableMinutes min.',
          impact: '−${estimatePlanItemMinutes(trimmable, exercise) ~/ (trimmable.sets == 0 ? 1 : trimmable.sets)} min.',
          isSafe: true,
          scope: AiAssistanceScope.timeFit,
        ));
      }
    }

    // --- Kolizja z regeneracją (szczególnie w trybie „na dzisiaj") ---
    if (active.contains(AiAssistanceScope.recoveryCheck) &&
        recovery.isNotEmpty) {
      for (final item in day.items) {
        if (lockedExerciseIds.contains(item.exerciseId)) continue;
        final exercise = resolve(item.exerciseId);
        final worst = worstRecoveryForExercise(exercise, recovery);
        if (worst == null || worst.$2 >= 55) continue;
        final substituteId = bestSubstituteId(
          exercise,
          owned,
          limitations,
          resolve,
          exclude: {
            ...excluded,
            ...day.items.map((entry) => entry.exerciseId),
          },
        );
        if (substituteId == null) {
          // Bez zamiennika: proponujemy zejście z objętości, nie usunięcie.
          if (item.sets <= 1) continue;
          proposals.add(PlanChangeProposal(
            id: nextId('recovery'),
            kind: PlanChangeKind.adjustSets,
            dayIndex: dayIndex,
            exerciseId: item.exerciseId,
            newSets: (item.sets - 1).clamp(1, 10),
            title: 'Zmniejsz objętość w „${exercise.name}"',
            reason: '${worst.$1.label} ma dziś ${worst.$2.round()}% '
                'regeneracji.',
            impact: '−1 seria dla partii w trakcie regeneracji.',
            isSafe: true,
            scope: AiAssistanceScope.recoveryCheck,
          ));
          continue;
        }
        final substitute = resolve(substituteId);
        final substituteWorst =
            worstRecoveryForExercise(substitute, recovery);
        if (substituteWorst != null && substituteWorst.$2 < worst.$2) continue;
        proposals.add(PlanChangeProposal(
          id: nextId('recovery'),
          kind: PlanChangeKind.swapExercise,
          dayIndex: dayIndex,
          exerciseId: item.exerciseId,
          replacementExerciseId: substituteId,
          title: 'Na dziś: „${exercise.name}" → „${substitute.name}"',
          reason: '${worst.$1.label} ma dziś ${worst.$2.round()}% '
              'regeneracji — zamiennik obciąża ją mniej.',
          impact: 'Mniejsze obciążenie partii w trakcie regeneracji.',
          isSafe: false,
          scope: AiAssistanceScope.recoveryCheck,
        ));
      }
    }
  }

  // --- Brakujące wzorce / partie / priorytety → DODANIE ćwiczenia ---
  if (active.contains(AiAssistanceScope.fillMissingExercises) ||
      active.contains(AiAssistanceScope.movementPatterns) ||
      active.contains(AiAssistanceScope.muscleBalance) ||
      active.contains(AiAssistanceScope.accessoryExercises)) {
    final usedIds = <String>{
      for (final day in plan.days)
        for (final item in day.items) item.exerciseId,
    };
    final targets = <MuscleGroup>{
      ...priorityMuscles.where(
          (group) => (report.weeklySetsByMuscle[group] ?? 0) == 0),
    };
    // Brakujące wzorce ruchowe przekładamy na partię, której dotyczą.
    for (final pattern in report.missingPatterns) {
      final group = _groupForPattern(pattern);
      if (group != null) targets.add(group);
    }
    // Klasyczny brak: tylny bark przy dominacji ruchów pchających.
    final pushHeavy = (report.weeklySetsByMuscle[MuscleGroup.chest] ?? 0) >
        (report.weeklySetsByMuscle[MuscleGroup.back] ?? 0) + 4;
    if (pushHeavy) targets.add(MuscleGroup.back);

    for (final group in targets) {
      final dayIndex = _bestDayForGroup(plan, report, group, fromDayIndex);
      if (dayIndex == null) continue;
      final candidate = _bestCandidateFor(
        library_: library_,
        group: group,
        owned: owned,
        limitations: limitations,
        excluded: {...excluded, ...usedIds},
        level: level,
      );
      if (candidate == null) continue;
      final limits = volumeLimitsFor(
        group,
        level: level,
        goal: goal,
        config: volumeLimits,
        intensity: intensity,
      );
      final sets =
          ((limits.sets.min + limits.sets.max) / 2).round().clamp(1, 8);
      final reps =
          ((limits.reps.min + limits.reps.max) / 2).round().clamp(1, 40);
      final entryType = candidate.entryType;
      final item = PlanItem(
        exerciseId: candidate.id,
        sets: sets,
        reps: entryType.showsReps ? reps : 0,
        durationSec: entryType.showsReps
            ? 0
            : (candidate.defaultDurationSec > 0
                ? candidate.defaultDurationSec
                : 40),
        note: '',
        restSeconds: _recommendedRest(candidate, goal),
      );
      proposals.add(PlanChangeProposal(
        id: nextId('add'),
        kind: PlanChangeKind.addExercise,
        dayIndex: dayIndex,
        exerciseId: candidate.id,
        newItem: item,
        title: 'Dodaj „${candidate.name}" do dnia '
            '„${plan.days[dayIndex].title}"',
        reason: priorityMuscles.contains(group)
            ? 'Wybrany priorytet ${group.label.toLowerCase()} nie ma w tym '
                'zestawie żadnego ćwiczenia.'
            : 'Zestawowi brakuje pracy na ${group.label.toLowerCase()}.',
        impact: '+$sets serii, około '
            '${estimatePlanItemMinutes(item, candidate)} min, '
            'sprzęt: ${candidate.equipment}.',
        isSafe: true,
        scope: AiAssistanceScope.fillMissingExercises,
      ));
      usedIds.add(candidate.id);
    }
  }

  // --- Podstawa decyzji ---
  final basis = <String>[
    if (level.trim().isNotEmpty) 'poziom: ${level.toLowerCase()}',
    if (goal.trim().isNotEmpty) 'cel: ${goal.toLowerCase()}',
    'intensywność: ${intensity.label.toLowerCase()}',
    'sprzęt: ${equipment.ownedSummary}',
    if (availableMinutes > 0) 'dostępny czas: $availableMinutes min',
    if (!limitations.isEmpty)
      'ograniczenia: ${limitations.flags.map((f) => f.label.toLowerCase()).join(', ')}',
    for (final entry in _lowestRecovery(recovery, 3))
      'regeneracja ${entry.$1.label.toLowerCase()}: ${entry.$2.round()}%',
    if (hasHistory) 'historia wykonań tego zestawu',
    'limity objętości zestawu',
  ];

  final limitedReason = !hasHistory
      ? 'Analiza ma ograniczoną dokładność, ponieważ brakuje historii '
          'wykonania tego zestawu.'
      : recovery.isEmpty
          ? 'Analiza ma ograniczoną dokładność — brakuje danych regeneracji.'
          : '';

  return PlanAnalysisResult(
    mode: mode,
    report: report,
    proposals: proposals,
    basis: basis,
    confidence: report.confidence,
    limitedAccuracyReason: limitedReason,
  );
}

/// Nakłada ZAAKCEPTOWANE propozycje na zestaw i zwraca nowy plan + porównanie.
///
/// Ćwiczenia z [lockedExerciseIds] są pomijane nawet wtedy, gdy propozycja
/// znalazła się na liście — blokada użytkownika ma pierwszeństwo przed
/// wszystkim innym.
({WorkoutPlan plan, PlanDiff diff}) applyPlanProposals(
  WorkoutPlan plan,
  List<PlanChangeProposal> accepted, {
  required Exercise Function(String id) resolve,
  Set<String> lockedExerciseIds = const <String>{},
  EquipmentProfile equipment = const EquipmentProfile(),
  LimitationProfile limitations = const LimitationProfile(),
  String level = '',
  String goal = '',
  WorkoutIntensityLevel intensity = WorkoutIntensityLevel.moderate,
  VolumeLimitsConfig volumeLimits = VolumeLimitsConfig.standard,
  int availableMinutes = 0,
  List<MuscleGroup> priorityMuscles = const <MuscleGroup>[],
  int fromDayIndex = 0,
}) {
  PlanQualityReport analyze(WorkoutPlan target) => analyzePlanQuality(
        target,
        resolve: resolve,
        equipment: equipment,
        limitations: limitations,
        level: level,
        goal: goal,
        intensity: intensity,
        volumeLimits: volumeLimits,
        availableMinutes: availableMinutes,
        priorityMuscles: priorityMuscles,
      );

  final before = analyze(plan);
  final days = [...plan.days];
  final added = <String>[];
  final removed = <String>[];
  final swapped = <(String, String)>[];
  final setChanges = <String>[];
  final reordered = <String>[];

  for (final proposal in accepted) {
    final dayIndex = proposal.dayIndex;
    if (dayIndex < fromDayIndex || dayIndex < 0 || dayIndex >= days.length) {
      continue;
    }
    // Blokada użytkownika unieważnia każdą zmianę dotykającą ćwiczenia.
    if (proposal.exerciseId.isNotEmpty &&
        lockedExerciseIds.contains(proposal.exerciseId)) {
      continue;
    }
    final day = days[dayIndex];
    final items = [...day.items];

    switch (proposal.kind) {
      case PlanChangeKind.addExercise:
        final item = proposal.newItem;
        if (item == null) break;
        if (items.any((entry) => entry.exerciseId == item.exerciseId)) break;
        items.add(item);
        added.add(resolve(item.exerciseId).name);

      case PlanChangeKind.removeExercise:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0) break;
        removed.add(resolve(proposal.exerciseId).name);
        items.removeAt(index);

      case PlanChangeKind.swapExercise:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0 || proposal.replacementExerciseId.isEmpty) break;
        if (items.any(
            (entry) => entry.exerciseId == proposal.replacementExerciseId)) {
          break;
        }
        final replacement = resolve(proposal.replacementExerciseId);
        final old = items[index];
        items[index] = old.copyWith(
          exerciseId: proposal.replacementExerciseId,
          // Ciężar starego ćwiczenia nie przenosi się na inny sprzęt.
          suggestedWeightKg: 0,
          durationSec: replacement.entryType.showsReps
              ? 0
              : (old.durationSec > 0
                  ? old.durationSec
                  : replacement.defaultDurationSec),
        );
        swapped.add((resolve(proposal.exerciseId).name, replacement.name));

      case PlanChangeKind.reorder:
        if (proposal.newOrder.isEmpty) break;
        final byId = <String, PlanItem>{
          for (final entry in items) entry.exerciseId: entry,
        };
        final ordered = <PlanItem>[];
        for (final id in proposal.newOrder) {
          final entry = byId.remove(id);
          if (entry != null) ordered.add(entry);
        }
        ordered.addAll(byId.values);
        items
          ..clear()
          ..addAll(ordered);
        reordered.add(day.title);

      case PlanChangeKind.adjustSets:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0 || proposal.newSets <= 0) break;
        setChanges.add('${resolve(proposal.exerciseId).name}: '
            '${items[index].sets} → ${proposal.newSets} serii');
        items[index] = items[index].copyWith(sets: proposal.newSets);

      case PlanChangeKind.adjustReps:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0 || proposal.newReps <= 0) break;
        setChanges.add('${resolve(proposal.exerciseId).name}: '
            '${items[index].reps} → ${proposal.newReps} powtórzeń');
        items[index] = items[index].copyWith(reps: proposal.newReps);

      case PlanChangeKind.adjustDuration:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0 || proposal.newDurationSec <= 0) break;
        setChanges.add('${resolve(proposal.exerciseId).name}: '
            '${items[index].durationSec} → ${proposal.newDurationSec} s');
        items[index] =
            items[index].copyWith(durationSec: proposal.newDurationSec);

      case PlanChangeKind.adjustRest:
        final index =
            items.indexWhere((entry) => entry.exerciseId == proposal.exerciseId);
        if (index < 0 || proposal.newRestSeconds <= 0) break;
        setChanges.add('${resolve(proposal.exerciseId).name}: przerwa '
            '${items[index].restSeconds} → ${proposal.newRestSeconds} s');
        items[index] =
            items[index].copyWith(restSeconds: proposal.newRestSeconds);
    }

    days[dayIndex] = day.copyWith(items: items);
  }

  final updated = plan.copyWith(days: days);
  final after = analyze(updated);

  return (
    plan: updated,
    diff: PlanDiff(
      before: before,
      after: after,
      addedExercises: added,
      removedExercises: removed,
      swappedExercises: swapped,
      setChanges: setChanges,
      reorderedDays: reordered,
    ),
  );
}

/// Najsłabiej zregenerowana partia obciążana przez ćwiczenie (partia, procent).
(BodyMuscle, double)? worstRecoveryForExercise(
  Exercise exercise,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
) {
  (BodyMuscle, double)? worst;
  for (final impact in exercise.effectiveMuscleImpacts) {
    if (impact.role == MuscleRole.stabilizer) continue;
    final state = recovery[impact.muscleGroup];
    if (state == null || !state.hasData) continue;
    final percent = state.recoveryPercent;
    if (percent == null) continue;
    if (worst == null || percent < worst.$2) {
      worst = (impact.muscleGroup, percent);
    }
  }
  return worst;
}

/// Zgodność ćwiczenia z dzisiejszą regeneracją — do kart w czacie AI.
({String label, double? percent, BodyMuscle? muscle}) exerciseRecoveryVerdict(
  Exercise exercise,
  Map<BodyMuscle, MuscleRecoveryState> recovery,
) {
  final worst = worstRecoveryForExercise(exercise, recovery);
  if (worst == null) {
    return (label: 'Brak wystarczających danych', percent: null, muscle: null);
  }
  final percent = worst.$2;
  final label = percent >= 75
      ? 'Dobre na dzisiaj'
      : percent >= 55
          ? 'Możliwe przy niższej intensywności'
          : 'Niepolecane — ${worst.$1.label.toLowerCase()} się regeneruje';
  return (label: label, percent: percent, muscle: worst.$1);
}

// ============================================================================
// Pomocnicze
// ============================================================================

List<(BodyMuscle, double)> _lowestRecovery(
  Map<BodyMuscle, MuscleRecoveryState> recovery,
  int take,
) {
  final entries = <(BodyMuscle, double)>[];
  for (final entry in recovery.entries) {
    final state = entry.value;
    if (!state.hasData) continue;
    final percent = state.recoveryPercent;
    if (percent == null) continue;
    entries.add((entry.key, percent));
  }
  entries.sort((a, b) => a.$2.compareTo(b.$2));
  return entries.take(take).toList();
}

int _recommendedRest(Exercise exercise, String goal) {
  final compound = exercise.effectiveMuscleImpacts.length > 1 &&
      movementPatternOf(exercise) != MovementPattern.core;
  final g = goal.toLowerCase();
  if (exercise.entryType == ExerciseEntryType.mobility) return 30;
  if (g.contains('sił') || g.contains('sil')) return compound ? 180 : 120;
  if (g.contains('redu') || g.contains('kond')) return compound ? 75 : 45;
  return compound ? 120 : 75;
}

List<String> _preferredOrder(
  WorkoutDay day,
  Exercise Function(String id) resolve,
) {
  final items = [...day.items];
  items.sort((a, b) {
    final left = _exerciseOrderRank(resolve(a.exerciseId));
    final right = _exerciseOrderRank(resolve(b.exerciseId));
    return left.compareTo(right);
  });
  return items.map((item) => item.exerciseId).toList();
}

int _exerciseOrderRank(Exercise exercise) {
  final pattern = movementPatternOf(exercise);
  final compound = exercise.effectiveMuscleImpacts.length > 1;
  if (pattern == MovementPattern.squat || pattern == MovementPattern.hinge) {
    return 0;
  }
  if (pattern == MovementPattern.horizontalPush ||
      pattern == MovementPattern.verticalPull) {
    return 1;
  }
  if (pattern == MovementPattern.horizontalPull ||
      pattern == MovementPattern.verticalPush) {
    return 2;
  }
  if (pattern == MovementPattern.lunge) return 3;
  if (compound) return 4;
  if (pattern == MovementPattern.core) return 6;
  return 5;
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

PlanItem? _lastTrimmableItem(
  WorkoutDay day,
  Exercise Function(String id) resolve,
  Set<String> locked,
) {
  for (final item in day.items.reversed) {
    if (locked.contains(item.exerciseId)) continue;
    if (item.sets <= 1) continue;
    return item;
  }
  return null;
}

MuscleGroup? _groupForPattern(MovementPattern pattern) => switch (pattern) {
      MovementPattern.horizontalPush => MuscleGroup.chest,
      MovementPattern.verticalPush => MuscleGroup.shoulders,
      MovementPattern.horizontalPull => MuscleGroup.back,
      MovementPattern.verticalPull => MuscleGroup.back,
      MovementPattern.squat => MuscleGroup.quadriceps,
      MovementPattern.hinge => MuscleGroup.hamstrings,
      MovementPattern.lunge => MuscleGroup.glutes,
      MovementPattern.core => MuscleGroup.core,
      MovementPattern.carryOrOther => null,
    };

/// Dzień, do którego najlepiej dołożyć ćwiczenie na daną partię: ten, który
/// już tę partię trenuje, a przy braku takiego — najkrótszy dzień treningowy.
int? _bestDayForGroup(
  WorkoutPlan plan,
  PlanQualityReport report,
  MuscleGroup group,
  int fromDayIndex,
) {
  int? best;
  var bestSets = -1;
  for (var index = fromDayIndex; index < report.dayStats.length; index++) {
    final stats = report.dayStats[index];
    if (stats.isRestDay) continue;
    final sets = stats.setsByMuscle[group] ?? 0;
    if (sets > bestSets) {
      bestSets = sets;
      best = index;
    }
  }
  if (best != null && bestSets > 0) return best;
  // Brak dnia z tą partią → najkrótszy dzień treningowy.
  int? shortest;
  var shortestMinutes = 1 << 30;
  for (var index = fromDayIndex; index < report.dayStats.length; index++) {
    final stats = report.dayStats[index];
    if (stats.isRestDay) continue;
    if (stats.estimatedMinutes < shortestMinutes) {
      shortestMinutes = stats.estimatedMinutes;
      shortest = index;
    }
  }
  return shortest;
}

Exercise? _bestCandidateFor({
  required List<Exercise> library_,
  required MuscleGroup group,
  required Set<EquipmentType> owned,
  required LimitationProfile limitations,
  required Set<String> excluded,
  required String level,
}) {
  final rank = trainingLevelRank(level);
  final candidates = <Exercise>[
    for (final exercise in library_)
      if (!excluded.contains(exercise.id) &&
          primaryMuscleGroupOf(exercise) == group &&
          isExerciseAvailable(exercise, owned) &&
          !exerciseViolatesLimitation(exercise, limitations) &&
          trainingLevelRank(exercise.level) <= rank + 1)
        exercise,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final distA = (trainingLevelRank(a.level) - rank).abs();
    final distB = (trainingLevelRank(b.level) - rank).abs();
    if (distA != distB) return distA.compareTo(distB);
    return a.name.compareTo(b.name);
  });
  return candidates.first;
}
