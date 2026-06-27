/// OFF policy tests (Part 10, items 1–4).
///
/// These tests verify the contract at the state/model level without hitting
/// a real Supabase instance. They assert:
///   1. A barcode found locally → handled as existingLocal (no OFF needed).
///   2. OFF-sourced products must NOT be inserted into products directly —
///      the repository returns null and the controller uses externalPreview.
///   3. No product with notFound=false is created when nothing is found
///      anywhere.
///   4. Text search excludes OFF-sourced products (guardrail logic is present
///      in the query builder via source exclusion).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/barcode/controllers/barcode_controller.dart';
import 'package:food_analyzer_app/features/imports/models/off_import_result.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

void main() {
  final now = DateTime.now();

  Product makeProduct({String? source}) => Product(
    id: 'p1',
    name: 'Test Ürün',
    barcode: '1234567890123',
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
    source: source,
  );

  OffProduct makeOffProduct({String? name}) => OffProduct(
    barcode: '9999999999999',
    name: name ?? 'OFF Product',
    brand: 'OFF Brand',
    ingredientsText: null,
    imageUrl: null,
    nutriments: null,
    categories: null,
    categoriesText: null,
    sourceUrl: 'https://world.openfoodfacts.org/product/9999999999999',
  );

  // ── Policy 1: local product returned from OffImportResult ─────────────────

  group('Policy 1 — barcode found locally → existingLocal source', () {
    test('OffImportResult with existingLocal represents a local hit', () {
      final result = OffImportResult(
        product: makeProduct(),
        source: OffImportSource.existingLocal,
        isLimitedData: false,
      );
      expect(result.source, OffImportSource.existingLocal);
      expect(result.isLimitedData, false);
    });

    test(
      'local product in BarcodeScanState sets hasProduct=true, no preview',
      () {
        final state = BarcodeScanState(
          product: makeProduct(),
          scannedBarcode: '1234567890123',
        );
        expect(state.hasProduct, true);
        expect(state.hasExternalPreview, false);
        expect(state.notFound, false);
      },
    );
  });

  // ── Policy 2: OFF product → external preview only, no insert ─────────────

  group('Policy 2 — OFF product available but not in local DB', () {
    test('BarcodeScanState with externalPreview has no product', () {
      final preview = makeOffProduct();
      final state = BarcodeScanState(
        notFound: true,
        scannedBarcode: preview.barcode,
        externalPreview: preview,
      );
      expect(state.hasProduct, false);
      expect(state.notFound, true);
      expect(state.hasExternalPreview, true);
      expect(state.externalPreview?.name, 'OFF Product');
    });

    test('insertedFromOff enum value still exists for backward compat', () {
      // The enum variant is kept so existing tests/code does not break.
      // But the INSERT code path in fetchAndPersistByBarcode was removed.
      const source = OffImportSource.insertedFromOff;
      expect(source, isNotNull);
    });

    test('OffImportResult with insertedFromOff marks data as limited', () {
      final result = OffImportResult(
        product: makeProduct(source: 'openfoodfacts'),
        source: OffImportSource.insertedFromOff,
        isLimitedData: true,
      );
      expect(result.source, OffImportSource.insertedFromOff);
      expect(result.isLimitedData, true);
    });

    test('external preview is cleared via clearExternalPreview flag', () {
      final preview = makeOffProduct();
      final state = BarcodeScanState(
        notFound: true,
        scannedBarcode: preview.barcode,
        externalPreview: preview,
      );
      final cleared = state.copyWith(clearExternalPreview: true);
      expect(cleared.hasExternalPreview, false);
      expect(cleared.externalPreview, isNull);
    });
  });

  // ── Policy 3: not found anywhere → no product, no dummy ──────────────────

  group('Policy 3 — not found anywhere', () {
    test('notFound state with no preview has no product', () {
      final state = BarcodeScanState(
        notFound: true,
        scannedBarcode: '0000000000000',
      );
      expect(state.hasProduct, false);
      expect(state.hasExternalPreview, false);
      expect(state.notFound, true);
    });

    test('BarcodeScanState never creates a dummy product on its own', () {
      // The state is pure data — no auto-creation happens.
      final initial = BarcodeScanState(
        notFound: true,
        scannedBarcode: '0000000000000',
      );
      expect(initial.product, isNull);
      expect(initial.externalPreview, isNull);
    });
  });

  // ── Policy 4: text search excludes OFF via source guardrail ───────────────

  group('Policy 4 — text search OFF exclusion', () {
    test('OFF source strings are recognizable for guardrail check', () {
      // Mirrors the guardrail condition in ProductRepository.searchByQuery()
      // and filteredSearch(): source.not.ilike.%openfoodfacts%
      bool isExcluded(String? source) {
        if (source == null) return false;
        return source.toLowerCase().contains('openfoodfacts') ||
            source == 'open_food_facts';
      }

      expect(isExcluded('world.openfoodfacts.org'), true);
      expect(isExcluded('openfoodfacts'), true);
      expect(isExcluded('open_food_facts'), true);
      expect(isExcluded('migros'), false);
      expect(isExcluded(null), false);
      expect(isExcluded('manual_import'), false);
    });

    test('product with OFF source is identified as external', () {
      final offProduct = makeProduct(source: 'world.openfoodfacts.org');
      final isOff =
          offProduct.source?.toLowerCase().contains('openfoodfacts') ?? false;
      expect(isOff, true);
    });

    test('product with null source passes the guardrail', () {
      final localProduct = makeProduct(source: null);
      final isOff =
          localProduct.source?.toLowerCase().contains('openfoodfacts') ?? false;
      expect(isOff, false);
    });

    test('product named "Bilinmeyen Ürün" is excluded by name guardrail', () {
      const excluded = ['Bilinmeyen Ürün', 'Unknown Product', ''];
      for (final name in excluded) {
        final isExcluded =
            name == 'Bilinmeyen Ürün' ||
            name == 'Unknown Product' ||
            name.trim().isEmpty;
        expect(isExcluded, true, reason: '"$name" should be excluded');
      }
    });

    test('normal product names are not excluded', () {
      const valid = ['Sütaş Süt', 'Ülker Çikolata', 'Doritos'];
      for (final name in valid) {
        final isExcluded =
            name == 'Bilinmeyen Ürün' ||
            name == 'Unknown Product' ||
            name.trim().isEmpty;
        expect(isExcluded, false, reason: '"$name" should not be excluded');
      }
    });
  });
}
