class ScoreAuditEvidenceValueSnapshot {
  const ScoreAuditEvidenceValueSnapshot({
    required this.value,
    required this.provenance,
    required this.verification,
  });

  final Object? value;
  final String provenance;
  final String verification;

  Map<String, Object?> toJson() => {
    'value': value,
    'provenance': provenance,
    'verification': verification,
  };

  static ScoreAuditEvidenceValueSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    if (json == null) return null;
    final rawValue = json['value'];
    if (rawValue is num && !rawValue.isFinite) return null;
    final provenance = _readString(json['provenance']);
    final verification = _readString(json['verification']);
    if (provenance == null || verification == null) return null;
    return ScoreAuditEvidenceValueSnapshot(
      value: rawValue,
      provenance: provenance,
      verification: verification,
    );
  }
}

class ScoreAuditCompositionSnapshot {
  const ScoreAuditCompositionSnapshot({
    required this.state,
    required this.percentage,
    required this.provenance,
    required this.verification,
    required this.dependency,
  });

  final String state;
  final double? percentage;
  final String provenance;
  final String verification;
  final String dependency;

  Map<String, Object?> toJson() => {
    'state': state,
    'percentage': percentage,
    'provenance': provenance,
    'verification': verification,
    'dependency': dependency,
  };

  static ScoreAuditCompositionSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    if (json == null) return null;
    final state = _readString(json['state']);
    final percentage = _readOptionalFiniteDouble(json['percentage']);
    final provenance = _readString(json['provenance']);
    final verification = _readString(json['verification']);
    final dependency = _readString(json['dependency']);
    if (state == null ||
        provenance == null ||
        verification == null ||
        dependency == null ||
        (json['percentage'] != null && percentage == null)) {
      return null;
    }
    return ScoreAuditCompositionSnapshot(
      state: state,
      percentage: percentage,
      provenance: provenance,
      verification: verification,
      dependency: dependency,
    );
  }
}

class ScoreAuditPresenceSnapshot {
  const ScoreAuditPresenceSnapshot({
    required this.state,
    required this.provenance,
    required this.verification,
    required this.dependency,
  });

  final String state;
  final String provenance;
  final String verification;
  final String dependency;

  Map<String, Object?> toJson() => {
    'state': state,
    'provenance': provenance,
    'verification': verification,
    'dependency': dependency,
  };

  static ScoreAuditPresenceSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    if (json == null) return null;
    final state = _readString(json['state']);
    final provenance = _readString(json['provenance']);
    final verification = _readString(json['verification']);
    final dependency = _readString(json['dependency']);
    if (state == null ||
        provenance == null ||
        verification == null ||
        dependency == null) {
      return null;
    }
    return ScoreAuditPresenceSnapshot(
      state: state,
      provenance: provenance,
      verification: verification,
      dependency: dependency,
    );
  }
}

class ScoreAuditResolvedInputSnapshot {
  ScoreAuditResolvedInputSnapshot({
    required Map<String, ScoreAuditEvidenceValueSnapshot> nutrition,
    required this.nutritionBasis,
    this.nutritionBasisProvenance,
    required this.productState,
    required this.resolvedCategory,
    required this.categorySource,
    required Iterable<String> categoryEvidenceValues,
    required Iterable<String> categoryReasons,
    required this.fvlEvidence,
    required this.nnsEvidence,
    required this.ingredientEvidenceCompleteness,
    required Map<String, ScoreAuditEvidenceValueSnapshot?> classificationFacts,
  }) : nutrition = Map.unmodifiable(nutrition),
       categoryEvidenceValues = List.unmodifiable(categoryEvidenceValues),
       categoryReasons = List.unmodifiable(categoryReasons),
       classificationFacts = Map.unmodifiable(classificationFacts);

  final Map<String, ScoreAuditEvidenceValueSnapshot> nutrition;
  final String nutritionBasis;
  // Section E of the basis remediation pass. Null for every snapshot built
  // BEFORE this field existed (backward-compatible — tryFromJson simply
  // does not find the key) as well as for any snapshot whose basis was
  // never independently proven. This absence is itself the load-bearing
  // signal: a null/`databaseImport` provenance here means the basis value
  // above cannot be trusted as currently-verified evidence, EVEN THOUGH
  // the bare value (e.g. "per100g") looks superficially valid — see
  // EtiketlyPublicScoreAuditGate's basis-trust check. Only `declaredLabel`
  // (source-proven, see legacy_scoring_evidence_recovery.dart) and
  // `adminVerified` (a human genuinely confirmed it) are trusted.
  final String? nutritionBasisProvenance;
  final String productState;
  final String resolvedCategory;
  final String categorySource;
  final List<String> categoryEvidenceValues;
  final List<String> categoryReasons;
  final ScoreAuditCompositionSnapshot fvlEvidence;
  final ScoreAuditPresenceSnapshot nnsEvidence;
  final String ingredientEvidenceCompleteness;
  final Map<String, ScoreAuditEvidenceValueSnapshot?> classificationFacts;

