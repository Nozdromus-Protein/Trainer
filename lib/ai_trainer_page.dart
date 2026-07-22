// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`). Ten sam
// zakres biblioteki — prywatne pola i importy z main.dart są dostępne bez zmian.
// Zawiera ekran AI Trainera (czat) — pierwszy krok rozbijania monolitu main.dart.
part of 'main.dart';

// ============================================================
// Etap 16: AI Trainer — czat
// ============================================================

const List<String> _kQuickQuestions = [
  'Co trenować dzisiaj?',
  'Które mięśnie są najbardziej przeciążone?',
  'Czy mój tydzień treningowy jest dobrze ułożony?',
  'Czy robię progres?',
  'Czy mam za duże RPE?',
  'Czy moje spalone kcal trafiły do Kalorii?',
  'Czy zwiększyć ciężar?',
  'Jak poprawić technikę?',
];

class AiTrainerPage extends StatefulWidget {
  const AiTrainerPage({super.key});

  @override
  State<AiTrainerPage> createState() => _AiTrainerPageState();
}

class _AiTrainerPageState extends State<AiTrainerPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(String text) {
    final store = AppScope.of(context);
    final trimmed = text.trim();
    if (trimmed.isEmpty || store.aiChatBusy) return;
    _controller.clear();
    store.chatWithAi(trimmed);
    Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.smart_toy_rounded, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Trainer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Asystent treningowy — zadaj pytanie', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (store.aiChatHistory.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Wyczyść historię',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Wyczyścić historię?'),
                        content: const Text('Wszystkie wiadomości zostaną usunięte.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyczyść')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) AppScope.of(context).clearAiChatHistory();
                  },
                ),
            ],
          ),
        ),

        // Disclaimer
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withOpacity(.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI nie zastępuje lekarza ani fizjoterapeuty. W razie bólu lub kontuzji skonsultuj się ze specjalistą.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),

        // Quick questions
        if (store.aiChatHistory.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Szybkie pytania', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kQuickQuestions
                      .map(
                        (q) => ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 12)),
                          onPressed: store.aiChatBusy ? null : () => _send(q),
                          avatar: const Icon(Icons.flash_on_rounded, size: 14),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),

        // Messages
        Expanded(
          child: store.aiChatHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 48, color: scheme.onSurfaceVariant.withOpacity(.4)),
                      const SizedBox(height: 12),
                      Text('Zadaj pierwsze pytanie', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: store.aiChatHistory.length + (store.aiChatBusy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == store.aiChatHistory.length && store.aiChatBusy) {
                      return const _TypingIndicator();
                    }
                    final msg = store.aiChatHistory[i];
                    return _ChatBubble(message: msg, isDark: isDark);
                  },
                ),
        ),

        // Quick questions (when history not empty — smaller strip)
        if (store.aiChatHistory.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: _kQuickQuestions
                  .map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(q, style: const TextStyle(fontSize: 11)),
                        onPressed: store.aiChatBusy ? null : () => _send(q),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

        // Input
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !store.aiChatBusy,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Napisz pytanie do trenera AI…',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      suffixIcon: store.aiChatBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: store.aiChatBusy ? null : () => _send(_controller.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isDark});

  final AiChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final isError = message.role == 'error';

    final bubbleColor = isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : isDark
                ? const Color(0xFF1E2A22)
                : scheme.surfaceContainerHighest;

    final textColor = isError
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isError ? scheme.errorContainer : scheme.primaryContainer,
              foregroundColor: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
              child: Icon(isError ? Icons.warning_rounded : Icons.smart_toy_rounded, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(message.content, style: TextStyle(color: textColor, fontSize: 14, height: 1.45)),
            ),
          ),
          if (isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class WorkoutAnalysisException implements Exception {
  const WorkoutAnalysisException([
    this.message = 'Nie udało się przygotować analizy treningu.',
  ]);

  final String message;

  @override
  String toString() => 'WorkoutAnalysisException: $message';
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.smart_toy_rounded, size: 14),
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) {
                        final phase = (_ctrl.value + i * 0.3) % 1.0;
                        final size = 6.0 + 3.0 * math.sin(phase * math.pi);
                        return SizedBox(
                          width: size,
                          height: size,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant.withOpacity(.7),
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

