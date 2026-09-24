import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_product.dart';

enum CatalogSearchStatus {
  idle,
  loading,
  results,
  empty,
  error,
}

class CatalogSearchState {
  const CatalogSearchState({
    required this.query,
    required this.status,
    this.products = const [],
  });

  const CatalogSearchState.idle()
      : this(
          query: '',
          status: CatalogSearchStatus.idle,
        );

  final String query;
  final CatalogSearchStatus status;
  final List<CatalogProduct> products;
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  throw StateError('CatalogRepository was not configured for this runtime.');
});

class CatalogSearchController extends Notifier<CatalogSearchState> {
  static const int requestLimit = 25;
  static const Duration debounceDuration = Duration(milliseconds: 300);

  Timer? _debounce;
  int _generation = 0;

  @override
  CatalogSearchState build() {
    ref.watch(
      authControllerProvider.select((auth) => auth.identity?.userId),
    );
    ref.onDispose(() {
      _debounce?.cancel();
    });
    _generation += 1;
    return const CatalogSearchState.idle();
  }

  void queryChanged(String query) {
    _debounce?.cancel();
    final generation = ++_generation;

    if (query.trim().isEmpty) {
      state = CatalogSearchState(
        query: query,
        status: CatalogSearchStatus.idle,
      );
      return;
    }

    state = CatalogSearchState(
      query: query,
      status: CatalogSearchStatus.loading,
    );

    _debounce = Timer(debounceDuration, () {
      _executeSearch(query, generation);
    });
  }

  Future<void> submit(String query) async {
    _debounce?.cancel();
    final generation = ++_generation;

    if (query.trim().isEmpty) {
      state = CatalogSearchState(
        query: query,
        status: CatalogSearchStatus.idle,
      );
      return;
    }

    state = CatalogSearchState(
      query: query,
      status: CatalogSearchStatus.loading,
    );
    await _executeSearch(query, generation);
  }

  Future<void> retry() async {
    await submit(state.query);
  }

  Future<void> _executeSearch(String query, int generation) async {
    try {
      final products = await ref.read(catalogRepositoryProvider).search(
            query,
            limit: requestLimit,
          );
      if (generation != _generation) {
        return;
      }

      state = CatalogSearchState(
        query: query,
        status: products.isEmpty
            ? CatalogSearchStatus.empty
            : CatalogSearchStatus.results,
        products: products,
      );
    } catch (_) {
      if (generation != _generation) {
        return;
      }

      state = CatalogSearchState(
        query: query,
        status: CatalogSearchStatus.error,
      );
    }
  }
}

final catalogSearchControllerProvider =
    NotifierProvider<CatalogSearchController, CatalogSearchState>(
  CatalogSearchController.new,
);
