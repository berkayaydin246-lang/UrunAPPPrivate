import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/widgets/salt_shaker_icon.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/widgets/ingredient_detail_sections.dart';
import 'package:food_analyzer_app/features/product/widgets/product_detail_shared.dart';

String confidenceToLabel(double score) {
  if (score >= 0.7) return 'Orta güven';
  return 'Düşük güven';
}

Color confidenceToColor(double score) {
  if (score >= 0.7) return Colors.orange[700]!;
  return Colors.deepOrange[700]!;
}

/// Controls which UI elements are shown in [AnalysisResultWidget].
///
/// - [ocr]: OCR-scanned ingredients. Shows uncertain-match confirmation UI.
/// - [barcode]: Product looked up from database / Open Food Facts.
///   Hides OCR-specific UI; uses database-appropriate banner and advice.
enum AnalysisDisplayMode { ocr, barcode }

// Additive-type signals that warrant a "katkı/tatlandırıcı" note.
// Excludes benign signals like high_salt_signal and acidity_regulator.
const _additiveSignals = {
  'preservative',
  'artificial_sweetener',
  'emulsifier',
  'flavoring',
  'ultra_processed_marker',
  'modified_starch',
  'phosphate',
  'low_quality_oil',
  'processed_meat_additive',
  'caffeine_stimulant',
  'sugar_syrup',
};

/// Returns deterministic consumption notes for a barcode product.
///
/// Returns an empty list when there is nothing meaningful to say.
/// Each entry is a standalone sentence suitable for display.
List<String> buildConsumptionNotes(
  ProductAnalysisResult result,
  NutritionData? nutrition,
) {
  final notes = <String>[];

  final hasHigh = result.detectedRiskIngredients.any(
    (i) => i.riskLevel == 'high',
  );
  final hasAdditiveSignal = result.riskSignals.keys.any(
    _additiveSignals.contains,
  );

  if (hasHigh) {
    notes.add(
      'Öne çıkan içerikler nedeniyle düzenli tüketimde dikkat edilebilir.',
    );
  } else if (hasAdditiveSignal) {
    notes.add(
      'Katkı, tatlandırıcı veya işlenmişlik sinyalleri içerdiği için '
      'tüketim sıklığını sınırlamak iyi olabilir.',
    );
  }

  if (nutrition != null) {
    if (nutrition.sugars != null && nutrition.sugars! > 22.5) {
      notes.add(
        'Şeker değeri yüksek görünüyor; tüketim sıklığına dikkat edilebilir.',
      );
    }
    if (nutrition.salt != null && nutrition.salt! > 1.5) {
      notes.add(
        'Tuz değeri yüksek görünüyor; porsiyon miktarına dikkat edilebilir.',
      );
    }
    if (nutrition.saturatedFat != null && nutrition.saturatedFat! > 5.0) {
      notes.add(
        'Doymuş yağ değeri yüksek görünüyor; tüketim sıklığına dikkat edilebilir.',
      );
    }
  }

  // Positive nutrition signals
  if (nutrition != null) {
    if (nutrition.fiber != null && nutrition.fiber! >= 6.0) {
      notes.add(
        'Lif içeriği yüksek; sindirim sağlığına olumlu katkı sağlayabilir.',
      );
    } else if (nutrition.fiber != null && nutrition.fiber! >= 3.0) {
      notes.add('İyi bir lif kaynağı olarak değerlendirilebilir.');
    }
    if (nutrition.proteins != null && nutrition.proteins! >= 12.0) {
      notes.add(
        'Protein değeri yüksek görünüyor; dengeli beslenme açısından olumlu.',
      );
    }
  }

  final hasAnyIngredients = result.recognizedIngredients.isNotEmpty;
  final hasAnyNutrition = nutrition?.hasAnyData ?? false;

  if (notes.isEmpty && (hasAnyIngredients || hasAnyNutrition)) {
    notes.add(
      'Belirgin yüksek dikkat sinyali tespit edilmedi; yine de porsiyon '
      've tüketim sıklığı önemlidir.',
    );
  }

  return notes;
}

class AnalysisResultWidget extends StatelessWidget {
  final ProductAnalysisResult result;
  final void Function(String originalToken, bool approved)?
  onLowConfidenceDecision;
  final AnalysisDisplayMode displayMode;
  final NutritionData? nutritionData;

  const AnalysisResultWidget({
    super.key,
    required this.result,
    this.onLowConfidenceDecision,
    this.displayMode = AnalysisDisplayMode.ocr,
    this.nutritionData,
  });

