import 'dart:convert';

import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

class SupabaseProductScoringLifecycleDataSource
    implements ProductScoringLifecycleDataSource {
  const SupabaseProductScoringLifecycleDataSource({
    this.productRepository = const ProductRepository(),
    this.auditRepository = const SupabaseScoreAuditSnapshotRepository(),
  });

  final ProductRepository productRepository;
  final ScoreAuditSnapshotRepository auditRepository;

  @override
  Future<Product?> fetchProduct(String productId) {
    return productRepository.getProductById(productId);
  }

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() {
    return productRepository.getAllIngredients();
  }

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  }) async {
    var query = SupabaseService.client
        .from('products')
        .update({'scoring_evidence': evidence.toJson()})
        .eq('id', productId);
    query = expectedCurrent == null
        ? query.isFilter('scoring_evidence', null)
        : query.eq('scoring_evidence', jsonEncode(expectedCurrent.toJson()));
    final rows = await query.select('id');
    return (rows as List).isNotEmpty;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) {
    return auditRepository.fetchMatching(current);
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) {
    return auditRepository.insertTrusted(
      snapshot,
      triggerSource: triggerSource,
    );
  }
}
