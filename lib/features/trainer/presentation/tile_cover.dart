// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
// Okładki kafelków zestawów: zdjęcie jako TŁO kafelka albo ikona obok tytułu,
// oraz arkusz nadawania własnej okładki — także zestawom RDZENNYM.
part of '../../../main.dart';

/// Czy kafelki mają pokazywać okładkę jako tło (zamiast ikony obok tytułu).
bool tileBackgroundMode(BuildContext context) =>
    normalizeTileVisual(AppScope.of(context).settings.tileVisual) ==
    'background';

/// Warstwa tła kafelka: zdjęcie + przyciemnienie pod tekst.
///
/// Zwraca `null`, gdy nie ma czego pokazać (brak okładki albo tryb ikony) —
/// wywołujący zostaje wtedy przy dotychczasowym gradiencie.
Widget? tileCoverBackground(
  BuildContext context, {
  required String coverPath,
  required BorderRadius radius,
  required Color accent,
}) {
  if (coverPath.trim().isEmpty) return null;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Positioned.fill(
    child: ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          buildExerciseMediaImage(
            coverPath,
            fit: BoxFit.cover,
            // Gdy obraz nie wczyta się, tło zostaje po prostu przezroczyste
            // i kafelek wygląda jak w trybie ikony — nic się nie psuje.
            fallback: const SizedBox.shrink(),
          ),
          // Przyciemnienie: tekst na kafelku musi zostać czytelny niezależnie
          // od tego, jak jasne jest zdjęcie użytkownika.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.78),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.86),
                      ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  accent.withValues(alpha: isDark ? 0.20 : 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Kafelek z opcjonalnym tłem-okładką.
///
/// Składa dotychczasową dekorację (gradient/obrys) z warstwą zdjęcia, gdy
/// użytkownik wybrał tryb „Tło" i kafelek ma okładkę.
class TileCoverShell extends StatelessWidget {
  const TileCoverShell({
    super.key,
    required this.coverPath,
    required this.radius,
    required this.accent,
    required this.decoration,
    required this.padding,
    required this.child,
  });

  final String coverPath;
  final BorderRadius radius;
  final Color accent;
  final BoxDecoration decoration;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = tileBackgroundMode(context)
        ? tileCoverBackground(
            context,
            coverPath: coverPath,
            radius: radius,
            accent: accent,
          )
        : null;
    if (background == null) {
      return Container(
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: decoration,
      child: Stack(
        children: [
          background,
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
}) async {
  final store = AppScope.read(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AppScope(
      store: store,
      child: _TileCoverSheet(tileKey: tileKey, title: title),
    ),
  );
}

class _TileCoverSheet extends StatefulWidget {
  const _TileCoverSheet({required this.tileKey, required this.title});

  final String tileKey;
  final String title;

  @override
  State<_TileCoverSheet> createState() => _TileCoverSheetState();
}

class _TileCoverSheetState extends State<_TileCoverSheet> {
  bool _busy = false;

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
            FilledButton.icon(
              key: const Key('tile_cover_pick'),
              onPressed: _busy ? null : _pick,
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
            const SizedBox(height: 12),
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