  Map<String, Object?> toJson() => {
    'nutrition': {
      for (final entry in nutrition.entries) entry.key: entry.value.toJson(),
    },
    'nutrition_basis': nutritionBasis,
    if (nutritionBasisProvenance != null)
      'nutrition_basis_provenance': nutritionBasisProvenance,
    'product_state': productState,
    'resolved_category': resolvedCategory,
    'category_source': categorySource,
    'category_evidence_values': categoryEvidenceValues,
    'category_reasons': categoryReasons,
    'fvl_evidence': fvlEvidence.toJson(),
    'nns_evidence': nnsEvidence.toJson(),
    'ingredient_evidence_completeness': ingredientEvidenceCompleteness,
    'classification_facts': {
      for (final entry in classificationFacts.entries)
        entry.key: entry.value?.toJson(),
    },
  };

  static ScoreAuditResolvedInputSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    final nutritionJson = _asMap(json?['nutrition']);
    final classificationJson = _asMap(json?['classification_facts']);
    if (json == null || nutritionJson == null || classificationJson == null) {
      return null;
    }

    final nutrition = <String, ScoreAuditEvidenceValueSnapshot>{};
    for (final entry in nutritionJson.entries) {
      final parsed = ScoreAuditEvidenceValueSnapshot.tryFromJson(entry.value);
      if (parsed == null) return null;
      nutrition[entry.key] = parsed;
    }
    final classification = <String, ScoreAuditEvidenceValueSnapshot?>{};
    for (final entry in classificationJson.entries) {
      if (entry.value == null) {
        classification[entry.key] = null;
        continue;
      }
      final parsed = ScoreAuditEvidenceValueSnapshot.tryFromJson(entry.value);
      if (parsed == null) return null;
      classification[entry.key] = parsed;
    }

    final nutritionBasis = _readString(json['nutrition_basis']);
    final productState = _readString(json['product_state']);
    final resolvedCategory = _readString(json['resolved_category']);
    final categorySource = _readString(json['category_source']);
    final categoryValues = _readStringList(json['category_evidence_values']);
    final categoryReasons = _readStringList(json['category_reasons']);
    final fvl = ScoreAuditCompositionSnapshot.tryFromJson(json['fvl_evidence']);
    final nns = ScoreAuditPresenceSnapshot.tryFromJson(json['nns_evidence']);
    final completeness = _readString(json['ingredient_evidence_completeness']);
    if (nutritionBasis == null ||
        productState == null ||
        resolvedCategory == null ||
        categorySource == null ||
        categoryValues == null ||
        categoryReasons == null ||
        fvl == null ||
        nns == null ||
        completeness == null) {
      return null;
    }
    return ScoreAuditResolvedInputSnapshot(
      nutrition: nutrition,
      nutritionBasis: nutritionBasis,
      // Absent on every snapshot written before this field existed —
      // deliberately not required here (unlike the other fields above),
      // since that absence is itself meaningful, not malformed data.
      nutritionBasisProvenance: _readString(json['nutrition_basis_provenance']),
      productState: productState,
      resolvedCategory: resolvedCategory,
      categorySource: categorySource,
      categoryEvidenceValues: categoryValues,
      categoryReasons: categoryReasons,
      fvlEvidence: fvl,
      nnsEvidence: nns,
      ingredientEvidenceCompleteness: completeness,
      classificationFacts: classification,
    );
  }
}

class ScoreAuditCanonicalAdditiveSnapshot {
  ScoreAuditCanonicalAdditiveSnapshot({
    required this.ingredientId,
    required this.canonicalKey,
    required this.canonicalName,
    required this.eCode,
    required this.additiveGroup,
    required this.riskLevelAtCalculationTime,
    required this.riskSource,
    required this.matchType,
    required this.matchConfidence,
    required this.matchAuthority,
    required this.eligibleForAdditiveQuality,
    required this.nutritionOverlap,
    required this.penaltyContribution,
    required this.exclusionReason,
    required Iterable<String> sourceTokens,
  }) : sourceTokens = List.unmodifiable(sourceTokens);

