import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Ingredient ingredient(
    String id,
    String name, {
    String riskLevel = 'unknown',
  }) {
    return Ingredient(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      riskLevel: riskLevel,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('palm oil gets neutral explanation, WHO references, and no E-code', () {
    final resolved = enrichIngredientKnowledge(ingredient('1', 'Palm Yağı'));

    expect(ingredientHasExplanationMetadata(resolved), isTrue);
    expect(resolved.eCode, isNull);
    expect(resolved.shortPurpose, contains('bitkisel bir yağdır'));
    expect(resolved.shortRiskSummary, contains('Doymuş yağ'));
    expect(
      resolved.sourceReferenceEntries?.any(
        (reference) =>
            reference.authority == 'WHO' &&
            reference.title.contains('Saturated fatty acid'),
      ),
      isTrue,
    );
  });

  test('potassium sorbate gets E202 and official additive references', () {
    final resolved = enrichIngredientKnowledge(
      ingredient('2', 'Potasyum sorbat'),
    );

    expect(resolved.eCode, 'E202');
    expect(resolved.ingredientType, 'Koruyucu');
    expect(
      resolved.sourceReferenceEntries?.any(
        (reference) =>
            reference.authority == 'European Commission' &&
            reference.documentCode == 'E202',
      ),
      isTrue,
    );
    expect(
      resolved.sourceReferenceEntries?.any(
        (reference) =>
            reference.authority == 'EFSA' &&
            reference.documentCode == 'EFSA Journal 2019;17(3):5625',
      ),
      isTrue,
    );
  });

  test('E471 aliases share one reviewed EFSA reference', () {
    final resolved = enrichIngredientKnowledge(
      ingredient('e471', 'Yağ asitlerinin mono- ve digliseritleri'),
    );

    expect(resolved.eCode, 'E471');
    expect(
      resolved.sourceReferenceEntries?.any(
        (reference) =>
            reference.authority == 'EFSA' &&
            reference.documentCode == 'EFSA Journal 2017;15(11):5045',
      ),
      isTrue,
    );
  });

  test('static E282 identity has aliases, authority, and no invented risk', () {
    for (final token in const [
      'kalsiyum propiyonat',
      'calcium propionate',
      'E282',
    ]) {
      final resolved = reviewedCanonicalIngredientIdentityForToken(token);

      expect(resolved, isNotNull, reason: token);
      expect(resolved!.eCode, 'E282', reason: token);
      expect(resolved.riskLevel, 'unknown', reason: token);
      expect(
        resolved.sourceReferenceEntries?.single.documentCode,
        'EFSA Journal 2014;12(7):3779',
        reason: token,
      );
    }
  });

  test('ordinary ingredients keep E-code empty', () {
    final sugar = enrichIngredientKnowledge(ingredient('3', 'Şeker'));
    final salt = enrichIngredientKnowledge(ingredient('4', 'Tuz'));
    final palm = enrichIngredientKnowledge(ingredient('5', 'Palm Yağı'));

    expect(isValidFoodAdditiveCode(sugar.eCode), isFalse);
    expect(isValidFoodAdditiveCode(salt.eCode), isFalse);
    expect(isValidFoodAdditiveCode(palm.eCode), isFalse);
  });

  test('sorbitol syrup keeps its specific additive code', () {
    final resolved = enrichIngredientKnowledge(
      ingredient('6', 'Sorbitol Şurubu'),
    );

    expect(resolved.eCode, 'E420(II)');
    expect(isValidFoodAdditiveCode(resolved.eCode), isTrue);
  });
}
