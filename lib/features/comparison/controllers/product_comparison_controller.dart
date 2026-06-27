import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/repositories/product_comparison_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

@immutable
class ComparisonPickerConfig {
  const ComparisonPickerConfig({required this.sourceProduct});

  final Product sourceProduct;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComparisonPickerConfig &&
            runtimeType == other.runtimeType &&
            sourceProduct.id == other.sourceProduct.id;
  }

  @override
  int get hashCode => sourceProduct.id.hashCode;
}

class ComparisonPickerState {
  const ComparisonPickerState({
    required this.sourceProduct,
    this.candidates = const <Product>[],
    this.isLoading = true,
    this.error,
    this.searchQuery = '',
    this.selectedProduct,
    this.requestGeneration = 0,
  });

  final Product sourceProduct;
  final List<Product> candidates;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final Product? selectedProduct;
  final int requestGeneration;

  bool get usesCategoryOverlap =>
      sourceProduct.categoryTags
          ?.map((tag) => tag.trim())
          .any((tag) => tag.isNotEmpty) ==
      true;

  ComparisonPickerState copyWith({
    List<Product>? candidates,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    Product? selectedProduct,
    bool clearSelectedProduct = false,
    int? requestGeneration,
  }) {
    return ComparisonPickerState(
      sourceProduct: sourceProduct,
      candidates: candidates ?? this.candidates,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProduct: clearSelectedProduct
          ? null
          : (selectedProduct ?? this.selectedProduct),
      requestGeneration: requestGeneration ?? this.requestGeneration,
    );
  }
}

class ComparisonPickerController extends StateNotifier<ComparisonPickerState> {
  ComparisonPickerController({
    required ProductComparisonRepository repository,
    required Product sourceProduct,
  }) : _repository = repository,
       super(ComparisonPickerState(sourceProduct: sourceProduct)) {
    _loadCandidates();
  }

  final ProductComparisonRepository _repository;
  Timer? _debounce;

  static const _debounceDuration = Duration(milliseconds: 320);

  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value, clearError: true);
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _loadCandidates);
  }

  Future<void> retry() => _loadCandidates();

  bool selectCandidate(Product product) {
    if (product.id == state.sourceProduct.id) return false;
    state = state.copyWith(selectedProduct: product);
    return true;
  }

  Future<void> _loadCandidates() async {
    final generation = state.requestGeneration + 1;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      requestGeneration: generation,
      clearSelectedProduct: true,
    );

    try {
      final products = await _repository.findComparisonCandidates(
        source: state.sourceProduct,
        query: state.searchQuery,
      );
      if (!mounted || generation != state.requestGeneration) return;

      state = state.copyWith(
        isLoading: false,
        candidates: List<Product>.unmodifiable(products),
      );
    } catch (_) {
      if (!mounted || generation != state.requestGeneration) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Ürünler yüklenemedi. Tekrar dene.',
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final comparisonPickerControllerProvider = StateNotifierProvider.autoDispose
    .family<
      ComparisonPickerController,
      ComparisonPickerState,
      ComparisonPickerConfig
    >(
      (ref, config) => ComparisonPickerController(
        repository: ref.watch(productComparisonRepositoryProvider),
        sourceProduct: config.sourceProduct,
      ),
    );

@immutable
class ProductComparisonConfig {
  const ProductComparisonConfig({
    required this.sourceProduct,
    required this.comparedProduct,
  });

  final Product sourceProduct;
  final Product comparedProduct;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProductComparisonConfig &&
            runtimeType == other.runtimeType &&
            sourceProduct.id == other.sourceProduct.id &&
            comparedProduct.id == other.comparedProduct.id;
  }

  @override
  int get hashCode => Object.hash(sourceProduct.id, comparedProduct.id);
}

class ProductComparisonState {
  const ProductComparisonState({
    required this.sourceProduct,
    required this.comparedProduct,
    this.comparison,
    this.isLoading = true,
    this.error,
    this.requestGeneration = 0,
  });

  final Product sourceProduct;
  final Product comparedProduct;
  final ProductComparison? comparison;
  final bool isLoading;
  final String? error;
  final int requestGeneration;

  ProductComparisonState copyWith({
    Product? sourceProduct,
    Product? comparedProduct,
    ProductComparison? comparison,
    bool clearComparison = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    int? requestGeneration,
  }) {
    return ProductComparisonState(
      sourceProduct: sourceProduct ?? this.sourceProduct,
      comparedProduct: comparedProduct ?? this.comparedProduct,
      comparison: clearComparison ? null : (comparison ?? this.comparison),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      requestGeneration: requestGeneration ?? this.requestGeneration,
    );
  }
}

class ProductComparisonController
    extends StateNotifier<ProductComparisonState> {
  ProductComparisonController({
    required ProductComparisonRepository repository,
    required Product sourceProduct,
    required Product comparedProduct,
  }) : _repository = repository,
       super(
         ProductComparisonState(
           sourceProduct: sourceProduct,
           comparedProduct: comparedProduct,
         ),
       ) {
    _loadComparison();
  }

  final ProductComparisonRepository _repository;

  Future<void> retry() => _loadComparison();

  Future<void> changeComparedProduct(Product product) async {
    if (product.id == state.sourceProduct.id ||
        product.id == state.comparedProduct.id) {
      return;
    }

    final generation = state.requestGeneration + 1;
    state = state.copyWith(
      comparedProduct: product,
      isLoading: true,
      clearError: true,
      requestGeneration: generation,
    );

    await _loadComparison(generation: generation);
  }

  Future<void> _loadComparison({int? generation}) async {
    final currentGeneration = generation ?? state.requestGeneration + 1;
    if (generation == null) {
      state = state.copyWith(
        isLoading: true,
        clearError: true,
        requestGeneration: currentGeneration,
      );
    }

    try {
      final comparison = await _repository.createComparison(
        productA: state.sourceProduct,
        productB: state.comparedProduct,
      );
      if (!mounted || currentGeneration != state.requestGeneration) return;

      state = state.copyWith(comparison: comparison, isLoading: false);
    } catch (_) {
      if (!mounted || currentGeneration != state.requestGeneration) return;

      state = state.copyWith(
        isLoading: false,
        error: 'Ürünler yüklenemedi. Tekrar dene.',
      );
    }
  }
}

final productComparisonControllerProvider = StateNotifierProvider.autoDispose
    .family<
      ProductComparisonController,
      ProductComparisonState,
      ProductComparisonConfig
    >(
      (ref, config) => ProductComparisonController(
        repository: ref.watch(productComparisonRepositoryProvider),
        sourceProduct: config.sourceProduct,
        comparedProduct: config.comparedProduct,
      ),
    );