  final String? ingredientId;
  final String canonicalKey;
  final String canonicalName;
  final String? eCode;
  final String? additiveGroup;
  final String riskLevelAtCalculationTime;
  final String riskSource;
  final String matchType;
  final double matchConfidence;
  final String matchAuthority;
  final bool eligibleForAdditiveQuality;
  final String nutritionOverlap;
  final double penaltyContribution;
  final String? exclusionReason;
  final List<String> sourceTokens;

  Map<String, Object?> toJson() => {
    'ingredient_id': ingredientId,
    'canonical_key': canonicalKey,
    'canonical_name': canonicalName,
    'e_code': eCode,
    'additive_group': additiveGroup,
    'risk_level_at_calculation_time': riskLevelAtCalculationTime,
    'risk_source': riskSource,
    'match_type': matchType,
    'match_confidence': matchConfidence,
    'match_authority': matchAuthority,
    'eligible_for_additive_quality': eligibleForAdditiveQuality,
    'nutrition_overlap': nutritionOverlap,
    'penalty_contribution': penaltyContribution,
    'exclusion_reason': exclusionReason,
    'source_tokens': sourceTokens,
  };

  Map<String, Object?> toFingerprintJson() => {
    'canonical_key': canonicalKey,
    'risk_level_at_calculation_time': riskLevelAtCalculationTime,
    'risk_source': riskSource,
    'match_type': matchType,
    'match_confidence': matchConfidence,
    'match_authority': matchAuthority,
    'eligible_for_additive_quality': eligibleForAdditiveQuality,
    'nutrition_overlap': nutritionOverlap,
  };

  static ScoreAuditCanonicalAdditiveSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    if (json == null) return null;
    final canonicalKey = _readString(json['canonical_key']);
    final canonicalName = _readString(json['canonical_name']);
    final risk = _readString(json['risk_level_at_calculation_time']);
    final riskSource = _readString(json['risk_source']);
    final matchType = _readString(json['match_type']);
    final confidence = _readFiniteDouble(json['match_confidence']);
    final authority = _readString(json['match_authority']);
    final eligible = json['eligible_for_additive_quality'];
    final overlap = _readString(json['nutrition_overlap']);
    final penalty = _readFiniteDouble(json['penalty_contribution']);
    final sourceTokens = _readStringList(json['source_tokens']);
    if (canonicalKey == null ||
        canonicalName == null ||
        risk == null ||
        riskSource == null ||
        matchType == null ||
        confidence == null ||
        authority == null ||
        eligible is! bool ||
        overlap == null ||
        penalty == null ||
        sourceTokens == null) {
      return null;
    }
    return ScoreAuditCanonicalAdditiveSnapshot(
      ingredientId: _readOptionalString(json['ingredient_id']),
      canonicalKey: canonicalKey,
      canonicalName: canonicalName,
      eCode: _readOptionalString(json['e_code']),
      additiveGroup: _readOptionalString(json['additive_group']),
      riskLevelAtCalculationTime: risk,
      riskSource: riskSource,
      matchType: matchType,
      matchConfidence: confidence,
      matchAuthority: authority,
      eligibleForAdditiveQuality: eligible,
      nutritionOverlap: overlap,
      penaltyContribution: penalty,
      exclusionReason: _readOptionalString(json['exclusion_reason']),
      sourceTokens: sourceTokens,
    );
  }
}

class ScoreAuditNutritionResultSnapshot {
  ScoreAuditNutritionResultSnapshot({
    required this.resolvedCategory,
    required this.rawScore,
    required this.isPlainWaterSpecialCase,
    required Map<String, Object?> negativePoints,
    required Map<String, Object?> positivePoints,
    required Iterable<String> specialRules,
    required this.nutritionQuality,
  }) : negativePoints = Map.unmodifiable(negativePoints),
       positivePoints = Map.unmodifiable(positivePoints),
       specialRules = List.unmodifiable(specialRules);

  final String resolvedCategory;
  final int? rawScore;
  final bool isPlainWaterSpecialCase;
  final Map<String, Object?> negativePoints;
  final Map<String, Object?> positivePoints;
  final List<String> specialRules;
  final double nutritionQuality;

  Map<String, Object?> toJson() => {
    'resolved_category': resolvedCategory,
    'raw_score': rawScore,
    'is_plain_water_special_case': isPlainWaterSpecialCase,
    'negative_points': negativePoints,
    'positive_points': positivePoints,
    'special_rules': specialRules,
    'nutrition_quality': nutritionQuality,
  };

  static ScoreAuditNutritionResultSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    final negative = _asMap(json?['negative_points']);
    final positive = _asMap(json?['positive_points']);
    if (json == null || negative == null || positive == null) return null;
    final category = _readString(json['resolved_category']);
    final rawScore = _readOptionalInt(json['raw_score']);
    final plainWater = json['is_plain_water_special_case'];
    final rules = _readStringList(json['special_rules']);
    final quality = _readFiniteDouble(json['nutrition_quality']);
    if (category == null ||
        (json['raw_score'] != null && rawScore == null) ||
        plainWater is! bool ||
        rules == null ||
        quality == null ||
        !_allFiniteMapValues(negative) ||
        !_allFiniteMapValues(positive)) {
      return null;
    }
    return ScoreAuditNutritionResultSnapshot(
      resolvedCategory: category,
      rawScore: rawScore,
      isPlainWaterSpecialCase: plainWater,
      negativePoints: negative,
      positivePoints: positive,
      specialRules: rules,
      nutritionQuality: quality,
    );
  }
}

class ScoreAuditAdditiveResultSnapshot {
  ScoreAuditAdditiveResultSnapshot({
    required this.additiveQuality,
    required this.unclampedAdditiveQuality,
    required this.totalPenalty,
    required Map<String, int> counts,
    required List<Map<String, Object?>> tierContributions,
  }) : counts = Map.unmodifiable(counts),
       tierContributions = List.unmodifiable(
         tierContributions.map(
           (entry) => Map<String, Object?>.unmodifiable(entry),
         ),
       );

  final double additiveQuality;
  final double unclampedAdditiveQuality;
  final double totalPenalty;
  final Map<String, int> counts;
  final List<Map<String, Object?>> tierContributions;

  Map<String, Object?> toJson() => {
    'additive_quality': additiveQuality,
    'unclamped_additive_quality': unclampedAdditiveQuality,
    'total_penalty': totalPenalty,
    'counts': counts,
    'tier_contributions': tierContributions,
  };

  static ScoreAuditAdditiveResultSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    final countsJson = _asMap(json?['counts']);
    final contributionsJson = json?['tier_contributions'];
    if (json == null || countsJson == null || contributionsJson is! List) {
      return null;
    }
    final quality = _readFiniteDouble(json['additive_quality']);
    final unclamped = _readFiniteDouble(json['unclamped_additive_quality']);
    final penalty = _readFiniteDouble(json['total_penalty']);
    if (quality == null || unclamped == null || penalty == null) return null;
    final counts = <String, int>{};
    for (final entry in countsJson.entries) {
      final parsed = _readInt(entry.value);
      if (parsed == null) return null;
      counts[entry.key] = parsed;
    }
    final contributions = <Map<String, Object?>>[];
    for (final raw in contributionsJson) {
      final parsed = _asMap(raw);
      if (parsed == null || !_allFiniteMapValues(parsed)) return null;
      contributions.add(parsed);
    }
    return ScoreAuditAdditiveResultSnapshot(
      additiveQuality: quality,
      unclampedAdditiveQuality: unclamped,
      totalPenalty: penalty,
      counts: counts,
      tierContributions: contributions,
    );
  }
}

class EtiketlyScoreAuditSnapshot {
  static const int currentSchemaVersion = 1;

  EtiketlyScoreAuditSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.productId,
    required this.barcode,
    required this.productUpdatedAt,
    required this.productVerificationStatus,
    required this.ingredientText,
    required this.sourceEvidenceSchemaVersion,
    required this.inputFingerprint,
    required this.scoreVersion,
    required this.nutritionMethodologyVersion,
    required this.nutritionTransformVersion,
    required this.additiveTransformVersion,
    required this.resolvedInput,
    required Iterable<ScoreAuditCanonicalAdditiveSnapshot> canonicalAdditives,
    required this.nutritionResult,
    required this.additiveResult,
    required this.nutritionContribution,
    required this.additiveContribution,
    required this.finalScore,
    this.capturedAt,
  }) : canonicalAdditives = List.unmodifiable(canonicalAdditives);

  final int schemaVersion;
  final String productId;
  final String? barcode;
  final DateTime productUpdatedAt;
  final String productVerificationStatus;
  final String ingredientText;
  final int? sourceEvidenceSchemaVersion;
  final String inputFingerprint;
  final String scoreVersion;
  final String nutritionMethodologyVersion;
  final String nutritionTransformVersion;
  final String additiveTransformVersion;
  final ScoreAuditResolvedInputSnapshot resolvedInput;
  final List<ScoreAuditCanonicalAdditiveSnapshot> canonicalAdditives;
  final ScoreAuditNutritionResultSnapshot nutritionResult;
  final ScoreAuditAdditiveResultSnapshot additiveResult;
  final double nutritionContribution;
  final double additiveContribution;
  final double finalScore;
  final DateTime? capturedAt;

  int get displayScore => finalScore.round();

  EtiketlyScoreAuditSnapshot withCapturedAt(DateTime value) {
    return EtiketlyScoreAuditSnapshot(
      schemaVersion: schemaVersion,
      productId: productId,
      barcode: barcode,
      productUpdatedAt: productUpdatedAt,
      productVerificationStatus: productVerificationStatus,
      ingredientText: ingredientText,
      sourceEvidenceSchemaVersion: sourceEvidenceSchemaVersion,
      inputFingerprint: inputFingerprint,
      scoreVersion: scoreVersion,
      nutritionMethodologyVersion: nutritionMethodologyVersion,
      nutritionTransformVersion: nutritionTransformVersion,
      additiveTransformVersion: additiveTransformVersion,
      resolvedInput: resolvedInput,
      canonicalAdditives: canonicalAdditives,
      nutritionResult: nutritionResult,
      additiveResult: additiveResult,
      nutritionContribution: nutritionContribution,
      additiveContribution: additiveContribution,
      finalScore: finalScore,
      capturedAt: value,
    );
  }

  EtiketlyScoreAuditSnapshot withInputFingerprint(String value) {
    return EtiketlyScoreAuditSnapshot(
      schemaVersion: schemaVersion,
      productId: productId,
      barcode: barcode,
      productUpdatedAt: productUpdatedAt,
      productVerificationStatus: productVerificationStatus,
      ingredientText: ingredientText,
      sourceEvidenceSchemaVersion: sourceEvidenceSchemaVersion,
      inputFingerprint: value,
      scoreVersion: scoreVersion,
      nutritionMethodologyVersion: nutritionMethodologyVersion,
      nutritionTransformVersion: nutritionTransformVersion,
      additiveTransformVersion: additiveTransformVersion,
      resolvedInput: resolvedInput,
      canonicalAdditives: canonicalAdditives,
      nutritionResult: nutritionResult,
      additiveResult: additiveResult,
      nutritionContribution: nutritionContribution,
      additiveContribution: additiveContribution,
      finalScore: finalScore,
      capturedAt: capturedAt,
    );
  }

  Map<String, Object?> fingerprintPayload() {
    final additives = [...canonicalAdditives]
      ..sort((left, right) {
        final byKey = left.canonicalKey.compareTo(right.canonicalKey);
        if (byKey != 0) return byKey;
        return (left.ingredientId ?? '').compareTo(right.ingredientId ?? '');
      });
    return {
      'snapshot_schema_version': schemaVersion,
      'score_version': scoreVersion,
      'nutrition_methodology_version': nutritionMethodologyVersion,
      'nutrition_transform_version': nutritionTransformVersion,
      'additive_transform_version': additiveTransformVersion,
      'ingredient_text': ingredientText,
      'source_evidence_schema_version': sourceEvidenceSchemaVersion,
      'resolved_input': resolvedInput.toJson(),
      'canonical_additives': additives
          .map((item) => item.toFingerprintJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'product_id': productId,
    'barcode': barcode,
    'product_updated_at': productUpdatedAt.toUtc().toIso8601String(),
    'product_verification_status': productVerificationStatus,
    'ingredient_text': ingredientText,
    'source_evidence_schema_version': sourceEvidenceSchemaVersion,
    'input_fingerprint': inputFingerprint,
    'score_version': scoreVersion,
    'nutrition_methodology_version': nutritionMethodologyVersion,
    'nutrition_transform_version': nutritionTransformVersion,
    'additive_transform_version': additiveTransformVersion,
    'resolved_input': resolvedInput.toJson(),
    'canonical_additives': canonicalAdditives
        .map((item) => item.toJson())
        .toList(growable: false),
    'nutrition_result': nutritionResult.toJson(),
    'additive_result': additiveResult.toJson(),
    'nutrition_contribution': nutritionContribution,
    'additive_contribution': additiveContribution,
    'final_score': finalScore,
    if (capturedAt != null)
      'captured_at': capturedAt!.toUtc().toIso8601String(),
  };

  static EtiketlyScoreAuditSnapshot? tryFromJson(Object? value) {
    final json = _asMap(value);
    if (json == null) return null;
    final schemaVersion = _readInt(json['schema_version']);
    if (schemaVersion != currentSchemaVersion) return null;
    final productId = _readString(json['product_id']);
    final updatedAt = _readDate(json['product_updated_at']);
    final verificationStatus = _readString(json['product_verification_status']);
    final ingredientText = _readRequiredString(json['ingredient_text']);
    final sourceEvidenceSchemaVersion = _readOptionalInt(
      json['source_evidence_schema_version'],
    );
    final fingerprint = _readString(json['input_fingerprint']);
    final scoreVersion = _readString(json['score_version']);
    final nutritionMethodologyVersion = _readString(
      json['nutrition_methodology_version'],
    );
    final nutritionTransformVersion = _readString(
      json['nutrition_transform_version'],
    );
    final additiveTransformVersion = _readString(
      json['additive_transform_version'],
    );
    final resolvedInput = ScoreAuditResolvedInputSnapshot.tryFromJson(
      json['resolved_input'],
    );
    final nutritionResult = ScoreAuditNutritionResultSnapshot.tryFromJson(
      json['nutrition_result'],
    );
    final additiveResult = ScoreAuditAdditiveResultSnapshot.tryFromJson(
      json['additive_result'],
    );
    final nutritionContribution = _readFiniteDouble(
      json['nutrition_contribution'],
    );
    final additiveContribution = _readFiniteDouble(
      json['additive_contribution'],
    );
    final finalScore = _readFiniteDouble(json['final_score']);
    final additiveJson = json['canonical_additives'];
    if (productId == null ||
        updatedAt == null ||
        verificationStatus == null ||
        ingredientText == null ||
        (json['source_evidence_schema_version'] != null &&
            sourceEvidenceSchemaVersion == null) ||
        fingerprint == null ||
        scoreVersion == null ||
        nutritionMethodologyVersion == null ||
        nutritionTransformVersion == null ||
        additiveTransformVersion == null ||
        resolvedInput == null ||
        nutritionResult == null ||
        additiveResult == null ||
        nutritionContribution == null ||
        additiveContribution == null ||
        finalScore == null ||
        additiveJson is! List) {
      return null;
    }
    final additives = <ScoreAuditCanonicalAdditiveSnapshot>[];
    for (final raw in additiveJson) {
      final item = ScoreAuditCanonicalAdditiveSnapshot.tryFromJson(raw);
      if (item == null) return null;
      additives.add(item);
    }
    final capturedAt = json['captured_at'] == null
        ? null
        : _readDate(json['captured_at']);
    if (json['captured_at'] != null && capturedAt == null) return null;
    return EtiketlyScoreAuditSnapshot(
      schemaVersion: schemaVersion!,
      productId: productId,
      barcode: _readOptionalString(json['barcode']),
      productUpdatedAt: updatedAt,
      productVerificationStatus: verificationStatus,
      ingredientText: ingredientText,
      sourceEvidenceSchemaVersion: sourceEvidenceSchemaVersion,
      inputFingerprint: fingerprint,
      scoreVersion: scoreVersion,
      nutritionMethodologyVersion: nutritionMethodologyVersion,
      nutritionTransformVersion: nutritionTransformVersion,
      additiveTransformVersion: additiveTransformVersion,
      resolvedInput: resolvedInput,
      canonicalAdditives: additives,
      nutritionResult: nutritionResult,
      additiveResult: additiveResult,
      nutritionContribution: nutritionContribution,
      additiveContribution: additiveContribution,
      finalScore: finalScore,
      capturedAt: capturedAt,
    );
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String? _readString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

String? _readRequiredString(Object? value) => value is String ? value : null;

String? _readOptionalString(Object? value) {
  if (value == null) return null;
  return _readString(value);
}

double? _readFiniteDouble(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

double? _readOptionalFiniteDouble(Object? value) {
  if (value == null) return null;
  return _readFiniteDouble(value);
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

int? _readOptionalInt(Object? value) {
  if (value == null) return null;
  return _readInt(value);
}

DateTime? _readDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

List<String>? _readStringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) return null;
  return List.unmodifiable(value.cast<String>());
}

bool _allFiniteMapValues(Map<String, Object?> value) {
  for (final item in value.values) {
    if (item is num && !item.isFinite) return false;
  }
  return true;
}
