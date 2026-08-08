import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_admin_review_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_presentation.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

const _nutritionFieldSpecs = <_NutritionFieldSpec>[
  _NutritionFieldSpec('energy_kj', 'Enerji', 'kJ'),
  _NutritionFieldSpec('energy_kcal', 'Enerji', 'kcal'),
  _NutritionFieldSpec('fat', 'Yağ', 'g'),
  _NutritionFieldSpec('saturated_fat', 'Doymuş Yağ', 'g'),
  _NutritionFieldSpec('carbohydrates', 'Karbonhidrat', 'g'),
  _NutritionFieldSpec('sugars', 'Şeker', 'g'),
  _NutritionFieldSpec('fiber', 'Lif', 'g'),
  _NutritionFieldSpec('proteins', 'Protein', 'g'),
  _NutritionFieldSpec('salt', 'Tuz', 'g'),
  _NutritionFieldSpec('sodium', 'Sodyum', 'g'),
];

class ProductSubmissionDetailPage extends ConsumerStatefulWidget {
  final String submissionId;
  final ProductSubmission? submission;

  const ProductSubmissionDetailPage({
    super.key,
    required this.submissionId,
    this.submission,
  });

  @override
  ConsumerState<ProductSubmissionDetailPage> createState() =>
      _ProductSubmissionDetailPageState();
}

