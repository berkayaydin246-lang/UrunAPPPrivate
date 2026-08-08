import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Versioned source evidence for a future deterministic scoring methodology.
///
/// This snapshot deliberately contains no calculated points, grade, or score.
class ScoringEvidenceSnapshot {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final NutritionBasis nutritionBasis;
  final NutritionProductState nutritionProductState;
  final ScoringNutritionData nutrition;
  final CompositionPercentageEvidence fvlEvidence;
  final PresenceEvidence nnsEvidence;
  final IngredientEvidenceCompleteness ingredientEvidenceCompleteness;
  final ScoringCategoryEvidence categoryEvidence;
  final ScoringClassificationFacts classificationFacts;
  final ScoringEvidenceAdminMetadata? adminVerification;

  ScoringEvidenceSnapshot({
    this.schemaVersion = currentSchemaVersion,
    this.nutritionBasis = NutritionBasis.unknown,
    this.nutritionProductState = NutritionProductState.unknown,
    this.nutrition = const ScoringNutritionData(),
    this.fvlEvidence = const CompositionPercentageEvidence.unknown(),
    this.nnsEvidence = const PresenceEvidence.unknown(),
    this.ingredientEvidenceCompleteness =
        IngredientEvidenceCompleteness.unknown,
    ScoringCategoryEvidence? categoryEvidence,
    this.classificationFacts = const ScoringClassificationFacts(),
    this.adminVerification,
  }) : categoryEvidence = categoryEvidence ?? ScoringCategoryEvidence.unknown(),
       assert(schemaVersion == currentSchemaVersion);

