// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Podmiana zaplanowanego zestawu na własny: lista pasujących zestawów,
// sprawdzenie AI przed podmianą i przywrócenie wersji bazowej.
part of '../../../main.dart';

/// Otwiera wybór własnego zestawu na dzisiejszy obszar rozkładu.
Future<void> showPlanSubstitutionSheet(
  BuildContext context,
  TrainingFocusArea area,
) async {
  final store = AppScope.read(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // Arkusz mieszka w overlayu Nawigatora — sklep podajemy jawnie.
    builder: (sheetContext) => AppScope(
      store: store,
      child: _PlanSubstitutionSheet(area: area),
    ),
  );
}

class _PlanSubstitutionSheet extends StatelessWidget {
  const _PlanSubstitutionSheet({required this.area});

  final TrainingFocusArea area;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final candidates = store.substitutionCandidatesForArea(area);
    final current = store.substitutedPlanForArea(area);

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
            Text('Zamień zestaw na własny',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              'Dzisiejszy plan to ${area.label.toLowerCase()}. Pokazujemy '
              'tylko te Twoje zestawy, które robią to samo — plan tygodnia '
              'zostaje bez zmian.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (current != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius:
                      BorderRadius.circular(uiCornerRadius(context, 14)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Teraz podstawiony',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          Text(current.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const Key('restore_base_plan'),
                      onPressed: () async {
                        await store.clearPlanForArea(area);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        showError(context, 'Przywrócono zestaw bazowy.');
                      },
                      child: const Text('Przywróć bazowy'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (candidates.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius:
                      BorderRadius.circular(uiCornerRadius(context, 14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Brak pasujących zestawów',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Żaden z Twoich zestawów nie trenuje '
                      '${area.label.toLowerCase()} na tyle, żeby zastąpić '
                      'dzisiejszy dzień. Utwórz zestaw zawężony do tej partii '
                      '— w kreatorze wybierz „Tylko wybrane partie".',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('substitution_create_plan'),
                      onPressed: () {
                        Navigator.pop(context);
                        showPlanCreationModeSheet(context);
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Utwórz własny zestaw'),
                    ),
                  ],
                ),
              )
            else
              for (final candidate in candidates)
                _SubstitutionCandidateCard(
                  key: Key('substitution_${candidate.plan.id}'),
                  area: area,
                  plan: candidate.plan,
                  verdict: candidate.verdict,
                  isCurrent: current?.id == candidate.plan.id,
                ),
          ],
        ),
      ),
    );
  }
}

class _SubstitutionCandidateCard extends StatefulWidget {
  const _SubstitutionCandidateCard({
    super.key,
    required this.area,
    required this.plan,
    required this.verdict,
    required this.isCurrent,
  });

  final TrainingFocusArea area;
  final WorkoutPlan plan;
  final PlanSubstitutionVerdict verdict;
  final bool isCurrent;

  @override
  State<_SubstitutionCandidateCard> createState() =>
      _SubstitutionCandidateCardState();
}

class _SubstitutionCandidateCardState
    extends State<_SubstitutionCandidateCard> {
  /// Wynik sprawdzenia AI. `null` = jeszcze nie sprawdzano.
  PlanAnalysisResult? _check;
  bool _checking = false;
  bool _busy = false;

  Future<void> _runCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    // Analiza to czysty Dart, ale liczy sporo — zdejmujemy ją z klatki.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    try {
      final store = AppScope.read(context);
      final result = store.analyzePlan(
        widget.plan,
        mode: PlanAnalysisMode.today,
      );
      if (!mounted) return;
      setState(() {
        _check = result;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _checking = false);
      showError(context, 'Nie udało się sprawdzić zestawu: $error');
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.read(context);
      await store.setPlanForArea(widget.area, widget.plan.id);
      // `mounted` stanu, nie `context.mounted` — to kontekst tego State.
      if (!mounted) return;
      Navigator.pop(context);
      showError(context,
          'Dzisiejszy ${widget.area.label.toLowerCase()} realizuje teraz '
          '„${widget.plan.name}".');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verdict = widget.verdict;
    final fitColor = switch (verdict.fit) {
      PlanSubstitutionFit.perfect => scheme.primary,
      PlanSubstitutionFit.partial => kDeloadColor,
      PlanSubstitutionFit.incompatible => scheme.error,
    };
    final check = _check;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
          border: Border.all(
            color: widget.isCurrent
                ? scheme.primary
                : fitColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(widget.plan.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                PlanOriginChip(mode: widget.plan.origin.creationMode),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  verdict.fit == PlanSubstitutionFit.perfect
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: fitColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(verdict.fit.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: fitColor, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final note in verdict.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $note',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            for (final warning in verdict.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(warning,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.error)),
                    ),
                  ],
                ),
              ),
            if (check != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 14, color: scheme.primary),
                        const SizedBox(width: 6),
                        // Expanded: przy dłuższej etykiecie („pewność 100%")
                        // wiersz inaczej wychodzi poza kartę.
                        Expanded(
                          child: Text(
                            'Sprawdzenie AI: ${check.report.score}/100 '
                            '(pewność ${(check.confidence * 100).round()}%)',
                            key: const Key('substitution_ai_score'),
                            maxLines: 2,
                            style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (check.report.issues.isEmpty)
                      Text('AI nie znalazło problemów na dzisiaj.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant))
                    else
                      for (final issue in check.report.issues.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('• ${issue.text}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('substitution_check_${widget.plan.id}'),
                  onPressed: _checking ? null : _runCheck,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: _checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 15),
                  label: Text(check == null
                      ? 'Sprawdź przez AI'
                      : 'Sprawdź ponownie'),
                ),
                FilledButton.tonalIcon(
                  key: Key('substitution_apply_${widget.plan.id}'),
                  onPressed: widget.isCurrent || _busy ? null : _apply,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                  label: Text(widget.isCurrent
                      ? 'Już podstawiony'
                      : 'Podstaw na dziś'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