class _ProductSubmissionDetailPageState
    extends ConsumerState<ProductSubmissionDetailPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _servingSizeController = TextEditingController();
  final _fvlPercentageController = TextEditingController();
  final _redMeatPercentageController = TextEditingController();
  final _nutSeedPercentageController = TextEditingController();
  late final Map<String, TextEditingController> _nutritionControllers = {
    for (final spec in _nutritionFieldSpecs) spec.key: TextEditingController(),
  };

  ProductSubmission? _resolved;
  bool _loaded = false;
  bool _populating = false;
  NutritionBasis _nutritionBasis = NutritionBasis.unknown;
  NutritionProductState _productState = NutritionProductState.unknown;
  IngredientEvidenceCompleteness _ingredientCompleteness =
      IngredientEvidenceCompleteness.unknown;
  CompositionPercentageState _fvlState = CompositionPercentageState.unknown;
  PresenceEvidenceState _nnsState = PresenceEvidenceState.unknown;
  ScoringCategory _scoringCategory = ScoringCategory.unknown;
  bool? _isPlainWater;
  bool? _redMeatIsPrimaryIngredient;
  bool? _isPlantBasedCheeseAlternative;
  bool? _isCompoundProduct;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _ingredientsController,
      _fvlPercentageController,
      _redMeatPercentageController,
      _nutSeedPercentageController,
      ..._nutritionControllers.values,
    ]) {
      controller.addListener(_refreshEvidencePreview);
    }
    _resolve();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _ingredientsController.dispose();
    _servingSizeController.dispose();
    _fvlPercentageController.dispose();
    _redMeatPercentageController.dispose();
    _nutSeedPercentageController.dispose();
    for (final controller in _nutritionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _resolve() {
    // Try from passed extra first, then from loaded list.
    final fromExtra = widget.submission;
    final fromList = ref
        .read(productSubmissionReviewProvider)
        .submissions
        .valueOrNull
        ?.where((s) => s.id == widget.submissionId)
        .firstOrNull;

    final resolved = fromExtra ?? fromList;
    if (resolved != null) {
      _populate(resolved);
    } else {
      // Fetch directly (deep link / page refresh).
      _fetchFromDb();
    }
  }

  Future<void> _fetchFromDb() async {
    final sub = await ref
        .read(productSubmissionApprovalRepositoryProvider)
        .fetchById(widget.submissionId);
    if (!mounted) return;
    if (sub != null) _populate(sub);
    setState(() => _loaded = true);
  }

  void _populate(ProductSubmission sub) {
    _populating = true;
    _resolved = sub;
    _nameController.text = sub.productName ?? '';
    _brandController.text = sub.brand ?? '';
    _ingredientsController.text = sub.extractedIngredientsText ?? '';
    final nutrition = normalizeNutritionMap(sub.extractedNutrition);
    for (final spec in _nutritionFieldSpecs) {
      _nutritionControllers[spec.key]!.text = _formatNutritionValue(
        nutrition?[spec.key],
      );
    }
    _servingSizeController.text = nutrition?['serving_size']?.toString() ?? '';
    final evidence = sub.scoringEvidence;
    _nutritionBasis =
        evidence?.nutritionBasisEvidence?.value ??
        evidence?.nutritionBasis ??
        NutritionBasis.unknown;
    _productState =
        evidence?.nutritionProductStateEvidence?.value ??
        evidence?.nutritionProductState ??
        NutritionProductState.unknown;
    _ingredientCompleteness =
        evidence?.ingredientEvidenceCompleteness ??
        IngredientEvidenceCompleteness.unknown;
    _fvlState =
        evidence?.fvlEvidence.state ?? CompositionPercentageState.unknown;
    _fvlPercentageController.text = _formatNutritionValue(
      evidence?.fvlEvidence.percentage,
    );
    _nnsState = evidence?.nnsEvidence.state ?? PresenceEvidenceState.unknown;
    _scoringCategory =
        evidence?.categoryEvidence.resolvedCategory ?? ScoringCategory.unknown;
    final facts = evidence?.classificationFacts;
    _isPlainWater = facts?.isPlainWater?.value;
    _redMeatPercentageController.text = _formatNutritionValue(
      facts?.redMeatPercentage?.value,
    );
    _redMeatIsPrimaryIngredient = facts?.redMeatIsPrimaryIngredient?.value;
    _nutSeedPercentageController.text = _formatNutritionValue(
      facts?.nutSeedPercentage?.value,
    );
    _isPlantBasedCheeseAlternative =
        facts?.isPlantBasedCheeseAlternative?.value;
    _isCompoundProduct = facts?.isCompoundProduct?.value;
    _loaded = true;
    _populating = false;
  }

  void _refreshEvidencePreview() {
    if (mounted && !_populating) setState(() {});
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final nutritionDraft = _readNutritionDraft();
    if (nutritionDraft.invalidLabel != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${nutritionDraft.invalidLabel} için sıfır veya daha büyük sayısal bir değer girin.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final review = _buildScoringEvidenceReview(nutritionDraft.nutrition);
    if (!_showReviewValidation(review)) return;

    List<ScoringEvidenceConflict> conflicts;
    try {
      conflicts = await ref
          .read(productSubmissionApprovalRepositoryProvider)
          .previewScoringEvidenceConflicts(
            barcode: _resolved!.barcode,
            reviewedNutrition: nutritionDraft.nutrition,
            incomingEvidence: review.evidence,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserMessage.forGeneric(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    final conflictText = conflicts.isEmpty
        ? ''
        : '\n\nMevcut üründeki daha güvenilir veriler korunacak:\n${conflicts.map(_conflictLabel).map((label) => '• $label').join('\n')}';

    final confirmed = await _confirmDialog(
      title: 'Ürünü Onayla',
      content:
          'Bu gönderi onaylanacak ve ürün veritabanına eklenecek.$conflictText',
      actionLabel: 'Onayla',
      actionColor: Colors.green,
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(productSubmissionReviewProvider.notifier)
        .approve(
          widget.submissionId,
          editedProductName: _nameController.text.trim(),
          editedBrand: _brandController.text.trim(),
          editedIngredientsText: _ingredientsController.text.trim(),
          editedNutrition: nutritionDraft.nutrition,
          nutritionWasReviewed: true,
          reviewedScoringEvidence: review.evidence,
        );

    if (!mounted) return;

    if (result != null) {
      final msg = switch (result) {
        ApproveProductResult.approved => 'Ürün veritabanına eklendi.',
        ApproveProductResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        _ => 'İşlem tamamlandı.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(productSubmissionReviewProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error == null ? UserMessage.generic : UserMessage.forGeneric(error),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _saveScoringEvidence() async {
    final nutritionDraft = _readNutritionDraft();
    if (nutritionDraft.invalidLabel != null) {
      _showInvalidNutrition(nutritionDraft.invalidLabel!);
      return;
    }
    final review = _buildScoringEvidenceReview(nutritionDraft.nutrition);
    if (!_showReviewValidation(review)) return;
    final saved = await ref
        .read(productSubmissionReviewProvider.notifier)
        .saveScoringEvidenceReview(
          widget.submissionId,
          reviewedNutrition: nutritionDraft.nutrition,
          evidence: review.evidence,
        );
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(productSubmissionReviewProvider).error ??
                UserMessage.generic,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    ProductSubmission? refreshed;
    try {
      refreshed = await ref
          .read(productSubmissionApprovalRepositoryProvider)
          .fetchById(widget.submissionId);
    } catch (_) {
      refreshed = null;
    }
    if (!mounted) return;
    if (refreshed != null) _populate(refreshed);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Puanlama verisi kaydedildi.')),
    );
  }

  ScoringEvidenceAdminReviewResult _buildScoringEvidenceReview(
    Map<String, dynamic>? nutrition,
  ) {
    return const ScoringEvidenceAdminReviewService().build(
      ScoringEvidenceAdminDraft(
        reviewedNutrition: nutrition,
        ingredientText: _ingredientsController.text,
        nutritionBasis: _nutritionBasis,
        productState: _productState,
        ingredientCompleteness: _ingredientCompleteness,
        fvlState: _fvlState,
        fvlPercentage: _readOptionalAdminNumber(_fvlPercentageController),
        nnsState: _nnsState,
        category: _scoringCategory,
        isPlainWater: _isPlainWater,
        redMeatPercentage: _readOptionalAdminNumber(
          _redMeatPercentageController,
        ),
        redMeatIsPrimaryIngredient: _redMeatIsPrimaryIngredient,
        nutSeedPercentage: _readOptionalAdminNumber(
          _nutSeedPercentageController,
        ),
        isPlantBasedCheeseAlternative: _isPlantBasedCheeseAlternative,
        isCompoundProduct: _isCompoundProduct,
        existingCandidate: _resolved?.scoringEvidence,
      ),
    );
  }

  bool _showReviewValidation(ScoringEvidenceAdminReviewResult review) {
    if (review.isValid) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(review.validationIssues.first),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return false;
  }

  void _showInvalidNutrition(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label için sıfır veya daha büyük sayısal bir değer girin.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  ({Map<String, dynamic>? nutrition, String? invalidLabel})
  _readNutritionDraft() {
    final values = <String, dynamic>{};
    for (final spec in _nutritionFieldSpecs) {
      final raw = _nutritionControllers[spec.key]!.text.trim();
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || !value.isFinite || value < 0) {
        return (nutrition: null, invalidLabel: spec.label);
      }
      values[spec.key] = value;
    }

    final servingSize = _servingSizeController.text.trim();
    if (servingSize.isNotEmpty) values['serving_size'] = servingSize;
    return (nutrition: normalizeNutritionMap(values), invalidLabel: null);
  }

  Future<void> _reject() async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Red sebebi (isteğe bağlı):'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Açıklama...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reddet', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(productSubmissionReviewProvider.notifier)
        .reject(
          widget.submissionId,
          reason: noteController.text.trim().isEmpty
              ? null
              : noteController.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gönderi reddedildi.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(productSubmissionReviewProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error == null ? UserMessage.generic : UserMessage.forGeneric(error),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String content,
    required String actionLabel,
    required Color actionColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel, style: TextStyle(color: actionColor)),
          ),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productSubmissionReviewProvider);
    final isBusy = state.isProcessing;

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gönderi Detayı')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolved == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gönderi Detayı')),
        body: const Center(child: Text('Gönderi bulunamadı.')),
      );
    }

    final sub = _resolved!;
    final previewNutrition = _readNutritionDraft();
    final evidenceReview = previewNutrition.invalidLabel == null
        ? _buildScoringEvidenceReview(previewNutrition.nutrition)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi Detayı')),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barcode (read-only)
                  _SectionLabel('Barkod'),
                  const SizedBox(height: 6),
                  _ReadOnlyField(sub.barcode),
                  const SizedBox(height: 16),

                  // OCR helper notice
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'OCR sonucu otomatik çıkarılmıştır. '
                      'Onaylamadan önce kontrol edip düzeltebilirsiniz.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable product name
                  _SectionLabel('Ürün Adı'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Ürün adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable brand
                  _SectionLabel('Marka'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _brandController,
                    decoration: const InputDecoration(
                      hintText: 'Marka',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable ingredients
                  _SectionLabel('İçindekiler (OCR)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _ingredientsController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Çıkarılan içerik metni...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionLabel('Besin Değerleri'),
                  const SizedBox(height: 2),
                  Text(
                    '100 g / 100 ml başına',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (normalizeNutritionMap(sub.extractedNutrition) ==
                      null) ...[
                    const _MissingNutritionNotice(),
                    const SizedBox(height: 8),
                  ],
                  _NutritionEditorCard(
                    controllers: _nutritionControllers,
                    servingSizeController: _servingSizeController,
                  ),
                  const SizedBox(height: 16),

                  _ScoringEvidenceReviewCard(
                    evidence: sub.scoringEvidence,
                    review: evidenceReview,
                    nutritionBasis: _nutritionBasis,
                    onNutritionBasisChanged: (value) {
                      setState(() => _nutritionBasis = value);
                    },
                    productState: _productState,
                    onProductStateChanged: (value) {
                      setState(() => _productState = value);
                    },
                    ingredientCompleteness: _ingredientCompleteness,
                    onIngredientCompletenessChanged: (value) {
                      setState(() => _ingredientCompleteness = value);
                    },
                    fvlState: _fvlState,
                    onFvlStateChanged: (value) {
                      setState(() => _fvlState = value);
                    },
                    fvlPercentageController: _fvlPercentageController,
                    nnsState: _nnsState,
                    onNnsStateChanged: (value) {
                      setState(() => _nnsState = value);
                    },
                    scoringCategory: _scoringCategory,
                    onScoringCategoryChanged: (value) {
                      setState(() => _scoringCategory = value);
                    },
                    isPlainWater: _isPlainWater,
                    onPlainWaterChanged: (value) {
                      setState(() => _isPlainWater = value);
                    },
                    redMeatPercentageController: _redMeatPercentageController,
                    redMeatIsPrimaryIngredient: _redMeatIsPrimaryIngredient,
                    onRedMeatPrimaryChanged: (value) {
                      setState(() => _redMeatIsPrimaryIngredient = value);
                    },
                    nutSeedPercentageController: _nutSeedPercentageController,
                    isPlantBasedCheeseAlternative:
                        _isPlantBasedCheeseAlternative,
                    onPlantAlternativeChanged: (value) {
                      setState(() => _isPlantBasedCheeseAlternative = value);
                    },
                    isCompoundProduct: _isCompoundProduct,
                    onCompoundProductChanged: (value) {
                      setState(() => _isCompoundProduct = value);
                    },
                    onSave: _saveScoringEvidence,
                  ),
                  const SizedBox(height: 16),

                  // Extraction status
                  _ExtractionStatusCard(
                    status: sub.extractionStatus,
                    error: sub.extractionError,
                  ),
                  const SizedBox(height: 16),

                  // Front image
                  if (sub.frontImageUrl != null) ...[
                    _SectionLabel('Ön Görsel'),
                    const SizedBox(height: 8),
                    _ImageCard(
                      key: const ValueKey('submission-front-image'),
                      url: sub.frontImageUrl!,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Label image
                  if (sub.labelImageUrl != null) ...[
                    _SectionLabel('Etiket Görseli'),
                    const SizedBox(height: 8),
                    _ImageCard(
                      key: const ValueKey('submission-label-image'),
                      url: sub.labelImageUrl!,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (sub.nutritionImageUrl != null) ...[
                    _SectionLabel('Besin Değeri Görseli'),
                    const SizedBox(height: 8),
                    _ImageCard(
                      key: const ValueKey('submission-nutrition-image'),
                      url: sub.nutritionImageUrl!,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: isBusy
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Onayla'),
                      onPressed: _approve,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Reddet'),
                      onPressed: _reject,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String value;
  const _ReadOnlyField(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _NutritionFieldSpec {
  final String key;
  final String label;
  final String unit;

  const _NutritionFieldSpec(this.key, this.label, this.unit);
}

String _formatNutritionValue(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '';
  final number = value.toDouble();
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toString();
}

double? _readOptionalAdminNumber(TextEditingController controller) {
  final raw = controller.text.trim();
  if (raw.isEmpty) return null;
  return double.tryParse(raw.replaceAll(',', '.')) ?? double.nan;
}

String _nutritionBasisLabel(NutritionBasis value) => switch (value) {
  NutritionBasis.per100g => '100 g başına',
  NutritionBasis.per100ml => '100 ml başına',
  NutritionBasis.perServing => 'Porsiyon başına',
  NutritionBasis.unknown => 'Bilinmiyor',
};

String _productStateLabel(NutritionProductState value) => switch (value) {
  NutritionProductState.asSold => 'Satıldığı haliyle',
  NutritionProductState.asPrepared => 'Hazırlanmış haliyle',
  NutritionProductState.unknown => 'Bilinmiyor',
};

String _ingredientCompletenessLabel(IngredientEvidenceCompleteness value) =>
    switch (value) {
      IngredientEvidenceCompleteness.complete => 'Tam ve okunabilir',
      IngredientEvidenceCompleteness.incomplete => 'Eksik / kısmi',
      IngredientEvidenceCompleteness.unknown => 'Bilinmiyor',
    };

String _fvlStateLabel(CompositionPercentageState value) => switch (value) {
  CompositionPercentageState.known => 'Bilinen oran',
  CompositionPercentageState.provenAbsent => 'Yokluğu doğrulandı',
  CompositionPercentageState.unknown => 'Bilinmiyor',
};

String _nnsStateLabel(PresenceEvidenceState value) => switch (value) {
  PresenceEvidenceState.present => 'Var',
  PresenceEvidenceState.absent => 'Yokluğu doğrulandı',
  PresenceEvidenceState.unknown => 'Bilinmiyor',
};

String _scoringCategoryLabel(ScoringCategory value) => switch (value) {
  ScoringCategory.generalFood => 'Genel gıda',
  ScoringCategory.cheese => 'Peynir',
  ScoringCategory.redMeat => 'Kırmızı et',
  ScoringCategory.fatsOilsNutsSeeds => 'Yağ / kuruyemiş / tohum',
  ScoringCategory.beverage => 'İçecek',
  ScoringCategory.outOfScope => 'Kapsam dışı',
  ScoringCategory.unknown => 'Bilinmiyor',
};

String _conflictLabel(ScoringEvidenceConflict conflict) {
  final field = conflict.field;
  if (field == 'nutrition_basis') return 'Besin değeri temeli çelişiyor.';
  if (field == 'nutrition_product_state') return 'Ürün hali çelişiyor.';
  if (field == 'fvl_evidence') return 'FVL kanıtı çelişiyor.';
  if (field == 'nns_evidence') return 'Tatlandırıcı kanıtı çelişiyor.';
  if (field == 'category_evidence.resolved_category') {
    return 'Puanlama ürün sınıfı çelişiyor.';
  }
  if (field.startsWith('nutrition.')) {
    return 'Doğrulanmış bir besin değeri çelişiyor.';
  }
  if (field.startsWith('classification_facts.')) {
    return 'Ürün sınıflandırma bilgisi çelişiyor.';
  }
  return 'Puanlama kanıtlarından biri çelişiyor.';
}

class _MissingNutritionNotice extends StatelessWidget {
  const _MissingNutritionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('submission-missing-nutrition'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: const Text(
        'Besin değerleri otomatik olarak çıkarılamadı. Bilgileri manuel olarak kontrol edebilirsiniz.',
        style: TextStyle(color: AppColors.warningText, height: 1.35),
      ),
    );
  }
}

class _NutritionEditorCard extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final TextEditingController servingSizeController;

  const _NutritionEditorCard({
    required this.controllers,
    required this.servingSizeController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = (constraints.maxWidth - 10) / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final spec in _nutritionFieldSpecs)
                    SizedBox(
                      width: fieldWidth,
                      child: TextField(
                        key: ValueKey('submission-nutrition-${spec.key}'),
                        controller: controllers[spec.key],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: spec.label,
                          suffixText: spec.unit,
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.surface,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('submission-nutrition-serving-size'),
                controller: servingSizeController,
                decoration: const InputDecoration(
                  labelText: 'Porsiyon bilgisi (isteğe bağlı)',
                  hintText: 'Örn. 30 g',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScoringEvidenceReviewCard extends StatelessWidget {
  final ScoringEvidenceSnapshot? evidence;
  final ScoringEvidenceAdminReviewResult? review;
  final NutritionBasis nutritionBasis;
  final ValueChanged<NutritionBasis> onNutritionBasisChanged;
  final NutritionProductState productState;
  final ValueChanged<NutritionProductState> onProductStateChanged;
  final IngredientEvidenceCompleteness ingredientCompleteness;
  final ValueChanged<IngredientEvidenceCompleteness>
  onIngredientCompletenessChanged;
  final CompositionPercentageState fvlState;
  final ValueChanged<CompositionPercentageState> onFvlStateChanged;
  final TextEditingController fvlPercentageController;
  final PresenceEvidenceState nnsState;
  final ValueChanged<PresenceEvidenceState> onNnsStateChanged;
  final ScoringCategory scoringCategory;
  final ValueChanged<ScoringCategory> onScoringCategoryChanged;
  final bool? isPlainWater;
  final ValueChanged<bool?> onPlainWaterChanged;
  final TextEditingController redMeatPercentageController;
  final bool? redMeatIsPrimaryIngredient;
  final ValueChanged<bool?> onRedMeatPrimaryChanged;
  final TextEditingController nutSeedPercentageController;
  final bool? isPlantBasedCheeseAlternative;
  final ValueChanged<bool?> onPlantAlternativeChanged;
  final bool? isCompoundProduct;
  final ValueChanged<bool?> onCompoundProductChanged;
  final VoidCallback onSave;

  const _ScoringEvidenceReviewCard({
    required this.evidence,
    required this.review,
    required this.nutritionBasis,
    required this.onNutritionBasisChanged,
    required this.productState,
    required this.onProductStateChanged,
    required this.ingredientCompleteness,
    required this.onIngredientCompletenessChanged,
    required this.fvlState,
    required this.onFvlStateChanged,
    required this.fvlPercentageController,
    required this.nnsState,
    required this.onNnsStateChanged,
    required this.scoringCategory,
    required this.onScoringCategoryChanged,
    required this.isPlainWater,
    required this.onPlainWaterChanged,
    required this.redMeatPercentageController,
    required this.redMeatIsPrimaryIngredient,
    required this.onRedMeatPrimaryChanged,
    required this.nutSeedPercentageController,
    required this.isPlantBasedCheeseAlternative,
    required this.onPlantAlternativeChanged,
    required this.isCompoundProduct,
    required this.onCompoundProductChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = evidence?.ingredientPercentageCandidates ?? const [];
    final basisIsOcr =
        evidence?.nutritionBasisEvidence?.provenance ==
        EvidenceProvenance.ocrDeclaredLabel;
    final stateIsOcr =
        evidence?.nutritionProductStateEvidence?.provenance ==
        EvidenceProvenance.ocrDeclaredLabel;
    final blockers = review == null
        ? const ['Besin değerlerinden biri geçersiz.']
        : ScoringReadinessPresentation.blockerLabels(review!.readiness);
    final isReady = review?.readiness.isScorable == true;

    return Container(
      key: const ValueKey('submission-scoring-evidence-section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Puanlama Verisi',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'OCR alanları taslaktır. Kaydetmeden önce etiketten doğrulayın.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          _ReviewDropdown<NutritionBasis>(
            fieldKey: 'scoring-basis',
            label: basisIsOcr
                ? 'Besin değeri temeli (OCR adayı)'
                : 'Besin değeri temeli',
            value: nutritionBasis,
            values: NutritionBasis.values,
            labelFor: _nutritionBasisLabel,
            onChanged: onNutritionBasisChanged,
          ),
          const SizedBox(height: 10),
          _ReviewDropdown<NutritionProductState>(
            fieldKey: 'scoring-product-state',
            label: stateIsOcr ? 'Ürün hali (OCR adayı)' : 'Ürün hali',
            value: productState,
            values: NutritionProductState.values,
            labelFor: _productStateLabel,
            onChanged: onProductStateChanged,
          ),
          const SizedBox(height: 10),
          _ReviewDropdown<IngredientEvidenceCompleteness>(
            fieldKey: 'scoring-ingredient-completeness',
            label: 'İçerik listesinin durumu',
            value: ingredientCompleteness,
            values: IngredientEvidenceCompleteness.values,
            labelFor: _ingredientCompletenessLabel,
            onChanged: onIngredientCompletenessChanged,
          ),
          const SizedBox(height: 10),
          _ReviewDropdown<CompositionPercentageState>(
            fieldKey: 'scoring-fvl-state',
            label: 'FVL kanıtı',
            value: fvlState,
            values: const [
              CompositionPercentageState.unknown,
              CompositionPercentageState.provenAbsent,
              CompositionPercentageState.known,
            ],
            labelFor: _fvlStateLabel,
            onChanged: onFvlStateChanged,
          ),
          if (fvlState == CompositionPercentageState.known) ...[
            const SizedBox(height: 10),
            _PercentageField(
              fieldKey: 'scoring-fvl-percentage',
              label: 'Doğrulanan FVL oranı',
              controller: fvlPercentageController,
            ),
          ],
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Etikette görülen oran adayları',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final candidate in candidates)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${candidate.ingredientText}: %${_formatNutritionValue(candidate.percentage)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Text(
              'Bu adaylar FVL oranını otomatik belirlemez.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          _ReviewDropdown<PresenceEvidenceState>(
            fieldKey: 'scoring-nns-state',
            label: 'NNS tatlandırıcı durumu',
            value: nnsState,
            values: const [
              PresenceEvidenceState.unknown,
              PresenceEvidenceState.present,
              PresenceEvidenceState.absent,
            ],
            labelFor: _nnsStateLabel,
            onChanged: onNnsStateChanged,
          ),
          const SizedBox(height: 10),
          _ReviewDropdown<ScoringCategory>(
            fieldKey: 'scoring-category',
            label: 'Puanlama ürün sınıfı',
            value: scoringCategory,
            values: ScoringCategory.values,
            labelFor: _scoringCategoryLabel,
            onChanged: onScoringCategoryChanged,
          ),
          ..._categoryFactFields(context),
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('submission-scoring-readiness-preview'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isReady ? Colors.green : Colors.orange).withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isReady ? Colors.green : Colors.orange).withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Puanlama için veri durumu: ${isReady ? 'Hazır' : 'Eksik veri var'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!isReady) ...[
                  const SizedBox(height: 6),
                  for (final blocker in blockers.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $blocker'),
                    ),
                ],
              ],
            ),
          ),
          if (review?.validationIssues.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            for (final issue in review!.validationIssues)
              Text(
                issue,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('save-scoring-evidence-review'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Puanlama Verisini Kaydet'),
          ),
        ],
      ),
    );
  }

  List<Widget> _categoryFactFields(BuildContext context) {
    switch (scoringCategory) {
      case ScoringCategory.redMeat:
        return [
          const SizedBox(height: 10),
          _PercentageField(
            fieldKey: 'scoring-red-meat-percentage',
            label: 'Kırmızı et oranı',
            controller: redMeatPercentageController,
          ),
          const SizedBox(height: 10),
          _TriStateReviewDropdown(
            fieldKey: 'scoring-red-meat-primary',
            label: 'Kırmızı et ana bileşen mi?',
            value: redMeatIsPrimaryIngredient,
            onChanged: onRedMeatPrimaryChanged,
          ),
        ];
      case ScoringCategory.fatsOilsNutsSeeds:
        return [
          const SizedBox(height: 10),
          _PercentageField(
            fieldKey: 'scoring-nut-seed-percentage',
            label: 'Kuruyemiş / tohum oranı (uygunsa)',
            controller: nutSeedPercentageController,
          ),
        ];
      case ScoringCategory.beverage:
        return [
          const SizedBox(height: 10),
          _TriStateReviewDropdown(
            fieldKey: 'scoring-plain-water',
            label: 'Sade su mu?',
            value: isPlainWater,
            onChanged: onPlainWaterChanged,
          ),
        ];
      case ScoringCategory.cheese:
        return [
          const SizedBox(height: 10),
          _TriStateReviewDropdown(
            fieldKey: 'scoring-cheese-plant-alternative',
            label: 'Bitkisel peynir alternatifi mi?',
            value: isPlantBasedCheeseAlternative,
            onChanged: onPlantAlternativeChanged,
          ),
          const SizedBox(height: 10),
          _TriStateReviewDropdown(
            fieldKey: 'scoring-cheese-compound',
            label: 'Bileşik ürün mü?',
            value: isCompoundProduct,
            onChanged: onCompoundProductChanged,
          ),
        ];
      case ScoringCategory.generalFood:
      case ScoringCategory.unknown:
      case ScoringCategory.outOfScope:
        return const [];
    }
  }
}

class _ReviewDropdown<T> extends StatelessWidget {
  final String fieldKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const _ReviewDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$fieldKey-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(labelFor(item))),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class _TriStateReviewDropdown extends StatelessWidget {
  final String fieldKey;
  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _TriStateReviewDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == null ? 'unknown' : (value! ? 'yes' : 'no');
    return DropdownButtonFormField<String>(
      key: ValueKey('$fieldKey-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        border: const OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'unknown', child: Text('Bilinmiyor')),
        DropdownMenuItem(value: 'yes', child: Text('Evet')),
        DropdownMenuItem(value: 'no', child: Text('Hayır')),
      ],
      onChanged: (choice) => onChanged(switch (choice) {
        'yes' => true,
        'no' => false,
        _ => null,
      }),
    );
  }
}

class _PercentageField extends StatelessWidget {
  final String fieldKey;
  final String label;
  final TextEditingController controller;

  const _PercentageField({
    required this.fieldKey,
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey(fieldKey),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ExtractionStatusCard extends StatelessWidget {
  final String status;
  final String? error;
  const _ExtractionStatusCard({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'success' => ('OCR başarılı', Colors.green),
      'failed' => ('OCR başarısız', Colors.red),
      'pending' => ('Otomatik okuma devam ediyor.', Colors.orange),
      _ => ('Otomatik okuma yapılmadı.', Colors.grey),
    };

    // Only show the error message when extraction actually failed.
    // A successful re-extraction may leave a stale error string in the DB;
    // displaying it alongside "OCR başarılı" would be misleading.
    final showError = status == 'failed';
    final errorMessage = showError ? UserMessage.forSubmissionOcr(error) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Çıkarma Durumu: $label',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 13,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              errorMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red[700]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String url;
  const _ImageCard({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (_, _, _) => Container(
          height: 120,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: Text('Görsel yüklenemedi.')),
        ),
      ),
    );
  }
}
