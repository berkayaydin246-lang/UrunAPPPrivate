import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

enum ProductEtiketlyScoreStatus { loading, calculated, unavailable, error }

enum EtiketlyScoreBand { veryGood, good, medium, weak, veryWeak }

/// Coarse, public-safe reason a score is not currently displayed. Derived
/// only from data the consumer app is already authorized to read (the
/// product row and the live scoring evaluation) — never from privileged
/// `product_staging` recovery diagnostics, which stay admin/recovery-tooling
/// only. See [ScoringBlockerDiagnosticService] for the privileged, detailed
/// equivalent used by admin/recovery tooling.
enum ProductEtiketlyScoreUnavailableStage {
  /// A. No trusted scoring evidence exists for this product yet.
  noTrustedEvidence,

  /// B. Evidence exists but scoring readiness is incomplete.
  evidenceIncompleteReadiness,

  /// C. Evidence exists and a score can be calculated, but no current
  /// matching audit snapshot is available to publish yet.
  auditNotCurrent,
}

class ProductEtiketlyScoreState {
  const ProductEtiketlyScoreState._({
    required this.status,
    this.displayScore,
    this.qualityLabel,
    this.band,
    this.nutritionDisplayScore,
    this.additiveDisplayScore,
    this.nutritionSummary,
    this.nutritionAttentionPoints = const [],
    this.additiveSummary,
    this.hasBeverageNnsOverlap = false,
    this.message,
    this.reasons = const [],
    this.scoreVersion,
    this.unavailableStage,
  });

  const ProductEtiketlyScoreState.loading()
    : this._(status: ProductEtiketlyScoreStatus.loading);

  const ProductEtiketlyScoreState.error()
    : this._(
        status: ProductEtiketlyScoreStatus.error,
        message: 'Puan şu anda hesaplanamadı.',
      );

  static const Map<ProductEtiketlyScoreUnavailableStage, String>
  _unavailableStageMessages = {
    ProductEtiketlyScoreUnavailableStage.noTrustedEvidence:
        'Bu ürün için doğrulanmış puanlama kanıtı henüz oluşturulmadı.',
    ProductEtiketlyScoreUnavailableStage.evidenceIncompleteReadiness:
        'Bu ürün için puanlama kanıtı var ama bazı bilgiler henüz doğrulanmadı.',
    ProductEtiketlyScoreUnavailableStage.auditNotCurrent:
        'Puan kaydı güncelleniyor.',
  };

  factory ProductEtiketlyScoreState.calculated({
    required int displayScore,
    required String qualityLabel,
    required EtiketlyScoreBand band,
    required int nutritionDisplayScore,
    required int additiveDisplayScore,
    required String nutritionSummary,
    required Iterable<String> nutritionAttentionPoints,
    required String additiveSummary,
    required bool hasBeverageNnsOverlap,
    required String scoreVersion,
  }) {
    return ProductEtiketlyScoreState._(
      status: ProductEtiketlyScoreStatus.calculated,
      displayScore: displayScore,
      qualityLabel: qualityLabel,
      band: band,
      nutritionDisplayScore: nutritionDisplayScore,
      additiveDisplayScore: additiveDisplayScore,
      nutritionSummary: nutritionSummary,
      nutritionAttentionPoints: List.unmodifiable(nutritionAttentionPoints),
      additiveSummary: additiveSummary,
      hasBeverageNnsOverlap: hasBeverageNnsOverlap,
      scoreVersion: scoreVersion,
    );
  }

  factory ProductEtiketlyScoreState.unavailable({
    required Iterable<String> reasons,
    ProductEtiketlyScoreUnavailableStage stage =
        ProductEtiketlyScoreUnavailableStage.evidenceIncompleteReadiness,
  }) {
    return ProductEtiketlyScoreState._(
      status: ProductEtiketlyScoreStatus.unavailable,
      message: _unavailableStageMessages[stage],
      reasons: List.unmodifiable(reasons.take(3)),
      unavailableStage: stage,
    );
  }

