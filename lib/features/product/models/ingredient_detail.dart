import 'ingredient.dart';
import 'ingredient_risk_reference.dart';

/// Rich ingredient detail wrapper used by the UI
class IngredientDetail {
  final Ingredient ingredient;

  IngredientDetail(this.ingredient);

  String get title => ingredient.name;

  String get shortDescription => ingredient.shortDescription ?? '';

  String get longDescription => ingredient.longDescription ?? '';

  String? get additiveGroup => ingredient.additiveGroup;

  List<String> get aliases =>
      ingredient.aliases ?? ingredient.alternativeNames ?? [];

  List<String> get englishNames => ingredient.englishNames ?? [];

  String? get childWarning => ingredient.childWarning;

  List<String> get sourceReferences => ingredient.sourceReferences ?? [];

  List<IngredientRiskReference> get sourceReferenceEntries =>
      ingredient.sourceReferenceEntries ?? [];

  // New educational metadata fields
  String? get ingredientType => ingredient.ingredientType;

  String? get shortPurpose => ingredient.shortPurpose;

  String? get shortRiskSummary => ingredient.shortRiskSummary;

  List<String>? get cautionGroups => ingredient.cautionGroups;

  String? get processingRole => ingredient.processingRole;

  bool get hasExplanationMetadata =>
      ingredientType != null ||
      shortPurpose != null ||
      shortRiskSummary != null ||
      (cautionGroups?.isNotEmpty ?? false) ||
      processingRole != null;
}
