import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

final productSubmissionApprovalRepositoryProvider = Provider(
  (_) => const ProductSubmissionApprovalRepository(),
);

class ProductSubmissionReviewState {
  final AsyncValue<List<ProductSubmission>> submissions;
  final bool isProcessing;
  final String? error;

  const ProductSubmissionReviewState({
    this.submissions = const AsyncValue.loading(),
    this.isProcessing = false,
    this.error,
  });

  ProductSubmissionReviewState copyWith({
    AsyncValue<List<ProductSubmission>>? submissions,
    bool? isProcessing,
    String? error,
    bool clearError = false,
  }) {
    return ProductSubmissionReviewState(
      submissions: submissions ?? this.submissions,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProductSubmissionReviewNotifier
    extends StateNotifier<ProductSubmissionReviewState> {
  final ProductSubmissionApprovalRepository _repo;

  ProductSubmissionReviewNotifier(this._repo)
    : super(const ProductSubmissionReviewState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(
      submissions: const AsyncValue.loading(),
      clearError: true,
    );
    try {
      final list = await _repo.fetchPendingSubmissions();
      state = state.copyWith(submissions: AsyncValue.data(list));
    } catch (e, st) {
      state = state.copyWith(submissions: AsyncValue.error(e, st));
    }
  }

  /// Approve a pending submission, optionally with admin-edited fields.
  ///
  /// Returns the [ApproveProductResult] so the UI can show the right message.
  Future<ApproveProductResult?> approve(
    String submissionId, {
    String? editedProductName,
    String? editedBrand,
    String? editedIngredientsText,
  }) async {
    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final result = await _repo.approveProductSubmission(
        submissionId,
        editedProductName: editedProductName,
        editedBrand: editedBrand,
        editedIngredientsText: editedIngredientsText,
      );
      _removeFromList(submissionId);
      state = state.copyWith(isProcessing: false);
      return result;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  /// Reject a pending submission with an optional reason.
  Future<bool> reject(String submissionId, {String? reason}) async {
    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      await _repo.rejectProductSubmission(submissionId, reason: reason);
      _removeFromList(submissionId);
      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  void _removeFromList(String submissionId) {
    final current = state.submissions.valueOrNull ?? [];
    state = state.copyWith(
      submissions: AsyncValue.data(
        current.where((s) => s.id != submissionId).toList(),
      ),
    );
  }
}

final productSubmissionReviewProvider =
    StateNotifierProvider<
      ProductSubmissionReviewNotifier,
      ProductSubmissionReviewState
    >(
      (ref) => ProductSubmissionReviewNotifier(
        ref.watch(productSubmissionApprovalRepositoryProvider),
      ),
    );