  final ProductEtiketlyScoreStatus status;
  final int? displayScore;
  final String? qualityLabel;
  final EtiketlyScoreBand? band;
  final int? nutritionDisplayScore;
  final int? additiveDisplayScore;
  final String? nutritionSummary;
  final List<String> nutritionAttentionPoints;
  final String? additiveSummary;
  final bool hasBeverageNnsOverlap;
  final String? message;
  final List<String> reasons;
  final String? scoreVersion;
  final ProductEtiketlyScoreUnavailableStage? unavailableStage;

  bool get isCalculated => status == ProductEtiketlyScoreStatus.calculated;
}

class EtiketlyScorePresentationMapper {
  const EtiketlyScorePresentationMapper({
    this.blockerMapper = const PublicScoreBlockerMapper(),
  });

  final PublicScoreBlockerMapper blockerMapper;

  ProductEtiketlyScoreState fromResult(
    EtiketlyScoreResult result, {
    bool usesLegacyFallback = false,
  }) {
    if (!result.isCalculated) {
      return ProductEtiketlyScoreState.unavailable(
        reasons: blockerMapper.messagesFor(
          result.readiness,
          usesLegacyFallback: usesLegacyFallback,
        ),
        stage: usesLegacyFallback
            ? ProductEtiketlyScoreUnavailableStage.noTrustedEvidence
            : ProductEtiketlyScoreUnavailableStage.evidenceIncompleteReadiness,
      );
    }

    final displayScore = result.futureDisplayScore!;
    final band = bandForDisplayScore(displayScore);
    final additive = result.additiveQuality;
    final nutrition = result.nutritionQuality!;
    final nutritionDisplayScore = nutrition.qualityScore.round();

    return ProductEtiketlyScoreState.calculated(
      displayScore: displayScore,
      qualityLabel: labelForBand(band),
      band: band,
      nutritionDisplayScore: nutritionDisplayScore,
      additiveDisplayScore: additive.qualityScore.round(),
      nutritionSummary: _nutritionSummary(nutritionDisplayScore),
      nutritionAttentionPoints: _nutritionAttentionPoints(nutrition),
      additiveSummary: _additiveSummary(
        lowCount: additive.lowCount,
        mediumCount: additive.mediumCount,
        highCount: additive.highCount,
      ),
      hasBeverageNnsOverlap: additive.excludedForNutritionOverlapCount > 0,
      scoreVersion: result.scoreVersion,
    );
  }

  ProductEtiketlyScoreState missingCanonicalAssessment({
    bool usesLegacyFallback = false,
  }) {
    return ProductEtiketlyScoreState.unavailable(
      reasons: const ['İçerik listesi henüz tam değerlendirilememiş.'],
      stage: usesLegacyFallback
          ? ProductEtiketlyScoreUnavailableStage.noTrustedEvidence
          : ProductEtiketlyScoreUnavailableStage.evidenceIncompleteReadiness,
    );
  }

  ProductEtiketlyScoreState auditSnapshotRequired() {
    // The stage message ("Puan kaydı güncelleniyor.") is already the full,
    // specific explanation for this state — no separate reason bullet is
    // needed, and repeating it would render the same text twice.
    return ProductEtiketlyScoreState.unavailable(
      reasons: const [],
      stage: ProductEtiketlyScoreUnavailableStage.auditNotCurrent,
    );
  }

  EtiketlyScoreBand bandForDisplayScore(int score) {
    if (score >= 85) return EtiketlyScoreBand.veryGood;
    if (score >= 70) return EtiketlyScoreBand.good;
    if (score >= 50) return EtiketlyScoreBand.medium;
    if (score >= 30) return EtiketlyScoreBand.weak;
    return EtiketlyScoreBand.veryWeak;
  }

  String labelForBand(EtiketlyScoreBand band) => switch (band) {
    EtiketlyScoreBand.veryGood => 'Çok iyi',
    EtiketlyScoreBand.good => 'İyi',
    EtiketlyScoreBand.medium => 'Orta',
    EtiketlyScoreBand.weak => 'Zayıf',
    EtiketlyScoreBand.veryWeak => 'Çok zayıf',
  };

