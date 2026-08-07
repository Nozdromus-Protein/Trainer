// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Okładki kafelków zestawów: zdjęcie jako TŁO kafelka albo ikona obok tytułu,
// oraz arkusz nadawania własnej okładki — także zestawom RDZENNYM.
part of '../../../main.dart';

/// Czy kafelki mają pokazywać okładkę jako tło (zamiast ikony obok tytułu).
bool tileBackgroundMode(BuildContext context) =>
    normalizeTileVisual(AppScope.of(context).settings.tileVisual) ==
    'background';

/// Kafelek z opcjonalnym tłem-okładką.
///
/// W trybie „Tło" kafelek dzieli się POZIOMO: górna część to zdjęcie, dolna
/// jest zarezerwowana na nagłówek i opis. Zdjęcie nie kończy się twardą
/// krawędzią — dolne 30% pasma płynnie zanika w kolor kafelka.
///
/// Pasmo ma stałe PROPORCJE ([coverAspect]), nie sztywną wysokość: kafelki
/// niosą różną ilość treści, więc wymuszone 50/50 albo rozpychało kafelek,
/// albo ucinało tekst.
///
/// Bez okładki (albo w trybie „Ikony") kafelek wygląda dokładnie jak dotąd:
/// wysokość idzie za treścią, tło to gradient z [decoration].
class TileCoverShell extends StatelessWidget {
  const TileCoverShell({
    super.key,
    required this.coverPath,
    required this.radius,
    required this.accent,
    required this.decoration,
    required this.padding,
    required this.child,
    this.coverAspect = 16 / 7,
  });

  final String coverPath;
  final BorderRadius radius;
  final Color accent;
  final BoxDecoration decoration;
  final EdgeInsets padding;
  final Widget child;

  /// Proporcje pasma ze zdjęciem (szerokość ÷ wysokość). Im mniejsza liczba,
  /// tym wyższe pasmo — domyślne 16:7 daje na typowym kafelku mniej więcej
  /// górną połowę.
  final double coverAspect;

