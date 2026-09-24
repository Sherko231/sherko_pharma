import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_product.dart';
import 'catalog_search_controller.dart';

enum CatalogDetailStatus {
  idle,
  loading,
  loaded,
  notFound,
  error,
}

class CatalogDetailState {
  const CatalogDetailState({
    required this.status,
    this.productId,
    this.product,
  });

  const CatalogDetailState.idle()
      : this(
          status: CatalogDetailStatus.idle,
        );

  final CatalogDetailStatus status;
  final String? productId;
  final CatalogProduct? product;
}

class CatalogDetailController extends Notifier<CatalogDetailState> {
  int _generation = 0;

  @override
  CatalogDetailState build() {
    ref.watch(
      authControllerProvider.select((auth) => auth.identity?.userId),
    );
    _generation += 1;
    return const CatalogDetailState.idle();
  }

  Future<void> load(String productId) async {
    final generation = ++_generation;
    state = CatalogDetailState(
      status: CatalogDetailStatus.loading,
      productId: productId,
    );

    try {
      final product = await ref.read(catalogRepositoryProvider).getById(
            productId,
          );
      if (generation != _generation) {
        return;
      }

      state = CatalogDetailState(
        status: CatalogDetailStatus.loaded,
        productId: productId,
        product: product,
      );
    } on CatalogNotFoundException {
      if (generation != _generation) {
        return;
      }
      state = CatalogDetailState(
        status: CatalogDetailStatus.notFound,
        productId: productId,
      );
    } catch (_) {
      if (generation != _generation) {
        return;
      }
      state = CatalogDetailState(
        status: CatalogDetailStatus.error,
        productId: productId,
      );
    }
  }

  void acceptServerProduct(CatalogProduct product) {
    _generation += 1;
    state = CatalogDetailState(
      status: CatalogDetailStatus.loaded,
      productId: product.id,
      product: product,
    );
  }

  Future<void> retry() async {
    final productId = state.productId;
    if (productId != null) {
      await load(productId);
    }
  }
}

final catalogDetailControllerProvider =
    NotifierProvider<CatalogDetailController, CatalogDetailState>(
  CatalogDetailController.new,
);
