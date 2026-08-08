import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';

enum CanonicalUnresolvedIngredientPolicy { retainAll, additiveCandidatesOnly }

/// The only production API that resolves canonical ingredient identity and risk.
///
/// Matching remains the responsibility of [IngredientMatcherService]. Once
/// matches exist, this service performs pure, deterministic risk resolution,
/// additive eligibility classification, deduplication, and overlap metadata.
class CanonicalIngredientRiskService {
  const CanonicalIngredientRiskService();

  CanonicalAdditiveAssessment assess(
    IngredientMatchingResult matchingResult, {
    ScoringCategory scoringCategory = ScoringCategory.unknown,
    CanonicalUnresolvedIngredientPolicy unresolvedIngredientPolicy =
        CanonicalUnresolvedIngredientPolicy.retainAll,
  }) {
    final recognized = <String, _CanonicalItemBuilder>{};
    final unresolved = <String, _UnresolvedBuilder>{};

    for (var index = 0; index < matchingResult.matches.length; index++) {
      final match = matchingResult.matches[index];
      final ingredient = match.matchedIngredient;
      if (ingredient == null ||
          match.matchType == MatchType.unmatched ||
          match.isRejected) {
        if (unresolvedIngredientPolicy ==
                CanonicalUnresolvedIngredientPolicy.additiveCandidatesOnly &&
            !_isPotentialAdditive(match)) {
          continue;
        }
        final key = match.normalizedText.trim().isEmpty
            ? IngredientCanonicalizer.normalizeToken(match.originalToken)
            : match.normalizedText.trim();
        unresolved
            .putIfAbsent(
              key,
              () => _UnresolvedBuilder(
                normalizedToken: key,
                matchType: match.matchType,
                matchConfidence: match.confidenceScore,
                candidateIngredientId: ingredient?.id,
                candidateCanonicalName: ingredient?.name,
              ),
            )
            .add(match.originalToken, match.confidenceScore);
        continue;
      }

      final enriched = enrichIngredientKnowledge(ingredient);
      final canonicalKey = canonicalKeyForIngredient(enriched);
      final riskResolution = _resolveRisk(enriched, canonicalKey);
      final evidence = CanonicalMatchEvidence(
        sourceToken: match.originalToken,
        normalizedToken: match.normalizedText,
        matchType: match.matchType,
        confidence: match.confidenceScore,
        affectsCurrentAnalysis: match.shouldAffectAnalysis,
        needsReview:
            _matchAuthority(match) != CanonicalMatchAuthority.authoritative,
      );

      recognized
          .putIfAbsent(
            canonicalKey,
            () => _CanonicalItemBuilder(
              ingredient: enriched,
              canonicalKey: canonicalKey,
              riskResolution: riskResolution,
              firstOccurrenceIndex: index,
            ),
          )
          .add(evidence, riskResolution);
    }

    final items =
        recognized.values
            .map((builder) => builder.build(scoringCategory: scoringCategory))
            .toList(growable: false)
          ..sort(
            (a, b) => a.firstOccurrenceIndex.compareTo(b.firstOccurrenceIndex),
          );
    final conflicts = items
        .expand((item) => item.conflicts)
        .toList(growable: false);

    return CanonicalAdditiveAssessment(
      recognizedIngredients: items,
      unresolvedIngredients: unresolved.values.map(
        (builder) => builder.build(),
      ),
      conflicts: conflicts,
    );
  }

  CanonicalAdditiveAssessment assessIngredients(
    Iterable<Ingredient> ingredients, {
    ScoringCategory scoringCategory = ScoringCategory.unknown,
  }) {
    final matches = ingredients.map(
      (ingredient) => IngredientMatch(
        originalToken: ingredient.eCode?.trim().isNotEmpty == true
            ? ingredient.eCode!.trim()
            : ingredient.name,
        normalizedText: ingredient.normalizedName,
        matchedIngredient: ingredient,
        matchedToken: ingredient.normalizedName,
        confidenceScore: 1,
        matchType: MatchType.exactMatch,
        shouldAffectAnalysis: true,
      ),
    );
    return assess(
      IngredientMatchingResult(matches: matches.toList(growable: false)),
      scoringCategory: scoringCategory,
    );
  }

