import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/models/product_context.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/unknown_ingredient_sanitizer.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Analysis engine: deterministic, rule-based product evaluation
class AnalysisEngine {
  const AnalysisEngine({
    CanonicalIngredientRiskService riskService =
        const CanonicalIngredientRiskService(),
  }) : _riskService = riskService;

  final CanonicalIngredientRiskService _riskService;

  ProductAnalysisResult analyze(
    IngredientMatchingResult matchingResult, {
    String? category,
    ProductContext? productContext,
    ScoringCategory scoringCategory = ScoringCategory.unknown,
  }) {
    final additiveAssessment = _riskService.assess(
      matchingResult,
      scoringCategory: scoringCategory,
    );
    final matchedItems = additiveAssessment.recognizedIngredients
        .where((item) => item.affectsCurrentAnalysis)
        .toList(growable: false);
    final matched = matchingResult.getConfirmedMatches();
    final reviewRequired = matchingResult.getLowConfidenceMatches();
    final unmatched = matchingResult.getUnmatched();

    final riskSignals = <String, int>{};
    final processingSignals = <String>{};
    final sugarSaltFat = <String>{};

    final highRisk = matchedItems
        .where((item) => item.riskLevel == CanonicalRiskLevel.high)
        .map((item) => item.ingredient)
        .toList(growable: false);
    final mediumRisk = matchedItems
        .where((item) => item.riskLevel == CanonicalRiskLevel.medium)
        .map((item) => item.ingredient)
        .toList(growable: false);
    final recognizedIngredients = matchedItems
        .map((item) => item.ingredient)
        .toList(growable: false);
    final List<Ingredient> otherRecognizedIngredients = <Ingredient>[];
    final Map<String, int> originalOrder = <String, int>{};
    final Set<String> signaledIngredientIds = <String>{};
    final Set<String> firstThreeSignalIngredientIds = <String>{};

    for (var i = 0; i < matchedItems.length; i++) {
      final item = matchedItems[i];
      final ingredient = item.ingredient;
      originalOrder[ingredient.id] = i;
      final isFirstThree = i < 3;

      void markSignalForIngredient() {
        signaledIngredientIds.add(ingredient.id);
        if (isFirstThree) {
          firstThreeSignalIngredientIds.add(ingredient.id);
        }
      }

      final evidenceText = <String>[
        ingredient.name,
        ingredient.normalizedName,
        if (ingredient.eCode != null) ingredient.eCode!,
        ...item.sourceTokens,
      ].join(' ').toLowerCase();

      bool containsAny(Iterable<String> values) =>
          values.any(evidenceText.contains);

      void addSignal(String key) =>
          riskSignals[key] = (riskSignals[key] ?? 0) + 1;

      if (containsAny(['palm', 'hydrogenated', 'hidrojenize', 'trans'])) {
        addSignal('low_quality_oil');
        processingSignals.add('hydrogenated_oil');
        markSignalForIngredient();
      }

      if (containsAny(['nitrit', 'nitrat', 'e250', 'e251', 'e249', 'e252'])) {
        addSignal('processed_meat_additive');
        addSignal('preservative');
        markSignalForIngredient();
      }

      if (containsAny(['benzoat', 'sorbat', 'benzoik asit', 'sorbik asit'])) {
        addSignal('preservative');
        markSignalForIngredient();
      }

      if (containsAny([
        'aspartam',
        'acesülfam',
        'asesülfam',
        'sukraloz',
        'sucralose',
        'sakarin',
        'siklamat',
      ])) {
        addSignal('artificial_sweetener');
        markSignalForIngredient();
      }

      if (containsAny(['kafein', 'taurin'])) {
        addSignal('caffeine_stimulant');
        markSignalForIngredient();
      }

      if (containsAny([
        'tartrazin',
        'e102',
        'allura red',
        'e129',
        'sunset yellow',
        'e110',
        'brilliant blue',
        'e133',
        'karmin',
        'e120',
      ])) {
        addSignal('artificial_color');
        markSignalForIngredient();
      }

      if (containsAny(['mono ve digliserit', 'lesitin', 'emülgatör'])) {
        addSignal('emulsifier');
        markSignalForIngredient();
      }

      if (containsAny(['aroma', 'flavor'])) {
        addSignal('flavoring');
        markSignalForIngredient();
      }

      if (containsAny([
        'glikoz',
        'glucose',
        'şurup',
        'fruktoz',
        'maltodekstrin',
        'malt ekstrakt',
        'şeker',
      ])) {
        addSignal('sugar_syrup');
        sugarSaltFat.add('sugar');
        markSignalForIngredient();
      }

      if (containsAny(['modifiye', 'modified starch'])) {
        addSignal('modified_starch');
        markSignalForIngredient();
      }

      if (containsAny(['fosfat', 'phosphate'])) {
        addSignal('phosphate');
        markSignalForIngredient();
      }

      if (containsAny(['tuz', 'sodyum'])) {
        if (!containsAny(['sitrat', 'citrat'])) {
          addSignal('high_salt_signal');
        }
        sugarSaltFat.add('salt');
      }

      if (containsAny(['sitrat', 'citrat'])) {
        addSignal('acidity_regulator');
      }

      if (containsAny([
        'aroma ver',
        'emülgatör',
        'antioksidan',
        'mono ve digliserit',
      ])) {
        addSignal('ultra_processed_marker');
        processingSignals.add(ingredient.normalizedName);
      }
    }

    for (final ingredient in recognizedIngredients) {
      final isRisky =
          highRisk.any((item) => item.id == ingredient.id) ||
          mediumRisk.any((item) => item.id == ingredient.id);
      if (!isRisky) {
        otherRecognizedIngredients.add(ingredient);
      }
    }

    final List<Ingredient> sortedRiskIngredients = _sortImportantIngredients(
      highRisk: highRisk,
      mediumRisk: mediumRisk,
      originalOrder: originalOrder,
      signaledIngredientIds: signaledIngredientIds,
      firstThreeSignalIngredientIds: firstThreeSignalIngredientIds,
    );

    // summary booleans
    final containsNitrite = riskSignals.containsKey('processed_meat_additive');
    final containsHighSugar = riskSignals.containsKey('sugar_syrup');

    // Simple dairy heuristic
    final isSimpleYogurt =
        (category != null &&
            (category.toLowerCase().contains('yogurt') ||
                category.toLowerCase().contains('yoğurt'))) &&
        matched.every((m) {
          final n = m.normalizedText;
          return n.contains('süt') ||
              n.contains('kultur') ||
              n.contains('kulturler') ||
              n.contains('yoğurt') ||
              n.contains('mayalama');
        });

    // Processed meat heuristic - prefer productContext if reliable
    final isProcessedMeat =
        (productContext != null &&
            productContext.isReliable &&
            productContext.productType == 'processed_meat') ||
        (category != null &&
            (category.toLowerCase().contains('processed') ||
                category.toLowerCase().contains('işlenmiş') ||
                category.toLowerCase().contains('et')));

    // Decide score
    AnalysisScoreLabel score = AnalysisScoreLabel.iyiSecim;

    if (highRisk.length >= 2) {
      score = AnalysisScoreLabel.sikTuketme;
    } else if (highRisk.length == 1) {
      score = AnalysisScoreLabel.dikkatliTuket;
    }

    if (containsHighSugar &&
        score.index < AnalysisScoreLabel.dikkatliTuket.index) {
      score = AnalysisScoreLabel.dikkatliTuket;
    }

    if (isProcessedMeat &&
        score.index < AnalysisScoreLabel.dikkatliTuket.index) {
      score = AnalysisScoreLabel.dikkatliTuket;
    }

    if (isSimpleYogurt && score == AnalysisScoreLabel.iyiSecim) {
      score = AnalysisScoreLabel.iyiSecim;
    }

    if (score == AnalysisScoreLabel.iyiSecim && mediumRisk.isNotEmpty) {
      score = AnalysisScoreLabel.orta;
    }

    // Build messages
    final summary = _buildSummary(
      score,
      highRisk,
      mediumRisk,
      containsHighSugar,
      isProcessedMeat,
      isSimpleYogurt,
    );

    final List<String> positive = [];
    final List<String> negative = [];

    if (isSimpleYogurt) {
      positive.add('Sade yoğurt içeriği');
    }
    if (containsHighSugar) {
      negative.add('Yüksek şeker / şurup içeriği tespit edildi');
    }
    if (containsNitrite) {
      negative.add('Nitrit / nitrata işaret eden içerik bulundu');
    }
    if (highRisk.isNotEmpty) {
      negative.add('${highRisk.length} adet yüksek riskli içerik');
    }
    if (mediumRisk.isNotEmpty) {
      negative.add('${mediumRisk.length} adet orta riskli içerik');
    }

    final String advice = _buildAdvice(score, isProcessedMeat, containsNitrite);

    // optional context note
    String? contextNote;
    if (productContext != null && productContext.isReliable) {
      if (containsNitrite && productContext.productType == 'processed_meat') {
        contextNote =
            'İşlenmiş et ürünlerinde bu katkı daha önemli bir dikkat sinyalidir.';
      }
      if ((riskSignals['caffeine_stimulant'] ?? 0) > 0 &&
          productContext.productType == 'energy_drink') {
        contextNote =
            'Enerji içeceklerinde kafein hassasiyeti olanlar, çocuklar ve gebeler için dikkat önerilir.';
      }
      if ((riskSignals['sugar_syrup'] ?? 0) > 0 &&
          (riskSignals['low_quality_oil'] ?? 0) > 0 &&
          productContext.productType == 'chocolate_spread') {
        contextNote =
            'Bu tür ürünlerde şeker ve yağ oranı tüketim sıklığı açısından önemlidir.';
      }
    }

    return ProductAnalysisResult(
      scoreLabel: score,
      summary: summary,
      warningText: (highRisk.isNotEmpty || containsHighSugar)
          ? 'Dikkat: bazı içerikler sağlık açısından risk taşıyabilir.'
          : null,
      positivePoints: positive,
      negativePoints: negative,
      consumptionAdvice: advice,
      detectedRiskIngredients: sortedRiskIngredients,
      recognizedIngredients: recognizedIngredients,
      otherRecognizedIngredients: otherRecognizedIngredients,
      reviewRequiredMatches: reviewRequired,
      unknownIngredients: UnknownIngredientSanitizer.sanitizeUnknownIngredients(
        rawUnknowns: unmatched.map((m) => m.originalToken).toList(),
        matches: matchingResult.matches,
      ),
      riskSignals: riskSignals,
      processingSignals: processingSignals.toList(growable: false),
      sugarSaltFatSignals: sugarSaltFat.toList(growable: false),
      productContextNote: contextNote,
      productContext: productContext,
      additiveAssessment: additiveAssessment,
    );
  }

