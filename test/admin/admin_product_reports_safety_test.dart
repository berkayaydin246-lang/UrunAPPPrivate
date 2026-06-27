import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin product reports safety checks', () {
    late final List<File> dartFiles;
    late final Map<String, String> fileContents;

    setUpAll(() {
      dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList(growable: false);
      fileContents = {
        for (final file in dartFiles) file.path: file.readAsStringSync(),
      };
    });

    test('Flutter code has no direct product_reports table query', () {
      for (final entry in fileContents.entries) {
        expect(
          entry.value.contains(".from('product_reports')") ||
              entry.value.contains('.from("product_reports")'),
          isFalse,
          reason: 'Direct product_reports table access found in ${entry.key}',
        );
      }
    });

    test('Flutter code contains no privileged service-role key references', () {
      for (final entry in fileContents.entries) {
        expect(
          entry.value.contains('service_role') ||
              entry.value.contains('SUPABASE_SERVICE_ROLE'),
          isFalse,
          reason: 'Privileged key reference found in ${entry.key}',
        );
      }
    });

    test(
      'admin authorization does not use user_metadata as the trust boundary',
      () {
        final adminFiles = fileContents.entries.where(
          (entry) => entry.key.contains('/features/admin/'),
        );
        for (final entry in adminFiles) {
          expect(
            entry.value.contains('user_metadata'),
            isFalse,
            reason: 'user_metadata reference found in ${entry.key}',
          );
        }
      },
    );

    test('admin auth verifies authorization through the trusted RPC', () {
      final authRepository = File(
        'lib/features/admin/repositories/admin_auth_repository.dart',
      ).readAsStringSync();
      expect(authRepository, contains("rpc('is_freshscan_admin')"));
    });

    test('admin authorization provider is not autoDispose', () {
      final controller = File(
        'lib/features/admin/controllers/admin_authorization_controller.dart',
      ).readAsStringSync();
      expect(controller, contains('StateNotifierProvider<'));
      expect(controller.contains('StateNotifierProvider.autoDispose'), isFalse);
    });

    test('Flutter app loads only the client-safe env asset', () {
      final mainFile = File('lib/main.dart').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(mainFile, contains("dotenv.load(fileName: _appEnvFile)"));
      expect(mainFile, contains("const _appEnvFile = '.env.client';"));
      expect(pubspec, contains('- .env.client'));
      expect(pubspec.contains('\n    - .env\n'), isFalse);
    });

    test('legacy home page has no public Ürün Bildirimleri shortcut', () {
      final homePage = File(
        'lib/features/home/home_page.dart',
      ).readAsStringSync();
      expect(homePage, isNot(contains('Ürün Bildirimleri')));
    });
  });
}