  CanonicalIngredientAssessment assessIngredient(
    Ingredient ingredient, {
    ScoringCategory scoringCategory = ScoringCategory.unknown,
  }) {
    return assessIngredients([
      ingredient,
    ], scoringCategory: scoringCategory).recognizedIngredients.single;
  }

  String canonicalKeyForIngredient(Ingredient ingredient) {
    final id = ingredient.id.trim();
    if (id.isNotEmpty) return 'ingredient:$id';

    final eCode = _normalizedECode(ingredient.eCode);
    if (eCode != null) return 'e-code:$eCode';

    final canonicalName = IngredientCanonicalizer.normalizeToken(
      ingredient.normalizedName.trim().isNotEmpty
          ? ingredient.normalizedName
          : ingredient.name,
    );
    return 'name:$canonicalName';
  }

  _RiskResolution _resolveRisk(Ingredient ingredient, String canonicalKey) {
    final ingredientRisk = _parseRisk(ingredient.riskLevel);
    final reviewedRisk = _parseRisk(
      reviewedCatalogRiskLevelForIngredient(ingredient),
    );
    final hasIngredientRisk = ingredientRisk != CanonicalRiskLevel.unknown;
    final hasReviewedRisk = reviewedRisk != CanonicalRiskLevel.unknown;

    if (hasIngredientRisk &&
        hasReviewedRisk &&
        ingredientRisk != reviewedRisk) {
      final conflict = CanonicalRiskConflict(
        canonicalKey: canonicalKey,
        type: CanonicalRiskConflictType.catalogueRiskMismatch,
        ingredientCatalogueRisk: ingredientRisk,
        reviewedCatalogueRisk: reviewedRisk,
        message:
            'Ingredient catalogue and reviewed explanation catalogue disagree.',
      );
      return _RiskResolution(
        level: CanonicalRiskLevel.unknown,
        source: CanonicalRiskSource.unresolvedConflict,
        conflicts: [conflict],
      );
    }
    if (hasIngredientRisk && hasReviewedRisk) {
      return _RiskResolution(
        level: ingredientRisk,
        source: CanonicalRiskSource.consistentCatalogues,
      );
    }
    if (hasIngredientRisk) {
      return _RiskResolution(
        level: ingredientRisk,
        source: CanonicalRiskSource.ingredientCatalogue,
      );
    }
    if (hasReviewedRisk) {
      return _RiskResolution(
        level: reviewedRisk,
        source: CanonicalRiskSource.reviewedExplanationCatalogue,
      );
    }
    return const _RiskResolution(
      level: CanonicalRiskLevel.unknown,
      source: CanonicalRiskSource.unknown,
    );
  }

  CanonicalRiskLevel _parseRisk(String? value) => switch (value?.trim()) {
    'low' => CanonicalRiskLevel.low,
    'medium' => CanonicalRiskLevel.medium,
    'high' => CanonicalRiskLevel.high,
    _ => CanonicalRiskLevel.unknown,
  };

  static CanonicalMatchAuthority _matchAuthority(IngredientMatch match) {
    if (match.isRejected || match.matchType == MatchType.unmatched) {
      return CanonicalMatchAuthority.unresolved;
    }
    return switch (match.matchType) {
      MatchType.exactMatch ||
      MatchType.eCodeMatch ||
      MatchType.aliasMatch => CanonicalMatchAuthority.authoritative,
      MatchType.highConfidenceFuzzy ||
      MatchType.lowConfidencePossible => CanonicalMatchAuthority.reviewRequired,
      MatchType.unmatched => CanonicalMatchAuthority.unresolved,
    };
  }

