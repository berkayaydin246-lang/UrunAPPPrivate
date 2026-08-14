import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_evaluation.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

class ScoringBlockerDiagnosticReport {
  const ScoringBlockerDiagnosticReport({
    required this.product,
    required this.stagingMatches,
    required this.selectedStaging,
    required this.recovery,
    required this.effectiveEvidence,
    required this.categoryEvidence,
    required this.ingredientsSourceComplete,
    required this.matching,
    required this.diagnosticAssessment,
    required this.scoringAssessment,
    required this.evaluation,
    required this.nutritionReady,
    required this.additiveReady,
    required this.finalScoreReady,
    required this.finalBlockers,
  });

  final Product product;
  final List<LegacyStagingScoringEvidence> stagingMatches;
  final LegacyStagingScoringEvidence? selectedStaging;
  final LegacyScoringEvidenceRecoveryResult? recovery;
  final ScoringEvidenceSnapshot? effectiveEvidence;
  final ScoringCategoryEvidence categoryEvidence;
  final bool ingredientsSourceComplete;
  final IngredientMatchingResult matching;
  final CanonicalAdditiveAssessment diagnosticAssessment;
  final CanonicalAdditiveAssessment scoringAssessment;
  final ProductEtiketlyScoreEvaluation? evaluation;
  final bool nutritionReady;
  final bool additiveReady;
  final bool finalScoreReady;
  final List<String> finalBlockers;

  bool get recoveredInMemory =>
      product.scoringEvidence == null && effectiveEvidence != null;

  bool get nutritionComplete {
    final nutrition = product.nutrition;
    return nutrition != null &&
        nutrition.energyKj != null &&
        nutrition.fat != null &&
        nutrition.saturatedFat != null &&
        nutrition.sugars != null &&
        nutrition.fiber != null &&
        nutrition.proteins != null &&
        nutrition.salt != null;
  }

  bool get classificationReady {
    final category = categoryEvidence.resolvedCategory;
    return categoryEvidence.isSufficient &&
        category != ScoringCategory.unknown &&
        category != ScoringCategory.outOfScope;
  }

  bool get fvlReady =>
      effectiveEvidence?.fvlEvidence.hasDeterministicValue == true;

  bool get nnsReady {
    if (categoryEvidence.resolvedCategory != ScoringCategory.beverage) {
      return true;
    }
    return effectiveEvidence?.nnsEvidence.isKnown == true;
  }

  List<CanonicalUnresolvedIngredient> get unmatchedOrdinaryIngredients {
    final scoringKeys = scoringAssessment.unresolvedIngredients
        .map((item) => item.normalizedToken)
        .toSet();
    return diagnosticAssessment.unresolvedIngredients
        .where((item) => !scoringKeys.contains(item.normalizedToken))
        .toList(growable: false);
  }

  List<CanonicalIngredientAssessment> get unknownRiskAdditives =>
      scoringAssessment.canonicalAdditives
          .where((item) => item.riskLevel == CanonicalRiskLevel.unknown)
          .toList(growable: false);

  List<CanonicalIngredientAssessment> get reviewRequiredAdditives =>
      scoringAssessment.canonicalAdditives
          .where(
            (item) =>
                item.matchAuthority == CanonicalMatchAuthority.reviewRequired,
          )
          .toList(growable: false);

  List<CanonicalIngredientAssessment> get duplicateNormalizedAdditives =>
      scoringAssessment.canonicalAdditives
          .where((item) => item.occurrenceCount > 1)
          .toList(growable: false);

  List<String> get nutritionBlockers {
    final blockers = <String>{
      ...?evaluation?.nutritionReadiness.blockingReasons.map(
        (reason) => reason.name,
      ),
      ...finalBlockers.where(_isLegacyNutritionBlocker),
    };
    return blockers.toList()..sort();
  }

  List<String> get classificationBlockers =>
      finalBlockers.where(_isClassificationBlocker).toList(growable: false);

  List<String> get fvlNnsBlockers =>
      finalBlockers.where(_isFvlNnsBlocker).toList(growable: false);

