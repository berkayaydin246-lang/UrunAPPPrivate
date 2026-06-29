import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/widgets/ingredient_detail_sections.dart';

/// Returns the canonical severity for [ingredient] as defined by the app's
/// spec registry, falling back to the DB-stored riskLevel when no spec exists.
/// Use this for any severity badge that must stay in sync with list rows.
String canonicalRiskLevelForIngredient(Ingredient ingredient) {
  final key = normalizeIngredientDisplayKey(
    ingredient.normalizedName.trim().isNotEmpty
        ? ingredient.normalizedName
        : ingredient.name,
  );
  return productRiskSpecForKey(key)?.riskLevel ?? ingredient.riskLevel;
}

String riskLabelForUser(String riskLevel) {
  switch (riskLevel) {
    case 'high':
      return 'Yüksek dikkat';
    case 'medium':
      return 'Orta dikkat';
    case 'low':
      return 'Az dikkat';
    default:
      return 'Bilgi amaçlı';
  }
}

Color riskColorForUser(String riskLevel) {
  switch (riskLevel) {
    case 'high':
      return Colors.deepOrange;
    case 'medium':
      return Colors.orange;
    case 'low':
      return Colors.green;
    default:
      return AppColors.textSecondary;
  }
}

enum ProductNutrientTone {
  high,
  medium,
  low,
  positive,
  strongPositive,
  neutral,
}

class ProductNutrientVisualData {
  const ProductNutrientVisualData({
    required this.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.tone,
    required this.assessmentLabel,
  });

  final String key;
  final String label;
  final IconData icon;
  final double? value;
  final String unit;
  final ProductNutrientTone tone;
  final String assessmentLabel;
}

Color productNutrientToneColor(ProductNutrientTone tone) {
  switch (tone) {
    case ProductNutrientTone.high:
      return AppColors.danger;
    case ProductNutrientTone.medium:
      return AppColors.warning;
    case ProductNutrientTone.low:
      return AppColors.positive;
    case ProductNutrientTone.positive:
      return AppColors.positive;
    case ProductNutrientTone.strongPositive:
      return AppColors.primary;
    case ProductNutrientTone.neutral:
      return AppColors.textSecondary;
  }
}

ProductNutrientVisualData? nutrientVisualDataForKey(String key, double? value) {
  switch (key) {
    case 'energy':
      return ProductNutrientVisualData(
        key: key,
        label: 'Enerji',
        icon: Icons.local_fire_department_outlined,
        value: value,
        unit: 'kcal',
        tone: ProductNutrientTone.neutral,
        assessmentLabel: '',
      );
    case 'fat':
      return _fatRow(value);
    case 'saturated_fat':
      return _satFatRow(value);
    case 'carbohydrates':
      return ProductNutrientVisualData(
        key: key,
        label: 'Karbonhidrat',
        icon: Icons.grain_outlined,
        value: value,
        unit: 'g',
        tone: ProductNutrientTone.neutral,
        assessmentLabel: '',
      );
    case 'sugars':
      return _sugarRow(value);
    case 'proteins':
      return _proteinRow(value);
    case 'fiber':
      return _fiberRow(value);
    case 'salt':
      return _saltRow(value);
    default:
      return null;
  }
}

List<ProductNutrientVisualData> buildNutritionVisualRows(
  NutritionData nutritionData,
) {
  return [
    nutrientVisualDataForKey('sugars', nutritionData.sugars),
    nutrientVisualDataForKey('salt', nutritionData.salt),
    nutrientVisualDataForKey('saturated_fat', nutritionData.saturatedFat),
    nutrientVisualDataForKey('fat', nutritionData.fat),
    nutrientVisualDataForKey('fiber', nutritionData.fiber),
    nutrientVisualDataForKey('proteins', nutritionData.proteins),
  ].whereType<ProductNutrientVisualData>().toList(growable: false);
}

class ProductIngredientPresentation {
  const ProductIngredientPresentation({
    required this.ingredient,
    required this.originalOrder,
  });

  final Ingredient ingredient;
  final int originalOrder;

  String get name => ingredient.name.trim();
  String get normalizedName => ingredient.normalizedName.trim();
  String get riskLevel => ingredient.riskLevel;

  String? get previewSummary {
    final shortRisk = ingredient.shortRiskSummary?.trim();
    if (shortRisk != null && shortRisk.isNotEmpty) {
      return shortRisk;
    }
    final childWarning = ingredient.childWarning?.trim();
    if (childWarning != null && childWarning.isNotEmpty) {
      return childWarning;
    }
    return null;
  }
}

