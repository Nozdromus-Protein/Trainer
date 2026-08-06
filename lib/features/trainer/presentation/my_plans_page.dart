// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Lista własnych zestawów pogrupowana po sposobie utworzenia
// (ręcznie / z pomocą AI / wygenerowane przez AI / programy / ulubione).
part of '../../../main.dart';

/// Kategoria listy zestawów.
enum PlanCategory {
  all('all', 'Wszystkie'),
  manual('manual', 'Utworzone ręcznie'),
  manualWithAi('manualWithAi', 'Utworzone z pomocą AI'),
  aiGenerated('aiGenerated', 'Wygenerowane przez AI'),
  programs('programs', 'Programy 30-dniowe'),
  favorites('favorites', 'Ulubione'),
  recent('recent', 'Ostatnio używane'),
  archived('archived', 'Archiwum');

  const PlanCategory(this.key, this.label);

  final String key;
  final String label;

  bool matches(WorkoutPlan plan) {
    final origin = plan.origin;
    switch (this) {
      case PlanCategory.all:
        return !origin.isArchived;
      case PlanCategory.manual:
        return !origin.isArchived &&
            origin.creationMode == PlanCreationMode.manual;
      case PlanCategory.manualWithAi:
        return !origin.isArchived &&
            origin.creationMode == PlanCreationMode.manualWithAi;
      case PlanCategory.aiGenerated:
        return !origin.isArchived &&
            origin.creationMode == PlanCreationMode.fullyAiGenerated;
      case PlanCategory.programs:
        return !origin.isArchived &&
            origin.creationMode == PlanCreationMode.systemProgram;
      case PlanCategory.favorites:
        return !origin.isArchived && origin.isFavorite;
      case PlanCategory.recent:
        return !origin.isArchived && origin.lastUsedAt != null;
      case PlanCategory.archived:
        return origin.isArchived;
    }
  }
}

/// Sposób sortowania listy zestawów.
enum PlanSort {
  recent('Ostatnio używane'),
  created('Data utworzenia'),
  name('Nazwa'),
  size('Liczba ćwiczeń');

  const PlanSort(this.label);

  final String label;
}

/// Karta wejściowa „Utwórz własny zestaw" + skrót do listy moich zestawów.
class CreateOwnPlanCard extends StatelessWidget {
  const CreateOwnPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Liczymy WŁASNE zestawy (bez programów katalogowych i archiwum) —
    // to one żyją na tej liście.
    final ownCount = store.plans
        .where((plan) =>
            !plan.origin.isArchived && !plan.origin.isSystemProgram)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Moje zestawy',
          actionLabel: ownCount > 0 ? 'Wszystkie ($ownCount)' : null,
          onAction: ownCount > 0 ? () => openMyPlansPage(context) : null,
        ),
        Gap(4),
        Text(
          'Ułóż zestaw sam, poproś AI o pomoc w wybranych miejscach albo pozwól '
          'jej przygotować całość — decyzja zawsze należy do Ciebie.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Gap(12),
        // Kafelki własnych zestawów — ten sam język wizualny co programy
        // 30-dniowe, ale z jawnym oznaczeniem, że to zestawy użytkownika.
        if (ownCount > 0) ...[
          OwnPlanTilesSection(layout: normalizeTileLayout(store.settings.tileLayout)),
          Gap(12),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('create_own_plan_card'),
            borderRadius: BorderRadius.circular(uiCornerRadius(context, 20)),
            onTap: () => showPlanCreationModeSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.20),
                    scheme.primary.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(uiCornerRadius(context, 20)),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: scheme.primary, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Utwórz własny zestaw',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.primary)),
                        const SizedBox(height: 2),
                        Text('Ręcznie · z pomocą AI · w całości przez AI',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sekcja kafelków WŁASNYCH zestawów na ekranie „Trening".
///
/// Układ (lista / siatka / kompakt) idzie za tym samym ustawieniem
/// personalizacji co programy 30-dniowe, więc ekran zostaje spójny.
class OwnPlanTilesSection extends StatelessWidget {
  const OwnPlanTilesSection({super.key, required this.layout, this.limit = 6});

  final String layout;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final plans = store.plans
        .where((plan) =>
            !plan.origin.isArchived && !plan.origin.isSystemProgram)
        .toList()
      ..sort((a, b) {
        // Ulubione na górze, potem ostatnio używane, potem reszta.
        final favorite = (b.origin.isFavorite ? 1 : 0)
            .compareTo(a.origin.isFavorite ? 1 : 0);
        if (favorite != 0) return favorite;
        final left = a.origin.lastUsedAt ?? a.origin.createdAt;
        final right = b.origin.lastUsedAt ?? b.origin.createdAt;
        if (left == null && right == null) return a.name.compareTo(b.name);
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    if (plans.isEmpty) return const SizedBox.shrink();
    final visible = plans.take(limit).toList();

    if (layout == 'grid') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 340 ? 2 : 1;
          final width = columns == 2
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final plan in visible)
                SizedBox(width: width, child: OwnPlanTile(plan: plan)),
            ],
          );
        },
      );
    }
    final compact = layout == 'compact';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in visible)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 8 : 12),
            child: OwnPlanTile(plan: plan, compact: compact),
          ),
      ],
    );
  }
}

