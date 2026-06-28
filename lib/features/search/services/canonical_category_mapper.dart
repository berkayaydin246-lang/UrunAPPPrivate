// Canonical category mapper.
//
// Maps a product (identified by its [categoryTags] array and display [name])
// to a two-level canonical category tree used in public product search.
// The mapping is deterministic and tag-first: database tags (set by the
// scraper/admin pipeline) are the primary signal; product-name keywords are
// the tiebreaker for sub-categories.
//
// The twelve main categories match the app's human-readable facet labels.

class CanonicalCategory {
  final String main;
  final String? sub;

  const CanonicalCategory({required this.main, this.sub});

  @override
  String toString() => sub != null ? '$main / $sub' : main;
}

class CanonicalCategoryMapper {
  CanonicalCategoryMapper._();

  // ── Main category label constants ─────────────────────────────────────────

  static const String kAtistirmalik = 'Atıştırmalık';
  static const String kIcecek = 'İçecek';
  static const String kSutKahvaltilik = 'Süt & Kahvaltılık';
  static const String kTemelGida = 'Temel Gıda';
  static const String kEtTavukBalik = 'Et, Tavuk & Balık';
  static const String kMeyveSebze = 'Meyve & Sebze';
  static const String kHazirDonuk = 'Hazır & Donuk';
  static const String kDondurma = 'Dondurma';
  static const String kFirinPastane = 'Fırın & Pastane';
  static const String kBebek = 'Bebek Gıda';
  static const String kOzelBeslenme = 'Özel Beslenme';
  static const String kDiger = 'Diğer';

  // ── Backward-compat aliases (old constants → new values) ──────────────────
  // Code compiled against old names continues to work; tests that compare
  // against constant references (not hardcoded strings) also pass.
  static const String kSut = kSutKahvaltilik;
  static const String kKahvaltilik = kSutKahvaltilik;
  static const String kEt = kEtTavukBalik;
  static const String kIcecekler = kIcecek;
  static const String kSosKonserve = kTemelGida;

  // ── Sub-category label constants ──────────────────────────────────────────
  // Süt & Kahvaltılık
  static const String kSutSub = 'Süt';
  static const String kYogurt = 'Yoğurt / Ayran';
  static const String kPeynir = 'Peynir';
  static const String kSutluTatli = 'Sütlü Tatlı / Krema';
  static const String kBalRecel = 'Bal / Reçel / Pekmez';
  static const String kTahinHelva = 'Tahin / Helva';
  static const String kKremCikolata = 'Krem Çikolata / Ezme';
  static const String kGevrek = 'Kahvaltılık Gevrek / Granola';
  // Et, Tavuk & Balık
  static const String kSarkuteri = 'Şarküteri';
  static const String kTavuk = 'Tavuk / Beyaz Et';
  static const String kKirmiziEt = 'Kırmızı Et';
  static const String kBalik = 'Balık / Deniz Ürünleri';
  // Atıştırmalık
  static const String kBiskuvi = 'Bisküvi';
  static const String kCips = 'Cips';
  static const String kCikolata = 'Çikolata / Gofret';
  static const String kKuruyemis = 'Kuruyemiş';
  static const String kSekerleme = 'Şekerleme';
  static const String kKek = 'Kek';
  static const String kKraker = 'Kraker';
  static const String kBarKaplamalilar = 'Bar / Kaplamalılar';
  static const String kMisirPirincPatlagi = 'Mısır ve Pirinç Patlağı';
  static const String kKuruMeyve = 'Kuru Meyve';
  static const String kSakiz = 'Sakız';
  // İçecek
  static const String kGazli = 'Gazlı İçecek';
  static const String kGazsiz = 'Gazsız İçecek';
  static const String kMeyvesuyu = 'Meyve Suyu';
  // Temel Gıda
  static const String kSoslar = 'Soslar';
  static const String kKonserve = 'Konserve';
  static const String kMakarna = 'Makarna';
  static const String kBakliyat = 'Bakliyat';
  static const String kYag = 'Yağ';
  static const String kUnSeker = 'Un / Şeker / Tuz';
  // Hazır & Donuk
  static const String kHazirYemek = 'Hazır Yemek';

  // ── All canonical main categories (for filter UI) ─────────────────────────

  static const List<String> allMainCategories = [
    kAtistirmalik,
    kIcecek,
    kSutKahvaltilik,
    kTemelGida,
    kEtTavukBalik,
    kMeyveSebze,
    kHazirDonuk,
    kDondurma,
    kFirinPastane,
    kBebek,
    kOzelBeslenme,
    kDiger,
  ];