  @override
  Widget build(BuildContext context) {
    final showBackground =
        coverPath.trim().isNotEmpty && tileBackgroundMode(context);
    if (!showBackground) {
      return Container(
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Kolor, w który zdjęcie ma zaniknąć: podstawa kafelka. Przy gradiencie
    // akcentu `decoration.color` jest puste, więc bierzemy tło karty — akcent
    // ma i tak niską krycie, a przejście zostaje niewidoczne.
    final fadeInto =
        decoration.color ?? theme.cardTheme.color ?? scheme.surface;

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GÓRNA CZĘŚĆ — zdjęcie zanikające ku dołowi.
          //
          // Pasmo ma stałe PROPORCJE, a nie sztywną wysokość: kafelki niosą
          // różną ilość treści (chipy, przyciski), więc twarde 50/50 albo
          // rozpychało kafelek do absurdalnej wysokości, albo ucinało tekst.
          AspectRatio(
            aspectRatio: coverAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                buildExerciseMediaImage(
                  coverPath,
                  fit: BoxFit.cover,
                  // Gdy obraz nie wczyta się, zostaje sam gradient kafelka —
                  // układ się nie rozjeżdża.
                  fallback: const SizedBox.shrink(),
                ),
                // Miękkie zejście zamiast twardej krawędzi: zdjęcie jest czyste
                // przez pierwsze 70% pasma, a dolne 30% płynnie przechodzi
                // w kolor kafelka.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.70, 1.0],
                      colors: [
                        Colors.transparent,
                        fadeInto.withValues(alpha: 0.0),
                        fadeInto,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // DOLNA CZĘŚĆ — nagłówek i opis na czystym tle kafelka.
          // Bez własnego koloru, żeby nie powstała druga krawędź.
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Otwiera arkusz nadawania okładki kafelkowi zestawu.
///
/// Działa dla zestawów RDZENNYCH (program, rozgrzewka, rozciąganie, cardio) —
/// także takich, których użytkownik jeszcze nie rozpoczął. Okładka jest tylko
/// warstwą wizualną: nie dotyka treści zestawu ani postępu.
Future<void> showTileCoverSheet(
  BuildContext context, {
  required String tileKey,
  required String title,
  Color? accent,
  MuscleGroup? group,
  List<String> mainMuscles = const [],
  List<String> equipment = const [],
}) async {
  final store = AppScope.read(context);
  final tone = accent ?? Theme.of(context).colorScheme.primary;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AppScope(
      store: store,
      child: _TileCoverSheet(
        tileKey: tileKey,
        title: title,
        accent: tone,
        group: group,
        mainMuscles: mainMuscles,
        equipment: equipment,
      ),
    ),
  );
}

class _TileCoverSheet extends StatefulWidget {
  const _TileCoverSheet({
    required this.tileKey,
    required this.title,
    required this.accent,
    this.group,
    this.mainMuscles = const [],
    this.equipment = const [],
  });

  final String tileKey;
  final String title;
  final Color accent;

  /// Partia zestawu — podpowiada, które ikony pokazać najwyżej.
  final MuscleGroup? group;
  final List<String> mainMuscles;
  final List<String> equipment;

  @override
  State<_TileCoverSheet> createState() => _TileCoverSheetState();
}

class _TileCoverSheetState extends State<_TileCoverSheet> {
  bool _busy = false;
  bool _generating = false;

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final store = AppScope.read(context);
      final previous = store.tileCoverOverrides[widget.tileKey] ?? '';
      await store.generateTileCoverWithAi(
        tileKey: widget.tileKey,
        title: widget.title,
        mainMuscles: widget.mainMuscles,
        equipment: widget.equipment,
      );
      // Poprzednią NASZĄ kopię sprzątamy — zdjęć z galerii nigdy nie ruszamy.
      if (previous.isNotEmpty && previous.contains('tile_covers')) {
        try {
          final old = File(previous);
          if (old.existsSync()) await old.delete();
        } catch (error) {
          debugPrint('[Trainer] Nie udało się usunąć starej okładki: $error');
        }
      }
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyAiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;

      // Kopiujemy do katalogu aplikacji — oryginał w galerii zostaje nietknięty,
      // a okładka przeżyje sprzątanie pamięci podręcznej systemu.
      final documents = await getApplicationDocumentsDirectory();
      final dir = Directory('${documents.path}/tile_covers');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeKey = widget.tileKey.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      final dest = File('${dir.path}/${safeKey}_${idNow()}.jpg');
      await dest.writeAsBytes(await picked.readAsBytes(), flush: true);

      if (!mounted) return;
      // `mounted` stanu wystarcza: to kontekst TEGO widgetu, nie obcy.
      final store = AppScope.read(context);
      final previous = store.tileCoverOverrides[widget.tileKey] ?? '';
      await store.setTileCover(widget.tileKey, dest.path);
      // Sprzątamy poprzednią okładkę — ale tylko NASZĄ kopię, nigdy zdjęcia
      // użytkownika z galerii.
      if (previous.isNotEmpty && previous.contains('tile_covers')) {
        try {
          final old = File(previous);
          if (old.existsSync()) await old.delete();
        } catch (error) {
          debugPrint('[Trainer] Nie udało się usunąć starej okładki: $error');
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      showError(context, 'Nie udało się ustawić okładki: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = store.tileCoverOverrides[widget.tileKey] ?? '';
    final backgroundMode = tileBackgroundMode(context);

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
            Text('Okładka kafelka',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (current.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: buildExerciseMediaImage(
                    current,
                    fit: BoxFit.cover,
                    fallback: Container(
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Text('Nie udało się wczytać obrazu'),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Ten kafelek nie ma jeszcze własnej okładki — pokazuje ikonę.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 14),
            _SheetSectionLabel(
              icon: Icons.wallpaper_rounded,
              title: 'Tło kafelka',
              hint: 'Zdjęcie z galerii albo grafika wygenerowana przez AI.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('tile_cover_pick'),
              onPressed: _busy || _generating ? null : _pick,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_library_rounded),
              label: Text(current.isEmpty
                  ? 'Wybierz zdjęcie z galerii'
                  : 'Zmień zdjęcie'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('tile_cover_generate'),
              onPressed: _busy || _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating
                  ? 'Generuję tło…'
                  : 'Wygeneruj tło przez AI'),
            ),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('tile_cover_clear'),
                onPressed: _busy
                    ? null
                    : () async {
                        // Nawigator bierzemy PRZED await — po nim kontekst
                        // może już nie należeć do żywego drzewa.
                        final navigator = Navigator.of(context);
                        await store.setTileCover(widget.tileKey, '');
                        if (!mounted) return;
                        navigator.pop();
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Usuń okładkę'),
              ),
            ],
            const SizedBox(height: 18),
            _SheetSectionLabel(
              icon: Icons.category_rounded,
              title: 'Ikona kafelka',
              hint: 'Widoczna w trybie „Ikony" — i wszędzie tam, gdzie '
                  'kafelek nie ma tła. Ponowne dotknięcie usuwa wybór.',
            ),
            TileIconPicker(
              tileKey: widget.tileKey,
              accent: widget.accent,
              suggestedGroup: widget.group,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    backgroundMode
                        ? Icons.image_rounded
                        : Icons.apps_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      backgroundMode
                          ? 'Kafelki pokazują okładkę jako tło. Zmienisz to '
                              'w Więcej → Personalizacja → Kafelki zestawów.'
                          : 'Kafelki pokazują teraz ikony. Aby zdjęcie wypełniło '
                              'cały kafelek, przełącz w Więcej → Personalizacja '
                              '→ Kafelki zestawów na „Tło".',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
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

/// Nagłówek sekcji w arkuszu okładki — jeden rytm dla tła i ikon.
class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
