import 'package:flutter/material.dart';

/// Etiketly launch animation — shown once on cold app start.
///
/// Timeline (total ≈ 1 700 ms):
///   0 – 250 ms   logo fades in, scales 0.92 → 1.0
///   250 – 850 ms scan line sweeps across the logo (left → right)
///   850 – 1150 ms subtle scale pulse 1.0 → 1.02 → 1.0
///   1150 – 1500 ms hold
///   1500 – 1700 ms screen fades out, [onComplete] called
///
/// [onComplete] should navigate away using replacement so no back-stack
/// entry points to this page.
class EtiketlyIntroPage extends StatefulWidget {
  const EtiketlyIntroPage({super.key, required this.onComplete});

  final VoidCallback onComplete;

  /// Exact cream colour sampled from the logo background.
  /// Also used in Android native splash (colors.xml) for a seamless
  /// colour transition before the Flutter engine draws its first frame.
  static const Color backgroundColor = Color(0xFFFBF5E9);

  @override
  State<EtiketlyIntroPage> createState() => _EtiketlyIntroPageState();
}

class _EtiketlyIntroPageState extends State<EtiketlyIntroPage>
    with TickerProviderStateMixin {
  // ── Durations ──────────────────────────────────────────────────────────────
  static const _mainDuration = Duration(milliseconds: 1500);
  static const _exitDuration = Duration(milliseconds: 200);

  // ── Controllers ────────────────────────────────────────────────────────────
  late final AnimationController _mainCtrl = AnimationController(
    vsync: this,
    duration: _mainDuration,
  );
  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: _exitDuration,
  );

  // ── Logo fade-in: 0 – 250 ms (0.000 – 0.167 of main) ─────────────────────
  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _mainCtrl,
    curve: const Interval(0.000, 0.167, curve: Curves.easeIn),
  );

  // ── Combined scale: entry + pulse, held constant in-between ───────────────
  late final Animation<double> _logoScale = TweenSequence<double>([
    // 0 – 250 ms: entry  0.92 → 1.0
    TweenSequenceItem(
      tween: Tween(
        begin: 0.92,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 16.7,
    ),
    // 250 – 850 ms: hold during scan
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40.0),
    // 850 – 1150 ms: subtle settle pulse
    TweenSequenceItem(
      tween: TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.02,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.02,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 1,
        ),
      ]),
      weight: 20.0,
    ),
    // 1150 – 1500 ms: hold
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 23.3),
  ]).animate(_mainCtrl);

  // ── Scan line: 250 – 850 ms (0.167 – 0.567 of main), progress 0 → 1 ──────
  late final Animation<double> _scanProgress =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _mainCtrl,
          curve: const Interval(0.167, 0.567, curve: Curves.easeInOut),
        ),
      );

  // ── Screen exit fade ───────────────────────────────────────────────────────
  late final Animation<double> _screenOpacity = Tween<double>(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeOut));

  // ── Sequence ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _runSequence();
  }

  Future<void> _runSequence() async {
    await _mainCtrl.forward();
    await _exitCtrl.forward();
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const logoSize = 220.0;
    const scanColor = Color(0xFFE8941A); // amber — matches the E letterform

    return Scaffold(
      backgroundColor: EtiketlyIntroPage.backgroundColor,
      body: FadeTransition(
        opacity: _screenOpacity,
        child: Center(
          child: FadeTransition(
            opacity: _logoOpacity,
            child: ScaleTransition(
              scale: _logoScale,
              child: SizedBox(
                width: logoSize,
                height: logoSize,
                child: Stack(
                  children: [
                    // Logo — opaque PNG on matching cream background
                    Image.asset(
                      'assets/branding/etiketly_icon.png',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                    ),
                    // Scan line overlay — clipped to logo bounds
                    Positioned.fill(
                      child: ClipRect(
                        child: AnimatedBuilder(
                          animation: _scanProgress,
                          builder: (context, _) => CustomPaint(
                            painter: _ScanLinePainter(
                              progress: _scanProgress.value,
                              color: scanColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a thin horizontal scan line sweeping from top to bottom.
///
/// [progress] 0.0 = line at top, 1.0 = line at bottom.
/// Outside [0, 1] the line is hidden, so there is no flash at start or end.
class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final y = size.height * progress;

    // Soft glow behind the main line
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: 0.10)
        ..strokeWidth = 10.0
        ..style = PaintingStyle.stroke,
    );

    // Primary scan line
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: 0.40)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}
