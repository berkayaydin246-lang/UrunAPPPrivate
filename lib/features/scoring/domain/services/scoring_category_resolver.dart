import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringCategoryResolver {
  const ScoringCategoryResolver();

  static const _directBeverageTags = {
    'gazli_icecek',
    'gazsiz_icecek',
    'enerji_icecekleri',
    'meyve_suyu',
    'maden_suyu',
  };

  static const _legacyDirectBeverageTags = {'sut'};

  static const _legacyGeneralFoodTags = {
    'yogurt',
    'sutlu_tatli_krema',
    'kahvaltilik',
    'kahvaltiliklar',
    'beyaz_et',
    'balik_deniz_urunleri',
    'ton_konserve',
    'biskuvi_kek',
    'cips_kraker',
    'cikolata_gofret',
    'atistirmalik',
    'saglikli_protein',
    'biskuvi',
    'cips',
    'cikolata',
    'bar_kaplamalilar',
    'kek',
    'kraker',
    'sekerleme',
    'misir_pirinc_patlagi',
    // Same real-world product family as 'misir_pirinc_patlagi' above under
    // a differently-formatted production tag string (inserts '_ve_' =
    // "and") — confirmed via the read-only taxonomy-closure inventory
    // (Section: FINAL scoring-category taxonomy gap). Not a new category
    // interpretation, just the same one under a second spelling.
    'misir_ve_pirinc_patlagi',
    'kuru_meyve',
    'sakiz',
    'makarna_bakliyat',
    'soslar',
    'sos',
    'konserve',
    'makarna',
    'bakliyat',
    'tuz_baharat_harc',
    // Dry/loose tea and ground/whole-bean coffee are sold by weight
    // (per-100g labels), not as prepared drinks — they must never be
    // confused with the prepared-beverage tags in _directBeverageTags
    // (gazli_icecek/gazsiz_icecek/meyve_suyu/maden_suyu, all per-100ml).
    // Exemption from mandatory nutritional declaration does not by itself
    // make a product ineligible: when an adequate trusted declaration
    // exists, these score via the ordinary solid-food formula like any
    // other generalFood product. Confirmed via saved production samples
    // (tmp/legacy_recovery_root_cause_probe_v2_output.txt) that 'cay'/
    // 'kahve'-tagged rows in this catalogue are dry/bagged/ground products
    // (e.g. "Migros Demlik Poşet Siyah Çay", "Joe&Co Filtre Kahve"), never
    // ready-to-drink beverages.
    'cay',
    'kahve',
    'hamur_pasta_malzemeleri',
    'ozel_beslenme_urunleri',
    'hazir_yemek',
    'pratik_yemek',
    'meze',
    'hazir_manti',
    'paketli_sandvic',
    'dondurulmus_pizza',
    'dondurulmus_patates',
    'dondurulmus_sebze',
    'dondurulmus_sushi',
    'dondurulmus_meyve',
    'dondurulmus_borek',
    'dondurulmus_manti',
    'pide_lahmacun',
    'dondurulmus_tatli',
    'dondurulmus_firin_urunleri',
    'dondurulmus_hazir_yemek',
    'dondurma_tatli',
    'kap_dondurma',
    'tek_dondurma',
    'bebek_cocuk',
    'bebek_beslenme',
    'bebek_atistirmalik',
    'firin_pastane',
    'ekmek',
    'unlu_mamul',
    'firin',
    'kuru_pasta',
    'galeta_grissini_gevrek',
    'tatli',
    'pasta',
    // Table/jarred olives — an ordinary solid conserve-style food, never a
    // beverage/cheese/red-meat product, and never the fatsOilsNutsSeeds
    // branch (that branch is reserved for products whose fat/nut/seed
    // content methodology applies to, e.g. bottled oil or >50% nut/seed
    // products — not brined table olives). A distinct Migros department
    // from 'zeytinyağı' (olive OIL, which falls under 'sivi_yag' above),
    // confirmed via the read-only taxonomy-closure inventory.
    'zeytin',
  };

  static const _legacyGeneralFoodCanonicalCategories = {
    'atıştırmalık',
    'kahvaltılıklar',
    'sos / konserve / hazır gıda',
    'temel gıda',
    'hazır & donuk',
    'dondurma',
    'fırın & pastane',
    'bebek gıda',
  };

  static const _redMeatTags = {
    'kirmizi_et',
    'sucuk',
    'sosis',
    'salam',
    'pastirma',
    'kavurma',
  };

  static const _nutSeedTags = {'kuruyemis', 'findik_ezmesi'};

  static const _beverageSubcategories = {
    'gazlı içecek',
    'gazsız içecek',
    'meyve suyu',
    'maden suyu',
  };

  ScoringCategoryEvidence resolve(ScoringCategoryResolverInput input) {
    final facts = input.facts;

    if (facts.hasTrustedOutOfScopeFact) {
      return ScoringCategoryEvidence(
        resolvedCategory: ScoringCategory.outOfScope,
        source: CategoryEvidenceSource.classificationFacts,
        reasons: const [CategoryResolutionReason.outOfScopeFact],
      );
    }

    final explicit = input.explicitCategory;
    final explicitCategory = explicit?.trustedValue;
    if (explicitCategory != null &&
        explicitCategory != ScoringCategory.unknown) {
      final incompleteReason = _explicitCategoryIncompleteReason(
        explicitCategory,
        facts,
      );
      if (incompleteReason != null) {
        return ScoringCategoryEvidence.unknown(
          evidenceValues: [explicitCategory.name],
          reasons: [incompleteReason],
        );
      }
      final isAdmin = explicit!.provenance == EvidenceProvenance.adminVerified;
      return ScoringCategoryEvidence(
        resolvedCategory: explicitCategory,
        source: isAdmin
            ? CategoryEvidenceSource.manualAdminVerification
            : CategoryEvidenceSource.explicitScoringMetadata,
        evidenceValues: [explicitCategory.name],
        reasons: const [CategoryResolutionReason.resolvedFromExplicitMetadata],
      );
    }

    final candidates = <ScoringCategory, _CategoryCandidate>{};
    final unresolvedReasons = <CategoryResolutionReason>{};

    void addCandidate(
      ScoringCategory category,
      CategoryEvidenceSource source,
      String value,
      CategoryResolutionReason reason,
    ) {
      candidates.putIfAbsent(
        category,
        () => _CategoryCandidate(category, source, value, reason),
      );
    }

    final plainWater = facts.isPlainWater?.trustedValue;
    if (plainWater == true) {
      addCandidate(
        ScoringCategory.beverage,
        CategoryEvidenceSource.classificationFacts,
        'isPlainWater=true',
        CategoryResolutionReason.plainWaterConfirmed,
      );
    }
    if (facts.isBeverage?.trustedValue == true) {
      addCandidate(
        ScoringCategory.beverage,
        CategoryEvidenceSource.classificationFacts,
        'isBeverage=true',
        CategoryResolutionReason.resolvedFromClassificationFacts,
      );
    }
    if (facts.isDrinkableDairy?.trustedValue == true) {
      addCandidate(
        ScoringCategory.beverage,
        CategoryEvidenceSource.classificationFacts,
        'isDrinkableDairy=true',
        CategoryResolutionReason.resolvedFromClassificationFacts,
      );
    }

    final hasTaxonomyValues =
        input.categoryTags.isNotEmpty ||
        _clean(input.canonicalCategory) != null ||
        _clean(input.canonicalSubcategory) != null;
    final taxonomyTrusted =
        input.taxonomyProvenance != EvidenceProvenance.unknown &&
        input.taxonomyVerification != EvidenceVerification.rejected;

    if (hasTaxonomyValues && !taxonomyTrusted) {
      unresolvedReasons.add(CategoryResolutionReason.untrustedTaxonomyEvidence);
    }

    if (taxonomyTrusted) {
      final tags = input.categoryTags.map(_normalize).toSet();
      final beverageTags = input.allowLegacyCompatibility
          ? {..._directBeverageTags, ..._legacyDirectBeverageTags}
          : _directBeverageTags;
      for (final tag in tags.intersection(beverageTags)) {
        addCandidate(
          ScoringCategory.beverage,
          CategoryEvidenceSource.trustedCategoryTag,
          tag,
          CategoryResolutionReason.resolvedFromTrustedTag,
        );
      }

      if (tags.contains('peynir')) {
        if (input.allowLegacyCompatibility) {
          addCandidate(
            ScoringCategory.cheese,
            CategoryEvidenceSource.trustedCategoryTag,
            'peynir',
            CategoryResolutionReason.resolvedFromLegacyTaxonomy,
          );
        } else {
          _resolveCheeseCandidate(
            facts: facts,
            addCandidate: addCandidate,
            unresolvedReasons: unresolvedReasons,
            source: CategoryEvidenceSource.trustedCategoryTag,
            value: 'peynir',
            reason: CategoryResolutionReason.resolvedFromTrustedTag,
          );
        }
      }

      if (tags.intersection(_redMeatTags).isNotEmpty) {
        final redMeatTag = tags.intersection(_redMeatTags).first;
        if (input.allowLegacyCompatibility && redMeatTag == 'kirmizi_et') {
          addCandidate(
            ScoringCategory.redMeat,
            CategoryEvidenceSource.trustedCategoryTag,
            redMeatTag,
            CategoryResolutionReason.resolvedFromLegacyTaxonomy,
          );
        } else {
          _resolveRedMeatCandidate(
            input: input,
            addCandidate: addCandidate,
            unresolvedReasons: unresolvedReasons,
            source: CategoryEvidenceSource.trustedCategoryTag,
            value: redMeatTag,
            reason: CategoryResolutionReason.resolvedFromTrustedTag,
          );
        }
      }

      if (tags.contains('sivi_yag') &&
          facts.isCompoundProduct?.trustedValue != true) {
        addCandidate(
          ScoringCategory.fatsOilsNutsSeeds,
          CategoryEvidenceSource.trustedCategoryTag,
          'sivi_yag',
          CategoryResolutionReason.resolvedFromTrustedTag,
        );
      }

      if (tags.intersection(_nutSeedTags).isNotEmpty) {
        _resolveNutSeedCandidate(
          input: input,
          addCandidate: addCandidate,
          unresolvedReasons: unresolvedReasons,
          source: CategoryEvidenceSource.trustedCategoryTag,
          value: tags.intersection(_nutSeedTags).first,
          reason: CategoryResolutionReason.resolvedFromTrustedTag,
        );
      }

      final subcategory = _clean(input.canonicalSubcategory);
      if (subcategory != null) {
        if (_beverageSubcategories.contains(subcategory)) {
          addCandidate(
            ScoringCategory.beverage,
            CategoryEvidenceSource.trustedCanonicalSubcategory,
            subcategory,
            CategoryResolutionReason.resolvedFromTrustedCanonicalSubcategory,
          );
        } else if (subcategory == 'peynir') {
          if (input.allowLegacyCompatibility) {
            addCandidate(
              ScoringCategory.cheese,
              CategoryEvidenceSource.trustedCanonicalSubcategory,
              subcategory,
              CategoryResolutionReason.resolvedFromLegacyTaxonomy,
            );
          } else {
            _resolveCheeseCandidate(
              facts: facts,
              addCandidate: addCandidate,
              unresolvedReasons: unresolvedReasons,
              source: CategoryEvidenceSource.trustedCanonicalSubcategory,
              value: subcategory,
              reason: CategoryResolutionReason
                  .resolvedFromTrustedCanonicalSubcategory,
            );
          }
        } else if (subcategory == 'kırmızı et') {
          if (input.allowLegacyCompatibility) {
            addCandidate(
              ScoringCategory.redMeat,
              CategoryEvidenceSource.trustedCanonicalSubcategory,
              subcategory,
              CategoryResolutionReason.resolvedFromLegacyTaxonomy,
            );
          } else {
            _resolveRedMeatCandidate(
              input: input,
              addCandidate: addCandidate,
              unresolvedReasons: unresolvedReasons,
              source: CategoryEvidenceSource.trustedCanonicalSubcategory,
              value: subcategory,
              reason: CategoryResolutionReason
                  .resolvedFromTrustedCanonicalSubcategory,
            );
          }
        } else if (subcategory == 'kuruyemiş') {
          _resolveNutSeedCandidate(
            input: input,
            addCandidate: addCandidate,
            unresolvedReasons: unresolvedReasons,
            source: CategoryEvidenceSource.trustedCanonicalSubcategory,
            value: subcategory,
            reason: CategoryResolutionReason
                .resolvedFromTrustedCanonicalSubcategory,
          );
        } else if (subcategory == 'yağ' &&
            facts.isCompoundProduct?.trustedValue == false) {
          addCandidate(
            ScoringCategory.fatsOilsNutsSeeds,
            CategoryEvidenceSource.trustedCanonicalSubcategory,
            subcategory,
            CategoryResolutionReason.resolvedFromTrustedCanonicalSubcategory,
          );
        }
      }

      if (input.allowLegacyCompatibility &&
          candidates.isEmpty &&
          !_hasUnresolvedSpecialCategory(unresolvedReasons)) {
        final ordinaryTag = tags
            .intersection(_legacyGeneralFoodTags)
            .firstOrNull;
        if (ordinaryTag != null) {
          addCandidate(
            ScoringCategory.generalFood,
            CategoryEvidenceSource.trustedCategoryTag,
            ordinaryTag,
            CategoryResolutionReason.resolvedFromLegacyTaxonomy,
          );
        } else {
          final canonicalCategory = _clean(input.canonicalCategory);
          if (tags.isEmpty &&
              canonicalCategory != null &&
              _legacyGeneralFoodCanonicalCategories.contains(
                canonicalCategory,
              )) {
            addCandidate(
              ScoringCategory.generalFood,
              CategoryEvidenceSource.trustedCanonicalCategory,
              canonicalCategory,
              CategoryResolutionReason.resolvedFromLegacyTaxonomy,
            );
          }
        }
      }
    }

    if (candidates.length > 1) {
      return ScoringCategoryEvidence.unknown(
        evidenceValues: candidates.values.map((candidate) => candidate.value),
        reasons: {
          ...unresolvedReasons,
          CategoryResolutionReason.conflictingEvidence,
        },
      );
    }

    if (candidates.length == 1) {
      final candidate = candidates.values.single;
      return ScoringCategoryEvidence(
        resolvedCategory: candidate.category,
        source: candidate.source,
        evidenceValues: [candidate.value],
        reasons: [candidate.reason],
      );
    }

    final canonicalCategory = _clean(input.canonicalCategory);
    final canonicalSubcategory = _clean(input.canonicalSubcategory);
    return ScoringCategoryEvidence.unknown(
      evidenceValues: [
        ...input.categoryTags,
        ?canonicalCategory,
        ?canonicalSubcategory,
      ],
      reasons: {
        ...unresolvedReasons,
        CategoryResolutionReason.insufficientEvidence,
      },
    );
  }

  CategoryResolutionReason? _explicitCategoryIncompleteReason(
    ScoringCategory category,
    ScoringClassificationFacts facts,
  ) {
    switch (category) {
      case ScoringCategory.redMeat:
        final percentage = facts.redMeatPercentage?.trustedValue;
        if (!_validPercentage(percentage) ||
            percentage! < 20 ||
            facts.redMeatIsPrimaryIngredient?.trustedValue != true) {
          return CategoryResolutionReason.redMeatEvidenceIncomplete;
        }
        break;
      case ScoringCategory.cheese:
        if (facts.isPlantBasedCheeseAlternative?.trustedValue != false ||
            facts.isCompoundProduct?.trustedValue != false) {
          return CategoryResolutionReason.cheeseEvidenceIncomplete;
        }
        break;
      case ScoringCategory.fatsOilsNutsSeeds:
        final percentage = facts.nutSeedPercentage?.trustedValue;
        if (percentage != null &&
            (!_validPercentage(percentage) || percentage <= 50)) {
          return CategoryResolutionReason.nutSeedPercentageUnknown;
        }
        break;
      case ScoringCategory.generalFood:
      case ScoringCategory.beverage:
      case ScoringCategory.outOfScope:
      case ScoringCategory.unknown:
        break;
    }
    return null;
  }

  void _resolveCheeseCandidate({
    required ScoringClassificationFacts facts,
    required void Function(
      ScoringCategory,
      CategoryEvidenceSource,
      String,
      CategoryResolutionReason,
    )
    addCandidate,
    required Set<CategoryResolutionReason> unresolvedReasons,
    required CategoryEvidenceSource source,
    required String value,
    required CategoryResolutionReason reason,
  }) {
    final plantAlternative = facts.isPlantBasedCheeseAlternative?.trustedValue;
    final compound = facts.isCompoundProduct?.trustedValue;
    if (plantAlternative == false && compound == false) {
      addCandidate(ScoringCategory.cheese, source, value, reason);
    } else if (plantAlternative == null || compound == null) {
      unresolvedReasons.add(CategoryResolutionReason.cheeseEvidenceIncomplete);
    }
  }

  void _resolveRedMeatCandidate({
    required ScoringCategoryResolverInput input,
    required void Function(
      ScoringCategory,
      CategoryEvidenceSource,
      String,
      CategoryResolutionReason,
    )
    addCandidate,
    required Set<CategoryResolutionReason> unresolvedReasons,
    required CategoryEvidenceSource source,
    required String value,
    required CategoryResolutionReason reason,
  }) {
    final percentage = input.facts.redMeatPercentage?.trustedValue;
    final isPrimary = input.facts.redMeatIsPrimaryIngredient?.trustedValue;
    if (_validPercentage(percentage) &&
        percentage! >= 20 &&
        isPrimary == true) {
      addCandidate(ScoringCategory.redMeat, source, value, reason);
    } else {
      unresolvedReasons.add(CategoryResolutionReason.redMeatEvidenceIncomplete);
    }
  }

  void _resolveNutSeedCandidate({
    required ScoringCategoryResolverInput input,
    required void Function(
      ScoringCategory,
      CategoryEvidenceSource,
      String,
      CategoryResolutionReason,
    )
    addCandidate,
    required Set<CategoryResolutionReason> unresolvedReasons,
    required CategoryEvidenceSource source,
    required String value,
    required CategoryResolutionReason reason,
  }) {
    final percentage = input.facts.nutSeedPercentage?.trustedValue;
    if (_validPercentage(percentage) && percentage! > 50) {
      addCandidate(ScoringCategory.fatsOilsNutsSeeds, source, value, reason);
    } else {
      unresolvedReasons.add(CategoryResolutionReason.nutSeedPercentageUnknown);
    }
  }

  static bool _validPercentage(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 100;

  static bool _hasUnresolvedSpecialCategory(
    Set<CategoryResolutionReason> reasons,
  ) =>
      reasons.contains(CategoryResolutionReason.redMeatEvidenceIncomplete) ||
      reasons.contains(CategoryResolutionReason.nutSeedPercentageUnknown) ||
      reasons.contains(CategoryResolutionReason.cheeseEvidenceIncomplete);

  static String _normalize(String value) => value.trim().toLowerCase();

  static String? _clean(String? value) {
    if (value == null) return null;
    final normalized = _normalize(value);
    return normalized.isEmpty ? null : normalized;
  }
}

class _CategoryCandidate {
  final ScoringCategory category;
  final CategoryEvidenceSource source;
  final String value;
  final CategoryResolutionReason reason;

  const _CategoryCandidate(this.category, this.source, this.value, this.reason);
}
