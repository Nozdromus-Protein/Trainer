import 'package:flutter/material.dart';

/// Ekran ładowania aplikacji Trainer.
///
/// Pokazuje się wyłącznie podczas realnego wczytywania danych (AppStore.load)
/// i znika automatycznie — bez sztucznego opóźnienia i bez przycisku pomijania.
/// Styl: sportowy, miętowy akcent, delikatny pasek ładowania z gradientem.
class TrainerSplashScreen extends StatefulWidget {
  const TrainerSplashScreen({super.key});

  static const Color _mint = Color(0xFF24D6A3);

  @override
  State<TrainerSplashScreen> createState() => _TrainerSplashScreenState();
}

class _TrainerSplashScreenState extends State<TrainerSplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
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
            child: Transform.translate(offset: Offset(0, 14 * (1 - value)), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dynamiczny symbol treningu: biegnąca postać w miętowym kręgu.
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final pulse = 1 + 0.04 * (0.5 - (_controller.value - 0.5).abs()) * 2;
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
                        color: TrainerSplashScreen._mint.withValues(alpha: dark ? 0.35 : 0.25),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.directions_run_rounded, size: 52, color: Colors.white),
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: muted),
              ),
              const SizedBox(height: 30),
              // Pasek ładowania z przesuwającym się miętowym gradientem.
              SizedBox(
                width: 190,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _SplashBarPainter(
                          progress: _controller.value,
                          trackColor: dark ? Colors.white12 : Colors.black12,
                          accent: TrainerSplashScreen._mint,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rysuje pasek ładowania: tło + przesuwający się gradientowy segment.
class _SplashBarPainter extends CustomPainter {
  const _SplashBarPainter({required this.progress, required this.trackColor, required this.accent});

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
        colors: [accent.withValues(alpha: 0), accent, accent.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawRect(rect, gradient);
  }

  @override
  bool shouldRepaint(_SplashBarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.trackColor != trackColor || oldDelegate.accent != accent;
}