List<ProductIngredientPresentation> buildStructuredIngredientPresentations(
  Iterable<Ingredient> ingredients,
) {
  final unique = <String, ProductIngredientPresentation>{};
  var order = 0;

  for (final ingredient in ingredients) {
    final resolvedIngredient = enrichIngredientKnowledge(ingredient);
    final key = ingredient.id.trim().isNotEmpty
        ? ingredient.id.trim()
        : normalizeIngredientDisplayKey(
            resolvedIngredient.normalizedName.isNotEmpty
                ? resolvedIngredient.normalizedName
                : resolvedIngredient.name,
          );
    unique.putIfAbsent(
      key,
      () => ProductIngredientPresentation(
        ingredient: resolvedIngredient,
        originalOrder: order++,
      ),
    );
  }

  final sorted = unique.values.toList(growable: false);
  sorted.sort((a, b) {
    final byRisk = _riskRank(b.riskLevel).compareTo(_riskRank(a.riskLevel));
    if (byRisk != 0) return byRisk;
    return a.originalOrder.compareTo(b.originalOrder);
  });
  return sorted;
}

List<String> extractStructuredAllergens(Iterable<Ingredient> ingredients) {
  final allergens = <String>{};
  for (final ingredient in ingredients) {
    final key = normalizeIngredientDisplayKey(
      ingredient.normalizedName.isNotEmpty
          ? ingredient.normalizedName
          : ingredient.name,
    );
    final allergen = allergenLabelForIngredientKey(key);
    if (allergen != null) {
      allergens.add(allergen);
    }
  }
  final values = allergens.toList(growable: false)..sort();
  return values;
}

String? allergenLabelForIngredientKey(String key) {
  if (key.contains('gluten') ||
      key.contains('buğday') ||
      key.contains('bugday')) {
    return 'Gluten / Buğday';
  }
  if (key.contains('süt') ||
      key.contains('sut') ||
      key.contains('laktoz') ||
      key.contains('peynir altı suyu') ||
      key.contains('peynir alti suyu')) {
    return 'Süt';
  }
  if (key.contains('yumurta')) return 'Yumurta';
  if (key.contains('soya')) return 'Soya';
  if (key.contains('fındık') || key.contains('findik')) return 'Fındık';
  if (key.contains('yer fıstığı') ||
      key.contains('yer fistigi') ||
      key == 'fıstık' ||
      key == 'fistik') {
    return 'Yer fıstığı / Fıstık';
  }
  if (key.contains('badem')) return 'Badem';
  if (key.contains('ceviz')) return 'Ceviz';
  if (key.contains('susam')) return 'Susam';
  if (key.contains('balık') || key.contains('balik')) return 'Balık';
  if (key.contains('kabuklu deniz')) return 'Kabuklu deniz ürünleri';
  return null;
}

String normalizeIngredientDisplayKey(String value) {
  var text = value.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'^[\s,.;:/\-–—]+|[\s,.;:/\-–—]+$'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text;
}

String normalizeIngredientTextForDisplay(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return 'Bilgi yok';
  }

  final text = IngredientCanonicalizer.cleanIngredientTextForDisplay(raw);

  if (text.isEmpty) {
    return 'Bilgi yok';
  }
  return text;
}

enum ProductRiskCategory {
  sweetener,
  oil,
  preservative,
  color,
  leavening,
  emulsifier,
  other,
}

class ProductRiskSpec {
  const ProductRiskSpec({
    required this.groupId,
    required this.displayName,
    required this.category,
    required this.riskLevel,
    this.riskSummary,
  });

  final String groupId;
  final String displayName;
  final ProductRiskCategory category;
  final String riskLevel;
  final String? riskSummary;
}

class ProductRiskPreviewItem {
  const ProductRiskPreviewItem({
    required this.name,
    required this.normalizedKey,
    required this.riskLevel,
    required this.originalOrder,
    this.summary,
    this.category,
    this.ingredient,
  });

  final String name;
  final String normalizedKey;
  final String riskLevel;
  final int originalOrder;
  final String? summary;
  final ProductRiskCategory? category;
  final Ingredient? ingredient;

  String? get categoryLabel =>
      category == null ? null : productRiskCategoryLabel(category!);

  IconData? get categoryIcon =>
      category == null ? null : productRiskCategoryIcon(category!);
}

