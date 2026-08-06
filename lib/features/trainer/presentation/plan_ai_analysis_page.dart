// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Analiza AI istniejącego zestawu: wybór rodzaju analizy i zakresu ingerencji,
// blokowanie ćwiczeń, lista propozycji do pojedynczej akceptacji, porównanie
// „przed / po" oraz zapis jako spersonalizowany wariant.
part of '../../../main.dart';

/// Otwiera analizę AI dla zestawu.
Future<void> openPlanAiAnalysis(BuildContext context, String planId) async {
  final mode = await showModalBottomSheet<PlanAnalysisMode>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => const _AnalysisModeSheet(),
  );
  if (mode == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlanAiAnalysisPage(planId: planId, mode: mode),
    ),
  );
}

class _AnalysisModeSheet extends StatelessWidget {
  const _AnalysisModeSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Przeanalizuj zestaw przez AI',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            for (final mode in PlanAnalysisMode.values) ...[
              Material(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: Key('analysis_mode_${mode.key}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context, mode),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          mode == PlanAnalysisMode.permanent
                              ? Icons.tune_rounded
                              : Icons.today_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(mode.label,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(mode.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class PlanAiAnalysisPage extends StatefulWidget {
  const PlanAiAnalysisPage({
    super.key,
    required this.planId,
    required this.mode,
  });

  final String planId;
  final PlanAnalysisMode mode;

  @override
  State<PlanAiAnalysisPage> createState() => _PlanAiAnalysisPageState();
}

class _PlanAiAnalysisPageState extends State<PlanAiAnalysisPage> {
  /// Zakres ingerencji AI. Pusty zbiór = analizuj wszystko.
  Set<AiAssistanceScope> _scopes = {
    AiAssistanceScope.fillMissingExercises,
    AiAssistanceScope.substitutions,
    AiAssistanceScope.setsAndReps,
    AiAssistanceScope.rest,
    AiAssistanceScope.equipmentCheck,
    AiAssistanceScope.limitationCheck,
    AiAssistanceScope.exerciseOrder,
    AiAssistanceScope.muscleBalance,
    AiAssistanceScope.recoveryCheck,
  };

  /// Ćwiczenia oznaczone „Nie zmieniaj tego ćwiczenia".
  final Set<String> _locked = <String>{};

  /// Zaakceptowane propozycje (id).
  final Set<String> _accepted = <String>{};

  /// Odrzucone propozycje (id) — znikają z listy do zastosowania.
  final Set<String> _rejected = <String>{};

  PlanAnalysisResult? _result;
  bool _analyzing = false;
  bool _saving = false;

  WorkoutPlan? _plan(AppStore store) {
    for (final plan in store.plans) {
      if (plan.id == widget.planId) return plan;
    }
    return null;
  }

  Future<void> _runAnalysis() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);
    // Analiza jest czystym Dartem, ale liczy sporo — zdejmujemy ją z klatki,
    // żeby nie ciąć animacji przejścia ekranu.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    final store = AppScope.read(context);
    final plan = _plan(store);
    if (plan == null) {
      setState(() => _analyzing = false);
      return;
    }
    try {
      final result = store.analyzePlan(
        plan,
        mode: widget.mode,
        scopes: _scopes,
        lockedExerciseIds: _locked,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _accepted.clear();
        _rejected.clear();
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      showError(context, 'Nie udało się przeanalizować zestawu: $error');
    }
  }

  List<PlanChangeProposal> get _pending {
    final result = _result;
    if (result == null) return const <PlanChangeProposal>[];
    return result.proposals
        .where((proposal) => !_rejected.contains(proposal.id))
        .toList();
  }

  List<PlanChangeProposal> get _acceptedProposals {
    final result = _result;
    if (result == null) return const <PlanChangeProposal>[];
    return result.proposals
        .where((proposal) => _accepted.contains(proposal.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final plan = _plan(store);
    final theme = Theme.of(context);

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analiza AI')),
        body: const Center(child: Text('Nie znaleziono zestawu.')),
      );
    }

    final result = _result;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: Text(widget.mode.label,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(plan.name,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(widget.mode.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (plan.completedDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoNote(
                text: 'Zmiany obejmą tylko przyszłe dni programu. Ukończone '
                    'dni (${plan.completedDays.length}) i dotychczasowe '
                    'postępy pozostaną bez zmian.',
              ),
            ],
            const SizedBox(height: 16),

            // --- Zakres ingerencji AI ---
            _SectionTitle(
                title: 'Co AI może zmienić?',
                subtitle: 'AI zajmie się wyłącznie zaznaczonymi obszarami.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final scope in AiAssistanceScope.values)
                  FilterChip(
                    key: Key('analysis_scope_${scope.key}'),
                    label: Text(scope.label,
                        style: const TextStyle(fontSize: 12)),
                    selected: _scopes.contains(scope),
                    onSelected: (value) => setState(() {
                      if (value) {
                        _scopes.add(scope);
                      } else {
                        _scopes.remove(scope);
                      }
                      // Zmiana zakresu unieważnia wynik — inaczej pokazywalibyśmy
                      // propozycje spoza tego, na co użytkownik pozwolił.
                      _result = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Wrap zamiast Row — dwie etykiety nie muszą się zmieścić
            // w jednym wierszu na wąskim ekranie.
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _scopes = AiAssistanceScope.values.toSet();
                    _result = null;
                  }),
                  child: const Text('Przeanalizuj cały zestaw'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _scopes = <AiAssistanceScope>{};
                    _result = null;
                  }),
                  child: const Text('Wyczyść'),
                ),
              ],
            ),

            // --- Blokowanie ćwiczeń ---
            const SizedBox(height: 8),
            _SectionTitle(
              title: 'Nie zmieniaj tych ćwiczeń',
              subtitle: 'Zablokowane ćwiczenia nie zostaną usunięte ani '
                  'zamienione.',
            ),
            const SizedBox(height: 8),
            _LockedExercisesPicker(
              plan: plan,
              locked: _locked,
              onToggle: (id, value) => setState(() {
                if (value) {
                  _locked.add(id);
                } else {
                  _locked.remove(id);
                }
                _result = null;
              }),
            ),

            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('run_plan_analysis'),
              onPressed: _analyzing ? null : _runAnalysis,
              icon: _analyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_analyzing ? 'Analizuję…' : 'Uruchom analizę'),
            ),

            if (result != null) ...[
              const SizedBox(height: 20),
              PlanQualityScoreCard(report: result.report),
              const SizedBox(height: 14),
              _AnalysisBasisCard(result: result),
              const SizedBox(height: 14),
              _SectionTitle(
                title: 'Proponowane poprawki (${_pending.length})',
                subtitle: 'Każdą zmianę zatwierdzasz osobno. Nic nie zostanie '
                    'zapisane bez Twojej decyzji.',
              ),
              const SizedBox(height: 8),
              if (_pending.isEmpty)
                _InfoNote(
                  text: result.proposals.isEmpty
                      ? 'AI nie znalazło nic do poprawy w zaznaczonym zakresie.'
                      : 'Odrzuciłeś wszystkie propozycje.',
                )
              else
                for (final proposal in _pending)
                  _ProposalCard(
                    proposal: proposal,
                    accepted: _accepted.contains(proposal.id),
                    onAccept: () =>
                        setState(() => _accepted.add(proposal.id)),
                    onReject: () => setState(() {
                      _accepted.remove(proposal.id);
                      _rejected.add(proposal.id);
                    }),
                    onLock: proposal.exerciseId.isEmpty
                        ? null
                        : () => setState(() {
                              _locked.add(proposal.exerciseId);
                              _rejected.add(proposal.id);
                              _accepted.remove(proposal.id);
                            }),
                  ),
              if (result.proposals.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('accept_safe_changes'),
                      onPressed: () => setState(() {
                        for (final proposal in result.safeProposals) {
                          if (_rejected.contains(proposal.id)) continue;
                          _accepted.add(proposal.id);
                        }
                      }),
                      icon: const Icon(Icons.verified_rounded, size: 16),
                      label: const Text('Zastosuj wszystkie bezpieczne'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _accepted.clear();
                        _rejected.addAll(
                            result.proposals.map((item) => item.id));
                      }),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Odrzuć wszystkie'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('compare_before_after'),
                      onPressed: _acceptedProposals.isEmpty
                          ? null
                          : () => _showComparison(context, plan),
                      icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                      label: const Text('Porównaj przed i po'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('save_as_variant'),
                  onPressed: _acceptedProposals.isEmpty || _saving
                      ? null
                      : () => _applyChanges(context, plan, asVariant: true),
                  icon: const Icon(Icons.save_rounded),
                  label: Text(widget.mode == PlanAnalysisMode.today
                      ? 'Zapisz wariant na dzisiaj'
                      : 'Zapisz jako mój wariant'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('replace_current_plan'),
                  onPressed: _acceptedProposals.isEmpty || _saving
                      ? null
                      : () => _confirmReplace(context, plan),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Zastąp moją obecną wersję'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Oryginalny zestaw bazowy pozostaje nietknięty — wariant '
                  'zapisuje się jako osobny zestaw.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  ({WorkoutPlan plan, PlanDiff diff}) _computeResult(
    AppStore store,
    WorkoutPlan plan,
  ) {
    return applyPlanProposals(
      plan,
      _acceptedProposals,
      resolve: (id) => ExerciseRepo.byId(id, store.customExercises),
      lockedExerciseIds: _locked,
      equipment: store.settings.equipmentProfile,
      limitations: store.settings.limitationProfile,
      level: normalizeTrainingLevel(store.settings.level),
      goal: store.settings.trainingMode.trim().isNotEmpty
          ? store.settings.trainingMode
          : store.settings.goal,
      intensity: WorkoutIntensityLevel.fromSteps(plan.intensitySteps),
      volumeLimits: store.volumeLimits,
      availableMinutes: store.settings.preferredWorkoutMinutes,
      priorityMuscles:
          store.bodyGoalProfile?.priorityMuscleGroups ?? const <MuscleGroup>[],
      // Ochrona rozpoczętego programu — ukończone dni nietykalne.
      fromDayIndex: plan.completedDays.isEmpty ? 0 : plan.currentDayIndex,
    );
  }

  Future<void> _showComparison(BuildContext context, WorkoutPlan plan) async {
    final store = AppScope.read(context);
    final computed = _computeResult(store, plan);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _ComparisonSheet(diff: computed.diff),
    );
  }

  Future<void> _confirmReplace(BuildContext context, WorkoutPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zastąpić obecną wersję?'),
        content: Text(
          plan.completedDays.isEmpty
              ? 'Treść zestawu „${plan.name}" zostanie zmieniona. Poprzednia '
                  'wersja zapisze się w historii — będziesz mógł ją przywrócić.'
              : 'Zmiany obejmą tylko przyszłe dni programu. Ukończone dni '
                  '(${plan.completedDays.length}), zapisane serie i wyniki '
                  'pozostaną bez zmian. Poprzednia wersja trafi do historii.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Zastąp'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _applyChanges(context, plan, asVariant: false);
  }

  Future<void> _applyChanges(
    BuildContext context,
    WorkoutPlan plan, {
    required bool asVariant,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = AppScope.read(context);
      final computed = _computeResult(store, plan);
      final summary = _changeSummary(computed.diff);

      if (asVariant) {
        final variant = await store.createPersonalizedVariant(
          plan,
          name: widget.mode == PlanAnalysisMode.today
              ? '${plan.name} — wariant na dzisiaj'
              : '${plan.name} — mój wariant AI',
          days: computed.plan.days,
          scopes: _scopes,
          reason: summary,
          mode: widget.mode,
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();
        showError(context, 'Zapisano „${variant.name}". Oryginał bez zmian.');
        return;
      }

      await store.applyAnalysisToPlan(
        plan.id,
        computed.plan.days,
        versionLabel: widget.mode == PlanAnalysisMode.today
            ? 'Dopasowanie na dzisiaj'
            : 'Dopasowanie do profilu',
        reason: summary,
        scopes: _scopes,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showError(context, 'Zaktualizowano zestaw. Poprzednia wersja jest '
          'w historii wersji.');
    } catch (error) {
      if (!context.mounted) return;
      showError(context, 'Nie udało się zapisać zmian: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _changeSummary(PlanDiff diff) {
    final parts = <String>[
      if (diff.addedExercises.isNotEmpty)
        'dodano ${diff.addedExercises.length}',
      if (diff.removedExercises.isNotEmpty)
        'usunięto ${diff.removedExercises.length}',
      if (diff.swappedExercises.isNotEmpty)
        'zamieniono ${diff.swappedExercises.length}',
      if (diff.setChanges.isNotEmpty)
        'skorygowano ${diff.setChanges.length} parametrów',
      if (diff.reorderedDays.isNotEmpty)
        'poprawiono kolejność w ${diff.reorderedDays.length} dniach',
    ];
    return parts.isEmpty ? 'Brak zmian' : parts.join(', ');
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LockedExercisesPicker extends StatefulWidget {
  const _LockedExercisesPicker({
    required this.plan,
    required this.locked,
    required this.onToggle,
  });

  final WorkoutPlan plan;
  final Set<String> locked;
  final void Function(String exerciseId, bool locked) onToggle;

  @override
  State<_LockedExercisesPicker> createState() => _LockedExercisesPickerState();
}

class _LockedExercisesPickerState extends State<_LockedExercisesPicker> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final ids = <String>{
      for (final day in widget.plan.days)
        for (final item in day.items) item.exerciseId,
    }.toList();

    if (ids.isEmpty) {
      return Text('Ten zestaw nie ma jeszcze ćwiczeń.',
          style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const Key('toggle_locked_picker'),
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded
              ? Icons.expand_less_rounded
              : Icons.expand_more_rounded),
          label: Text(widget.locked.isEmpty
              ? 'Wybierz ćwiczenia do zablokowania'
              : 'Zablokowane: ${widget.locked.length}'),
        ),
        if (_expanded)
          for (final id in ids)
            CheckboxListTile(
              key: Key('lock_$id'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: widget.locked.contains(id),
              title: Text(
                ExerciseRepo.byId(id, store.customExercises).name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (value) => widget.onToggle(id, value ?? false),
            ),
      ],
    );
  }
}

class _AnalysisBasisCard extends StatelessWidget {
  const _AnalysisBasisCard({required this.result});

  final PlanAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analiza została przygotowana na podstawie:',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final entry in result.basis)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $entry',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 8),
          Text(
            'Pewność analizy: ${(result.confidence * 100).round()}%',
            key: const Key('analysis_confidence'),
            style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800, color: scheme.primary),
          ),
          if (result.limitedAccuracyReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(result.limitedAccuracyReason,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.accepted,
    required this.onAccept,
    required this.onReject,
    required this.onLock,
  });

  final PlanChangeProposal proposal;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (proposal.kind) {
      PlanChangeKind.addExercise => Icons.add_circle_outline_rounded,
      PlanChangeKind.removeExercise => Icons.remove_circle_outline_rounded,
      PlanChangeKind.swapExercise => Icons.swap_horiz_rounded,
      PlanChangeKind.reorder => Icons.reorder_rounded,
      PlanChangeKind.adjustSets => Icons.repeat_rounded,
      PlanChangeKind.adjustReps => Icons.numbers_rounded,
      PlanChangeKind.adjustDuration => Icons.timer_rounded,
      PlanChangeKind.adjustRest => Icons.hourglass_bottom_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accepted
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
          border: Border.all(
            color: accepted
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(proposal.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (proposal.isSafe)
                  Tooltip(
                    message: 'Zmiana bezpieczna — nie usuwa Twoich ćwiczeń',
                    child: Icon(Icons.verified_rounded,
                        size: 16, color: scheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Powód: ${proposal.reason}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
            if (proposal.impact.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Wpływ: ${proposal.impact}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.tonal(
                  key: Key('accept_${proposal.id}'),
                  onPressed: accepted ? null : onAccept,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(accepted ? 'Zaakceptowano' : 'Zaakceptuj'),
                ),
                OutlinedButton(
                  key: Key('reject_${proposal.id}'),
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Odrzuć'),
                ),
                if (onLock != null)
                  OutlinedButton(
                    key: Key('lock_from_${proposal.id}'),
                    onPressed: onLock,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Nie zmieniaj tego ćwiczenia'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSheet extends StatelessWidget {
  const _ComparisonSheet({required this.diff});

  final PlanDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Porównanie przed i po',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ComparisonColumn(
                    title: 'Przed analizą',
                    report: diff.before,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ComparisonColumn(
                    title: 'Po zmianach',
                    report: diff.after,
                    highlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (diff.addedExercises.isNotEmpty)
              _DiffList(
                  title: 'Dodane ćwiczenia', items: diff.addedExercises),
            if (diff.removedExercises.isNotEmpty)
              _DiffList(
                  title: 'Usunięte ćwiczenia', items: diff.removedExercises),
            if (diff.swappedExercises.isNotEmpty)
              _DiffList(
                title: 'Zamienione ćwiczenia',
                items: [
                  for (final pair in diff.swappedExercises)
                    '${pair.$1} → ${pair.$2}',
                ],
              ),
            if (diff.setChanges.isNotEmpty)
              _DiffList(
                  title: 'Zmiany serii / powtórzeń / przerw',
                  items: diff.setChanges),
            if (diff.reorderedDays.isNotEmpty)
              _DiffList(
                  title: 'Poprawiona kolejność', items: diff.reorderedDays),
            const SizedBox(height: 10),
            _InfoNote(
              text: 'Zmiana czasu: ${_signed(diff.minuteDelta)} min · '
                  'objętość: ${_signed(diff.setDelta)} serii · '
                  'ocena: ${_signed(diff.scoreDelta)} pkt.',
            ),
          ],
        ),
      ),
    );
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
}

class _ComparisonColumn extends StatelessWidget {
  const _ComparisonColumn({
    required this.title,
    required this.report,
    this.highlight = false,
  });

  final String title;
  final PlanQualityReport report;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _Stat(label: 'Ćwiczenia', value: '${report.totalExercises}'),
          _Stat(label: 'Serie', value: '${report.totalSets}'),
          _Stat(label: 'Czas', value: '~${report.estimatedMinutes} min'),
          _Stat(label: 'Ocena', value: '${report.score}/100'),
          if (report.missingPatterns.isNotEmpty)
            _Stat(
              label: 'Braki',
              value: report.missingPatterns
                  .map((pattern) => pattern.label)
                  .join(', '),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DiffList extends StatelessWidget {
  const _DiffList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $item',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
