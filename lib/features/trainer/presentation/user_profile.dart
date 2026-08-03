// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`). Ten sam zakres
// biblioteki — prywatne pola i importy z main.dart są dostępne bez zmian.
//
// Zawiera PROFIL UŻYTKOWNIKA: kartę profilu (awatar, pseudonim, „O mnie",
// staż, seria dni, osiągnięcia, prywatność), sam awatar oraz arkusze jego
// wyboru i edycji danych profilu.
part of '../../../main.dart';

/// Karta profilu użytkownika: awatar, pseudonim, „O mnie", data startu,
/// aktualny cel, ulubione aktywności, seria dni, osiągnięcia i statystyki.
///
/// Profil jest PRYWATNY — nie ma tu żadnej funkcji społecznościowej ani
/// publikowania. Przełącznik prywatności decyduje wyłącznie o tym, czy
/// statystyki trafiają do kontekstu przekazywanego asystentowi AI.
class UserProfileCard extends StatelessWidget {
  const UserProfileCard({super.key});

  /// Najdłuższa seria dni z treningiem (z historii wpisów).
  static int _bestStreak(List<WorkoutLog> logs) {
    final days = <String>{
      for (final log in logs)
        '${log.date.year}-${log.date.month}-${log.date.day}',
    };
    if (days.isEmpty) return 0;
    final dates = <DateTime>[
      for (final key in days)
        DateTime(
          int.parse(key.split('-')[0]),
          int.parse(key.split('-')[1]),
          int.parse(key.split('-')[2]),
        ),
    ]..sort();
    var best = 1;
    var current = 1;
    for (var i = 1; i < dates.length; i++) {
      final diff = dates[i].difference(dates[i - 1]).inDays;
      current = diff == 1 ? current + 1 : 1;
      if (current > best) best = current;
    }
    return best;
  }

