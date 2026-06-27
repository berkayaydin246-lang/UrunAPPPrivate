import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/comparison/repositories/product_comparison_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

void main() {
  group('ProductComparisonRepository.findComparisonCandidates', () {
    test(
      'excludes the source product and deduplicates repeated rows',
      () async {
        final source = _product(
          id: 'source',
          name: 'Kaynak Cips',
          categoryTags: const ['cips', 'atistirmalik'],
        );
        final duplicate = _product(
          id: 'candidate-1',
          name: 'Rakip Cips',
          categoryTags: const ['cips'],
        );
        final remote = _FakeRemoteSource(
          overlapRows: [
            duplicate.toJson(),
            source.toJson(),
            duplicate.toJson(),
          ],
        );
        final repository = ProductComparisonRepository(
          productRepository: _NoopProductRepository(),
          remoteSource: remote,
        );

        final results = await repository.findComparisonCandidates(
          source: source,
        );

        expect(results.map((product) => product.id), ['candidate-1']);
      },
    );

    test(
      'uses category tag overlap and sends a PostgreSQL text[] literal',
      () async {
        final source = _product(
          id: 'source',
          name: 'Kaynak Cips',
          categoryTags: const ['cips', 'kraker'],
        );
        final remote = _FakeRemoteSource(overlapRows: const []);
        final repository = ProductComparisonRepository(
          productRepository: _NoopProductRepository(),
          remoteSource: remote,
        );

        await repository.findComparisonCandidates(source: source);

        expect(remote.overlapCalls, hasLength(1));
        expect(remote.overlapCalls.single.query, isNull);
        expect(remote.overlapCalls.single.overlapLiteral, '{"cips","kraker"}');
      },
    );

    test(
      'does not send an overlap filter when the source has no usable tags',
      () async {
        final source = _product(
          id: 'source',
          name: 'Kaynak Ürün',
          categoryTags: const [],
        );
        final remote = _FakeRemoteSource(searchRows: const []);
        final repository = ProductComparisonRepository(
          productRepository: _NoopProductRepository(),
          remoteSource: remote,
        );

        await repository.findComparisonCandidates(
          source: source,
          query: 'cola',
        );

        expect(remote.overlapCalls, isEmpty);
        expect(remote.searchCalls, hasLength(1));
        expect(remote.searchCalls.single.query, 'cola');
      },
    );

    test(
      'ranks by shared tags, then nutrition availability, then stable ordering',
      () async {
        final source = _product(
          id: 'source',
          name: 'Kaynak Cips',
          categoryTags: const ['cips', 'tuzlu'],
        );
        final best = _product(
          id: 'best',
          name: 'A Cips',
          brand: 'A Marka',
          categoryTags: const ['cips', 'tuzlu'],
          nutrition: const {'sugars': 1.2},
        );
        final middle = _product(
          id: 'middle',
          name: 'B Cips',
          brand: 'B Marka',
          categoryTags: const ['cips', 'tuzlu'],
        );
        final last = _product(
          id: 'last',
          name: 'C Cips',
          brand: 'C Marka',
          categoryTags: const ['cips'],
          nutrition: const {'sugars': 1.0},
        );
        final remote = _FakeRemoteSource(
          overlapRows: [last.toJson(), middle.toJson(), best.toJson()],
        );
        final repository = ProductComparisonRepository(
          productRepository: _NoopProductRepository(),
          remoteSource: remote,
        );

        final results = await repository.findComparisonCandidates(
          source: source,
        );

        expect(results.map((product) => product.id), [
          'best',
          'middle',
          'last',
        ]);
      },
    );

    test(
      'filters by query across name, brand, normalized name, and barcode',
      () async {
        final source = _product(
          id: 'source',
          name: 'Kaynak İçecek',
          categoryTags: const ['icecekler'],
        );
        final matching = _product(
          id: 'match',
          name: 'Zero Sugar İçecek',
          brand: 'FreshScan',
          normalizedName: 'zero sugar icecek',
          barcode: '123456',
          categoryTags: const ['icecekler'],
        );
        final remote = _FakeRemoteSource(
          overlapRows: [
            _product(
              id: 'other-name',
              name: 'Farklı Ürün',
              brand: 'Başka Marka',
              categoryTags: const ['icecekler'],
            ).toJson(),
            matching.toJson(),
          ],
        );
        final repository = ProductComparisonRepository(
          productRepository: _NoopProductRepository(),
          remoteSource: remote,
        );

        expect(
          (await repository.findComparisonCandidates(
            source: source,
            query: 'freshscan',
          )).map((product) => product.id),
          ['match'],
        );
        expect(
          (await repository.findComparisonCandidates(
            source: source,
            query: '123456',
          )).map((product) => product.id),
          ['match'],
        );
      },
    );

    test('respects the requested limit', () async {
      final source = _product(
        id: 'source',
        name: 'Kaynak Cips',
        categoryTags: const ['cips'],
      );
      final remote = _FakeRemoteSource(
        overlapRows: List.generate(
          6,
          (index) => _product(
            id: 'candidate-$index',
            name: 'Ürün $index',
            categoryTags: const ['cips'],
          ).toJson(),
        ),
      );
      final repository = ProductComparisonRepository(
        productRepository: _NoopProductRepository(),
        remoteSource: remote,
      );

      final results = await repository.findComparisonCandidates(
        source: source,
        limit: 2,
      );

      expect(results, hasLength(2));
      expect(remote.overlapCalls.single.limit, 6);
    });
  });

  group('buildPostgresTextArrayLiteral', () {
    test('quotes values and skips blanks', () {
      expect(
        buildPostgresTextArrayLiteral(['cips', ' ', 'biskuvi']),
        '{"cips","biskuvi"}',
      );
    });
  });
}

Product _product({
  required String id,
  required String name,
  String? brand,
  String? normalizedName,
  String? barcode,
  List<String>? categoryTags,
  Map<String, dynamic>? nutrition,
}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    barcode: barcode,
    name: name,
    normalizedName: normalizedName,
    brand: brand,
    nutritionText: nutrition == null ? null : jsonEncode(nutrition),
    verificationStatus: 'verified',
    categoryTags: categoryTags,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeRemoteSource implements ProductComparisonRemoteSource {
  _FakeRemoteSource({
    this.overlapRows = const <Map<String, dynamic>>[],
    this.searchRows = const <Map<String, dynamic>>[],
  });

  final List<Map<String, dynamic>> overlapRows;
  final List<Map<String, dynamic>> searchRows;
  final List<({String overlapLiteral, String? query, int limit})> overlapCalls =
      <({String overlapLiteral, String? query, int limit})>[];
  final List<({String? query, int limit})> searchCalls =
      <({String? query, int limit})>[];

  @override
  Future<List<Map<String, dynamic>>> fetchOverlapProducts({
    required String overlapLiteral,
    String? query,
    required int limit,
  }) async {
    overlapCalls.add((
      overlapLiteral: overlapLiteral,
      query: query,
      limit: limit,
    ));
    return overlapRows;
  }

  @override
  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    required int limit,
  }) async {
    searchCalls.add((query: query, limit: limit));
    return searchRows;
  }
}

class _NoopProductRepository extends ProductRepository {}