  /// Returns null for absent, malformed, or unsupported evidence versions.
  /// Individual malformed fields in a supported snapshot degrade to unknown.
  static ScoringEvidenceSnapshot? tryFromJson(dynamic value) {
    final json = _asMap(value);
    if (json == null ||
        _readSchemaVersion(json['schema_version']) != currentSchemaVersion) {
      return null;
    }

    return ScoringEvidenceSnapshot(
      nutritionBasis:
          _enumValue(NutritionBasis.values, json['nutrition_basis']) ??
          NutritionBasis.unknown,
      nutritionProductState:
          _enumValue(
            NutritionProductState.values,
            json['nutrition_product_state'],
          ) ??
          NutritionProductState.unknown,
      nutrition: _nutritionFromJson(json['nutrition']),
      fvlEvidence: _fvlFromJson(json['fvl_evidence']),
      nnsEvidence: _presenceFromJson(json['nns_evidence']),
      ingredientEvidenceCompleteness:
          _enumValue(
            IngredientEvidenceCompleteness.values,
            json['ingredient_evidence_completeness'],
          ) ??
          IngredientEvidenceCompleteness.unknown,
      categoryEvidence: _categoryEvidenceFromJson(json['category_evidence']),
      classificationFacts: _classificationFactsFromJson(
        json['classification_facts'],
      ),
      adminVerification: ScoringEvidenceAdminMetadata.tryFromJson(
        json['admin_verification'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'nutrition_basis': _enumName(nutritionBasis),
      'nutrition_product_state': _enumName(nutritionProductState),
      'nutrition': _nutritionToJson(nutrition),
      'fvl_evidence': _fvlToJson(fvlEvidence),
      'nns_evidence': _presenceToJson(nnsEvidence),
      'ingredient_evidence_completeness': _enumName(
        ingredientEvidenceCompleteness,
      ),
      'category_evidence': _categoryEvidenceToJson(categoryEvidence),
      'classification_facts': _classificationFactsToJson(classificationFacts),
      if (adminVerification != null)
        'admin_verification': adminVerification!.toJson(),
    };
  }

  EtiketlyScoringInput toScoringInput() {
    return EtiketlyScoringInput(
      nutrition: nutrition,
      nutritionBasis: nutritionBasis,
      productState: nutritionProductState,
      categoryEvidence: categoryEvidence,
      classificationFacts: classificationFacts,
      fvlEvidence: fvlEvidence,
      nnsEvidence: nnsEvidence,
      ingredientEvidenceCompleteness: ingredientEvidenceCompleteness,
    );
  }

  ScoringEvidenceSnapshot copyWith({
    NutritionBasis? nutritionBasis,
    NutritionProductState? nutritionProductState,
    ScoringNutritionData? nutrition,
    CompositionPercentageEvidence? fvlEvidence,
    PresenceEvidence? nnsEvidence,
    IngredientEvidenceCompleteness? ingredientEvidenceCompleteness,
    ScoringCategoryEvidence? categoryEvidence,
    ScoringClassificationFacts? classificationFacts,
    ScoringEvidenceAdminMetadata? adminVerification,
  }) {
    return ScoringEvidenceSnapshot(
      nutritionBasis: nutritionBasis ?? this.nutritionBasis,
      nutritionProductState:
          nutritionProductState ?? this.nutritionProductState,
      nutrition: nutrition ?? this.nutrition,
      fvlEvidence: fvlEvidence ?? this.fvlEvidence,
      nnsEvidence: nnsEvidence ?? this.nnsEvidence,
      ingredientEvidenceCompleteness:
          ingredientEvidenceCompleteness ?? this.ingredientEvidenceCompleteness,
      categoryEvidence: categoryEvidence ?? this.categoryEvidence,
      classificationFacts: classificationFacts ?? this.classificationFacts,
      adminVerification: adminVerification ?? this.adminVerification,
    );
  }
}

class ScoringEvidenceAdminMetadata {
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? note;

  const ScoringEvidenceAdminMetadata({
    this.verifiedBy,
    this.verifiedAt,
    this.note,
  });

  bool get hasData => verifiedBy != null || verifiedAt != null || note != null;

  static ScoringEvidenceAdminMetadata? tryFromJson(dynamic value) {
    final json = _asMap(value);
    if (json == null) return null;
    final metadata = ScoringEvidenceAdminMetadata(
      verifiedBy: _cleanText(json['verified_by']),
      verifiedAt: _readDate(json['verified_at']),
      note: _cleanText(json['note']),
    );
    return metadata.hasData ? metadata : null;
  }

  Map<String, dynamic> toJson() {
    return {
      if (verifiedBy != null) 'verified_by': verifiedBy,
      if (verifiedAt != null) 'verified_at': verifiedAt!.toIso8601String(),
      if (note != null) 'note': note,
    };
  }
}

ScoringNutritionData _nutritionFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return const ScoringNutritionData();
  return ScoringNutritionData(
    energyKj: _doubleEvidenceFromJson(json['energy_kj']),
    energyKcal: _doubleEvidenceFromJson(json['energy_kcal']),
    totalFat: _doubleEvidenceFromJson(json['total_fat']),
    saturatedFat: _doubleEvidenceFromJson(json['saturated_fat']),
    sugars: _doubleEvidenceFromJson(json['sugars']),
    protein: _doubleEvidenceFromJson(json['protein']),
    fiber: _doubleEvidenceFromJson(json['fiber']),
    salt: _doubleEvidenceFromJson(json['salt']),
    sodium: _doubleEvidenceFromJson(json['sodium']),
  );
}

Map<String, dynamic> _nutritionToJson(ScoringNutritionData value) {
  return {
    'energy_kj': _evidenceToJson(value.energyKj),
    'energy_kcal': _evidenceToJson(value.energyKcal),
    'total_fat': _evidenceToJson(value.totalFat),
    'saturated_fat': _evidenceToJson(value.saturatedFat),
    'sugars': _evidenceToJson(value.sugars),
    'protein': _evidenceToJson(value.protein),
    'fiber': _evidenceToJson(value.fiber),
    'salt': _evidenceToJson(value.salt),
    'sodium': _evidenceToJson(value.sodium),
  };
}

EvidenceValue<double> _doubleEvidenceFromJson(
  dynamic value, {
  double? maximum,
}) {
  final json = _asMap(value);
  if (json == null) return const EvidenceValue<double>.unknown();
  final rawValue = json['value'];
  final parsedValue = _finiteNonNegative(rawValue, maximum: maximum);
  if (rawValue != null && parsedValue == null) {
    return const EvidenceValue<double>.unknown();
  }
  final provenance =
      _enumValue(EvidenceProvenance.values, json['provenance']) ??
      EvidenceProvenance.unknown;
  final verification = provenance == EvidenceProvenance.unknown
      ? EvidenceVerification.unknown
      : _enumValue(EvidenceVerification.values, json['verification']) ??
            EvidenceVerification.unknown;
  return EvidenceValue<double>(
    value: parsedValue,
    provenance: provenance,
    verification: verification,
  );
}

EvidenceValue<bool> _boolEvidenceFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return const EvidenceValue<bool>.unknown();
  final rawValue = json['value'];
  if (rawValue != null && rawValue is! bool) {
    return const EvidenceValue<bool>.unknown();
  }
  final provenance =
      _enumValue(EvidenceProvenance.values, json['provenance']) ??
      EvidenceProvenance.unknown;
  final verification = provenance == EvidenceProvenance.unknown
      ? EvidenceVerification.unknown
      : _enumValue(EvidenceVerification.values, json['verification']) ??
            EvidenceVerification.unknown;
  return EvidenceValue<bool>(
    value: rawValue as bool?,
    provenance: provenance,
    verification: verification,
  );
}