  String _nutritionSummary(int displayScore) {
    final label = labelForBand(bandForDisplayScore(displayScore)).toLowerCase();
    return '100 g / 100 ml temelindeki beslenme profili $label düzeydedir.';
  }

  List<String> _nutritionAttentionPoints(
    NutritionQualityResult nutritionQuality,
  ) {
    final negative = nutritionQuality.rawResult.negativePoints;
    if (negative == null) return const [];

    return [
      if (negative.saltPoints >= 10)
        'Tuz, beslenme bileşenini belirgin biçimde düşüren bir dikkat noktasıdır.',
      if (negative.sugarsPoints >= 8)
        'Şeker, beslenme bileşenini belirgin biçimde düşüren bir dikkat noktasıdır.',
      if (negative.saturatedFatPoints >= 7 ||
          negative.saturatedEnergyPoints >= 7 ||
          negative.saturatedFatRatioPoints >= 7)
        'Doymuş yağ, beslenme bileşenini belirgin biçimde düşüren bir dikkat noktasıdır.',
    ];
  }

  String _additiveSummary({
    required int lowCount,
    required int mediumCount,
    required int highCount,
  }) {
    final total = lowCount + mediumCount + highCount;
    if (total == 0) {
      return 'Etiketly katkı değerlendirmesi: puanlamaya dahil edilen katkı bulunmadı.';
    }

    final counts = <String>[
      if (highCount > 0) '$highCount yüksek',
      if (mediumCount > 0) '$mediumCount orta',
      if (lowCount > 0) '$lowCount düşük',
    ];
    return 'Etiketly katkı değerlendirmesi: ${counts.join(', ')} düzey.';
  }
}

class PublicScoreBlockerMapper {
  const PublicScoreBlockerMapper();

  List<String> messagesFor(
    EtiketlyScoreReadinessResult readiness, {
    bool usesLegacyFallback = false,
  }) {
    if (usesLegacyFallback) {
      return _legacyFallbackMessages(readiness);
    }

    final messages = <String>{};
    final nutritionBlockers = readiness.nutritionReadiness.blockingReasons;

    if (nutritionBlockers.any(_isBasisBlocker)) {
      messages.add('Besin değerlerinin 100 g / 100 ml temeli doğrulanmamış.');
    }
    if (nutritionBlockers.contains(ScoringReadinessBlocker.missingFiber)) {
      messages.add('Lif bilgisi eksik.');
    }
    if (nutritionBlockers.any(_isMissingNutritionBlocker)) {
      messages.add('Gerekli besin değerleri eksik veya doğrulanmamış.');
    }
    if (nutritionBlockers.any(_isCategoryBlocker)) {
      messages.add('Ürünün puanlama kategorisi henüz doğrulanmamış.');
    }
    if (nutritionBlockers.contains(
      ScoringReadinessBlocker.unknownProductState,
    )) {
      messages.add('Ürünün değerlendirme durumu henüz doğrulanmamış.');
    }
    if (nutritionBlockers.any(_isCompositionBlocker)) {
      messages.add('Gerekli içerik bileşimi bilgileri doğrulanmamış.');
    }
    if (readiness.blockingReasons.contains(
          EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete,
        ) ||
        nutritionBlockers.contains(
          ScoringReadinessBlocker.incompleteIngredientEvidence,
        )) {
      messages.add('İçerik listesi tam doğrulanmamış.');
    }
    if (readiness.blockingReasons.any(_isAdditiveBlocker)) {
      messages.add('Bazı katkı maddeleri henüz doğrulanmamış.');
    }
    if (messages.isEmpty) {
      messages.add('Gerekli puanlama bilgileri henüz doğrulanmamış.');
    }

    return List.unmodifiable(messages.take(3));
  }