  /// Visible main categories for public UI (home, tabs, swipe).
  /// Excludes internal fallback categories (Özel Beslenme, Diğer).
  static const List<String> visibleMainCategories = [
    kAtistirmalik,
    kIcecek,
    kSutKahvaltilik,
    kTemelGida,
    kEtTavukBalik,
    kMeyveSebze,
    kHazirDonuk,
    kDondurma,
    kFirinPastane,
    kBebek,
  ];

  // ── Category image assets ────────────────────────────────────────────────

  static const Map<String, String> categoryImageAssets = {
    kAtistirmalik: 'assets/images/categories/atistirmalik.png',
    kIcecek: 'assets/images/categories/icecek.png',
    kSutKahvaltilik: 'assets/images/categories/sut_kahvaltilik.png',
    kTemelGida: 'assets/images/categories/temel_gida.png',
    kEtTavukBalik: 'assets/images/categories/et_tavuk_balik.png',
    kMeyveSebze: 'assets/images/categories/meyve_sebze.png',
    kHazirDonuk: 'assets/images/categories/hazir_donuk.png',
    kDondurma: 'assets/images/categories/dondurma.png',
    kFirinPastane: 'assets/images/categories/firin_pastane.png',
    kBebek: 'assets/images/categories/bebek_gida.png',
  };

  /// Returns the image asset path for a main category, or null if not available.
  static String? imageAssetForCategory(String categoryLabel) =>
      categoryImageAssets[categoryLabel];

  static const Map<String, List<String>> _mainToSubs = {
    kSutKahvaltilik: [
      kSutSub,
      kYogurt,
      kPeynir,
      kSutluTatli,
      kBalRecel,
      kTahinHelva,
      kKremCikolata,
      kGevrek,
    ],
    kEtTavukBalik: [kSarkuteri, kTavuk, kKirmiziEt, kBalik],
    kAtistirmalik: [
      kBiskuvi,
      kCips,
      kCikolata,
      kKuruyemis,
      kSekerleme,
      kKek,
      kKraker,
      kBarKaplamalilar,
      kMisirPirincPatlagi,
      kKuruMeyve,
      kSakiz,
    ],
    kIcecek: [kGazli, kGazsiz, kMeyvesuyu],
    kTemelGida: [kSoslar, kKonserve, kMakarna, kBakliyat, kYag, kUnSeker],
    kHazirDonuk: [kHazirYemek],
    kMeyveSebze: [],
    kDondurma: [],
    kFirinPastane: [],
    kBebek: [],
    kOzelBeslenme: [],
    kDiger: [],
  };

  /// Returns subcategories for a given main category.
  static List<String> subCategoriesFor(String main) =>
      _mainToSubs[main] ?? const [];

  // ── DB tag → main category reverse lookup (for server-side filtering) ─────

  static const Map<String, List<String>> _mainToTags = {
    kSutKahvaltilik: [
      // Old scraper tags
      'sut_urunleri', 'peynir_yogurt',
      // New Migros scraper tags
      'sut', 'yogurt', 'peynir', 'sutlu_tatli_krema',
      // Breakfast / spreads
      'kahvaltilik', 'findik_ezmesi', 'kahvaltiliklar',
    ],
    kEtTavukBalik: [
      'et_sarkuteri',
      'et-sarkulteri',
      'ton_konserve',
      'sucuk',
      'sosis',
      'salam',
      'jambon',
      'pastirma',
      'fume_et',
      'kavurma',
      'beyaz_et',
      'kirmizi_et',
      'balik_deniz_urunleri',
    ],
    kAtistirmalik: [
      'biskuvi_kek',
      'cips_kraker',
      'cikolata_gofret',
      'atistirmalik',
      'saglikli_protein',
      'biskuvi',
      'cips',
      'kuruyemis',
      'cikolata',
      'bar_kaplamalilar',
      'kek',
      'kraker',
      'sekerleme',
      'misir_pirinc_patlagi',
      'kuru_meyve',
      'sakiz',
    ],
    kIcecek: [
      'icecekler',
      'enerji_icecekleri',
      'gazli_icecek',
      'gazsiz_icecek',
    ],
    kTemelGida: ['makarna_bakliyat', 'soslar', 'sos', 'konserve'],
    kHazirDonuk: ['hazir_yemek'],
    kDondurma: ['dondurma_tatli'],
    kBebek: ['bebek_cocuk'],
    kMeyveSebze: [
      // Tags assigned when Migros meyve/sebze categories are scraped.
      // No products with these tags exist yet → query returns empty state.
      'meyve_sebze',
      'meyve',
      'sebze',
      'taze_meyve',
      'taze_sebze',
    ],
    kFirinPastane: ['firin_pastane', 'ekmek', 'unlu_mamul', 'firin'],
    kOzelBeslenme: [],
    kDiger: [],
  };

