// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`). Ten sam zakres
// biblioteki — prywatne pola i importy z main.dart są dostępne bez zmian.
part of '../../../main.dart';

// ============================================================================
// KREATOR PIERWSZEJ KONFIGURACJI PROFILU
// ----------------------------------------------------------------------------
// Pokazuje się PO PIERWSZYM zalogowaniu / założeniu konta oraz wtedy, gdy
// profil nie został ukończony — NIE przy każdym uruchomieniu aplikacji. Istnieje
// też jawne wejście „Uzupełnij profil" (Więcej → Profil treningowy).
//
// Zbiera komplet danych, na których stoi dopasowanie: dane podstawowe, cel,
// doświadczenie, sprzęt, ograniczenia, preferencje i integracje. Każdy etap
// zapisuje się od razu ([AppStore.updateSettings]), więc przerwanie kreatora
// nie kasuje tego, co już wpisano — „Dokończę później" wraca dokładnie tu,
// gdzie skończyliśmy ([AppSettings.onboardingStep]).
// ============================================================================

/// Gotowe ikony awatara dla użytkowników, którzy nie chcą zdjęcia.
const Map<String, IconData> kTrainerAvatarIcons = <String, IconData>{
  'dumbbell': Icons.fitness_center_rounded,
  'run': Icons.directions_run_rounded,
  'bolt': Icons.bolt_rounded,
  'heart': Icons.favorite_rounded,
  'trophy': Icons.emoji_events_rounded,
  'shield': Icons.shield_moon_rounded,
  'spark': Icons.auto_awesome_rounded,
  'mountain': Icons.terrain_rounded,
};

/// Podpowiedzi ulubionych aktywności w kreatorze i profilu.
const List<String> kFavoriteActivitySuggestions = <String>[
  'Siłownia',
  'Bieganie',
  'Rower',
  'Pływanie',
  'Kalistenika',
  'Marsz',
  'Rozciąganie',
  'Sporty walki',
  'Wspinaczka',
  'Piłka nożna',
];

class ProfileSetupWizardPage extends StatefulWidget {
  const ProfileSetupWizardPage({super.key});

  @override
  State<ProfileSetupWizardPage> createState() => _ProfileSetupWizardPageState();
}

class _ProfileSetupWizardPageState extends State<ProfileSetupWizardPage> {
  /// Etapy kreatora — kolejność ma znaczenie (każdy korzysta z poprzednich).
  static const List<String> _stepTitles = <String>[
    'Dane podstawowe',
    'Cel',
    'Doświadczenie',
    'Sprzęt i miejsce',
    'Ograniczenia',
    'Preferencje',
    'Integracje',
    'Podsumowanie',
  ];

  late int _step;
  bool _saving = false;

  // Etap 1
  late final TextEditingController _name;
  late final TextEditingController _about;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _age;
  String _sex = '';

  // Etap 2
  String _silhouette = '';
  late final TextEditingController _targetWeight;
  String _mode = 'Rekompozycja';

  // Etap 3
  String _level = 'Średniozaawansowany';
  int _experienceMonths = 0;
  Set<int> _weekdays = <int>{};

  // Etap 4
  String _equipmentMode = '';
  Set<String> _ownedEquipment = <String>{};

  // Etap 5
  Set<String> _limitations = <String>{};
  late final TextEditingController _limitationNote;