String productRiskCategoryLabel(ProductRiskCategory category) {
  switch (category) {
    case ProductRiskCategory.sweetener:
      return 'Şeker/Tatlandırıcı';
    case ProductRiskCategory.oil:
      return 'Yağ';
    case ProductRiskCategory.preservative:
      return 'Koruyucu';
    case ProductRiskCategory.color:
      return 'Renklendirici';
    case ProductRiskCategory.leavening:
      return 'Kabartıcı';
    case ProductRiskCategory.emulsifier:
      return 'Emülgatör';
    case ProductRiskCategory.other:
      return 'Diğer';
  }
}

IconData productRiskCategoryIcon(ProductRiskCategory category) {
  switch (category) {
    case ProductRiskCategory.sweetener:
      return Icons.cake_outlined;
    case ProductRiskCategory.oil:
      return Icons.water_drop_outlined;
    case ProductRiskCategory.preservative:
      return Icons.shield_outlined;
    case ProductRiskCategory.color:
      return Icons.palette_outlined;
    case ProductRiskCategory.leavening:
      return Icons.bubble_chart_outlined;
    case ProductRiskCategory.emulsifier:
      return Icons.science_outlined;
    case ProductRiskCategory.other:
      return Icons.warning_amber_rounded;
  }
}

List<ProductRiskPreviewItem> buildComparisonRiskPreviewItems({
  ProductAnalysisResult? analysisResult,
  Iterable<Ingredient> fallbackIngredients = const <Ingredient>[],
}) {
  final byKey = <String, ProductRiskPreviewItem>{};
  var order = 0;

  void addItem(ProductRiskPreviewItem? item, {required String key}) {
    if (item == null || byKey.containsKey(key)) return;
    byKey[key] = item;
  }

  final analysisIngredients = <Ingredient>[
    ...?analysisResult?.recognizedIngredients,
    ...?analysisResult?.detectedRiskIngredients,
  ];

  for (final ingredient in analysisIngredients) {
    final item = _buildRiskPreviewItemFromIngredient(
      enrichIngredientKnowledge(ingredient),
      originalOrder: order++,
    );
    addItem(item, key: item?.normalizedKey ?? '');
  }

  for (final ingredient in fallbackIngredients) {
    final item = _buildRiskPreviewItemFromIngredient(
      enrichIngredientKnowledge(ingredient),
      originalOrder: order++,
    );
    addItem(item, key: item?.normalizedKey ?? '');
  }

  for (final token in analysisResult?.unknownIngredients ?? const <String>[]) {
    final item = _buildRiskPreviewItemFromToken(token, originalOrder: order++);
    addItem(item, key: item?.normalizedKey ?? '');
  }

  final values = byKey.values.toList(growable: false);
  values.sort((a, b) {
    final byRisk = _riskRank(b.riskLevel).compareTo(_riskRank(a.riskLevel));
    if (byRisk != 0) return byRisk;
    return a.originalOrder.compareTo(b.originalOrder);
  });
  return values;
}

List<String>? buildComparisonAllergenLabels({
  ProductAnalysisResult? analysisResult,
  Iterable<Ingredient> fallbackIngredients = const <Ingredient>[],
  String? rawIngredientText,
}) {
  final hasAnalysis = analysisResult != null;
  final hasFallback = fallbackIngredients.isNotEmpty;
  final hasRawText = rawIngredientText?.trim().isNotEmpty == true;
  if (!hasAnalysis && !hasFallback && !hasRawText) {
    return null;
  }

  final allergens = <String>{};

  void addKey(String rawKey) {
    final key = normalizeIngredientDisplayKey(rawKey);
    if (key.isEmpty) return;
    final allergen = allergenLabelForIngredientKey(key);
    if (allergen != null) {
      allergens.add(allergen);
    }
  }

  for (final ingredient in fallbackIngredients) {
    addKey(
      ingredient.normalizedName.isNotEmpty
          ? ingredient.normalizedName
          : ingredient.name,
    );
  }

  for (final ingredient in [
    ...?analysisResult?.recognizedIngredients,
    ...?analysisResult?.detectedRiskIngredients,
  ]) {
    addKey(
      ingredient.normalizedName.isNotEmpty
          ? ingredient.normalizedName
          : ingredient.name,
    );
  }

  for (final token in analysisResult?.unknownIngredients ?? const <String>[]) {
    addKey(_stripComparisonAmountPrefix(token));
  }

  for (final token in analysisResult?.allergenTokens ?? const <String>[]) {
    addKey(token);
  }

  if (hasRawText) {
    for (final token in IngredientCanonicalizer.extractAllergenTokens(
      rawIngredientText!,
    )) {
      addKey(token);
    }
  }

  final values = allergens.toList(growable: false)..sort();
  return values;
}