/// Kafelek własnego zestawu: gradient w tonacji trybu utworzenia, partie,
/// objętość i szybkie akcje (start, analiza AI, podmiana w planie dnia).
class OwnPlanTile extends StatelessWidget {
  const OwnPlanTile({super.key, required this.plan, this.compact = false});

  final WorkoutPlan plan;
  final bool compact;

  /// Kolor wiodący kafelka zależy od tego, jak zestaw powstał — dzięki temu
  /// widać to jednym rzutem oka, bez czytania chipów.
  Color _accent(ColorScheme scheme) => switch (plan.origin.creationMode) {
        PlanCreationMode.fullyAiGenerated => scheme.primary,
        PlanCreationMode.manualWithAi => scheme.tertiary,
        _ => scheme.secondary,
      };

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accent(scheme);

    final exerciseCount =
        plan.days.fold<int>(0, (sum, day) => sum + day.items.length);
    final setCount = plan.days.fold<int>(
        0, (sum, day) => sum + day.items.fold<int>(0, (s, i) => s + i.sets));

    // Partie, które zestaw realnie trenuje (partia GŁÓWNA ćwiczeń).
    final muscles = <MuscleGroup>{};
    for (final day in plan.days) {
      for (final item in day.items) {
        muscles.add(primaryMuscleGroupOf(
            ExerciseRepo.byId(item.exerciseId, store.customExercises)));
      }
    }
    final musclesLabel = muscles.isEmpty
        ? 'Brak ćwiczeń'
        : muscles.take(3).map((g) => g.label).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('own_plan_tile_${plan.id}'),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 20)),
        onTap: () => openWorkoutProgram(context, plan.id),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.18),
                accent.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(uiCornerRadius(context, 20)),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 34 : 40,
                      height: compact ? 34 : 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        plan.origin.aiGenerated
                            ? Icons.smart_toy_rounded
                            : plan.origin.aiAssisted
                                ? Icons.auto_fix_high_rounded
                                : Icons.edit_note_rounded,
                        size: compact ? 18 : 21,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: (compact
                                    ? theme.textTheme.bodyMedium
                                    : theme.textTheme.titleSmall)
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            musclesLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (plan.origin.isFavorite)
                      Icon(Icons.star_rounded, size: 16, color: kDeloadColor),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PlanOriginChip(mode: plan.origin.creationMode),
                      _SmallChip(
                          label: '${plan.days.length} dni',
                          icon: Icons.calendar_today_rounded),
                      _SmallChip(
                          label: '$exerciseCount ćwiczeń',
                          icon: Icons.fitness_center_rounded),
                      if (setCount > 0)
                        _SmallChip(
                            label: '$setCount serii',
                            icon: Icons.repeat_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => openWorkoutProgram(context, plan.id),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('Otwórz'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: Key('own_plan_analyze_${plan.id}'),
                        tooltip: 'Przeanalizuj przez AI',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                        onPressed: () => openPlanAiAnalysis(context, plan.id),
                      ),
                      IconButton(
                        key: Key('own_plan_fav_${plan.id}'),
                        tooltip: plan.origin.isFavorite
                            ? 'Usuń z ulubionych'
                            : 'Dodaj do ulubionych',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          plan.origin.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 19,
                          color: plan.origin.isFavorite ? kDeloadColor : null,
                        ),
                        onPressed: () => store.setPlanFavorite(
                            plan.id, !plan.origin.isFavorite),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Otwiera listę własnych zestawów.
Future<void> openMyPlansPage(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const MyPlansPage()),
  );
}

class MyPlansPage extends StatefulWidget {
  const MyPlansPage({super.key});

  @override
  State<MyPlansPage> createState() => _MyPlansPageState();
}

class _MyPlansPageState extends State<MyPlansPage> {
  PlanCategory _category = PlanCategory.all;
  PlanSort _sort = PlanSort.recent;
  String _query = '';