  List<String> get additiveBlockers =>
      finalBlockers.where(_isAdditiveBlocker).toList(growable: false);

  static bool _isLegacyNutritionBlocker(String blocker) {
    return blocker == 'missing_nutrition' ||
        blocker == 'nutrition_source_unverified' ||
        blocker == 'product_state_unknown' ||
        blocker.startsWith('missing_energy') ||
        blocker.startsWith('missing_total_fat') ||
        blocker.startsWith('missing_saturated_fat') ||
        blocker.startsWith('missing_sugars') ||
        blocker.startsWith('missing_fiber') ||
        blocker.startsWith('missing_protein') ||
        blocker.startsWith('missing_salt') ||
        blocker.startsWith('basis_');
  }

  static bool _isClassificationBlocker(String blocker) =>
      blocker == 'missing_classification' ||
      blocker == 'basis_unit_ambiguous' ||
      blocker.contains('ScoringCategory') ||
      blocker.contains('CategoryEvidence');

  static bool _isFvlNnsBlocker(String blocker) =>
      blocker == 'fvl_unknown' ||
      blocker == 'nns_unknown' ||
      blocker.contains('Fvl') ||
      blocker.contains('Nns');

  static bool _isAdditiveBlocker(String blocker) =>
      blocker.startsWith('canonical_additive_') ||
      blocker.startsWith('additive:') ||
      blocker == 'ingredients_incomplete' ||
      blocker == 'missing_ingredients';
}

class ScoringBlockerDiagnosticService {
  const ScoringBlockerDiagnosticService({
    this.recovery = const LegacyScoringEvidenceRecoveryService(),
    this.matcher = const IngredientMatcherService(),
    this.riskService = const CanonicalIngredientRiskService(),
    this.categoryResolver = const ScoringCategoryResolver(),
    this.orchestrator = const ProductEtiketlyScoreOrchestrator(),
  });

  final LegacyScoringEvidenceRecoveryService recovery;
  final IngredientMatcherService matcher;
  final CanonicalIngredientRiskService riskService;
  final ScoringCategoryResolver categoryResolver;
  final ProductEtiketlyScoreOrchestrator orchestrator;

  Future<ScoringBlockerDiagnosticReport> inspect({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
  }) async {
    final selectedStaging = _selectStaging(stagingMatches);
    final ingredientsSourceComplete =
        selectedStaging?.hasSourceCompleteIngredients(
          product.ingredientsText,
        ) ??
        false;
    final resolvedFromPersistedTaxonomy = categoryResolver.resolve(
      ScoringCategoryResolverInput(
        categoryTags: product.categoryTags ?? const [],
        canonicalCategory: product.canonicalCategory,
        canonicalSubcategory: product.canonicalSubcategory,
        taxonomyProvenance: EvidenceProvenance.databaseImport,
        taxonomyVerification: EvidenceVerification.unverified,
        facts: const ScoringClassificationFacts(),
        allowLegacyCompatibility: true,
      ),
    );

    final recoveryResult = product.scoringEvidence == null
        ? await recovery.recover(
            product: product,
            stagingMatches: stagingMatches,
            ingredientCatalogue: ingredientCatalogue,
          )
        : null;
    final evidence = product.scoringEvidence ?? recoveryResult?.evidence;
    final categoryEvidence =
        evidence?.categoryEvidence ?? resolvedFromPersistedTaxonomy;

    final tokens = matcher.parseIngredients(product.ingredientsText ?? '');
    final matching = await matcher.matchIngredientTokens(
      tokens,
      ingredientCatalogue,
    );
    final diagnosticAssessment = riskService.assess(
      matching,
      scoringCategory: categoryEvidence.resolvedCategory,
    );
    final scoringAssessment = riskService.assessForScoring(
      matching,
      scoringCategory: categoryEvidence.resolvedCategory,
    );

    ProductEtiketlyScoreEvaluation? evaluation;
    if (evidence != null) {
      evaluation = orchestrator.calculate(
        product: _withEvidence(product, evidence),
        canonicalAssessment: scoringAssessment,
      );
    }
    final additiveBlockers = evaluation?.finalReadiness.blockingReasons.where(
      (reason) => reason != EtiketlyScoreReadinessBlocker.nutritionNotReady,
    );
    final finalBlockers = recoveryResult != null
        ? [...recoveryResult.blockerReasons]
        : <String>[
            ...?evaluation?.nutritionReadiness.blockingReasons.map(
              (reason) => 'nutrition:${reason.name}',
            ),
            ...?additiveBlockers?.map((reason) => 'additive:${reason.name}'),
            if (evaluation == null) 'canonical_assessment_unavailable',
          ];
    finalBlockers.sort();

    return ScoringBlockerDiagnosticReport(
      product: product,
      stagingMatches: List.unmodifiable(stagingMatches),
      selectedStaging: selectedStaging,
      recovery: recoveryResult,
      effectiveEvidence: evidence,
      categoryEvidence: categoryEvidence,
      ingredientsSourceComplete: ingredientsSourceComplete,
      matching: matching,
      diagnosticAssessment: diagnosticAssessment,
      scoringAssessment: scoringAssessment,
      evaluation: evaluation,
      nutritionReady: evaluation?.nutritionReadiness.isScorable ?? false,
      additiveReady: evaluation != null && additiveBlockers?.isEmpty == true,
      finalScoreReady: evaluation?.isCalculated ?? false,
      finalBlockers: List.unmodifiable(finalBlockers),
    );
  }

