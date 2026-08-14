import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/admin/models/user_submission.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/data/product_scoring_lifecycle_data_source.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';

/// Thrown when a product with the same barcode already exists in the database.
class DuplicateBarcodeException implements Exception {
  const DuplicateBarcodeException();
}

class ProductDraftCreationResult {
  const ProductDraftCreationResult({
    required this.productId,
    required this.scoring,
  });

  final String productId;
  final ProductScoringLifecycleResult scoring;
}

class ProductDraftRepository {
  const ProductDraftRepository({
    ProductScoringLifecycleService scoringLifecycle =
        const ProductScoringLifecycleService(
          dataSource: SupabaseProductScoringLifecycleDataSource(),
        ),
  }) : _scoringLifecycle = scoringLifecycle;

  final ProductScoringLifecycleService _scoringLifecycle;

  /// Creates a new pending product draft from an approved user submission.
  ///
  /// Throws [DuplicateBarcodeException] if a product with the same barcode
  /// already exists. Returns the new product's UUID on success.
  Future<ProductDraftCreationResult> createDraftFromSubmission(
    UserSubmission submission,
  ) async {
    final client = SupabaseService.client;

    // Prevent duplicate barcode before inserting.
    final barcode = submission.barcode?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      final existing = await client
          .from('products')
          .select('id')
          .eq('barcode', barcode)
          .maybeSingle();

      if (existing != null) {
        throw const DuplicateBarcodeException();
      }
    }

    final payload = <String, dynamic>{
      'name': (submission.productName?.trim().isNotEmpty == true)
          ? submission.productName!.trim()
          : 'İsimsiz Ürün',
      'barcode': (barcode != null && barcode.isNotEmpty) ? barcode : null,
      'ingredients_text': submission.ocrText,
      'image_url': submission.frontImageUrl,
      'source': 'user_submission',
      'verification_status': 'pending',
    };

    final result = await client
        .from('products')
        .insert(payload)
        .select('id')
        .single();

    final productId = result['id'] as String;
    final scoring = await _scoringLifecycle.processCurrent(
      productId,
      triggerSource: ScoreAuditTriggerSource.submissionApproval,
    );
    return ProductDraftCreationResult(productId: productId, scoring: scoring);
  }
}