  /// Aktualna seria dni treningowych (licząc wstecz od dziś albo wczoraj).
  static int _currentStreak(List<WorkoutLog> logs) {
    final days = <String>{
      for (final log in logs)
        '${log.date.year}-${log.date.month}-${log.date.day}',
    };
    if (days.isEmpty) return 0;
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(key(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(key(cursor))) return 0;
    }
    var streak = 0;
    while (days.contains(key(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = store.settings;
    final logs = store.logs;
    final sessions =
        logs.map((log) => log.sessionId).where((id) => id.isNotEmpty).toSet();
    final currentStreak = _currentStreak(logs);
    final bestStreak = _bestStreak(logs);
    final start = settings.trainingStartDate;
    final daysTraining =
        start == null ? 0 : DateTime.now().difference(start).inDays;
    final goal = SilhouetteGoal.fromId(settings.targetSilhouette);

    return Card(
      key: const Key('user_profile_card'),
      child: Padding(
        padding: uiInsets(context, const EdgeInsets.all(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TrainerProfileAvatar(
                  size: uiTouchSize(context, 64),
                  onTap: () => showProfileAvatarSheet(context),
                ),
                SizedBox(width: uiGap(context, 14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.displayName.trim().isEmpty
                            ? 'Twój profil'
                            : settings.displayName.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        settings.aboutMe.trim().isEmpty
                            ? 'Dodaj pseudonim, zdjęcie i krótki opis'
                            : settings.aboutMe.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('edit_user_profile'),
                  tooltip: 'Edytuj profil',
                  onPressed: () => showUserProfileEditor(context),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            SizedBox(height: uiGap(context, 12)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MiniTag(
                    text: currentStreak > 0
                        ? 'Seria: $currentStreak dni'
                        : 'Seria: brak'),
                if (bestStreak > 0) MiniTag(text: 'Rekord serii: $bestStreak'),
                MiniTag(text: 'Treningi: ${sessions.length}'),
                if (daysTraining > 0)
                  MiniTag(text: 'Trenujesz od $daysTraining dni'),
                if (goal != null) MiniTag(text: 'Cel: ${goal.label}'),
                MiniTag(
                    text: 'Prowadzenie: '
                        '${GuidanceMode.fromKey(settings.guidanceMode).label}'),
              ],
            ),
            if (settings.favoriteActivities.isNotEmpty) ...[
              SizedBox(height: uiGap(context, 10)),
              Text('Ulubione aktywności',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              SizedBox(height: uiGap(context, 6)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final activity in settings.favoriteActivities)
                    MiniTag(text: activity),
                ],
              ),
            ],
            SizedBox(height: uiGap(context, 10)),
            SwitchListTile(
              key: const Key('profile_stats_private'),
              contentPadding: EdgeInsets.zero,
              value: settings.profileStatsPrivate,
              title: const Text('Statystyki profilu prywatne'),
              subtitle: const Text(
                  'Nie przekazuj serii, stażu i osiągnięć do asystenta AI'),
              onChanged: (value) => store.updateSettings(
                  settings.copyWith(profileStatsPrivate: value)),
            ),
            if (!settings.onboardingCompleted ||
                settings.displayName.trim().isEmpty)
              OutlinedButton.icon(
                key: const Key('complete_profile_button'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const ProfileSetupWizardPage()),
                ),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: const Text('Uzupełnij profil'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wybór awatara: zdjęcie z galerii, aparat, gotowa ikona albo inicjały.
///
/// Zdjęcie jest KOPIOWANE do katalogu dokumentów aplikacji — ścieżka z pickera
/// wskazuje cache systemowy, który bywa czyszczony i awatar by znikał.
/// Poprzedni plik awatara usuwamy, żeby nie zostawiać śmieci na urządzeniu.
Future<void> showProfileAvatarSheet(BuildContext context) async {
  final store = AppScope.read(context);

  Future<void> pick(ImageSource source) async {
    final XFile? picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 900, imageQuality: 88);
    if (picked == null) return;
    final previous = store.settings.avatarPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.contains('.')
          ? picked.path.split('.').last.toLowerCase()
          : 'jpg';
      final dest =
          '${dir.path}/trainer_avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(picked.path).copy(dest);
      await store.updateSettings(
          store.settings.copyWith(avatarPath: dest, avatarIconKey: ''));
      if (previous.isNotEmpty && previous != dest) {
        try {
          final old = File(previous);
          if (old.existsSync()) await old.delete();
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('[Profil] Kopiowanie awatara nieudane: $error');
      await store.updateSettings(
          store.settings.copyWith(avatarPath: picked.path, avatarIconKey: ''));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          Text('Zdjęcie profilowe',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('avatar_from_gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Wybierz z galerii'),
            onTap: () {
              Navigator.pop(sheetContext);
              pick(ImageSource.gallery);
            },
          ),
          ListTile(
            key: const Key('avatar_from_camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Zrób zdjęcie'),
            onTap: () {
              Navigator.pop(sheetContext);
              pick(ImageSource.camera);
            },
          ),
          const Divider(height: 24),
          Text('Albo wybierz ikonę',
              style: Theme.of(sheetContext)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in kTrainerAvatarIcons.entries)
                IconButton.filledTonal(
                  key: Key('avatar_icon_${entry.key}'),
                  onPressed: () {
                    store.updateSettings(store.settings
                        .copyWith(avatarIconKey: entry.key, avatarPath: ''));
                    Navigator.pop(sheetContext);
                  },
                  icon: Icon(entry.value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const Key('avatar_reset'),
            onPressed: () {
              store.updateSettings(
                  store.settings.copyWith(avatarPath: '', avatarIconKey: ''));
              Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.person_outline_rounded),
            label: const Text('Zostaw inicjały'),
          ),
        ],
      ),
    ),
  );
}

/// Edycja pseudonimu, opisu, daty startu i ulubionych aktywności.
Future<void> showUserProfileEditor(BuildContext context) async {
  final store = AppScope.read(context);
  final settings = store.settings;
  final name = TextEditingController(text: settings.displayName);
  final about = TextEditingController(text: settings.aboutMe);
  var start = settings.trainingStartDate;
  final favorites = {...settings.favoriteActivities};

  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              Text('Twój profil',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('profile_name_field'),
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Imię lub pseudonim'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('profile_about_field'),
                controller: about,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'O mnie'),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Trenuję od'),
                subtitle: Text(start == null
                    ? 'Nie podano'
                    : trainerHistoryFullDate(start!)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: start ?? DateTime.now(),
                    firstDate: DateTime(1980),
                    lastDate: DateTime.now(),
                    helpText: 'Data rozpoczęcia treningów',
                  );
                  if (picked != null) setSheetState(() => start = picked);
                },
              ),
              const SizedBox(height: 6),
              Text('Ulubione aktywności',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final activity in kFavoriteActivitySuggestions)
                    FilterChip(
                      label: Text(activity),
                      selected: favorites.contains(activity),
                      onSelected: (on) => setSheetState(() {
                        if (on) {
                          favorites.add(activity);
                        } else {
                          favorites.remove(activity);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('save_user_profile'),
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Zapisz'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (saved == true) {
    await store.updateSettings(store.settings.copyWith(
      displayName: name.text.trim(),
      aboutMe: about.text.trim(),
      trainingStartDate: start,
      favoriteActivities: favorites.toList(),
    ));
  }
  name.dispose();
  about.dispose();
}

/// Awatar profilu: zdjęcie z galerii/aparatu, gotowa ikona albo inicjały.
class TrainerProfileAvatar extends StatelessWidget {
  const TrainerProfileAvatar({super.key, this.size = 48, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    final path = settings.avatarPath.trim();
    final iconKey = settings.avatarIconKey.trim();
    final name = settings.displayName.trim();

    Widget content;
    if (path.isNotEmpty && File(path).existsSync()) {
      content = ClipOval(
        child: Image.file(File(path),
            width: size, height: size, fit: BoxFit.cover, cacheWidth: 256),
      );
    } else if (kTrainerAvatarIcons.containsKey(iconKey)) {
      content = Icon(kTrainerAvatarIcons[iconKey],
          size: size * 0.5, color: scheme.onPrimaryContainer);
    } else {
      content = Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w900,
          color: scheme.onPrimaryContainer,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        key: const Key('trainer_profile_avatar'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primaryContainer,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: content,
      ),
    );
  }
}