import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

/// Provide ProductRepository as a singleton.
final productRepositoryProvider = Provider((_) => const ProductRepository());

/// Provide OpenFoodFactsService as a singleton.
final offServiceProvider = Provider((_) => OpenFoodFactsService());

// ── Local search ──────────────────────────────────────────────────────────────

/// Current debounced search query string.
/// The UI sets this ~300 ms after the user stops typing.
class SearchQueryNotifier extends StateNotifier<String> {
  SearchQueryNotifier() : super('');

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final searchQueryProvider = StateNotifierProvider<SearchQueryNotifier, String>(
  (_) => SearchQueryNotifier(),
);

/// Local Supabase product search, auto-refreshes when [searchQueryProvider] changes.
/// Returns an empty list when the query is shorter than 2 characters.
final activeSearchProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return [];
  return ref.watch(productRepositoryProvider).searchByQuery(query);
});

// ── OFF text search (user-triggered) ─────────────────────────────────────────

class OffTextSearchState {
  final AsyncValue<List<OffProduct>> results;
  final String lastQuery;

  const OffTextSearchState({
    this.results = const AsyncValue.data([]),
    this.lastQuery = '',
  });

  OffTextSearchState copyWith({
    AsyncValue<List<OffProduct>>? results,
    String? lastQuery,
  }) => OffTextSearchState(
    results: results ?? this.results,
    lastQuery: lastQuery ?? this.lastQuery,
  );
}

class OffTextSearchNotifier extends StateNotifier<OffTextSearchState> {
  final OpenFoodFactsService _service;

  OffTextSearchNotifier(this._service) : super(const OffTextSearchState());

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      results: const AsyncValue.loading(),
      lastQuery: trimmed,
    );
    try {
      final products = await _service.searchByText(trimmed);
      state = state.copyWith(results: AsyncValue.data(products));
    } catch (e, st) {
      state = state.copyWith(results: AsyncValue.error(e, st));
    }
  }

  void clear() => state = const OffTextSearchState();
}

final offTextSearchProvider =
    StateNotifierProvider.autoDispose<
      OffTextSearchNotifier,
      OffTextSearchState
    >((ref) => OffTextSearchNotifier(ref.watch(offServiceProvider)));
