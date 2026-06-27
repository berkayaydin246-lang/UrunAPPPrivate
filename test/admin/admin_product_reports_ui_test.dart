import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_home_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_product_report_detail_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_product_reports_page.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

import 'helpers/admin_product_reports_test_helpers.dart';

void main() {
  setUpAll(_mockPathProvider);

  group('Admin authorization and menu UI', () {
    testWidgets(
      'signed-out admin area shows login form without public registration',
      (tester) async {
        final authRepository = FakeAdminAuthRepository();
        addTearDown(authRepository.dispose);

        await _pumpAdminWidget(
          tester,
          authRepository: authRepository,
          child: const AdminHomePage(),
        );

        expect(find.text('Yönetici Girişi'), findsOneWidget);
        expect(find.text('Yönetici hesabınızla giriş yapın.'), findsOneWidget);
        expect(find.byKey(const ValueKey('admin-login-email')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin-login-password')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin-login-button')),
          findsOneWidget,
        );
        expect(find.text('Kayıt Ol'), findsNothing);
        expect(find.text('Sign Up'), findsNothing);
        expect(find.byTooltip('Çıkış yap'), findsNothing);
      },
    );

    testWidgets(
      'login uses Supabase auth and authorized menu shows Ürün Bildirimleri',
      (tester) async {
        final authRepository = FakeAdminAuthRepository(verifyResult: true);
        addTearDown(authRepository.dispose);

        await _pumpAdminWidget(
          tester,
          authRepository: authRepository,
          child: const AdminHomePage(),
        );

        await tester.enterText(
          find.byKey(const ValueKey('admin-login-email')),
          '  admin@freshscan.test ',
        );
        await tester.enterText(
          find.byKey(const ValueKey('admin-login-password')),
          'super-secret',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('admin-login-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(authRepository.signInCallCount, 1);
        expect(authRepository.lastEmail, 'admin@freshscan.test');
        expect(authRepository.lastPassword, 'super-secret');
        expect(authRepository.verifyCallCount, greaterThanOrEqualTo(1));
        expect(find.text('Ürün Bildirimleri'), findsOneWidget);
        expect(find.byTooltip('Çıkış yap'), findsOneWidget);
      },
    );

    testWidgets('ordinary authenticated user sees not-authorized state', (
      tester,
    ) async {
      final authRepository = FakeAdminAuthRepository(
        currentSession: fakeSession(appMetadata: const {'role': 'consumer'}),
        verifyResult: false,
      );
      addTearDown(authRepository.dispose);

      await _pumpAdminWidget(
        tester,
        authRepository: authRepository,
        child: const AdminHomePage(),
      );

      expect(find.text('Bu hesabın yönetici yetkisi yok.'), findsOneWidget);
      expect(authRepository.verifyCallCount, greaterThanOrEqualTo(1));
    });
  });

  group('Admin product reports pages', () {
    testWidgets('reports page defaults to Bekliyor and loads the first page', (
      tester,
    ) async {
      final authRepository = FakeAdminAuthRepository(
        currentSession: fakeSession(),
        verifyResult: true,
      );
      final reportRepository = FakeAdminProductReportRepository(
        listHandler: ({status, limit = 30, cursor}) async {
          return AdminProductReportPage(
            reports: [
              makeReportSummary(
                id: 'pending-1',
                productNameSnapshot: 'Lay\'s Klasik',
                status: ProductReportStatus.pending,
              ),
            ],
            nextCursor: null,
          );
        },
      );
      addTearDown(authRepository.dispose);

      await _pumpAdminWidget(
        tester,
        authRepository: authRepository,
        reportRepository: reportRepository,
        child: const AdminProductReportsPage(),
      );

      expect(reportRepository.listCalls, hasLength(1));
      expect(
        reportRepository.listCalls.single.status,
        ProductReportStatus.pending,
      );
      expect(find.text('Lay\'s Klasik'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('report-filter-pending')),
            )
            .selected,
        isTrue,
      );
      expect(find.text('Bekliyor'), findsWidgets);
    });

    testWidgets(
      'detail page keeps snapshot and current product distinct and exposes only valid actions',
      (tester) async {
        final authRepository = FakeAdminAuthRepository(
          currentSession: fakeSession(),
          verifyResult: true,
        );
        final reportRepository = FakeAdminProductReportRepository(
          getHandler: (reportId) async {
            return makeReportDetail(
              id: reportId,
              productNameSnapshot: 'Bildirimdeki Ürün',
              productBrandSnapshot: 'Anlık Marka',
              details: 'Arka etiket güncel değil.',
              status: ProductReportStatus.pending,
            );
          },
        );
        addTearDown(authRepository.dispose);

        await _pumpAdminWidget(
          tester,
          authRepository: authRepository,
          reportRepository: reportRepository,
          child: const AdminProductReportDetailPage(reportId: 'report-1'),
        );

        expect(find.text('Bildirim anındaki ürün'), findsOneWidget);
        expect(find.text('Mevcut ürün kaydı'), findsOneWidget);
        expect(find.text('Bildirimdeki Ürün'), findsOneWidget);
        expect(find.text('Katalog Ürünü'), findsOneWidget);
        expect(find.text('Arka etiket güncel değil.'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Durum işlemleri'),
          220,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Durum işlemleri'), findsOneWidget);
      },
    );

    testWidgets(
      'detail page note save enables after input and missing sections stay safe',
      (tester) async {
        final authRepository = FakeAdminAuthRepository(
          currentSession: fakeSession(),
          verifyResult: true,
        );
        final reportRepository = FakeAdminProductReportRepository(
          getHandler: (reportId) async {
            return makeReportDetail(
              id: reportId,
              details: null,
              evidenceImageUrls: const [],
              currentProduct: null,
              adminNote: null,
            );
          },
          updateHandler:
              ({required reportId, required status, String? adminNote}) async {
                return makeReportDetail(
                  id: reportId,
                  details: null,
                  evidenceImageUrls: const [],
                  currentProduct: null,
                  status: status,
                  adminNote: adminNote,
                );
              },
        );
        addTearDown(authRepository.dispose);

        await _pumpAdminWidget(
          tester,
          authRepository: authRepository,
          reportRepository: reportRepository,
          child: const AdminProductReportDetailPage(reportId: 'report-2'),
        );

        expect(find.text('Kullanıcı açıklama eklememiş.'), findsOneWidget);
        expect(find.text('Kanıt görseli eklenmemiş.'), findsOneWidget);
        expect(
          find.text('Ürün mevcut veritabanında bulunamıyor.'),
          findsOneWidget,
        );

        final saveButton = find
            .byKey(const ValueKey('admin-report-note-save'))
            .first;
        expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);

        await tester.enterText(
          find.byKey(const ValueKey('admin-report-note-field')),
          'Yeni yönetici notu',
        );
        await tester.pump();

        expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);
      },
    );
  });
}

Future<void> _pumpAdminWidget(
  WidgetTester tester, {
  required FakeAdminAuthRepository authRepository,
  FakeAdminProductReportRepository? reportRepository,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(authRepository),
        if (reportRepository != null)
          adminProductReportRepositoryProvider.overrideWithValue(
            reportRepository,
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(useGoogleFonts: false),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return '.';
      });
}
