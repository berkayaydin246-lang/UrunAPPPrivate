import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kUserProductLibrarySchemaVersion = 1;
const kMaxViewedProductActivityEntries = 100;
const kMaxScannedProductActivityEntries = 100;
const kUserProductLibraryStorageKey = 'freshscan.user_product_library';

abstract interface class UserProductLibraryRepository {
  Future<bool> isFavorite(String productId);

  Future<void> addFavorite(LocalProductSnapshot product);

  Future<void> removeFavorite(String productId);

  Future<bool> toggleFavorite(LocalProductSnapshot product);

  Future<List<FavoriteProductEntry>> getFavorites();

  Future<void> recordViewedProduct(LocalProductSnapshot product);

  Future<void> recordScannedProduct(LocalProductSnapshot product);

  Future<List<ProductActivityEntry>> getRecentActivity({
    ProductActivityType? type,
    int? limit,
  });

  Future<void> clearRecentActivity({ProductActivityType? type});
}

abstract interface class UserProductLibraryStorage {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);
}

class SharedPreferencesUserProductLibraryStorage
    implements UserProductLibraryStorage {
  const SharedPreferencesUserProductLibraryStorage();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<String?> readString(String key) async {
    return (await _prefs).getString(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    final saved = await (await _prefs).setString(key, value);
    if (!saved) {
      throw StateError('Failed to persist user product library state');
    }
  }
}

final userProductLibraryStorageProvider = Provider<UserProductLibraryStorage>(
  (ref) => const SharedPreferencesUserProductLibraryStorage(),
);

final userProductLibraryRepositoryProvider =
    Provider<UserProductLibraryRepository>((ref) {
      return LocalUserProductLibraryRepository(
        storage: ref.watch(userProductLibraryStorageProvider),
      );
    });

class LocalUserProductLibraryRepository
    implements UserProductLibraryRepository {
  LocalUserProductLibraryRepository({
    required UserProductLibraryStorage storage,
    DateTime Function()? clock,
  }) : _storage = storage,
       _clock = clock ?? DateTime.now;

  final UserProductLibraryStorage _storage;
  final DateTime Function() _clock;

  _UserProductLibraryEnvelope? _cache;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<bool> isFavorite(String productId) async {
    if (productId.trim().isEmpty) return false;

    final envelope = await _readCurrentEnvelope();
    return envelope.favorites.any(
      (entry) => entry.product.productId == productId,
    );
  }

  @override
  Future<void> addFavorite(LocalProductSnapshot product) {
    return _mutate<void>((current) {
      final now = _clock().toUtc();
      final updatedFavorites = _normalizeFavorites([
        FavoriteProductEntry(product: product, addedAt: now),
        ...current.favorites.where(
          (entry) => entry.product.productId != product.productId,
        ),
      ]);

      return (
        nextEnvelope: current.copyWith(favorites: updatedFavorites),
        result: null,
      );
    });
  }

  @override
  Future<void> removeFavorite(String productId) {
    return _mutate<void>((current) {
      final updatedFavorites = current.favorites
          .where((entry) => entry.product.productId != productId)
          .toList(growable: false);

      return (
        nextEnvelope: current.copyWith(favorites: updatedFavorites),
        result: null,
      );
    });
  }

  @override
  Future<bool> toggleFavorite(LocalProductSnapshot product) {
    return _mutate<bool>((current) {
      final isAlreadyFavorite = current.favorites.any(
        (entry) => entry.product.productId == product.productId,
      );

      final nextFavorites = isAlreadyFavorite
          ? current.favorites
                .where((entry) => entry.product.productId != product.productId)
                .toList(growable: false)
          : _normalizeFavorites([
              FavoriteProductEntry(product: product, addedAt: _clock().toUtc()),
              ...current.favorites,
            ]);

      return (
        nextEnvelope: current.copyWith(favorites: nextFavorites),
        result: !isAlreadyFavorite,
      );
    });
  }

  @override
  Future<List<FavoriteProductEntry>> getFavorites() async {
    final envelope = await _readCurrentEnvelope();
    return List<FavoriteProductEntry>.unmodifiable(envelope.favorites);
  }

  @override
  Future<void> recordViewedProduct(LocalProductSnapshot product) {
    return _recordActivity(ProductActivityType.viewed, product);
  }

  @override
  Future<void> recordScannedProduct(LocalProductSnapshot product) {
    return _recordActivity(ProductActivityType.scanned, product);
  }

  @override
  Future<List<ProductActivityEntry>> getRecentActivity({
    ProductActivityType? type,
    int? limit,
  }) async {
    final envelope = await _readCurrentEnvelope();
    final filtered = type == null
        ? envelope.activity
        : envelope.activity.where((entry) => entry.type == type).toList();

    if (limit == null || limit < 0 || filtered.length <= limit) {
      return List<ProductActivityEntry>.unmodifiable(filtered);
    }

    return List<ProductActivityEntry>.unmodifiable(filtered.take(limit));
  }

  @override
  Future<void> clearRecentActivity({ProductActivityType? type}) {
    return _mutate<void>((current) {
      final nextActivity = type == null
          ? const <ProductActivityEntry>[]
          : current.activity
                .where((entry) => entry.type != type)
                .toList(growable: false);

      return (
        nextEnvelope: current.copyWith(activity: nextActivity),
        result: null,
      );
    });
  }

  Future<void> _recordActivity(
    ProductActivityType type,
    LocalProductSnapshot product,
  ) {
    return _mutate<void>((current) {
      final timestamp = _clock().toUtc();
      final updatedActivity = _normalizeActivity([
        ProductActivityEntry(
          product: product,
          type: type,
          occurredAt: timestamp,
        ),
        ...current.activity.where(
          (entry) =>
              entry.type != type ||
              entry.product.productId != product.productId,
        ),
      ]);

      return (
        nextEnvelope: current.copyWith(activity: updatedActivity),
        result: null,
      );
    });
  }

  Future<_UserProductLibraryEnvelope> _readCurrentEnvelope() async {
    await _waitForPendingWrites();
    return _loadEnvelope();
  }

  Future<T> _mutate<T>(
    ({_UserProductLibraryEnvelope nextEnvelope, T result}) Function(
      _UserProductLibraryEnvelope current,
    )
    mutate,
  ) {
    final completer = Completer<T>();

    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      try {
        final current = await _loadEnvelope();
        final (:nextEnvelope, :result) = mutate(current);

        final normalized = _normalizeEnvelope(nextEnvelope);
        await _persistEnvelope(normalized);
        _cache = normalized;
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<_UserProductLibraryEnvelope> _loadEnvelope() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }

    final raw = await _storage.readString(kUserProductLibraryStorageKey);
    final decoded = _decodeEnvelope(raw);
    _cache = decoded;
    return decoded;
  }

  Future<void> _persistEnvelope(_UserProductLibraryEnvelope envelope) async {
    final raw = jsonEncode(envelope.toJson());
    await _storage.writeString(kUserProductLibraryStorageKey, raw);
  }

  Future<void> _waitForPendingWrites() async {
    await _writeQueue.catchError((_) {});
  }

  _UserProductLibraryEnvelope _decodeEnvelope(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const _UserProductLibraryEnvelope.empty();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const _UserProductLibraryEnvelope.empty();
      }

      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final version = _readSchemaVersion(map['schemaVersion']);

      if (version > kUserProductLibrarySchemaVersion) {
        _debugUserLibraryLog(
          '[UserLibrary] Unsupported schema version $version; using empty state.',
        );
        return const _UserProductLibraryEnvelope.empty();
      }

      final favorites = _decodeFavorites(map['favorites']);
      final activity = _decodeActivity(map['activity']);

      return _normalizeEnvelope(
        _UserProductLibraryEnvelope(
          schemaVersion: kUserProductLibrarySchemaVersion,
          favorites: favorites,
          activity: activity,
        ),
      );
    } catch (error) {
      _debugUserLibraryLog('[UserLibrary] Failed to decode storage: $error');
      return const _UserProductLibraryEnvelope.empty();
    }
  }

  int _readSchemaVersion(Object? rawVersion) {
    if (rawVersion is int) return rawVersion;
    if (rawVersion is num) return rawVersion.toInt();
    if (rawVersion is String) return int.tryParse(rawVersion) ?? 0;
    return 0;
  }

  List<FavoriteProductEntry> _decodeFavorites(Object? rawFavorites) {
    if (rawFavorites is! List) return const <FavoriteProductEntry>[];

    final entries = <FavoriteProductEntry>[];
    for (final rawEntry in rawFavorites) {
      final entry = FavoriteProductEntry.tryParse(rawEntry);
      if (entry != null) {
        entries.add(entry);
      }
    }
    return _normalizeFavorites(entries);
  }

  List<ProductActivityEntry> _decodeActivity(Object? rawActivity) {
    if (rawActivity is! List) return const <ProductActivityEntry>[];

    final entries = <ProductActivityEntry>[];
    for (final rawEntry in rawActivity) {
      final entry = ProductActivityEntry.tryParse(rawEntry);
      if (entry != null) {
        entries.add(entry);
      }
    }
    return _normalizeActivity(entries);
  }

  List<FavoriteProductEntry> _normalizeFavorites(
    Iterable<FavoriteProductEntry> favorites,
  ) {
    final sorted = favorites.toList(growable: false)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    final seenIds = <String>{};
    final uniqueFavorites = <FavoriteProductEntry>[];

    for (final entry in sorted) {
      if (seenIds.add(entry.product.productId)) {
        uniqueFavorites.add(entry);
      }
    }

    return List<FavoriteProductEntry>.unmodifiable(uniqueFavorites);
  }

  List<ProductActivityEntry> _normalizeActivity(
    Iterable<ProductActivityEntry> activity,
  ) {
    final sorted = activity.toList(growable: false)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final retained = <ProductActivityEntry>[];
    final seenKeys = <String>{};
    var viewedCount = 0;
    var scannedCount = 0;

    for (final entry in sorted) {
      final dedupeKey = '${entry.type.storageValue}:${entry.product.productId}';
      if (!seenKeys.add(dedupeKey)) {
        continue;
      }

      switch (entry.type) {
        case ProductActivityType.viewed:
          if (viewedCount >= kMaxViewedProductActivityEntries) {
            continue;
          }
          viewedCount++;
          break;
        case ProductActivityType.scanned:
          if (scannedCount >= kMaxScannedProductActivityEntries) {
            continue;
          }
          scannedCount++;
          break;
      }

      retained.add(entry);
    }

    retained.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return List<ProductActivityEntry>.unmodifiable(retained);
  }

  _UserProductLibraryEnvelope _normalizeEnvelope(
    _UserProductLibraryEnvelope envelope,
  ) {
    return _UserProductLibraryEnvelope(
      schemaVersion: kUserProductLibrarySchemaVersion,
      favorites: _normalizeFavorites(envelope.favorites),
      activity: _normalizeActivity(envelope.activity),
    );
  }
}

void _debugUserLibraryLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}

@immutable
class _UserProductLibraryEnvelope {
  final int schemaVersion;
  final List<FavoriteProductEntry> favorites;
  final List<ProductActivityEntry> activity;

  const _UserProductLibraryEnvelope({
    required this.schemaVersion,
    this.favorites = const <FavoriteProductEntry>[],
    this.activity = const <ProductActivityEntry>[],
  });

  const _UserProductLibraryEnvelope.empty()
    : schemaVersion = kUserProductLibrarySchemaVersion,
      favorites = const <FavoriteProductEntry>[],
      activity = const <ProductActivityEntry>[];

  _UserProductLibraryEnvelope copyWith({
    List<FavoriteProductEntry>? favorites,
    List<ProductActivityEntry>? activity,
  }) {
    return _UserProductLibraryEnvelope(
      schemaVersion: kUserProductLibrarySchemaVersion,
      favorites: favorites ?? this.favorites,
      activity: activity ?? this.activity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'favorites': favorites.map((entry) => entry.toJson()).toList(),
      'activity': activity.map((entry) => entry.toJson()).toList(),
    };
  }
}