  List<Ingredient> _sortImportantIngredients({
    required List<Ingredient> highRisk,
    required List<Ingredient> mediumRisk,
    required Map<String, int> originalOrder,
    required Set<String> signaledIngredientIds,
    required Set<String> firstThreeSignalIngredientIds,
  }) {
    final merged = <Ingredient>[];
    final seen = <String>{};

    for (final ingredient in [...highRisk, ...mediumRisk]) {
      if (seen.add(ingredient.id)) {
        merged.add(ingredient);
      }
    }

    int riskWeight(String level) {
      switch (level) {
        case 'high':
          return 3;
        case 'medium':
          return 2;
        case 'low':
          return 1;
        default:
          return 0;
      }
    }

    // priority_score is not available in the current Ingredient model,
    // so this keeps deterministic ordering while leaving a stable placeholder.
    const int unavailablePriority = 0;

    merged.sort((a, b) {
      final byRisk = riskWeight(b.riskLevel).compareTo(riskWeight(a.riskLevel));
      if (byRisk != 0) return byRisk;

      final byPriority = unavailablePriority.compareTo(unavailablePriority);
      if (byPriority != 0) return byPriority;

      final byFirstThree =
          (firstThreeSignalIngredientIds.contains(b.id) ? 1 : 0).compareTo(
            firstThreeSignalIngredientIds.contains(a.id) ? 1 : 0,
          );
      if (byFirstThree != 0) return byFirstThree;

      final byAnySignal = (signaledIngredientIds.contains(b.id) ? 1 : 0)
          .compareTo(signaledIngredientIds.contains(a.id) ? 1 : 0);
      if (byAnySignal != 0) return byAnySignal;

      return (originalOrder[a.id] ?? 9999).compareTo(
        originalOrder[b.id] ?? 9999,
      );
    });

    return merged;
  }