  static String? _normalizedECode(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = IngredientCanonicalizer.normalizeECode(
      raw,
    ).toUpperCase();
    return isValidFoodAdditiveCode(normalized) ? normalized : null;
  }

  static final _additiveCodeCandidate = RegExp(
    r'\be\s*[-:]?\s*\d{2,4}\b',
    caseSensitive: false,
  );

  static final _additiveFunctionCandidate = RegExp(
    r'\b(?:katkı|katki|koruyucu|renklendirici|tatlandırıcı|tatlandirici|emülgatör|emulgator|stabilizör|stabilizor|antioksidan|kabartıcı|kabartici|sekestran|parlatıcı|parlatici|köpük önleyici|kopuk onleyici|nem tutucu|sertleştirici|sertlestirici|asitlik düzenleyici|asitlik duzenleyici|kıvam artırıcı|kivam artirici|topaklanma önleyici|topaklanma onleyici|modifiye nişasta|modifiye nisasta|aroma verici)\b',
    caseSensitive: false,
  );

  static final _knownAdditiveCandidate = RegExp(
    r'\b(?:benzoat|nitrit|nitrat|sülfit|sulfit|sorbat|tartrazin|aspartam|sukraloz|asesülfam|asesulfam|monosodyum glutamat|karmin|lesitin|digliserit|guar gam|ksantan gam)\b',
    caseSensitive: false,
  );

  static bool _isPotentialAdditive(IngredientMatch match) {
    final ingredient = match.matchedIngredient;
    if (ingredient != null &&
        (_normalizedECode(ingredient.eCode) != null ||
            ingredient.additiveGroup?.trim().isNotEmpty == true)) {
      return true;
    }
    final text = '${match.originalToken} ${match.normalizedText}';
    return _additiveCodeCandidate.hasMatch(text) ||
        _additiveFunctionCandidate.hasMatch(text) ||
        _knownAdditiveCandidate.hasMatch(text);
  }
}

class _RiskResolution {
  const _RiskResolution({
    required this.level,
    required this.source,
    this.conflicts = const [],
  });

  final CanonicalRiskLevel level;
  final CanonicalRiskSource source;
  final List<CanonicalRiskConflict> conflicts;
}

class _CanonicalItemBuilder {
  _CanonicalItemBuilder({
    required this.ingredient,
    required this.canonicalKey,
    required _RiskResolution riskResolution,
    required this.firstOccurrenceIndex,
  }) : _riskSources = {riskResolution.source};

  final Ingredient ingredient;
  final String canonicalKey;
  final int firstOccurrenceIndex;
  final List<CanonicalMatchEvidence> _evidence = [];
  final Set<CanonicalRiskLevel> _riskLevels = {};
  final Set<CanonicalRiskSource> _riskSources;
  final List<CanonicalRiskConflict> _conflicts = [];

  void add(CanonicalMatchEvidence evidence, _RiskResolution riskResolution) {
    _evidence.add(evidence);
    _riskLevels.add(riskResolution.level);
    _riskSources.add(riskResolution.source);
    for (final conflict in riskResolution.conflicts) {
      final alreadyRecorded = _conflicts.any(
        (existing) =>
            existing.type == conflict.type &&
            existing.ingredientCatalogueRisk ==
                conflict.ingredientCatalogueRisk &&
            existing.reviewedCatalogueRisk == conflict.reviewedCatalogueRisk,
      );
      if (!alreadyRecorded) _conflicts.add(conflict);
    }
  }

