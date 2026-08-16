import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Controlled category-derived nutrition-basis fallback.
///
/// Product decision (see legacy_scoring_evidence_recovery.dart's basis
/// resolution step): a product whose independent source evidence only ever
/// declares a GENERIC per-100 basis (e.g. Migros' "100 g / ml" header) may
/// still resolve an exact basis deterministically when its OWN taxonomy
/// tags unambiguously identify a solid or liquid product family. This is
/// never AI, never product-name fuzzy matching, and never the broad
/// [ScoringCategory] alone (which is far too coarse — `generalFood` spans
/// everything from biscuits to soups) — it is a closed, explicit allowlist
/// of real `category_tags` values already observed in this project's
/// production taxonomy (see scoring_category_resolver.dart and the
/// taxonomy-closure inventory this allowlist was audited against).
///
/// Deliberately excludes any tag whose physical form is not reliably
/// encoded by the tag alone — soups, sauces/dressings, concentrates,
/// powders prepared with water, meal replacements, ice cream/frozen
/// desserts, and generic/broad "breakfast basket"-style tags all remain
/// unresolved (`NutritionBasis.unknown`) on purpose, even though some of
/// their members happen to be solid or liquid — the family as a whole is
/// not unambiguous.
///
/// This resolver is intentionally the ONLY place this allowlist is
/// defined — nothing here re-derives category/eligibility/basis-parsing
/// logic that lives elsewhere, and it has no opinion on scoring math,
/// readiness, or the public audit gate.
class CategoryDerivedBasisResolver {
  const CategoryDerivedBasisResolver();

  // Unambiguous solid (per-100g) families. Every tag here is a real,
  // observed `category_tags` value (see scoring_category_resolver.dart's
  // _legacyGeneralFoodTags/_redMeatTags/_nutSeedTags and the taxonomy
  // read-only inventory) whose physical form — solid/paste/mass-based —
  // is reliable regardless of the specific product within the family.
  static const _per100gTags = {
    // Biscuits, wafers, crackers, confectionery, snacks.
    'biskuvi',
    'biskuvi_kek',
    'kraker',
    'cips_kraker',
    'galeta_grissini_gevrek',
    'cips',
    'sekerleme',
    'misir_pirinc_patlagi',
    'misir_ve_pirinc_patlagi',
    'kuru_meyve',
    'sakiz',
    'bar_kaplamalilar',
    // Chocolate/confectionery solids.
    'cikolata',
    'cikolata_gofret',
    // Pasta, rice/grains, legumes.
    'makarna',
    'makarna_bakliyat',
    'bakliyat',
    // Canned fish (unambiguously weight-declared regardless of packing
    // liquid) — never the bare/generic 'konserve' tag, which spans
    // soup-adjacent conserves this resolver deliberately stays out of.
    'ton_konserve',
    'balik_deniz_urunleri',
    'beyaz_et',
    // Processed solid meat products (red-meat family; percentage/primary-
    // ingredient readiness gating for the redMeat SCORING category is a
    // separate, untouched concern — this only says "solid, per-100g").
    'kirmizi_et',
    'sucuk',
    'sosis',
    'salam',
    'pastirma',
    'kavurma',
    // Cheese.
    'peynir',
    // Nuts/seeds and mass-based nut/seed pastes.
    'kuruyemis',
    'findik_ezmesi',
    // Yogurt: internationally declared per-100g even though spoonable.
    'yogurt',
    // Bread/bakery solids.
    'kek',
    'pasta',
    'kuru_pasta',
    'ekmek',
    'unlu_mamul',
    'firin_pastane',
    'firin',
    'hamur_pasta_malzemeleri',
    // Dry/bagged/ground tea and coffee — confirmed via saved production
    // samples (this session's taxonomy work) to be dry solid products in
    // this catalogue, never ready-to-drink beverages.
    'cay',
    'kahve',
    // Table olives (a distinct, solid conserve product from olive OIL).
    'zeytin',
    // Edible oils: internationally declared per-100g by mass, never
    // per-100ml, despite being physically liquid.
    'sivi_yag',
    // Solid frozen foods with a reliably solid physical form.
    'hazir_manti',
    'dondurulmus_manti',
    'paketli_sandvic',
    'pide_lahmacun',
    'dondurulmus_pizza',
    'dondurulmus_patates',
    'dondurulmus_sebze',
    'dondurulmus_borek',
    'dondurulmus_firin_urunleri',
    'dondurulmus_sushi',
    'dondurulmus_meyve',
  };

  // Unambiguous liquid (per-100ml) families — ready-to-drink beverages
  // only.
  static const _per100mlTags = {
    'gazli_icecek',
    'gazsiz_icecek',
    'enerji_icecekleri',
    'meyve_suyu',
    'maden_suyu',
    'sut',
  };

  /// Resolves a deterministic basis from [categoryTags] alone. Returns
  /// [NutritionBasis.unknown] when no tag unambiguously identifies a
  /// solid/liquid family, OR when the tags themselves disagree (a tag from
  /// each allowlist present at once) — fails closed rather than guessing.
  NutritionBasis resolve(Iterable<String> categoryTags) {
    final tags = categoryTags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final matchesSolid = tags.intersection(_per100gTags).isNotEmpty;
    final matchesLiquid = tags.intersection(_per100mlTags).isNotEmpty;
    if (matchesSolid && matchesLiquid) return NutritionBasis.unknown;
    if (matchesSolid) return NutritionBasis.per100g;
    if (matchesLiquid) return NutritionBasis.per100ml;
    return NutritionBasis.unknown;
  }
}
