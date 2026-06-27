import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/imports/repositories/open_food_facts_repository.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/user_library/controllers/user_product_library_controller.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';

/// Barcode scanning state.
class BarcodeScanState {
  final Product? product;
  final String? scannedBarcode;
  final bool isLoading;
  final String? loadingMessage;
  final String? error;
  final bool notFound;

  /// External OFF preview when the barcode is not in our local catalog.
  /// The product is shown with a clear "unverified / external" badge.
  /// It is NOT inserted into the products table.
  final OffProduct? externalPreview;

  BarcodeScanState({
    this.product,
    this.scannedBarcode,
    this.isLoading = false,
    this.loadingMessage,
    this.error,
    this.notFound = false,
    this.externalPreview,
  });

  BarcodeScanState copyWith({
    Product? product,
    String? scannedBarcode,
    bool? isLoading,
    String? loadingMessage,
    String? error,
    bool? notFound,
    OffProduct? externalPreview,
    bool clearError = false,
    bool clearExternalPreview = false,
  }) {
    return BarcodeScanState(
      product: product ?? this.product,
      scannedBarcode: scannedBarcode ?? this.scannedBarcode,
      isLoading: isLoading ?? this.isLoading,
      loadingMessage: loadingMessage ?? this.loadingMessage,
      error: clearError ? null : (error ?? this.error),
      notFound: notFound ?? this.notFound,
      externalPreview: clearExternalPreview
          ? null
          : (externalPreview ?? this.externalPreview),
    );
  }

  bool get hasProduct => product != null;
  bool get hasError => error != null;
  bool get hasExternalPreview => externalPreview != null;
}

/// Notifier for managing barcode scan state.
class BarcodeScanNotifier extends StateNotifier<BarcodeScanState> {
  final _offRepo = OpenFoodFactsRepository();
  final Future<void> Function(LocalProductSnapshot product)
  _recordScannedProduct;

  String? _lastScannedBarcode;
  DateTime? _lastScanTime;

  static const int _debounceMs = 500;

  BarcodeScanNotifier({
    required Future<void> Function(LocalProductSnapshot product)
    recordScannedProduct,
  }) : _recordScannedProduct = recordScannedProduct,
       super(BarcodeScanState());

  /// Process a scanned barcode using a local-first policy.
  ///
  /// 1. Search local products table (via OFF repo's local-check path).
  ///    If found (existing or enriched), navigate to product detail.
  /// 2. If not found locally, query OFF as a read-only external preview.
  ///    The OFF product is shown with an "unverified" label; it is NOT inserted
  ///    into the products table.
  /// 3. If not found anywhere, show friendly empty state.
  ///
  /// Returns true if the barcode was processed, false if duplicate (debounce).
  Future<bool> handleBarcodeScanned(String barcode) async {
    final now = DateTime.now();

    if (_lastScannedBarcode == barcode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < _debounceMs) {
      return false;
    }

    _lastScannedBarcode = barcode;
    _lastScanTime = now;

    state = BarcodeScanState(
      isLoading: true,
      loadingMessage: 'Ürün aranıyor...',
      scannedBarcode: barcode,
    );

    _debugBarcodeLog('[Barcode] scanned=$barcode');

    try {
      // Step 1: check local products DB (and enrich from OFF if found but
      // incomplete). No INSERT happens here — see fetchAndPersistByBarcode.
      final imported = await _offRepo.fetchAndPersistByBarcode(barcode);

      if (imported != null) {
        _debugBarcodeLog('[Barcode] found locally id=${imported.product.id}');
        _recordScannedActivity(imported.product);
        state = BarcodeScanState(
          product: imported.product,
          scannedBarcode: barcode,
        );
        return true;
      }

      // Step 2: not in local catalog — fetch OFF as external preview (no DB).
      _debugBarcodeLog('[Barcode] not in local catalog — fetching OFF preview');
      state = state.copyWith(loadingMessage: "Open Food Facts'te aranıyor...");
      final preview = await _offRepo.fetchExternalPreview(barcode);

      _debugBarcodeLog(
        '[Barcode] OFF preview=${preview == null ? "notFound" : preview.name}',
      );

      state = BarcodeScanState(
        notFound: true,
        scannedBarcode: barcode,
        externalPreview: preview, // null = not found anywhere
      );
      return true;
    } on OffNetworkException {
      state = BarcodeScanState(
        scannedBarcode: barcode,
        error: 'Ürün bilgisi alınamadı. İnternet bağlantınızı kontrol edin.',
      );
      return true;
    } catch (e) {
      _debugBarcodeLog('[Barcode] error=$e');
      state = BarcodeScanState(
        scannedBarcode: barcode,
        error: 'Barkod okunurken hata oluştu. Lütfen tekrar deneyin.',
      );
      return true;
    }
  }

  void reset() {
    state = BarcodeScanState();
    _lastScannedBarcode = null;
    _lastScanTime = null;
  }

  void clearError() {
    state = state.copyWith(error: null, clearError: true);
  }

  void _recordScannedActivity(Product product) {
    unawaited(
      _recordScannedProduct(localSnapshotFromProduct(product)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _debugBarcodeLog('[Barcode] failed to record scanned product: $error');
      }),
    );
  }
}

void _debugBarcodeLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}

final barcodeScanProvider =
    StateNotifierProvider<BarcodeScanNotifier, BarcodeScanState>(
      (ref) => BarcodeScanNotifier(
        recordScannedProduct: ref
            .read(recentProductActivityProvider.notifier)
            .recordScannedProduct,
      ),
    );
