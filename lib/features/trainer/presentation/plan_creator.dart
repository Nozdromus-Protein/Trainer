// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Kreator własnych zestawów: wybór trybu (ręcznie / ręcznie z AI / w pełni AI),
// wieloetapowy kreator i podgląd przed zapisem.
part of '../../../main.dart';

// ============================================================================
// Etap: Własne zestawy — wybór sposobu tworzenia
// ============================================================================

/// Otwiera wybór sposobu utworzenia zestawu (A / B / C).
Future<void> showPlanCreationModeSheet(BuildContext context) async {
  final mode = await showModalBottomSheet<PlanCreationMode>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => const _PlanCreationModeSheet(),
  );
  if (mode == null || !context.mounted) return;
  await openPlanCreatorWizard(context, mode);
}

class _PlanCreationModeSheet extends StatelessWidget {
  const _PlanCreationModeSheet();

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
            Text(
              'Utwórz własny zestaw',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Wybierz, jak chcesz go ułożyć. Zawsze możesz później wszystko '
              'zmienić ręcznie.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _ModeOptionCard(
              key: const Key('plan_mode_manual'),
              icon: Icons.edit_note_rounded,
              title: 'Utwórz ręcznie',
              subtitle:
                  'Sam wybierasz dni, ćwiczenia, kolejność, serie i przerwy. '
                  'AI niczego nie zmienia bez Twojego polecenia.',
              mode: PlanCreationMode.manual,
            ),
            const SizedBox(height: 10),
            _ModeOptionCard(
              key: const Key('plan_mode_manual_ai'),
              icon: Icons.auto_fix_high_rounded,
              title: 'Utwórz ręcznie z pomocą AI',
              subtitle:
                  'Ty budujesz podstawę, a AI pomaga tylko w tym, co zaznaczysz '
                  '— i każdą zmianę pokazuje do zatwierdzenia.',
              mode: PlanCreationMode.manualWithAi,
            ),
            const SizedBox(height: 10),
            _ModeOptionCard(
              key: const Key('plan_mode_full_ai'),
              icon: Icons.smart_toy_rounded,
              title: 'Wygeneruj cały zestaw przez AI',
              subtitle:
                  'AI układa komplet na podstawie Twojego profilu, sprzętu, '
                  'regeneracji i historii. Zobaczysz pełny podgląd przed zapisem.',
              mode: PlanCreationMode.fullyAiGenerated,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOptionCard extends StatelessWidget {
  const _ModeOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mode,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final PlanCreationMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(uiCornerRadius(context, 18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 18)),
        onTap: () => Navigator.pop(context, mode),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Otwiera kreator zestawu w wybranym trybie.
Future<WorkoutPlan?> openPlanCreatorWizard(
  BuildContext context,
  PlanCreationMode mode,
) {
  return Navigator.of(context).push<WorkoutPlan>(
    MaterialPageRoute<WorkoutPlan>(
      builder: (_) => PlanCreatorPage(mode: mode),
    ),
  );
}

// ============================================================================
// Kreator krok po kroku
// ============================================================================

class PlanCreatorPage extends StatefulWidget {
  const PlanCreatorPage({super.key, required this.mode});

  final PlanCreationMode mode;

  @override
  State<PlanCreatorPage> createState() => _PlanCreatorPageState();
}

class _PlanCreatorPageState extends State<PlanCreatorPage> {
  late PlanBlueprint _blueprint;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _customGoalController = TextEditingController();
  int _step = 0;
  bool _initialized = false;
  bool _saving = false;

  /// Gotowy podgląd zestawu (kroki AI). `null` = jeszcze nie policzony.
  BuiltPlan? _preview;
  PlanQualityReport? _previewQuality;

  /// Kroki widoczne w danym trybie. Tryb w pełni ręczny pomija checklistę AI.
  ///
  /// Każdy krok to JEDNO pytanie przewodnie plus opcjonalne doprecyzowania —
  /// dzięki temu ekran zostaje krótki, a decyzje nie mieszają się ze sobą.
  List<String> get _steps => [
        'Cel',
        'Partie',
        'Dni',
        'Czas',
        'Sprzęt',
        'Ograniczenia',
        'Preferencje',
        if (widget.mode == PlanCreationMode.manualWithAi) 'Pomoc AI',
        'Podgląd',
      ];

  bool get _isLastStep => _step == _steps.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final store = AppScope.read(context);
    _blueprint = store.defaultPlanBlueprint(widget.mode);
    // Tryb „z pomocą AI" startuje z bezpiecznym, sensownym zestawem zakresów —
    // użytkownik i tak może odznaczyć każdy z nich.
    if (widget.mode == PlanCreationMode.manualWithAi) {
      _blueprint = _blueprint.copyWith(aiScopes: {
        AiAssistanceScope.fillMissingExercises,
        AiAssistanceScope.setsAndReps,
        AiAssistanceScope.rest,
        AiAssistanceScope.equipmentCheck,
        AiAssistanceScope.muscleBalance,
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customGoalController.dispose();
    super.dispose();
  }

  void _update(PlanBlueprint next) {
    setState(() {
      _blueprint = next;
      // Każda zmiana wejścia unieważnia policzony podgląd.
      _preview = null;
      _previewQuality = null;
    });
  }

  void _buildPreview() {
    final store = AppScope.read(context);
    final blueprint = _blueprint.copyWith(
      name: _nameController.text.trim(),
      customPurposeText: _customGoalController.text.trim(),
    );
    // Kto dobiera ćwiczenia?
    //  - tryb ręczny: NIKT poza użytkownikiem,
    //  - tryb z pomocą AI: tylko gdy użytkownik zaznaczył „uzupełnij
    //    brakujące ćwiczenia" — inaczej dostaje sam szkielet dni,
    //  - tryb w pełni AI: zawsze.
    final aiFillsExercises = widget.mode ==
            PlanCreationMode.fullyAiGenerated ||
        (widget.mode == PlanCreationMode.manualWithAi &&
            blueprint.aiScopes.contains(AiAssistanceScope.fillMissingExercises));

    if (!aiFillsExercises) {
      final empty = buildEmptyManualPlan(
        blueprint,
        planId: 'preview_${blueprint.hashCode}',
      );
      final scopes = blueprint.aiScopes;
      setState(() {
        _blueprint = blueprint;
        _preview = BuiltPlan(
          plan: empty,
          decisions: [
            if (widget.mode == PlanCreationMode.manual)
              'Tryb ręczny: zestaw powstaje pusty — ćwiczenia dodajesz sam '
                  'w szczegółach dnia.'
            else
              'Nie zaznaczyłeś „${AiAssistanceScope.fillMissingExercises.label}", '
                  'więc AI nie dobiera ćwiczeń — dodajesz je sam.',
            if (widget.mode == PlanCreationMode.manualWithAi &&
                scopes.isNotEmpty)
              'AI pomoże w: '
                  '${scopes.map((scope) => scope.label.toLowerCase()).join(', ')} '
                  '— po dodaniu ćwiczeń uruchom analizę zestawu.',
          ],
        );
        _previewQuality = null;
      });
      return;
    }
    final built = store.previewPlanFromBlueprint(blueprint);
    setState(() {
      _blueprint = blueprint;
      _preview = built;
      _previewQuality = store.planQuality(built.plan);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = AppScope.read(context);
      final plan = await store.createPlanFromBlueprint(
        _blueprint,
        prebuilt: _preview?.plan.copyWith(id: 'plan_${idNow()}'),
      );
      if (!mounted) return;
      Navigator.of(context).pop(plan);
      if (!context.mounted) return;
      showError(context, 'Zapisano zestaw „${plan.name}".');
    } catch (error) {
      if (!mounted) return;
      showError(context, 'Nie udało się zapisać zestawu: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (widget.mode) {
      PlanCreationMode.manual => 'Nowy zestaw — ręcznie',
      PlanCreationMode.manualWithAi => 'Nowy zestaw — z pomocą AI',
      PlanCreationMode.fullyAiGenerated => 'Nowy zestaw — generuje AI',
      _ => 'Nowy zestaw',
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _WizardProgressBar(steps: _steps, current: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _buildStep(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => setState(() => _step -= 1),
                        child: const Text('Wstecz'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const Key('plan_creator_next'),
                      onPressed: _saving
                          ? null
                          : () {
                              if (_isLastStep) {
                                _save();
                                return;
                              }
                              setState(() => _step += 1);
                              // Wchodząc na podgląd liczymy zestaw raz —
                              // nigdy w build().
                              if (_isLastStep) _buildPreview();
                            },
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_isLastStep
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded),
                      label: Text(_isLastStep ? 'Zapisz zestaw' : 'Dalej'),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLastStep)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Nic nie zostało jeszcze zapisane.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    final name = _steps[_step];
    switch (name) {
      case 'Cel':
        return _goalStep(context);
      case 'Partie':
        return _priorityStep(context);
      case 'Dni':
        return _daysStep(context);
      case 'Czas':
        return _timeStep(context);
      case 'Sprzęt':
        return _equipmentStep(context);
      case 'Ograniczenia':
        return _limitationsStep(context);
      case 'Preferencje':
        return _preferencesStep(context);
      case 'Pomoc AI':
        return _aiScopeStep(context);
      default:
        return _previewStep(context);
    }
  }

  // --- Krok 1: cel ---
  Widget _goalStep(BuildContext context) {
    return _StepBody(
      title: 'Jaki jest cel tego zestawu?',
      subtitle: 'Cel decyduje o zakresie powtórzeń, przerwach i doborze ruchów.',
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nazwa zestawu (opcjonalnie)',
            hintText: 'np. Push — mój wariant',
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final purpose in PlanPurpose.values)
              ChoiceChip(
                label: Text(purpose.label),
                selected: _blueprint.purpose == purpose,
                onSelected: (_) => _update(_blueprint.copyWith(purpose: purpose)),
              ),
          ],
        ),
        if (_blueprint.purpose == PlanPurpose.custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customGoalController,
            decoration: const InputDecoration(
              labelText: 'Opisz swój cel',
            ),
          ),
        ],
      ],
    );
  }

  // --- Krok 2: partie i zakres zestawu ---
  Widget _priorityStep(BuildContext context) {
    final store = AppScope.of(context);
    final selected = _blueprint.priorityMuscles.toSet();
    final hint = store.goalPriorityHint
        .where((group) => !selected.contains(group))
        .toList();

    return _StepBody(
      title: 'Które partie ma trenować ten zestaw?',
      subtitle: 'Nic nie zaznaczaj, jeżeli chcesz przekrojowy trening '
          'całego ciała.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in kLimitedMuscleGroups)
              FilterChip(
                key: Key('priority_${group.name}'),
                label: Text(group.label),
                selected: selected.contains(group),
                onSelected: (value) {
                  final next = <MuscleGroup>[..._blueprint.priorityMuscles];
                  if (value) {
                    next.add(group);
                  } else {
                    next.remove(group);
                  }
                  // Pierwsze zaznaczenie ustawia zakres na „tylko wybrane" —
                  // to znaczenie, którego użytkownicy się spodziewają.
                  // Suwak niżej pozwala od razu to zmienić.
                  final scope = next.isEmpty
                      ? PlanFocusScope.balanced
                      : (_blueprint.focusScope == PlanFocusScope.balanced
                          ? PlanFocusScope.onlySelected
                          : _blueprint.focusScope);
                  _update(_blueprint.copyWith(
                    priorityMuscles: next,
                    focusScope: scope,
                  ));
                },
              ),
          ],
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 10),
          _HintRow(
            text: 'Z Twojego celu sylwetkowego: '
                '${hint.map((g) => g.label.toLowerCase()).join(', ')}.',
            actionLabel: 'Dodaj',
            onAction: () => _update(_blueprint.copyWith(
              priorityMuscles: <MuscleGroup>[
                ..._blueprint.priorityMuscles,
                ...hint,
              ],
              focusScope: _blueprint.focusScope == PlanFocusScope.balanced
                  ? PlanFocusScope.onlySelected
                  : _blueprint.focusScope,
            )),
          ),
        ],
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 18),
          _WizardSectionLabel(
            title: 'Zakres zestawu',
            hint: 'Decyduje, czy do zestawu wejdzie cokolwiek poza '
                'zaznaczonymi partiami.',
          ),
          const SizedBox(height: 8),
          for (final scope in PlanFocusScope.values)
            _RadioOptionCard(
              key: Key('focus_scope_${scope.key}'),
              title: scope.label,
              subtitle: scope.description,
              selected: _blueprint.focusScope == scope,
              onTap: () => _update(_blueprint.copyWith(focusScope: scope)),
            ),
        ],
      ],
    );
  }

  // --- Krok 6: ograniczenia i poziom ---
  Widget _limitationsStep(BuildContext context) {
    final limits = _blueprint.limitations;
    return _StepBody(
      title: 'Czego mamy unikać?',
      subtitle: 'Zaznaczone ograniczenia wykluczają kolidujące ćwiczenia '
          'z całego zestawu.',
      children: [
        _WizardSectionLabel(
          title: 'Poziom zaawansowania',
          hint: 'Decyduje o trudności dobieranych ćwiczeń.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final level in kTrainingLevels)
              ChoiceChip(
                key: Key('level_${normalizeTrainingLevel(level)}'),
                label: Text(level),
                selected:
                    normalizeTrainingLevel(_blueprint.level) ==
                        normalizeTrainingLevel(level),
                onSelected: (_) => _update(_blueprint.copyWith(level: level)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _WizardSectionLabel(
          title: 'Ograniczenia',
          hint: 'Startujemy z Twojego profilu — możesz je tu zawęzić.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final flag in TrainingLimitation.values)
              FilterChip(
                key: Key('limitation_${flag.key}'),
                label: Text(flag.label),
                selected: limits.flags.contains(flag),
                onSelected: (value) {
                  final next = <TrainingLimitation>{...limits.flags};
                  if (value) {
                    next.add(flag);
                  } else {
                    next.remove(flag);
                  }
                  _update(_blueprint.copyWith(
                    limitations: LimitationProfile(
                      flags: next,
                      customText: limits.customText,
                    ),
                  ));
                },
              ),
          ],
        ),
        if (limits.customText.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _HintRow(text: 'Z profilu: ${limits.customText.trim()}'),
        ],
      ],
    );
  }

  // --- Krok 3: dni ---
  Widget _daysStep(BuildContext context) {
    return _StepBody(
      title: 'Ile dni w tygodniu?',
      subtitle: 'Możesz wskazać konkretne dni albo zostawić plan elastyczny.',
      children: [
        Row(
          children: [
            const Text('Dni'),
            Expanded(
              child: Slider(
                value: _blueprint.daysPerWeek.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '${_blueprint.daysPerWeek}',
                onChanged: (value) =>
                    _update(_blueprint.copyWith(daysPerWeek: value.round())),
              ),
            ),
            Text('${_blueprint.daysPerWeek}'),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _blueprint.flexibleSchedule,
          title: const Text('Plan elastyczny'),
          subtitle: const Text('Bez przypisania do konkretnych dni tygodnia'),
          onChanged: (value) => _update(_blueprint.copyWith(
            flexibleSchedule: value,
            weekdays: value ? const <int>[] : _blueprint.weekdays,
          )),
        ),
        if (!_blueprint.flexibleSchedule) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var weekday = 1; weekday <= 7; weekday++)
                FilterChip(
                  label: Text(weekdayShortName(weekday)),
                  selected: _blueprint.weekdays.contains(weekday),
                  onSelected: (value) {
                    final next = <int>[..._blueprint.weekdays];
                    if (value) {
                      next.add(weekday);
                    } else {
                      next.remove(weekday);
                    }
                    next.sort();
                    _update(_blueprint.copyWith(weekdays: next));
                  },
                ),
            ],
          ),
        ],
        // Podział tygodnia ma sens tylko wtedy, gdy zestaw obejmuje więcej
        // niż wybrane partie — inaczej każdy dzień i tak pracuje na tych samych.
        if (!(_blueprint.focusScope == PlanFocusScope.onlySelected &&
            _blueprint.priorityMuscles.isNotEmpty)) ...[
          const SizedBox(height: 18),
          _WizardSectionLabel(
            title: 'Podział tygodnia',
            hint: 'Jak rozłożyć partie na poszczególne dni.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in PlanSplitStyle.values)
                ChoiceChip(
                  key: Key('split_${style.key}'),
                  label: Text(style.label),
                  selected: _blueprint.split == style,
                  onSelected: (_) => _update(_blueprint.copyWith(split: style)),
                ),
            ],
          ),
        ] else
          _HintRow(
            text: 'Zestaw zawężony do wybranych partii — każdy dzień pracuje '
                'na tych samych grupach, więc podział tygodnia nie ma tu '
                'zastosowania.',
          ),
      ],
    );
  }

  // --- Krok 4: czas ---
  Widget _timeStep(BuildContext context) {
    const presets = [15, 30, 45, 60, 90];
    return _StepBody(
      title: 'Ile masz czasu na trening?',
      subtitle: 'Czas ogranicza liczbę ćwiczeń i długość przerw.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in presets)
              ChoiceChip(
                label: Text(minutes == 90 ? '60–90 min' : '$minutes min'),
                selected: _blueprint.minutesPerSession == minutes,
                onSelected: (_) =>
                    _update(_blueprint.copyWith(minutesPerSession: minutes)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Własny czas'),
            Expanded(
              child: Slider(
                value: _blueprint.minutesPerSession.clamp(10, 120).toDouble(),
                min: 10,
                max: 120,
                divisions: 22,
                label: '${_blueprint.minutesPerSession} min',
                onChanged: (value) => _update(
                    _blueprint.copyWith(minutesPerSession: value.round())),
              ),
            ),
            Text('${_blueprint.minutesPerSession}'),
          ],
        ),
        const SizedBox(height: 18),
        _WizardSectionLabel(
          title: 'Przerwy między seriami',
          hint: 'Krótsze przerwy = więcej pracy w tym samym czasie.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rest in PlanRestPreference.values)
              ChoiceChip(
                key: Key('rest_${rest.key}'),
                label: Text(rest.label),
                selected: _blueprint.restPreference == rest,
                onSelected: (_) =>
                    _update(_blueprint.copyWith(restPreference: rest)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _WizardSectionLabel(
          title: 'Liczba ćwiczeń na dzień',
          hint: 'Zostaw „automatycznie", żeby wyliczyć ją z dostępnego czasu.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _blueprint.exercisesPerDay.clamp(0, 10).toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: _blueprint.exercisesPerDay == 0
                    ? 'auto'
                    : '${_blueprint.exercisesPerDay}',
                onChanged: (value) => _update(
                    _blueprint.copyWith(exercisesPerDay: value.round())),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                _blueprint.exercisesPerDay == 0
                    ? 'auto'
                    : '${_blueprint.exercisesPerDay}',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Krok 5: sprzęt ---
  Widget _equipmentStep(BuildContext context) {
    final profile = _blueprint.equipment;
    return _StepBody(
      title: 'Jaki sprzęt jest dostępny?',
      subtitle: 'Startujemy z Twojego profilu — możesz zawęzić go dla tego '
          'zestawu.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in EquipmentMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: profile.mode == mode,
                onSelected: (_) => _update(
                  _blueprint.copyWith(
                    equipment: profile.copyWith(mode: mode),
                  ),
                ),
              ),
          ],
        ),
        if (profile.mode.isUserSelectable) ...[
          const SizedBox(height: 14),
          Text('Posiadany sprzęt',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in EquipmentType.values)
                if (!kAlwaysAvailableEquipment.contains(type) &&
                    type != EquipmentType.other)
                  FilterChip(
                    label: Text(type.label),
                    selected: profile.customOwned.contains(type),
                    onSelected: (value) {
                      final next = <EquipmentType>{...profile.customOwned};
                      if (value) {
                        next.add(type);
                      } else {
                        next.remove(type);
                      }
                      _update(_blueprint.copyWith(
                        equipment: profile.copyWith(customOwned: next),
                      ));
                    },
                  ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _InfoNote(
          text: 'Dostępne: ${profile.ownedSummary}.',
        ),
      ],
    );
  }

  // --- Krok 6: preferencje ---
  Widget _preferencesStep(BuildContext context) {
    return _StepBody(
      title: 'Jak ma wyglądać trening?',
      subtitle: 'Intensywność, dodatki wokół treningu i Twoje ulubione ruchy.',
      children: [
        _WizardSectionLabel(
          title: 'Intensywność',
          hint: 'Wpływa na liczbę serii, powtórzeń i dobór ćwiczeń.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final level in WorkoutIntensityLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: _blueprint.intensity == level,
                onSelected: (_) =>
                    _update(_blueprint.copyWith(intensity: level)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _WizardSectionLabel(
          title: 'Wokół treningu',
          hint: 'Rozgrzewkę i rozciąganie prowadzą osobne moduły — nie '
              'zajmują miejsca w dniu treningowym.',
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _blueprint.includeWarmup,
          title: const Text('Rozgrzewka'),
          onChanged: (value) =>
              _update(_blueprint.copyWith(includeWarmup: value ?? true)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _blueprint.includeCooldown,
          title: const Text('Schłodzenie'),
          onChanged: (value) =>
              _update(_blueprint.copyWith(includeCooldown: value ?? true)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _blueprint.includeMobility,
          title: const Text('Mobilność'),
          onChanged: (value) =>
              _update(_blueprint.copyWith(includeMobility: value ?? false)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _blueprint.includeCardio,
          title: const Text('Cardio'),
          onChanged: (value) =>
              _update(_blueprint.copyWith(includeCardio: value ?? false)),
        ),
        const SizedBox(height: 18),
        _WizardSectionLabel(
          title: 'Konkretne ćwiczenia',
          hint: 'Preferowane wejdą jako pierwsze, wykluczone nie pojawią się '
              'w ogóle.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickExercises(context, excluded: false),
          icon: const Icon(Icons.favorite_border_rounded),
          label: Text(_blueprint.preferredExerciseIds.isEmpty
              ? 'Preferowane ćwiczenia'
              : 'Preferowane (${_blueprint.preferredExerciseIds.length})'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickExercises(context, excluded: true),
          icon: const Icon(Icons.block_rounded),
          label: Text(_blueprint.excludedExerciseIds.isEmpty
              ? 'Ćwiczenia wykluczone'
              : 'Wykluczone (${_blueprint.excludedExerciseIds.length})'),
        ),
      ],
    );
  }

  Future<void> _pickExercises(
    BuildContext context, {
    required bool excluded,
  }) async {
    final store = AppScope.read(context);
    final current = excluded
        ? _blueprint.excludedExerciseIds
        : _blueprint.preferredExerciseIds;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _ExerciseMultiPickerSheet(
        title: excluded ? 'Ćwiczenia wykluczone' : 'Preferowane ćwiczenia',
        library: ExerciseRepo.combined(store.customExercises),
        selected: current.toSet(),
      ),
    );
    if (picked == null || !mounted) return;
    _update(excluded
        ? _blueprint.copyWith(excludedExerciseIds: picked)
        : _blueprint.copyWith(preferredExerciseIds: picked));
  }

  // --- Krok 7: zakres pomocy AI ---
  Widget _aiScopeStep(BuildContext context) {
    final selected = _blueprint.aiScopes;
    return _StepBody(
      title: 'W czym ma pomóc AI?',
      subtitle: 'AI zajmie się WYŁĄCZNIE zaznaczonymi punktami. Reszta '
          'zostaje w Twoich rękach.',
      children: [
        // Wrap, nie Row: przy większej czcionce systemowej dwie etykiety
        // nie mieszczą się w jednym wierszu na wąskim telefonie.
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _update(_blueprint.copyWith(
                  aiScopes: AiAssistanceScope.values.toSet())),
              child: const Text('Zaznacz wszystko'),
            ),
            TextButton(
              onPressed: () => _update(
                  _blueprint.copyWith(aiScopes: const <AiAssistanceScope>{})),
              child: const Text('Odznacz wszystko'),
            ),
          ],
        ),
        for (final scope in AiAssistanceScope.values)
          CheckboxListTile(
            key: Key('ai_scope_${scope.key}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: selected.contains(scope),
            title: Text(scope.label),
            onChanged: (value) {
              final next = <AiAssistanceScope>{...selected};
              if (value ?? false) {
                next.add(scope);
              } else {
                next.remove(scope);
              }
              _update(_blueprint.copyWith(aiScopes: next));
            },
          ),
      ],
    );
  }

  // --- Krok 8: podgląd ---
  Widget _previewStep(BuildContext context) {
    final preview = _preview;
    if (preview == null) {
      // Podgląd liczymy po wejściu na krok; gdy z jakiegoś powodu go nie ma,
      // dajemy jawny przycisk zamiast liczyć w build().
      return _StepBody(
        title: 'Podgląd zestawu',
        subtitle: 'Zbuduj podgląd, żeby zobaczyć plan przed zapisaniem.',
        children: [
          FilledButton.icon(
            onPressed: _buildPreview,
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Pokaż podgląd'),
          ),
        ],
      );
    }

    final store = AppScope.read(context);
    final theme = Theme.of(context);
    final quality = _previewQuality;

    return _StepBody(
      title: 'Podgląd zestawu',
      subtitle: 'Sprawdź plan przed zapisaniem — nic nie jest jeszcze zapisane.',
      children: [
        Text(preview.plan.name,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(preview.plan.note,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (quality != null) PlanQualityScoreCard(report: quality),
        const SizedBox(height: 12),
        for (var index = 0; index < preview.plan.days.length; index++)
          _PreviewDayCard(
            day: preview.plan.days[index],
            stats: quality == null || index >= quality.dayStats.length
                ? null
                : quality.dayStats[index],
            resolve: (id) =>
                ExerciseRepo.byId(id, store.customExercises),
          ),
        if (preview.decisions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoNote(text: preview.decisions.join('\n')),
        ],
      ],
    );
  }
}

/// Etykieta sekcji wewnątrz kroku — jeden spójny rytm dla całego kreatora.
class _WizardSectionLabel extends StatelessWidget {
  const _WizardSectionLabel({required this.title, this.hint = ''});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// Wybór jednej opcji z krótkim wyjaśnieniem — czytelniejszy niż chipy tam,
/// gdzie różnica między opcjami wymaga zdania komentarza.
class _RadioOptionCard extends StatelessWidget {
  const _RadioOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 14)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: selected ? scheme.primary : null)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Jednolinijkowa podpowiedź z opcjonalną akcją („Dodaj").
class _HintRow extends StatelessWidget {
  const _HintRow({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lightbulb_outline_rounded,
            size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _WizardProgressBar extends StatelessWidget {
  const _WizardProgressBar({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Krok ${current + 1} z ${steps.length} · ${steps[current]}',
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (current + 1) / steps.length,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Karta oceny zestawu (0–100) z zaletami i sugestiami.
class PlanQualityScoreCard extends StatelessWidget {
  const PlanQualityScoreCard({super.key, required this.report});

  final PlanQualityReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = report.score >= 80
        ? scheme.primary
        : report.score >= 60
            ? kDeloadColor
            : scheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 18)),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Ocena zestawu',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${report.score}/100',
                  key: const Key('plan_quality_score'),
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _FactChip(
                  icon: Icons.fitness_center_rounded,
                  label: '${report.totalExercises} ćwiczeń'),
              _FactChip(
                  icon: Icons.repeat_rounded,
                  label: '${report.totalSets} serii'),
              _FactChip(
                  icon: Icons.schedule_rounded,
                  label: '~${report.estimatedMinutes} min'),
              _FactChip(
                  icon: Icons.calendar_today_rounded,
                  label: '${report.trainingDays} dni'),
            ],
          ),
          if (report.strengths.isNotEmpty) ...[
            const SizedBox(height: 12),
            _NoteList(
              title: 'Zalety',
              icon: Icons.check_circle_outline_rounded,
              color: scheme.primary,
              notes: report.strengths,
            ),
          ],
          if (report.issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NoteList(
              title: 'Wykryte problemy',
              icon: Icons.error_outline_rounded,
              color: scheme.error,
              notes: report.issues,
            ),
          ],
          if (report.suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NoteList(
              title: 'Sugestie',
              icon: Icons.lightbulb_outline_rounded,
              color: kDeloadColor,
              notes: report.suggestions,
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({
    required this.title,
    required this.icon,
    required this.color,
    required this.notes,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<PlanQualityNote> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        for (final note in notes.take(6))
          Padding(
            padding: const EdgeInsets.only(left: 21, bottom: 3),
            child: Text('• ${note.text}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.35)),
          ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PreviewDayCard extends StatelessWidget {
  const _PreviewDayCard({
    required this.day,
    required this.stats,
    required this.resolve,
  });

  final WorkoutDay day;
  final PlanDayStats? stats;
  final Exercise Function(String id) resolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(day.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (stats != null)
                  Text('~${stats!.estimatedMinutes} min · ${stats!.totalSets} serii',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            if (day.items.isEmpty)
              Text('Brak ćwiczeń — dodasz je w szczegółach dnia.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant))
            else
              for (final item in day.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(resolve(item.exerciseId).name,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.durationSec > 0
                            ? '${item.sets}× ${item.durationSec} s'
                            : '${item.sets}× ${item.reps}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Wielokrotny wybór ćwiczeń z bazy (preferowane / wykluczone).
class _ExerciseMultiPickerSheet extends StatefulWidget {
  const _ExerciseMultiPickerSheet({
    required this.title,
    required this.library,
    required this.selected,
  });

  final String title;
  final List<Exercise> library;
  final Set<String> selected;

  @override
  State<_ExerciseMultiPickerSheet> createState() =>
      _ExerciseMultiPickerSheetState();
}

class _ExerciseMultiPickerSheetState extends State<_ExerciseMultiPickerSheet> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';
  MuscleGroup? _group;

  List<Exercise> get _filtered {
    final query = normalizeSearchText(_query);
    return widget.library.where((exercise) {
      if (_group != null && primaryMuscleGroupOf(exercise) != _group) {
        return false;
      }
      if (query.isEmpty) return true;
      return normalizeSearchText(exercise.name).contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    Text('${_selected.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Szukaj ćwiczenia…',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Wszystkie'),
                        selected: _group == null,
                        onSelected: (_) => setState(() => _group = null),
                      ),
                    ),
                    for (final group in kLimitedMuscleGroups)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(group.label),
                          selected: _group == group,
                          onSelected: (_) => setState(() => _group = group),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final exercise = items[index];
                    return CheckboxListTile(
                      dense: true,
                      value: _selected.contains(exercise.id),
                      title: Text(exercise.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(exercise.equipment,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (value) => setState(() {
                        if (value ?? false) {
                          _selected.add(exercise.id);
                        } else {
                          _selected.remove(exercise.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Anuluj'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _selected.toList()),
                        child: const Text('Zatwierdź'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