  @override
  Widget build(BuildContext context) {
    final ingredientRows = _getIngredientRowsForDisplay();
    final productDetailSections = displayMode == AnalysisDisplayMode.barcode
        ? _splitProductDetailIngredientRows(result, ingredientRows)
        : null;
    final consumptionNote = _consumptionNote();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Source banner — wording differs by mode
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey[100]!),
          ),
          child: Text(
            _sourceBanner(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.blueGrey[900]),
          ),
        ),
        // Uncertain-match confirmation only in OCR mode
        if (displayMode == AnalysisDisplayMode.ocr &&
            result.reviewRequiredMatches.isNotEmpty) ...[
          _UncertainIngredientSection(
            items: result.reviewRequiredMatches,
            onDecision: onLowConfidenceDecision,
          ),
          const SizedBox(height: 10),
        ],
        if (displayMode == AnalysisDisplayMode.ocr &&
            ingredientRows.isNotEmpty) ...[
          _SectionCard(
            title: 'İçindekiler',
            icon: Icons.restaurant_outlined,
            accentColor: Colors.blueGrey,
            child: _UnifiedIngredientSection(
              ingredients: ingredientRows,
              defaultVisibleCount: 8,
            ),
          ),
        ],
        if (displayMode == AnalysisDisplayMode.barcode &&
            productDetailSections != null &&
            productDetailSections.attentionGroups.isNotEmpty) ...[
          _SectionCard(
            title: 'Dikkat Edilecek İçerikler',
            icon: Icons.priority_high_outlined,
            accentColor: Colors.deepOrange,
            child: _GroupedAttentionView(
              groups: productDetailSections.attentionGroups,
            ),
          ),
        ],
        if (displayMode == AnalysisDisplayMode.barcode &&
            productDetailSections != null &&
            productDetailSections.allergens.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Alerjenler',
            icon: Icons.warning_amber_outlined,
            accentColor: Colors.amber,
            child: _AllergenSection(allergens: productDetailSections.allergens),
          ),
        ],
        // "No matches" message in barcode mode when ingredients were analysed
        // but nothing was recognised in the database.
        if (displayMode == AnalysisDisplayMode.barcode &&
            productDetailSections != null &&
            productDetailSections.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              'İçindekiler metni bulundu ancak dikkat gerektiren eşleşme tespit edilmedi.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
            ),
          ),
        ],
        // Nutrition section (barcode mode only, when data is available)
        if (displayMode == AnalysisDisplayMode.barcode &&
            nutritionData != null &&
            nutritionData!.hasAnyData) ...[
          const SizedBox(height: 10),
          NutritionSectionCard(nutritionData: nutritionData!),
        ],
        if (displayMode == AnalysisDisplayMode.ocr &&
            consumptionNote.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Tüketim Notu',
            icon: Icons.tips_and_updates_outlined,
            accentColor: Colors.indigo,
            child: Text(
              consumptionNote,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
      ],
    );
  }

  String _sourceBanner() {
    switch (displayMode) {
      case AnalysisDisplayMode.barcode:
        return 'Analiz, ürün veritabanındaki içerik bilgilerine göre '
            'hazırlanmıştır. Ambalajdaki güncel etiketi kontrol edin.';
      case AnalysisDisplayMode.ocr:
        return 'Analiz, etikette tespit edilen önemli içeriklere göre '
            'hazırlanmıştır.';
    }
  }

  /// Returns the consumption note for OCR mode (barcode delegates to product_page).
  String _consumptionNote() {
    if (displayMode == AnalysisDisplayMode.barcode) return '';
    return result.consumptionAdvice;
  }

  List<_IngredientDisplayItem> _getIngredientRowsForDisplay() {
    // Combine risk ingredients + all recognized ingredients
    final combined = <String, _IngredientDisplayItem>{};
    var order = 0;

    // Add all recognized ingredients in ingredient-list order.
    for (final ing in result.recognizedIngredients) {
      combined.putIfAbsent(
        'matched:${ing.id}',
        () => _IngredientDisplayItem.fromIngredient(
          enrichIngredientKnowledge(ing),
          order++,
        ),
      );
    }

    // Add high/medium risk ingredients that may not be present above.
    for (final ing in result.detectedRiskIngredients) {
      combined.putIfAbsent(
        'matched:${ing.id}',
        () => _IngredientDisplayItem.fromIngredient(
          enrichIngredientKnowledge(ing),
          order++,
        ),
      );
    }

    // Barcode products can have useful parsed tokens that are not in the
    // ingredient table yet. Show them as deterministic display rows instead
    // of falling back to a "no matches" message.
    if (displayMode == AnalysisDisplayMode.barcode) {
      for (final token in result.unknownIngredients) {
        for (final displayToken in _expandProductDetailParsedToken(token)) {
          final item = _IngredientDisplayItem.fromParsedToken(
            displayToken,
            order++,
          );
          combined.putIfAbsent('parsed:${item.normalizedName}', () => item);
        }
      }
    }

    // Convert to list and sort
    final ingredients = displayMode == AnalysisDisplayMode.barcode
        ? _filterProductDetailIngredientRows(combined.values.toList())
        : combined.values.toList();
    return _sortByRiskAndOrder(ingredients);
  }

  List<_IngredientDisplayItem> _sortByRiskAndOrder(
    List<_IngredientDisplayItem> ingredients,
  ) {
    final sorted = [...ingredients];
    int weight(String level) {
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

    sorted.sort((a, b) {
      final byRisk = weight(b.riskLevel).compareTo(weight(a.riskLevel));
      if (byRisk != 0) return byRisk;
      return a.originalOrder.compareTo(b.originalOrder);
    });
    return sorted;
  }
}

/// Filters raw display rows for the product-detail (barcode) path: drops noise,
/// description fragments, generic functional/food-group labels, and the generic
/// "bitkisel yağ" group when a specific oil is present. Friendly naming,
/// grouping and dedup happen later in [_splitProductDetailIngredientRows].
List<_IngredientDisplayItem> _filterProductDetailIngredientRows(
  List<_IngredientDisplayItem> items,
) {
  final dropped = <String>[];
  final standalone = <_IngredientDisplayItem>[];

  for (final item in items) {
    final reason = _dropReasonForProductDetailIngredient(item);
    if (reason != null) {
      dropped.add('${item.name}:$reason');
      continue;
    }
    standalone.add(item);
  }

  final hasSpecificOil = standalone.any(
    (item) => _isSpecificOil(_filterKey(item.normalizedName)),
  );

  final kept = <_IngredientDisplayItem>[];
  for (final item in standalone) {
    final key = _filterKey(item.normalizedName);
    if (_isGenericOilGroup(key) && hasSpecificOil) {
      dropped.add('${item.name}:generic_oil_specific_oil_present');
      continue;
    }
    kept.add(item);
  }

  _debugAnalysisResultLog(
    '[ProductDetailIngredients] kept display item count=${kept.length}',
  );
  _debugAnalysisResultLog(
    '[ProductDetailIngredients] dropped token count=${dropped.length} '
    'reason=${dropped.join(", ")}',
  );

  return kept;
}

String? _dropReasonForProductDetailIngredient(_IngredientDisplayItem item) {
  final key = _filterKey(item.normalizedName);
  if (key.length < 3) return 'too_short';
  if (_noiseTokens.contains(key)) return 'noise_token';
  if (key.startsWith('fk-')) return 'product_description_fragment';
  if (key.startsWith('içindeki:') || key.startsWith('icindeki:')) {
    return 'product_description_fragment';
  }
  if (key.contains('kakao soslu kakaolu kaplamalı bitter çikolatalı kek') ||
      key.contains('kakaolu kaplamalı bitter çikolatalı kek') ||
      key.contains('kakao kaplamalı bitter çikolatalı kek') ||
      key.contains('kakao soslu') ||
      key.contains('bitter çikolatalı kek') ||
      key.contains('kakaolu kaplamali bitter cikolatali kek') ||
      key.contains('kakao kaplamali bitter cikolatali kek') ||
      key.contains('kakao soslu') ||
      key.contains('bitter cikolatali kek')) {
    return 'product_description_fragment';
  }
  if (_functionalCategoryLabels.contains(key)) {
    return 'generic_functional_category';
  }
  if (_genericFoodGroupLabels.contains(key)) return 'generic_food_group';
  return null;
}

void _debugAnalysisResultLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}

String _filterKey(String value) {
  var text = value.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'^[\s,.;:/\-–—]+|[\s,.;:/\-–—]+$'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text;
}

bool _isGenericOilGroup(String key) =>
    key == 'bitkisel yağlar' || key == 'bitkisel yağ' || key == 'bitkisel yag';

bool _isSpecificOil(String key) {
  return key.contains('palm') ||
      key.contains('palmiye') ||
      key.contains('ayçiçek yağı') ||
      key.contains('aycicek yagi') ||
      key.contains('mısır yağı') ||
      key.contains('misir yagi') ||
      key.contains('kanola yağı') ||
      key.contains('kanola yagi') ||
      key.contains('kakao yağı') ||
      key.contains('kakao yagi');
}