  /// Returns the set of DB `category_tags` values that belong to [mainCategory].
  /// Used to build server-side Supabase `category_tags` overlap filters.
  static List<String> mainCategoryToTags(String mainCategory) =>
      _mainToTags[mainCategory] ?? const [];

  /// Formats [tags] as a PostgreSQL text-array literal suitable for the
  /// PostgREST `ov` (overlap) operator: e.g. `{biskuvi,cips}`.
  ///
  /// Trims whitespace, drops empty strings, and de-duplicates.
  /// Returns `''` when [tags] is empty — callers must guard against passing an
  /// empty string to the server (empty-tagged categories must show an empty
  /// state, not fall back to unfiltered product results).
  static String toPostgresTextArrayLiteral(List<String> tags) {
    final seen = <String>{};
    final clean = StringBuffer('{');
    var first = true;
    for (final t in tags) {
      final s = t.trim();
      if (s.isNotEmpty && seen.add(s)) {
        if (!first) clean.write(',');
        clean.write(s);
        first = false;
      }
    }
    if (first) return ''; // all tags were empty
    clean.write('}');
    return clean.toString();
  }

  // ── Sub-category → specific DB tags (for server-side pre-pagination narrowing) ─

  static const Map<String, Map<String, List<String>>> _subToTags = {
    kSutKahvaltilik: {
      // Use only the precise Migros scraper tag for each sub.
      // The broad OFT grouping tags (sut_urunleri, peynir_yogurt) covered ALL
      // dairy and caused the server to return full-dairy pages, forcing the
      // client loop to scan hundreds of rows before finding the right subcategory.
      kSutSub: ['sut'],
      kYogurt: ['yogurt'],
      kPeynir: ['peynir'],
      kSutluTatli: ['sutlu_tatli_krema'],
      // Breakfast spreads share kahvaltiliklar/kahvaltilik — server returns all,
      // name-based client disambiguation picks the right sub (kBalRecel vs kGevrek).
      kBalRecel: ['kahvaltiliklar', 'kahvaltilik'],
      kTahinHelva: ['kahvaltiliklar', 'kahvaltilik'],
      kKremCikolata: ['findik_ezmesi', 'kahvaltiliklar', 'kahvaltilik'],
      kGevrek: ['kahvaltiliklar', 'kahvaltilik'],
    },
    kEtTavukBalik: {
      kSarkuteri: [
        'et_sarkuteri',
        'et-sarkulteri',
        'sucuk',
        'sosis',
        'salam',
        'jambon',
        'pastirma',
        'fume_et',
        'kavurma',
      ],
      kTavuk: ['beyaz_et'],
      kKirmiziEt: ['kirmizi_et'],
      kBalik: ['balik_deniz_urunleri', 'ton_konserve'],
    },
    kAtistirmalik: {
      // Use the single precise Migros tag per sub.  The compound OFT tags
      // (biskuvi_kek, cips_kraker, cikolata_gofret) span two subcategories each
      // and were leaking products from one sub into another sub's server filter.
      kBiskuvi: ['biskuvi'],
      kCips: ['cips'],
      kCikolata: ['cikolata', 'bar_kaplamalilar'],
      kKuruyemis: ['kuruyemis', 'saglikli_protein'],
      kSekerleme: ['sekerleme'],
      kKek: ['kek'],
      kKraker: ['kraker'],
      kBarKaplamalilar: ['bar_kaplamalilar', 'saglikli_protein'],
      kMisirPirincPatlagi: ['misir_pirinc_patlagi'],
      kKuruMeyve: ['kuru_meyve'],
      kSakiz: ['sakiz'],
    },
    kIcecek: {
      kGazli: ['gazli_icecek', 'enerji_icecekleri'],
      kGazsiz: ['gazsiz_icecek'],
      // kMeyvesuyu shares 'icecekler' tag — server narrowing not possible.
    },
    kTemelGida: {
      // CRITICAL: 'makarna_bakliyat' was here before; it caused the server to
      // return hundreds of pasta/legume rows when filtering for Soslar, forcing
      // the empty-page loop to scan them all before finding any sos products.
      kSoslar: ['sos'],
      kKonserve: ['konserve'],
      kMakarna: ['makarna_bakliyat'],
      kBakliyat: ['makarna_bakliyat'],
      kYag: ['makarna_bakliyat'],
      kUnSeker: ['makarna_bakliyat'],
    },
    kHazirDonuk: {
      kHazirYemek: ['hazir_yemek'],
    },
    // kDondurma: single tag 'dondurma_tatli' — no sub narrowing needed.
    // kBebek: single tag 'bebek_cocuk' — no sub narrowing needed.
  };