ProductRiskPreviewItem? _buildRiskPreviewItemFromIngredient(
  Ingredient ingredient, {
  required int originalOrder,
}) {
  final normalizedKey = normalizeIngredientDisplayKey(
    ingredient.normalizedName.isNotEmpty
        ? ingredient.normalizedName
        : ingredient.name,
  );
  if (normalizedKey.isEmpty || _isAllergenOnlyIngredientKey(normalizedKey)) {
    return null;
  }

  final spec = productRiskSpecForKey(normalizedKey);
  final summary = ingredient.shortRiskSummary?.trim().isNotEmpty == true
      ? ingredient.shortRiskSummary!.trim()
      : ingredient.childWarning?.trim();

  if (spec == null &&
      ingredient.riskLevel != 'high' &&
      ingredient.riskLevel != 'medium') {
    return null;
  }

  final dedupeKey = spec?.groupId ?? normalizedKey;
  return ProductRiskPreviewItem(
    name: spec?.displayName ?? ingredient.name.trim(),
    normalizedKey: dedupeKey,
    riskLevel: spec?.riskLevel ?? ingredient.riskLevel,
    originalOrder: originalOrder,
    summary: summary?.isNotEmpty == true ? summary : spec?.riskSummary,
    category: spec?.category,
    ingredient: ingredient,
  );
}

ProductRiskPreviewItem? _buildRiskPreviewItemFromToken(
  String token, {
  required int originalOrder,
}) {
  final normalizedKey = normalizeIngredientDisplayKey(
    _stripComparisonAmountPrefix(token),
  );
  if (normalizedKey.isEmpty || _isAllergenOnlyIngredientKey(normalizedKey)) {
    return null;
  }

  final spec = productRiskSpecForKey(normalizedKey);
  if (spec == null) {
    return null;
  }

  return ProductRiskPreviewItem(
    name: spec.displayName,
    normalizedKey: spec.groupId,
    riskLevel: spec.riskLevel,
    originalOrder: originalOrder,
    summary: spec.riskSummary,
    category: spec.category,
  );
}

String _stripComparisonAmountPrefix(String value) {
  return value
      .replaceFirst(
        RegExp(r'^değişen miktarlarda\s+', caseSensitive: false),
        '',
      )
      .replaceFirst(
        RegExp(r'^degisen miktarlarda\s+', caseSensitive: false),
        '',
      )
      .trim();
}

bool _hasSyrupMarker(String key) {
  return key.contains('şurup') ||
      key.contains('şurub') ||
      key.contains('surup') ||
      key.contains('surub');
}

