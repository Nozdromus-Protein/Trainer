// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Katalog ikon wektorowych do wyboru na kafelkach zestawów — pogrupowany
// po partiach mięśniowych, żeby wybór szedł za treścią zestawu.
part of '../../../main.dart';

/// Pojedyncza ikona wektorowa do wyboru na kafelku.
///
/// [key] jest STABILNY — trafia do zapisu, więc nie wolno go zmieniać po
/// wydaniu. Zmiana ikony to czysta warstwa wizualna: nie dotyka treści
/// zestawu, postępu ani historii.
class TileIcon {
  const TileIcon(this.key, this.icon, this.label, {this.group});

  final String key;
  final IconData icon;
  final String label;

  /// Partia, do której ikona pasuje. `null` = ikona ogólna (każdy zestaw).
  final MuscleGroup? group;

  static TileIcon? fromKey(String key) {
    for (final item in kTileIconCatalog) {
      if (item.key == key) return item;
    }
    return null;
  }
}

/// Katalog ikon do wyboru. Kolejność ma znaczenie — najpierw ogólne,
/// potem partiami, tak jak pokazuje je arkusz wyboru.
const List<TileIcon> kTileIconCatalog = [
  // — ogólne —
  TileIcon('general_dumbbell', Icons.fitness_center_rounded, 'Hantel'),
  TileIcon('general_bolt', Icons.bolt_rounded, 'Moc'),
  TileIcon('general_flame', Icons.local_fire_department_rounded, 'Spalanie'),
  TileIcon('general_calendar', Icons.calendar_month_rounded, 'Program'),
  TileIcon('general_star', Icons.star_rounded, 'Ulubione'),
  TileIcon('general_target', Icons.my_location_rounded, 'Cel'),
  TileIcon('general_trend', Icons.trending_up_rounded, 'Progres'),
  TileIcon('general_timer', Icons.timer_rounded, 'Na czas'),
  TileIcon('general_spa', Icons.spa_rounded, 'Regeneracja'),
  TileIcon('general_shield', Icons.shield_rounded, 'Stabilizacja'),

  // — klatka —
  TileIcon('chest_press', Icons.fitness_center_rounded, 'Wyciskanie',
      group: MuscleGroup.chest),
  TileIcon('chest_open', Icons.open_in_full_rounded, 'Rozpiętki',
      group: MuscleGroup.chest),
  TileIcon('chest_shield', Icons.security_rounded, 'Klatka',
      group: MuscleGroup.chest),

  // — plecy —
  TileIcon('back_row', Icons.rowing_rounded, 'Wiosłowanie',
      group: MuscleGroup.back),
  TileIcon('back_pullup', Icons.vertical_align_top_rounded, 'Podciąganie',
      group: MuscleGroup.back),
  TileIcon('back_width', Icons.swap_horiz_rounded, 'Szerokość',
      group: MuscleGroup.back),

  // — barki —
  TileIcon('shoulders_overhead', Icons.vertical_align_top_rounded,
      'Nad głowę', group: MuscleGroup.shoulders),
  TileIcon('shoulders_lateral', Icons.accessibility_new_rounded, 'Barki',
      group: MuscleGroup.shoulders),

  // — ramiona —
  TileIcon('biceps_curl', Icons.sports_mma_rounded, 'Biceps',
      group: MuscleGroup.biceps),
  TileIcon('triceps_ext', Icons.back_hand_rounded, 'Triceps',
      group: MuscleGroup.triceps),
  TileIcon('forearms_grip', Icons.front_hand_rounded, 'Przedramiona',
      group: MuscleGroup.forearms),

  // — core —
  TileIcon('core_grid', Icons.grid_on_rounded, 'Brzuch',
      group: MuscleGroup.core),
  TileIcon('core_plank', Icons.horizontal_rule_rounded, 'Deska',
      group: MuscleGroup.core),

  // — nogi —
  TileIcon('quads_squat', Icons.airline_seat_legroom_extra_rounded,
      'Przysiad', group: MuscleGroup.quadriceps),
  TileIcon('hamstrings_hinge', Icons.escalator_warning_rounded, 'Dwugłowe',
      group: MuscleGroup.hamstrings),
  TileIcon('glutes_bridge', Icons.airline_seat_recline_normal_rounded,
      'Pośladki', group: MuscleGroup.glutes),
  TileIcon('calves_raise', Icons.stairs_rounded, 'Łydki',
      group: MuscleGroup.calves),

  // — kondycja —
  TileIcon('cardio_run', Icons.directions_run_rounded, 'Bieg',
      group: MuscleGroup.cardio),
  TileIcon('cardio_bike', Icons.directions_bike_rounded, 'Rower',
      group: MuscleGroup.cardio),
  TileIcon('cardio_walk', Icons.directions_walk_rounded, 'Marsz',
      group: MuscleGroup.cardio),
  TileIcon('cardio_heart', Icons.favorite_rounded, 'Tętno',
      group: MuscleGroup.cardio),
];

/// Ikony pogrupowane do wyświetlenia: najpierw ogólne, potem po partiach.
Map<String, List<TileIcon>> tileIconGroups() {
  final result = <String, List<TileIcon>>{'Ogólne': []};
  for (final item in kTileIconCatalog) {
    final label = item.group?.label ?? 'Ogólne';
    result.putIfAbsent(label, () => <TileIcon>[]).add(item);
  }
  return result;
}

/// Ikona kafelka: wybrana przez użytkownika albo [fallback].
IconData resolvedTileIcon(
  BuildContext context, {
  required String tileKey,
  required IconData fallback,
}) =>
    AppScope.of(context).iconForTile(tileKey)?.icon ?? fallback;

/// Siatka wyboru ikony wektorowej — sekcje po partiach mięśniowych.
class TileIconPicker extends StatelessWidget {
  const TileIconPicker({
    super.key,
    required this.tileKey,
    required this.accent,
    this.suggestedGroup,
  });

  final String tileKey;
  final Color accent;

  /// Partia zestawu — jej sekcja ląduje zaraz po ogólnych.
  final MuscleGroup? suggestedGroup;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final selected = store.tileIconOverrides[tileKey] ?? '';
    final groups = tileIconGroups();

    // Kolejność sekcji: ogólne → partia tego zestawu → reszta.
    final order = <String>[
      'Ogólne',
      if (suggestedGroup != null && groups.containsKey(suggestedGroup!.label))
        suggestedGroup!.label,
      ...groups.keys.where((name) =>
          name != 'Ogólne' && name != suggestedGroup?.label),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in order)
          if ((groups[name] ?? const <TileIcon>[]).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              child: Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in groups[name]!)
                  _TileIconChoice(
                    key: Key('tile_icon_${item.key}'),
                    item: item,
                    accent: accent,
                    selected: selected == item.key,
                    onTap: () => store.setTileIcon(
                        tileKey, selected == item.key ? '' : item.key),
                  ),
              ],
            ),
          ],
      ],
    );
  }
}

class _TileIconChoice extends StatelessWidget {
  const _TileIconChoice({
    super.key,
    required this.item,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final TileIcon item;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: item.label,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Icon(item.icon,
                size: 22, color: selected ? accent : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