  LegacyStagingScoringEvidence? _selectStaging(
    List<LegacyStagingScoringEvidence> matches,
  ) {
    if (matches.isEmpty ||
        matches.map((match) => match.evidenceSignature).toSet().length != 1) {
      return null;
    }
    final sorted = [...matches]
      ..sort((left, right) => left.id.compareTo(right.id));
    return sorted.first;
  }

  Product _withEvidence(Product product, ScoringEvidenceSnapshot evidence) {
    return Product(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      normalizedName: product.normalizedName,
      brand: product.brand,
      categoryId: product.categoryId,
      imageUrl: product.imageUrl,
      ingredientsText: product.ingredientsText,
      nutritionText: product.nutritionText,
      source: product.source,
      sourceUrl: product.sourceUrl,
      verificationStatus: product.verificationStatus,
      searchKeywords: product.searchKeywords,
      categoryTags: product.categoryTags,
      canonicalCategory: product.canonicalCategory,
      canonicalSubcategory: product.canonicalSubcategory,
      scoringEvidence: evidence,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
    );
  }
}

class ScoringBlockerReportFormatter {
  const ScoringBlockerReportFormatter();

  String format(ScoringBlockerDiagnosticReport report) {
    final product = report.product;
    final nutrition = product.nutrition;
    final evidence = report.effectiveEvidence;
    final lines = <String>[
      '[PRODUCT]',
      'product_id=${_text(product.id)}',
      'name=${_text(product.name)}',
      'brand=${_text(product.brand)}',
      'source=${_text(product.source)}',
      'source_url=${_text(product.sourceUrl)}',
      'matching_staging_row=${_yesNo(report.stagingMatches.isNotEmpty)}',
      'matching_staging_row_count=${report.stagingMatches.length}',
      'selected_staging_id=${_text(report.selectedStaging?.id)}',
      'existing_scoring_evidence=${_yesNo(product.scoringEvidence != null)}',
      'recovered_in_memory=${_yesNo(report.recoveredInMemory)}',
      '',
      '[NUTRITION EVIDENCE]',
      'raw_staging_nutrition_basis=${_stagingBasis(report)}',
      'explicit_per100=${_yesNo(report.recovery?.explicitPer100 ?? _isExplicitPer100(report))}',
      'resolved_basis=${evidence?.nutritionBasis.name ?? NutritionBasis.unknown.name}',
      'product_state=${evidence?.nutritionProductState.name ?? NutritionProductState.unknown.name}',
      'energy_kj=${_number(nutrition?.energyKj)}',
      'energy_kcal=${_number(nutrition?.energyKcal)}',
      'fat=${_number(nutrition?.fat)}',
      'saturated_fat=${_number(nutrition?.saturatedFat)}',
      'carbohydrates=${_number(nutrition?.carbohydrates)}',
      'sugars=${_number(nutrition?.sugars)}',
      'fiber=${_number(nutrition?.fiber)}',
      'protein=${_number(nutrition?.proteins)}',
      'salt=${_number(nutrition?.salt)}',
      'sodium=${_number(nutrition?.sodium)}',
      'nutrition_complete=${_yesNo(report.nutritionComplete)}',
      'nutrition_blockers=${_list(report.nutritionBlockers)}',
      '',
      '[CLASSIFICATION]',
      'category_id=${_text(product.categoryId)}',
      'category_tags=${_list(product.categoryTags ?? const [])}',
      'canonical_category=${_text(product.canonicalCategory)}',
      'canonical_subcategory=${_text(product.canonicalSubcategory)}',
      'category_evidence_source=${report.categoryEvidence.source.name}',
      'category_evidence_values=${_list(report.categoryEvidence.evidenceValues)}',
      'resolved_scoring_category=${report.categoryEvidence.resolvedCategory.name}',
      'classification_ready=${_yesNo(report.classificationReady)}',
      'classification_blockers=${_list(report.classificationBlockers)}',
      '',
      '[FVL / NNS]',
      'fvl_evidence=${_fvl(evidence?.fvlEvidence)}',
      'fvl_ready=${_yesNo(report.fvlReady)}',
      'nns_evidence=${_nns(evidence?.nnsEvidence)}',
      'nns_ready=${_yesNo(report.nnsReady)}',
      'fvl_nns_blockers=${_list(report.fvlNnsBlockers)}',
      '',
      '[INGREDIENT / ADDITIVE SCORING]',
      'ingredient_source_completeness=${report.ingredientsSourceComplete ? 'complete' : 'unknown'}',
      'parsed_ingredient_count=${report.matching.totalIngredients}',
    ];
    _addItems(
      lines,
      'canonical_matches',
      report.diagnosticAssessment.recognizedIngredients.map(_canonicalItem),
    );
    _addItems(
      lines,
      'unmatched_ordinary_food_ingredients',
      report.unmatchedOrdinaryIngredients.map(_unresolvedItem),
    );
    _addItems(
      lines,
      'additive_like_unresolved_ingredients',
      report.scoringAssessment.unresolvedIngredients.map(_unresolvedItem),
    );
    _addItems(
      lines,
      'out_of_scope_flavouring_evidence',
      report.scoringAssessment.outOfScopeFlavouringEvidence.map(
        _outOfScopeFlavouringItem,
      ),
    );
    _addItems(
      lines,
      'unknown_additive_risks',
      report.unknownRiskAdditives.map(_canonicalItem),
    );
    _addItems(
      lines,
      'risk_conflicts',
      report.scoringAssessment.conflicts.map(
        (conflict) => '${conflict.canonicalKey}:${conflict.type.name}',
      ),
    );
    _addItems(
      lines,
      'review_required_additive_evidence',
      report.reviewRequiredAdditives.map(_canonicalItem),
    );
    _addItems(
      lines,
      'duplicate_normalized_additives',
      report.duplicateNormalizedAdditives.map(_canonicalItem),
    );
    lines
      ..add('additive_ready=${_yesNo(report.additiveReady)}')
      ..add('additive_blockers=${_list(report.additiveBlockers)}')
      ..add('')
      ..add('[FINAL]')
      ..add('nutrition_ready=${_yesNo(report.nutritionReady)}')
      ..add('additive_ready=${_yesNo(report.additiveReady)}')
      ..add('final_score_ready=${_yesNo(report.finalScoreReady)}')
      ..add('calculated_score=${_number(report.evaluation?.result.score)}')
      ..add('ordered_blocker_reasons=${_list(report.finalBlockers)}')
      ..add('[BLOCKER CLASSIFICATION]');
    for (var index = 0; index < report.finalBlockers.length; index++) {
      final blocker = report.finalBlockers[index];
      lines.add(
        'blocker[$index]=${_text(blocker)} cause=${_blockerCause(blocker, report)}',
      );
    }
    if (report.finalBlockers.isEmpty) lines.add('blockers=none');
    return lines.join('\n');
  }