bool _isAllergenOnlyIngredientKey(String key) {
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

ProductRiskSpec? productRiskSpecForKey(String key) {
  final normalized = normalizeIngredientDisplayKey(key);
  if (normalized.isEmpty) {
    return null;
  }

  if (normalized.contains('aspartam')) {
    return const ProductRiskSpec(
      groupId: 'aspartam',
      displayName: 'Aspartam',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'high',
      riskSummary:
          'Fenilketonüri (PKU) olanların kaçınması gerekir; sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('sukraloz') ||
      normalized.contains('asesülfam') ||
      normalized.contains('asesulfam') ||
      normalized.contains('sakarin')) {
    return ProductRiskSpec(
      groupId: 'intense_sweetener',
      displayName: normalized.contains('sukraloz')
          ? 'Sukraloz'
          : (normalized.contains('sakarin') ? 'Sakarin' : 'Asesülfam K'),
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Yapay tatlandırıcı olarak kullanılır; sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('sorbitol')) {
    return const ProductRiskSpec(
      groupId: 'sorbitol',
      displayName: 'Sorbitol',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Fazla tüketimde sindirim rahatsızlığı yapabilir; paketli tatlılarda dikkat edilebilir.',
    );
  }
  if (_hasSyrupMarker(normalized)) {
    return const ProductRiskSpec(
      groupId: 'sugar_syrup',
      displayName: 'Şeker şurubu',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Sık tüketimde ilave şeker alımını artırır; tüketim sıklığına dikkat edilmelidir.',
    );
  }
  if (normalized.contains('maltodekstrin')) {
    return const ProductRiskSpec(
      groupId: 'maltodextrin',
      displayName: 'Maltodekstrin',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Hızlı sindirilen bir karbonhidrattır; sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('maltitol')) {
    return const ProductRiskSpec(
      groupId: 'maltitol',
      displayName: 'Maltitol (E965)',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Fazla tüketimde sindirim rahatsızlığı yapabilir; kan şekerini tamamen etkilemez ancak sıfır değildir.',
    );
  }
  if (normalized.contains('siklamat') ||
      normalized.contains('cyclamate') ||
      normalized == 'e952' ||
      normalized.contains('e-952') ||
      normalized.contains('e 952')) {
    return const ProductRiskSpec(
      groupId: 'cyclamate',
      displayName: 'Siklamat (E952)',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'AB\'de izin verilmiştir; tatlandırıcı içeren ürünlerde tüketim alışkanlığı ve ürün profili birlikte değerlendirilmelidir.',
    );
  }
  if (normalized.contains('şeker') || normalized.contains('seker')) {
    return const ProductRiskSpec(
      groupId: 'sugar',
      displayName: 'Şeker',
      category: ProductRiskCategory.sweetener,
      riskLevel: 'medium',
      riskSummary:
          'Sık tüketimde ilave şeker alımını artırır; tüketim sıklığına dikkat edilmelidir.',
    );
  }
  if (normalized.contains('palm') || normalized.contains('palmiye')) {
    return const ProductRiskSpec(
      groupId: 'palm',
      displayName: 'Palm yağı',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary:
          'Sık tüketimde doymuş yağ alımını artırabilir; ultra işlenmiş ürünlerde dikkatli olunmalıdır.',
    );
  }
  if (normalized.contains('ayçiçek yağı') ||
      normalized.contains('aycicek yagi')) {
    return const ProductRiskSpec(
      groupId: 'sunflower_oil',
      displayName: 'Ayçiçek yağı',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary:
          'İşlenmiş ürünlerde toplam yağ alımına katkı sağlar; sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('mısır yağı') || normalized.contains('misir yagi')) {
    return const ProductRiskSpec(
      groupId: 'corn_oil',
      displayName: 'Mısır yağı',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary: 'İşlenmiş ürünlerde toplam yağ alımına dikkat edilmelidir.',
    );
  }
  if (normalized.contains('kanola yağı') ||
      normalized.contains('kanola yagi')) {
    return const ProductRiskSpec(
      groupId: 'canola_oil',
      displayName: 'Kanola yağı',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary: 'İşlenmiş ürünlerde toplam yağ alımına dikkat edilmelidir.',
    );
  }
  if (normalized.contains('kakao yağı') || normalized.contains('kakao yagi')) {
    return const ProductRiskSpec(
      groupId: 'cocoa_butter',
      displayName: 'Kakao yağı',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary:
          'Tek başına yüksek riskli değildir; toplam yağ ve şeker yüküyle birlikte değerlendirilmelidir.',
    );
  }
  if (normalized.contains('hidrojenize')) {
    return const ProductRiskSpec(
      groupId: 'hydrogenated_oil',
      displayName: 'Hidrojenize yağ',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary:
          'İşlenmiş yağ yapısı nedeniyle sık tüketimde dikkatli olunmalıdır.',
    );
  }
  if (normalized == 'bitkisel yağlar' ||
      normalized == 'bitkisel yağ' ||
      normalized == 'bitkisel yag') {
    return const ProductRiskSpec(
      groupId: 'vegetable_oil',
      displayName: 'Bitkisel yağ',
      category: ProductRiskCategory.oil,
      riskLevel: 'medium',
      riskSummary:
          'Yağın türü net belirtilmediğinde kalite değerlendirmesi sınırlıdır; toplam yağ alımına dikkat edilmelidir.',
    );
  }
  if (normalized == 'bht' ||
      normalized.contains('b.h.t') ||
      normalized.contains('e321') ||
      normalized.contains('e-321') ||
      normalized.contains('e 321') ||
      normalized.contains('butil hidroksi toluen') ||
      normalized.contains('bütillenmiş hidroksi toluen') ||
      normalized.contains('butylated hydroxytoluene')) {
    return const ProductRiskSpec(
      groupId: 'bht',
      displayName: 'BHT (E321) antioksidan',
      category: ProductRiskCategory.preservative,
      riskLevel: 'medium',
      riskSummary:
          'Yasal sınırlar içinde kullanılır; sık paketli tüketimde toplam alım miktarına dikkat edilmesi önerilir.',
    );
  }
  if (normalized == 'bha' ||
      normalized.contains('b.h.a') ||
      normalized.contains('e320') ||
      normalized.contains('e-320') ||
      normalized.contains('e 320') ||
      normalized.contains('butil hidroksi anizol') ||
      normalized.contains('butylated hydroxyanisole')) {
    return const ProductRiskSpec(
      groupId: 'bha',
      displayName: 'BHA (E320) antioksidan',
      category: ProductRiskCategory.preservative,
      riskLevel: 'medium',
      riskSummary:
          'Yasal sınırlar içinde kullanılır; sık paketli tüketimde toplam alım miktarına dikkat edilmesi önerilir.',
    );
  }
  if (normalized == 'tbhq' ||
      normalized.contains('e319') ||
      normalized.contains('e-319') ||
      normalized.contains('e 319') ||
      normalized.contains('tersiyer butil') ||
      normalized.contains('tertiary butyl')) {
    return const ProductRiskSpec(
      groupId: 'tbhq',
      displayName: 'TBHQ (E319) antioksidan',
      category: ProductRiskCategory.preservative,
      riskLevel: 'medium',
      riskSummary:
          'Yasal sınırlar içinde kullanılır; sık paketli tüketimde toplam alım miktarına dikkat edilmesi önerilir.',
    );
  }
  if (normalized.contains('nitrit') ||
      normalized.contains('nitrat') ||
      normalized.contains('e250') ||
      normalized.contains('e251') ||
      normalized.contains('e249') ||
      normalized.contains('e252')) {
    return const ProductRiskSpec(
      groupId: 'nitrite',
      displayName: 'Nitrit/Nitrat koruyucu',
      category: ProductRiskCategory.preservative,
      riskLevel: 'high',
      riskSummary:
          'İşlenmiş et katkısı olarak sık tüketimde dikkatli olunması önerilir.',
    );
  }
  if (normalized.contains('sorbik asit') ||
      normalized.contains('potasyum sorbat')) {
    return const ProductRiskSpec(
      groupId: 'sorbate',
      displayName: 'Sorbat koruyucu',
      category: ProductRiskCategory.preservative,
      riskLevel: 'low',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('sodyum benzoat') ||
      normalized.contains('benzoik asit')) {
    return const ProductRiskSpec(
      groupId: 'benzoate',
      displayName: 'Benzoat koruyucu',
      category: ProductRiskCategory.preservative,
      riskLevel: 'low',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('tartrazin') || normalized.contains('e102')) {
    return const ProductRiskSpec(
      groupId: 'tartrazine',
      displayName: 'Tartrazin',
      category: ProductRiskCategory.color,
      riskLevel: 'high',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (normalized.contains('allura red') || normalized.contains('e129')) {
    return const ProductRiskSpec(
      groupId: 'allura_red',
      displayName: 'Allura Red',
      category: ProductRiskCategory.color,
      riskLevel: 'high',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (normalized.contains('sunset yellow') || normalized.contains('e110')) {
    return const ProductRiskSpec(
      groupId: 'sunset_yellow',
      displayName: 'Sunset Yellow',
      category: ProductRiskCategory.color,
      riskLevel: 'high',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (normalized.contains('karmin') ||
      normalized.contains('cochineal') ||
      normalized.contains('e120')) {
    return const ProductRiskSpec(
      groupId: 'carmine',
      displayName: 'Karmin (E120)',
      category: ProductRiskCategory.color,
      riskLevel: 'medium',
      riskSummary:
          'Hassas kişilerde alerjik tepkiye yol açabilir; vejetaryen/vegan diyette kullanımına dikkat edilmelidir.',
    );
  }
  if (normalized.contains('brilliant blue') ||
      normalized.contains('parlak mavi') ||
      normalized.contains('e133')) {
    return const ProductRiskSpec(
      groupId: 'brilliant_blue',
      displayName: 'Brilliant Blue (E133)',
      category: ProductRiskCategory.color,
      riskLevel: 'high',
      riskSummary:
          'Hassas kişilerde tepkiye yol açabilir; çocukların sık tüketiminde dikkat edilmelidir.',
    );
  }
  if (normalized.contains('karamel') && normalized.contains('renklendirici')) {
    return const ProductRiskSpec(
      groupId: 'caramel_color',
      displayName: 'Karamel renklendirici',
      category: ProductRiskCategory.color,
      riskLevel: 'medium',
      riskSummary:
          'Ultra işlenmiş ürün göstergesi olabilir; sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('sodyum asit pirofosfat') ||
      normalized.contains('disodyum difosfat') ||
      normalized.contains('difosfat') ||
      normalized == 'e450') {
    return const ProductRiskSpec(
      groupId: 'phosphate_leavening',
      displayName: 'Fosfat bazlı kabartıcı',
      category: ProductRiskCategory.leavening,
      riskLevel: 'medium',
      riskSummary:
          'Fosfat katkısı olduğu için sık paketli ürün tüketiminde dikkat edilebilir.',
    );
  }
  if (normalized.contains('sodyum hidrojen karbonat') ||
      normalized.contains('sodyum bikarbonat') ||
      normalized == 'karbonat' ||
      normalized == 'e500') {
    return const ProductRiskSpec(
      groupId: 'carbonate_leavening',
      displayName: 'Karbonat bazlı kabartıcı',
      category: ProductRiskCategory.leavening,
      riskLevel: 'low',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; paketli ürün göstergesi olarak değerlendirilebilir.',
    );
  }
  if (normalized.contains('poligliserol') ||
      normalized == 'pgpr' ||
      normalized == 'e476') {
    return const ProductRiskSpec(
      groupId: 'pgpr',
      displayName: 'Çikolata emülgatörü',
      category: ProductRiskCategory.emulsifier,
      riskLevel: 'low',
      riskSummary:
          'Tek başına yüksek riskli değildir; ultra işlenmiş ürünlerde katkı göstergesi olabilir.',
    );
  }
  if (normalized.contains('mono ve digliserit') ||
      normalized.contains('mono- ve digliserit')) {
    return const ProductRiskSpec(
      groupId: 'mono_diglyceride',
      displayName: 'Mono ve digliseritler',
      category: ProductRiskCategory.emulsifier,
      riskLevel: 'low',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; ultra işlenmiş ürün göstergesi olabilir.',
    );
  }
  if (normalized.contains('ksantan gam')) {
    return const ProductRiskSpec(
      groupId: 'xanthan',
      displayName: 'Ksantan gam',
      category: ProductRiskCategory.emulsifier,
      riskLevel: 'low',
      riskSummary:
          'Genel olarak düşük dikkat düzeyindedir; ultra işlenmiş ürün göstergesi olabilir.',
    );
  }
  if (normalized.contains('karragenan') ||
      normalized.contains('karagenan') ||
      normalized.contains('karraginan') ||
      normalized.contains('carrageenan') ||
      normalized.contains('e407')) {
    return const ProductRiskSpec(
      groupId: 'carrageenan',
      displayName: 'Karragenan (E407)',
      category: ProductRiskCategory.emulsifier,
      riskLevel: 'medium',
      riskSummary:
          'Sindirim sistemi hassasiyeti olanlarda dikkat edilmesi önerilir; sık tüketimde toplam katkı yüküne dikkat edilebilir.',
    );
  }
  if (normalized.contains('soya lesitini') ||
      normalized.contains('soya lesitin') ||
      normalized.contains('soy lecithin') ||
      normalized.contains('e322')) {
    return const ProductRiskSpec(
      groupId: 'soy_lecithin',
      displayName: 'Soya lesitini (E322)',
      category: ProductRiskCategory.emulsifier,
      riskLevel: 'low',
      riskSummary:
          'Soya alerjisi olanlar için dikkat gerektirmektedir; genel tüketimde düşük risk düzeyindedir.',
    );
  }
  if (normalized == 'tuz') {
    return const ProductRiskSpec(
      groupId: 'salt',
      displayName: 'Tuz',
      category: ProductRiskCategory.other,
      riskLevel: 'medium',
      riskSummary:
          'Sık tüketimde toplam sodyum alımını artırabilir; tuz hassasiyeti olanlar dikkat etmelidir.',
    );
  }
  if (normalized.contains('monosodyum glutamat')) {
    return const ProductRiskSpec(
      groupId: 'msg',
      displayName: 'Çeşni artırıcı (MSG)',
      category: ProductRiskCategory.other,
      riskLevel: 'medium',
      riskSummary:
          'İzin verilen miktarlarda kullanılır; hassas kişilerde sık tüketimde dikkat edilebilir.',
    );
  }
  if (normalized.contains('kafein') ||
      normalized.contains('taurin') ||
      normalized.contains('guarana') ||
      normalized.contains('ginseng') ||
      normalized.contains('l-karnitin')) {
    return ProductRiskSpec(
      groupId: 'stimulant',
      displayName: normalized.contains('kafein')
          ? 'Kafein'
          : (normalized.contains('taurin')
                ? 'Taurin'
                : (normalized.contains('guarana')
                      ? 'Guarana'
                      : 'Uyarıcı katkı')),
      category: ProductRiskCategory.other,
      riskLevel: 'medium',
      riskSummary:
          'Çocuklar ve hassas kişiler için sık tüketimde dikkatli olunmalıdır.',
    );
  }

  return null;
}

void showIngredientDetailSheet(BuildContext context, Ingredient ingredient) {
  final resolvedIngredient = enrichIngredientKnowledge(ingredient);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final maxHeight = MediaQuery.of(context).size.height * 0.82;
      final canonicalRisk = canonicalRiskLevelForIngredient(ingredient);
      final riskLabel = riskLabelForUser(canonicalRisk);
      final riskColor = riskColorForUser(canonicalRisk);

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
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        resolvedIngredient.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Kapat',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: riskColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$riskLabel${(resolvedIngredient.ingredientType?.trim().isNotEmpty ?? false) ? ' · ${resolvedIngredient.ingredientType!}' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                IngredientDetailSections(ingredient: resolvedIngredient),
              ],
            ),
          ),
        ),
      );
    },
  );
}

ProductNutrientVisualData _sugarRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value > 22.5) {
    tone = ProductNutrientTone.high;
    label = 'Yüksek';
  } else if (value > 5.0) {
    tone = ProductNutrientTone.medium;
    label = 'Orta';
  } else {
    tone = ProductNutrientTone.low;
    label = 'Düşük';
  }
  return ProductNutrientVisualData(
    key: 'sugars',
    label: 'Şeker',
    icon: Icons.cake_outlined,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

ProductNutrientVisualData _saltRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value > 1.5) {
    tone = ProductNutrientTone.high;
    label = 'Yüksek';
  } else if (value > 0.3) {
    tone = ProductNutrientTone.medium;
    label = 'Orta';
  } else {
    tone = ProductNutrientTone.low;
    label = 'Düşük';
  }
  return ProductNutrientVisualData(
    key: 'salt',
    label: 'Tuz',
    icon: Icons.grain_outlined,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

ProductNutrientVisualData _satFatRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value > 5.0) {
    tone = ProductNutrientTone.high;
    label = 'Yüksek';
  } else if (value > 1.5) {
    tone = ProductNutrientTone.medium;
    label = 'Orta';
  } else {
    tone = ProductNutrientTone.low;
    label = 'Düşük';
  }
  return ProductNutrientVisualData(
    key: 'saturated_fat',
    label: 'Doymuş Yağ',
    icon: Icons.opacity,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

ProductNutrientVisualData _fatRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value > 17.5) {
    tone = ProductNutrientTone.high;
    label = 'Yüksek';
  } else if (value > 3.0) {
    tone = ProductNutrientTone.medium;
    label = 'Orta';
  } else {
    tone = ProductNutrientTone.low;
    label = 'Düşük';
  }
  return ProductNutrientVisualData(
    key: 'fat',
    label: 'Yağ',
    icon: Icons.water_drop_outlined,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

ProductNutrientVisualData _fiberRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value >= 6.0) {
    tone = ProductNutrientTone.strongPositive;
    label = 'Çok iyi';
  } else if (value >= 3.0) {
    tone = ProductNutrientTone.positive;
    label = 'İyi';
  } else {
    tone = ProductNutrientTone.neutral;
    label = 'Bilgi amaçlı';
  }
  return ProductNutrientVisualData(
    key: 'fiber',
    label: 'Lif',
    icon: Icons.eco_outlined,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

ProductNutrientVisualData _proteinRow(double? value) {
  ProductNutrientTone tone;
  String label;
  if (value == null) {
    tone = ProductNutrientTone.neutral;
    label = '';
  } else if (value >= 12.0) {
    tone = ProductNutrientTone.strongPositive;
    label = 'Çok iyi';
  } else if (value >= 5.0) {
    tone = ProductNutrientTone.positive;
    label = 'İyi';
  } else {
    tone = ProductNutrientTone.neutral;
    label = 'Bilgi amaçlı';
  }
  return ProductNutrientVisualData(
    key: 'proteins',
    label: 'Protein',
    icon: Icons.fitness_center_outlined,
    value: value,
    unit: 'g',
    tone: tone,
    assessmentLabel: label,
  );
}

int _riskRank(String level) {
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