  List<WorkoutPlan> _visiblePlans(AppStore store) {
    final query = normalizeSearchText(_query);
    final filtered = store.plans.where((plan) {
      if (!_category.matches(plan)) return false;
      if (query.isEmpty) return true;
      return normalizeSearchText(plan.name).contains(query) ||
          normalizeSearchText(plan.note).contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case PlanSort.recent:
          final left = a.origin.lastUsedAt ?? a.origin.updatedAt;
          final right = b.origin.lastUsedAt ?? b.origin.updatedAt;
          if (left == null && right == null) return a.name.compareTo(b.name);
          if (left == null) return 1;
          if (right == null) return -1;
          return right.compareTo(left);
        case PlanSort.created:
          final left = a.origin.createdAt;
          final right = b.origin.createdAt;
          if (left == null && right == null) return a.name.compareTo(b.name);
          if (left == null) return 1;
          if (right == null) return -1;
          return right.compareTo(left);
        case PlanSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case PlanSort.size:
          int count(WorkoutPlan plan) => plan.days
              .fold<int>(0, (sum, day) => sum + day.items.length);
          return count(b).compareTo(count(a));
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final plans = _visiblePlans(store);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('Moje zestawy'),
        actions: [
          PopupMenuButton<PlanSort>(
            key: const Key('my_plans_sort'),
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sortowanie',
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final sort in PlanSort.values)
                PopupMenuItem(
                  value: sort,
                  child: Row(
                    children: [
                      if (_sort == sort)
                        const Icon(Icons.check_rounded, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(sort.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('my_plans_create'),
        onPressed: () => showPlanCreationModeSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Utwórz własny zestaw'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                key: const Key('my_plans_search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Szukaj zestawu…',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final category in PlanCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('plan_category_${category.key}'),
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (_) =>
                            setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: plans.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 44,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text(
                              _query.isNotEmpty
                                  ? 'Brak zestawów pasujących do wyszukiwania.'
                                  : 'W kategorii „${_category.label}" nie ma '
                                      'jeszcze żadnego zestawu.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: plans.length,
                      itemBuilder: (context, index) =>
                          MyPlanTile(plan: plans[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kafelek zestawu z oznaczeniem sposobu utworzenia i menu akcji.
class MyPlanTile extends StatelessWidget {
  const MyPlanTile({super.key, required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final origin = plan.origin;
    final exerciseCount =
        plan.days.fold<int>(0, (sum, day) => sum + day.items.length);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(uiCornerRadius(context, 18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(uiCornerRadius(context, 18)),
          onTap: () => openWorkoutProgram(context, plan.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: Key('plan_fav_${plan.id}'),
                      visualDensity: VisualDensity.compact,
                      tooltip: origin.isFavorite
                          ? 'Usuń z ulubionych'
                          : 'Dodaj do ulubionych',
                      icon: Icon(
                        origin.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: origin.isFavorite ? kDeloadColor : null,
                        size: 20,
                      ),
                      onPressed: () =>
                          store.setPlanFavorite(plan.id, !origin.isFavorite),
                    ),
                    _PlanActionsMenu(plan: plan),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    PlanOriginChip(mode: origin.creationMode),
                    if (plan.isActive)
                      _SmallChip(
                          label: 'Aktywny',
                          color: scheme.primary,
                          icon: Icons.play_arrow_rounded),
                    if (origin.isArchived)
                      const _SmallChip(
                          label: 'Archiwum', icon: Icons.archive_rounded),
                    _SmallChip(
                        label: '${plan.days.length} dni',
                        icon: Icons.calendar_today_rounded),
                    _SmallChip(
                        label: '$exerciseCount ćwiczeń',
                        icon: Icons.fitness_center_rounded),
                    if (origin.isPersonalizedVariant)
                      _SmallChip(
                          label: 'Wariant: ${origin.basePlanName}',
                          icon: Icons.call_split_rounded),
                    if (origin.version > 1)
                      _SmallChip(
                          label: 'Wersja ${origin.version}',
                          icon: Icons.history_rounded),
                  ],
                ),
                if (origin.aiAssistanceScopes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'AI pomogło w: '
                    '${origin.aiAssistanceScopes.map((s) => s.label.toLowerCase()).take(3).join(', ')}'
                    '${origin.aiAssistanceScopes.length > 3 ? '…' : ''}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip oznaczający sposób utworzenia zestawu.
class PlanOriginChip extends StatelessWidget {
  const PlanOriginChip({super.key, required this.mode});

  final PlanCreationMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (mode) {
      PlanCreationMode.manual => (Icons.edit_note_rounded, scheme.onSurfaceVariant),
      PlanCreationMode.manualWithAi =>
        (Icons.auto_fix_high_rounded, scheme.tertiary),
      PlanCreationMode.fullyAiGenerated =>
        (Icons.smart_toy_rounded, scheme.primary),
      PlanCreationMode.systemProgram =>
        (Icons.calendar_month_rounded, scheme.secondary),
      PlanCreationMode.imported => (Icons.download_rounded, scheme.onSurfaceVariant),
      PlanCreationMode.legacy => (Icons.history_rounded, scheme.onSurfaceVariant),
    };
    return _SmallChip(label: mode.badgeLabel, icon: icon, color: color);
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: tone, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlanAction { analyze, duplicate, edit, archive, unarchive, activate, delete, versions }

class _PlanActionsMenu extends StatelessWidget {
  const _PlanActionsMenu({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.read(context);
    return PopupMenuButton<_PlanAction>(
      key: Key('plan_menu_${plan.id}'),
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (action) async {
        switch (action) {
          case _PlanAction.analyze:
            await openPlanAiAnalysis(context, plan.id);
          case _PlanAction.duplicate:
            final copy = await store.duplicateWorkoutPlan(plan.id);
            if (!context.mounted || copy == null) return;
            showError(context, 'Utworzono kopię „${copy.name}".');
          case _PlanAction.edit:
            if (!context.mounted) return;
            openWorkoutProgram(context, plan.id);
          case _PlanAction.archive:
            await store.setPlanArchived(plan.id, true);
            if (!context.mounted) return;
            showError(context, 'Zestaw przeniesiony do archiwum.');
          case _PlanAction.unarchive:
            await store.setPlanArchived(plan.id, false);
          case _PlanAction.activate:
            await store.setActiveWorkoutPlan(plan.id);
          case _PlanAction.versions:
            if (!context.mounted) return;
            await showPlanVersionsSheet(context, plan.id);
          case _PlanAction.delete:
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Usunąć zestaw?'),
                content: Text(
                  'Zestaw „${plan.name}" zostanie usunięty. Historia '
                  'wykonanych treningów i Twoje wyniki zostaną zachowane.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Anuluj'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Usuń'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            await store.deleteWorkoutPlan(plan.id);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _PlanAction.analyze,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.auto_awesome_rounded, size: 18),
            title: Text('Przeanalizuj zestaw przez AI'),
          ),
        ),
        const PopupMenuItem(
          value: _PlanAction.edit,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_rounded, size: 18),
            title: Text('Edytuj'),
          ),
        ),
        const PopupMenuItem(
          value: _PlanAction.duplicate,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_rounded, size: 18),
            title: Text('Duplikuj'),
          ),
        ),
        if (!plan.isActive && !plan.origin.isArchived)
          const PopupMenuItem(
            value: _PlanAction.activate,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.play_circle_outline_rounded, size: 18),
              title: Text('Ustaw jako aktywny'),
            ),
          ),
        if (plan.versions.isNotEmpty)
          const PopupMenuItem(
            value: _PlanAction.versions,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, size: 18),
              title: Text('Historia wersji'),
            ),
          ),
        if (plan.origin.isArchived)
          const PopupMenuItem(
            value: _PlanAction.unarchive,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.unarchive_rounded, size: 18),
              title: Text('Przywróć z archiwum'),
            ),
          )
        else
          const PopupMenuItem(
            value: _PlanAction.archive,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.archive_rounded, size: 18),
              title: Text('Archiwizuj'),
            ),
          ),
        const PopupMenuItem(
          value: _PlanAction.delete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded, size: 18),
            title: Text('Usuń'),
          ),
        ),
      ],
    );
  }
}

/// Historia wersji zestawu z możliwością przywrócenia wcześniejszej.
Future<void> showPlanVersionsSheet(BuildContext context, String planId) async {
  final store = AppScope.read(context);
  final matches = store.plans.where((plan) => plan.id == planId);
  if (matches.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // Arkusz żyje w overlayu Nawigatora — sklep podajemy jawnie, zamiast
    // liczyć na [AppScope] gdzieś wyżej w drzewie.
    builder: (sheetContext) => AppScope(
      store: store,
      child: _PlanVersionsSheet(planId: planId),
    ),
  );
}

class _PlanVersionsSheet extends StatelessWidget {
  const _PlanVersionsSheet({required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final matches = store.plans.where((plan) => plan.id == planId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final plan = matches.first;
    final theme = Theme.of(context);
    final versions = plan.versions.reversed.toList();

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
            Text('Historia wersji',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              'Bieżąca wersja: ${plan.origin.version}. Przywrócenie starszej '
              'wersji zmienia tylko treść dni — postęp i historia treningów '
              'zostają nietknięte.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (versions.isEmpty)
              Text('Ten zestaw nie ma jeszcze zapisanych wersji.',
                  style: theme.textTheme.bodyMedium)
            else
              for (final snapshot in versions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${snapshot.version}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text(snapshot.label,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${shortDate(snapshot.createdAt)}'
                      '${snapshot.reason.isEmpty ? '' : ' · ${snapshot.reason}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final ok = await store.restorePlanVersion(
                            planId, snapshot.version);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        showError(
                          context,
                          ok
                              ? 'Przywrócono wersję ${snapshot.version}.'
                              : 'Nie udało się przywrócić wersji.',
                        );
                      },
                      child: const Text('Przywróć'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
