class CategoryTagDecision {
  final String tag;
  final int score;
  final bool accepted;
  final bool strongNegative;
  final List<String> reasons;

  const CategoryTagDecision({
    required this.tag,
    required this.score,
    required this.accepted,
    required this.strongNegative,
    required this.reasons,
  });
}

class CategoryClassificationResult {
  final List<String> categoryTags;
  final Map<String, CategoryTagDecision> decisions;

  const CategoryClassificationResult({
    required this.categoryTags,
    required this.decisions,
  });

  bool hasTag(String tag) => categoryTags.contains(tag);
}

class ProductCategoryClassifier {
  static const int acceptThreshold = 5;

  static const _tagOrder = <String>[
    'et_sarkuteri',
    'cips_kraker',
    'sut_urunleri',
    'peynir_yogurt',
    'cikolata_gofret',
    'biskuvi_kek',
    'soslar',
    'icecekler',
    'enerji_icecekleri',
    'ton_konserve',
    'kahvaltilik',
    'findik_ezmesi',
    'hazir_yemek',
    'bebek_cocuk',
    'dondurma_tatli',
    'saglikli_protein',
    'atistirmalik',
  ];

  static CategoryClassificationResult classify({
    required String name,
    String? brand,
    List<String>? searchKeywords,
    List<String>? categoryTags,
    List<String>? offCategories,
    List<String>? offCategoryTags,
    String? ingredientsText,
  }) {
    final input = _ClassificationInput.fromValues(
      name: name,
      brand: brand,
      searchKeywords: searchKeywords,
      categoryTags: categoryTags,
      offCategories: offCategories,
      offCategoryTags: offCategoryTags,
      ingredientsText: ingredientsText,
    );

    final decisions = <String, CategoryTagDecision>{};
    final accepted = <String>[];

    for (final tag in _tagOrder) {
      final decision = _scoreTag(tag, input);
      decisions[tag] = decision;
      if (decision.accepted) accepted.add(tag);
    }

    accepted.sort((a, b) {
      final scoreDiff = (decisions[b]?.score ?? 0) - (decisions[a]?.score ?? 0);
      if (scoreDiff != 0) return scoreDiff;
      return a.compareTo(b);
    });

    return CategoryClassificationResult(
      categoryTags: accepted,
      decisions: decisions,
    );
  }

  static CategoryTagDecision evaluateTag({
    required String tag,
    required String name,
    String? brand,
    List<String>? searchKeywords,
    List<String>? categoryTags,
    List<String>? offCategories,
    List<String>? offCategoryTags,
    String? ingredientsText,
  }) {
    final input = _ClassificationInput.fromValues(
      name: name,
      brand: brand,
      searchKeywords: searchKeywords,
      categoryTags: categoryTags,
      offCategories: offCategories,
      offCategoryTags: offCategoryTags,
      ingredientsText: ingredientsText,
    );
    return _scoreTag(tag, input);
  }