  // Etap 6
  Set<String> _favorites = <String>{};
  String _intensity = 'moderate';
  int _restSeconds = 90;
  int _workoutMinutes = 60;
  String _guidance = 'full';

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    _step = settings.onboardingStep.clamp(0, _stepTitles.length - 1);
    _name = TextEditingController(text: settings.displayName);
    _about = TextEditingController(text: settings.aboutMe);
    _height = TextEditingController(
        text:
            settings.heightCm > 0 ? settings.heightCm.round().toString() : '');
    _weight = TextEditingController(
        text: settings.bodyWeightKg > 0
            ? settings.bodyWeightKg.toStringAsFixed(1)
            : '');
    _age =
        TextEditingController(text: settings.age > 0 ? '${settings.age}' : '');
    _sex = settings.sex;
    _silhouette = settings.targetSilhouette;
    _targetWeight = TextEditingController(
        text: settings.targetWeightKg > 0
            ? settings.targetWeightKg.toStringAsFixed(1)
            : '');
    _mode = normalizeTrainingMode(settings.trainingMode);
    _level = normalizeTrainingLevel(settings.level);
    _experienceMonths = settings.experienceMonths;
    _weekdays = {...settings.trainingWeekdays};
    _equipmentMode = settings.equipmentModeKey;
    _ownedEquipment = {...settings.ownedEquipmentKeys};
    _limitations = {...settings.limitationFlagKeys};
    _limitationNote = TextEditingController(text: settings.limitations);
    _favorites = {...settings.favoriteActivities};
    _intensity = WorkoutIntensityLevel.fromKey(settings.preferredIntensity).key;
    _restSeconds =
        settings.preferredRestSeconds > 0 ? settings.preferredRestSeconds : 90;
    _workoutMinutes = settings.preferredWorkoutMinutes > 0
        ? settings.preferredWorkoutMinutes
        : 60;
    _guidance = settings.guidanceMode;
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _height.dispose();
    _weight.dispose();
    _age.dispose();
    _targetWeight.dispose();
    _limitationNote.dispose();
    super.dispose();
  }

  double _parseDouble(TextEditingController c, double fallback) {
    final parsed = double.tryParse(c.text.replaceAll(',', '.').trim());
    return parsed == null || parsed <= 0 ? fallback : parsed;
  }

  /// Zapisuje WSZYSTKO, co dotąd wpisano. Wołane po każdym etapie, więc
  /// przerwanie kreatora nie kosztuje ani jednego pola.
  Future<void> _persist({bool? completed, int? step}) async {
    final store = AppScope.read(context);
    final current = store.settings;
    await store.updateSettings(current.copyWith(
      displayName: _name.text.trim(),
      aboutMe: _about.text.trim(),
      heightCm: _parseDouble(_height, current.heightCm),
      bodyWeightKg: _parseDouble(_weight, current.bodyWeightKg),
      age: int.tryParse(_age.text.trim()) ?? current.age,
      sex: _sex,
      targetSilhouette: _silhouette,
      targetWeightKg: _parseDouble(_targetWeight, 0).clamp(0, 400),
      trainingMode: _mode,
      goal: _mode,
      level: _level,
      experienceMonths: _experienceMonths,
      trainingWeekdays: _weekdays.isEmpty
          ? current.trainingWeekdays
          : (_weekdays.toList()..sort()),
      equipmentModeKey: _equipmentMode,
      ownedEquipmentKeys: _ownedEquipment.toList(),
      limitationFlagKeys: _limitations.toList(),
      limitations: _limitationNote.text.trim(),
      favoriteActivities: _favorites.toList(),
      preferredIntensity: _intensity,
      preferredRestSeconds: _restSeconds,
      preferredWorkoutMinutes: _workoutMinutes,
      guidanceMode: _guidance,
      trainingStartDate: current.trainingStartDate ?? DateTime.now(),
      onboardingCompleted: completed ?? current.onboardingCompleted,
      onboardingStep: step ?? _step,
    ));
  }

  Future<void> _next() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final isLast = _step >= _stepTitles.length - 1;
      await _persist(
        completed: isLast ? true : null,
        step: isLast ? 0 : _step + 1,
      );
      if (!mounted) return;
      if (isLast) return; // brama sama przełączy na HomeShell
      setState(() => _step++);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _back() async {
    if (_step == 0 || _saving) return;
    setState(() => _step--);
    await _persist(step: _step);
  }

  /// „Dokończę później" — dane zostają, kreator znika, wejście wraca w profilu.
  Future<void> _finishLater() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _persist(completed: true, step: _step);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = (_step + 1) / _stepTitles.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitles[_step]),
        leading: _step == 0
            ? null
            : IconButton(
                key: const Key('wizard_back'),
                tooltip: 'Wstecz',
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            key: const Key('wizard_finish_later'),
            onPressed: _saving ? null : _finishLater,
            child: const Text('Później'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    key: const Key('wizard_progress'),
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 3),
                Text('Etap ${_step + 1} z ${_stepTitles.length}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: uiInsets(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
          children: [_buildStep(theme)],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('wizard_next'),
            onPressed: _saving ? null : _next,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_step >= _stepTitles.length - 1
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded),
            label: Text(_step >= _stepTitles.length - 1
                ? 'Zapisz profil i zacznij'
                : 'Dalej'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ),
    );
  }

  Widget _sectionHint(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.35)),
      );

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w900)),
      );

  Widget _buildStep(ThemeData theme) {
    switch (_step) {
      case 0:
        return _stepBasics(theme);
      case 1:
        return _stepGoal(theme);
      case 2:
        return _stepExperience(theme);
      case 3:
        return _stepEquipment(theme);
      case 4:
        return _stepLimitations(theme);
      case 5:
        return _stepPreferences(theme);
      case 6:
        return _stepIntegrations(theme);
      default:
        return _stepSummary(theme);
    }
  }

  Widget _stepBasics(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Te dane napędzają regenerację, kalorie i dobór ciężarów. Możesz je '
            'później zmienić w profilu treningowym.'),
        TextField(
          key: const Key('wizard_name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Imię lub pseudonim', hintText: 'np. Dawid'),
        ),
        _label(theme, 'Płeć (używana w obliczeniach)'),
        Wrap(
          spacing: 8,
          children: [
            for (final option in const [
              ('', 'Nie podaję'),
              ('male', 'Mężczyzna'),
              ('female', 'Kobieta')
            ])
              ChoiceChip(
                label: Text(option.$2),
                selected: _sex == option.$1,
                onSelected: (_) => setState(() => _sex = option.$1),
              ),
          ],
        ),
        _label(theme, 'Wiek, wzrost i waga'),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('wizard_age'),
                controller: _age,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Wiek', suffixText: 'lat'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Wzrost', suffixText: 'cm'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Waga', suffixText: 'kg'),
              ),
            ),
          ],
        ),
        _label(theme, 'O mnie (opcjonalnie)'),
        TextField(
          controller: _about,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText:
                  'Krótko o sobie — cel, historia treningowa, cokolwiek.'),
        ),
      ],
    );
  }

  Widget _stepGoal(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Sylwetka to miejsce docelowe, strategia to droga. Kalorie i objętość '
            'liczymy ze strategii, a nie z samego wyglądu.'),
        _label(theme, 'Cel sylwetkowy'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final goal in SilhouetteGoal.values)
              ChoiceChip(
                label: Text(goal.label),
                selected: _silhouette == goal.id,
                onSelected: (_) => setState(() => _silhouette = goal.id),
              ),
          ],
        ),
        _label(theme, 'Strategia treningowa'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in const [
              'Masa',
              'Redukcja',
              'Rekompozycja',
              'Kondycja'
            ])
              ChoiceChip(
                label: Text(mode),
                selected: _mode == mode,
                onSelected: (_) => setState(() => _mode = mode),
              ),
          ],
        ),
        _label(theme, 'Cel wagowy'),
        TextField(
          key: const Key('wizard_target_weight'),
          controller: _targetWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Docelowa masa ciała',
              suffixText: 'kg',
              hintText: 'zostaw puste, jeśli nie masz celu'),
        ),
      ],
    );
  }

  Widget _stepExperience(ThemeData theme) {
    const weekdayNames = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Poziom decyduje o doborze ćwiczeń i limitach objętości, a dni '
            'treningowe — o rozkładzie tygodnia.'),
        _label(theme, 'Poziom zaawansowania'),
        Wrap(
          spacing: 8,
          children: [
            for (final level in const [
              'Początkujący',
              'Średniozaawansowany',
              'Zaawansowany'
            ])
              ChoiceChip(
                label: Text(level),
                selected: _level == level,
                onSelected: (_) => setState(() => _level = level),
              ),
          ],
        ),
        _label(theme, 'Staż treningowy: ${_experienceLabel()}'),
        Slider(
          value: _experienceMonths.toDouble().clamp(0, 120),
          min: 0,
          max: 120,
          divisions: 40,
          label: _experienceLabel(),
          onChanged: (v) => setState(() => _experienceMonths = v.round()),
        ),
        _label(theme, 'Dni treningowe w tygodniu'),
        Wrap(
          spacing: 6,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(weekdayNames[day - 1]),
                selected: _weekdays.contains(day),
                onSelected: (on) => setState(() {
                  if (on) {
                    _weekdays.add(day);
                  } else {
                    _weekdays.remove(day);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  String _experienceLabel() {
    if (_experienceMonths <= 0) return 'zaczynam';
    if (_experienceMonths < 12) return '$_experienceMonths mies.';
    final years = _experienceMonths ~/ 12;
    final months = _experienceMonths % 12;
    return months == 0 ? '$years lat' : '$years lat $months mies.';
  }

  Widget _stepEquipment(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Generator NIE zaproponuje ćwiczenia na sprzęcie, którego nie masz. '
            'Im dokładniej tu zaznaczysz, tym mniej podmian w zestawach.'),
        _label(theme, 'Gdzie trenujesz'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in EquipmentMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: _equipmentMode == mode.key,
                onSelected: (_) => setState(() => _equipmentMode = mode.key),
              ),
          ],
        ),
        _label(theme, 'Posiadany sprzęt'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in EquipmentType.values)
              FilterChip(
                label: Text(type.label),
                selected: _ownedEquipment.contains(type.key),
                onSelected: (on) => setState(() {
                  if (on) {
                    _ownedEquipment.add(type.key);
                  } else {
                    _ownedEquipment.remove(type.key);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stepLimitations(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Zaznaczone ograniczenia wykluczają kolidujące ćwiczenia z zestawów '
            'i z podmian. Możesz je zmienić w każdej chwili.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final limit in TrainingLimitation.values)
              FilterChip(
                label: Text(limit.label),
                selected: _limitations.contains(limit.key),
                onSelected: (on) => setState(() {
                  if (on) {
                    _limitations.add(limit.key);
                  } else {
                    _limitations.remove(limit.key);
                  }
                }),
              ),
          ],
        ),
        _label(theme, 'Własna notatka'),
        TextField(
          controller: _limitationNote,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText:
                  'np. lewy bark boli przy wyciskaniu nad głowę — omijać'),
        ),
      ],
    );
  }

  Widget _stepPreferences(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Preferencje sterują tym, JAK Trainer prowadzi trening — nie tym, '
            'czy prowadzi.'),
        _label(theme, 'Ulubione rodzaje aktywności'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final activity in kFavoriteActivitySuggestions)
              FilterChip(
                label: Text(activity),
                selected: _favorites.contains(activity),
                onSelected: (on) => setState(() {
                  if (on) {
                    _favorites.add(activity);
                  } else {
                    _favorites.remove(activity);
                  }
                }),
              ),
          ],
        ),
        _label(theme, 'Preferowana intensywność'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final level in WorkoutIntensityLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: _intensity == level.key,
                onSelected: (_) => setState(() => _intensity = level.key),
              ),
          ],
        ),
        _label(theme, 'Przerwa między seriami: $_restSeconds s'),
        Slider(
          value: _restSeconds.toDouble().clamp(30, 240),
          min: 30,
          max: 240,
          divisions: 14,
          label: '$_restSeconds s',
          onChanged: (v) => setState(() => _restSeconds = v.round()),
        ),
        _label(theme, 'Dostępny czas na trening: $_workoutMinutes min'),
        Slider(
          value: _workoutMinutes.toDouble().clamp(15, 150),
          min: 15,
          max: 150,
          divisions: 9,
          label: '$_workoutMinutes min',
          onChanged: (v) => setState(() => _workoutMinutes = v.round()),
        ),
        _label(theme, 'Tryb prowadzenia przez Trainera'),
        // Świadomie ListTile z ikoną zamiast RadioListTile: `groupValue`
        // i `onChanged` są w tej wersji Fluttera przestarzałe, a RadioGroup
        // nie wnosi tu niczego poza dodatkowym opakowaniem.
        for (final mode in GuidanceMode.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_guidance == mode.key
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded),
            onTap: () => setState(() => _guidance = mode.key),
            title: Text(mode.label),
            subtitle: Text(mode.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _stepIntegrations(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Integracje możesz włączyć teraz albo później — profil działa bez '
            'nich, tylko z mniejszą liczbą danych o aktywności.'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Health Connect / Samsung Health'),
            subtitle: const Text(
                'Kroki, dystans, aktywne kalorie, sen i tętno z zegarka'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HealthConnectSettingsPage())),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_alt_rounded),
            title: const Text('Licznik Kalorii — most danych'),
            subtitle:
                const Text('Kalorie treningu, cele dnia i wspólny profil'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openTrainerSubPage(context, const IntegrationsPage(),
                title: 'Integracje'),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Konto i kopia w chmurze'),
            subtitle: const Text(
                'Treningi, plany i postępy przeżyją reinstalację telefonu'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountSyncPage())),
          ),
        ),
      ],
    );
  }

  Widget _stepSummary(ThemeData theme) {
    final scheme = theme.colorScheme;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    final goal = SilhouetteGoal.fromId(_silhouette);
    const weekdayNames = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
    final days =
        (_weekdays.toList()..sort()).map((d) => weekdayNames[d - 1]).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHint(
            theme,
            'Sprawdź, czy wszystko się zgadza. Po zatwierdzeniu Trainer ułoży '
            'rozkład tygodnia i pierwsze zestawy pod te dane.'),
        Card(
          key: const Key('wizard_summary'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('Imię', _name.text.trim()),
                row('Wiek / wzrost / waga',
                    '${_age.text.trim()} lat · ${_height.text.trim()} cm · ${_weight.text.trim()} kg'),
                row('Cel sylwetkowy', goal?.label ?? ''),
                row('Strategia', _mode),
                row(
                    'Cel wagowy',
                    _targetWeight.text.trim().isEmpty
                        ? ''
                        : '${_targetWeight.text.trim()} kg'),
                row('Poziom', _level),
                row('Staż', _experienceLabel()),
                row('Dni treningowe', days),
                row('Sprzęt',
                    '${EquipmentMode.fromKey(_equipmentMode)?.label ?? 'nie wybrano'} · ${_ownedEquipment.length} pozycji'),
                row(
                    'Ograniczenia',
                    _limitations.isEmpty
                        ? 'brak'
                        : '${_limitations.length} zaznaczone'),
                row('Intensywność',
                    WorkoutIntensityLevel.fromKey(_intensity).label),
                row('Prowadzenie', GuidanceMode.fromKey(_guidance).label),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