Map<String, dynamic> _evidenceToJson<T>(
  EvidenceValue<T> value, {
  double? maximum,
}) {
  final rawValue = value.value;
  if (rawValue is num &&
      _finiteNonNegative(rawValue, maximum: maximum) == null) {
    return const {
      'value': null,
      'provenance': 'unknown',
      'verification': 'unknown',
    };
  }
  return {
    'value': rawValue,
    'provenance': _enumName(value.provenance),
    'verification': _enumName(
      value.provenance == EvidenceProvenance.unknown
          ? EvidenceVerification.unknown
          : value.verification,
    ),
  };
}

CompositionPercentageEvidence _fvlFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return const CompositionPercentageEvidence.unknown();
  final state = _enumValue(CompositionPercentageState.values, json['state']);
  final provenance = _enumValue(EvidenceProvenance.values, json['provenance']);
  final verification =
      provenance == null || provenance == EvidenceProvenance.unknown
      ? EvidenceVerification.unknown
      : _enumValue(EvidenceVerification.values, json['verification']) ??
            EvidenceVerification.unknown;
  final dependency = _enumValue(EvidenceDependency.values, json['dependency']);
  if (state == null || provenance == null || dependency == null) {
    return const CompositionPercentageEvidence.unknown();
  }

  switch (state) {
    case CompositionPercentageState.known:
      final percentage = _finiteNonNegative(json['percentage'], maximum: 100);
      if (percentage == null) {
        return const CompositionPercentageEvidence.unknown();
      }
      return CompositionPercentageEvidence.known(
        percentage,
        provenance: provenance,
        verification: verification,
        dependency: dependency,
      );
    case CompositionPercentageState.provenAbsent:
      final percentage = _finiteNonNegative(json['percentage'], maximum: 100);
      if (percentage != 0) {
        return const CompositionPercentageEvidence.unknown();
      }
      return CompositionPercentageEvidence.provenAbsent(
        provenance: provenance,
        verification: verification,
        dependency: dependency,
      );
    case CompositionPercentageState.unknown:
      return const CompositionPercentageEvidence.unknown();
  }
}

Map<String, dynamic> _fvlToJson(CompositionPercentageEvidence value) {
  if (value.state == CompositionPercentageState.known &&
      _finiteNonNegative(value.percentage, maximum: 100) == null) {
    return _unknownFvlJson();
  }
  if (value.state == CompositionPercentageState.provenAbsent &&
      value.percentage != 0) {
    return _unknownFvlJson();
  }
  return {
    'state': _enumName(value.state),
    'percentage': value.percentage,
    'provenance': _enumName(value.provenance),
    'verification': _enumName(
      value.provenance == EvidenceProvenance.unknown
          ? EvidenceVerification.unknown
          : value.verification,
    ),
    'dependency': _enumName(value.dependency),
  };
}

