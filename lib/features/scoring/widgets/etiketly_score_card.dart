import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

class EtiketlyScoreCard extends StatelessWidget {
  const EtiketlyScoreCard({super.key, required this.state});

  final ProductEtiketlyScoreState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      ProductEtiketlyScoreStatus.loading => _ScoreShell(
        key: const ValueKey('etiketly-score-loading'),
        child: _LoadingContent(onShowInfo: () => _showMethodology(context)),
      ),
      ProductEtiketlyScoreStatus.calculated => _CalculatedScoreContent(
        state: state,
        onShowInfo: () => _showMethodology(context),
      ),
      ProductEtiketlyScoreStatus.unavailable => _ScoreShell(
        key: const ValueKey('etiketly-score-unavailable'),
        child: _UnavailableContent(
          state: state,
          onShowInfo: () => _showMethodology(context),
        ),
      ),
      ProductEtiketlyScoreStatus.error => _ScoreShell(
        key: const ValueKey('etiketly-score-error'),
        child: _ErrorContent(onShowInfo: () => _showMethodology(context)),
      ),
    };
  }

  void _showMethodology(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => const _ScoreMethodologySheet(),
    );
  }
}

class _CalculatedScoreContent extends StatelessWidget {
  const _CalculatedScoreContent({
    required this.state,
    required this.onShowInfo,
  });

  final ProductEtiketlyScoreState state;
  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    final style = _styleForBand(state.band!);
    final score = state.displayScore!;
    final qualityLabel = state.qualityLabel!;

    return Semantics(
      key: const ValueKey('etiketly-score-calculated'),
      container: true,
      label:
          'Etiketly Puanı $score üzerinden 100. İçerik profili: $qualityLabel. '
          'Beslenme kalitesi ${state.nutritionDisplayScore} üzerinden 100. '
          'Katkı kalitesi ${state.additiveDisplayScore} üzerinden 100.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [style.background, AppColors.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: style.foreground.withValues(alpha: 0.3)),
          boxShadow: AppShadows.soft(style.foreground),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScoreHeader(onShowInfo: onShowInfo),
            const SizedBox(height: 16),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 14,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$score',
                      key: const ValueKey('etiketly-score-value'),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: style.foreground,
                        fontSize: 58,
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '/100',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                Container(
                  key: const ValueKey('etiketly-score-quality-label'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: style.foreground.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '$qualityLabel içerik profili',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: style.foreground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Puanı ne etkiledi?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _ComponentScores(state: state),
            const SizedBox(height: 12),
            Text(
              state.additiveSummary!,
              key: const ValueKey('etiketly-additive-summary'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (state.hasBeverageNnsOverlap) ...[
              const SizedBox(height: 5),
              Text(
                'Tatlandırıcı etkisi beslenme bileşeninde hesaba katıldı.',
                key: const ValueKey('etiketly-nns-overlap-note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComponentScores extends StatelessWidget {
  const _ComponentScores({required this.state});

  final ProductEtiketlyScoreState state;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ComponentScore(
        key: const ValueKey('etiketly-nutrition-component'),
        icon: Icons.restaurant_menu_rounded,
        label: 'Beslenme kalitesi',
        value: state.nutritionDisplayScore!,
      ),
      _ComponentScore(
        key: const ValueKey('etiketly-additive-component'),
        icon: Icons.science_outlined,
        label: 'Katkı kalitesi',
        value: state.additiveDisplayScore!,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (constraints.maxWidth < 320 || largeText) {
          return Column(
            children: [cards.first, const SizedBox(height: 8), cards.last],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards.first),
              const SizedBox(width: 8),
              Expanded(child: cards.last),
            ],
          ),
        );
      },
    );
  }
}

class _ComponentScore extends StatelessWidget {
  const _ComponentScore({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$value / 100',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent({required this.onShowInfo});

  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Etiketly Puanı hesaplanıyor.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreHeader(onShowInfo: onShowInfo),
          const SizedBox(height: 18),
          Row(
            children: [
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Doğrulanmış bilgiler değerlendiriliyor…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnavailableContent extends StatelessWidget {
  const _UnavailableContent({required this.state, required this.onShowInfo});

  final ProductEtiketlyScoreState state;
  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Etiketly Puanı hesaplanamadı. ${state.message} '
          '${state.reasons.join(' ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreHeader(onShowInfo: onShowInfo),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Etiketly Puanı hesaplanamadı',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      state.message!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...state.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: SizedBox.square(
                        dimension: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.onShowInfo});

  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Etiketly Puanı şu anda hesaplanamadı.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreHeader(onShowInfo: onShowInfo),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.refresh_rounded, color: AppColors.neutralText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Puan şu anda hesaplanamadı.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreShell extends StatelessWidget {
  const _ScoreShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft(AppColors.neutral),
      ),
      child: child,
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.onShowInfo});

  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          'ETİKETLY PUANI',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.primary,
            letterSpacing: 0.75,
          ),
        ),
        TextButton.icon(
          key: const ValueKey('etiketly-score-info-button'),
          onPressed: onShowInfo,
          icon: const Icon(Icons.info_outline_rounded, size: 17),
          label: const Text('Nasıl hesaplanıyor?'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ],
    );
  }
}

class _ScoreMethodologySheet extends StatelessWidget {
  const _ScoreMethodologySheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Etiketly Puanı nasıl hesaplanır?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Etiketly Puanı, doğrulanmış besin değerleri ve doğrulanmış katkı '
              'değerlendirmesinden deterministik olarak hesaplanır.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 14),
            const _MethodologyWeight(label: 'Beslenme kalitesi', value: '%80'),
            const SizedBox(height: 8),
            const _MethodologyWeight(
              label: 'Katkı değerlendirmesi',
              value: '%20',
            ),
            const SizedBox(height: 14),
            Text(
              'Puan bir tıbbi değerlendirme veya kişisel beslenme önerisi değildir.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodologyWeight extends StatelessWidget {
  const _MethodologyWeight({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBandStyle {
  const _ScoreBandStyle({required this.foreground, required this.background});

  final Color foreground;
  final Color background;
}

_ScoreBandStyle _styleForBand(EtiketlyScoreBand band) => switch (band) {
  EtiketlyScoreBand.veryGood => const _ScoreBandStyle(
    foreground: Color(0xFF24704C),
    background: Color(0xFFE8F6EE),
  ),
  EtiketlyScoreBand.good => const _ScoreBandStyle(
    foreground: Color(0xFF52783A),
    background: Color(0xFFEEF6E8),
  ),
  EtiketlyScoreBand.medium => const _ScoreBandStyle(
    foreground: Color(0xFF966515),
    background: Color(0xFFFFF3D8),
  ),
  EtiketlyScoreBand.weak => const _ScoreBandStyle(
    foreground: Color(0xFFA65E32),
    background: Color(0xFFFFEFE3),
  ),
  EtiketlyScoreBand.veryWeak => const _ScoreBandStyle(
    foreground: Color(0xFF9B4B4B),
    background: Color(0xFFFFECEC),
  ),
};
