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
      for (final tag in tags.intersection(_directBeverageTags)) {
        addCandidate(
          ScoringCategory.beverage,
          CategoryEvidenceSource.trustedCategoryTag,
          tag,
          CategoryResolutionReason.resolvedFromTrustedTag,
        );
      }

      if (tags.contains('peynir')) {
        _resolveCheeseCandidate(
          facts: facts,
          addCandidate: addCandidate,
          unresolvedReasons: unresolvedReasons,
          source: CategoryEvidenceSource.trustedCategoryTag,
          value: 'peynir',
          reason: CategoryResolutionReason.resolvedFromTrustedTag,
        );
      }

      if (tags.intersection(_redMeatTags).isNotEmpty) {
        _resolveRedMeatCandidate(
          input: input,
          addCandidate: addCandidate,
          unresolvedReasons: unresolvedReasons,
          source: CategoryEvidenceSource.trustedCategoryTag,
          value: tags.intersection(_redMeatTags).first,
          reason: CategoryResolutionReason.resolvedFromTrustedTag,
        );
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
          _resolveCheeseCandidate(
            facts: facts,
            addCandidate: addCandidate,
            unresolvedReasons: unresolvedReasons,
            source: CategoryEvidenceSource.trustedCanonicalSubcategory,
            value: subcategory,
            reason: CategoryResolutionReason
                .resolvedFromTrustedCanonicalSubcategory,
          );
        } else if (subcategory == 'kırmızı et') {
          _resolveRedMeatCandidate(
            input: input,
            addCandidate: addCandidate,
            unresolvedReasons: unresolvedReasons,
            source: CategoryEvidenceSource.trustedCanonicalSubcategory,
            value: subcategory,
            reason: CategoryResolutionReason
                .resolvedFromTrustedCanonicalSubcategory,
          );
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