Map<String, dynamic> _unknownFvlJson() {
  return const {
    'state': 'unknown',
    'percentage': null,
    'provenance': 'unknown',
    'verification': 'unknown',
    'dependency': 'none',
  };
}

PresenceEvidence _presenceFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return const PresenceEvidence.unknown();
  final state = _enumValue(PresenceEvidenceState.values, json['state']);
  final provenance = _enumValue(EvidenceProvenance.values, json['provenance']);
  final verification =
      provenance == null || provenance == EvidenceProvenance.unknown
      ? EvidenceVerification.unknown
      : _enumValue(EvidenceVerification.values, json['verification']) ??
            EvidenceVerification.unknown;
  final dependency = _enumValue(EvidenceDependency.values, json['dependency']);
  if (state == null || provenance == null || dependency == null) {
    return const PresenceEvidence.unknown();
  }

  return switch (state) {
    PresenceEvidenceState.present => PresenceEvidence.present(
      provenance: provenance,
      verification: verification,
      dependency: dependency,
    ),
    PresenceEvidenceState.absent => PresenceEvidence.absent(
      provenance: provenance,
      verification: verification,
      dependency: dependency,
    ),
    PresenceEvidenceState.unknown => const PresenceEvidence.unknown(),
  };
}

Map<String, dynamic> _presenceToJson(PresenceEvidence value) {
  return {
    'state': _enumName(value.state),
    'provenance': _enumName(value.provenance),
    'verification': _enumName(
      value.provenance == EvidenceProvenance.unknown
          ? EvidenceVerification.unknown
          : value.verification,
    ),
    'dependency': _enumName(value.dependency),
  };
}

ScoringCategoryEvidence _categoryEvidenceFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return ScoringCategoryEvidence.unknown();
  final category =
      _enumValue(ScoringCategory.values, json['resolved_category']) ??
      ScoringCategory.unknown;
  final source =
      _enumValue(CategoryEvidenceSource.values, json['source']) ??
      CategoryEvidenceSource.unknown;
  final evidenceValues = _stringList(json['evidence_values']);
  final reasons = <CategoryResolutionReason>{};
  final rawReasons = json['reasons'];
  if (rawReasons is List) {
    for (final rawReason in rawReasons) {
      final reason = _enumValue(CategoryResolutionReason.values, rawReason);
      if (reason != null) reasons.add(reason);
    }
  }
  if (category == ScoringCategory.unknown ||
      source == CategoryEvidenceSource.unknown) {
    return ScoringCategoryEvidence.unknown(
      evidenceValues: evidenceValues,
      reasons: reasons.isEmpty
          ? const [CategoryResolutionReason.insufficientEvidence]
          : reasons,
    );
  }
  return ScoringCategoryEvidence(
    resolvedCategory: category,
    source: source,
    evidenceValues: evidenceValues,
    reasons: reasons,
  );
}

Map<String, dynamic> _categoryEvidenceToJson(ScoringCategoryEvidence value) {
  return {
    'resolved_category': _enumName(value.resolvedCategory),
    'source': _enumName(value.source),
    'evidence_values': value.evidenceValues,
    'reasons': value.reasons.map(_enumName).toList(),
  };
}

ScoringClassificationFacts _classificationFactsFromJson(dynamic value) {
  final json = _asMap(value);
  if (json == null) return const ScoringClassificationFacts();
  return ScoringClassificationFacts(
    isPlainWater: _optionalBoolEvidence(json, 'is_plain_water'),
    redMeatPercentage: _optionalDoubleEvidence(
      json,
      'red_meat_percentage',
      maximum: 100,
    ),
    redMeatIsPrimaryIngredient: _optionalBoolEvidence(
      json,
      'red_meat_is_primary_ingredient',
    ),
    nutSeedPercentage: _optionalDoubleEvidence(
      json,
      'nut_seed_percentage',
      maximum: 100,
    ),
    isPlantBasedCheeseAlternative: _optionalBoolEvidence(
      json,
      'is_plant_based_cheese_alternative',
    ),
    isCompoundProduct: _optionalBoolEvidence(json, 'is_compound_product'),
    isDrinkableDairy: _optionalBoolEvidence(json, 'is_drinkable_dairy'),
    isBeverage: _optionalBoolEvidence(json, 'is_beverage'),
    isFoodSupplement: _optionalBoolEvidence(json, 'is_food_supplement'),
    isInfantFood: _optionalBoolEvidence(json, 'is_infant_food'),
    isMedicalFood: _optionalBoolEvidence(json, 'is_medical_food'),
    isSportsNutrition: _optionalBoolEvidence(json, 'is_sports_nutrition'),
    isMealReplacement: _optionalBoolEvidence(json, 'is_meal_replacement'),
  );
}

