// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Interaktywne karty ćwiczeń w rozmowie z Trenerem AI: podgląd, dodanie do
// bazy (z wykrywaniem duplikatów), dodanie do zestawu, start pojedynczego
// ćwiczenia i akcje na wielu kartach naraz.
part of '../../../main.dart';

/// Blok „Proponowane ćwiczenia" pod wiadomością AI.
///
/// Można go zwinąć, przy większej liczbie kart przechodzi w listę zwartą,
/// a tryb wyboru pozwala zaznaczyć kilka ćwiczeń i wykonać akcję zbiorczą.
class AiExerciseSuggestionsBlock extends StatefulWidget {
  const AiExerciseSuggestionsBlock({
    super.key,
    required this.reply,
    this.messageId = '',
  });

  final TrainerAiStructuredReply reply;
  final String messageId;

  @override
  State<AiExerciseSuggestionsBlock> createState() =>
      _AiExerciseSuggestionsBlockState();
}

class _AiExerciseSuggestionsBlockState
    extends State<AiExerciseSuggestionsBlock> {
  bool _expanded = true;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  List<AiExerciseSuggestion> get _suggestions =>
      widget.reply.exerciseSuggestions;

  List<AiExerciseSuggestion> get _selectedSuggestions => [
        for (final suggestion in _suggestions)
          if (_selected.contains(suggestion.cardKey)) suggestion,
      ];

  @override
  Widget build(BuildContext context) {
    // Blok może nieść trzy różne rzeczy: karty ćwiczeń, propozycję całego
    // zestawu i prośbę o analizę. Każda z nich działa samodzielnie.
    final extras = <Widget>[
      if (widget.reply.setSuggestion != null)
        AiSetSuggestionCard(
          suggestion: widget.reply.setSuggestion!,
          messageId: widget.messageId,
        ),
      if (widget.reply.planAnalysisPlanId.isNotEmpty)
        AiPlanAnalysisPrompt(
          planId: widget.reply.planAnalysisPlanId,
          planName: widget.reply.planAnalysisPlanName,
        ),
    ];
    if (_suggestions.isEmpty) {
      return extras.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: extras,
            );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCardsBlock(context, theme, scheme),
        ...extras,
      ],
    );
  }

  Widget _buildCardsBlock(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('ai_cards_toggle'),
            borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.fitness_center_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Proponowane ćwiczenia (${_suggestions.length})',
                      style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800, color: scheme.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_suggestions.length > 1)
                    IconButton(
                      key: const Key('ai_cards_selection_mode'),
                      visualDensity: VisualDensity.compact,
                      tooltip: _selectionMode
                          ? 'Zakończ wybieranie'
                          : 'Wybierz kilka',
                      icon: Icon(
                        _selectionMode
                            ? Icons.check_box_rounded
                            : Icons.checklist_rounded,
                        size: 18,
                      ),
                      onPressed: () => setState(() {
                        _selectionMode = !_selectionMode;
                        if (!_selectionMode) _selected.clear();
                        _expanded = true;
                      }),
                    ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (widget.reply.reasoningSummary.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  widget.reply.reasoningSummary,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            for (final suggestion in _suggestions)
              AiExerciseCard(
                key: Key('ai_card_${suggestion.cardKey}'),
                suggestion: suggestion,
                messageId: widget.messageId,
                selectionMode: _selectionMode,
                selected: _selected.contains(suggestion.cardKey),
                onSelectedChanged: (value) => setState(() {
                  if (value) {
                    _selected.add(suggestion.cardKey);
                  } else {
                    _selected.remove(suggestion.cardKey);
                  }
                }),
              ),
            if (_selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          key: const Key('ai_cards_select_all'),
                          onPressed: () => setState(() {
                            _selected
                              ..clear()
                              ..addAll(
                                  _suggestions.map((item) => item.cardKey));
                          }),
                          child: const Text('Zaznacz wszystkie'),
                        ),
                        TextButton(
                          onPressed: () => setState(_selected.clear),
                          child: const Text('Wyczyść'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('ai_cards_bulk_to_base'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => _bulkAddToLibrary(context),
                          icon: const Icon(Icons.library_add_rounded, size: 16),
                          label: const Text('Dodaj wybrane do bazy'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('ai_cards_bulk_to_plan'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => _bulkAddToPlan(context),
                          icon: const Icon(Icons.playlist_add_rounded, size: 16),
                          label: const Text('Dodaj wybrane do zestawu'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('ai_cards_bulk_new_plan'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => _createPlanFromSelection(context),
                          icon: const Icon(Icons.add_box_rounded, size: 16),
                          label: const Text('Utwórz zestaw z wybranych'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (widget.reply.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final warning in widget.reply.warnings)
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
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _bulkAddToLibrary(BuildContext context) async {
    final store = AppScope.read(context);
    final chosen = _selectedSuggestions;
    var added = 0;
    var skipped = 0;
    for (final suggestion in chosen) {
      if (suggestion.alreadyInDatabase) {
        skipped++;
        continue;
      }
      final duplicates = store.findDuplicatesForSuggestion(suggestion);
      if (hasLikelyDuplicate(duplicates)) {
        skipped++;
        continue;
      }
      await store.addCustomExercise(
        store.exerciseDraftFromSuggestion(suggestion,
            conversationMessageId: widget.messageId),
      );
      added++;
    }
    if (!context.mounted) return;
    showError(
      context,
      'Dodano $added ${added == 1 ? 'ćwiczenie' : 'ćwiczeń'} do bazy'
      '${skipped > 0 ? ', pominięto $skipped już istniejących' : ''}.',
    );
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  Future<void> _bulkAddToPlan(BuildContext context) async {
    final target = await showPlanDayPickerSheet(context);
    if (target == null || !context.mounted) return;
    final store = AppScope.read(context);
    var added = 0;
    for (final suggestion in _selectedSuggestions) {
      final exerciseId = await _ensureExerciseId(store, suggestion);
      if (exerciseId == null) continue;
      final ok = await store.addExerciseToPlanDay(
        planId: target.planId,
        dayIndex: target.dayIndex,
        exerciseId: exerciseId,
      );
      if (ok) added++;
    }
    if (!context.mounted) return;
    showError(context,
        'Dodano $added ${added == 1 ? 'ćwiczenie' : 'ćwiczeń'} do zestawu.');
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  Future<void> _createPlanFromSelection(BuildContext context) async {
    final store = AppScope.read(context);
    final chosen = _selectedSuggestions;
    if (chosen.isEmpty) return;

    final exerciseIds = <String>[];
    for (final suggestion in chosen) {
      final id = await _ensureExerciseId(store, suggestion);
      if (id != null) exerciseIds.add(id);
    }
    if (exerciseIds.isEmpty || !context.mounted) return;

    final config = await showModalBottomSheet<_NewPlanFromCardsConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => const _NewPlanFromCardsSheet(),
    );
    if (config == null || !context.mounted) return;

    final plan = await _buildPlanFromExerciseIds(
      store,
      exerciseIds: exerciseIds,
      config: config,
      conversationMessageId: widget.messageId,
    );
    if (!context.mounted) return;
    showError(context, 'Utworzono zestaw „${plan.name}".');
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }
}

/// Propozycja CAŁEGO zestawu zwrócona przez AI w rozmowie.
///
/// Pokazuje rozpiskę dni i ćwiczeń oraz jeden przycisk tworzący zestaw.
/// Nic nie zapisuje samo z siebie — dopiero kliknięcie użytkownika.
class AiSetSuggestionCard extends StatefulWidget {
  const AiSetSuggestionCard({
    super.key,
    required this.suggestion,
    this.messageId = '',
  });

  final AiSetSuggestion suggestion;
  final String messageId;

  @override
  State<AiSetSuggestionCard> createState() => _AiSetSuggestionCardState();
}

class _AiSetSuggestionCardState extends State<AiSetSuggestionCard> {
  bool _busy = false;

  Future<void> _create(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.read(context);
      final now = DateTime.now();
      final days = <WorkoutDay>[];

      for (var index = 0; index < widget.suggestion.days.length; index++) {
        final day = widget.suggestion.days[index];
        final items = <PlanItem>[];
        for (final exercise in day.exercises) {
          final id = await _ensureExerciseId(store, exercise);
          if (id == null) continue;
          if (items.any((item) => item.exerciseId == id)) continue;
          final def = ExerciseRepo.byId(id, store.customExercises);
          // Parametry z automatycznego systemu prowadzenia; wartości podane
          // przez AI nadpisują je tylko wtedy, gdy je faktycznie podała.
          final base = store.recommendedPlanItemFor(def);
          items.add(base.copyWith(
            sets: exercise.suggestedSets > 0 ? exercise.suggestedSets : base.sets,
            reps: exercise.suggestedReps > 0 && base.reps > 0
                ? exercise.suggestedReps
                : base.reps,
            restSeconds: exercise.suggestedRestSeconds > 0
                ? exercise.suggestedRestSeconds
                : base.restSeconds,
          ));
        }
        if (items.isEmpty) continue;
        days.add(WorkoutDay(
          weekday: day.weekday > 0 ? day.weekday : (index % 7) + 1,
          title: day.title,
          items: items,
          kind: WorkoutDayKind.strength,
        ));
      }

      if (days.isEmpty) {
        if (!context.mounted) return;
        showError(context,
            'Nie udało się zbudować zestawu — brak rozpoznanych ćwiczeń.');
        return;
      }

      final plan = WorkoutPlan(
        id: 'plan_${idNow()}',
        name: widget.suggestion.name.trim().isEmpty
            ? 'Zestaw od Trenera AI'
            : widget.suggestion.name.trim(),
        days: days,
        note: widget.suggestion.note.trim().isEmpty
            ? 'Zestaw zaproponowany przez Trenera AI w rozmowie.'
            : widget.suggestion.note.trim(),
        goal: normalizeWorkoutPlanGoal(
          widget.suggestion.goal.trim().isEmpty
              ? store.settings.goal
              : widget.suggestion.goal,
        ),
        level: normalizeTrainingLevel(store.settings.level),
        allowAnyDay: true,
        origin: PlanOrigin(
          creationMode: PlanCreationMode.fullyAiGenerated,
          sourceType: PlanSourceType.aiChat,
          createdAt: now,
          updatedAt: now,
          createdByUserId: trainerAccountService.user?.uid ?? '',
          sourceMessageId: widget.messageId,
          aiEngine: 'Trener AI',
        ),
      );
      await store.addWorkoutPlan(plan);
      if (!context.mounted) return;
      showError(context, 'Utworzono zestaw „${plan.name}".');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exerciseCount = widget.suggestion.allExercises.length;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: scheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.suggestion.name.trim().isEmpty
                      ? 'Proponowany zestaw'
                      : widget.suggestion.name,
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: scheme.tertiary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.suggestion.days.length} '
            '${widget.suggestion.days.length == 1 ? 'dzień' : 'dni'} · '
            '$exerciseCount ćwiczeń',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final day in widget.suggestion.days)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.title,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  for (final exercise in day.exercises)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• ${exercise.name}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('ai_set_suggestion_create'),
            onPressed: _busy ? null : () => _create(context),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_box_rounded, size: 16),
            label: const Text('Utwórz ten zestaw'),
          ),
        ],
      ),
    );
  }
}

/// Przycisk otwierający analizę zestawu, o którą użytkownik poprosił w czacie.
class AiPlanAnalysisPrompt extends StatelessWidget {
  const AiPlanAnalysisPrompt({
    super.key,
    required this.planId,
    required this.planName,
  });

  final String planId;
  final String planName;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    // Zestaw mógł zostać w międzyczasie usunięty — wtedy nie pokazujemy nic.
    if (!store.plans.any((plan) => plan.id == planId)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  planName.isEmpty ? 'Analiza zestawu' : planName,
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pełna analiza pokaże ocenę, wykryte problemy i propozycje zmian. '
            'Nic nie zmieni się bez Twojego zatwierdzenia.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('ai_open_plan_analysis'),
            onPressed: () => openPlanAiAnalysis(context, planId),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Otwórz analizę zestawu'),
          ),
        ],
      ),
    );
  }
}