const _noiseTokens = {
  "'dir",
  'dir',
  've',
  'ile',
  'için',
  'icin',
  'içerir',
  'icerir',
  'içindeki',
  'icindeki',
  'içindekiler',
  'icindekiler',
  'alerjen',
  'alerjenler',
  'büyük harfle',
  'buyuk harfle',
  'yazılmıştır',
  'yazilmistir',
  'eser miktarda',
  'miktarda',
  'değişen miktarlarda',
  'degisen miktarlarda',
};

const _functionalCategoryLabels = {
  'koruyucu',
  'kabartıcı',
  'kabartici',
  'kıvam arttırıcı',
  'kivam arttirici',
  'asitlik düzenleyici',
  'asitlik duzenleyici',
  'nem verici',
  'emülgatör',
  'emulgator',
  'renklendirici',
  'aroma verici',
  'aroma vericiler',
  'stabilizör',
  'stabilizor',
  'antioksidan',
  'tatlandırıcı',
  'tatlandirici',
  'topaklanmayı önleyici',
  'topaklanmayi onleyici',
  'jelleştirici',
  'jellestirici',
};

const _genericFoodGroupLabels = {
  'süt ürünü',
  'sut urunu',
  'süt ürünleri',
  'sut urunleri',
  'tahıl',
  'tahil',
  'bitkisel ürün',
  'bitkisel urun',
  'kakao kaplama',
  'kakaolu kaplama',
};

_ProductDetailIngredientSections _splitProductDetailIngredientRows(
  ProductAnalysisResult result,
  List<_IngredientDisplayItem> items,
) {
  final allergenLabels = <String>{};
  final attentionInput = <_IngredientDisplayItem>[];

  for (final item in items) {
    final key = _filterKey(item.normalizedName);
    final allergen = allergenLabelForIngredientKey(key);
    if (allergen != null) allergenLabels.add(allergen);
    if (_isAllergenOnlyIngredient(key)) continue;
    attentionInput.add(item);
  }

  for (final token in result.allergenTokens) {
    final key = _filterKey(token);
    final allergen = allergenLabelForIngredientKey(key);
    if (allergen != null) allergenLabels.add(allergen);
  }

  return _ProductDetailIngredientSections(
    attentionGroups: _buildAttentionGroups(attentionInput),
    allergens: allergenLabels.toList(growable: false)..sort(),
  );
}

bool _isAllergenOnlyIngredient(String key) {
  return key.contains('gluten') ||
      key.contains('buğday') ||
      key.contains('bugday') ||
      key.contains('süt') ||
      key.contains('sut') ||
      key.contains('laktoz') ||
      key.contains('peynir altı suyu') ||
      key.contains('peynir alti suyu') ||
      key.contains('yumurta') ||
      key.contains('soya') ||
      key.contains('fındık') ||
      key.contains('findik') ||
      key.contains('fıstık') ||
      key.contains('fistik') ||
      key.contains('badem') ||
      key.contains('ceviz') ||
      key.contains('susam') ||
      key.contains('balık') ||
      key.contains('balik') ||
      key.contains('kabuklu deniz');
}

// ── Grouped attention model ───────────────────────────────────────────────────

/// User-facing category groups inside the "Dikkat Edilecek İçerikler" card.
enum _AttentionCategory {
  sweetener,
  oil,
  preservative,
  color,
  leavening,
  emulsifier,
  other,
}

const _attentionCategoryOrder = <_AttentionCategory>[
  _AttentionCategory.sweetener,
  _AttentionCategory.oil,
  _AttentionCategory.preservative,
  _AttentionCategory.color,
  _AttentionCategory.leavening,
  _AttentionCategory.emulsifier,
  _AttentionCategory.other,
];

String _attentionCategoryTitle(_AttentionCategory c) => switch (c) {
  _AttentionCategory.sweetener => 'Şeker ve Tatlandırıcılar',
  _AttentionCategory.oil => 'Yağlar',
  _AttentionCategory.preservative => 'Koruyucular',
  _AttentionCategory.color => 'Renklendiriciler',
  _AttentionCategory.leavening => 'Kabartıcılar',
  _AttentionCategory.emulsifier => 'Emülgatörler ve Kıvam Vericiler',
  _AttentionCategory.other => 'Diğer Dikkat Edilecekler',
};

String _attentionCategoryLabel(_AttentionCategory c) => switch (c) {
  _AttentionCategory.sweetener => 'Şeker/Tatlandırıcı',
  _AttentionCategory.oil => 'Yağ',
  _AttentionCategory.preservative => 'Koruyucu',
  _AttentionCategory.color => 'Renklendirici',
  _AttentionCategory.leavening => 'Kabartıcı',
  _AttentionCategory.emulsifier => 'Emülgatör',
  _AttentionCategory.other => 'Katkı',
};

IconData _attentionCategoryIcon(_AttentionCategory c) => switch (c) {
  _AttentionCategory.sweetener => Icons.cake_outlined,
  _AttentionCategory.oil => Icons.water_drop_outlined,
  _AttentionCategory.preservative => Icons.shield_outlined,
  _AttentionCategory.color => Icons.palette_outlined,
  _AttentionCategory.leavening => Icons.bubble_chart_outlined,
  _AttentionCategory.emulsifier => Icons.science_outlined,
  _AttentionCategory.other => Icons.warning_amber_rounded,
};

Color _attentionCategoryColor(_AttentionCategory c) => switch (c) {
  _AttentionCategory.sweetener => Colors.pinkAccent,
  _AttentionCategory.oil => Colors.orange,
  _AttentionCategory.preservative => Colors.blueGrey,
  _AttentionCategory.color => Colors.deepPurple,
  _AttentionCategory.leavening => Colors.teal,
  _AttentionCategory.emulsifier => Colors.indigo,
  _AttentionCategory.other => Colors.deepOrange,
};

/// Canonical, single-source spec for an attention-worthy ingredient. The same
/// [risk] drives both the list dot colour and the detail sheet text, so they
/// can never disagree.
class _AttentionSpec {
  final String groupId; // merges technical variants into one row
  final String displayName; // user-friendly row title
  final _AttentionCategory category;
  final String risk; // canonical: high / medium / low
  final String? technicalNote; // shown in the detail sheet
  final String? purpose;
  final String? riskSummary;

  const _AttentionSpec({
    required this.groupId,
    required this.displayName,
    required this.category,
    required this.risk,
    this.technicalNote,
    this.purpose,
    this.riskSummary,
  });
}

bool _hasSyrupMarker(String k) =>
    k.contains('şurup') ||
    k.contains('şurub') ||
    k.contains('surup') ||
    k.contains('surub');

