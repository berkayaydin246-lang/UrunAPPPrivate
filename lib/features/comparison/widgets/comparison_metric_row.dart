import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/salt_shaker_icon.dart';
import 'package:food_analyzer_app/features/comparison/domain/comparison_metric.dart';
import 'package:food_analyzer_app/features/product/widgets/product_detail_shared.dart';

class ComparisonMetricRow extends StatelessWidget {
  const ComparisonMetricRow({
    super.key,
    required this.metric,
    this.showDivider = true,
  });

  final ComparisonMetric metric;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final nutrientVisual = nutrientVisualDataForKey(
      metric.key,
      metric.productAValue ?? metric.productBValue,
    );
    final icon = nutrientVisual?.icon ?? Icons.bar_chart_rounded;
    final iconColor = productNutrientToneColor(
      nutrientVisual?.tone ?? ProductNutrientTone.neutral,
    );
    return Semantics(
      container: true,
      label: _semanticLabel(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: showDivider
              ? const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricLeadingIcon(
                      metricKey: metric.key,
                      fallbackIcon: icon,
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          metric.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: _MetricValueCell(
                  cellKey: 'comparison-metric-${metric.key}-a',
                  textAlign: TextAlign.left,
                  valueText: _valueText(
                    metric.productAValue,
                    metric.displayUnit,
                  ),
                  tone: _toneForSide(productA: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: _MetricValueCell(
                  cellKey: 'comparison-metric-${metric.key}-b',
                  textAlign: TextAlign.right,
                  valueText: _valueText(
                    metric.productBValue,
                    metric.displayUnit,
                  ),
                  tone: _toneForSide(productA: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _MetricValueTone _toneForSide({required bool productA}) {
    final value = productA ? metric.productAValue : metric.productBValue;
    if (value == null) {
      return _MetricValueTone.missing;
    }
    if (metric.preference == ComparisonPreference.neutral) {
      return _MetricValueTone.plain;
    }
    if (metric.outcome == ComparisonOutcome.equal ||
        metric.outcome == ComparisonOutcome.notComparable ||
        metric.outcome == ComparisonOutcome.missingData ||
        metric.outcome == ComparisonOutcome.neutral) {
      return _MetricValueTone.plain;
    }

    final isBetter = productA
        ? metric.highlightsProductA
        : metric.highlightsProductB;
    return isBetter ? _MetricValueTone.better : _MetricValueTone.worse;
  }

  String _semanticLabel() {
    final leftStatus = metric.highlightsProductA ? ', daha iyi seçenek' : '';
    final rightStatus = metric.highlightsProductB ? ', daha iyi seçenek' : '';
    final status = metric.centralStatusLabel.isNotEmpty
        ? ' ${metric.centralStatusLabel}.'
        : '';
    return '${metric.label}. Sol ürün ${_valueText(metric.productAValue, metric.displayUnit)}'
        '$leftStatus. Sağ ürün ${_valueText(metric.productBValue, metric.displayUnit)}'
        '$rightStatus.$status';
  }

  String _valueText(double? value, String unit) {
    if (value == null) return 'Bilgi yok';
    final formatted = value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$formatted $unit';
  }
}

class _MetricLeadingIcon extends StatelessWidget {
  const _MetricLeadingIcon({
    required this.metricKey,
    required this.fallbackIcon,
    required this.color,
  });

  final String metricKey;
  final IconData fallbackIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('comparison-metric-$metricKey-icon'),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: metricKey == 'salt'
            ? SaltShakerIcon(color: color, size: 18)
            : Icon(fallbackIcon, size: 18, color: color),
      ),
    );
  }
}

enum _MetricValueTone { better, worse, plain, missing }

class _MetricValueCell extends StatelessWidget {
  const _MetricValueCell({
    required this.cellKey,
    required this.textAlign,
    required this.valueText,
    required this.tone,
  });

  final String cellKey;
  final TextAlign textAlign;
  final String valueText;
  final _MetricValueTone tone;

  @override
  Widget build(BuildContext context) {
    final isMissing = tone == _MetricValueTone.missing;
    final isBetter = tone == _MetricValueTone.better;
    final isWorse = tone == _MetricValueTone.worse;
    final accentColor = AppColors.positive;
    final worseColor = AppColors.danger.withValues(alpha: 0.68);
    final crossAxisAlignment = textAlign == TextAlign.right
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Column(
      key: ValueKey(cellKey),
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          key: ValueKey('$cellKey-text'),
          valueText,
          textAlign: textAlign,
          style:
              (isMissing
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                    color: isMissing
                        ? AppColors.textSecondary
                        : (isBetter
                              ? accentColor
                              : (isWorse ? worseColor : AppColors.textPrimary)),
                    fontSize: isMissing ? 13 : 16,
                    fontWeight: isBetter ? FontWeight.w800 : FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
        ),
        if (isBetter) ...[
          const SizedBox(height: 2),
          Container(
            key: ValueKey('$cellKey-underline'),
            width: 28,
            height: 2,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    );
  }
}
