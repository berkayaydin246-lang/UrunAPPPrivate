import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

void main() {
  group('LocalUserProductLibraryRepository', () {
    test('missing local storage returns empty favorites and history', () async {
      final repository = _buildRepository();

      expect(await repository.getFavorites(), isEmpty);
      expect(await repository.getRecentActivity(), isEmpty);
      expect(await repository.isFavorite('p1'), isFalse);
    });

    test('a product can be added to favorites', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');

      await repository.addFavorite(cola);

      final favorites = await repository.getFavorites();
      expect(favorites, hasLength(1));
      expect(favorites.single.product, cola);
      expect(await repository.isFavorite('cola'), isTrue);
    });

    test('adding the same favorite twice does not duplicate it', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');

      await repository.addFavorite(cola);
      await repository.addFavorite(cola.copyWith(name: 'Coca Cola Zero'));

      final favorites = await repository.getFavorites();
      expect(favorites, hasLength(1));
      expect(favorites.single.product.name, 'Coca Cola Zero');
    });

    test('removing a missing favorite does not fail', () async {
      final repository = _buildRepository();

      await repository.removeFavorite('missing-product');

      expect(await repository.getFavorites(), isEmpty);
    });

    test('toggleFavorite returns the final favorite state', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');

      expect(await repository.toggleFavorite(cola), isTrue);
      expect(await repository.toggleFavorite(cola), isFalse);
      expect(await repository.isFavorite('cola'), isFalse);
    });

    test('favorites are ordered newest first', () async {
      final repository = _buildRepository();

      await repository.addFavorite(_snapshot('first'));
      await repository.addFavorite(_snapshot('second'));

      final favorites = await repository.getFavorites();
      expect(favorites.map((entry) => entry.product.productId), [
        'second',
        'first',
      ]);
    });

    test('viewing the same product twice moves it to the top', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');
      final ayran = _snapshot('ayran');

      await repository.recordViewedProduct(cola);
      await repository.recordViewedProduct(ayran);
      await repository.recordViewedProduct(cola.copyWith(name: 'Coca Cola 2'));

      final activity = await repository.getRecentActivity(
        type: ProductActivityType.viewed,
      );
      expect(activity, hasLength(2));
      expect(activity.first.product.productId, 'cola');
      expect(activity.first.product.name, 'Coca Cola 2');
    });

    test('scanning the same product twice moves it to the top', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');
      final ayran = _snapshot('ayran');

      await repository.recordScannedProduct(cola);
      await repository.recordScannedProduct(ayran);
      await repository.recordScannedProduct(cola.copyWith(name: 'Cola Scan 2'));

      final activity = await repository.getRecentActivity(
        type: ProductActivityType.scanned,
      );
      expect(activity, hasLength(2));
      expect(activity.first.product.productId, 'cola');
      expect(activity.first.product.name, 'Cola Scan 2');
    });

    test(
      'viewed and scanned entries for the same product can coexist',
      () async {
        final repository = _buildRepository();
        final cola = _snapshot('cola');

        await repository.recordViewedProduct(cola);
        await repository.recordScannedProduct(cola);

        final allActivity = await repository.getRecentActivity();
        expect(allActivity, hasLength(2));
        expect(
          allActivity.map((entry) => entry.type),
          containsAll([
            ProductActivityType.viewed,
            ProductActivityType.scanned,
          ]),
        );
      },
    );

    test('viewed history is capped at 100', () async {
      final repository = _buildRepository();

      for (
        var index = 0;
        index < kMaxViewedProductActivityEntries + 5;
        index++
      ) {
        await repository.recordViewedProduct(_snapshot('viewed-$index'));
      }

      final viewed = await repository.getRecentActivity(
        type: ProductActivityType.viewed,
      );
      expect(viewed, hasLength(kMaxViewedProductActivityEntries));
      expect(viewed.first.product.productId, 'viewed-104');
      expect(viewed.last.product.productId, 'viewed-5');
    });

    test('scanned history is capped at 100', () async {
      final repository = _buildRepository();

      for (
        var index = 0;
        index < kMaxScannedProductActivityEntries + 5;
        index++
      ) {
        await repository.recordScannedProduct(_snapshot('scanned-$index'));
      }

      final scanned = await repository.getRecentActivity(
        type: ProductActivityType.scanned,
      );
      expect(scanned, hasLength(kMaxScannedProductActivityEntries));
      expect(scanned.first.product.productId, 'scanned-104');
      expect(scanned.last.product.productId, 'scanned-5');
    });

    test('history trimming never removes favorites', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');

      await repository.addFavorite(cola);
      for (
        var index = 0;
        index < kMaxViewedProductActivityEntries + 10;
        index++
      ) {
        await repository.recordViewedProduct(_snapshot('viewed-$index'));
      }

      final favorites = await repository.getFavorites();
      expect(favorites, hasLength(1));
      expect(favorites.single.product.productId, 'cola');
    });

    test('clearing viewed history does not clear scanned history', () async {
      final repository = _buildRepository();

      await repository.recordViewedProduct(_snapshot('viewed'));
      await repository.recordScannedProduct(_snapshot('scanned'));
      await repository.clearRecentActivity(type: ProductActivityType.viewed);

      expect(
        await repository.getRecentActivity(type: ProductActivityType.viewed),
        isEmpty,
      );
      expect(
        await repository.getRecentActivity(type: ProductActivityType.scanned),
        hasLength(1),
      );
    });

    test('clearing scanned history does not clear viewed history', () async {
      final repository = _buildRepository();

      await repository.recordViewedProduct(_snapshot('viewed'));
      await repository.recordScannedProduct(_snapshot('scanned'));
      await repository.clearRecentActivity(type: ProductActivityType.scanned);

      expect(
        await repository.getRecentActivity(type: ProductActivityType.scanned),
        isEmpty,
      );
      expect(
        await repository.getRecentActivity(type: ProductActivityType.viewed),
        hasLength(1),
      );
    });

    test('clearing all activity does not remove favorites', () async {
      final repository = _buildRepository();
      final cola = _snapshot('cola');

      await repository.addFavorite(cola);
      await repository.recordViewedProduct(cola);
      await repository.recordScannedProduct(cola);
      await repository.clearRecentActivity();

      expect(await repository.getRecentActivity(), isEmpty);
      expect(await repository.getFavorites(), hasLength(1));
    });

    test('malformed individual records are skipped safely', () async {
      final storage = _InMemoryUserProductLibraryStorage(
        initialValues: {
          kUserProductLibraryStorageKey: jsonEncode({
            'schemaVersion': 1,
            'favorites': [
              {
                'product': _snapshot('valid-favorite').toJson(),
                'addedAt': '2026-06-26T12:00:00Z',
              },
              {
                'product': {'name': 'Missing id'},
                'addedAt': '2026-06-26T12:01:00Z',
              },
              {
                'product': _snapshot('bad-timestamp').toJson(),
                'addedAt': 'not-a-date',
              },
            ],
            'activity': [
              {
                'product': _snapshot('valid-activity').toJson(),
                'type': 'viewed',
                'occurredAt': '2026-06-26T12:02:00Z',
              },
              {
                'product': _snapshot('bad-type').toJson(),
                'type': 'unknown',
                'occurredAt': '2026-06-26T12:03:00Z',
              },
              {
                'product': _snapshot('bad-date').toJson(),
                'type': 'scanned',
                'occurredAt': 'bad-date',
              },
            ],
          }),
        },
      );
      final repository = _buildRepository(storage: storage);

      final favorites = await repository.getFavorites();
      final activity = await repository.getRecentActivity();

      expect(favorites, hasLength(1));
      expect(favorites.single.product.productId, 'valid-favorite');
      expect(activity, hasLength(1));
      expect(activity.single.product.productId, 'valid-activity');
    });

    test('storage schema version is persisted', () async {
      final storage = _InMemoryUserProductLibraryStorage();
      final repository = _buildRepository(storage: storage);

      await repository.addFavorite(_snapshot('cola'));

      final raw = storage.values[kUserProductLibraryStorageKey];
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], kUserProductLibrarySchemaVersion);
    });

    test('snapshot conversion handles missing brand and image', () {
      final now = DateTime.utc(2026, 6, 26);
      final product = Product(
        id: 'p1',
        name: 'Sade Kraker',
        brand: null,
        imageUrl: null,
        categoryTags: null,
        verificationStatus: 'verified',
        createdAt: now,
        updatedAt: now,
      );

      final snapshot = localSnapshotFromProduct(product);

      expect(snapshot.productId, 'p1');
      expect(snapshot.brand, isNull);
      expect(snapshot.imageUrl, isNull);
      expect(snapshot.categoryTags, isEmpty);
    });

    test('concurrent writes do not lose records', () async {
      final storage = _InMemoryUserProductLibraryStorage(
        writeDelay: const Duration(milliseconds: 2),
      );
      final repository = _buildRepository(storage: storage);

      await Future.wait([
        repository.addFavorite(_snapshot('fav-1')),
        repository.addFavorite(_snapshot('fav-2')),
        repository.recordViewedProduct(_snapshot('view-1')),
        repository.recordViewedProduct(_snapshot('view-2')),
        repository.recordScannedProduct(_snapshot('scan-1')),
      ]);

      final favorites = await repository.getFavorites();
      final viewed = await repository.getRecentActivity(
        type: ProductActivityType.viewed,
      );
      final scanned = await repository.getRecentActivity(
        type: ProductActivityType.scanned,
      );

      expect(favorites.map((entry) => entry.product.productId).toSet(), {
        'fav-1',
        'fav-2',
      });
      expect(viewed.map((entry) => entry.product.productId).toSet(), {
        'view-1',
        'view-2',
      });
      expect(scanned.map((entry) => entry.product.productId).toSet(), {
        'scan-1',
      });
    });

    test(
      'unsupported future schema version fails safely with empty state',
      () async {
        final storage = _InMemoryUserProductLibraryStorage(
          initialValues: {
            kUserProductLibraryStorageKey: jsonEncode({
              'schemaVersion': 99,
              'favorites': [
                {
                  'product': _snapshot('cola').toJson(),
                  'addedAt': '2026-06-26T12:00:00Z',
                },
              ],
              'activity': [],
            }),
          },
        );
        final repository = _buildRepository(storage: storage);

        expect(await repository.getFavorites(), isEmpty);
        expect(await repository.getRecentActivity(), isEmpty);
      },
    );

    test(
      'unsupported future schema is not overwritten during read-only startup',
      () async {
        final rawPayload = jsonEncode({
          'schemaVersion': 99,
          'favorites': [
            {
              'product': _snapshot('cola').toJson(),
              'addedAt': '2026-06-26T12:00:00Z',
            },
          ],
          'activity': [
            {
              'product': _snapshot('scan-1').toJson(),
              'type': 'scanned',
              'occurredAt': '2026-06-26T12:02:00Z',
            },
          ],
        });
        final storage = _InMemoryUserProductLibraryStorage(
          initialValues: {kUserProductLibraryStorageKey: rawPayload},
        );
        final repository = _buildRepository(storage: storage);

        expect(await repository.getFavorites(), isEmpty);
        expect(await repository.getRecentActivity(), isEmpty);
        expect(storage.values[kUserProductLibraryStorageKey], rawPayload);
      },
    );
  });
}

LocalUserProductLibraryRepository _buildRepository({
  _InMemoryUserProductLibraryStorage? storage,
}) {
  return LocalUserProductLibraryRepository(
    storage: storage ?? _InMemoryUserProductLibraryStorage(),
    clock: _TestClock().call,
  );
}

LocalProductSnapshot _snapshot(String productId) {
  return LocalProductSnapshot(
    productId: productId,
    name: 'Product $productId',
    brand: 'Brand $productId',
    imageUrl: 'https://example.com/$productId.png',
    categoryTags: const ['atistirmalik'],
  );
}

class _TestClock {
  _TestClock() : _current = DateTime.utc(2026, 6, 26, 12);

  DateTime _current;

  DateTime call() {
    final result = _current;
    _current = _current.add(const Duration(minutes: 1));
    return result;
  }
}

class _InMemoryUserProductLibraryStorage implements UserProductLibraryStorage {
  _InMemoryUserProductLibraryStorage({
    Map<String, String>? initialValues,
    this.writeDelay = Duration.zero,
  }) : values = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> values;
  final Duration writeDelay;

  @override
  Future<String?> readString(String key) async {
    return values[key];
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    values[key] = value;
  }
}