  CanonicalIngredientAssessment build({
    required ScoringCategory scoringCategory,
  }) {
    var riskLevel = _riskLevels.singleOrNull ?? CanonicalRiskLevel.unknown;
    var riskSource = _aggregateRiskSource();
    if (_riskLevels.length > 1) {
      riskSource = CanonicalRiskSource.unresolvedConflict;
      _conflicts.add(
        CanonicalRiskConflict(
          canonicalKey: canonicalKey,
          type: CanonicalRiskConflictType.duplicateIdentityRiskMismatch,
          message: 'Duplicate matches for one canonical identity disagree.',
        ),
      );
      riskLevel = CanonicalRiskLevel.unknown;
    }

    final primaryEvidence = [..._evidence]..sort(_compareEvidence);
    final primary = primaryEvidence.first;
    final authority = _aggregateAuthority(_evidence);
    final affectsCurrentAnalysis = _evidence.any(
      (evidence) => evidence.affectsCurrentAnalysis,
    );
    final eCode = CanonicalIngredientRiskService._normalizedECode(
      ingredient.eCode,
    );
    final additiveGroup = ingredient.additiveGroup?.trim();
    final isAdditive =
        isValidFoodAdditiveCode(eCode) ||
        (additiveGroup != null && additiveGroup.isNotEmpty);
    final overlap = _nutritionOverlap(
      ingredient: ingredient,
      eCode: eCode,
      isAdditive: isAdditive,
      scoringCategory: scoringCategory,
      evidence: _evidence,
    );
    final eligible =
        isAdditive &&
        authority == CanonicalMatchAuthority.authoritative &&
        affectsCurrentAnalysis &&
        riskLevel != CanonicalRiskLevel.unknown &&
        _conflicts.isEmpty;
    final warnings = <String>[
      if (_conflicts.isNotEmpty)
        'Canonical risk is unresolved due to conflict.',
      if (riskLevel == CanonicalRiskLevel.unknown)
        'No reviewed canonical risk is available.',
      if (authority == CanonicalMatchAuthority.reviewRequired)
        'Match requires review before future additive scoring.',
    ];

    return CanonicalIngredientAssessment(
      ingredient: _copyWithRisk(ingredient, riskLevel.name),
      ingredientId: ingredient.id.trim().isEmpty ? null : ingredient.id.trim(),
      canonicalKey: canonicalKey,
      canonicalName: ingredient.name.trim(),
      eCode: eCode,
      additiveGroup: additiveGroup?.isEmpty == true ? null : additiveGroup,
      isAdditive: isAdditive,
      riskLevel: riskLevel,
      riskSource: riskSource,
      matchType: primary.matchType,
      matchConfidence: primary.confidence,
      matchAuthority: authority,
      matchEvidence: _evidence,
      affectsCurrentAnalysis: affectsCurrentAnalysis,
      eligibleForFutureAdditiveScore: eligible,
      nutritionMethodologyOverlap: overlap,
      warnings: warnings,
      conflicts: _conflicts,
      firstOccurrenceIndex: firstOccurrenceIndex,
    );
  }

  static int _compareEvidence(
    CanonicalMatchEvidence a,
    CanonicalMatchEvidence b,
  ) {
    final byType = _matchRank(b.matchType).compareTo(_matchRank(a.matchType));
    if (byType != 0) return byType;
    return b.confidence.compareTo(a.confidence);
  }

  CanonicalRiskSource _aggregateRiskSource() {
    if (_conflicts.isNotEmpty ||
        _riskSources.contains(CanonicalRiskSource.unresolvedConflict)) {
      return CanonicalRiskSource.unresolvedConflict;
    }
    if (_riskSources.contains(CanonicalRiskSource.consistentCatalogues) ||
        (_riskSources.contains(CanonicalRiskSource.ingredientCatalogue) &&
            _riskSources.contains(
              CanonicalRiskSource.reviewedExplanationCatalogue,
            ))) {
      return CanonicalRiskSource.consistentCatalogues;
    }
    return _riskSources.singleOrNull ?? CanonicalRiskSource.unknown;
  }

