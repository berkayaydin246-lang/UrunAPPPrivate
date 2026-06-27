import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/services/app_installation_id_service.dart';

void main() {
  group('AppInstallationIdService', () {
    test('returns the same generated ID across repeated reads', () async {
      final storage = _InMemoryAppInstallationIdStorage();
      final service = AppInstallationIdService(
        storage: storage,
        uuidGenerator: () => _installationIdA,
      );

      final first = await service.getOrCreateInstallationId();
      final second = await service.getOrCreateInstallationId();

      expect(first, _installationIdA);
      expect(second, _installationIdA);
      expect(storage.writeCount, 1);
      expect(storage.values[kAppInstallationIdStorageKey], _installationIdA);
    });

    test('concurrent calls reuse the same in-flight generation', () async {
      final storage = _InMemoryAppInstallationIdStorage();
      var generatorCallCount = 0;
      final service = AppInstallationIdService(
        storage: storage,
        uuidGenerator: () {
          generatorCallCount += 1;
          return _installationIdA;
        },
      );

      final results = await Future.wait([
        service.getOrCreateInstallationId(),
        service.getOrCreateInstallationId(),
        service.getOrCreateInstallationId(),
      ]);

      expect(results, [_installationIdA, _installationIdA, _installationIdA]);
      expect(generatorCallCount, 1);
      expect(storage.writeCount, 1);
    });

    test(
      'persists across service instances that share the same storage',
      () async {
        final storage = _InMemoryAppInstallationIdStorage();
        final firstService = AppInstallationIdService(
          storage: storage,
          uuidGenerator: () => _installationIdA,
        );
        final secondService = AppInstallationIdService(
          storage: storage,
          uuidGenerator: () => _installationIdB,
        );

        expect(
          await firstService.getOrCreateInstallationId(),
          _installationIdA,
        );
        expect(
          await secondService.getOrCreateInstallationId(),
          _installationIdA,
        );
        expect(storage.writeCount, 1);
      },
    );

    test('reuses a trimmed stored ID without regenerating', () async {
      final storage = _InMemoryAppInstallationIdStorage(
        initialValues: {kAppInstallationIdStorageKey: '  $_installationIdA  '},
      );
      var generatorCalled = false;
      final service = AppInstallationIdService(
        storage: storage,
        uuidGenerator: () {
          generatorCalled = true;
          return _installationIdB;
        },
      );

      final installationId = await service.getOrCreateInstallationId();

      expect(installationId, _installationIdA);
      expect(generatorCalled, isFalse);
      expect(storage.writeCount, 0);
    });
  });
}

class _InMemoryAppInstallationIdStorage implements AppInstallationIdStorage {
  _InMemoryAppInstallationIdStorage({Map<String, String>? initialValues})
    : values = <String, String>{...?initialValues};

  final Map<String, String> values;
  int writeCount = 0;

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    writeCount += 1;
    values[key] = value;
  }
}

const _installationIdA = '11111111-1111-4111-8111-111111111111';
const _installationIdB = '22222222-2222-4222-8222-222222222222';
