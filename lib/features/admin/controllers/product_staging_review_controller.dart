import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_staging_approval_repository.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

final productStagingApprovalRepositoryProvider = Provider(
  (_) => const ProductStagingApprovalRepository(),
);

class ProductStagingReviewState {
  final AsyncValue<List<ProductCandidate>> candidates;
  final bool isProcessing;
  final String? error;

  const ProductStagingReviewState({
    this.candidates = const AsyncValue.loading(),
    this.isProcessing = false,
    this.error,
  });

  ProductStagingReviewState copyWith({
    AsyncValue<List<ProductCandidate>>? candidates,
    bool? isProcessing,
    String? error,
    bool clearError = false,
  }) {
    return ProductStagingReviewState(
      candidates: candidates ?? this.candidates,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProductStagingReviewNotifier
    extends StateNotifier<ProductStagingReviewState> {
  final ProductStagingApprovalRepository _repo;

  ProductStagingReviewNotifier(this._repo)
    : super(const ProductStagingReviewState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(
      candidates: const AsyncValue.loading(),
      clearError: true,
    );
    try {
      final list = await _repo.fetchPendingStagedProducts();
      state = state.copyWith(candidates: AsyncValue.data(list));
    } catch (e, st) {
      state = state.copyWith(candidates: AsyncValue.error(e, st));
    }
  }

  /// Approve a staged product, optionally with admin edits.
  /// Returns the result so the UI can show the right message.
  Future<ApproveStagedResult?> approve(
    String stagingId, {
    StagingApprovalEdits edits = const StagingApprovalEdits(),
  }) async {
    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final result = await _repo.approveStagedProduct(stagingId, edits: edits);
      // Only drop the row from the queue when staging was actually marked
      // approved. If the staging update failed (productSavedStagingFailed), the
      // row is still pending and must remain visible.
      if (result.stagingWasApproved) {
        _removeFromList(stagingId);
      }
      state = state.copyWith(isProcessing: false);
      return result;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<bool> reject(String stagingId, String reason) async {
    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      await _repo.rejectStagedProduct(stagingId, reason);
      _removeFromList(stagingId);
      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  Future<bool> markNeedsReview(String stagingId, String note) async {
    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      await _repo.markStagedProductNeedsReview(stagingId, note);
      // needs_review items remain in the queue, so reload rather than remove.
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  void _removeFromList(String stagingId) {
    final current = state.candidates.valueOrNull ?? [];
    state = state.copyWith(
      candidates: AsyncValue.data(
        current.where((c) => c.id != stagingId).toList(),
      ),
    );
  }
}

final productStagingReviewProvider =
    StateNotifierProvider<
      ProductStagingReviewNotifier,
      ProductStagingReviewState
    >((ref) {
      return ProductStagingReviewNotifier(
        ref.watch(productStagingApprovalRepositoryProvider),
      );
    });