Map<String, dynamic> _classificationFactsToJson(
  ScoringClassificationFacts value,
) {
  return {
    if (value.isPlainWater != null)
      'is_plain_water': _evidenceToJson(value.isPlainWater!),
    if (value.redMeatPercentage != null)
      'red_meat_percentage': _evidenceToJson(
        value.redMeatPercentage!,
        maximum: 100,
      ),
    if (value.redMeatIsPrimaryIngredient != null)
      'red_meat_is_primary_ingredient': _evidenceToJson(
        value.redMeatIsPrimaryIngredient!,
      ),
    if (value.nutSeedPercentage != null)
      'nut_seed_percentage': _evidenceToJson(
        value.nutSeedPercentage!,
        maximum: 100,
      ),
    if (value.isPlantBasedCheeseAlternative != null)
      'is_plant_based_cheese_alternative': _evidenceToJson(
        value.isPlantBasedCheeseAlternative!,
      ),
    if (value.isCompoundProduct != null)
      'is_compound_product': _evidenceToJson(value.isCompoundProduct!),
    if (value.isDrinkableDairy != null)
      'is_drinkable_dairy': _evidenceToJson(value.isDrinkableDairy!),
    if (value.isBeverage != null)
      'is_beverage': _evidenceToJson(value.isBeverage!),
    if (value.isFoodSupplement != null)
      'is_food_supplement': _evidenceToJson(value.isFoodSupplement!),
    if (value.isInfantFood != null)
      'is_infant_food': _evidenceToJson(value.isInfantFood!),
    if (value.isMedicalFood != null)
      'is_medical_food': _evidenceToJson(value.isMedicalFood!),
    if (value.isSportsNutrition != null)
      'is_sports_nutrition': _evidenceToJson(value.isSportsNutrition!),
    if (value.isMealReplacement != null)
      'is_meal_replacement': _evidenceToJson(value.isMealReplacement!),
  };
}

EvidenceValue<bool>? _optionalBoolEvidence(
  Map<String, dynamic> json,
  String key,
) => json.containsKey(key) ? _boolEvidenceFromJson(json[key]) : null;

EvidenceValue<double>? _optionalDoubleEvidence(
  Map<String, dynamic> json,
  String key, {
  double? maximum,
}) => json.containsKey(key)
    ? _doubleEvidenceFromJson(json[key], maximum: maximum)
    : null;

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[key] = entry.value;
  }
  return result;
}

int? _readSchemaVersion(dynamic value) {
  if (value is! num || !value.isFinite) return null;
  final integer = value.toInt();
  return value == integer ? integer : null;
}

double? _finiteNonNegative(dynamic value, {double? maximum}) {
  if (value is! num) return null;
  final parsed = value.toDouble();
  if (!parsed.isFinite || parsed < 0) return null;
  if (maximum != null && parsed > maximum) return null;
  return parsed;
}

T? _enumValue<T extends Enum>(List<T> values, dynamic value) {
  if (value is! String) return null;
  for (final candidate in values) {
    if (value == candidate.name || value == _enumName(candidate)) {
      return candidate;
    }
  }
  return null;
}

String _enumName(Enum value) {
  return value.name.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)!.toLowerCase()}',
  );
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _cleanText(dynamic value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

DateTime? _readDate(dynamic value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}
