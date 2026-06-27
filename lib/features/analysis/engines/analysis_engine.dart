import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/models/product_context.dart';
import 'package:food_analyzer_app/features/analysis/services/unknown_ingredient_sanitizer.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

/// Analysis engine: deterministic, rule-based product evaluation
class AnalysisEngine {
  const AnalysisEngine();

  ProductAnalysisResult analyze(
    IngredientMatchingResult matchingResult, {
    String? category,
    ProductContext? productContext,
  }) {
    final matched = matchingResult.getConfirmedMatches();
    final reviewRequired = matchingResult.getLowConfidenceMatches();
    final unmatched = matchingResult.getUnmatched();

    // Risk-first detection from ingredient tokens
    final riskSignals = <String, int>{};
    final processingSignals = <String>{};
    final sugarSaltFat = <String>{};

    final List<Ingredient> highRisk = <Ingredient>[];
    final List<Ingredient> mediumRisk = <Ingredient>[];
    final List<Ingredient> recognizedIngredients = <Ingredient>[];
    final List<Ingredient> otherRecognizedIngredients = <Ingredient>[];
    final Set<String> recognizedIds = <String>{};
    final Map<String, int> originalOrder = <String, int>{};
    final Set<String> signaledIngredientIds = <String>{};
    final Set<String> firstThreeSignalIngredientIds = <String>{};

    for (var i = 0; i < matched.length; i++) {
      final m = matched[i];
      final matchedIngredient = m.matchedIngredient;
      if (matchedIngredient != null &&
          recognizedIds.add(matchedIngredient.id)) {
        recognizedIngredients.add(matchedIngredient);
        originalOrder[matchedIngredient.id] = i;
      }

      final isFirstThree = i < 3;

      void markSignalForIngredient(Ingredient? ingredient) {
        if (ingredient == null) return;
        signaledIngredientIds.add(ingredient.id);
        if (isFirstThree) {
          firstThreeSignalIngredientIds.add(ingredient.id);
        }
      }

      final name = m.normalizedText.toLowerCase();
      final canonical = (m.matchedIngredient?.normalizedName ?? '')
          .toLowerCase();

      // helper to add signal
      void addSignal(String key) =>
          riskSignals[key] = (riskSignals[key] ?? 0) + 1;

      // low_quality_oil
      if (name.contains('palm') ||
          canonical.contains('palm yağı') ||
          name.contains('hydrogenated') ||
          name.contains('trans')) {
        addSignal('low_quality_oil');
        processingSignals.add('hydrogenated_oil');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!highRisk.any((i) => i.id == ing.id)) highRisk.add(ing);
        }
      }

      // nitrite / processed meat additive
      if (name.contains('nitrit') ||
          name.contains('nitrat') ||
          canonical.contains('sodyum nitrit')) {
        addSignal('processed_meat_additive');
        addSignal('preservative');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!highRisk.any((i) => i.id == ing.id)) highRisk.add(ing);
        }
      }

      // benzoat / sorbat etc
      if (name.contains('benzoat') ||
          name.contains('sorbat') ||
          name.contains('potasyum sorbat') ||
          name.contains('sodyum benzoat')) {
        addSignal('preservative');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // artificial sweeteners
      if (name.contains('aspartam') ||
          name.contains('acesülfam') ||
          name.contains('asesülfam') ||
          name.contains('sukraloz') ||
          name.contains('sukralose')) {
        addSignal('artificial_sweetener');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // caffeine/taurine
      if (name.contains('kafein') || name.contains('taurin')) {
        addSignal('caffeine_stimulant');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!highRisk.any((i) => i.id == ing.id)) highRisk.add(ing);
        }
      }

      // artificial colors
      if (name.contains('tartrazin') ||
          canonical.contains('tartrazin') ||
          name.contains('e102') ||
          canonical.contains('e102')) {
        addSignal('artificial_color');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!highRisk.any((i) => i.id == ing.id)) highRisk.add(ing);
        }
      }

      // emulsifiers
      if (name.contains('mono ve digliserit') ||
          name.contains('lesitin') ||
          name.contains('emülgatör')) {
        addSignal('emulsifier');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // flavoring
      if (name.contains('aroma') || name.contains('flavor')) {
        addSignal('flavoring');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // sugar syrups and maltodextrin
      if (name.contains('glikoz') ||
          name.contains('glucose') ||
          name.contains('şurup') ||
          name.contains('fruktoz') ||
          name.contains('glikoz şurubu') ||
          name.contains('maltodekstrin') ||
          name.contains('malt ekstrakt') ||
          name.contains('şeker')) {
        addSignal('sugar_syrup');
        sugarSaltFat.add('sugar');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // modified starch
      if (name.contains('modifiye') ||
          name.contains('modifiye nişasta') ||
          name.contains('modified starch')) {
        addSignal('modified_starch');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // phosphate
      if (name.contains('fosfat') || name.contains('phosphate')) {
        addSignal('phosphate');
        if (m.matchedIngredient != null) {
          final ing = m.matchedIngredient!;
          markSignalForIngredient(ing);
          if (!mediumRisk.any((i) => i.id == ing.id)) mediumRisk.add(ing);
        }
      }

      // high salt (salt indicators)
      if (name.contains('tuz') || name.contains('sodyum')) {
        if (!name.contains('sitrat') && !name.contains('citrat')) {
          addSignal('high_salt_signal');
        }
        sugarSaltFat.add('salt');
      }

      if (name.contains('sitrat') || name.contains('citrat')) {
        addSignal('acidity_regulator');
      }

      // ultra-processed markers
      if (name.contains('aroma ver') ||
          name.contains('emülgatör') ||
          name.contains('antioksidan') ||
          name.contains('mono ve digliserit')) {
        addSignal('ultra_processed_marker');
        processingSignals.add(name);
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
