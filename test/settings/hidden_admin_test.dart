import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:food_analyzer_app/features/admin/pages/admin_home_page.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';
import 'package:food_analyzer_app/features/admin/widgets/admin_authorization_gate.dart';
import 'package:food_analyzer_app/features/settings/pages/settings_page.dart';
import 'package:food_analyzer_app/main.dart';

import '../admin/helpers/admin_product_reports_test_helpers.dart';

// ── Settings page unit tests ──────────────────────────────────────────────────

Widget _buildSettings() {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/internal/admin',
        name: 'admin_home',
        builder: (_, _) => const Scaffold(body: Text('admin_sentinel')),
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('SettingsPage', () {
    testWidgets('renders app brand and version', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      expect(find.text('Etiketly'), findsOneWidget);
      expect(find.text('Etiketi tara, içeriği anla.'), findsOneWidget);
      expect(find.text('Sürüm 1.0.0'), findsOneWidget);
    });

    testWidgets('no Admin text visible in settings', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      expect(find.textContaining('Admin'), findsNothing);
      expect(find.textContaining('Yönetici'), findsNothing);
    });

    testWidgets('7 taps on version text opens admin route', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      final versionText = find.text('Sürüm 1.0.0');
      for (var i = 0; i < 7; i++) {
        await tester.tap(versionText);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('admin_sentinel'), findsOneWidget);
    });

    testWidgets('fewer than 7 taps does not navigate to admin', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      final versionText = find.text('Sürüm 1.0.0');
      for (var i = 0; i < 6; i++) {
        await tester.tap(versionText);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('admin_sentinel'), findsNothing);
      expect(find.text('Sürüm 1.0.0'), findsOneWidget); // still on settings
    });

    testWidgets('legal rows are visible and "Yakında" is gone', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      expect(find.text('Gizlilik Politikası'), findsOneWidget);
      expect(find.text('Kullanım Şartları'), findsOneWidget);
      expect(find.text('İletişim / Veri Silme Talebi'), findsOneWidget);
      expect(find.text('Yakında'), findsNothing);
    });

    testWidgets('legal rows have trailing open-in-new icon', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.open_in_new_rounded), findsWidgets);
    });

    // url_launcher silently succeeds in the test environment (no platform mock),
    // so SnackBar assertions are not practical. We verify no crash instead.
    testWidgets('tapping Gizlilik Politikası does not crash', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gizlilik Politikası'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Kullanım Şartları does not crash', (tester) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kullanım Şartları'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping İletişim / Veri Silme Talebi does not crash', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSettings());
      await tester.pumpAndSettle();

      await tester.tap(find.text('İletişim / Veri Silme Talebi'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // ── Consumer navigation tests ──────────────────────────────────────────────

  group('Consumer navigation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'etiketly_onboarding_completed_v1': true,
      });
    });

    testWidgets('bottom navigation shows only Ara and Barkod', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MyApp()));
      await tester.pumpAndSettle();

      expect(find.text('Ara'), findsOneWidget);
      expect(find.text('Barkod'), findsOneWidget);
      expect(find.text('Admin'), findsNothing);
    });

    testWidgets('home screen has no admin or Yönetim section', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MyApp()));
      await tester.pumpAndSettle();

      // Verify search page loaded; navigate to / (home) would require extra
      // routing; check the search page has no admin text.
      expect(find.textContaining('Yönetim'), findsNothing);
      expect(find.textContaining('Staging Ürünleri'), findsNothing);
      expect(find.textContaining('OCR Benchmark'), findsNothing);
    });
  });

  // ── Admin route integrity tests ────────────────────────────────────────────

  group('Admin route', () {
    testWidgets('admin home still renders authorization gate', (tester) async {
      // Use FakeAdminAuthRepository so AdminAuthorizationGate can render
      // without a real Supabase instance (no credentials in tests).
      final fakeAuth = FakeAdminAuthRepository();
      addTearDown(fakeAuth.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminAuthRepositoryProvider.overrideWithValue(fakeAuth)],
          child: MaterialApp(home: const AdminHomePage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // AdminAuthorizationGate must be present — it guards admin content
      expect(find.byType(AdminAuthorizationGate), findsOneWidget);
    });
  });
}
