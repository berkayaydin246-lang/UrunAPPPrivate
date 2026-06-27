import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

@immutable
class FavoriteProductsState {
  final List<FavoriteProductEntry> favorites;
  final bool isLoading;
  final String? error;

  const FavoriteProductsState({
    this.favorites = const <FavoriteProductEntry>[],
    this.isLoading = false,
    this.error,
  });

  FavoriteProductsState copyWith({
    List<FavoriteProductEntry>? favorites,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return FavoriteProductsState(
      favorites: favorites ?? this.favorites,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Set<String> get favoriteIds => {
    for (final entry in favorites) entry.product.productId,
  };
}

class FavoriteProductsNotifier extends StateNotifier<FavoriteProductsState> {
  FavoriteProductsNotifier(this._repository)
    : super(const FavoriteProductsState(isLoading: true)) {
    unawaited(refresh());
  }

  final UserProductLibraryRepository _repository;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final favorites = await _repository.getFavorites();
      state = state.copyWith(
        favorites: favorites,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> addFavorite(LocalProductSnapshot product) async {
    await _runMutation(() => _repository.addFavorite(product));
  }

  Future<void> removeFavorite(String productId) async {
    await _runMutation(() => _repository.removeFavorite(productId));
  }

  Future<bool> toggleFavorite(LocalProductSnapshot product) async {
    var isFavorite = false;
    await _runMutation(() async {
      isFavorite = await _repository.toggleFavorite(product);
    });
    return isFavorite;
  }

  Future<void> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      final favorites = await _repository.getFavorites();
      state = state.copyWith(favorites: favorites, clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}

@immutable
class RecentProductActivityState {
  final List<ProductActivityEntry> viewedEntries;
  final List<ProductActivityEntry> scannedEntries;
  final bool isLoading;
  final String? error;

  const RecentProductActivityState({
    this.viewedEntries = const <ProductActivityEntry>[],
    this.scannedEntries = const <ProductActivityEntry>[],
    this.isLoading = false,
    this.error,
  });

  List<ProductActivityEntry> get entries {
    final merged = <ProductActivityEntry>[...viewedEntries, ...scannedEntries];
    merged.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return List<ProductActivityEntry>.unmodifiable(merged);
  }

  RecentProductActivityState copyWith({
    List<ProductActivityEntry>? viewedEntries,
    List<ProductActivityEntry>? scannedEntries,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return RecentProductActivityState(
      viewedEntries: viewedEntries ?? this.viewedEntries,
      scannedEntries: scannedEntries ?? this.scannedEntries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RecentProductActivityNotifier
    extends StateNotifier<RecentProductActivityState> {
  RecentProductActivityNotifier(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const RecentProductActivityState(isLoading: true)) {
    unawaited(refresh());
  }

  final UserProductLibraryRepository _repository;
  final DateTime Function() _clock;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final entries = await _repository.getRecentActivity();
      state = _buildStateFromEntries(
        entries,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> recordViewedProduct(LocalProductSnapshot product) async {
    await _recordActivity(ProductActivityType.viewed, product);
  }

  Future<void> recordScannedProduct(LocalProductSnapshot product) async {
    await _recordActivity(ProductActivityType.scanned, product);
  }

  Future<void> clearRecentActivity({ProductActivityType? type}) async {
    await _runMutation(() => _repository.clearRecentActivity(type: type));
  }

  Future<void> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      final entries = await _repository.getRecentActivity();
      state = _buildStateFromEntries(
        entries,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      rethrow;
    }
  }

  Future<void> _recordActivity(
    ProductActivityType type,
    LocalProductSnapshot product,
  ) async {
    final previousState = state;
    final optimisticEntry = ProductActivityEntry(
      product: product,
      type: type,
      occurredAt: _clock().toUtc(),
    );

    state = _applyOptimisticActivityEntry(previousState, optimisticEntry);

    try {
      switch (type) {
        case ProductActivityType.viewed:
          await _repository.recordViewedProduct(product);
          break;
        case ProductActivityType.scanned:
          await _repository.recordScannedProduct(product);
          break;
      }

      final entries = await _repository.getRecentActivity();
      state = _buildStateFromEntries(
        entries,
        isLoading: false,
        clearError: true,
      );
    } catch (error, stackTrace) {
      try {
        final entries = await _repository.getRecentActivity();
        state = _buildStateFromEntries(
          entries,
          isLoading: false,
          error: 'Kullanıcı etkinliği kaydedilemedi.',
        );
      } catch (_) {
        state = previousState.copyWith(
          isLoading: false,
          error: 'Kullanıcı etkinliği kaydedilemedi.',
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RecentProductActivityState _applyOptimisticActivityEntry(
    RecentProductActivityState previousState,
    ProductActivityEntry entry,
  ) {
    final isViewed = entry.type == ProductActivityType.viewed;
    final nextEntries = _insertActivityEntry(
      existingEntries: isViewed
          ? previousState.viewedEntries
          : previousState.scannedEntries,
      entry: entry,
      maxEntries: isViewed
          ? kMaxViewedProductActivityEntries
          : kMaxScannedProductActivityEntries,
    );

    return previousState.copyWith(
      viewedEntries: isViewed ? nextEntries : previousState.viewedEntries,
      scannedEntries: isViewed ? previousState.scannedEntries : nextEntries,
      clearError: true,
    );
  }

  List<ProductActivityEntry> _insertActivityEntry({
    required List<ProductActivityEntry> existingEntries,
    required ProductActivityEntry entry,
    required int maxEntries,
  }) {
    final nextEntries = <ProductActivityEntry>[
      entry,
      ...existingEntries.where(
        (existing) => existing.product.productId != entry.product.productId,
      ),
    ];

    if (nextEntries.length > maxEntries) {
      nextEntries.removeRange(maxEntries, nextEntries.length);
    }

    return List<ProductActivityEntry>.unmodifiable(nextEntries);
  }

  RecentProductActivityState _buildStateFromEntries(
    List<ProductActivityEntry> entries, {
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    final nextViewed = List<ProductActivityEntry>.unmodifiable(
      entries.where((entry) => entry.type == ProductActivityType.viewed),
    );
    final nextScanned = List<ProductActivityEntry>.unmodifiable(
      entries.where((entry) => entry.type == ProductActivityType.scanned),
    );

    return RecentProductActivityState(
      viewedEntries: listEquals(state.viewedEntries, nextViewed)
          ? state.viewedEntries
          : nextViewed,
      scannedEntries: listEquals(state.scannedEntries, nextScanned)
          ? state.scannedEntries
          : nextScanned,
      isLoading: isLoading ?? state.isLoading,
      error: clearError ? null : (error ?? state.error),
    );
  }
}

final favoriteProductsProvider =
    StateNotifierProvider<FavoriteProductsNotifier, FavoriteProductsState>(
      (ref) => FavoriteProductsNotifier(
        ref.watch(userProductLibraryRepositoryProvider),
      ),
    );

final favoriteProductIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(favoriteProductsProvider).favoriteIds;
});

final favoriteEntriesProvider = Provider<List<FavoriteProductEntry>>((ref) {
  return ref.watch(favoriteProductsProvider.select((state) => state.favorites));
});

final isProductFavoriteProvider = Provider.family<bool, String>((
  ref,
  productId,
) {
  return ref.watch(favoriteProductIdsProvider).contains(productId);
});

final userProductLibraryClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final recentProductActivityProvider =
    StateNotifierProvider<
      RecentProductActivityNotifier,
      RecentProductActivityState
    >((ref) {
      return RecentProductActivityNotifier(
        ref.watch(userProductLibraryRepositoryProvider),
        clock: ref.watch(userProductLibraryClockProvider),
      );
    });

@immutable
class RecentProductActivityQuery {
  final ProductActivityType? type;
  final int? limit;

  const RecentProductActivityQuery({this.type, this.limit});

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecentProductActivityQuery &&
            runtimeType == other.runtimeType &&
            type == other.type &&
            limit == other.limit;
  }

  @override
  int get hashCode => Object.hash(type, limit);
}

final recentProductActivityEntriesProvider =
    Provider<List<ProductActivityEntry>>((ref) {
      return ref.watch(recentProductActivityProvider).entries;
    });

final viewedProductActivityEntriesProvider =
    Provider<List<ProductActivityEntry>>((ref) {
      return ref.watch(
        recentProductActivityProvider.select((state) => state.viewedEntries),
      );
    });

final scannedProductActivityEntriesProvider =
    Provider<List<ProductActivityEntry>>((ref) {
      return ref.watch(
        recentProductActivityProvider.select((state) => state.scannedEntries),
      );
    });

final filteredRecentProductActivityProvider =
    Provider.family<List<ProductActivityEntry>, RecentProductActivityQuery>((
      ref,
      query,
    ) {
      final entries = switch (query.type) {
        ProductActivityType.viewed => ref.watch(
          viewedProductActivityEntriesProvider,
        ),
        ProductActivityType.scanned => ref.watch(
          scannedProductActivityEntriesProvider,
        ),
        null => ref.watch(recentProductActivityEntriesProvider),
      };

      var filtered = entries;

      if (query.limit != null && query.limit! >= 0) {
        filtered = filtered.take(query.limit!).toList(growable: false);
      }

      return filtered;
    });