  static int _matchRank(MatchType type) => switch (type) {
    MatchType.exactMatch => 5,
    MatchType.eCodeMatch => 4,
    MatchType.aliasMatch => 3,
    MatchType.highConfidenceFuzzy => 2,
    MatchType.lowConfidencePossible => 1,
    MatchType.unmatched => 0,
  };

  static CanonicalMatchAuthority _aggregateAuthority(
    Iterable<CanonicalMatchEvidence> evidence,
  ) {
    if (evidence.any(
      (item) =>
          item.matchType == MatchType.exactMatch ||
          item.matchType == MatchType.eCodeMatch ||
          item.matchType == MatchType.aliasMatch,
    )) {
      return CanonicalMatchAuthority.authoritative;
    }
    return evidence.isEmpty
        ? CanonicalMatchAuthority.unresolved
        : CanonicalMatchAuthority.reviewRequired;
  }

  static NutritionMethodologyOverlap _nutritionOverlap({
    required Ingredient ingredient,
    required String? eCode,
    required bool isAdditive,
    required ScoringCategory scoringCategory,
    required Iterable<CanonicalMatchEvidence> evidence,
  }) {
    if (!isAdditive || scoringCategory != ScoringCategory.beverage) {
      return NutritionMethodologyOverlap.none;
    }
    final identifiers = <String>[
      ingredient.name,
      ingredient.normalizedName,
      ?eCode,
      ...?ingredient.aliases,
      ...?ingredient.alternativeNames,
      ...?ingredient.commonNames,
      ...?ingredient.englishNames,
      ...evidence.map((item) => item.sourceToken),
    ].join(', ');
    return const NnsEvidenceDetector().detect(identifiers).hasQualifyingMatch
        ? NutritionMethodologyOverlap.beverageNnsAlreadyRepresented
        : NutritionMethodologyOverlap.none;
  }

  static Ingredient _copyWithRisk(Ingredient ingredient, String riskLevel) {
    return Ingredient(
      id: ingredient.id,
      name: ingredient.name,
      normalizedName: ingredient.normalizedName,
      alternativeNames: ingredient.alternativeNames,
      aliases: ingredient.aliases,
      commonNames: ingredient.commonNames,
      englishNames: ingredient.englishNames,
      eCode: ingredient.eCode,
      category: ingredient.category,
      riskLevel: riskLevel,
      shortDescription: ingredient.shortDescription,
      longDescription: ingredient.longDescription,
      additiveGroup: ingredient.additiveGroup,
      childWarning: ingredient.childWarning,
      sourceReferences: ingredient.sourceReferences,
      sourceReferenceEntries: ingredient.sourceReferenceEntries,
      sourceUrl: ingredient.sourceUrl,
      ingredientType: ingredient.ingredientType,
      shortPurpose: ingredient.shortPurpose,
      shortRiskSummary: ingredient.shortRiskSummary,
      cautionGroups: ingredient.cautionGroups,
      processingRole: ingredient.processingRole,
      createdAt: ingredient.createdAt,
      updatedAt: ingredient.updatedAt,
    );
  }
}

class _UnresolvedBuilder {
  _UnresolvedBuilder({
    required this.normalizedToken,
    required this.matchType,
    required this.matchConfidence,
    required this.candidateIngredientId,
    required this.candidateCanonicalName,
  });

  final String normalizedToken;
  final MatchType matchType;
  double matchConfidence;
  final String? candidateIngredientId;
  final String? candidateCanonicalName;
  final List<String> sourceTokens = [];

  void add(String token, double confidence) {
    sourceTokens.add(token);
    if (confidence > matchConfidence) matchConfidence = confidence;
  }

  CanonicalUnresolvedIngredient build() => CanonicalUnresolvedIngredient(
    normalizedToken: normalizedToken,
    sourceTokens: sourceTokens,
    matchType: matchType,
    matchConfidence: matchConfidence,
    candidateIngredientId: candidateIngredientId,
    candidateCanonicalName: candidateCanonicalName,
  );
}

extension<T> on Set<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
