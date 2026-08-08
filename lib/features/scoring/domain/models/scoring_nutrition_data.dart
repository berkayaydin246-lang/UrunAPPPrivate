import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';

class ScoringNutritionData {
  final EvidenceValue<double> energyKj;
  final EvidenceValue<double> energyKcal;
  final EvidenceValue<double> totalFat;
  final EvidenceValue<double> saturatedFat;
  final EvidenceValue<double> sugars;
  final EvidenceValue<double> protein;
  final EvidenceValue<double> fiber;
  final EvidenceValue<double> salt;
  final EvidenceValue<double> sodium;

  const ScoringNutritionData({
    this.energyKj = const EvidenceValue<double>.unknown(),
    this.energyKcal = const EvidenceValue<double>.unknown(),
    this.totalFat = const EvidenceValue<double>.unknown(),
    this.saturatedFat = const EvidenceValue<double>.unknown(),
    this.sugars = const EvidenceValue<double>.unknown(),
    this.protein = const EvidenceValue<double>.unknown(),
    this.fiber = const EvidenceValue<double>.unknown(),
    this.salt = const EvidenceValue<double>.unknown(),
    this.sodium = const EvidenceValue<double>.unknown(),
  });
}
