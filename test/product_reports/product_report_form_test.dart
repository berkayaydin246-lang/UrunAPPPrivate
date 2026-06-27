import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/product_page.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/product_reports/controllers/product_report_form_controller.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_receipt.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_submission.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';
import 'package:food_analyzer_app/features/product_reports/repositories/product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/widgets/product_report_sheet.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeReportRepository implements ProductReportRepository {
  final Future<ProductReportReceipt> Function(ProductReportSubmission) _handler;
  var callCount = 0;
  ProductReportSubmission? lastSubmission;

  _FakeReportRepository({
    required Future<ProductReportReceipt> Function(ProductReportSubmission)
    handler,
  }) : _handler = handler;

  factory _FakeReportRepository.success() => _FakeReportRepository(
    handler: (_) async => ProductReportReceipt(
      reportId: _kReportId,
      submittedAt: DateTime(2026, 6, 26),
    ),
  );

  factory _FakeReportRepository.failure(
    ProductReportSubmissionFailureType type,
  ) => _FakeReportRepository(
    handler: (_) async => throw ProductReportSubmissionException(
      type: type,
      userMessage: 'raw backend: $type',
    ),
  );

  factory _FakeReportRepository.blocking(Completer<void> gate) =>
      _FakeReportRepository(
        handler: (_) async {
          await gate.future;
          return ProductReportReceipt(reportId: _kReportId);
        },
      );

  @override
  Future<ProductReportReceipt> submitReport(
    ProductReportSubmission submission,
  ) async {
    callCount++;
    lastSubmission = submission;
    return _handler(submission);
  }
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({required Product product}) : _product = product;
  final Product _product;
  var getProductByIdCalls = 0;

  @override
  Future<Product?> getProductById(String id) async {
    getProductByIdCalls++;
    return _product;
  }

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async =>
      null;

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async =>
      const [];

  @override
  Future<List<Ingredient>> getAllIngredients() async => const [];
}

class _SpyUserLibraryRepository implements UserProductLibraryRepository {
  _SpyUserLibraryRepository()
    : _delegate = LocalUserProductLibraryRepository(storage: _MemoryStorage());

  final LocalUserProductLibraryRepository _delegate;
  var recordViewedCallCount = 0;

  @override
  Future<bool> isFavorite(String productId) => _delegate.isFavorite(productId);

  @override
  Future<void> addFavorite(LocalProductSnapshot product) =>
      _delegate.addFavorite(product);

  @override
  Future<void> removeFavorite(String productId) =>
      _delegate.removeFavorite(productId);

  @override
  Future<bool> toggleFavorite(LocalProductSnapshot product) =>
      _delegate.toggleFavorite(product);

  @override
  Future<List<FavoriteProductEntry>> getFavorites() => _delegate.getFavorites();

  @override
  Future<void> recordViewedProduct(LocalProductSnapshot product) {
    recordViewedCallCount++;
    return _delegate.recordViewedProduct(product);
  }

  @override
  Future<void> recordScannedProduct(LocalProductSnapshot product) =>
      _delegate.recordScannedProduct(product);

  @override
  Future<List<ProductActivityEntry>> getRecentActivity({
    ProductActivityType? type,
    int? limit,
  }) => _delegate.getRecentActivity(type: type, limit: limit);

  @override
  Future<void> clearRecentActivity({ProductActivityType? type}) =>
      _delegate.clearRecentActivity(type: type);
}