  /// Returns the specific DB `category_tags` values for [subCategory] under
  /// [mainCategory].  Returns empty if server-side tag narrowing is not
  /// possible for this subcategory (name-based disambiguation only), in which
  /// case callers should fall back to [mainCategoryToTags].
  static List<String> subCategoryToTags(
    String mainCategory,
    String subCategory,
  ) => _subToTags[mainCategory]?[subCategory] ?? const [];

  // ── Sub-category → search_keywords narrowing (for broad shared-tag subs) ──

  // Kahvaltiliklar subcategories share the kahvaltiliklar/kahvaltilik tag.
  // These search_keywords allow the server to narrow BEFORE pagination without
  // requiring a client-side canonical pass.
  static const Map<String, Map<String, List<String>>> _subToKeywords = {
    kSutKahvaltilik: {
      kBalRecel: [
        'bal',
        'honey',
        'recel',
        'receli',
        'reçel',
        'jam',
        'pekmez',
        'marmelat',
      ],
      kTahinHelva: ['tahin', 'helva'],
      kKremCikolata: [
        'cokokrem',
        'çokokrem',
        'nutella',
        'findik',
        'fındık',
        'fistik',
        'fıstık',
        'ezme',
      ],
      kGevrek: [
        'granola',
        'musli',
        'müsli',
        'gevrek',
        'yulaf',
        'lifalif',
        'corn',
        'flakes',
        'nesquik',
      ],
    },
  };

  // Subcategories where tag + keyword server filtering cannot distinguish the
  // sub from its siblings (all share one broad tag, no distinguishing keywords).
  // The client-side subcategory pass is still required for these.
  static const Set<String> _clientValidationRequired = {
    kMakarna, kBakliyat, kYag, kUnSeker, // all share makarna_bakliyat
    kMeyvesuyu, // no specific tag; falls back to all İçecek
  };

  /// Returns the `search_keywords` values used to narrow a broad-tag subcategory
  /// server-side (AND-ed with the tag overlap filter before `.range()`).
  /// Returns empty for exact-tag subcategories where tags alone are sufficient.
  static List<String> subCategoryToKeywords(
    String mainCategory,
    String subCategory,
  ) => _subToKeywords[mainCategory]?[subCategory] ?? const [];

  /// Returns true for subcategories where the server query alone cannot
  /// reliably determine membership (shared tags, no keyword distinction).
  /// These require an additional client-side pass to avoid false positives.
  static bool subCategoryRequiresClientValidation(String subCategory) =>
      _clientValidationRequired.contains(subCategory);

  // ── Core mapping ──────────────────────────────────────────────────────────

