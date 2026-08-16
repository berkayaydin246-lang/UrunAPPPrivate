import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

abstract final class ScoringReadinessPresentation {
  static List<String> blockerLabels(ScoringReadinessResult readiness) =>
      readiness.blockingReasons.map(blockerLabel).toList(growable: false);

  static String blockerLabel(ScoringReadinessBlocker blocker) =>
      switch (blocker) {
        ScoringReadinessBlocker.unknownNutritionBasis =>
          'Besin değerlerinin 100 g / 100 ml temeli doğrulanmadı.',
        ScoringReadinessBlocker.unsupportedPerServingOnly =>
          'Yalnızca porsiyon başına değerler puanlama için yeterli değil.',
        ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory =>
          'Besin değeri temeli seçilen ürün sınıfıyla uyuşmuyor.',
        ScoringReadinessBlocker.unknownProductState =>
          'Ürünün satıldığı veya hazırlanmış hali doğrulanmadı.',
        ScoringReadinessBlocker.unknownScoringCategory =>
          'Ürün sınıfı doğrulanmadı.',
        ScoringReadinessBlocker.conflictingCategoryEvidence =>
          'Ürün sınıfı kanıtları birbiriyle çelişiyor.',
        ScoringReadinessBlocker.redMeatEvidenceIncomplete =>
          'Kırmızı et oranı ve ana bileşen bilgisi eksik.',
        ScoringReadinessBlocker.nutSeedPercentageUnknown =>
          'Kuruyemiş/tohum oranı doğrulanmadı.',
        ScoringReadinessBlocker.cheeseEvidenceIncomplete =>
          'Peynir sınıfının dışlama bilgileri doğrulanmadı.',
        ScoringReadinessBlocker.outOfScopeProduct =>
          'Bu ürün puanlama kapsamı dışında.',
        ScoringReadinessBlocker.missingEnergyKj => 'Enerji (kJ) eksik.',
        ScoringReadinessBlocker.energyKjNotDeclared =>
          'Enerji (kJ) etiketten doğrulanmadı.',
        ScoringReadinessBlocker.missingTotalFatForFatCategory =>
          'Toplam yağ bilgisi eksik.',
        ScoringReadinessBlocker.missingSaturatedFat =>
          'Doymuş yağ bilgisi eksik.',
        ScoringReadinessBlocker.missingSugars => 'Şeker bilgisi eksik.',
        ScoringReadinessBlocker.missingSalt => 'Tuz bilgisi eksik.',
        ScoringReadinessBlocker.missingProtein => 'Protein bilgisi eksik.',
        ScoringReadinessBlocker.missingFiber => 'Lif bilgisi eksik.',
        ScoringReadinessBlocker.unknownFvlPercentage => 'FVL oranı bilinmiyor.',
        ScoringReadinessBlocker.unknownNnsPresence =>
          'Tatlandırıcı durumu doğrulanmadı.',
        ScoringReadinessBlocker.incompleteIngredientEvidence =>
          'İçerik listesinin tamlığı doğrulanmadı.',
        ScoringReadinessBlocker.unknownNutritionProvenance =>
          'Besin değerlerinin kaynağı doğrulanmadı.',
        ScoringReadinessBlocker.unknownCompositionEvidenceProvenance =>
          'FVL bilgisinin kaynağı doğrulanmadı.',
        ScoringReadinessBlocker.unknownNnsEvidenceProvenance =>
          'Tatlandırıcı bilgisinin kaynağı doğrulanmadı.',
        ScoringReadinessBlocker.invalidEvidenceValue =>
          'Puanlama verilerinden biri geçersiz.',
        ScoringReadinessBlocker.rejectedEvidence =>
          'Reddedilmiş bir kanıt yeniden incelenmeli.',
        ScoringReadinessBlocker.saturatedFatExceedsTotalFat =>
          'Doymuş yağ, toplam yağdan fazla görünüyor.',
        ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory =>
          'Bu ürün sınıfı için toplam yağ sıfır veya eksi görünüyor.',
        ScoringReadinessBlocker.plainWaterCategoryMismatch =>
          'Ürün sade su olarak görünüyor ancak içecek sınıfında değil.',
      };
}