  bool _isExplicitPer100(ScoringBlockerDiagnosticReport report) {
    final basis = report.selectedStaging?.nutritionBasis?.trim().toLowerCase();
    return basis == 'per_100' &&
        !report.selectedStaging!.nutritionWarnings.any(
          (warning) =>
              warning.trim().toLowerCase() ==
              'nutrition_basis_unknown_assumed_per_100',
        );
  }

  String _stagingBasis(ScoringBlockerDiagnosticReport report) {
    final values =
        report.stagingMatches
            .map((match) => match.nutritionBasis?.trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return _list(values);
  }

  String _fvl(CompositionPercentageEvidence? evidence) {
    if (evidence == null) return 'state=unknown';
    return 'state=${evidence.state.name} percentage=${_number(evidence.percentage)} '
        'provenance=${evidence.provenance.name} '
        'verification=${evidence.verification.name} '
        'dependency=${evidence.dependency.name}';
  }

  String _nns(PresenceEvidence? evidence) {
    if (evidence == null) return 'state=unknown';
    return 'state=${evidence.state.name} provenance=${evidence.provenance.name} '
        'verification=${evidence.verification.name} '
        'dependency=${evidence.dependency.name}';
  }

  String _canonicalItem(CanonicalIngredientAssessment item) {
    return '${item.canonicalName} e_code=${_text(item.eCode)} '
        'additive=${_yesNo(item.isAdditive)} risk=${item.riskLevel.name} '
        'authority=${item.matchAuthority.name} occurrences=${item.occurrenceCount}';
  }

  String _unresolvedItem(CanonicalUnresolvedIngredient item) =>
      '${item.normalizedToken} tokens=${_list(item.sourceTokens)} '
      'match_type=${item.matchType.name} confidence=${item.matchConfidence.toStringAsFixed(3)}';

  String _outOfScopeFlavouringItem(
    CanonicalOutOfScopeFlavouringEvidence item,
  ) =>
      '${item.normalizedToken} tokens=${_list(item.sourceTokens)} '
      'classification=outOfScopeFlavouringEvidence';

  void _addItems(List<String> lines, String label, Iterable<String> values) {
    final items = values.map(_text).toList(growable: false);
    lines.add('${label}_count=${items.length}');
    for (var index = 0; index < items.length; index++) {
      lines.add('$label[$index]=${items[index]}');
    }
  }

  String _blockerCause(String blocker, ScoringBlockerDiagnosticReport report) {
    if (blocker == 'missing_classification' ||
        blocker == 'basis_unit_ambiguous') {
      return 'E_category_classification_gap';
    }
    if (blocker.startsWith('canonical_additive_') ||
        blocker.startsWith('additive:')) {
      return 'D_canonical_additive_catalogue_or_matching_gap';
    }
    if (blocker == 'basis_unknown' ||
        blocker == 'basis_unknown_assumed_per100' ||
        blocker == 'nutrition_source_unverified' ||
        blocker == 'ingredients_incomplete' ||
        blocker == 'product_state_unknown') {
      return 'B_unverified_basis_or_provenance';
    }
    if (blocker == 'fvl_unknown' && !report.ingredientsSourceComplete) {
      return 'B_unverified_basis_or_provenance';
    }
    if (blocker.startsWith('missing_') || blocker == 'fvl_unknown') {
      return 'A_genuinely_missing_source_data';
    }
    return 'unclassified_requires_review';
  }

  String _yesNo(bool value) => value ? 'yes' : 'no';

  String _number(double? value) {
    if (value == null) return '-';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  String _list(Iterable<String> values) {
    final items = values.map(_text).where((value) => value != '-').toList();
    return items.isEmpty ? 'none' : items.join(' | ');
  }

  String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '-';
    return text.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  }
}