  /// Map a product to its canonical category.
  ///
  /// Priority:
  ///   1. DB [canonicalCategory] / [canonicalSubcategory] fields (set by migration
  ///      or scraper) → fastest and most accurate when populated
  ///   2. DB category_tags (set by scraper/admin pipeline) → deterministic tag-first
  ///   3. Product name keywords → sub-category tiebreaker
  ///   4. Default: [kDiger]
  static CanonicalCategory map({
    required List<String>? categoryTags,
    required String name,
    String? canonicalCategory,
    String? canonicalSubcategory,
  }) {
    // Priority 1: use pre-computed canonical fields from DB when available.
    if (canonicalCategory != null && canonicalCategory.isNotEmpty) {
      return CanonicalCategory(
        main: canonicalCategory,
        sub: (canonicalSubcategory?.isNotEmpty ?? false)
            ? canonicalSubcategory
            : null,
      );
    }

    final tags = categoryTags ?? const <String>[];
    final nameLower = name.toLowerCase();

    // ── New Migros scraper tags (exact sub-categories) ─────────────────────
    if (_hasTag(tags, 'sut')) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kSutSub);
    }
    if (_hasTag(tags, 'yogurt')) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kYogurt);
    }
    if (_hasTag(tags, 'peynir')) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kPeynir);
    }
    if (_hasTag(tags, 'sutlu_tatli_krema')) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kSutluTatli);
    }
    if (_hasAnyTag(tags, [
      'sucuk',
      'sosis',
      'salam',
      'jambon',
      'pastirma',
      'fume_et',
      'kavurma',
    ])) {
      return const CanonicalCategory(main: kEtTavukBalik, sub: kSarkuteri);
    }
    if (_hasTag(tags, 'beyaz_et')) {
      return const CanonicalCategory(main: kEtTavukBalik, sub: kTavuk);
    }
    if (_hasTag(tags, 'kirmizi_et')) {
      return const CanonicalCategory(main: kEtTavukBalik, sub: kKirmiziEt);
    }
    if (_hasTag(tags, 'balik_deniz_urunleri')) {
      return const CanonicalCategory(main: kEtTavukBalik, sub: kBalik);
    }
    if (_hasTag(tags, 'cips')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCips);
    }
    if (_hasTag(tags, 'biskuvi')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kBiskuvi);
    }
    if (_hasAnyTag(tags, ['cikolata', 'bar_kaplamalilar'])) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCikolata);
    }
    if (_hasTag(tags, 'kuruyemis')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kKuruyemis);
    }
    if (_hasTag(tags, 'gazli_icecek')) {
      return const CanonicalCategory(main: kIcecek, sub: kGazli);
    }
    if (_hasTag(tags, 'gazsiz_icecek')) {
      return const CanonicalCategory(main: kIcecek, sub: kGazsiz);
    }
    if (_hasTag(tags, 'sos')) {
      return const CanonicalCategory(main: kTemelGida, sub: kSoslar);
    }
    if (_hasTag(tags, 'konserve')) {
      return const CanonicalCategory(main: kTemelGida, sub: kKonserve);
    }
    if (_hasTag(tags, 'kahvaltiliklar')) {
      return CanonicalCategory(
        main: kSutKahvaltilik,
        sub: _kahvaltilikSub(nameLower),
      );
    }

    // ── Süt & Kahvaltılık ─────────────────────────────────────────────────
    if (_hasTag(tags, 'sut_urunleri')) {
      return CanonicalCategory(main: kSutKahvaltilik, sub: _sutSub(nameLower));
    }
    if (_hasTag(tags, 'peynir_yogurt')) {
      return CanonicalCategory(
        main: kSutKahvaltilik,
        sub: _peynirYogurtSub(nameLower),
      );
    }

    // ── Et, Tavuk & Balık ─────────────────────────────────────────────────
    if (_hasTag(tags, 'et_sarkuteri') || _hasTag(tags, 'et-sarkulteri')) {
      return CanonicalCategory(main: kEtTavukBalik, sub: _etSub(nameLower));
    }
    if (_hasTag(tags, 'ton_konserve')) {
      return const CanonicalCategory(main: kEtTavukBalik, sub: kBalik);
    }

    // ── Atıştırmalık ───────────────────────────────────────────────────────
    if (_hasTag(tags, 'cikolata_gofret')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCikolata);
    }
    if (_hasTag(tags, 'cips_kraker')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCips);
    }
    if (_hasTag(tags, 'biskuvi_kek')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kBiskuvi);
    }
    if (_hasTag(tags, 'atistirmalik')) {
      return CanonicalCategory(
        main: kAtistirmalik,
        sub: _atistirmalikSub(nameLower),
      );
    }
    if (_hasTag(tags, 'saglikli_protein')) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kKuruyemis);
    }

    // ── İçecek ────────────────────────────────────────────────────────────
    if (_hasTag(tags, 'enerji_icecekleri')) {
      return const CanonicalCategory(main: kIcecek, sub: kGazli);
    }
    if (_hasTag(tags, 'icecekler')) {
      return CanonicalCategory(main: kIcecek, sub: _icecekSub(nameLower));
    }

    // ── Temel Gıda ─────────────────────────────────────────────────────────
    if (_hasTag(tags, 'soslar')) {
      return const CanonicalCategory(main: kTemelGida, sub: kSoslar);
    }
    if (_hasTag(tags, 'makarna_bakliyat')) {
      return CanonicalCategory(main: kTemelGida, sub: _temelGidaSub(nameLower));
    }

    // ── Hazır & Donuk ─────────────────────────────────────────────────────
    if (_hasTag(tags, 'hazir_yemek')) {
      return const CanonicalCategory(main: kHazirDonuk, sub: kHazirYemek);
    }

    // ── Süt & Kahvaltılık (breakfast spreads) ────────────────────────────
    if (_hasTag(tags, 'findik_ezmesi')) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kKremCikolata);
    }
    if (_hasTag(tags, 'kahvaltilik')) {
      return CanonicalCategory(
        main: kSutKahvaltilik,
        sub: _kahvaltilikSub(nameLower),
      );
    }

    // ── Dedicated main categories ─────────────────────────────────────────
    if (_hasTag(tags, 'bebek_cocuk')) {
      return const CanonicalCategory(main: kBebek);
    }
    if (_hasTag(tags, 'dondurma_tatli')) {
      return const CanonicalCategory(main: kDondurma);
    }

    // ── Keyword fallback (no matching tag) ─────────────────────────────────
    return _keywordFallback(nameLower);
  }

  // ── Sub-category helpers ──────────────────────────────────────────────────

  static String _sutSub(String n) {
    if (_any(n, ['yoğurt', 'yogurt', 'kefir', 'yoghurt'])) {
      return kYogurt;
    }
    if (_any(n, [
      'peynir',
      'cheese',
      'kaşar',
      'kasar',
      'labne',
      'lor',
      'tulum',
      'ricotta',
      'gouda',
      'cheddar',
      'beyaz peynir',
    ])) {
      return kPeynir;
    }
    if (_any(n, [
      'muhallebi',
      'sütlaç',
      'sutlac',
      'krema',
      'sütlü tatlı',
      'sutlu tatli',
      'puding',
      'kaymak',
    ])) {
      return kSutluTatli;
    }
    if (_any(n, ['ayran'])) {
      return kYogurt;
    }
    return kSutSub;
  }

  static String _peynirYogurtSub(String n) {
    if (_any(n, ['yoğurt', 'yogurt', 'kefir', 'yoghurt', 'ayran'])) {
      return kYogurt;
    }
    return kPeynir;
  }

  static String _etSub(String n) {
    if (_any(n, ['tavuk', 'chicken', 'hindi', 'piliç', 'pilic'])) {
      return kTavuk;
    }
    if (_any(n, [
      'dana',
      'biftek',
      'koyun',
      'kuzu',
      'beef',
      'sığır',
      'sigir',
    ])) {
      return kKirmiziEt;
    }
    return kSarkuteri;
  }

  static String _atistirmalikSub(String n) {
    if (_any(n, [
      'badem',
      'fındık',
      'findik',
      'ceviz',
      'antep fıstığı',
      'fıstık',
      'fistik',
      'peanut',
      'kuruyemiş',
      'kuruyemis',
    ])) {
      return kKuruyemis;
    }
    if (_any(n, ['çikolata', 'cikolata', 'chocolate', 'gofret', 'wafer'])) {
      return kCikolata;
    }
    if (_any(n, [
      'cips',
      'chips',
      'doritos',
      'pringles',
      'cheetos',
      'kraker',
    ])) {
      return kCips;
    }
    return kBiskuvi;
  }

  static String _icecekSub(String n) {
    if (_any(n, [
      'kola',
      'cola',
      'gazoz',
      'soda',
      'gazlı',
      'gazli',
      'energy',
    ])) {
      return kGazli;
    }
    if (_any(n, [
      'meyve suyu',
      'juice',
      'limonata',
      'nektar',
      'portakal suyu',
    ])) {
      return kMeyvesuyu;
    }
    return kGazsiz;
  }

  static String _kahvaltilikSub(String n) {
    if (_any(n, [
      'bal',
      'honey',
      'reçel',
      'recel',
      'jam',
      'pekmez',
      'marmelat',
    ])) {
      return kBalRecel;
    }
    if (_any(n, ['tahin', 'helva', 'helvası'])) {
      return kTahinHelva;
    }
    if (_any(n, [
      'nutella',
      'çokokrem',
      'cokokrem',
      'krem çikolata',
      'krem cikolata',
      'fındık ezmesi',
      'findik ezmesi',
      'fıstık ezmesi',
    ])) {
      return kKremCikolata;
    }
    if (_any(n, [
      'granola',
      'müsli',
      'musli',
      'gevrek',
      'mısır gevreği',
      'misir gevregi',
      'yulaf',
      'cereal',
    ])) {
      return kGevrek;
    }
    return kBalRecel;
  }

  static String _temelGidaSub(String n) {
    if (_any(n, [
      'ketçap',
      'ketcap',
      'ketchup',
      'mayonez',
      'mayo',
      'sos',
      'sauce',
      'barbekü',
      'barbeku',
      'bbq',
      'pesto',
      'acuka',
      'salça',
      'salca',
    ])) {
      return kSoslar;
    }
    if (_any(n, ['konserve', 'konserve mısır', 'konserve misir', 'bezelye'])) {
      return kKonserve;
    }
    if (_any(n, [
      'makarna',
      'pasta',
      'spaghetti',
      'erişte',
      'eriste',
      'şehriye',
    ])) {
      return kMakarna;
    }
    if (_any(n, [
      'nohut',
      'chickpea',
      'mercimek',
      'lentil',
      'fasulye',
      'bean',
      'bulgur',
      'bakliyat',
    ])) {
      return kBakliyat;
    }
    if (_any(n, ['pirinç', 'pirinc', 'rice'])) {
      return kBakliyat;
    }
    if (_any(n, ['yağ', 'yag', 'oil', 'margarin'])) {
      return kYag;
    }
    if (_any(n, ['un', 'flour', 'şeker', 'seker', 'sugar', 'tuz', 'salt'])) {
      return kUnSeker;
    }
    return kMakarna;
  }

  // ── Keyword-only fallback (no DB tag matched) ─────────────────────────────

  static CanonicalCategory _keywordFallback(String n) {
    if (_any(n, ['süt', 'sut', 'milk', 'ayran', 'kefir'])) {
      return const CanonicalCategory(main: kSutKahvaltilik, sub: kSutSub);
    }

    if (_any(n, ['peynir', 'cheese', 'yoğurt', 'yogurt'])) {
      return CanonicalCategory(main: kSutKahvaltilik, sub: _peynirYogurtSub(n));
    }

    if (_any(n, ['bisküvi', 'biskuvi', 'biscuit', 'cookie', 'kurabiye'])) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kBiskuvi);
    }

    if (_any(n, ['çikolata', 'cikolata', 'chocolate', 'gofret'])) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCikolata);
    }

    if (_any(n, ['cips', 'chips', 'kraker'])) {
      return const CanonicalCategory(main: kAtistirmalik, sub: kCips);
    }

    if (_any(n, [
      'kola',
      'cola',
      'içecek',
      'icecek',
      'drink',
      'juice',
      'meyve suyu',
    ])) {
      return const CanonicalCategory(main: kIcecek);
    }

    if (_any(n, [
      'ketçap',
      'ketchup',
      'ketcap',
      'mayonez',
      'sos',
      'salça',
      'salca',
    ])) {
      return const CanonicalCategory(main: kTemelGida, sub: kSoslar);
    }

    if (_any(n, ['konserve'])) {
      return const CanonicalCategory(main: kTemelGida, sub: kKonserve);
    }

    if (_any(n, ['makarna', 'bakliyat', 'nohut', 'mercimek'])) {
      return const CanonicalCategory(main: kTemelGida, sub: kBakliyat);
    }

    return const CanonicalCategory(main: kDiger);
  }

  static bool matchesSubCategory({
    required String mainCategory,
    required String subCategory,
    required List<String>? categoryTags,
    required String name,
    String? normalizedName,
    List<String>? searchKeywords,
    String? canonicalCategory,
    String? canonicalSubcategory,
  }) {
    // Exact-tag fast path: for subcategories whose tags uniquely identify them
    // (requiresClientValidation=false), accept the product immediately if its
    // category_tags contain any of the subcategory's specific tags.  This
    // prevents a stale canonical_category from removing correctly-tagged products.
    // Shared-tag subcategories (kMakarna/kBakliyat/kYag all share makarna_bakliyat)
    // must skip this path and go through full name-based mapping instead.
    if (!subCategoryRequiresClientValidation(subCategory)) {
      final subSpecificTags = subCategoryToTags(mainCategory, subCategory);
      if (subSpecificTags.isNotEmpty) {
        final productTagSet = (categoryTags ?? const <String>[]).toSet();
        if (subSpecificTags.any(productTagSet.contains)) return true;
      }
    }

    final mapped = map(
      categoryTags: categoryTags,
      name: name,
      canonicalCategory: canonicalCategory,
      canonicalSubcategory: canonicalSubcategory,
    );
    if (mapped.main != mainCategory) return false;
    if (mapped.sub == subCategory) return true;
    if (mainCategory != kAtistirmalik) return false;

    final tags = (categoryTags ?? const <String>[]).map(_normalizeText).toSet();
    final haystack = _normalizeText(
      [
        name,
        normalizedName ?? '',
        ...(searchKeywords ?? const <String>[]),
      ].join(' '),
    );

    return _matchesSnackSubCategory(
      mapped: mapped,
      subCategory: subCategory,
      tags: tags,
      haystack: haystack,
    );
  }

  static bool _matchesSnackSubCategory({
    required CanonicalCategory mapped,
    required String subCategory,
    required Set<String> tags,
    required String haystack,
  }) {
    bool hasTag(String tag) => tags.contains(_normalizeText(tag));
    bool hasAnyTag(Iterable<String> values) =>
        values.any((value) => hasTag(value));
    bool hasAnyTerm(Iterable<String> values) =>
        values.any((value) => _containsNormalizedTerm(haystack, value));

    switch (subCategory) {
      case kBiskuvi:
        return hasAnyTag(['biskuvi', 'biskuvi_kek']) &&
                !hasAnyTerm(['kek', 'cake', 'muffin', 'brownie']) ||
            hasAnyTerm(['bisküvi', 'biskuvi', 'biscuit', 'cookie', 'kurabiye']);
      case kCips:
        return hasAnyTag(['cips', 'cips_kraker']) &&
                !hasAnyTerm(['kraker', 'cracker']) ||
            hasAnyTerm([
              'cips',
              'chips',
              'doritos',
              'lays',
              'pringles',
              'ruffles',
              'cheetos',
            ]);
      case kCikolata:
        final breakfastSpread =
            mapped.main == kSutKahvaltilik ||
            hasAnyTag(['findik_ezmesi']) ||
            hasAnyTerm([
              'krem çikolata',
              'krem cikolata',
              'fındık ezmesi',
              'findik ezmesi',
              'fıstık ezmesi',
              'fistik ezmesi',
              'nutella',
              'çokokrem',
              'cokokrem',
              'spread',
              'ezme',
            ]);
        final excluded =
            hasAnyTag([
              'gazli_icecek',
              'gazsiz_icecek',
              'sos',
              'konserve',
              'sut',
              'yogurt',
              'peynir',
              'kahvaltiliklar',
            ]) ||
            hasAnyTerm([
              'gazoz',
              'cola',
              'kola',
              'ketçap',
              'ketcap',
              'mayonez',
              'yoğurt',
              'yogurt',
              'peynir',
            ]);
        if (breakfastSpread || excluded) return false;
        return hasAnyTag(['cikolata_gofret', 'cikolata', 'bar_kaplamalilar']) ||
            hasAnyTerm([
              'çikolata',
              'cikolata',
              'gofret',
              'wafer',
              'bitter',
              'sütlü çikolata',
              'sutlu cikolata',
              'kaplamalı',
              'kaplamali',
            ]) ||
            (hasAnyTerm(['bar']) &&
                hasAnyTerm([
                  'çikolata',
                  'cikolata',
                  'wafer',
                  'kaplamalı',
                  'kaplamali',
                ]));
      case kKuruyemis:
        return hasAnyTag(['kuruyemis', 'saglikli_protein']) ||
            hasAnyTerm([
              'kuruyemiş',
              'kuruyemis',
              'badem',
              'fındık',
              'findik',
              'ceviz',
              'fıstık',
              'fistik',
              'kaju',
              'antep',
            ]);
      case kSekerleme:
        return hasTag('sekerleme') ||
            hasAnyTerm([
              'şekerleme',
              'sekerleme',
              'bonbon',
              'draje',
              'toffee',
              'jelibon',
              'gummy',
              'lolipop',
              'lollipop',
              'pastil',
            ]);
      case kKek:
        return hasAnyTag(['biskuvi_kek', 'kek']) ||
            hasAnyTerm(['kek', 'cake', 'muffin', 'brownie', 'popkek']);
      case kKraker:
        return hasAnyTag(['cips_kraker', 'kraker']) ||
            hasAnyTerm([
              'kraker',
              'cracker',
              'çubuk kraker',
              'cubuk kraker',
              'crax',
            ]);
      case kBarKaplamalilar:
        return hasAnyTag([
              'bar_kaplamalilar',
              'cikolata_gofret',
              'saglikli_protein',
            ]) ||
            hasAnyTerm([
              'bar',
              'kaplamalı',
              'kaplamali',
              'protein bar',
              'granola bar',
              'albeni',
              'metro',
              'twix',
              'snickers',
              'bounty',
            ]);
      case kMisirPirincPatlagi:
        return hasTag('misir_pirinc_patlagi') ||
            hasAnyTerm([
              'mısır patlağı',
              'misir patlagi',
              'pirinç patlağı',
              'pirinc patlagi',
              'rice cake',
              'popcorn',
            ]);
      case kKuruMeyve:
        return hasTag('kuru_meyve') ||
            hasAnyTerm([
              'kuru meyve',
              'dried fruit',
              'kuru kayısı',
              'kuru incir',
              'hurma',
              'üzüm',
              'uzum',
            ]);
      case kSakiz:
        return hasTag('sakiz') ||
            hasAnyTerm(['sakız', 'sakiz', 'chewing gum', 'gum']);
      default:
        return false;
    }
  }

  // ── Low-level helpers ─────────────────────────────────────────────────────

  static String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u');
  }

  static bool _containsNormalizedTerm(String haystack, String term) {
    final normalizedTerm = _normalizeText(term).trim();
    if (haystack.isEmpty || normalizedTerm.isEmpty) return false;
    final escaped = RegExp.escape(normalizedTerm);
    return RegExp(
      '(^|[^a-z0-9])$escaped([^a-z0-9]|\$)',
      caseSensitive: false,
    ).hasMatch(haystack);
  }

  static bool _hasTag(List<String> tags, String tag) => tags.contains(tag);

  static bool _hasAnyTag(List<String> tags, List<String> needles) =>
      needles.any(tags.contains);

  static bool _any(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
