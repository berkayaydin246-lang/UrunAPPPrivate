import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
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

    // Resolve final field values: admin edits > extracted > fallback.
    final productName =
        _resolve(editedProductName) ??
        _resolve(submission.productName) ??
        'İsimsiz Ürün';
    final brand = _resolve(editedBrand) ?? _resolve(submission.brand);
    final ingredientsText =
        _resolve(editedIngredientsText) ??
        _resolve(submission.extractedIngredientsText);
    final nutritionText = submission.extractedNutrition != null
        ? jsonEncode(submission.extractedNutrition)
        : null;
    final imageUrl =
        _resolve(submission.frontImageUrl) ?? _resolve(submission.imageUrl);

    _debugSubmissionApprovalLog(
      '[Approval] resolved fields — name=$productName brand=$brand '
      'ingredientsText=${ingredientsText != null} nutritionText=${nutritionText != null}',
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
      await client.from('products').insert({
        'barcode': barcode,
        'name': productName,
        'source': 'user_submission',
        'verification_status': 'user_submitted',
        ...?_entry('brand', brand),
        ...?_entry('image_url', imageUrl),
        ...?_entry('ingredients_text', ingredientsText),
        ...?_entry('nutrition_text', nutritionText),
      });
      _debugSubmissionApprovalLog('[Approval] product insert succeeded');
      result = ApproveProductResult.approved;
    } else {
      // Enrich existing product — only fill null/empty fields.
      _debugSubmissionApprovalLog(
        '[Approval] existing product found — patching missing fields',
      );
      final existing = Product.fromJson(existingRow);
      final patch = <String, dynamic>{};

      if (_isEmpty(existing.name)) patch['name'] = productName;
      if (existing.brand == null) patch.addAll(_entry('brand', brand) ?? {});
      if (existing.imageUrl == null) {
        patch.addAll(_entry('image_url', imageUrl) ?? {});
      }
      if (existing.ingredientsText == null) {
        patch.addAll(_entry('ingredients_text', ingredientsText) ?? {});
      }
      if (existing.nutritionText == null) {
        patch.addAll(_entry('nutrition_text', nutritionText) ?? {});
      }

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
