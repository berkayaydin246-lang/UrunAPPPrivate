import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/ingredient_risk_reference.dart';

final DateTime _catalogAccessedAt = DateTime.utc(2026, 6, 27);

final IngredientRiskReference _whoHealthyDietReference =
    IngredientRiskReference(
      authority: 'WHO',
      title: 'Healthy diet',
      url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
      accessedAt: _catalogAccessedAt,
    );

final IngredientRiskReference _whoSugarsGuidelineReference =
    IngredientRiskReference(
      authority: 'WHO',
      title: 'Guideline: Sugars intake for adults and children',
      url: 'https://www.who.int/publications/i/item/9789241549028',
      accessedAt: _catalogAccessedAt,
    );

final IngredientRiskReference _whoSodiumGuidelineReference =
    IngredientRiskReference(
      authority: 'WHO',
      title: 'Guideline: Sodium intake for adults and children',
      url: 'https://www.who.int/publications/i/item/9789241504836',
      accessedAt: _catalogAccessedAt,
    );

final IngredientRiskReference
_whoSatFatGuidelineReference = IngredientRiskReference(
  authority: 'WHO',
  title:
      'Saturated fatty acid and trans-fatty acid intake for adults and children',
  url: 'https://www.who.int/publications/i/item/9789240073630',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _whoNonSugarSweetenerReference =
    IngredientRiskReference(
      authority: 'WHO',
      title: 'Use of non-sugar sweeteners: WHO guideline',
      url: 'https://www.who.int/publications/i/item/9789240073616',
      accessedAt: _catalogAccessedAt,
    );

final IngredientRiskReference _fdaSweetenersReference = IngredientRiskReference(
  authority: 'FDA',
  title: 'Aspartame and Other Sweeteners in Food',
  url:
      'https://www.fda.gov/food/food-additives-petitions/aspartame-and-other-sweeteners-food',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference
_fdaHighIntensitySweetenersReference = IngredientRiskReference(
  authority: 'FDA',
  title: 'High-Intensity Sweeteners',
  url:
      'https://www.fda.gov/food/food-additives-petitions/high-intensity-sweeteners',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference
_fdaSweetenerOverviewReference = IngredientRiskReference(
  authority: 'FDA',
  title: 'How Sweet It Is: All About Sweeteners',
  url:
      'https://www.fda.gov/consumers/consumer-updates/how-sweet-it-all-about-sweeteners',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference
_fdaFoodAllergiesReference = IngredientRiskReference(
  authority: 'FDA',
  title: 'Food Allergies',
  url:
      'https://www.fda.gov/food/nutrition-food-labeling-and-critical-foods/food-allergies',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference
_commissionAdditivesOverviewReference = IngredientRiskReference(
  authority: 'European Commission',
  title: 'Food additives',
  url:
      'https://food.ec.europa.eu/food-safety/food-improvement-agents/additives_en',
  accessedAt: _catalogAccessedAt,
);

IngredientRiskReference _commissionDatabaseReference({
  required String documentCode,
  required String note,
}) {
  return IngredientRiskReference(
    authority: 'European Commission',
    title: 'Food additives database',
    url:
        'https://food.ec.europa.eu/food-safety/food-improvement-agents/additives/database_en',
    accessedAt: _catalogAccessedAt,
    documentCode: documentCode,
    note: note,
  );
}

final IngredientRiskReference
_efsaColourSafetyReference = IngredientRiskReference(
  authority: 'EFSA',
  title:
      'Scientific Opinion on the re-evaluation of six food colours (E102, E104, E110, E122, E129, E160e)',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/2306',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _efsaE133Reference = IngredientRiskReference(
  authority: 'EFSA',
  title: 'Re-evaluation of Brilliant Blue FCF (E133)',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/3433',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _efsaNitriteReference = IngredientRiskReference(
  authority: 'EFSA',
  title:
      'Re-evaluation of sodium nitrite (E 250), potassium nitrite (E 249), sodium nitrate (E 251) and potassium nitrate (E 252)',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/5235',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference
_whoProcessedMeatReference = IngredientRiskReference(
  authority: 'WHO/IARC',
  title: 'Carcinogenicity of consumption of red and processed meat',
  url:
      'https://www.thelancet.com/journals/lanonc/article/PIIS1470-2045(15)00444-1/fulltext',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _efsaMsgReference = IngredientRiskReference(
  authority: 'EFSA',
  title:
      'Re-evaluation of glutamic acid (E620), sodium glutamate (E621), potassium glutamate (E622), calcium glutamate (E623), ammonium glutamate (E624) and magnesium glutamate (E625) as food additives',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/4910',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _efsaMaltodextrinReference =
    IngredientRiskReference(
      authority: 'EFSA',
      title: 'Scientific Opinion on the safety of maltodextrin as a novel food',
      url: 'https://www.efsa.europa.eu/en/efsajournal/pub/5526',
      accessedAt: _catalogAccessedAt,
    );

final IngredientRiskReference _efsaE120Reference = IngredientRiskReference(
  authority: 'EFSA',
  title: 'Re-evaluation of cochineal, carminic acid, carmines (E 120)',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/3995',
  accessedAt: _catalogAccessedAt,
);

final IngredientRiskReference _efsaCyclamateReference = IngredientRiskReference(
  authority: 'EFSA',
  title: 'Scientific Opinion on the safety of cyclamates as food additives',
  url: 'https://www.efsa.europa.eu/en/efsajournal/pub/4784',
  accessedAt: _catalogAccessedAt,
);

Ingredient enrichIngredientKnowledge(Ingredient ingredient) {
  final entry = _ingredientCatalogEntryForIngredient(ingredient);
  if (entry == null) {
    return ingredient;
  }

  final mergedReferences = _mergeReferenceLists(
    ingredient.sourceReferenceEntries,
    entry.references,
  );
  final mergedReferenceStrings = _mergeStringLists(
    ingredient.sourceReferences,
    (mergedReferences ?? const <IngredientRiskReference>[])
        .map((reference) => reference.toDisplayString())
        .toList(),
  );

  final resolvedECode = isValidFoodAdditiveCode(ingredient.eCode)
      ? ingredient.eCode!.trim().toUpperCase()
      : entry.eCode;

  return Ingredient(
    id: ingredient.id,
    name: ingredient.name,
    normalizedName: ingredient.normalizedName,
    alternativeNames: ingredient.alternativeNames,
    aliases: _mergeStringLists(ingredient.aliases, entry.aliases),
    commonNames: ingredient.commonNames,
    englishNames: ingredient.englishNames,
    eCode: resolvedECode,
    category: ingredient.category,
    // Preserve DB riskLevel when it's explicitly set; fall back to catalog only
    // for 'unknown'. The severity badge is resolved separately via
    // canonicalRiskLevelForIngredient() which looks up the spec function.
    riskLevel: ingredient.riskLevel == 'unknown'
        ? entry.riskLevel
        : ingredient.riskLevel,
    shortDescription: ingredient.shortDescription,
    longDescription: ingredient.longDescription,
    additiveGroup: ingredient.additiveGroup,
    childWarning: ingredient.childWarning,
    sourceReferences: mergedReferenceStrings,
    sourceReferenceEntries: mergedReferences,
    sourceUrl: ingredient.sourceUrl,
    // Catalog wins for educational content — DB may contain auto-generated text.
    // Fall back to DB content only when the catalog has nothing for that field.
    ingredientType: _preferExisting(
      entry.ingredientType,
      ingredient.ingredientType ?? '',
    ),
    shortPurpose: _preferExisting(
      entry.shortPurpose,
      ingredient.shortPurpose ?? '',
    ),
    shortRiskSummary: _preferExisting(
      entry.shortRiskSummary,
      ingredient.shortRiskSummary ?? '',
    ),
    cautionGroups: (entry.cautionGroups?.isNotEmpty ?? false)
        ? entry.cautionGroups
        : ingredient.cautionGroups,
    processingRole: _preferExistingNullable(
      entry.processingRole,
      ingredient.processingRole,
    ),
    createdAt: ingredient.createdAt,
    updatedAt: ingredient.updatedAt,
  );
}

_IngredientCatalogEntry? _ingredientCatalogEntryForIngredient(
  Ingredient ingredient,
) {
  final forms =
      <String>{
            ingredient.name,
            ingredient.normalizedName,
            ingredient.eCode ?? '',
            ...?ingredient.aliases,
            ...?ingredient.alternativeNames,
            ...?ingredient.commonNames,
            ...?ingredient.englishNames,
          }
          .map(_normalizeKey)
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

  for (final entry in _catalogEntries) {
    if (entry.matches(forms)) {
      return entry;
    }
  }
  return null;
}

bool ingredientHasExplanationMetadata(Ingredient ingredient) {
  return (ingredient.ingredientType?.trim().isNotEmpty ?? false) ||
      (ingredient.shortPurpose?.trim().isNotEmpty ?? false) ||
      (ingredient.shortRiskSummary?.trim().isNotEmpty ?? false) ||
      (ingredient.cautionGroups?.isNotEmpty ?? false) ||
      (ingredient.processingRole?.trim().isNotEmpty ?? false);
}

bool isValidFoodAdditiveCode(String? value) {
  final code = value?.trim().toUpperCase();
  if (code == null || code.isEmpty) {
    return false;
  }
  return RegExp(
    r'^E\d{3,4}(?:[A-Z]|\([IVX]+\))?$',
    caseSensitive: false,
  ).hasMatch(code);
}

String _preferExisting(String? current, String fallback) {
  final trimmed = current?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  return fallback;
}

String? _preferExistingNullable(String? current, String? fallback) {
  final trimmed = current?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  final fallbackTrimmed = fallback?.trim();
  if (fallbackTrimmed != null && fallbackTrimmed.isNotEmpty) {
    return fallbackTrimmed;
  }
  return null;
}

List<String>? _mergeStringLists(List<String>? first, List<String>? second) {
  final merged = <String>[];
  final seen = <String>{};

  void addAll(Iterable<String>? values) {
    if (values == null) return;
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        merged.add(trimmed);
      }
    }
  }

  addAll(first);
  addAll(second);
  return merged.isEmpty ? null : merged;
}

List<IngredientRiskReference>? _mergeReferenceLists(
  List<IngredientRiskReference>? first,
  List<IngredientRiskReference>? second,
) {
  final merged = <IngredientRiskReference>[];
  final seen = <String>{};

  void addAll(Iterable<IngredientRiskReference>? values) {
    if (values == null) return;
    for (final value in values) {
      final key = [
        value.authority,
        value.title,
        value.documentCode ?? '',
        value.url,
      ].join('|').toLowerCase();
      if (seen.add(key)) {
        merged.add(value);
      }
    }
  }

  addAll(first);
  addAll(second);
  return merged.isEmpty ? null : merged;
}

String _normalizeKey(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'^[\s,.;:/\-–—()]+|[\s,.;:/\-–—()]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _IngredientCatalogEntry {
  const _IngredientCatalogEntry({
    required this.aliases,
    this.containsAny = const <String>[],
    this.eCode,
    required this.ingredientType,
    required this.shortPurpose,
    required this.shortRiskSummary,
    this.cautionGroups,
    this.processingRole,
    required this.riskLevel,
    required this.references,
  });

  final List<String> aliases;
  final List<String> containsAny;
  final String? eCode;
  final String ingredientType;
  final String shortPurpose;
  final String shortRiskSummary;
  final List<String>? cautionGroups;
  final String? processingRole;
  final String riskLevel;
  final List<IngredientRiskReference> references;

  bool matches(List<String> forms) {
    final aliasKeys = aliases.map(_normalizeKey).toSet();
    final containsKeys = containsAny.map(_normalizeKey).toList(growable: false);

    for (final form in forms) {
      if (aliasKeys.contains(form)) {
        return true;
      }
      for (final token in containsKeys) {
        if (token.isNotEmpty && form.contains(token)) {
          return true;
        }
      }
      if (eCode != null && form == eCode!.toLowerCase()) {
        return true;
      }
    }
    return false;
  }
}

final List<_IngredientCatalogEntry> _catalogEntries = [
  _IngredientCatalogEntry(
    aliases: const ['soya lesitini', 'soy lecithin'],
    containsAny: const ['soya lesitini'],
    eCode: 'E322',
    ingredientType: 'Emülgatör',
    shortPurpose:
        'Soya lesitini, yağ ve su fazını daha dengeli tutmak için kullanılan bir emülgatördür.',
    shortRiskSummary:
        'Genellikle düşük dikkat düzeyindedir. Soya kaynağı içerdiği için etiketteki alerjen bilgisini takip eden kullanıcılar bunu ayrıca değerlendirebilir.',
    cautionGroups: const ['soya bildirimi takip edenler'],
    processingRole:
        'Çikolata, kremalı dolgular ve bazı fırıncılık ürünlerinde görülebilir.',
    riskLevel: 'low',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E322',
        note: 'Lesitinler için AB katkı maddesi veri tabanı girişi.',
      ),
      _fdaFoodAllergiesReference,
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['lesitin', 'lecithin', 'lecithins'],
    containsAny: const ['lesitin'],
    eCode: 'E322',
    ingredientType: 'Emülgatör',
    shortPurpose:
        'Lesitin, yağ ve su fazını kararlı tutmaya ve ürün dokusunu desteklemeye yardımcı olan bir emülgatördür.',
    shortRiskSummary:
        'Genellikle düşük dikkat düzeyindedir. Kaynağı soya, ayçiçeği veya yumurta olabileceği için etiket bilgisi ürün bazında kontrol edilmelidir.',
    processingRole:
        'Çikolata, sos, kremalı ürün ve fırıncılık karışımlarında kullanılabilir.',
    riskLevel: 'low',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E322',
        note: 'Lesitinler için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['potasyum sorbat', 'potassium sorbate'],
    containsAny: const ['potasyum sorbat'],
    eCode: 'E202',
    ingredientType: 'Koruyucu',
    shortPurpose:
        'Potasyum sorbat, küf ve maya gelişimini sınırlamak için kullanılan bir koruyucudur.',
    shortRiskSummary:
        'Mevzuatta izin verilen kullanım koşullarında değerlendirilir. Etiketly bunu katkı yoğunluğunu daha görünür kılmak için bilgi amaçlı gösterir.',
    processingRole:
        'Soslar, içecekler, unlu mamuller ve bazı sütlü ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E202',
        note: 'Potasyum sorbat için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sorbik asit', 'sorbic acid'],
    containsAny: const ['sorbik asit'],
    eCode: 'E200',
    ingredientType: 'Koruyucu',
    shortPurpose:
        'Sorbik asit, ürünün raf ömrünü desteklemek ve maya ile küf gelişimini sınırlamak için kullanılabilir.',
    shortRiskSummary:
        'Mevzuatta izin verilen kullanım koşullarında değerlendirilir. Etiketly bunu içerik profilini daha anlaşılır göstermek için bilgi amaçlı listeler.',
    processingRole: 'Asidik gıdalar ve çeşitli paketli ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E200',
        note: 'Sorbik asit için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sodyum benzoat', 'sodium benzoate'],
    containsAny: const ['sodyum benzoat'],
    eCode: 'E211',
    ingredientType: 'Koruyucu',
    shortPurpose:
        'Sodyum benzoat, belirli ürünlerde mikrobiyal gelişimi sınırlamak için kullanılan bir koruyucudur.',
    shortRiskSummary:
        'Mevzuatta izin verilen kullanım koşullarında değerlendirilir. Etiketly bunu ürünün katkı yapısını daha şeffaf göstermek için bilgi amaçlı listeler.',
    processingRole: 'İçecek, sos ve çeşitli paketli ürünlerde kullanılabilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E211',
        note: 'Sodyum benzoat için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['benzoik asit', 'benzoic acid'],
    containsAny: const ['benzoik asit'],
    eCode: 'E210',
    ingredientType: 'Koruyucu',
    shortPurpose:
        'Benzoik asit, belirli ürünlerde raf ömrünü desteklemek için kullanılan bir koruyucu bileşendir.',
    shortRiskSummary:
        'Mevzuatta izin verilen kullanım koşullarında değerlendirilir. Etiketly bunu içerik şeffaflığı için bilgi amaçlı gösterir.',
    processingRole:
        'Asidik içecekler, soslar ve benzeri paketli ürünlerde bulunabilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E210',
        note: 'Benzoik asit için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'bht',
      'b.h.t.',
      'butil hidroksi toluen',
      'bütillenmiş hidroksitoluen',
      'butylated hydroxytoluene',
    ],
    containsAny: const [
      'bht',
      'b.h.t',
      'butil hidroksi toluen',
      'bütillenmiş hidroksi toluen',
      'butylated hydroxytoluene',
    ],
    eCode: 'E321',
    ingredientType: 'Yapay antioksidan',
    shortPurpose:
        'BHT, yağların ve yağ içeren ürünlerin bozulmasını yavaşlatmak için kullanılan yapay bir antioksidandır.',
    shortRiskSummary:
        'Türk Gıda Kodeksi ve AB mevzuatında izin verilen sınır değerler çerçevesinde kullanılır. Sık paketli ürün tüketiminde toplam katkı alımına dikkat edilmesi önerilir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['sık paketli ürün tüketicileri'],
    processingRole:
        'Cips, bisküvi, gıda ambalaj malzemeleri ve yağlı işlenmiş ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E321',
        note: 'BHT için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'bha',
      'b.h.a.',
      'butil hidroksi anizol',
      'bütillenmiş hidroksianizol',
      'butylated hydroxyanisole',
    ],
    containsAny: const [
      'bha',
      'b.h.a',
      'butil hidroksi anizol',
      'butylated hydroxyanisole',
    ],
    eCode: 'E320',
    ingredientType: 'Yapay antioksidan',
    shortPurpose:
        'BHA, yağ içeren gıdalarda oksidasyonu yavaşlatmak ve raf ömrünü uzatmak için kullanılan yapay bir antioksidandır.',
    shortRiskSummary:
        'Türk Gıda Kodeksi ve AB mevzuatında izin verilen sınır değerler çerçevesinde kullanılır. Sık paketli ürün tüketiminde toplam katkı alımına dikkat edilmesi önerilir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['sık paketli ürün tüketicileri'],
    processingRole:
        'Yağlı atıştırmalıklar, bisküvi ve bazı işlenmiş gıdalarda bulunabilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E320',
        note: 'BHA için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'tbhq',
      'tersiyer butil hidrokikinon',
      'tersiyer bütilhidrokinon',
      'tertiary butylhydroquinone',
    ],
    containsAny: const ['tbhq', 'tersiyer butil', 'tertiary butyl'],
    eCode: 'E319',
    ingredientType: 'Yapay antioksidan',
    shortPurpose:
        'TBHQ, bitkisel yağlar ve yağ içeren işlenmiş gıdalarda bozulmayı önlemek için kullanılan yapay bir antioksidandır.',
    shortRiskSummary:
        'Türk Gıda Kodeksi ve AB mevzuatında izin verilen sınır değerler çerçevesinde kullanılır. Sık paketli ürün tüketiminde toplam katkı alımına dikkat edilmesi önerilir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['sık paketli ürün tüketicileri'],
    processingRole:
        'Bitkisel yağlar, hazır yemekler ve çeşitli işlenmiş atıştırmalıklarda görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E319',
        note: 'TBHQ için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['aspartam', 'aspartame'],
    containsAny: const ['aspartam'],
    eCode: 'E951',
    ingredientType: 'Yoğun tatlandırıcı',
    shortPurpose:
        'Aspartam, daha az şekerle tatlılık sağlamak amacıyla kullanılan yoğun tatlandırıcılardan biridir.',
    shortRiskSummary:
        'Tatlandırıcı içeren ürünler tek başına daha dengeli bir seçim anlamına gelmez; ürünün tamamı ve tüketim sıklığı birlikte değerlendirilmelidir.',
    processingRole:
        'Şekersiz içecekler, sakızlar ve tatlandırılmış hafif ürünlerde görülebilir.',
    riskLevel: 'high',
    references: [
      _whoNonSugarSweetenerReference,
      _fdaSweetenersReference,
      _commissionDatabaseReference(
        documentCode: 'E951',
        note: 'Aspartam için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'asesülfam k',
      'acesulfame k',
      'acesulfame potassium',
      'asesülfam potasyum',
    ],
    containsAny: const ['asesülfam', 'acesulfame'],
    eCode: 'E950',
    ingredientType: 'Yoğun tatlandırıcı',
    shortPurpose:
        'Asesülfam K, ürünlere düşük miktarda tatlılık vermek için kullanılan yoğun tatlandırıcılardan biridir.',
    shortRiskSummary:
        'Tatlandırıcı içeren ürünler değerlendirilirken ürünün genel beslenme profili ve tüketim alışkanlığı birlikte düşünülmelidir.',
    processingRole:
        'Şekersiz içecekler, tatlandırılmış süt ürünleri ve sakızlarda görülebilir.',
    riskLevel: 'medium',
    references: [
      _whoNonSugarSweetenerReference,
      _fdaHighIntensitySweetenersReference,
      _commissionDatabaseReference(
        documentCode: 'E950',
        note: 'Asesülfam K için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sakarin', 'saccharin'],
    containsAny: const ['sakarin'],
    eCode: 'E954',
    ingredientType: 'Yoğun tatlandırıcı',
    shortPurpose:
        'Sakarin, şeker yerine yüksek tatlılık sağlayabilen yoğun tatlandırıcılardan biridir.',
    shortRiskSummary:
        'Tatlandırıcı kullanılan ürünlerde değerlendirme yalnızca bu bileşene değil, ürünün genel içeriğine ve tüketim sıklığına göre yapılmalıdır.',
    processingRole:
        'Şekersiz içecek, masaüstü tatlandırıcı ve sakız ürünlerinde görülebilir.',
    riskLevel: 'medium',
    references: [
      _whoNonSugarSweetenerReference,
      _fdaHighIntensitySweetenersReference,
      _commissionDatabaseReference(
        documentCode: 'E954',
        note: 'Sakarin ve tuzları için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sukraloz', 'sucralose'],
    containsAny: const ['sukraloz'],
    eCode: 'E955',
    ingredientType: 'Yoğun tatlandırıcı',
    shortPurpose:
        'Sukraloz, düşük miktarda tatlılık sağlamak için kullanılan yoğun tatlandırıcılardan biridir.',
    shortRiskSummary:
        'Tatlandırıcı içeren ürünler değerlendirilirken ürünün toplam beslenme profili ve tüketim alışkanlığı birlikte düşünülmelidir.',
    processingRole:
        'Şekersiz içecekler, hafif tatlılar ve masaüstü tatlandırıcılarda görülebilir.',
    riskLevel: 'medium',
    references: [
      _whoNonSugarSweetenerReference,
      _fdaHighIntensitySweetenersReference,
      _commissionDatabaseReference(
        documentCode: 'E955',
        note: 'Sukraloz için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sorbitol şurubu', 'sorbitol syrup'],
    containsAny: const ['sorbitol şurubu'],
    eCode: 'E420(II)',
    ingredientType: 'Tatlandırıcı / hacim verici',
    shortPurpose:
        'Sorbitol şurubu, şekersiz veya azaltılmış şekerli ürünlerde tat, hacim ve nem dengesini desteklemek için kullanılabilir.',
    shortRiskSummary:
        'Şeker alkolleri içeren ürünler değerlendirilirken porsiyon miktarı ve ürünün toplam tatlandırıcı bileşimi birlikte düşünülmelidir.',
    processingRole:
        'Şekersiz şekerleme, sakız ve bazı fırıncılık ürünlerinde görülebilir.',
    riskLevel: 'medium',
    references: [
      _fdaSweetenerOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E420(ii)',
        note: 'Sorbitol şurubu için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sorbitol'],
    containsAny: const ['sorbitol'],
    eCode: 'E420(I)',
    ingredientType: 'Tatlandırıcı / hacim verici',
    shortPurpose:
        'Sorbitol, bazı ürünlerde şeker yerine tat ve hacim sağlamak için kullanılan bir şeker alkolüdür.',
    shortRiskSummary:
        'Şeker alkolleri içeren ürünler değerlendirilirken porsiyon miktarı ve ürünün toplam tatlandırıcı bileşimi birlikte düşünülmelidir.',
    processingRole:
        'Şekersiz şekerlemeler, sakızlar ve bazı özel formülasyonlarda görülebilir.',
    riskLevel: 'medium',
    references: [
      _fdaSweetenerOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E420(i)',
        note: 'Sorbitol için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['mono ve digliseritler', 'mono and diglycerides'],
    containsAny: const ['mono ve digliserit'],
    eCode: 'E471',
    ingredientType: 'Emülgatör',
    shortPurpose:
        'Mono ve digliseritler, yağ ve su fazını daha kararlı tutmaya yardımcı olan emülgatörlerdir.',
    shortRiskSummary:
        'Bu bileşen genellikle ürün yapısını desteklemek için kullanılır. Etiketly bunu katkı yoğunluğunu daha anlaşılır göstermek için bilgi amaçlı listeler.',
    processingRole:
        'Fırıncılık ürünleri, dondurulmuş tatlılar ve kremalı ürünlerde kullanılabilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E471',
        note: 'Mono ve digliseritler için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['karagenan', 'carrageenan'],
    containsAny: const ['karagenan', 'carrageenan'],
    eCode: 'E407',
    ingredientType: 'Kıvam arttırıcı',
    shortPurpose:
        'Karagenan, kıvamı ve stabiliteyi desteklemek için kullanılan bir jel/kıvam bileşenidir.',
    shortRiskSummary:
        'Etiketly bunu ürünün katkı yapısını daha görünür kılmak için bilgi amaçlı gösterir. Değerlendirme ürünün tamamı ile birlikte yapılmalıdır.',
    processingRole:
        'Sütlü tatlılar, bitkisel içecekler ve soslarda görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E407',
        note: 'Karagenan için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['guar gam', 'guar gum'],
    containsAny: const ['guar gam', 'guar gum'],
    eCode: 'E412',
    ingredientType: 'Kıvam arttırıcı',
    shortPurpose:
        'Guar gam, kıvamı ve homojen yapıyı desteklemek için kullanılan bir stabilizatördür.',
    shortRiskSummary:
        'Etiketly bunu ürünün katkı profiline görünürlük kazandırmak için bilgi amaçlı listeler. Değerlendirme ürünün tamamı ile birlikte yapılmalıdır.',
    processingRole:
        'Dondurma, sos, içecek ve glutensiz karışımlarda görülebilir.',
    riskLevel: 'low',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E412',
        note: 'Guar gam için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['ksantan gam', 'xanthan gum'],
    containsAny: const ['ksantan gam', 'xanthan gum'],
    eCode: 'E415',
    ingredientType: 'Kıvam arttırıcı',
    shortPurpose:
        'Ksantan gam, kıvamı, akış davranışını ve ürün stabilitesini desteklemek için kullanılan bir bileşendir.',
    shortRiskSummary:
        'Etiketly bunu katkı yapısına görünürlük kazandırmak için bilgi amaçlı listeler. Değerlendirme ürünün bütünü ile birlikte yapılmalıdır.',
    processingRole:
        'Soslar, içecekler ve glutensiz veya düşük yağlı ürünlerde görülebilir.',
    riskLevel: 'low',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E415',
        note: 'Ksantan gam için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['karamel renklendirici', 'karamel renklendiricisi'],
    containsAny: const ['karamel renklendirici', 'caramel colour'],
    ingredientType: 'Renklendirici',
    shortPurpose:
        'Karamel renklendirici, ürüne kahverengi tonlar vermek için kullanılan bir renklendirici grubudur.',
    shortRiskSummary:
        'Bu ifade birden fazla alt türü kapsayabildiği için E-kodu ancak spesifik alt tür açıkça belirtilirse gösterilmelidir. Etiketly bunu etiket şeffaflığı için bilgi amaçlı listeler.',
    processingRole:
        'Koyu renkli içecekler, soslar, bisküviler ve bazı tatlı ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _commissionAdditivesOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E150',
        note:
            'Karamel renklendirici grubu için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['palm yağı', 'palmiye yağı', 'palm oil'],
    containsAny: const ['palm yağı', 'palmiye yağı', 'palm oil'],
    ingredientType: 'Bitkisel yağ',
    shortPurpose:
        'Palm yağı, bazı paketli gıdalarda doku, kıvam ve raf ömrünü desteklemek için kullanılan bitkisel bir yağdır.',
    shortRiskSummary:
        'Doymuş yağ oranı yüksek olabildiği için Etiketly bu maddeyi dikkat edilmesi gereken içerikler arasında gösterir. Değerlendirme ürünün tamamı, porsiyon miktarı ve tüketim sıklığı ile birlikte düşünülmelidir.',
    cautionGroups: const ['doymuş yağ alımını sınırlayanlar'],
    processingRole:
        'Atıştırmalıklar, kremalı dolgular ve bazı fırıncılık ürünlerinde görülebilir.',
    riskLevel: 'medium',
    references: [_whoSatFatGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['bitkisel yağ', 'nebati yağ', 'vegetable oil'],
    containsAny: const ['bitkisel yağ', 'nebati yağ'],
    ingredientType: 'Bitkisel yağ',
    shortPurpose:
        'Bitkisel yağ ifadesi, ürünün yağ fazını ve dokusunu destekleyen bir veya birden fazla yağın genel adıdır.',
    shortRiskSummary:
        'Yağın tam türü belirtilmediğinde doymuş yağ profili ürün bazında değişebilir. Bu nedenle değerlendirme toplam yağ içeriği ve tüketim sıklığı ile birlikte yapılmalıdır.',
    processingRole:
        'Bisküvi, kraker, cips, sos ve hazır karışımlarda görülebilir.',
    riskLevel: 'medium',
    references: [_whoHealthyDietReference, _whoSatFatGuidelineReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['şeker', 'seker', 'sakkaroz', 'sucrose'],
    ingredientType: 'İlave şeker',
    shortPurpose:
        'Şeker, ürüne tat vermek ve bazı ürünlerde doku ile renk gelişimini desteklemek için kullanılan bir bileşendir.',
    shortRiskSummary:
        'İlave şeker alımı değerlendirilirken ürünün porsiyon büyüklüğü ve gün içindeki toplam tüketim birlikte düşünülmelidir.',
    processingRole:
        'Tatlılar, içecekler, kahvaltılık ürünler ve çeşitli soslarda görülebilir.',
    riskLevel: 'medium',
    references: [_whoSugarsGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['şeker şurubu', 'sugar syrup'],
    containsAny: const ['şeker şurubu', 'invert şeker'],
    ingredientType: 'İlave şeker şurubu',
    shortPurpose:
        'Şeker şurubu, tat ve nem dengesini desteklemek için kullanılan ilave şeker kaynaklarından biridir.',
    shortRiskSummary:
        'İlave şeker içeren şuruplar değerlendirilirken ürünün porsiyon büyüklüğü ve toplam tüketim sıklığı birlikte düşünülmelidir.',
    processingRole:
        'Tatlı atıştırmalıklar, dolgular, soslar ve kahvaltılık ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [_whoSugarsGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['glikoz şurubu', 'glukoz şurubu', 'glucose syrup'],
    containsAny: const [
      'glikoz şurubu',
      'glukoz şurubu',
      'glikoz-fruktoz şurubu',
      'glucose syrup',
    ],
    ingredientType: 'İlave şeker şurubu',
    shortPurpose:
        'Glikoz şurubu, tat, kıvam ve nem dengesini desteklemek için kullanılan ilave şeker kaynaklarından biridir.',
    shortRiskSummary:
        'İlave şeker içeren şuruplar değerlendirilirken ürünün porsiyon büyüklüğü ve toplam tüketim sıklığı birlikte düşünülmelidir.',
    processingRole: 'Şekerleme, bisküvi, bar ve çeşitli soslarda görülebilir.',
    riskLevel: 'medium',
    references: [_whoSugarsGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['fruktoz şurubu', 'fructose syrup'],
    containsAny: const ['fruktoz şurubu', 'fructose syrup'],
    ingredientType: 'İlave şeker şurubu',
    shortPurpose:
        'Fruktoz şurubu, tat ve kıvam sağlamak için kullanılan ilave şeker kaynaklarından biridir.',
    shortRiskSummary:
        'İlave şeker içeren şuruplar değerlendirilirken ürünün porsiyon büyüklüğü ve toplam tüketim sıklığı birlikte düşünülmelidir.',
    processingRole:
        'Tatlı içecekler, şekerlemeler ve bazı kahvaltılık ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [_whoSugarsGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['tuz', 'salt'],
    ingredientType: 'Tuz / sodyum kaynağı',
    shortPurpose:
        'Tuz, ürünün tadını dengelemek ve bazı ürünlerde işlemeyi desteklemek için kullanılabilir.',
    shortRiskSummary:
        'Toplam sodyum alımı değerlendirilirken porsiyon miktarı ve gün içindeki diğer kaynaklarla birlikte düşünmek gerekir.',
    processingRole:
        'Atıştırmalıklar, peynirler, hazır çorbalar, soslar ve işlenmiş et ürünlerinde görülebilir.',
    riskLevel: 'medium',
    references: [_whoSodiumGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sodyum', 'sodium'],
    ingredientType: 'Sodyum bileşeni',
    shortPurpose:
        'Sodyum ifadesi, ürünün formülasyonunda tadı, korumayı veya işlevsel yapıyı destekleyen sodyum içeren bir bileşene işaret edebilir.',
    shortRiskSummary:
        'Sodyumla ilgili değerlendirme yapılırken ürünün etiketindeki toplam tuz/sodyum bilgisi ve porsiyon büyüklüğü birlikte düşünülmelidir.',
    processingRole:
        'Çeşitli katkı maddeleri ve bileşikler içinde sodyum formu olarak görülebilir.',
    riskLevel: 'medium',
    references: [_whoSodiumGuidelineReference, _whoHealthyDietReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['buğday gluteni', 'bugday gluteni', 'wheat gluten'],
    containsAny: const ['buğday gluteni', 'wheat gluten'],
    ingredientType: 'Tahıl proteini',
    shortPurpose:
        'Buğday gluteni, özellikle hamur yapısını ve elastikiyeti desteklemek için kullanılan bir tahıl proteinidir.',
    shortRiskSummary:
        'Gluten içeren bir bileşen olduğu için etiketteki alerjen ve içerik bilgisini takip eden kullanıcılar açısından görünür kılınır.',
    cautionGroups: const ['gluten bildirimi takip edenler'],
    processingRole:
        'Ekmek, unlu mamul, hazır karışım ve bazı işlenmiş ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['süt tozu', 'milk powder'],
    containsAny: const ['süt tozu', 'milk powder'],
    ingredientType: 'Süt bileşeni',
    shortPurpose:
        'Süt tozu, süt bileşenini daha yoğun biçimde sağlamak ve ürün dokusunu desteklemek için kullanılabilir.',
    shortRiskSummary:
        'Süt kaynaklı bir bileşen olduğu için etiketteki alerjen bilgisini takip eden kullanıcılar açısından görünür kılınır.',
    cautionGroups: const ['süt bildirimi takip edenler'],
    processingRole:
        'Bisküvi, çikolata, içecek tozu ve çeşitli hazır karışımlarda görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['fındık', 'findik', 'hazelnut'],
    ingredientType: 'Alerjen bildirimi',
    shortPurpose:
        'Fındık, ürünün tat ve doku profilini etkileyebilen bir kuruyemiş bileşenidir.',
    shortRiskSummary:
        'Fındık, etiketlerde alerjen olarak belirtilmesi gereken bileşenler arasındadır. Etiketly bunu alerjen görünürlüğü için bilgi amaçlı gösterir.',
    cautionGroups: const ['kuruyemiş bildirimi takip edenler'],
    processingRole:
        'Çikolata, kremalı ürün, atıştırmalık ve kahvaltılık karışımlarda görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['yer fıstığı', 'yer fistigi', 'peanut'],
    containsAny: const ['yer fıstığı', 'peanut'],
    ingredientType: 'Alerjen bildirimi',
    shortPurpose:
        'Yer fıstığı, ürünün tat ve doku profilini etkileyebilen bir kuruyemiş bileşenidir.',
    shortRiskSummary:
        'Yer fıstığı, etiketlerde alerjen olarak belirtilmesi gereken bileşenler arasındadır. Etiketly bunu alerjen görünürlüğü için bilgi amaçlı gösterir.',
    cautionGroups: const ['yer fıstığı bildirimi takip edenler'],
    processingRole:
        'Ezme, sos, bar ve çeşitli atıştırmalık ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['soya', 'soy', 'soybean'],
    ingredientType: 'Alerjen bildirimi',
    shortPurpose:
        'Soya, protein, yağ veya emülgatör kaynağı olarak kullanılan bir bitkisel bileşendir.',
    shortRiskSummary:
        'Soya, etiketlerde alerjen olarak belirtilmesi gereken bileşenler arasındadır. Etiketly bunu alerjen görünürlüğü için bilgi amaçlı gösterir.',
    cautionGroups: const ['soya bildirimi takip edenler'],
    processingRole:
        'İçecekler, soslar, et alternatifleri ve emülgatör kaynaklarında görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['susam', 'sesame'],
    ingredientType: 'Alerjen bildirimi',
    shortPurpose:
        'Susam, ürünün tat ve doku profilini etkileyebilen bir tohum bileşenidir.',
    shortRiskSummary:
        'Susam, etiketlerde alerjen olarak belirtilmesi gereken bileşenler arasındadır. Etiketly bunu alerjen görünürlüğü için bilgi amaçlı gösterir.',
    cautionGroups: const ['susam bildirimi takip edenler'],
    processingRole:
        'Fırıncılık ürünleri, soslar ve karışık atıştırmalıklarda görülebilir.',
    riskLevel: 'medium',
    references: [_fdaFoodAllergiesReference],
  ),

  // ── Artificial colours ───────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const [
      'brilliant blue',
      'brilliant blue fcf',
      'parlak mavi',
      'fd&c blue no. 1',
    ],
    containsAny: const ['brilliant blue', 'parlak mavi', 'fd&c blue'],
    eCode: 'E133',
    ingredientType: 'Yapay renklendirici',
    shortPurpose:
        'Brilliant Blue FCF, gıdalara mavi renk vermek için kullanılan yapay bir renklendiricidir.',
    shortRiskSummary:
        'AB mevzuatı bu renklendiriciyi içeren ürünlere çocukların dikkat ve aktivitesini olumsuz etkileyebilir uyarısı eklenmesini zorunlu kılmaktadır. EFSA değerlendirmesine göre ürünlerde kullanımı AB\'de izin verilen sınırlar içindedir. Etiketly bu nedenle yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'çocuklar',
      'yapay renklendirici içeriklerine dikkat edenler',
    ],
    processingRole:
        'Şekerleme, dondurma, içecek ve bazı atıştırmalıklarda görülebilir.',
    riskLevel: 'high',
    references: [_efsaE133Reference, _commissionAdditivesOverviewReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['tartrazin', 'tartrazine', 'fd&c yellow no. 5'],
    containsAny: const ['tartrazin', 'tartrazine'],
    eCode: 'E102',
    ingredientType: 'Yapay renklendirici',
    shortPurpose:
        'Tartrazin, gıdalara sarı renk vermek için kullanılan yapay bir renklendiricidir.',
    shortRiskSummary:
        'AB mevzuatı bu renklendiriciyi içeren ürünlere çocukların dikkat ve aktivitesini olumsuz etkileyebilir uyarısı eklenmesini zorunlu kılmaktadır. EFSA değerlendirmesine göre ürünlerde kullanımı AB\'de izin verilen sınırlar içindedir. Etiketly bu nedenle yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'çocuklar',
      'yapay renklendirici içeriklerine dikkat edenler',
    ],
    processingRole:
        'Şekerleme, içecek, hazır jöle ve bazı atıştırmalıklarda görülebilir.',
    riskLevel: 'high',
    references: [
      _efsaColourSafetyReference,
      _commissionAdditivesOverviewReference,
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'allura red',
      'allura red ac',
      'fd&c red no. 40',
      'kırmızı renklendirici',
    ],
    containsAny: const ['allura red'],
    eCode: 'E129',
    ingredientType: 'Yapay renklendirici',
    shortPurpose:
        'Allura Red AC, gıdalara kırmızı renk vermek için kullanılan yapay bir renklendiricidir.',
    shortRiskSummary:
        'AB mevzuatı bu renklendiriciyi içeren ürünlere çocukların dikkat ve aktivitesini olumsuz etkileyebilir uyarısı eklenmesini zorunlu kılmaktadır. EFSA değerlendirmesine göre ürünlerde kullanımı AB\'de izin verilen sınırlar içindedir. Etiketly bu nedenle yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'çocuklar',
      'yapay renklendirici içeriklerine dikkat edenler',
    ],
    processingRole:
        'Şekerleme, meşrubat, bazı içecek ve atıştırmalıklarda görülebilir.',
    riskLevel: 'high',
    references: [
      _efsaColourSafetyReference,
      _commissionAdditivesOverviewReference,
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sunset yellow', 'sunset yellow fcf', 'fd&c yellow no. 6'],
    containsAny: const ['sunset yellow'],
    eCode: 'E110',
    ingredientType: 'Yapay renklendirici',
    shortPurpose:
        'Sunset Yellow FCF, gıdalara turuncu-sarı renk vermek için kullanılan yapay bir renklendiricidir.',
    shortRiskSummary:
        'AB mevzuatı bu renklendiriciyi içeren ürünlere çocukların dikkat ve aktivitesini olumsuz etkileyebilir uyarısı eklenmesini zorunlu kılmaktadır. EFSA değerlendirmesine göre ürünlerde kullanımı AB\'de izin verilen sınırlar içindedir. Etiketly bu nedenle yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'çocuklar',
      'yapay renklendirici içeriklerine dikkat edenler',
    ],
    processingRole:
        'Şekerleme, aromalı içecek ve bazı atıştırmalıklarda görülebilir.',
    riskLevel: 'high',
    references: [
      _efsaColourSafetyReference,
      _commissionAdditivesOverviewReference,
    ],
  ),
  _IngredientCatalogEntry(
    aliases: const [
      'karmin',
      'karminik asit',
      'kırmızı 4',
      'cochineal',
      'carminic acid',
      'carmines',
    ],
    containsAny: const ['karmin', 'karminik', 'cochineal', 'carminic'],
    eCode: 'E120',
    ingredientType: 'Doğal kaynaklı renklendirici',
    shortPurpose:
        'Karmin, koşinil böceğinden elde edilen doğal kaynaklı bir renklendiricidir. Gıdalara kırmızı ve pembe tonlar verir.',
    shortRiskSummary:
        'EFSA değerlendirmesine göre nadiren alerjik ve anaflaktik tepkiye yol açabilir. Vejetaryen ve vegan diyette hayvansal kaynaklı olması nedeniyle özel değerlendirme gerektirebilir. Etiketly bu nedenle orta dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'alerjisi olanlar',
      'vejetaryen / vegan diyeti izleyenler',
    ],
    processingRole:
        'Şekerleme, yoğurt, meyve ürünleri ve bazı içeceklerde görülebilir.',
    riskLevel: 'medium',
    references: [_efsaE120Reference, _commissionAdditivesOverviewReference],
  ),

  // ── Preservatives ───────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const ['sodyum nitrit', 'sodium nitrite'],
    containsAny: const ['sodyum nitrit', 'sodium nitrite'],
    eCode: 'E250',
    ingredientType: 'Koruyucu / renk sabitleme maddesi',
    shortPurpose:
        'Sodyum nitrit, işlenmiş et ürünlerinde rengi sabitlemek, bozulmayı önlemek ve Clostridium botulinum bakterisinin oluşumunu engellemek için kullanılır.',
    shortRiskSummary:
        'EFSA ve IARC değerlendirmelerine göre işlenmiş et ürünlerinin sık tüketiminin belirli kanser türleriyle ilişkili olduğuna dair epidemiyolojik kanıtlar mevcuttur; bu ilişkide nitrit/nitrattan oluşan N-nitroso bileşiklerinin rol oynadığı düşünülmektedir. Yasal sınırlar içinde kullanılır. Etiketly bunu yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'işlenmiş et tüketimini sınırlayanlar',
      'çocuklar için sık tüketimde dikkat önerilir',
    ],
    processingRole:
        'Sucuk, sosis, jambon ve diğer işlenmiş et ürünlerinde görülebilir.',
    riskLevel: 'high',
    references: [_efsaNitriteReference, _whoProcessedMeatReference],
  ),
  _IngredientCatalogEntry(
    aliases: const ['sodyum nitrat', 'sodium nitrate'],
    containsAny: const ['sodyum nitrat', 'sodium nitrate'],
    eCode: 'E251',
    ingredientType: 'Koruyucu',
    shortPurpose:
        'Sodyum nitrat, bazı işlenmiş gıdalarda bozulmayı yavaşlatmak ve rengi korumak için kullanılır.',
    shortRiskSummary:
        'EFSA değerlendirmesine göre nitrattan nitrit oluşumu nedeniyle işlenmiş et ürünlerinde sık tüketimde dikkat önerilir. Yasal sınırlar içinde kullanılır. Etiketly bunu yüksek dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['işlenmiş et tüketimini sınırlayanlar'],
    processingRole: 'Kürlenmiş et ve bazı hazır gıda ürünlerinde görülebilir.',
    riskLevel: 'high',
    references: [_efsaNitriteReference, _whoProcessedMeatReference],
  ),

  // ── Flavor enhancers ────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const ['monosodyum glutamat', 'msg', 'monosodium glutamate'],
    containsAny: const ['monosodyum glutamat', 'monosodium glutamate'],
    eCode: 'E621',
    ingredientType: 'Çeşni artırıcı (lezzet kuvvetlendirici)',
    shortPurpose:
        'Monosodyum glutamat (MSG), yiyeceklerdeki umami tadını yoğunlaştırmak için kullanılan bir çeşni artırıcıdır.',
    shortRiskSummary:
        'EFSA değerlendirmesine göre günlük alım düzeylerine bağlı olarak yüksek miktardaki tüketime dikkat edilmesi önerilmektedir. Yasal sınırlar içinde kullanılır; genel nüfus için standart porsiyon değerlerinde risk görülmemiştir. Etiketly bunu bilgi amaçlı orta dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['MSG hassasiyeti bildirenler'],
    processingRole:
        'Hazır çorba, sos, cips ve çeşitli tuzlu atıştırmalıklarda görülebilir.',
    riskLevel: 'medium',
    references: [_efsaMsgReference, _commissionAdditivesOverviewReference],
  ),

  // ── Carbohydrates ───────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const ['maltodekstrin', 'maltodextrin'],
    containsAny: const ['maltodekstrin', 'maltodextrin'],
    ingredientType: 'Hızlı sindirilen karbonhidrat / dolgu maddesi',
    shortPurpose:
        'Maltodekstrin, ürünlerin dokusunu, kıvamını ve raf ömrünü desteklemek için kullanılan bir karbonhidrat bileşenidir.',
    shortRiskSummary:
        'Glisemik indeksi yüksek olduğundan hızla kana karışabilir. Tek başına risk teşkil etmez; ancak ultra işlenmiş ürünlerin tipik bir bileşeni olduğu için tüketim sıklığına dikkat edilmesi önerilir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['kan şekeri dengesine dikkat edenler'],
    processingRole:
        'Hazır içecekler, bar, bisküvi, sos ve aromalı atıştırmalıklarda görülebilir.',
    riskLevel: 'medium',
    references: [_efsaMaltodextrinReference, _whoHealthyDietReference],
  ),

  // ── Sugar alcohols ──────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const ['maltitol', 'maltitol syrup'],
    containsAny: const ['maltitol'],
    eCode: 'E965',
    ingredientType: 'Tatlandırıcı / şeker alkolü',
    shortPurpose:
        'Maltitol, şekersiz veya azaltılmış şekerli ürünlerde tat ve hacim sağlamak için kullanılan bir şeker alkolüdür.',
    shortRiskSummary:
        'Fazla tüketimde sindirim rahatsızlığı (gaz, ishal) yapabilir. Glisemik indeksi şekerden düşük olmakla birlikte sıfır değildir. Etiketly bunu bilgi amaçlı orta dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const [
      'irritabl bağırsak sendromu olanlar',
      'kan şekeri dengesine dikkat edenler',
    ],
    processingRole:
        'Şekersiz şekerleme, çikolata ve bazı diyabetik ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _fdaSweetenerOverviewReference,
      _commissionDatabaseReference(
        documentCode: 'E965',
        note:
            'Maltitol ve maltitol şurubu için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),

  // ── Sweeteners ──────────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const [
      'siklamat',
      'sodyum siklamat',
      'cyclamate',
      'sodium cyclamate',
    ],
    containsAny: const ['siklamat', 'cyclamate'],
    eCode: 'E952',
    ingredientType: 'Yoğun tatlandırıcı',
    shortPurpose:
        'Siklamat, şekerden yaklaşık 30–50 kat daha tatlı olan yapay bir tatlandırıcıdır. Düşük kalorili ürünlerde şeker yerine kullanılır.',
    shortRiskSummary:
        'EFSA değerlendirmesine göre güvenlik verileri yeterli bulunarak AB\'de izin verilmiştir; ancak bazı ülkelerde (örn. ABD) hâlâ kısıtlıdır. Tatlandırıcı içeren ürünler değerlendirilirken ürünün genel beslenme profili ve tüketim alışkanlığı birlikte düşünülmelidir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    processingRole:
        'Şekersiz içecekler, şekerleme ve bazı düşük kalorili ürünlerde görülebilir.',
    riskLevel: 'medium',
    references: [
      _efsaCyclamateReference,
      _commissionDatabaseReference(
        documentCode: 'E952',
        note: 'Siklamatlar için AB katkı maddesi veri tabanı girişi.',
      ),
    ],
  ),

  // ── Oils ────────────────────────────────────────────────────────────────
  _IngredientCatalogEntry(
    aliases: const [
      'hidrojenize yağ',
      'kısmen hidrojenize yağ',
      'hydrogenated oil',
      'partially hydrogenated oil',
    ],
    containsAny: const [
      'hidrojenize yağ',
      'kısmen hidrojenize',
      'hydrogenated oil',
      'partially hydrogenated',
    ],
    ingredientType: 'İşlenmiş yağ',
    shortPurpose:
        'Hidrojenize yağ, sıvı bitkisel yağların katı/yarı katı hale getirilmesi işlemiyle üretilir. Ürünün raf ömrünü ve dokusunu iyileştirmek için kullanılır.',
    shortRiskSummary:
        'Kısmen hidrojenize yağlar trans yağ asitleri içerebilir. WHO ve EFSA, trans yağ alımının kardiyovasküler sağlık açısından sınırlandırılmasını önermektedir. Tam hidrojenize yağlar çok az trans yağ içerir; değerlendirme etiket bilgisiyle yapılmalıdır. Etiketly bunu orta dikkat kategorisinde gösterir. Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
    cautionGroups: const ['toplam yağ alımını sınırlayanlar'],
    processingRole:
        'Bisküvi, kek, hazır dolgular ve bazı atıştırmalıklarda görülebilir.',
    riskLevel: 'medium',
    references: [_whoSatFatGuidelineReference, _whoHealthyDietReference],
  ),
];