  static CategoryTagDecision _scoreTag(String tag, _ClassificationInput input) {
    switch (tag) {
      case 'et_sarkuteri':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _meatOffTags,
          strongTerms: _meatStrongTerms,
          mediumTerms: _meatMediumTerms,
          negativeTerms: _meatNegativeTerms,
          threshold: 5,
          extraScore: (input) {
            var bonus = 0;
            if (input.brand == 'eti') {
              bonus -= 20;
            }
            return bonus;
          },
          extraReject: (input) {
            if (input.brand == 'eti' && !input.hasAny(_meatStrongTerms)) {
              return true;
            }
            return false;
          },
        );
      case 'cips_kraker':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _snackOffTags,
          strongTerms: _snackStrongTerms,
          mediumTerms: _snackMediumTerms,
          negativeTerms: _snackNegativeTerms,
          threshold: 5,
        );
      case 'sut_urunleri':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _dairyOffTags,
          strongTerms: _dairyStrongTerms,
          mediumTerms: _dairyMediumTerms,
          negativeTerms: _dairyNegativeTerms,
          threshold: 5,
          extraReject: (input) =>
              input.hasAny(_snackStrongTerms) ||
              input.hasAny(_snackMediumTerms),
        );
      case 'peynir_yogurt':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _cheeseYogurtOffTags,
          strongTerms: _cheeseYogurtStrongTerms,
          mediumTerms: _cheeseYogurtMediumTerms,
          negativeTerms: _dairyNegativeTerms,
          threshold: 5,
          extraReject: (input) =>
              input.hasAny(_snackStrongTerms) ||
              input.hasAny(_snackMediumTerms),
        );
      case 'cikolata_gofret':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _chocolateOffTags,
          strongTerms: _chocolateStrongTerms,
          mediumTerms: _chocolateMediumTerms,
          negativeTerms: _chocolateNegativeTerms,
          threshold: 5,
          extraReject: (input) =>
              input.hasAny(_meatStrongTerms) || input.hasAny(_sauceStrongTerms),
        );
      case 'biskuvi_kek':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _biscuitOffTags,
          strongTerms: _biscuitStrongTerms,
          mediumTerms: _biscuitMediumTerms,
          negativeTerms: _biscuitNegativeTerms,
          threshold: 5,
          extraReject: (input) =>
              input.hasAny(_meatStrongTerms) || input.hasAny(_sauceStrongTerms),
        );
      case 'soslar':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _sauceOffTags,
          strongTerms: _sauceStrongTerms,
          mediumTerms: _sauceMediumTerms,
          negativeTerms: _sauceNegativeTerms,
          threshold: 5,
        );
      case 'icecekler':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _beverageOffTags,
          strongTerms: _beverageStrongTerms,
          mediumTerms: _beverageMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'enerji_icecekleri':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _energyOffTags,
          strongTerms: _energyStrongTerms,
          mediumTerms: _energyMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'ton_konserve':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _fishOffTags,
          strongTerms: _fishStrongTerms,
          mediumTerms: _fishMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'kahvaltilik':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _breakfastOffTags,
          strongTerms: _breakfastStrongTerms,
          mediumTerms: _breakfastMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'findik_ezmesi':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _spreadOffTags,
          strongTerms: _spreadStrongTerms,
          mediumTerms: _spreadMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'hazir_yemek':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _readyMealOffTags,
          strongTerms: _readyMealStrongTerms,
          mediumTerms: _readyMealMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'bebek_cocuk':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _babyOffTags,
          strongTerms: _babyStrongTerms,
          mediumTerms: _babyMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'dondurma_tatli':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _dessertOffTags,
          strongTerms: _dessertStrongTerms,
          mediumTerms: _dessertMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'saglikli_protein':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _proteinOffTags,
          strongTerms: _proteinStrongTerms,
          mediumTerms: _proteinMediumTerms,
          negativeTerms: const <String>[],
          threshold: 5,
        );
      case 'atistirmalik':
        return _scoreTagged(
          tag,
          input,
          exactOffTags: _snackOffTags,
          strongTerms: _snackStrongTerms,
          mediumTerms: [
            ..._snackMediumTerms,
            ..._chocolateStrongTerms,
            ..._biscuitStrongTerms,
            ..._spreadStrongTerms,
            ..._proteinStrongTerms,
          ],
          negativeTerms: const <String>[],
          threshold: 5,
        );
      default:
        return const CategoryTagDecision(
          tag: '',
          score: 0,
          accepted: false,
          strongNegative: false,
          reasons: [],
        );
    }
  }

  static CategoryTagDecision _scoreTagged(
    String tag,
    _ClassificationInput input, {
    required Set<String> exactOffTags,
    required List<String> strongTerms,
    required List<String> mediumTerms,
    required List<String> negativeTerms,
    required int threshold,
    bool Function(_ClassificationInput input)? extraReject,
    int Function(_ClassificationInput input)? extraScore,
  }) {
    final reasons = <String>[];
    var score = 0;
    var strongNegative = false;

    if (input.existingCategoryTags.contains(tag)) {
      score += 10;
      reasons.add('existing_category_tag');
    }

    if (input.offTags.any(exactOffTags.contains)) {
      score += 8;
      reasons.add('off_category_tag');
    }

    if (input.hasAny(strongTerms)) {
      score += 5;
      reasons.add('strong_term');
    }

    if (input.hasAny(mediumTerms)) {
      score += 2;
      reasons.add('medium_term');
    }

    if (input.hasAny(negativeTerms)) {
      score -= 20;
      strongNegative = true;
      reasons.add('negative_term');
    }

    if (extraScore != null) {
      final bonus = extraScore(input);
      if (bonus != 0) {
        score += bonus;
        reasons.add('extra_score_$bonus');
      }
    }

    if (extraReject != null && extraReject(input)) {
      score -= 20;
      strongNegative = true;
      reasons.add('extra_reject');
    }

    final accepted = !strongNegative && score >= threshold;
    return CategoryTagDecision(
      tag: tag,
      score: score,
      accepted: accepted,
      strongNegative: strongNegative,
      reasons: reasons,
    );
  }

  static const _meatOffTags = <String>{
    'en:meats',
    'en:prepared-meats',
    'en:sausages',
    'en:salami',
    'en:hams',
    'en:poultry',
    'en:turkey',
    'en:chicken',
    'en:beef',
  };

  static const _meatStrongTerms = <String>[
    'salam',
    'sucuk',
    'sosis',
    'jambon',
    'pastirma',
    'pastırma',
    'hindi',
    'dana',
    'tavuk',
    'meat',
    'sausage',
    'salami',
    'ham',
    'deli',
    'şarküteri',
    'sarkuteri',
  ];

  static const _meatMediumTerms = <String>[
    'et',
    'turkey',
    'chicken',
    'beef',
    'poultry',
  ];

  static const _meatNegativeTerms = <String>[
    'cips',
    'chips',
    'kraker',
    'cracker',
    'snack',
    'aroma',
    'cesnili',
    'baharatli',
    'mevsim yesillikli',
    'doritos',
    'lays',
    'ruffles',
    'pringles',
    'cheetos',
    'crax',
    'ketchup',
    'ketcap',
    'ketçap',
    'mayonez',
    'mayonnaise',
  ];

  static const _snackOffTags = <String>{
    'en:snacks',
    'en:salty-snacks',
    'en:chips-and-fries',
    'en:crisps',
    'en:crackers',
  };

  static const _snackStrongTerms = <String>[
    'cips',
    'chips',
    'kraker',
    'cracker',
    'çubuk kraker',
    'cubuk kraker',
    'sticks',
    'doritos',
    'lays',
    "lay's",
    'pringles',
    'ruffles',
    'cheetos',
    'crax',
    'snack',
    'atistirmalik',
    'aperatif',
  ];

  static const _snackMediumTerms = <String>[
    'patates cipsi',
    'potato chips',
    'salty snack',
    'baharatli',
    'cesnili',
    'mevsim yesillikli',
    'aroma',
  ];

  static const _snackNegativeTerms = <String>[];

  static const _dairyOffTags = <String>{
    'en:dairies',
    'en:milks',
    'en:fermented-milk-products',
    'en:milk-products',
  };

  static const _dairyStrongTerms = <String>[
    'sut',
    'süt',
    'milk',
    'ayran',
    'kefir',
    'dairy',
  ];

  static const _dairyMediumTerms = <String>['sutlu', 'sütlü'];

  static const _dairyNegativeTerms = <String>[
    'cips',
    'chips',
    'kraker',
    'cracker',
    'snack',
    'aroma',
    'cesnili',
    'baharatli',
    'mevsim yesillikli',
    'doritos',
    'lays',
    'ruffles',
    'pringles',
    'cheetos',
    'crax',
    'ketchup',
    'ketcap',
    'ketçap',
  ];

  static const _cheeseYogurtOffTags = <String>{
    'en:cheeses',
    'en:yogurts',
    'en:fermented-milk-products',
    'en:milk-products',
  };

  static const _cheeseYogurtStrongTerms = <String>[
    'peynir',
    'cheese',
    'yogurt',
    'yoğurt',
    'yoghurt',
    'labne',
    'krem peynir',
    'kasar',
    'kaşar',
    'beyaz peynir',
    'lor',
  ];

  static const _cheeseYogurtMediumTerms = <String>['sut', 'süt', 'milk'];

  static const _chocolateOffTags = <String>{
    'en:chocolates',
    'en:chocolate-confectioneries',
    'en:wafers',
  };

  static const _chocolateStrongTerms = <String>[
    'cikolata',
    'çikolata',
    'chocolate',
    'cikolatali',
    'çikolatalı',
    'gofret',
    'wafer',
    'kakao',
    'cacao',
    'kinder',
    'milka',
    'twix',
    'snickers',
    'bounty',
    'ferrero',
    'albeni',
    'metro',
    'karam',
    'bar',
  ];

  static const _chocolateMediumTerms = <String>[];

  static const _chocolateNegativeTerms = <String>[
    'salam',
    'sucuk',
    'sosis',
    'jambon',
    'ketcap',
    'ketçap',
    'ketchup',
    'mayonez',
    'mayonnaise',
  ];

  static const _biscuitOffTags = <String>{
    'en:biscuits',
    'en:cakes',
    'en:cookies',
  };

  static const _biscuitStrongTerms = <String>[
    'bisküvi',
    'biskuvi',
    'biscuit',
    'cookie',
    'kek',
    'cake',
    'muffin',
    'kurabiye',
    'petit',
  ];

  static const _biscuitMediumTerms = <String>['cracker', 'kraker'];

  static const _biscuitNegativeTerms = <String>[
    'salam',
    'sucuk',
    'sosis',
    'jambon',
  ];

  static const _sauceOffTags = <String>{'en:sauces'};

  static const _sauceStrongTerms = <String>[
    'ketcap',
    'ketçap',
    'ketchup',
    'mayonez',
    'mayonnaise',
    'sos',
    'sauce',
    'hardal',
    'mustard',
    'bbq',
    'salca',
    'salça',
  ];

  static const _sauceMediumTerms = <String>[];

  static const _sauceNegativeTerms = <String>[];

  static const _beverageOffTags = <String>{'en:beverages'};

  static const _beverageStrongTerms = <String>[
    'icecek',
    'içecek',
    'drink',
    'beverage',
    'kola',
    'cola',
    'soda',
    'maden suyu',
    'cay',
    'çay',
    'kahve',
    'coffee',
    'ayran',
    'meyve suyu',
    'limonata',
  ];

  static const _beverageMediumTerms = <String>[];

  static const _energyOffTags = <String>{'en:energy-drinks'};

  static const _energyStrongTerms = <String>[
    'enerji icecegi',
    'enerji içeceği',
    'energy drink',
    'energy',
    'red bull',
    'redbull',
    'monster',
    'burn',
    'powerzone',
    'rockstar',
    'boost',
  ];

  static const _energyMediumTerms = <String>[];

  static const _fishOffTags = <String>{
    'en:fish-products',
    'en:tunas',
    'en:canned-fishes',
  };

  static const _fishStrongTerms = <String>[
    'ton baligi',
    'ton balığı',
    'tuna',
    'sardalya',
    'sardine',
    'hamsi',
    'anchovy',
    'konserve balik',
    'konserve balık',
    'canned fish',
  ];

  static const _fishMediumTerms = <String>[];

  static const _breakfastOffTags = <String>{'en:breakfasts'};

  static const _breakfastStrongTerms = <String>[
    'kahvalti',
    'kahvaltı',
    'breakfast',
    'recel',
    'reçel',
    'jam',
    'bal',
    'honey',
    'pekmez',
    'tahin',
    'tahini',
    'zeytin',
    'olive',
    'misir gevregi',
    'mısır gevreği',
    'musli',
    'müsli',
    'cereal',
  ];

  static const _breakfastMediumTerms = <String>[];

  static const _spreadOffTags = <String>{'en:spreads'};

  static const _spreadStrongTerms = <String>[
    'findik ezmesi',
    'fındık ezmesi',
    'fistik ezmesi',
    'fıstık ezmesi',
    'peanut butter',
    'hazelnut',
    'nutella',
    'lotus',
    'spread',
    'surelebilir',
    'sürülebilir',
  ];

  static const _spreadMediumTerms = <String>[];

  static const _readyMealOffTags = <String>{
    'en:ready-meals',
    'en:canned-foods',
  };

  static const _readyMealStrongTerms = <String>[
    'hazir yemek',
    'hazır yemek',
    'ready meal',
    'hazir corba',
    'hazır çorba',
    'soup',
    'noodle',
    'ramen',
    'konserve',
  ];

  static const _readyMealMediumTerms = <String>[];

  static const _babyOffTags = <String>{'en:baby-foods'};

  static const _babyStrongTerms = <String>[
    'bebek',
    'baby',
    'cocuk',
    'çocuk',
    'child',
    'mama',
    'ek gida',
    'ek gıda',
    'junior',
    'infant',
  ];

  static const _babyMediumTerms = <String>[];

  static const _dessertOffTags = <String>{'en:desserts', 'en:ice-creams'};

  static const _dessertStrongTerms = <String>[
    'dondurma',
    'ice cream',
    'icecream',
    'tatli',
    'tatlı',
    'sweet',
    'dessert',
    'puding',
    'pudding',
    'helva',
    'lokum',
    'baklava',
  ];

  static const _dessertMediumTerms = <String>[];

  static const _proteinOffTags = <String>{
    'en:protein-bars',
    'en:dietary-supplements',
  };

  static const _proteinStrongTerms = <String>[
    'protein',
    'granola',
    'bar',
    'healthy',
    'fit',
    'diet',
    'light',
    'whey',
    'supplement',
  ];

  static const _proteinMediumTerms = <String>[];
}