/// Returns the canonical attention spec for a normalized ingredient key, or
/// null when the ingredient is not decision-relevant (it is then hidden, to
/// keep the product detail compact). This is the single source of truth for the
/// display name, category and risk level of grouped attention rows.
_AttentionSpec? _attentionSpecForKey(String key) {
  final k = key.toLowerCase();

  // ── Sweeteners & sugars ──────────────────────────────────────────────────
  if (k.contains('aspartam')) {
    return const _AttentionSpec(
      groupId: 'aspartam',
      displayName: 'Aspartam',
      category: _AttentionCategory.sweetener,
      risk: 'high',
      technicalNote: 'Aspartam (E951)',
      purpose: 'Yapay tatlandırıcı olarak tat vermek için kullanılır.',
      riskSummary:
          'Fenilketonüri (PKU) olanların kaçınması gerekir; sık tüketimde dikkat edilebilir.',
    );
  }
  if (k.contains('sukraloz') ||
      k.contains('asesülfam') ||
      k.contains('asesulfam') ||
      k.contains('sakarin')) {
    return _AttentionSpec(
      groupId: 'intense_sweetener',
      displayName: k.contains('sukraloz')
          ? 'Sukraloz'
          : (k.contains('sakarin') ? 'Sakarin' : 'Asesülfam K'),
      category: _AttentionCategory.sweetener,
      risk: 'medium',
      purpose: 'Yapay tatlandırıcı olarak şekersiz tatlılık sağlar.',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; sık tüketimde dikkat edilebilir.',
    );
  }
  if (k.contains('sorbitol')) {
    return const _AttentionSpec(
      groupId: 'sorbitol',
      displayName: 'Sorbitol',
      category: _AttentionCategory.sweetener,
      risk: 'medium',
      technicalNote: 'Sorbitol (E420)',
      purpose:
          'Tat, nem tutma ve kıvam sağlamak için kullanılan bir polioldür.',
      riskSummary:
          'Fazla tüketimde sindirim rahatsızlığı yapabilir; paketli tatlılarda dikkat edilebilir.',
    );
  }
  if (_hasSyrupMarker(k)) {
    return const _AttentionSpec(
      groupId: 'sugar_syrup',
      displayName: 'Şeker şurubu',
      category: _AttentionCategory.sweetener,
      risk: 'medium',
      technicalNote:
          'Etikette "invert şeker şurubu", "glukoz şurubu" veya "glukoz-fruktoz şurubu" olarak geçebilir.',
      purpose: 'Tat, kıvam ve nem tutma sağlamak için kullanılır.',
      riskSummary:
          'Sık tüketimde ilave şeker alımını artırır; tüketim sıklığına dikkat edilmelidir.',
    );
  }
  if (k.contains('maltodekstrin')) {
    return const _AttentionSpec(
      groupId: 'maltodextrin',
      displayName: 'Maltodekstrin',
      category: _AttentionCategory.sweetener,
      risk: 'medium',
      purpose: 'Dolgu, kıvam ve tat taşıyıcı olarak kullanılır.',
      riskSummary:
          'Hızlı sindirilen bir karbonhidrattır; sık tüketimde dikkat edilebilir.',
    );
  }
  if (k.contains('şeker') || k.contains('seker')) {
    return const _AttentionSpec(
      groupId: 'sugar',
      displayName: 'Şeker',
      category: _AttentionCategory.sweetener,
      risk: 'medium',
      technicalNote: 'İlave şeker (sakaroz)',
      purpose: 'Tat vermek ve ürün dokusunu desteklemek için kullanılır.',
      riskSummary:
          'Sık tüketimde ilave şeker alımını artırır; tüketim sıklığına dikkat edilmelidir.',
    );
  }

  // ── Oils ─────────────────────────────────────────────────────────────────
  if (k.contains('palm') || k.contains('palmiye')) {
    return const _AttentionSpec(
      groupId: 'palm',
      displayName: 'Palm yağı',
      category: _AttentionCategory.oil,
      risk: 'medium',
      technicalNote:
          'Etikette "palm yağı", "palmiye yağı" veya "hidrojenize palm yağı" olarak geçebilir.',
      purpose: 'Ürüne doku, kıvam ve raf ömrü kazandırmak için kullanılır.',
      riskSummary:
          'Sık tüketimde doymuş yağ alımını artırabilir; ultra işlenmiş ürünlerde dikkatli olunmalıdır.',
    );
  }
  if (k.contains('ayçiçek yağı') || k.contains('aycicek yagi')) {
    return const _AttentionSpec(
      groupId: 'sunflower_oil',
      displayName: 'Ayçiçek yağı',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose:
          'Ürünün yağ fazını oluşturmak ve lezzet/doku sağlamak için kullanılır.',
      riskSummary:
          'Tek başına yüksek riskli değildir; işlenmiş ürünlerde toplam yağ alımına katkı sağlar.',
    );
  }
  if (k.contains('mısır yağı') || k.contains('misir yagi')) {
    return const _AttentionSpec(
      groupId: 'corn_oil',
      displayName: 'Mısır yağı',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose: 'Ürünün yağ fazını oluşturmak için kullanılır.',
      riskSummary:
          'Tek başına yüksek riskli değildir; işlenmiş ürünlerde toplam yağ alımına dikkat edilmelidir.',
    );
  }
  if (k.contains('kanola yağı') || k.contains('kanola yagi')) {
    return const _AttentionSpec(
      groupId: 'canola_oil',
      displayName: 'Kanola yağı',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose: 'Ürünün yağ fazını oluşturmak için kullanılır.',
      riskSummary:
          'Tek başına yüksek riskli değildir; işlenmiş ürünlerde toplam yağ alımına dikkat edilmelidir.',
    );
  }
  if (k.contains('kakao yağı') || k.contains('kakao yagi')) {
    return const _AttentionSpec(
      groupId: 'cocoa_butter',
      displayName: 'Kakao yağı',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose:
          'Çikolata ve kaplamalarda doku ve ağız hissi sağlamak için kullanılır.',
      riskSummary:
          'Tek başına yüksek riskli değildir; toplam yağ ve şeker yüküyle birlikte değerlendirilmelidir.',
    );
  }
  if (k.contains('hidrojenize')) {
    return const _AttentionSpec(
      groupId: 'hydrogenated_oil',
      displayName: 'Hidrojenize yağ',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose: 'Ürünün dokusunu ve raf ömrünü iyileştirmek için kullanılır.',
      riskSummary:
          'İşlenmiş yağ yapısı nedeniyle sık tüketimde dikkatli olunmalıdır; etikette trans yağ bilgisi kontrol edilmelidir.',
    );
  }
  if (_isGenericOilGroup(k)) {
    return const _AttentionSpec(
      groupId: 'vegetable_oil',
      displayName: 'Bitkisel yağ',
      category: _AttentionCategory.oil,
      risk: 'medium',
      purpose: 'Ürüne doku, kıvam ve lezzet kazandırmak için kullanılır.',
      riskSummary:
          'Yağın türü net belirtilmediğinde kalite değerlendirmesi sınırlıdır; toplam yağ alımına dikkat edilmelidir.',
    );
  }

  // ── Preservatives ────────────────────────────────────────────────────────
  if (k.contains('nitrit') || k.contains('nitrat')) {
    return const _AttentionSpec(
      groupId: 'nitrite',
      displayName: 'Nitrit/Nitrat koruyucu',
      category: _AttentionCategory.preservative,
      risk: 'high',
      technicalNote: 'Sodyum nitrit / nitrat (E249–E252)',
      purpose: 'İşlenmiş ette rengi ve raf ömrünü korumak için kullanılır.',
      riskSummary:
          'İşlenmiş et katkısı olarak sık tüketimde dikkatli olunması önerilir.',
    );
  }
  if (k.contains('sorbik asit') || k.contains('potasyum sorbat')) {
    return const _AttentionSpec(
      groupId: 'sorbate',
      displayName: 'Sorbat koruyucu',
      category: _AttentionCategory.preservative,
      risk: 'low',
      technicalNote: 'Sorbik asit / Potasyum sorbat (E200–E202)',
      purpose:
          'Ürünün raf ömrünü uzatmak ve küf/maya gelişimini sınırlamak için kullanılır.',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }
  if (k.contains('sodyum benzoat') || k.contains('benzoik asit')) {
    return const _AttentionSpec(
      groupId: 'benzoate',
      displayName: 'Benzoat koruyucu',
      category: _AttentionCategory.preservative,
      risk: 'low',
      technicalNote: 'Benzoik asit / Sodyum benzoat (E210–E211)',
      purpose:
          'Ürünün raf ömrünü uzatmak ve mikrobiyal gelişimi sınırlamak için kullanılır.',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }

  // ── Colors ───────────────────────────────────────────────────────────────
  if (k.contains('tartrazin') || k.contains('e102')) {
    return const _AttentionSpec(
      groupId: 'tartrazine',
      displayName: 'Tartrazin',
      category: _AttentionCategory.color,
      risk: 'high',
      technicalNote: 'Tartrazin (E102)',
      purpose: 'Ürüne sarı renk vermek için kullanılan yapay renklendiricidir.',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (k.contains('allura red') || k.contains('e129')) {
    return const _AttentionSpec(
      groupId: 'allura_red',
      displayName: 'Allura Red',
      category: _AttentionCategory.color,
      risk: 'high',
      technicalNote: 'Allura Red AC (E129)',
      purpose:
          'Ürüne kırmızı renk vermek için kullanılan yapay renklendiricidir.',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (k.contains('sunset yellow') || k.contains('e110')) {
    return const _AttentionSpec(
      groupId: 'sunset_yellow',
      displayName: 'Sunset Yellow',
      category: _AttentionCategory.color,
      risk: 'high',
      technicalNote: 'Sunset Yellow FCF (E110)',
      purpose:
          'Ürüne turuncu/sarı renk vermek için kullanılan yapay renklendiricidir.',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (k.contains('karamel') && k.contains('renklendirici')) {
    return const _AttentionSpec(
      groupId: 'caramel_color',
      displayName: 'Karamel renklendirici',
      category: _AttentionCategory.color,
      risk: 'medium',
      technicalNote: 'Karamel rengi (E150)',
      purpose: 'Ürüne kahverengi ton vermek için kullanılır.',
      riskSummary:
          'Genel olarak düşük/orta dikkat düzeyindedir; ultra işlenmiş ürün göstergesi olabilir.',
    );
  }

  // ── Leavening agents ─────────────────────────────────────────────────────
  if (k.contains('sodyum asit pirofosfat') ||
      k.contains('disodyum difosfat') ||
      k.contains('difosfat') ||
      k == 'e450') {
    return const _AttentionSpec(
      groupId: 'phosphate_leavening',
      displayName: 'Fosfat bazlı kabartıcı',
      category: _AttentionCategory.leavening,
      risk: 'medium',
      technicalNote: 'Sodyum asit pirofosfat / E450',
      purpose:
          'Hamur işlerinde kabarma ve doku oluşumunu desteklemek için kullanılır.',
      riskSummary:
          'Fosfat katkısı olduğu için sık paketli ürün tüketiminde dikkat edilebilir.',
    );
  }
  if (k.contains('sodyum hidrojen karbonat') ||
      k.contains('sodyum bikarbonat') ||
      k == 'karbonat' ||
      k == 'e500') {
    return const _AttentionSpec(
      groupId: 'carbonate_leavening',
      displayName: 'Karbonat bazlı kabartıcı',
      category: _AttentionCategory.leavening,
      risk: 'low',
      technicalNote: 'Sodyum hidrojen karbonat / E500',
      purpose:
          'Hamurun kabarmasını ve istenen dokunun oluşmasını sağlamak için kullanılır.',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; paketli ürün göstergesi olarak değerlendirilebilir.',
    );
  }

  // ── Emulsifiers & thickeners ─────────────────────────────────────────────
  if (k.contains('poligliserol') || k == 'pgpr' || k == 'e476') {
    return const _AttentionSpec(
      groupId: 'pgpr',
      displayName: 'Çikolata emülgatörü',
      category: _AttentionCategory.emulsifier,
      risk: 'low',
      technicalNote: 'Poligliserol polirisinoleat (E476)',
      purpose:
          'Çikolata ve kaplamalarda kıvamı ve akışkanlığı düzenlemek için kullanılır.',
      riskSummary:
          'Tek başına yüksek riskli bir içerik değildir; ultra işlenmiş ürünlerde katkı göstergesi olabilir.',
    );
  }
  if (k.contains('mono ve digliserit') || k.contains('mono- ve digliserit')) {
    return const _AttentionSpec(
      groupId: 'mono_diglyceride',
      displayName: 'Mono ve digliseritler',
      category: _AttentionCategory.emulsifier,
      risk: 'low',
      technicalNote: 'Yağ asitlerinin mono- ve digliseritleri (E471)',
      purpose:
          'Yağ ve su fazını kararlı tutmak, ürün dokusunu desteklemek için kullanılır.',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; ultra işlenmiş ürün göstergesi olabilir.',
    );
  }
  if (k.contains('ksantan gam')) {
    return const _AttentionSpec(
      groupId: 'xanthan',
      displayName: 'Ksantan gam',
      category: _AttentionCategory.emulsifier,
      risk: 'low',
      technicalNote: 'Ksantan gam (E415)',
      purpose: 'Ürünün kıvamını ve stabilitesini korumak için kullanılır.',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; ultra işlenmiş ürün göstergesi olabilir.',
    );
  }

  // ── Other relevant ───────────────────────────────────────────────────────
  if (k == 'tuz') {
    return const _AttentionSpec(
      groupId: 'salt',
      displayName: 'Tuz',
      category: _AttentionCategory.other,
      risk: 'medium',
      technicalNote: 'Tuz (sodyum klorür)',
      purpose: 'Tat dengesini sağlamak için kullanılır.',
      riskSummary:
          'Sık tüketimde toplam sodyum alımını artırabilir; tuz hassasiyeti olanlar dikkat etmelidir.',
    );
  }
  if (k.contains('monosodyum glutamat')) {
    return const _AttentionSpec(
      groupId: 'msg',
      displayName: 'Çeşni artırıcı (MSG)',
      category: _AttentionCategory.other,
      risk: 'medium',
      technicalNote: 'Monosodyum glutamat (E621)',
      purpose: 'Tadı yoğunlaştırmak için kullanılır.',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }
  if (k.contains('kafein') ||
      k.contains('taurin') ||
      k.contains('guarana') ||
      k.contains('ginseng') ||
      k.contains('l-karnitin')) {
    return _AttentionSpec(
      groupId: 'stimulant',
      displayName: k.contains('kafein')
          ? 'Kafein'
          : (k.contains('taurin')
                ? 'Taurin'
                : (k.contains('guarana') ? 'Guarana' : 'Uyarıcı katkı')),
      category: _AttentionCategory.other,
      risk: 'medium',
      purpose: 'Uyarıcı/enerji verici etki için kullanılır.',
      riskSummary:
          'Çocuklar ve hassas kişiler için sık tüketimde dikkatli olunmalıdır.',
    );
  }

  return null;
}

int _riskRank(String risk) => switch (risk) {
  'high' => 3,
  'medium' => 2,
  'low' => 1,
  _ => 0,
};

/// One row inside a grouped attention category.
class _AttentionItem {
  final _AttentionSpec spec;
  final Ingredient? ingredient; // DB match, when available
  final int order;

  const _AttentionItem({
    required this.spec,
    required this.ingredient,
    required this.order,
  });
}

/// A rendered category group with its (capped) visible rows.
class _AttentionGroup {
  final _AttentionCategory category;
  final List<_AttentionItem> items; // capped to the visible max
  final int hiddenCount;

  const _AttentionGroup({
    required this.category,
    required this.items,
    required this.hiddenCount,
  });
}

const _maxRowsPerAttentionGroup = 3;

/// Builds grouped, de-duplicated, capped attention rows from filtered items.
List<_AttentionGroup> _buildAttentionGroups(
  List<_IngredientDisplayItem> items,
) {
  // Dedup by spec.groupId — collapses technical variants (palm + hidrojenize
  // palm, sorbik asit + potasyum sorbat, …) into one canonical row.
  final byGroup = <String, _AttentionItem>{};
  for (final item in items) {
    final spec = _attentionSpecForKey(_filterKey(item.normalizedName));
    if (spec == null) continue;
    final existing = byGroup[spec.groupId];
    if (existing == null ||
        (existing.ingredient == null && item.ingredient != null)) {
      byGroup[spec.groupId] = _AttentionItem(
        spec: spec,
        ingredient: item.ingredient,
        order: item.originalOrder,
      );
    }
  }

  final buckets = <_AttentionCategory, List<_AttentionItem>>{};
  for (final ai in byGroup.values) {
    buckets.putIfAbsent(ai.spec.category, () => []).add(ai);
  }

  final groups = <_AttentionGroup>[];
  for (final category in _attentionCategoryOrder) {
    final list = buckets[category];
    if (list == null || list.isEmpty) continue;
    // Sort by risk (high→low) then original ingredient order.
    list.sort((a, b) {
      final byRisk = _riskRank(b.spec.risk).compareTo(_riskRank(a.spec.risk));
      if (byRisk != 0) return byRisk;
      return a.order.compareTo(b.order);
    });
    final visible = list.take(_maxRowsPerAttentionGroup).toList();
    groups.add(
      _AttentionGroup(
        category: category,
        items: visible,
        hiddenCount: list.length - visible.length,
      ),
    );
  }
  return groups;
}

class _ProductDetailIngredientSections {
  final List<_AttentionGroup> attentionGroups;
  final List<String> allergens;

  const _ProductDetailIngredientSections({
    required this.attentionGroups,
    required this.allergens,
  });

  bool get isEmpty => attentionGroups.isEmpty && allergens.isEmpty;
}

List<String> _expandProductDetailParsedToken(String token) {
  final key = _filterKey(token);
  if (key.isEmpty) return const [];

  if (key == 'bitter çikolata şeker' || key == 'bitter cikolata seker') {
    return const ['şeker'];
  }

  final withoutAmountPrefix = key
      .replaceFirst(RegExp(r'^değişen miktarlarda\s+'), '')
      .replaceFirst(RegExp(r'^degisen miktarlarda\s+'), '');

  return [_canonicalProductDetailToken(withoutAmountPrefix)];
}

String _canonicalProductDetailToken(String key) {
  if (key == 'poligliserol ester' ||
      key == 'poligliserol polirisinoleat' ||
      key == 'pgpr' ||
      key == 'e476') {
    return 'poligliserol polirisinoleat';
  }

  if (key == 'lesitin' ||
      key == 'soya lesitini' ||
      key == 'ayçiçek lesitini' ||
      key == 'aycicek lesitini' ||
      key == 'e322') {
    return 'lesitin';
  }

  if (key == 'mono- ve digliseritler' ||
      key == 'mono ve digliseritler' ||
      key == 'mono ve digliserit' ||
      key == 'mono digliseritler') {
    return 'mono ve digliseritler';
  }

  if (key == 'palm' || key == 'palm yağı' || key == 'palmiye yağı') {
    return 'palm yağı';
  }
  if (key == 'tam hidrojenize palm') {
    return 'tam hidrojenize palm yağı';
  }
  if (key == 'sodyum bikarbonat') {
    return 'sodyum hidrojen karbonat';
  }

  return key;
}

class _IngredientDisplayItem {
  final String name;
  final String normalizedName;
  final String riskLevel;
  final int originalOrder;
  final Ingredient? ingredient;

  const _IngredientDisplayItem({
    required this.name,
    required this.normalizedName,
    required this.riskLevel,
    required this.originalOrder,
    this.ingredient,
  });

  factory _IngredientDisplayItem.fromIngredient(
    Ingredient ingredient,
    int originalOrder,
  ) {
    return _IngredientDisplayItem(
      name: ingredient.name,
      normalizedName: ingredient.normalizedName,
      riskLevel: ingredient.riskLevel,
      originalOrder: originalOrder,
      ingredient: ingredient,
    );
  }

  factory _IngredientDisplayItem.fromParsedToken(
    String token,
    int originalOrder,
  ) {
    final normalized = _canonicalProductDetailToken(_filterKey(token));
    return _IngredientDisplayItem(
      name: _displayNameForParsedToken(normalized),
      normalizedName: normalized,
      riskLevel: _riskLevelForParsedToken(normalized),
      originalOrder: originalOrder,
    );
  }
}

String _displayNameForParsedToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed[0] == 'i') return 'İ${trimmed.substring(1)}';
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

String _riskLevelForParsedToken(String token) {
  final normalized = token.toLowerCase();
  if (normalized.contains('nitrit') ||
      normalized.contains('nitrat') ||
      normalized.contains('aspartam') ||
      normalized.contains('tartrazin')) {
    return 'high';
  }
  if (normalized.contains('yağ') ||
      normalized.contains('yag') ||
      normalized.contains('tuz') ||
      normalized.contains('sodyum') ||
      normalized.contains('şeker') ||
      normalized.contains('seker') ||
      normalized.contains('şurup') ||
      normalized.contains('surup') ||
      normalized.contains('sorbat') ||
      normalized.contains('sorbik asit') ||
      normalized.contains('sitrik asit') ||
      normalized.contains('ksantan gam') ||
      normalized.contains('modifiye nişasta') ||
      normalized.contains('modifiye nisasta') ||
      normalized.contains('gliserol') ||
      normalized.contains('poligliserol') ||
      normalized.contains('mono ve digliserit') ||
      normalized.contains('aroma') ||
      normalized.contains('emülgatör') ||
      normalized.contains('emulgator') ||
      normalized.contains('hidrojenize')) {
    return 'medium';
  }
  return 'low';
}

// ── Nutrition section ─────────────────────────────────────────────────────────

enum _NLevel { high, medium, low, positive, strongPositive, neutral }

class _NutritionRowData {
  final String key;
  final String label;
  final IconData icon;
  final double? value;
  final String unit;
  final _NLevel level;
  final String assessmentLabel;

  const _NutritionRowData({
    required this.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.level,
    required this.assessmentLabel,
  });
}

_NutritionRowData _sugarRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v > 22.5) {
    level = _NLevel.high;
    label = 'Yüksek';
  } else if (v > 5.0) {
    level = _NLevel.medium;
    label = 'Orta';
  } else {
    level = _NLevel.low;
    label = 'Düşük';
  }
  return _NutritionRowData(
    key: 'sugars',
    label: 'Şeker',
    icon: Icons.cake_outlined,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

_NutritionRowData _saltRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v > 1.5) {
    level = _NLevel.high;
    label = 'Yüksek';
  } else if (v > 0.3) {
    level = _NLevel.medium;
    label = 'Orta';
  } else {
    level = _NLevel.low;
    label = 'Düşük';
  }
  return _NutritionRowData(
    key: 'salt',
    label: 'Tuz',
    icon: Icons.grain_outlined,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

_NutritionRowData _satFatRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v > 5.0) {
    level = _NLevel.high;
    label = 'Yüksek';
  } else if (v > 1.5) {
    level = _NLevel.medium;
    label = 'Orta';
  } else {
    level = _NLevel.low;
    label = 'Düşük';
  }
  return _NutritionRowData(
    key: 'saturated_fat',
    label: 'Doymuş Yağ',
    icon: Icons.opacity,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

_NutritionRowData _fatRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v > 17.5) {
    level = _NLevel.high;
    label = 'Yüksek';
  } else if (v > 3.0) {
    level = _NLevel.medium;
    label = 'Orta';
  } else {
    level = _NLevel.low;
    label = 'Düşük';
  }
  return _NutritionRowData(
    key: 'fat',
    label: 'Yağ',
    icon: Icons.water_drop_outlined,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

_NutritionRowData _fiberRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v >= 6.0) {
    level = _NLevel.strongPositive;
    label = 'Çok iyi';
  } else if (v >= 3.0) {
    level = _NLevel.positive;
    label = 'İyi';
  } else {
    level = _NLevel.neutral;
    label = 'Bilgi amaçlı';
  }
  return _NutritionRowData(
    key: 'fiber',
    label: 'Lif',
    icon: Icons.eco_outlined,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

_NutritionRowData _proteinRow(double? v) {
  _NLevel level;
  String label;
  if (v == null) {
    level = _NLevel.neutral;
    label = '';
  } else if (v >= 12.0) {
    level = _NLevel.strongPositive;
    label = 'Çok iyi';
  } else if (v >= 5.0) {
    level = _NLevel.positive;
    label = 'İyi';
  } else {
    level = _NLevel.neutral;
    label = 'Bilgi amaçlı';
  }
  return _NutritionRowData(
    key: 'proteins',
    label: 'Protein',
    icon: Icons.fitness_center_outlined,
    value: v,
    unit: 'g',
    level: level,
    assessmentLabel: label,
  );
}

Color _levelColor(_NLevel level) {
  switch (level) {
    case _NLevel.high:
      return Colors.red[600]!;
    case _NLevel.medium:
      return Colors.orange[600]!;
    case _NLevel.low:
      return Colors.green[600]!;
    case _NLevel.positive:
      return Colors.green[600]!;
    case _NLevel.strongPositive:
      return Colors.green[800]!;
    case _NLevel.neutral:
      return Colors.grey[500]!;
  }
}

/// Yuka-style nutrition facts card. Public so product_page can embed it directly.
class NutritionSectionCard extends StatelessWidget {
  final NutritionData nutritionData;

  const NutritionSectionCard({super.key, required this.nutritionData});

  @override
  Widget build(BuildContext context) {
    final rows = [
      _sugarRow(nutritionData.sugars),
      _saltRow(nutritionData.salt),
      _satFatRow(nutritionData.saturatedFat),
      _fatRow(nutritionData.fat),
      _fiberRow(nutritionData.fiber),
      _proteinRow(nutritionData.proteins),
    ].where((r) => r.value != null).toList(growable: false);

    if (rows.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Besin Değerleri',
      icon: Icons.bar_chart,
      accentColor: Colors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '100 g/ml başına',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          if (nutritionData.energyKcal != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _NutritionLeadingIcon(
                  nutrientKey: 'energy',
                  icon: Icons.local_fire_department_outlined,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kalori',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${nutritionData.energyKcal!.toStringAsFixed(0)} kcal',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[800]),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          ...rows.map((row) => _NutritionRow(data: row)),
        ],
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  final _NutritionRowData data;

  const _NutritionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(data.level);
    final valueText = '${data.value!.toStringAsFixed(1)} ${data.unit}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _NutritionLeadingIcon(
            nutrientKey: data.key,
            icon: data.icon,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            valueText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[800]),
          ),
          if (data.assessmentLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                data.assessmentLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NutritionLeadingIcon extends StatelessWidget {
  final String nutrientKey;
  final IconData icon;
  final Color color;

  const _NutritionLeadingIcon({
    required this.nutrientKey,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('nutrition-row-$nutrientKey-icon'),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: nutrientKey == 'salt'
            ? SaltShakerIcon(color: color, size: 17)
            : Icon(icon, size: 17, color: color),
      ),
    );
  }
}

// ── Shared section card ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _AllergenSection extends StatelessWidget {
  final List<String> allergens;

  const _AllergenSection({required this.allergens});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allergens
          .map(
            (allergen) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Text(
                allergen,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.amber[900],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Renders the grouped "Dikkat Edilecek İçerikler" content: a stack of category
/// subsections, each with a small title and up to 3 dot+name rows. Rows show no
/// risk subtitle; tapping a row opens the canonical detail sheet.
class _GroupedAttentionView extends StatelessWidget {
  final List<_AttentionGroup> groups;

  const _GroupedAttentionView({required this.groups});

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (i > 0) blocks.add(const SizedBox(height: 12));
      final categoryColor = _attentionCategoryColor(group.category);
      blocks.add(
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _attentionCategoryIcon(group.category),
                size: 18,
                color: categoryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _attentionCategoryTitle(group.category),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[700],
                ),
              ),
            ),
          ],
        ),
      );
      blocks.add(const SizedBox(height: 4));
      for (final item in group.items) {
        blocks.add(
          _GroupedIngredientRow(
            item: item,
            onTap: () => _showAttentionDetail(context, item),
          ),
        );
      }
      if (group.hiddenCount > 0) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 22),
            child: Text(
              '+${group.hiddenCount} içerik daha',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  void _showAttentionDetail(BuildContext context, _AttentionItem item) {
    final spec = item.spec;
    final baseIngredient =
        item.ingredient ??
        Ingredient(
          id: 'attention:${spec.groupId}',
          name: spec.displayName,
          normalizedName: spec.displayName.toLowerCase(),
          riskLevel: spec.risk,
          ingredientType: _categoryLabelForSpec(spec),
          shortPurpose: spec.purpose,
          shortRiskSummary: spec.riskSummary,
          createdAt: DateTime.utc(1970),
          updatedAt: DateTime.utc(1970),
        );
    final resolvedIngredient = enrichIngredientKnowledge(baseIngredient);
    final riskLabel = riskLabelForUser(spec.risk);
    final categoryLabel = _attentionCategoryLabel(spec.category);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.82;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          resolvedIngredient.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Kapat',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Subtitle: risk · category — same risk as the list dot.
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: riskColorForUser(spec.risk),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$riskLabel · $categoryLabel',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (spec.technicalNote != null) ...[
                    Text(
                      'Teknik adı',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spec.technicalNote!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 12),
                  ],
                  IngredientDetailSections(ingredient: resolvedIngredient),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _categoryLabelForSpec(_AttentionSpec spec) =>
    _attentionCategoryLabel(spec.category);

/// A compact product-detail row: colored risk dot + display name. No subtitle.
class _GroupedIngredientRow extends StatelessWidget {
  final _AttentionItem item;
  final VoidCallback onTap;

  const _GroupedIngredientRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final risk = item.spec.risk;
    final riskColor = riskColorForUser(risk);

    return Semantics(
      button: true,
      label:
          '${item.spec.displayName}, ${riskLabelForUser(risk)}. '
          'Detayları görmek için dokunun.',
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          constraints: const BoxConstraints(minHeight: 40),
          color: Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: riskColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.spec.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedIngredientSection extends StatefulWidget {
  final List<_IngredientDisplayItem> ingredients;
  final int defaultVisibleCount;

  const _UnifiedIngredientSection({
    required this.ingredients,
    this.defaultVisibleCount = 8,
  });

  @override
  State<_UnifiedIngredientSection> createState() =>
      _UnifiedIngredientSectionState();
}

class _UnifiedIngredientSectionState extends State<_UnifiedIngredientSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.ingredients.isEmpty) {
      return const SizedBox.shrink();
    }

    final initial = widget.ingredients
        .take(widget.defaultVisibleCount)
        .toList(growable: false);
    final remaining = widget.ingredients
        .skip(widget.defaultVisibleCount)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...initial.map(
          (item) => _UnifiedIngredientRow(
            item: item,
            onTap: item.ingredient == null
                ? null
                : () => _showIngredientDetail(context, item.ingredient!),
          ),
        ),
        if (remaining.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _expanded ? 'Daha az göster' : 'Daha fazla göster',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.blueGrey[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (_expanded)
          ...remaining.map(
            (item) => _UnifiedIngredientRow(
              item: item,
              onTap: item.ingredient == null
                  ? null
                  : () => _showIngredientDetail(context, item.ingredient!),
            ),
          ),
      ],
    );
  }

  void _showIngredientDetail(BuildContext context, Ingredient ingredient) {
    final resolvedIngredient = enrichIngredientKnowledge(ingredient);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.82;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          resolvedIngredient.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Kapat',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: riskColorForUser(resolvedIngredient.riskLevel),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${riskLabelForUser(resolvedIngredient.riskLevel)}${(resolvedIngredient.ingredientType?.trim().isNotEmpty ?? false) ? ' · ${resolvedIngredient.ingredientType!}' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  IngredientDetailSections(ingredient: resolvedIngredient),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnifiedIngredientRow extends StatelessWidget {
  final _IngredientDisplayItem item;
  final VoidCallback? onTap;

  const _UnifiedIngredientRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final riskLabel = riskLabelForUser(item.riskLevel);
    final riskColor = riskColorForUser(item.riskLevel);

    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? '${item.name}, $riskLabel.'
          : '${item.name}, $riskLabel. Detayları görmek için dokunun.',
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: riskColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riskLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UncertainIngredientSection extends StatelessWidget {
  final List<IngredientMatch> items;
  final void Function(String originalToken, bool approved)? onDecision;

  const _UncertainIngredientSection({required this.items, this.onDecision});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Emin Olunamayan İçerikler',
      icon: Icons.help_outline,
      accentColor: Colors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OCR bazı içeriklerden emin olamadı. Etikette bu içerik varsa Var, yoksa Yok seçebilirsiniz.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.amber[900]),
          ),
          const SizedBox(height: 10),
          ...items.map((match) {
            final ingredient = match.matchedIngredient;
            final ingredientName = ingredient?.name ?? 'Bilinmeyen eşleşme';
            final riskLabel = ingredient == null
                ? 'Bilgi yok'
                : riskLabelForUser(ingredient.riskLevel);
            final typeText = ingredient?.ingredientType;
            final confidence = confidenceToLabel(match.confidenceScore);
            final confidenceColor = confidenceToColor(match.confidenceScore);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: ingredient == null
                              ? Colors.grey
                              : riskColorForUser(ingredient.riskLevel),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ingredientName,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[900],
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              typeText != null && typeText.trim().isNotEmpty
                                  ? '$riskLabel · $typeText'
                                  : riskLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: confidenceColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          confidence,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: confidenceColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onDecision != null
                              ? () => onDecision!(match.originalToken, true)
                              : null,
                          child: const Text('Var'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onDecision != null
                              ? () => onDecision!(match.originalToken, false)
                              : null,
                          child: const Text('Yok'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
