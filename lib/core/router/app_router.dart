import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/home/home_page.dart';
import 'package:food_analyzer_app/features/search/search_page.dart';
import 'package:food_analyzer_app/features/barcode/barcode_page.dart';
import 'package:food_analyzer_app/features/product/product_page.dart';
import 'package:food_analyzer_app/features/ocr/ocr_page.dart';
import 'package:food_analyzer_app/features/ocr/pages/ocr_benchmark_page.dart';
import 'package:food_analyzer_app/features/analysis/analysis_page.dart';
import 'package:food_analyzer_app/features/analysis/models/analysis_route_args.dart';
import 'package:food_analyzer_app/features/history/history_page.dart';
import 'package:food_analyzer_app/features/admin/models/user_submission.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_review_list_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_review_detail_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_home_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_product_reports_page.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_product_report_detail_page.dart';
import 'package:food_analyzer_app/features/admin/pages/product_submission_list_page.dart';
import 'package:food_analyzer_app/features/admin/pages/product_submission_detail_page.dart';
import 'package:food_analyzer_app/features/admin/pages/product_staging_list_page.dart';
import 'package:food_analyzer_app/features/admin/pages/product_staging_detail_page.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/pages/comparison_product_picker_page.dart';
import 'package:food_analyzer_app/features/comparison/pages/product_comparison_page.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/pages/category_products_page.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/search',
    routes: <RouteBase>[
      // ── Main shell — bottom navigation bar ──────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          // Branch 0: Product Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'search',
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          // Branch 1: Barcode Scanner
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'barcode',
                path: '/barcode',
                builder: (context, state) => const BarcodeScreen(),
              ),
            ],
          ),
          // Branch 2: Admin — secure admin menu
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'admin_home',
                path: '/internal/admin',
                builder: (context, state) => const AdminHomePage(),
              ),
            ],
          ),
        ],
      ),

      // ── Routes outside the shell (full-screen, no bottom nav) ───────────────
      GoRoute(
        name: 'home',
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        name: 'product',
        path: '/product/:id',
        builder: (context, state) =>
            ProductScreen(productId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        name: 'comparison_picker',
        path: '/product/:id/compare',
        builder: (context, state) => ComparisonProductPickerPage(
          routeArgs: state.extra is ComparisonPickerRouteArgs
              ? state.extra as ComparisonPickerRouteArgs
              : ComparisonPickerRouteArgs(
                  sourceProductId: state.pathParameters['id'] ?? '',
                ),
        ),
      ),
      GoRoute(
        name: 'product_comparison',
        path: '/product/:id/compare/:otherId',
        builder: (context, state) => ProductComparisonPage(
          routeArgs: state.extra is ProductComparisonRouteArgs
              ? state.extra as ProductComparisonRouteArgs
              : ProductComparisonRouteArgs(
                  sourceProductId: state.pathParameters['id'] ?? '',
                  comparedProductId: state.pathParameters['otherId'] ?? '',
                ),
        ),
      ),
      GoRoute(
        name: 'category_products',
        path: '/category/:id',
        builder: (context, state) {
          final category = state.extra is ProductCategory
              ? state.extra as ProductCategory
              : ProductCategories.findById(state.pathParameters['id'] ?? '');
          if (category == null) {
            return const Scaffold(
              body: Center(child: Text('Kategori bulunamadı.')),
            );
          }
          return CategoryProductsPage(category: category);
        },
      ),
      GoRoute(
        name: 'ocr',
        path: '/ocr',
        builder: (context, state) => const OcrScreen(),
      ),
      GoRoute(
        name: 'analysis',
        path: '/analysis',
        builder: (context, state) {
          final args = state.extra is AnalysisRouteArgs
              ? state.extra as AnalysisRouteArgs
              : null;
          return AnalysisScreen(routeArgs: args);
        },
      ),
      GoRoute(
        name: 'history',
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        name: 'product_staging_review',
        path: '/internal/product-staging',
        builder: (context, state) => const ProductStagingListPage(),
      ),
      GoRoute(
        name: 'product_submission_review',
        path: '/internal/product-submissions',
        builder: (context, state) => const ProductSubmissionListPage(),
      ),
      GoRoute(
        name: 'admin_product_reports',
        path: '/internal/admin/product-reports',
        builder: (context, state) => const AdminProductReportsPage(),
      ),
      GoRoute(
        name: 'admin_product_report_detail',
        path: '/internal/admin/product-reports/:id',
        builder: (context, state) => AdminProductReportDetailPage(
          reportId: state.pathParameters['id'] ?? '',
        ),
      ),
      // Staging detail is a full-screen push (no bottom nav)
      GoRoute(
        name: 'product_staging_review_detail',
        path: '/internal/product-staging/:id',
        builder: (context, state) => ProductStagingDetailPage(
          stagingId: state.pathParameters['id'] ?? '',
          candidate: state.extra is ProductCandidate
              ? state.extra as ProductCandidate
              : null,
        ),
      ),
      GoRoute(
        name: 'admin_review',
        path: '/internal/review',
        builder: (context, state) => const AdminReviewListPage(),
      ),
      GoRoute(
        name: 'admin_review_detail',
        path: '/internal/review/:id',
        builder: (context, state) => AdminReviewDetailPage(
          submissionId: state.pathParameters['id'] ?? '',
          submission: state.extra is UserSubmission
              ? state.extra as UserSubmission
              : null,
        ),
      ),
      GoRoute(
        name: 'ocr_benchmark',
        path: '/internal/ocr-benchmark',
        builder: (context, state) => const OcrBenchmarkPage(),
      ),
      GoRoute(
        name: 'product_submission_review_detail',
        path: '/internal/product-submissions/:id',
        builder: (context, state) => ProductSubmissionDetailPage(
          submissionId: state.pathParameters['id'] ?? '',
          submission: state.extra is ProductSubmission
              ? state.extra as ProductSubmission
              : null,
        ),
      ),
    ],
  );
}

/// Bottom-navigation shell that wraps the three main tab branches.
///
/// Tapping a tab that is already active scrolls back to root (by passing
/// initialLocation: true), matching standard tab-bar behaviour.
class _AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _AppShell({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: navigationShell.currentIndex,
            onTap: (index) => navigationShell.goBranch(
              index,
              // Re-tapping the active tab resets it to its root route.
              initialLocation: index == navigationShell.currentIndex,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.search_rounded),
                activeIcon: Icon(Icons.search_rounded),
                label: 'Ara',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.qr_code_scanner_rounded),
                activeIcon: Icon(Icons.qr_code_scanner_rounded),
                label: 'Barkod',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings_outlined),
                activeIcon: Icon(Icons.admin_panel_settings_rounded),
                label: 'Admin',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
