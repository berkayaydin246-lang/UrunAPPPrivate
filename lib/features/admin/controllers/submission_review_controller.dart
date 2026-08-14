import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/models/user_submission.dart';
import 'package:food_analyzer_app/features/admin/repositories/submission_review_repository.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_draft_repository.dart';

final submissionReviewRepositoryProvider = Provider(
  (_) => const SubmissionReviewRepository(),
);

final productDraftRepositoryProvider = Provider(
  (_) => const ProductDraftRepository(),
);

class SubmissionReviewState {
  final AsyncValue<List<UserSubmission>> submissions;
  final bool isUpdating;
  final String? updateError;
  final bool isDraftCreating;
  final String? draftCreateError;

  const SubmissionReviewState({
    this.submissions = const AsyncValue.loading(),
    this.isUpdating = false,
    this.updateError,
    this.isDraftCreating = false,
    this.draftCreateError,
  });

  SubmissionReviewState copyWith({
    AsyncValue<List<UserSubmission>>? submissions,
    bool? isUpdating,
    String? updateError,
    bool clearUpdateError = false,
    bool? isDraftCreating,
    String? draftCreateError,
    bool clearDraftCreateError = false,
  }) {
    return SubmissionReviewState(
      submissions: submissions ?? this.submissions,
      isUpdating: isUpdating ?? this.isUpdating,
      updateError: clearUpdateError ? null : (updateError ?? this.updateError),
      isDraftCreating: isDraftCreating ?? this.isDraftCreating,
      draftCreateError: clearDraftCreateError
          ? null
          : (draftCreateError ?? this.draftCreateError),
    );
  }
}

class SubmissionReviewNotifier extends StateNotifier<SubmissionReviewState> {
  final SubmissionReviewRepository _repo;
  final ProductDraftRepository _draftRepo;

  SubmissionReviewNotifier(this._repo, this._draftRepo)
    : super(const SubmissionReviewState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(
      submissions: const AsyncValue.loading(),
      clearUpdateError: true,
      clearDraftCreateError: true,
    );
    try {
      final list = await _repo.fetchPendingSubmissions();
      state = state.copyWith(submissions: AsyncValue.data(list));
    } catch (e, st) {
      state = state.copyWith(submissions: AsyncValue.error(e, st));
    }
  }

  Future<bool> updateStatus(
    String id,
    String newStatus, {
    String? adminNote,
  }) async {
    state = state.copyWith(isUpdating: true, clearUpdateError: true);
    try {
      await _repo.updateStatus(id, newStatus, adminNote: adminNote);
      final current = state.submissions.valueOrNull ?? [];
      final updated = current.where((s) => s.id != id).toList();
      state = state.copyWith(
        submissions: AsyncValue.data(updated),
        isUpdating: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isUpdating: false, updateError: e.toString());
      return false;
    }
  }

  /// Creates a pending product draft from a user submission.
  ///
  /// Returns the new product UUID on success, or null on failure.
  /// On duplicate barcode, sets [draftCreateError] to a user-friendly message.
  Future<String?> createProductDraft(UserSubmission submission) async {
    state = state.copyWith(isDraftCreating: true, clearDraftCreateError: true);
    try {
      final result = await _draftRepo.createDraftFromSubmission(submission);
      state = state.copyWith(isDraftCreating: false);
      return result.productId;
    } on DuplicateBarcodeException {
      state = state.copyWith(
        isDraftCreating: false,
        draftCreateError: 'Bu barkoda sahip ürün zaten mevcut.',
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isDraftCreating: false,
        draftCreateError: 'Ürün taslağı oluşturulamadı: $e',
      );
      return null;
    }
  }
}

final submissionReviewProvider =
    StateNotifierProvider<SubmissionReviewNotifier, SubmissionReviewState>(
      (ref) => SubmissionReviewNotifier(
        ref.watch(submissionReviewRepositoryProvider),
        ref.watch(productDraftRepositoryProvider),
      ),
    );
