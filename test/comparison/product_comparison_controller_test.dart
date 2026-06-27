import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/comparison/controllers/product_comparison_controller.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/repositories/product_comparison_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

void main() {
  group('ComparisonPickerController', () {
    test('loads initial candidates', () async {
      final source = _product(id: 'source', name: 'Kaynak Cips');
      final candidate = _product(id: 'candidate', name: 'Rakip Cips');
      final repository = _FakeComparisonRepository(
        findHandler: ({required source, query, limit = 40}) async => [
          candidate,
        ],
      );
      final controller = ComparisonPickerController(
        repository: repository,
        sourceProduct: source,
      );
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.candidates, [candidate]);
      expect(repository.findCalls.single.query, '');
    });

    test(
      'search debounce ignores stale responses from older requests',
      () async {
        final source = _product(id: 'source', name: 'Kaynak İçecek');
        final colaCompleter = Completer<List<Product>>();
        final zeroCompleter = Completer<List<Product>>();
        final repository = _FakeComparisonRepository(
          findHandler: ({required source, query, limit = 40}) {
            final normalized = query?.trim() ?? '';
            if (normalized.isEmpty) {
              return Future<List<Product>>.value(const <Product>[]);
            }
            if (normalized == 'cola') {
              return colaCompleter.future;
            }
            if (normalized == 'zero') {
              return zeroCompleter.future;
            }
            throw UnimplementedError('Unexpected query $query');
          },
        );
        final controller = ComparisonPickerController(
          repository: repository,
          sourceProduct: source,
        );
        addTearDown(controller.dispose);

        await _settle();

        controller.setSearchQuery('cola');
        await Future<void>.delayed(const Duration(milliseconds: 360));
        controller.setSearchQuery('zero');
        await Future<void>.delayed(const Duration(milliseconds: 360));

        colaCompleter.complete([_product(id: 'old', name: 'Eski Sonuç')]);
        await _settle();

        expect(controller.state.candidates, isEmpty);
        expect(controller.state.isLoading, isTrue);

        final latest = _product(id: 'latest', name: 'Yeni Sonuç');
        zeroCompleter.complete([latest]);
        await _settle();

        expect(controller.state.isLoading, isFalse);
        expect(controller.state.candidates, [latest]);
        expect(repository.findCalls.map((call) => call.query), [
          '',
          'cola',
          'zero',
        ]);
      },
    );

    test('source product cannot be selected', () async {
      final source = _product(id: 'source', name: 'Kaynak');
      final repository = _FakeComparisonRepository(
        findHandler: ({required source, query, limit = 40}) async => const [],
      );
      final controller = ComparisonPickerController(
        repository: repository,
        sourceProduct: source,
      );
      addTearDown(controller.dispose);

      expect(controller.selectCandidate(source), isFalse);
      expect(controller.state.selectedProduct, isNull);
    });

    test('retry succeeds after an initial repository failure', () async {
      final source = _product(id: 'source', name: 'Kaynak');
      var callCount = 0;
      final candidate = _product(id: 'candidate', name: 'Rakip');
      final repository = _FakeComparisonRepository(
        findHandler: ({required source, query, limit = 40}) async {
          callCount++;
          if (callCount == 1) {
            throw Exception('boom');
          }
          return [candidate];
        },
      );
      final controller = ComparisonPickerController(
        repository: repository,
        sourceProduct: source,
      );
      addTearDown(controller.dispose);

      await _settle();
      expect(controller.state.error, 'Ürünler yüklenemedi. Tekrar dene.');

      await controller.retry();

      expect(controller.state.error, isNull);
      expect(controller.state.candidates, [candidate]);
    });
  });

  group('ProductComparisonController', () {
    test('creates the initial comparison', () async {
      final productA = _product(id: 'a', name: 'Protein Yoğurt 150 G');
      final productB = _product(id: 'b', name: 'Rakip Yoğurt 150 G');
      final repository = _FakeComparisonRepository(
        createHandler: ({required productA, required productB}) async =>
            ProductComparison.build(productA: productA, productB: productB),
      );
      final controller = ProductComparisonController(
        repository: repository,
        sourceProduct: productA,
        comparedProduct: productB,
      );
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.comparison?.productA.product.id, 'a');
      expect(controller.state.comparison?.productB.product.id, 'b');
    });

    test('changing Product B preserves Product A', () async {
      final productA = _product(id: 'a', name: 'Protein Yoğurt 150 G');
      final productB = _product(id: 'b', name: 'Rakip Yoğurt 150 G');
      final productC = _product(id: 'c', name: 'Yeni Rakip Yoğurt 150 G');
      final repository = _FakeComparisonRepository(
        createHandler: ({required productA, required productB}) async =>
            ProductComparison.build(productA: productA, productB: productB),
      );
      final controller = ProductComparisonController(
        repository: repository,
        sourceProduct: productA,
        comparedProduct: productB,
      );
      addTearDown(controller.dispose);

      await _settle();
      await controller.changeComparedProduct(productC);

      expect(controller.state.sourceProduct, same(productA));
      expect(controller.state.comparedProduct, same(productC));
      expect(controller.state.comparison?.productA.product.id, 'a');
      expect(controller.state.comparison?.productB.product.id, 'c');
      expect(repository.createCalls.last, (
        productA: productA,
        productB: productC,
      ));
    });

    test('retry works after repository failure', () async {
      final productA = _product(id: 'a', name: 'Protein Yoğurt 150 G');
      final productB = _product(id: 'b', name: 'Rakip Yoğurt 150 G');
      var callCount = 0;
      final repository = _FakeComparisonRepository(
        createHandler: ({required productA, required productB}) async {
          callCount++;
          if (callCount == 1) {
            throw Exception('boom');
          }
          return ProductComparison.build(
            productA: productA,
            productB: productB,
          );
        },
      );
      final controller = ProductComparisonController(
        repository: repository,
        sourceProduct: productA,
        comparedProduct: productB,
      );
      addTearDown(controller.dispose);

      await _settle();
      expect(controller.state.error, 'Ürünler yüklenemedi. Tekrar dene.');

      await controller.retry();

      expect(controller.state.error, isNull);
      expect(controller.state.comparison, isNotNull);
    });
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Product _product({required String id, required String name}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    name: name,
    nutritionText: jsonEncode(const {'sugars': 1.0, 'proteins': 2.0}),
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeComparisonRepository extends ProductComparisonRepository {
  _FakeComparisonRepository({this.findHandler, this.createHandler})
    : super(
        productRepository: _NoopProductRepository(),
        remoteSource: const _NoopRemoteSource(),
      );

  final Future<List<Product>> Function({
    required Product source,
    String? query,
    int limit,
  })?
  findHandler;
  final Future<ProductComparison> Function({
    required Product productA,
    required Product productB,
  })?
  createHandler;
  final List<({Product source, String? query, int limit})> findCalls =
      <({Product source, String? query, int limit})>[];
  final List<({Product productA, Product productB})> createCalls =
      <({Product productA, Product productB})>[];

  @override
  Future<List<Product>> findComparisonCandidates({
    required Product source,
    String? query,
    int limit = 40,
  }) async {
    findCalls.add((source: source, query: query ?? '', limit: limit));
    return findHandler?.call(source: source, query: query, limit: limit) ??
        const <Product>[];
  }

  @override
  Future<ProductComparison> createComparison({
    required Product productA,
    required Product productB,
  }) async {
    createCalls.add((productA: productA, productB: productB));
    return createHandler?.call(productA: productA, productB: productB) ??
        ProductComparison.build(productA: productA, productB: productB);
  }
}

class _NoopRemoteSource implements ProductComparisonRemoteSource {
  const _NoopRemoteSource();

  @override
  Future<List<Map<String, dynamic>>> fetchOverlapProducts({
    required String overlapLiteral,
    String? query,
    required int limit,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    required int limit,
  }) async => const <Map<String, dynamic>>[];
}

class _NoopProductRepository extends ProductRepository {}