  List<String> _legacyFallbackMessages(EtiketlyScoreReadinessResult readiness) {
    final messages = <String>{};
    final nutritionBlockers = readiness.nutritionReadiness.blockingReasons;

    // Basis, category, state, provenance and composition values are unknown in
    // ProductScoringInputAdapter's legacy fallback by construction. Presenting
    // those placeholders as proven product defects is misleading; retain only
    // blockers established directly from current product/canonical data.
    if (readiness.blockingReasons.any(_isAdditiveBlocker)) {
      messages.add('Bazı katkı maddeleri henüz doğrulanmamış.');
    }
    if (nutritionBlockers.contains(ScoringReadinessBlocker.missingFiber)) {
      messages.add('Lif bilgisi eksik.');
    }
    if (nutritionBlockers.any(_isMissingDeclaredNutritionValue)) {
      messages.add('Gerekli besin değerleri eksik.');
    }
    if (messages.isEmpty) {
      messages.add('Gerekli puanlama kanıtları henüz tamamlanmamış.');
    }
    return List.unmodifiable(messages.take(3));
  }

  bool _isBasisBlocker(ScoringReadinessBlocker blocker) => switch (blocker) {
    ScoringReadinessBlocker.unknownNutritionBasis ||
    ScoringReadinessBlocker.unsupportedPerServingOnly ||
    ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory => true,
    _ => false,
  };

  bool _isMissingNutritionBlocker(ScoringReadinessBlocker blocker) =>
      switch (blocker) {
        ScoringReadinessBlocker.missingEnergyKj ||
        ScoringReadinessBlocker.energyKjNotDeclared ||
        ScoringReadinessBlocker.missingTotalFatForFatCategory ||
        ScoringReadinessBlocker.missingSaturatedFat ||
        ScoringReadinessBlocker.missingSugars ||
        ScoringReadinessBlocker.missingSalt ||
        ScoringReadinessBlocker.missingProtein ||
        ScoringReadinessBlocker.unknownNutritionProvenance ||
        ScoringReadinessBlocker.invalidEvidenceValue ||
        ScoringReadinessBlocker.rejectedEvidence => true,
        _ => false,
      };

  bool _isMissingDeclaredNutritionValue(ScoringReadinessBlocker blocker) =>
      switch (blocker) {
        ScoringReadinessBlocker.missingEnergyKj ||
        ScoringReadinessBlocker.energyKjNotDeclared ||
        ScoringReadinessBlocker.missingTotalFatForFatCategory ||
        ScoringReadinessBlocker.missingSaturatedFat ||
        ScoringReadinessBlocker.missingSugars ||
        ScoringReadinessBlocker.missingSalt ||
        ScoringReadinessBlocker.missingProtein => true,
        _ => false,
      };

  bool _isCategoryBlocker(ScoringReadinessBlocker blocker) => switch (blocker) {
    ScoringReadinessBlocker.unknownScoringCategory ||
    ScoringReadinessBlocker.conflictingCategoryEvidence ||
    ScoringReadinessBlocker.redMeatEvidenceIncomplete ||
    ScoringReadinessBlocker.nutSeedPercentageUnknown ||
    ScoringReadinessBlocker.cheeseEvidenceIncomplete ||
    ScoringReadinessBlocker.outOfScopeProduct => true,
    _ => false,
  };

  bool _isCompositionBlocker(ScoringReadinessBlocker blocker) =>
      switch (blocker) {
        ScoringReadinessBlocker.unknownFvlPercentage ||
        ScoringReadinessBlocker.unknownNnsPresence ||
        ScoringReadinessBlocker.unknownCompositionEvidenceProvenance ||
        ScoringReadinessBlocker.unknownNnsEvidenceProvenance => true,
        _ => false,
      };

  bool _isAdditiveBlocker(EtiketlyScoreReadinessBlocker blocker) =>
      switch (blocker) {
        EtiketlyScoreReadinessBlocker.unresolvedIngredientEvidence ||
        EtiketlyScoreReadinessBlocker.reviewRequiredAdditiveEvidence ||
        EtiketlyScoreReadinessBlocker.additiveRiskConflict ||
        EtiketlyScoreReadinessBlocker.unknownAdditiveRisk ||
        EtiketlyScoreReadinessBlocker.additiveAssessmentIncomplete => true,
        _ => false,
      };
}