class _ClassificationInput {
  final String name;
  final String brand;
  final String searchableText;
  final Set<String> tokens;
  final Set<String> offTags;
  final Set<String> existingCategoryTags;

  _ClassificationInput({
    required this.name,
    required this.brand,
    required this.searchableText,
    required this.tokens,
    required this.offTags,
    required this.existingCategoryTags,
  });

  factory _ClassificationInput.fromValues({
    required String name,
    String? brand,
    List<String>? searchKeywords,
    List<String>? categoryTags,
    List<String>? offCategories,
    List<String>? offCategoryTags,
    String? ingredientsText,
  }) {
    final safeName = _normalize(name);
    final safeBrand = _normalize(brand ?? '');
    final searchableText = [
      name,
      brand ?? '',
      ingredientsText ?? '',
      if (searchKeywords != null) searchKeywords.join(' '),
      if (offCategories != null) offCategories.join(' '),
    ].map(_normalize).join(' ');

    final tokens = <String>{
      ..._tokensFromText(safeName),
      ..._tokensFromText(safeBrand),
      ..._tokensFromText(searchableText),
      if (searchKeywords != null)
        ...searchKeywords.map(_normalize).expand(_tokensFromText),
    };

    final offTags = <String>{
      ...?offCategories?.map((e) => e.toLowerCase().trim()),
      ...?offCategoryTags?.map((e) => e.toLowerCase().trim()),
    };

    final existingCategoryTags = <String>{
      ...?categoryTags?.map((e) => e.toLowerCase().trim()),
    };

    return _ClassificationInput(
      name: safeName,
      brand: safeBrand,
      searchableText: searchableText,
      tokens: tokens,
      offTags: offTags,
      existingCategoryTags: existingCategoryTags,
    );
  }

  bool hasAny(Iterable<String> terms) {
    for (final term in terms) {
      final normalized = _normalize(term);
      if (normalized.isEmpty) continue;
      if (searchableText.contains(normalized)) return true;
      if (tokens.contains(normalized)) return true;
    }
    return false;
  }
}

String _normalize(String input) {
  var s = input.toLowerCase().trim();
  s = s
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u');
  s = s.replaceAll(RegExp(r"[’'`´]"), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

Set<String> _tokensFromText(String text) =>
    text.split(' ').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