  String _buildSummary(
    AnalysisScoreLabel score,
    List<Ingredient> highRisk,
    List<Ingredient> mediumRisk,
    bool highSugar,
    bool processedMeat,
    bool simpleYogurt,
  ) {
    switch (score) {
      case AnalysisScoreLabel.iyiSecim:
        return simpleYogurt
            ? 'İçerikler basit ve beklendiği gibi.'
            : 'Genel olarak kabul edilebilir bir içerik listesi.';
      case AnalysisScoreLabel.orta:
        return 'Orta düzeyde dikkat gerektiren içerikler var.';
      case AnalysisScoreLabel.dikkatliTuket:
        return 'Dikkatli olunması önerilir; bazı içerikler risk oluşturabilir.';
      case AnalysisScoreLabel.sikTuketme:
        return 'Bu ürün sık tüketim için uygun olmayabilir.';
    }
  }

  String _buildAdvice(
    AnalysisScoreLabel score,
    bool isProcessedMeat,
    bool containsNitrite,
  ) {
    if (score == AnalysisScoreLabel.sikTuketme) {
      return 'Sık tüketimde dikkatli değerlendirilmelidir; ürünün tamamı, porsiyon miktarı ve tüketim sıklığı birlikte düşünülmelidir.';
    }
    if (isProcessedMeat && containsNitrite) {
      return 'İşlenmiş et ve nitrit birlikte yer alıyorsa, tüketim sıklığı ve porsiyon miktarı birlikte değerlendirilmelidir.';
    }
    if (score == AnalysisScoreLabel.dikkatliTuket) {
      return 'Tüketim sıklığı değerlendirilirken ürünün içeriği ve porsiyon miktarı birlikte düşünülebilir.';
    }
    return 'Analiz yalnızca net eşleşen içeriklere göre yapılır. Etiketleri kontrol etmeye devam edin.';
  }
}
