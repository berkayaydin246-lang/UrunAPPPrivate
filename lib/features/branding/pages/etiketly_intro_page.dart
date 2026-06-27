import 'package:flutter/material.dart';

/// Etiketly launch animation — shown once on cold app start.
///
/// Timeline (total ≈ 2 300 ms):
///   0 – 350 ms   logo fades in, scales 0.90 → 1.00  (easeOutCubic)
///   350 – 1 300 ms  scan line sweeps across logo bounds  (easeInOutCubic)
///   1 050 – 1 550 ms  settle pulse 1.00 → 1.035 → 1.00 (overlaps scan exit)
///   1 550 – 2 000 ms  calm hold
///   2 000 – 2 300 ms  screen fades out, [onComplete] called
///
/// [onComplete] must navigate away with replacement so no back-stack entry
/// points back to this page.
class EtiketlyIntroPage extends StatefulWidget {
  const EtiketlyIntroPage({super.key, required this.onComplete});

  final VoidCallback onComplete;

  /// Exact cream sampled from the Etiketly logo background.
  /// Must match Android colors.xml @color/splashBackground so there is no
  /// colour flash between the native splash and the Flutter frame.
  static const Color backgroundColor = Color(0xFFFBF5E9);

  @override
  State<EtiketlyIntroPage> createState() => _EtiketlyIntroPageState();
}

class _EtiketlyIntroPageState extends State<EtiketlyIntroPage>
    with TickerProviderStateMixin {
  // ── Durations ──────────────────────────────────────────────────────────────
  static const _mainDuration = Duration(milliseconds: 2000);
  static const _exitDuration = Duration(milliseconds: 300);

  // ── Controllers ────────────────────────────────────────────────────────────
  late final AnimationController _mainCtrl = AnimationController(
    vsync: this,
    duration: _mainDuration,
  );
  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: _exitDuration,
  );

  // ── Logo fade-in: 0 – 350 ms (0.000 – 0.175) ─────────────────────────────
  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _mainCtrl,
    curve: const Interval(0.000, 0.175, curve: Curves.easeIn),
  );

  // ── Combined scale  ───────────────────────────────────────────────────────
  // Weights correspond to milliseconds (sum = 2000):
  //   350 entry | 700 hold | 500 settle | 450 hold
  late final Animation<double> _logoScale = TweenSequence<double>([
    // 0 – 350 ms: entry  0.90 → 1.00
    TweenSequenceItem(
      tween: Tween(
        begin: 0.90,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 17.5,
    ),
    // 350 – 1 050 ms: hold at 1.0 during scan
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 35.0),
    // 1 050 – 1 550 ms: settle pulse  1.0 → 1.035 → 1.0
    TweenSequenceItem(
      tween: TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.035,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.035,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 1,
        ),
      ]),
      weight: 25.0,
    ),
    // 1 550 – 2 000 ms: calm hold
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 22.5),
  ]).animate(_mainCtrl);

  // ── Scan line: 350 – 1 300 ms (0.175 – 0.650), progress 0 → 1 ───────────
  late final Animation<double> _scanProgress =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _mainCtrl,
          curve: const Interval(0.175, 0.650, curve: Curves.easeInOutCubic),
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
    // ~30–35% larger than the previous 220 dp hardcoded value.
    // Clamped so it stays proportional on tablets.
    final logoSize = (MediaQuery.of(context).size.width * 0.75).clamp(
      270.0,
      310.0,
    );

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
                    // Transparent logo mark — no visible background square.
                    Image.asset(
                      'assets/branding/etiketly_logo_mark.png',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                    ),
                    // Scan line — clipped to the logo bounding box.
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

/// Draws a thin horizontal amber scan line that sweeps from top to bottom
/// within the logo bounding box.
///
/// The line fades in during the first 10 % of travel and fades out during
/// the last 10 %, making its appearance feel intentional rather than abrupt.
class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  // Compute line opacity with soft lead-in / lead-out.
  static double _lineOpacity(double p) {
    const fade = 0.10;
    if (p <= 0.0 || p >= 1.0) return 0.0;
    if (p < fade) return p / fade;
    if (p > 1.0 - fade) return (1.0 - p) / fade;
    return 1.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = _lineOpacity(progress);
    if (opacity == 0.0) return;

    final y = size.height * progress;
    final halfW = size.width * 0.5;

    // Glow pass — wide, very soft
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: opacity * 0.10)
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // Primary line — centred third of the logo width is brightest
    final lineOpacityPrimary = opacity * 0.50;
    canvas.drawLine(
      Offset(halfW - size.width * 0.42, y),
      Offset(halfW + size.width * 0.42, y),
      Paint()
        ..color = color.withValues(alpha: lineOpacityPrimary)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) =>
      old.progress != progress || old.color != color;
}