/// Zapewnia, że ćwiczenie z karty MA identyfikator w bazie.
/// Gdy go nie ma — zapisuje ćwiczenie jako własne i zwraca nowe id.
Future<String?> _ensureExerciseId(
  AppStore store,
  AiExerciseSuggestion suggestion,
) async {
  if (suggestion.exerciseId.trim().isNotEmpty) {
    final existing =
        ExerciseRepo.byIdOrNull(suggestion.exerciseId.trim(), store.customExercises);
    if (existing != null) return existing.id;
  }
  final duplicates = store.findDuplicatesForSuggestion(suggestion);
  final exact = duplicates
      .where((match) => match.strength == DuplicateMatchStrength.exact);
  if (exact.isNotEmpty) return exact.first.exercise.id;

  final draft = store.exerciseDraftFromSuggestion(suggestion);
  await store.addCustomExercise(draft);
  return draft.id;
}

/// Buduje i zapisuje zestaw z listy ćwiczeń wybranych w czacie.
Future<WorkoutPlan> _buildPlanFromExerciseIds(
  AppStore store, {
  required List<String> exerciseIds,
  required _NewPlanFromCardsConfig config,
  String conversationMessageId = '',
}) async {
  final now = DateTime.now();
  final days = <WorkoutDay>[];
  final perDay = (exerciseIds.length / config.days).ceil().clamp(1, 20);

  for (var dayIndex = 0; dayIndex < config.days; dayIndex++) {
    final slice = exerciseIds.skip(dayIndex * perDay).take(perDay).toList();
    if (slice.isEmpty) break;
    final items = <PlanItem>[];
    for (final id in slice) {
      final def = ExerciseRepo.byId(id, store.customExercises);
      // Parametry z automatycznego systemu prowadzenia, a gdy użytkownik
      // podał własne serie/powtórzenia w oknie — nadpisujemy tylko je.
      final base = store.recommendedPlanItemFor(def);
      items.add(base.copyWith(
        sets: config.sets > 0 ? config.sets : base.sets,
        reps: config.reps > 0 && base.reps > 0 ? config.reps : base.reps,
      ));
    }
    days.add(WorkoutDay(
      weekday: (dayIndex % 7) + 1,
      title: config.days == 1 ? 'Trening' : 'Dzień ${dayIndex + 1}',
      items: items,
      kind: WorkoutDayKind.strength,
    ));
  }

  final plan = WorkoutPlan(
    id: 'plan_${idNow()}',
    name: config.name.trim().isEmpty
        ? 'Zestaw z rozmowy z AI'
        : config.name.trim(),
    days: days,
    note: 'Zestaw zbudowany z ćwiczeń zaproponowanych przez Trenera AI.',
    goal: normalizeWorkoutPlanGoal(store.settings.goal),
    level: normalizeTrainingLevel(store.settings.level),
    allowAnyDay: true,
    origin: PlanOrigin(
      creationMode: PlanCreationMode.manualWithAi,
      sourceType: PlanSourceType.aiChat,
      createdAt: now,
      updatedAt: now,
      createdByUserId: trainerAccountService.user?.uid ?? '',
      sourceMessageId: conversationMessageId,
      aiEngine: 'Trener AI',
      aiAssistanceScopes: const {AiAssistanceScope.fillMissingExercises},
    ),
  );
  await store.addWorkoutPlan(plan);
  return plan;
}

