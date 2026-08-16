import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

/// Maximally-permissive, trusted classification facts — chosen so that
/// EVERY fact-gated special-branch mapping the resolver has (red meat's
/// percentage/primary-ingredient gate, cheese's plant-based/compound
/// exclusions, fats/oils/nuts/seeds' nut-share gate) would pass if the tag
/// itself is wired to that branch at all. This exists ONLY to measure
/// "does the resolver have ANY mapping mechanism for this tag" — a pure
/// taxonomy-coverage question — without conflating it with "does this
/// specific historical product also happen to have the separate
/// classification-fact evidence it would need" (a genuinely different,
/// already-tracked readiness concern; see 'sucuk'/'sosis'/etc. in
/// scoring_category_resolver_test.dart, which deliberately stay unknown
/// under empty facts even though the resolver has always known how to map
/// them). Never includes any `hasTrustedOutOfScopeFact` value — that would
/// short-circuit every tag to outOfScope before tag evaluation even runs,
/// and eligibility is deliberately out of scope for this measurement.
const _maximallyPermissiveFacts = ScoringClassificationFacts(
  redMeatPercentage: EvidenceValue<double>(
    value: 100,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  ),
  redMeatIsPrimaryIngredient: EvidenceValue<bool>(
    value: true,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  ),
  nutSeedPercentage: EvidenceValue<double>(
    value: 100,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  ),
  isPlantBasedCheeseAlternative: EvidenceValue<bool>(
    value: false,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  ),
  isCompoundProduct: EvidenceValue<bool>(
    value: false,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  ),
);

/// Section (taxonomy closure pass): a pure, read-only measurement of how
/// many raw `category_tags` values the live [ScoringCategoryResolver] has
/// SOME deterministic mapping mechanism for, given a list of production
/// tag strings. Takes no database connection and performs no I/O — the
/// caller supplies the tag inventory (e.g. from a prior read-only
/// production query) and this only ever runs the existing resolver
/// against it, under the exact same trust configuration the legacy
/// bulk-recovery pipeline already uses in production
/// (`allowLegacyCompatibility: true`, `databaseImport`/`unverified`
/// taxonomy — see legacy_scoring_evidence_recovery.dart), combined with
/// [_maximallyPermissiveFacts] so a fact-gated mapping (red meat, cheese,
/// fats/oils/nuts/seeds) is never mistaken for a missing tag mapping.
///
/// Each tag is evaluated in isolation (as the product's only category
/// tag) — the correct reading of "does the resolver recognize THIS tag",
/// not a simulation of every real product's full, possibly multi-tag
/// evidence set.
class ScoringCategoryTagCoverageReport {
  const ScoringCategoryTagCoverageReport({
    required this.inventoryTagCount,
    required this.resolvedTags,
    required this.unresolvedTags,
  });

  final int inventoryTagCount;

  /// Tags for which the resolver has SOME deterministic mapping mechanism
  /// — a pure taxonomy-coverage signal. Does NOT mean every real product
  /// carrying this tag will currently resolve: fact-gated branches
  /// (red meat/cheese/fats-oils-nuts-seeds) still separately require the
  /// product's OWN trusted classification facts, which this diagnostic
  /// never fabricates for production data — see [_maximallyPermissiveFacts].
  final List<String> resolvedTags;

  /// Tags the resolver cannot map AT ALL, even under maximally permissive
  /// facts — a genuine taxonomy gap (or a deliberately-left-ambiguous tag,
  /// per this pass's audit). Never a proof that a mapping SHOULD exist.
  final List<String> unresolvedTags;
}

class ScoringCategoryTaxonomyCoverageDiagnostic {
  const ScoringCategoryTaxonomyCoverageDiagnostic({
    this.resolver = const ScoringCategoryResolver(),
  });

  final ScoringCategoryResolver resolver;

  ScoringCategoryTagCoverageReport evaluate(List<String> tags) {
    final resolvedTags = <String>[];
    final unresolvedTags = <String>[];
    for (final tag in tags) {
      final result = resolver.resolve(
        ScoringCategoryResolverInput(
          categoryTags: [tag],
          taxonomyProvenance: EvidenceProvenance.databaseImport,
          taxonomyVerification: EvidenceVerification.unverified,
          allowLegacyCompatibility: true,
          facts: _maximallyPermissiveFacts,
        ),
      );
      if (result.resolvedCategory == ScoringCategory.unknown) {
        unresolvedTags.add(tag);
      } else {
        resolvedTags.add(tag);
      }
    }
    return ScoringCategoryTagCoverageReport(
      inventoryTagCount: tags.length,
      resolvedTags: resolvedTags,
      unresolvedTags: unresolvedTags,
    );
  }
}
