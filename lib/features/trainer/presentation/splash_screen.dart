import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Stan ładowania pokazywany na splashu: ile już zrobione i co się właśnie
/// dzieje. Jedna klasa dla wszystkich etapów startu aplikacji.
@immutable
class AppLoadProgress {
  /// Postęp 0..1. Wartość ujemna = postęp nieznany (pasek nieokreślony).
  final double value;

  /// Krok opisany po ludzku — ląduje małym druczkiem pod paskiem.
  final String label;

  const AppLoadProgress(this.value, this.label);

  /// Etap bez policzalnego postępu (np. inicjalizacja konta).
  const AppLoadProgress.indeterminate(this.label) : value = -1;

  bool get isDeterminate => value >= 0;

  int get percent => (value.clamp(0.0, 1.0) * 100).round();
}

/// Ekran ładowania aplikacji Trainer.
///
/// Pokazuje się wyłącznie podczas realnego wczytywania danych (AppStore.load)
/// i znika automatycznie — bez sztucznego opóźnienia i bez przycisku pomijania.
///
/// Gdy dostanie [progress], pasek jest OKREŚLONY: pokazuje procent i nazwę
/// bieżącego kroku małym druczkiem. Bez [progress] wraca do paska
/// przesuwającego się w kółko (tam, gdzie postępu nie da się policzyć).
class TrainerSplashScreen extends StatefulWidget {
  const TrainerSplashScreen({super.key, this.progress});

  final ValueListenable<AppLoadProgress>? progress;

  static const Color _mint = Color(0xFF24D6A3);

  @override
  State<TrainerSplashScreen> createState() => _TrainerSplashScreenState();
}

class _TrainerSplashScreenState extends State<TrainerSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final background = dark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final onBackground = dark ? Colors.white : const Color(0xFF12211C);
    final muted = dark ? Colors.white60 : const Color(0xFF5B6B66);

    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dynamiczny symbol treningu: biegnąca postać w miętowym kręgu.
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final pulse =
                      1 + 0.04 * (0.5 - (_controller.value - 0.5).abs()) * 2;
                  return Transform.scale(scale: pulse, child: child);
                },
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        TrainerSplashScreen._mint,
                        TrainerSplashScreen._mint.withValues(alpha: 0.55),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: TrainerSplashScreen._mint
                            .withValues(alpha: dark ? 0.35 : 0.25),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.directions_run_rounded,
                      size: 52, color: Colors.white),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Trainer',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: onBackground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Przygotowuję trening…',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: muted),
              ),
              const SizedBox(height: 30),
              _SplashProgress(
                progress: widget.progress,
                controller: _controller,
                dark: dark,
                muted: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pasek postępu splasha wraz z procentem i podpisem kroku.
class _SplashProgress extends StatelessWidget {
  const _SplashProgress({
    required this.progress,
    required this.controller,
    required this.dark,
    required this.muted,
  });

  final ValueListenable<AppLoadProgress>? progress;
  final AnimationController controller;
  final bool dark;
  final Color muted;

  static const double _barWidth = 220;

  @override
  Widget build(BuildContext context) {
    final listenable = progress;
    if (listenable == null) {
      return _bar(const AppLoadProgress.indeterminate(''));
    }
    return ValueListenableBuilder<AppLoadProgress>(
      valueListenable: listenable,
      builder: (context, value, _) => _bar(value),
    );
  }

  Widget _bar(AppLoadProgress state) {
    final track = dark ? Colors.white12 : Colors.black12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _barWidth,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              color: track,
              child: state.isDeterminate
                  // Określony postęp: pasek dopełza do nowej wartości, żeby
                  // skoki między etapami nie migały.
                  ? TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                          begin: 0, end: state.value.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: value <= 0 ? 0.001 : value,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  TrainerSplashScreen._mint
                                      .withValues(alpha: 0.75),
                                  TrainerSplashScreen._mint,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => CustomPaint(
                        painter: _SplashBarPainter(
                          progress: controller.value,
                          trackColor: track,
                          accent: TrainerSplashScreen._mint,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (state.label.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: _barWidth + 60,
            child: Text(
              state.isDeterminate
                  ? '${state.percent}% · ${state.label}'
                  : state.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Rysuje nieokreślony pasek ładowania: tło + przesuwający się segment.
class _SplashBarPainter extends CustomPainter {
  const _SplashBarPainter(
      {required this.progress, required this.trackColor, required this.accent});

  final double progress;
  final Color trackColor;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = trackColor;
    canvas.drawRect(Offset.zero & size, track);

    const segmentFraction = 0.42;
    final segmentWidth = size.width * segmentFraction;
    // Segment wjeżdża z lewej i wyjeżdża z prawej (pełny cykl kontrolera).
    final travel = size.width + segmentWidth;
    final left = -segmentWidth + travel * progress;
    final rect = Rect.fromLTWH(left, 0, segmentWidth, size.height);
    final gradient = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0),
          accent,
          accent.withValues(alpha: 0)
        ],
      ).createShader(rect);
    canvas.drawRect(rect, gradient);
  }

  @override
  bool shouldRepaint(_SplashBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.accent != accent;
}