class _NewPlanFromCardsConfig {
  const _NewPlanFromCardsConfig({
    required this.name,
    required this.days,
    required this.sets,
    required this.reps,
  });

  final String name;
  final int days;
  final int sets;
  final int reps;
}

class _NewPlanFromCardsSheet extends StatefulWidget {
  const _NewPlanFromCardsSheet();

  @override
  State<_NewPlanFromCardsSheet> createState() => _NewPlanFromCardsSheetState();
}

class _NewPlanFromCardsSheetState extends State<_NewPlanFromCardsSheet> {
  final TextEditingController _name = TextEditingController();
  int _days = 1;
  int _sets = 0;
  int _reps = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 +
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nowy zestaw z wybranych ćwiczeń',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nazwa zestawu'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Dni'),
                  Expanded(
                    child: Slider(
                      value: _days.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$_days',
                      onChanged: (value) =>
                          setState(() => _days = value.round()),
                    ),
                  ),
                  Text('$_days'),
                ],
              ),
              Row(
                children: [
                  const Text('Serie'),
                  Expanded(
                    child: Slider(
                      value: _sets.toDouble(),
                      min: 0,
                      max: 6,
                      divisions: 6,
                      label: _sets == 0 ? 'auto' : '$_sets',
                      onChanged: (value) =>
                          setState(() => _sets = value.round()),
                    ),
                  ),
                  Text(_sets == 0 ? 'auto' : '$_sets'),
                ],
              ),
              Row(
                children: [
                  const Text('Powt.'),
                  Expanded(
                    child: Slider(
                      value: _reps.toDouble(),
                      min: 0,
                      max: 20,
                      divisions: 20,
                      label: _reps == 0 ? 'auto' : '$_reps',
                      onChanged: (value) =>
                          setState(() => _reps = value.round()),
                    ),
                  ),
                  Text(_reps == 0 ? 'auto' : '$_reps'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '„auto" = Trainer dobierze wartości z Twojej historii, celu '
                'i limitów objętości.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('new_plan_from_cards_confirm'),
                onPressed: () => Navigator.pop(
                  context,
                  _NewPlanFromCardsConfig(
                    name: _name.text,
                    days: _days,
                    sets: _sets,
                    reps: _reps,
                  ),
                ),
                child: const Text('Utwórz zestaw'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pojedyncza karta ćwiczenia w rozmowie z AI.
///
/// Karta jest odporna na braki: pokazuje TYLKO te sekcje, dla których AI
/// podało dane, i nigdy nie zapisuje niczego sama.
class AiExerciseCard extends StatefulWidget {
  const AiExerciseCard({
    super.key,
    required this.suggestion,
    this.messageId = '',
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final AiExerciseSuggestion suggestion;
  final String messageId;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  State<AiExerciseCard> createState() => _AiExerciseCardState();
}

class _AiExerciseCardState extends State<AiExerciseCard> {
  /// Blokada podwójnego kliknięcia — bez niej szybkie tapnięcie „Dodaj"
  /// mogłoby utworzyć dwa wpisy.
  bool _busy = false;

  AiExerciseSuggestion get _suggestion => widget.suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recoveryColor = switch (_suggestion.recoveryCompatibility) {
      AiRecoveryCompatibility.good => scheme.primary,
      AiRecoveryCompatibility.moderate => kDeloadColor,
      AiRecoveryCompatibility.poor => scheme.error,
      AiRecoveryCompatibility.unknown => scheme.onSurfaceVariant,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 14)),
          border: Border.all(
            color: widget.selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: widget.selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        key: Key('ai_card_check_${_suggestion.cardKey}'),
                        value: widget.selected,
                        onChanged: (value) =>
                            widget.onSelectedChanged?.call(value ?? false),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _suggestion.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_suggestion.alreadyInDatabase)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.verified_rounded,
                        size: 16, color: scheme.primary),
                  ),
              ],
            ),
            // --- Fakty. Puste pola po prostu się nie pojawiają. ---
            if (_suggestion.primaryMuscles.isNotEmpty ||
                _suggestion.secondaryMuscles.isNotEmpty ||
                _suggestion.equipment.trim().isNotEmpty ||
                _suggestion.difficulty.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_suggestion.primaryMuscles.isNotEmpty)
                    _SmallChip(
                      label: _suggestion.primaryMuscles.take(3).join(', '),
                      icon: Icons.accessibility_new_rounded,
                    ),
                  if (_suggestion.secondaryMuscles.isNotEmpty)
                    _SmallChip(
                      label: _suggestion.secondaryMuscles.take(2).join(', '),
                      icon: Icons.add_circle_outline_rounded,
                    ),
                  if (_suggestion.equipment.trim().isNotEmpty)
                    _SmallChip(
                        label: _suggestion.equipment,
                        icon: Icons.fitness_center_rounded),
                  if (_suggestion.difficulty.trim().isNotEmpty)
                    _SmallChip(
                        label: _suggestion.difficulty,
                        icon: Icons.trending_up_rounded),
                ],
              ),
            ],
            if (_suggestion.recoveryCompatibility !=
                    AiRecoveryCompatibility.unknown ||
                _suggestion.recoveryNote.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.healing_rounded, size: 13, color: recoveryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _suggestion.recoveryNote.trim().isNotEmpty
                          ? _suggestion.recoveryNote
                          : _suggestion.recoveryCompatibility.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: recoveryColor, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (_suggestion.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _suggestion.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_suggestion.reasonRecommended.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Dlaczego: ${_suggestion.reasonRecommended}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _CardAction(
                  key: Key('ai_card_view_${_suggestion.cardKey}'),
                  icon: Icons.visibility_rounded,
                  label: 'Zobacz',
                  onPressed: _busy ? null : () => _view(context),
                ),
                if (!_suggestion.alreadyInDatabase)
                  _CardAction(
                    key: Key('ai_card_add_base_${_suggestion.cardKey}'),
                    icon: Icons.library_add_rounded,
                    label: 'Dodaj do bazy',
                    onPressed: _busy ? null : () => _addToLibrary(context),
                  ),
                _CardAction(
                  key: Key('ai_card_add_plan_${_suggestion.cardKey}'),
                  icon: Icons.playlist_add_rounded,
                  label: 'Dodaj do zestawu',
                  onPressed: _busy ? null : () => _addToPlan(context),
                ),
                _CardAction(
                  key: Key('ai_card_start_${_suggestion.cardKey}'),
                  icon: Icons.play_arrow_rounded,
                  label: 'Rozpocznij',
                  onPressed: _busy ? null : () => _start(context),
                ),
                _CardAction(
                  key: Key('ai_card_swap_${_suggestion.cardKey}'),
                  icon: Icons.swap_horiz_rounded,
                  label: 'Zamień na podobne',
                  onPressed: _busy ? null : () => _showSimilar(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _view(BuildContext context) async {
    final store = AppScope.read(context);
    final existing = _suggestion.exerciseId.trim().isEmpty
        ? null
        : ExerciseRepo.byIdOrNull(
            _suggestion.exerciseId.trim(), store.customExercises);
    if (existing != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseDetailsPage(exerciseId: existing.id),
        ),
      );
      return;
    }
    // Ćwiczenie spoza bazy — pokazujemy podgląd tego, co podała AI.
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _AiSuggestionPreviewSheet(suggestion: _suggestion),
    );
  }

  Future<void> _addToLibrary(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.read(context);
      final duplicates = store.findDuplicatesForSuggestion(_suggestion);
      if (duplicates.isNotEmpty && context.mounted) {
        final decision = await showModalBottomSheet<_DuplicateDecision>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (sheetContext) =>
              _DuplicateExerciseSheet(matches: duplicates),
        );
        if (decision == null || !context.mounted) return;
        switch (decision.action) {
          case _DuplicateAction.cancel:
            return;
          case _DuplicateAction.openExisting:
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ExerciseDetailsPage(exerciseId: decision.exercise!.id),
              ),
            );
            return;
          case _DuplicateAction.addAsVariant:
            await _saveDraft(context, asVariantOf: decision.exercise);
            return;
          case _DuplicateAction.addAnyway:
            await _saveDraft(context);
            return;
        }
      }
      if (!context.mounted) return;
      await _saveDraft(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft(
    BuildContext context, {
    Exercise? asVariantOf,
  }) async {
    final store = AppScope.read(context);
    var draft = store.exerciseDraftFromSuggestion(
      _suggestion,
      conversationMessageId: widget.messageId,
    );
    if (asVariantOf != null) {
      draft = draft.copyWith(
        name: '${asVariantOf.name} — wariant: ${_suggestion.name}',
        category: asVariantOf.category,
        muscles:
            draft.muscles.isEmpty ? asVariantOf.muscles : draft.muscles,
      );
    }
    // Podgląd PRZED zapisem — użytkownik może jeszcze poprawić każde pole.
    if (!context.mounted) return;
    final approved = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _NewExercisePreviewSheet(draft: draft),
    );
    if (approved == null || !context.mounted) return;
    await store.addCustomExercise(approved);
    if (!context.mounted) return;
    showError(context, 'Dodano „${approved.name}" do bazy ćwiczeń.');
  }

  Future<void> _addToPlan(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.read(context);
      final exerciseId = await _ensureExerciseId(store, _suggestion);
      if (exerciseId == null || !context.mounted) return;
      final target = await showPlanDayPickerSheet(context);
      if (target == null || !context.mounted) return;

      // Analiza kolizji PRZED dodaniem: sprzęt, ograniczenia, regeneracja,
      // nakładanie partii i czas dnia.
      final warnings = analyzeExerciseAddition(
        store,
        planId: target.planId,
        dayIndex: target.dayIndex,
        exerciseId: exerciseId,
      );
      if (warnings.isNotEmpty && context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Sprawdź przed dodaniem'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $warning'),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Dodaj mimo to'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }

      final added = await store.addExerciseToPlanDay(
        planId: target.planId,
        dayIndex: target.dayIndex,
        exerciseId: exerciseId,
      );
      if (!context.mounted) return;
      showError(
        context,
        added
            ? 'Dodano do dnia „${target.dayTitle}".'
            : 'To ćwiczenie jest już w dniu „${target.dayTitle}".',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.read(context);
      final exerciseId = await _ensureExerciseId(store, _suggestion);
      if (exerciseId == null || !context.mounted) return;
      final exercise =
          ExerciseRepo.byId(exerciseId, store.customExercises);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseDetailsPage(exerciseId: exercise.id),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSimilar(BuildContext context) async {
    final store = AppScope.read(context);
    final exerciseId = _suggestion.exerciseId.trim();
    final base = exerciseId.isEmpty
        ? null
        : ExerciseRepo.byIdOrNull(exerciseId, store.customExercises);
    final owned = store.settings.equipmentProfile.resolveOwned();
    final limits = store.settings.limitationProfile;

    final alternatives = <Exercise>[];
    if (base != null) {
      final substituteId = bestSubstituteId(
        base,
        owned,
        limits,
        (id) => ExerciseRepo.byId(id, store.customExercises),
      );
      if (substituteId != null) {
        alternatives.add(
            ExerciseRepo.byId(substituteId, store.customExercises));
      }
      final group = primaryMuscleGroupOf(base);
      for (final exercise in ExerciseRepo.combined(store.customExercises)) {
        if (alternatives.length >= 6) break;
        if (exercise.id == base.id) continue;
        if (alternatives.any((item) => item.id == exercise.id)) continue;
        if (primaryMuscleGroupOf(exercise) != group) continue;
        if (!isExerciseAvailable(exercise, owned)) continue;
        if (exerciseViolatesLimitation(exercise, limits)) continue;
        alternatives.add(exercise);
      }
    }
    if (!context.mounted) return;
    if (alternatives.isEmpty) {
      showError(context,
          'Nie znalazłem zamiennika pasującego do Twojego sprzętu.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Podobne ćwiczenia',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              for (final exercise in alternatives)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(exercise.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(exercise.equipment,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ExerciseDetailsPage(exerciseId: exercise.id),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 34),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ============================================================================
// Analiza kolizji przed dodaniem ćwiczenia do dnia
// ============================================================================

/// Sprawdza, co może pójść nie tak przy dodaniu ćwiczenia do dnia zestawu.
///
/// Zwraca listę czytelnych ostrzeżeń — pusta lista oznacza, że nic nie stoi
/// na przeszkodzie. Funkcja NICZEGO nie blokuje; decyzję podejmuje użytkownik.
List<String> analyzeExerciseAddition(
  AppStore store, {
  required String planId,
  required int dayIndex,
  required String exerciseId,
  DateTime? now,
}) {
  final warnings = <String>[];
  final matches = store.plans.where((plan) => plan.id == planId);
  if (matches.isEmpty) return warnings;
  final plan = matches.first;
  if (dayIndex < 0 || dayIndex >= plan.days.length) return warnings;
  final day = plan.days[dayIndex];
  final exercise = ExerciseRepo.byId(exerciseId, store.customExercises);
  Exercise resolve(String id) => ExerciseRepo.byId(id, store.customExercises);

  // Sprzęt.
  final owned = store.settings.equipmentProfile.resolveOwned();
  if (!isExerciseAvailable(exercise, owned)) {
    warnings.add('To ćwiczenie wymaga sprzętu spoza Twojego profilu '
        '(${exercise.equipment}).');
  }
  // Ograniczenia.
  if (exerciseViolatesLimitation(exercise, store.settings.limitationProfile)) {
    warnings.add('Ćwiczenie koliduje z Twoimi ograniczeniami treningowymi.');
  }
  // Powtórzenie.
  if (day.items.any((item) => item.exerciseId == exerciseId)) {
    warnings.add('To ćwiczenie już jest w dniu „${day.title}".');
  }
  // Regeneracja.
  final recovery = store.muscleRecoveryMap(now ?? DateTime.now());
  final worst = worstRecoveryForExercise(exercise, recovery);
  if (worst != null && worst.$2 < 60) {
    warnings.add('${worst.$1.label} ma dziś ${worst.$2.round()}% regeneracji '
        '— rozważ inny dzień albo mniejszą objętość.');
  }
  // Nakładanie partii w dniu.
  final group = primaryMuscleGroupOf(exercise);
  var groupExercises = 0;
  var groupSets = 0;
  var dayMinutes = 0;
  for (final item in day.items) {
    final def = resolve(item.exerciseId);
    dayMinutes += estimatePlanItemMinutes(item, def);
    final impacts = def.effectiveMuscleImpacts
        .map((impact) => muscleGroupOfBodyMuscle(impact.muscleGroup));
    if (impacts.contains(group)) {
      groupExercises++;
      groupSets += item.sets;
    }
  }
  if (groupExercises >= 3) {
    warnings.add('To ćwiczenie mocno angażuje ${group.label.toLowerCase()}. '
        'W wybranym dniu są już $groupExercises ćwiczenia obciążające tę partię '
        '($groupSets serii).');
  }
  // Czas dnia.
  final available = store.settings.preferredWorkoutMinutes;
  if (available > 0) {
    final added =
        estimatePlanItemMinutes(store.recommendedPlanItemFor(exercise), exercise);
    if (dayMinutes + added > available + 10) {
      warnings.add('Dzień urośnie do około ${dayMinutes + added} min, '
          'a Twój limit to $available min.');
    }
  }
  return warnings;
}

// ============================================================================
// Wybór zestawu i dnia
// ============================================================================

/// Wybrany cel: zestaw + dzień.
class PlanDayTarget {
  const PlanDayTarget({
    required this.planId,
    required this.dayIndex,
    required this.dayTitle,
  });

  final String planId;
  final int dayIndex;
  final String dayTitle;
}

/// Pokazuje wybór zestawu i dnia (z opcją utworzenia nowego zestawu).
///
/// Arkusz montowany jest w overlayu Nawigatora, więc NIE zakładamy, że znajdzie
/// [AppScope] nad sobą — przekazujemy sklep jawnie z kontekstu wywołania.
Future<PlanDayTarget?> showPlanDayPickerSheet(BuildContext context) {
  final store = AppScope.read(context);
  return showModalBottomSheet<PlanDayTarget>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AppScope(
      store: store,
      child: const _PlanDayPickerSheet(),
    ),
  );
}

class _PlanDayPickerSheet extends StatefulWidget {
  const _PlanDayPickerSheet();

  @override
  State<_PlanDayPickerSheet> createState() => _PlanDayPickerSheetState();
}

class _PlanDayPickerSheetState extends State<_PlanDayPickerSheet> {
  String? _planId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final plans =
        store.plans.where((plan) => !plan.origin.isArchived).toList();
    final selected = _planId == null
        ? null
        : plans.where((plan) => plan.id == _planId).firstOrNull;

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
            Text(
              selected == null ? 'Wybierz zestaw' : 'Wybierz dzień',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (selected == null) ...[
              if (plans.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nie masz jeszcze żadnego zestawu.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              for (final plan in plans)
                ListTile(
                  key: Key('picker_plan_${plan.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(plan.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${plan.days.length} dni',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  leading: PlanOriginChip(mode: plan.origin.creationMode),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(() => _planId = plan.id),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('picker_create_plan'),
                onPressed: () async {
                  Navigator.pop(context);
                  await showPlanCreationModeSheet(context);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Utwórz nowy zestaw'),
              ),
            ] else ...[
              for (var index = 0; index < selected.days.length; index++)
                ListTile(
                  key: Key('picker_day_$index'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(selected.days[index].title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${selected.days[index].items.length} ćwiczeń',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => Navigator.pop(
                    context,
                    PlanDayTarget(
                      planId: selected.id,
                      dayIndex: index,
                      dayTitle: selected.days[index].title,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _planId = null),
                child: const Text('Wróć do listy zestawów'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Duplikaty i podgląd nowego ćwiczenia
// ============================================================================

enum _DuplicateAction { openExisting, addAsVariant, addAnyway, cancel }

class _DuplicateDecision {
  const _DuplicateDecision(this.action, [this.exercise]);

  final _DuplicateAction action;
  final Exercise? exercise;
}

class _DuplicateExerciseSheet extends StatelessWidget {
  const _DuplicateExerciseSheet({required this.matches});

  final List<ExerciseDuplicateMatch> matches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = matches.first;
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
            Text(
              // Nagłówek mówi dokładnie tyle, ile wiemy: „prawdopodobnie to
              // samo" tylko przy mocnym dopasowaniu, przy samym podobieństwie
              // wzorca ruchu — „podobne ćwiczenie".
              hasLikelyDuplicate(matches)
                  ? 'To ćwiczenie prawdopodobnie jest już w bazie.'
                  : 'W bazie są podobne ćwiczenia.',
              key: const Key('duplicate_warning'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final match in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(match.exercise.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(match.reason,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  leading: const Icon(Icons.info_outline_rounded, size: 20),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton.tonal(
              key: const Key('duplicate_open_existing'),
              onPressed: () => Navigator.pop(
                context,
                _DuplicateDecision(
                    _DuplicateAction.openExisting, best.exercise),
              ),
              child: const Text('Otwórz istniejące'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('duplicate_add_variant'),
              onPressed: () => Navigator.pop(
                context,
                _DuplicateDecision(
                    _DuplicateAction.addAsVariant, best.exercise),
              ),
              child: const Text('Dodaj jako wariant'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('duplicate_add_anyway'),
              onPressed: () => Navigator.pop(
                context,
                const _DuplicateDecision(_DuplicateAction.addAnyway),
              ),
              child: const Text('Dodaj mimo wszystko'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const _DuplicateDecision(_DuplicateAction.cancel),
              ),
              child: const Text('Anuluj'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Podgląd nowego ćwiczenia PRZED zapisaniem — pola można poprawić.
class _NewExercisePreviewSheet extends StatefulWidget {
  const _NewExercisePreviewSheet({required this.draft});

  final Exercise draft;

  @override
  State<_NewExercisePreviewSheet> createState() =>
      _NewExercisePreviewSheetState();
}

class _NewExercisePreviewSheetState extends State<_NewExercisePreviewSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.draft.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.draft.description);
  late final TextEditingController _muscles =
      TextEditingController(text: widget.draft.muscles.join(', '));
  late final TextEditingController _equipment =
      TextEditingController(text: widget.draft.equipment);
  late String _level = widget.draft.level;
  bool _generating = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _muscles.dispose();
    _equipment.dispose();
    super.dispose();
  }

  Exercise _build() {
    final muscles = _muscles.text
        .split(RegExp(r'[,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return widget.draft.copyWith(
      name: _name.text.trim().isEmpty ? widget.draft.name : _name.text.trim(),
      description: _description.text.trim(),
      muscles: muscles.isEmpty ? widget.draft.muscles : muscles,
      equipment: _equipment.text.trim().isEmpty
          ? widget.draft.equipment
          : _equipment.text.trim(),
      level: _level,
      category: muscles.isEmpty ? widget.draft.category : muscles.first,
    );
  }

  Future<void> _generateDescription() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final store = AppScope.read(context);
      final info =
          await store.generateExerciseDescriptionWithGemini(_build());
      if (!mounted) return;
      setState(() {
        if (info.description.trim().isNotEmpty) {
          _description.text = info.description.trim();
        }
        final muscles = <String>[
          ...info.primaryMuscles,
          ...info.secondaryMuscles,
        ].where((value) => value.trim().isNotEmpty).toList();
        if (muscles.isNotEmpty) _muscles.text = muscles.join(', ');
        if (info.equipment.trim().isNotEmpty) {
          _equipment.text = info.equipment.trim();
        }
        if (info.level.trim().isNotEmpty) {
          _level = normalizeTrainingLevel(info.level);
        }
      });
    } catch (error) {
      if (!mounted) return;
      showError(context, 'Gemini: $error');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 +
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nowe ćwiczenie',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Źródło: Trener AI. Sprawdź dane przed zapisaniem.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nazwa'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _muscles,
                decoration: const InputDecoration(
                  labelText: 'Mięśnie (po przecinku)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _equipment,
                decoration: const InputDecoration(labelText: 'Sprzęt'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _level,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Poziom'),
                items: [
                  for (final level in kTrainingLevels)
                    DropdownMenuItem(value: level, child: Text(level)),
                ],
                onChanged: (value) =>
                    setState(() => _level = value ?? _level),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Opis'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _generating ? null : _generateDescription,
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Uzupełnij opis przez Gemini'),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('new_exercise_confirm'),
                onPressed: () => Navigator.pop(context, _build()),
                child: const Text('Zapisz w bazie'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Anuluj'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Podgląd ćwiczenia, którego nie ma w bazie (dane wyłącznie od AI).
class _AiSuggestionPreviewSheet extends StatelessWidget {
  const _AiSuggestionPreviewSheet({required this.suggestion});

  final AiExerciseSuggestion suggestion;

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
            Text(suggestion.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Ćwiczenie zaproponowane przez Trenera AI — nie ma go '
                'jeszcze w Twojej bazie.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (suggestion.primaryMuscles.isNotEmpty)
              _PreviewRow(
                  label: 'Główne partie',
                  value: suggestion.primaryMuscles.join(', ')),
            if (suggestion.secondaryMuscles.isNotEmpty)
              _PreviewRow(
                  label: 'Pomocnicze',
                  value: suggestion.secondaryMuscles.join(', ')),
            if (suggestion.equipment.trim().isNotEmpty)
              _PreviewRow(label: 'Sprzęt', value: suggestion.equipment),
            if (suggestion.difficulty.trim().isNotEmpty)
              _PreviewRow(label: 'Poziom', value: suggestion.difficulty),
            if (suggestion.recoveryNote.trim().isNotEmpty)
              _PreviewRow(
                  label: 'Regeneracja', value: suggestion.recoveryNote),
            if (suggestion.description.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(suggestion.description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
            ],
            if (!suggestion.hasAnyDetail)
              Text(
                'AI podało tylko nazwę. Po dodaniu do bazy możesz uzupełnić '
                'resztę ręcznie albo przez Gemini.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
