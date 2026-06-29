import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/legal/legal_link_launcher.dart';
import 'package:food_analyzer_app/core/legal/legal_links.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

/// Data for a single onboarding slide.
@immutable
class _Slide {
  const _Slide({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    icon: Icons.qr_code_scanner_rounded,
    iconColor: AppColors.primary,
    title: 'Etiketi tara',
    body:
        'Ürün barkodunu veya etiketini tarayarak içerik bilgilerine hızlıca ulaş.',
  ),
  _Slide(
    icon: Icons.list_alt_rounded,
    iconColor: AppColors.accent,
    title: 'İçindekileri anla',
    body:
        'Katkı maddeleri, alerjenler ve dikkat edilmesi gereken içerikleri daha anlaşılır gör.',
  ),
  _Slide(
    icon: Icons.compare_arrows_rounded,
    iconColor: AppColors.info,
    title: 'Ürünleri karşılaştır',
    body: 'Benzer ürünlerin besin değerlerini ve içeriklerini yan yana incele.',
  ),
  _Slide(
    icon: Icons.lightbulb_outline_rounded,
    iconColor: AppColors.warning,
    title: 'Bilgiyle seçim yap',
    body: 'Etiketly bilgilendirme amaçlıdır; tıbbi tavsiye yerine geçmez.',
  ),
];

/// First-launch onboarding flow shown once after the Etiketly intro animation.
///
/// [onComplete] is called (with onboarding persisted) when the user taps
/// "Başlayalım" or "Atla". The router is responsible for persisting completion
/// and navigating to the home route.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _currentPage = 0;

  bool get _isLast => _currentPage == _slides.length - 1;

  void _advance() {
    if (_isLast) {
      widget.onComplete();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip button ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('Atla'),
                ),
              ),
            ),

            // ── Slide content ──────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _SlideView(slide: _slides[index], isLast: index == 3),
              ),
            ),

            // ── Page indicators ────────────────────────────────────────────
            _Indicators(count: _slides.length, current: _currentPage),
            const SizedBox(height: 20),

            // ── CTA ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FilledButton(
                onPressed: _advance,
                child: Text(_isLast ? 'Başlayalım' : 'Devam'),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

// ── Slide ──────────────────────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.isLast});

  final _Slide slide;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: slide.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(slide.icon, size: 42, color: slide.iconColor),
          ),
          const SizedBox(height: 30),

          // Title
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),

          // Body
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),

          // Legal footer — last page only
          if (isLast) ...[const SizedBox(height: 28), const _LegalFooter()],
        ],
      ),
    );
  }
}

// ── Legal footer ───────────────────────────────────────────────────────────────

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary);
    final linkStyle = style?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textSecondary,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        GestureDetector(
          onTap: () => openLegalLink(context, LegalLinks.privacy),
          child: Text('Gizlilik Politikası', style: linkStyle),
        ),
        Text('·', style: style),
        GestureDetector(
          onTap: () => openLegalLink(context, LegalLinks.terms),
          child: Text('Kullanım Şartları', style: linkStyle),
        ),
        Text('·', style: style),
        Text('Bilgilendirme amaçlıdır', style: style),
      ],
    );
  }
}

// ── Page indicators ────────────────────────────────────────────────────────────

class _Indicators extends StatelessWidget {
  const _Indicators({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
