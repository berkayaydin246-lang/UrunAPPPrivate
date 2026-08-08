import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

enum ApproveProductResult {
  approved, // new product row created
  updatedExisting, // existing product enriched with submission data
  notFound, // submission id not found
  invalidBarcode, // submission has no barcode
  alreadyProcessed, // submission is not pending
}

class ProductSubmissionApprovalRepository {
  const ProductSubmissionApprovalRepository();

  // ── read ──────────────────────────────────────────────────────────────────

  Future<List<ProductSubmission>> fetchPendingSubmissions() async {
    final response = await SupabaseService.client
        .from('product_submissions')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return (response as List)
        .map((json) => ProductSubmission.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ProductSubmission?> fetchById(String submissionId) async {
    final row = await SupabaseService.client
        .from('product_submissions')
        .select()
        .eq('id', submissionId)
        .maybeSingle();
    if (row == null) return null;
    return ProductSubmission.fromJson(row);
  }

  // ── approval ──────────────────────────────────────────────────────────────

  /// Approve a pending submission.
  ///
  /// Creates a new product row, or enriches an existing one by barcode
  /// (only fills fields that are currently null — never overwrites verified data).
  /// Then marks the submission as `approved`.
  ///
  /// Pass [editedProductName], [editedBrand], [editedIngredientsText] to let
  /// the admin override extracted values before approval.
  Future<ApproveProductResult> approveProductSubmission(
    String submissionId, {
    String? editedProductName,
    String? editedBrand,
    String? editedIngredientsText,
    Map<String, dynamic>? editedNutrition,
    bool nutritionWasReviewed = false,
  }) async {
    final client = SupabaseService.client;
    _debugSubmissionApprovalLog(
      '[Approval] started — submissionId=$submissionId',
    );

    // 1. Fetch submission.
    _debugSubmissionApprovalLog(
      '[Approval] fetching submission from product_submissions',
    );
    final row = await client
        .from('product_submissions')
        .select()
        .eq('id', submissionId)
        .maybeSingle();

    if (row == null) {
      _debugSubmissionApprovalLog('[Approval] submission not found');
      return ApproveProductResult.notFound;
    }

    final submission = ProductSubmission.fromJson(row);
    _debugSubmissionApprovalLog(
      '[Approval] submission status=${submission.status} barcode=${submission.barcode}',
    );

    if (submission.status != 'pending') {
      _debugSubmissionApprovalLog(
        '[Approval] submission already processed (status=${submission.status})',
      );
      return ApproveProductResult.alreadyProcessed;
    }

    final barcode = submission.barcode.trim();
    if (barcode.isEmpty) {
      _debugSubmissionApprovalLog(
        '[Approval] barcode is empty — cannot approve',
      );
      return ApproveProductResult.invalidBarcode;
    }

    final insertMap = buildProductInsertMap(
      submission,
      editedProductName: editedProductName,
      editedBrand: editedBrand,
      editedIngredientsText: editedIngredientsText,
      editedNutrition: editedNutrition,
      nutritionWasReviewed: nutritionWasReviewed,
    );

    _debugSubmissionApprovalLog(
      '[Approval] resolved fields — name=${insertMap['name']} '
      'brand=${insertMap.containsKey('brand')} '
      'ingredientsText=${insertMap.containsKey('ingredients_text')} '
      'nutritionText=${insertMap.containsKey('nutrition_text')}',
    );

    // 2. Check for existing product.
    _debugSubmissionApprovalLog(
      '[Approval] checking products table for barcode=$barcode',
    );
    final existingRow = await client
        .from('products')
        .select()
        .eq('barcode', barcode)
        .maybeSingle();

    final ApproveProductResult result;

    if (existingRow == null) {
      // Insert new product.
      _debugSubmissionApprovalLog(
        '[Approval] no existing product — inserting new product row',
      );
      await client.from('products').insert(insertMap);
      _debugSubmissionApprovalLog('[Approval] product insert succeeded');
      result = ApproveProductResult.approved;
    } else {
      // Enrich existing product — only fill null/empty fields.
      _debugSubmissionApprovalLog(
        '[Approval] existing product found — patching missing fields',
      );
      final existing = Product.fromJson(existingRow);
      final evidenceMerge = const ScoringEvidenceMerger().merge(
        existing.scoringEvidence,
        submission.scoringEvidence,
      );
      if (evidenceMerge.conflicts.isNotEmpty) {
        _debugSubmissionApprovalLog(
          '[Approval] scoring evidence conflicts retained deterministically: '
          '${evidenceMerge.conflicts.map((item) => item.field).join(', ')}',
        );
      }
      final patch = buildProductEnrichPatch(
        existing,
        insertMap,
        scoringEvidenceMerge: evidenceMerge,
      );

      if (patch.isNotEmpty) {
        _debugSubmissionApprovalLog(
          '[Approval] updating product with patch keys=${patch.keys.toList()}',
        );
        await client.from('products').update(patch).eq('barcode', barcode);
        _debugSubmissionApprovalLog('[Approval] product update succeeded');
      } else {
        _debugSubmissionApprovalLog(
          '[Approval] no patch needed — existing product already complete',
        );
      }
      result = ApproveProductResult.updatedExisting;
    }

    // 3. Mark submission approved.
    _debugSubmissionApprovalLog(
      '[Approval] updating product_submissions.status = approved',
    );
    await client
        .from('product_submissions')
        .update({'status': 'approved'})
        .eq('id', submissionId);
    _debugSubmissionApprovalLog(
      '[Approval] submission status update succeeded — result=$result',
    );

    return result;
  }

  // ── rejection ─────────────────────────────────────────────────────────────

  Future<void> rejectProductSubmission(
    String submissionId, {
    String? reason,
  }) async {
    _debugSubmissionApprovalLog(
      '[Approval] rejecting submissionId=$submissionId reason=$reason',
    );
    final client = SupabaseService.client;
    final resolved = _resolve(reason);
    await client
        .from('product_submissions')
        .update({'status': 'rejected', ...?_entry('notes', resolved)})
        .eq('id', submissionId);
    _debugSubmissionApprovalLog('[Approval] rejection update succeeded');
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Builds the final `products` row from a submission and reviewed admin data.
  static Map<String, dynamic> buildProductInsertMap(
    ProductSubmission submission, {
    String? editedProductName,
    String? editedBrand,
    String? editedIngredientsText,
    Map<String, dynamic>? editedNutrition,
    bool nutritionWasReviewed = false,
  }) {
    final nutritionSource = nutritionWasReviewed
        ? editedNutrition
        : editedNutrition ?? submission.extractedNutrition;
    final normalizedNutrition = normalizeNutritionMap(nutritionSource);
    final nutritionText = normalizedNutrition == null
        ? null
        : jsonEncode(normalizedNutrition);

    return {
      'barcode': submission.barcode.trim(),
      'name':
          _resolve(editedProductName) ??
          _resolve(submission.productName) ??
          'İsimsiz Ürün',
      'source': 'user_submission',
      'verification_status': 'user_submitted',
      ...?_entry('brand', _resolve(editedBrand) ?? _resolve(submission.brand)),
      ...?_entry(
        'image_url',
        _resolve(submission.frontImageUrl) ?? _resolve(submission.imageUrl),
      ),
      ...?_entry(
        'ingredients_text',
        _resolve(editedIngredientsText) ??
            _resolve(submission.extractedIngredientsText),
      ),
      ...?_entry('nutrition_text', nutritionText),
      if (submission.scoringEvidence != null)
        'scoring_evidence': submission.scoringEvidence!.toJson(),
    };
  }

  /// Fills only missing product fields; existing nutrition is never replaced.
  static Map<String, dynamic> buildProductEnrichPatch(
    Product existing,
    Map<String, dynamic> reviewedInsertMap, {
    ScoringEvidenceMergeResult? scoringEvidenceMerge,
  }) {
    final patch = <String, dynamic>{};
    if (_isEmpty(existing.name)) patch['name'] = reviewedInsertMap['name'];
    if (existing.brand == null && reviewedInsertMap.containsKey('brand')) {
      patch['brand'] = reviewedInsertMap['brand'];
    }
    if (existing.imageUrl == null &&
        reviewedInsertMap.containsKey('image_url')) {
      patch['image_url'] = reviewedInsertMap['image_url'];
    }
    if (existing.ingredientsText == null &&
        reviewedInsertMap.containsKey('ingredients_text')) {
      patch['ingredients_text'] = reviewedInsertMap['ingredients_text'];
    }
    if (existing.nutritionText == null &&
        reviewedInsertMap.containsKey('nutrition_text')) {
      patch['nutrition_text'] = reviewedInsertMap['nutrition_text'];
    }
    final incomingEvidence = ScoringEvidenceSnapshot.tryFromJson(
      reviewedInsertMap['scoring_evidence'],
    );
    final evidenceMerge =
        scoringEvidenceMerge ??
        const ScoringEvidenceMerger().merge(
          existing.scoringEvidence,
          incomingEvidence,
        );
    if (evidenceMerge.changed && evidenceMerge.evidence != null) {
      patch['scoring_evidence'] = evidenceMerge.evidence!.toJson();
    }
    return patch;
  }

  static String? _resolve(String? value) {
    final v = value?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static bool _isEmpty(String value) => value.trim().isEmpty;

  /// Returns a single-entry map `{key: value}` when value is non-null,
  /// or null otherwise — for use with the `...?` spread operator.
  static Map<String, dynamic>? _entry(String key, String? value) =>
      value != null ? {key: value} : null;
}

void _debugSubmissionApprovalLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