class _MemoryStorage implements UserProductLibraryStorage {
  final _values = <String, String>{};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async =>
      _values[key] = value;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kProductId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _kReportId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Product _makeProduct({String id = _kProductId}) => Product(
  id: id,
  name: 'Test Ürünü',
  brand: 'Test Marka',
  verificationStatus: 'verified',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ProviderContainer _makeContainer(_FakeReportRepository repo) {
  final container = ProviderContainer(
    overrides: [productReportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpProductPage(
  WidgetTester tester, {
  required _FakeProductRepository productRepository,
  required _FakeReportRepository reportRepository,
  _SpyUserLibraryRepository? userLibraryRepository,
}) async {
  // 800×2000 logical viewport so the full product page fits without scrolling.
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2000);

  final libraryRepo = userLibraryRepository ?? _SpyUserLibraryRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(productRepository),
        productReportRepositoryProvider.overrideWithValue(reportRepository),
        userProductLibraryRepositoryProvider.overrideWithValue(libraryRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ProductScreen(productId: _makeProduct().id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSheetDirectly(
  WidgetTester tester,
  _FakeReportRepository reportRepository, {
  Product? product,
}) async {
  final p = product ?? _makeProduct();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productReportRepositoryProvider.overrideWithValue(reportRepository),
        userProductLibraryRepositoryProvider.overrideWithValue(
          _SpyUserLibraryRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(body: ProductReportSheet(product: p)),
      ),
    ),
  );
}

// ── Controller unit tests ─────────────────────────────────────────────────────

void main() {
  group('ReportFormState', () {
    test('initial state: no type selected, canSubmit is false', () {
      const state = ReportFormState();
      expect(state.selectedType, isNull);
      expect(state.canSubmit, isFalse);
      expect(state.status, ReportSubmissionStatus.idle);
      expect(state.errorMessage, isNull);
    });

    test('canSubmit is true after type is selected (non-other)', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.wrongImage,
      );
      expect(state.canSubmit, isTrue);
    });

    test('canSubmit is false for "other" type with empty details', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.other,
        details: '',
      );
      expect(state.canSubmit, isFalse);
    });

    test('canSubmit is false for "other" with whitespace-only details', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.other,
        details: '   ',
      );
      expect(state.canSubmit, isFalse);
    });

    test('canSubmit is true for "other" with non-empty details', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.other,
        details: 'açıklama',
      );
      expect(state.canSubmit, isTrue);
    });

    test('canSubmit is false while submitting', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.wrongImage,
        status: ReportSubmissionStatus.submitting,
      );
      expect(state.canSubmit, isFalse);
    });

    test('canSubmit is false when details exceeds 1000 characters', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.wrongNutrition,
        details: 'a' * 1001,
      );
      expect(state.canSubmit, isFalse);
    });

    test('canSubmit is true at exactly 1000 characters', () {
      final state = const ReportFormState().copyWith(
        selectedType: ProductReportType.wrongNutrition,
        details: 'a' * 1000,
      );
      expect(state.canSubmit, isTrue);
    });
  });

  group('ProductReportFormNotifier', () {
    test('selectType updates selectedType and clears error', () {
      final container = _makeContainer(_FakeReportRepository.success());
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongImage);

      final state = container.read(productReportFormProvider(_kProductId));
      expect(state.selectedType, ProductReportType.wrongImage);
      expect(state.errorMessage, isNull);
    });

    test('updateDetails updates the details field', () {
      final container = _makeContainer(_FakeReportRepository.success());
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.updateDetails('test açıklaması');

      expect(
        container.read(productReportFormProvider(_kProductId)).details,
        'test açıklaması',
      );
    });

    test('submit calls repository with trimmed details', () async {
      final repo = _FakeReportRepository.success();
      final container = _makeContainer(repo);
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongNutrition);
      notifier.updateDetails('  besin değeri yanlış  ');
      await notifier.submit();

      expect(repo.callCount, 1);
      expect(repo.lastSubmission!.details, 'besin değeri yanlış');
    });

    test('submit always passes empty evidence URLs', () async {
      final repo = _FakeReportRepository.success();
      final container = _makeContainer(repo);
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongImage);
      await notifier.submit();

      expect(repo.lastSubmission!.evidenceImageUrls, isEmpty);
    });

    test('submit passes null details when field is blank', () async {
      final repo = _FakeReportRepository.success();
      final container = _makeContainer(repo);
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongBarcode);
      notifier.updateDetails('   ');
      await notifier.submit();

      expect(repo.lastSubmission!.details, isNull);
    });

    test('successful submit transitions to success status', () async {
      final container = _makeContainer(_FakeReportRepository.success());
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.outdatedIngredients);
      final result = await notifier.submit();

      expect(result, isTrue);
      expect(
        container.read(productReportFormProvider(_kProductId)).status,
        ReportSubmissionStatus.success,
      );
    });

    test(
      'double submit while in-flight produces exactly one RPC call',
      () async {
        final gate = Completer<void>();
        final repo = _FakeReportRepository.blocking(gate);
        final container = _makeContainer(repo);
        final notifier = container.read(
          productReportFormProvider(_kProductId).notifier,
        );

        notifier.selectType(ProductReportType.wrongCategory);

        final firstFuture = notifier.submit();
        final secondResult = await notifier.submit(); // blocked synchronously

        gate.complete();
        await firstFuture;

        expect(repo.callCount, 1);
        expect(secondResult, isFalse);
      },
    );

    test('failure preserves selected type and details', () async {
      final container = _makeContainer(
        _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.networkFailure,
        ),
      );
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongImage);
      notifier.updateDetails('photo looks wrong');
      await notifier.submit();

      final state = container.read(productReportFormProvider(_kProductId));
      expect(state.selectedType, ProductReportType.wrongImage);
      expect(state.details, 'photo looks wrong');
      expect(state.status, ReportSubmissionStatus.failure);
    });

    test('failed submit returns false', () async {
      final container = _makeContainer(
        _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.unknown,
        ),
      );
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );

      notifier.selectType(ProductReportType.wrongImage);
      final result = await notifier.submit();

      expect(result, isFalse);
    });
  });

  group('Error message mapping', () {
    Future<String?> submitAndGetError(
      ProductReportSubmissionFailureType type,
    ) async {
      final repo = _FakeReportRepository.failure(type);
      final container = _makeContainer(repo);
      final notifier = container.read(
        productReportFormProvider(_kProductId).notifier,
      );
      notifier.selectType(ProductReportType.wrongImage);
      await notifier.submit();
      return container
          .read(productReportFormProvider(_kProductId))
          .errorMessage;
    }

    test('rateLimited → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.rateLimited,
      );
      expect(msg, contains('Bugün çok sayıda bildirim'));
      expect(msg, isNot(contains('rateLimited')));
      expect(msg, isNot(contains('report_rate_limited')));
    });

    test('duplicateRecentReport → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.duplicateRecentReport,
      );
      expect(msg, contains('yakın zamanda'));
      expect(msg, isNot(contains('duplicate')));
    });

    test('productNotFound → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.productNotFound,
      );
      expect(msg, contains('veritabanında bulunamıyor'));
      expect(msg, isNot(contains('product_not_found')));
    });

    test('invalidSubmission → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.invalidSubmission,
      );
      expect(msg, contains('kontrol edip'));
      expect(msg, isNot(contains('invalidSubmission')));
    });

    test('networkFailure → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.networkFailure,
      );
      expect(msg, contains('Bağlantı kurulamadı'));
      expect(msg, isNot(contains('SocketException')));
    });

    test('unknown → safe Turkish message', () async {
      final msg = await submitAndGetError(
        ProductReportSubmissionFailureType.unknown,
      );
      expect(msg, contains('gönderilemedi'));
      expect(msg, isNot(contains('unknown')));
    });

    test(
      'raw backend exception message never surfaces as errorMessage',
      () async {
        final msg = await submitAndGetError(
          ProductReportSubmissionFailureType.unknown,
        );
        expect(msg, isNot(contains('raw backend')));
      },
    );
  });

  group('Report type enum coverage', () {
    test('all 7 ProductReportType values have a non-empty labelTr', () {
      for (final type in ProductReportType.values) {
        expect(type.labelTr, isNotEmpty, reason: '$type missing labelTr');
      }
    });

    test('labelTr values match the centralized Turkish spec', () {
      expect(ProductReportType.wrongImage.labelTr, 'Görsel yanlış');
      expect(
        ProductReportType.outdatedIngredients.labelTr,
        'İçindekiler güncel değil',
      );
      expect(
        ProductReportType.wrongNutrition.labelTr,
        'Besin değerleri yanlış',
      );
      expect(
        ProductReportType.wrongNameOrBrand.labelTr,
        'Ürün adı veya marka yanlış',
      );
      expect(ProductReportType.wrongCategory.labelTr, 'Kategori yanlış');
      expect(ProductReportType.wrongBarcode.labelTr, 'Barkod yanlış');
      expect(ProductReportType.other.labelTr, 'Diğer');
    });
  });

  // ── Widget tests ──────────────────────────────────────────────────────────────

  group('Product Detail — report card presence', () {
    testWidgets('Product Detail displays the report entry card', (
      tester,
    ) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
      );

      expect(find.byKey(const Key('product-report-card')), findsOneWidget);
      expect(find.text('Bu üründe bir hata mı var?'), findsOneWidget);
      expect(find.text('Hata bildir'), findsOneWidget);
    });

    testWidgets('opening Product Detail does not call the report RPC', (
      tester,
    ) async {
      final reportRepo = _FakeReportRepository.success();

      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: reportRepo,
      );

      expect(reportRepo.callCount, 0);
    });

    testWidgets('tapping "Hata bildir" opens the report sheet', (tester) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-sheet')), findsOneWidget);
      expect(find.text('Ürün bilgisi bildir'), findsOneWidget);
    });
  });

  group('Report sheet — type selection', () {
    testWidgets('sheet shows all 7 report types from the enum', (tester) async {
      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      for (final type in ProductReportType.values) {
        expect(
          find.text(type.labelTr),
          findsOneWidget,
          reason: '${type.labelTr} should be visible',
        );
      }
    });

    testWidgets('submit button is disabled before type selection', (
      tester,
    ) async {
      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('report-submit-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('submit button is enabled after type selection', (
      tester,
    ) async {
      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      await tester.tap(find.text('Görsel yanlış'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('report-submit-button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('submit disabled for "Diğer" with empty details', (
      tester,
    ) async {
      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      await tester.tap(find.text('Diğer'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('report-submit-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('submit enabled for "Diğer" when details are filled', (
      tester,
    ) async {
      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      await tester.tap(find.text('Diğer'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('report-details-field')),
        'örnek açıklama',
      );
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('report-submit-button')),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('Report sheet — success path', () {
    testWidgets('success closes the sheet', (tester) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('İçindekiler güncel değil'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-sheet')), findsNothing);
    });

    testWidgets('success shows non-blocking SnackBar feedback', (tester) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İçindekiler güncel değil'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('Bildirimin alındı'), findsOneWidget);
      // Sheet is gone — not a blocking dialog
      expect(find.byKey(const Key('report-sheet')), findsNothing);
    });
  });

  group('Report sheet — failure path', () {
    testWidgets('failure keeps the sheet open', (tester) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.networkFailure,
        ),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görsel yanlış'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-sheet')), findsOneWidget);
    });

    testWidgets('rate-limit failure shows safe Turkish message', (
      tester,
    ) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.rateLimited,
        ),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görsel yanlış'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Bugün çok sayıda bildirim gönderdin. Daha sonra tekrar deneyebilirsin.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('rateLimited'), findsNothing);
      expect(find.textContaining('raw backend'), findsNothing);
    });

    testWidgets('duplicate-recent-report shows correct Turkish message', (
      tester,
    ) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.duplicateRecentReport,
        ),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görsel yanlış'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Bu ürün için yakın zamanda aynı bildirimi gönderdin.'),
        findsOneWidget,
      );
    });

    testWidgets('failure preserves selected type visible in sheet', (
      tester,
    ) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.failure(
          ProductReportSubmissionFailureType.networkFailure,
        ),
      );

      await tester.tap(find.text('Hata bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Besin değerleri yanlış'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('report-details-field')),
        'besin detayları',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      // Sheet still open, type row still in view
      expect(find.byKey(const Key('report-sheet')), findsOneWidget);
      expect(find.text('Besin değerleri yanlış'), findsOneWidget);
    });
  });

  group('Report sheet — layout', () {
    testWidgets('no overflow on small 360×640 screen', (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(360, 640);

      await _pumpSheetDirectly(tester, _FakeReportRepository.success());

      expect(tester.takeException(), isNull);
    });
  });

  group('Existing behavior regression', () {
    testWidgets('favorites action still present on Product Detail', (
      tester,
    ) async {
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
      );

      expect(
        find.byKey(const ValueKey('product-favorite-action')),
        findsOneWidget,
      );
    });

    testWidgets('viewed history recorded on Product Detail open', (
      tester,
    ) async {
      final libraryRepo = _SpyUserLibraryRepository();
      await _pumpProductPage(
        tester,
        productRepository: _FakeProductRepository(product: _makeProduct()),
        reportRepository: _FakeReportRepository.success(),
        userLibraryRepository: libraryRepo,
      );

      expect(libraryRepo.recordViewedCallCount, 1);
    });
  });
}
