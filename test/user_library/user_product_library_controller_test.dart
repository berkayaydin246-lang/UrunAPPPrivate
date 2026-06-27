import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/user_library/controllers/user_product_library_controller.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

void main() {
  group('User library controllers', () {
    test('favorite state exposes per-product favorite status', () async {
      final clock = _Clock();
      final repository = LocalUserProductLibraryRepository(
        storage: _MemoryStorage(),
        clock: clock.call,
      );
      final container = ProviderContainer(
        overrides: [
          userProductLibraryRepositoryProvider.overrideWithValue(repository),
          userProductLibraryClockProvider.overrideWithValue(clock.call),
        ],
      );
      addTearDown(container.dispose);

      await _flush();
      expect(container.read(isProductFavoriteProvider('cola')), isFalse);

      await container
          .read(favoriteProductsProvider.notifier)
          .addFavorite(_snapshot('cola'));

      expect(container.read(isProductFavoriteProvider('cola')), isTrue);
      expect(container.read(isProductFavoriteProvider('ayran')), isFalse);
    });

    test(
      'recordViewedProduct updates viewed state immediately and preserves scanned and favorites',
      () async {
        final repositoryClock = _Clock();
        final controllerClock = _Clock();
        final storage = _MemoryStorage(
          writeDelay: const Duration(milliseconds: 20),
        );
        final repository = LocalUserProductLibraryRepository(
          storage: storage,
          clock: repositoryClock.call,
        );
        final container = ProviderContainer(
          overrides: [
            userProductLibraryRepositoryProvider.overrideWithValue(repository),
            userProductLibraryClockProvider.overrideWithValue(
              controllerClock.call,
            ),
          ],
        );
        addTearDown(container.dispose);

        await _flush();
        await container
            .read(favoriteProductsProvider.notifier)
            .addFavorite(_snapshot('fav'));
        await container
            .read(recentProductActivityProvider.notifier)
            .recordScannedProduct(_snapshot('scan'));

        final writeFuture = container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(_snapshot('viewed'));

        final viewedEntries = container.read(
          viewedProductActivityEntriesProvider,
        );
        final scannedEntries = container.read(
          scannedProductActivityEntriesProvider,
        );
        final favoriteIds = container.read(favoriteProductIdsProvider);

        expect(viewedEntries, hasLength(1));
        expect(viewedEntries.first.product.productId, 'viewed');
        expect(scannedEntries, hasLength(1));
        expect(scannedEntries.first.product.productId, 'scan');
        expect(favoriteIds, contains('fav'));

        await writeFuture;

        final raw = storage.values[kUserProductLibraryStorageKey];
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        final activity = decoded['activity'] as List<dynamic>;
        expect(
          activity.any((entry) {
            final product = entry['product'] as Map<String, dynamic>;
            return product['productId'] == 'viewed';
          }),
          isTrue,
        );
      },
    );

    test(
      're-viewing the same product moves it to index 0 without duplication',
      () async {
        final clock = _Clock();
        final repository = LocalUserProductLibraryRepository(
          storage: _MemoryStorage(),
          clock: clock.call,
        );
        final container = ProviderContainer(
          overrides: [
            userProductLibraryRepositoryProvider.overrideWithValue(repository),
            userProductLibraryClockProvider.overrideWithValue(_Clock().call),
          ],
        );
        addTearDown(container.dispose);

        await _flush();
        await container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(_snapshot('cola'));
        await container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(_snapshot('ayran'));
        await container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(_snapshot('cola'));

        final viewedEntries = container.read(
          viewedProductActivityEntriesProvider,
        );
        expect(viewedEntries.map((entry) => entry.product.productId), [
          'cola',
          'ayran',
        ]);
      },
    );

    test(
      'recordScannedProduct updates scanned state immediately and leaves viewed state untouched',
      () async {
        final repositoryClock = _Clock();
        final controllerClock = _Clock();
        final repository = LocalUserProductLibraryRepository(
          storage: _MemoryStorage(writeDelay: const Duration(milliseconds: 20)),
          clock: repositoryClock.call,
        );
        final container = ProviderContainer(
          overrides: [
            userProductLibraryRepositoryProvider.overrideWithValue(repository),
            userProductLibraryClockProvider.overrideWithValue(
              controllerClock.call,
            ),
          ],
        );
        addTearDown(container.dispose);

        await _flush();
        await container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(_snapshot('cola'));

        final writeFuture = container
            .read(recentProductActivityProvider.notifier)
            .recordScannedProduct(_snapshot('scan'));

        final viewedEntries = container.read(
          viewedProductActivityEntriesProvider,
        );
        final scannedEntries = container.read(
          scannedProductActivityEntriesProvider,
        );

        expect(viewedEntries.map((entry) => entry.product.productId), ['cola']);
        expect(scannedEntries.map((entry) => entry.product.productId), [
          'scan',
        ]);

        await writeFuture;
      },
    );

    test(
      'persistence failure rolls back optimistic viewed state without corrupting existing records',
      () async {
        final repositoryClock = _Clock();
        final controllerClock = _Clock();
        final storage = _MemoryStorage();
        final repository = LocalUserProductLibraryRepository(
          storage: storage,
          clock: repositoryClock.call,
        );
        final container = ProviderContainer(
          overrides: [
            userProductLibraryRepositoryProvider.overrideWithValue(repository),
            userProductLibraryClockProvider.overrideWithValue(
              controllerClock.call,
            ),
          ],
        );
        addTearDown(container.dispose);

        await _flush();
        await container
            .read(recentProductActivityProvider.notifier)
            .recordScannedProduct(_snapshot('scan'));

        storage.failWrites = true;

        await expectLater(
          container
              .read(recentProductActivityProvider.notifier)
              .recordViewedProduct(_snapshot('viewed')),
          throwsA(isA<StateError>()),
        );

        expect(container.read(viewedProductActivityEntriesProvider), isEmpty);
        expect(
          container
              .read(scannedProductActivityEntriesProvider)
              .map((entry) => entry.product.productId),
          ['scan'],
        );

        storage.failWrites = false;
        final restartedContainer = ProviderContainer(
          overrides: [
            userProductLibraryRepositoryProvider.overrideWithValue(
              LocalUserProductLibraryRepository(
                storage: storage,
                clock: _Clock().call,
              ),
            ),
            userProductLibraryClockProvider.overrideWithValue(_Clock().call),
          ],
        );
        addTearDown(restartedContainer.dispose);

        restartedContainer.read(recentProductActivityProvider.notifier);
        await _flush();
        expect(
          restartedContainer.read(viewedProductActivityEntriesProvider),
          isEmpty,
        );
        expect(
          restartedContainer
              .read(scannedProductActivityEntriesProvider)
              .map((entry) => entry.product.productId),
          ['scan'],
        );
      },
    );

    test('restart restores persisted viewed and scanned records', () async {
      final storage = _MemoryStorage();
      final repository = LocalUserProductLibraryRepository(
        storage: storage,
        clock: _Clock().call,
      );
      final firstContainer = ProviderContainer(
        overrides: [
          userProductLibraryRepositoryProvider.overrideWithValue(repository),
          userProductLibraryClockProvider.overrideWithValue(_Clock().call),
        ],
      );
      addTearDown(firstContainer.dispose);

      await _flush();
      await firstContainer
          .read(recentProductActivityProvider.notifier)
          .recordViewedProduct(_snapshot('cola'));
      await firstContainer
          .read(recentProductActivityProvider.notifier)
          .recordScannedProduct(_snapshot('scan'));

      final secondContainer = ProviderContainer(
        overrides: [
          userProductLibraryRepositoryProvider.overrideWithValue(
            LocalUserProductLibraryRepository(
              storage: storage,
              clock: _Clock().call,
            ),
          ),
          userProductLibraryClockProvider.overrideWithValue(_Clock().call),
        ],
      );
      addTearDown(secondContainer.dispose);

      secondContainer.read(recentProductActivityProvider.notifier);
      await _flush();

      expect(
        secondContainer
            .read(viewedProductActivityEntriesProvider)
            .map((entry) => entry.product.productId),
        ['cola'],
      );
      expect(
        secondContainer
            .read(scannedProductActivityEntriesProvider)
            .map((entry) => entry.product.productId),
        ['scan'],
      );
    });

    test('recent activity provider loads and filters local activity', () async {
      final repository = LocalUserProductLibraryRepository(
        storage: _MemoryStorage(),
        clock: _Clock().call,
      );
      final container = ProviderContainer(
        overrides: [
          userProductLibraryRepositoryProvider.overrideWithValue(repository),
          userProductLibraryClockProvider.overrideWithValue(_Clock().call),
        ],
      );
      addTearDown(container.dispose);

      await _flush();
      await container
          .read(recentProductActivityProvider.notifier)
          .recordViewedProduct(_snapshot('cola'));
      await container
          .read(recentProductActivityProvider.notifier)
          .recordScannedProduct(_snapshot('cola'));

      final allEntries = container.read(recentProductActivityEntriesProvider);
      final viewedOnly = container.read(
        filteredRecentProductActivityProvider(
          const RecentProductActivityQuery(type: ProductActivityType.viewed),
        ),
      );

      expect(allEntries, hasLength(2));
      expect(viewedOnly, hasLength(1));
      expect(viewedOnly.single.type, ProductActivityType.viewed);
    });
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

LocalProductSnapshot _snapshot(String productId) {
  return LocalProductSnapshot(
    productId: productId,
    name: 'Product $productId',
    brand: null,
    imageUrl: null,
    categoryTags: const ['icecek'],
  );
}

class _Clock {
  _Clock() : _current = DateTime.utc(2026, 6, 26, 14);

  DateTime _current;

  DateTime call() {
    final result = _current;
    _current = _current.add(const Duration(minutes: 1));
    return result;
  }
}

class _MemoryStorage implements UserProductLibraryStorage {
  _MemoryStorage({this.writeDelay = Duration.zero});

  final Duration writeDelay;
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    if (failWrites) {
      throw StateError('Failed to persist user product library state');
    }
    values[key] = value;
  }
}
