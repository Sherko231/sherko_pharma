import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../order/application/order_controller.dart';
import '../../order/domain/order_model.dart';
import '../domain/catalog_product.dart';
import 'catalog_detail_controller.dart';
import 'catalog_search_controller.dart';

class ScopedCatalogRefreshState {
  const ScopedCatalogRefreshState({
    this.isActive = false,
    this.isRefreshing = false,
    this.errorMessage,
    this.priceChanges = const {},
  });

  final bool isActive;
  final bool isRefreshing;
  final String? errorMessage;
  final Map<String, CatalogProduct> priceChanges;

  ScopedCatalogRefreshState copyWith({
    bool? isActive,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
    Map<String, CatalogProduct>? priceChanges,
  }) {
    return ScopedCatalogRefreshState(
      isActive: isActive ?? this.isActive,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      priceChanges: priceChanges ?? this.priceChanges,
    );
  }
}

class ScopedCatalogRefreshController
    extends Notifier<ScopedCatalogRefreshState> {
  static const Duration pollingInterval = Duration(minutes: 2);
  static const String refreshErrorMessage =
      'Some catalog data could not be refreshed. Showing the last known values.';

  Timer? _timer;
  int _identityGeneration = 0;
  bool _refreshInFlight = false;

  @override
  ScopedCatalogRefreshState build() {
    ref.listen<String?>(
      authControllerProvider.select((auth) => auth.identity?.userId),
      (previous, next) {
        _identityGeneration += 1;
        _refreshInFlight = false;
        if (next == null) {
          _timer?.cancel();
          state = const ScopedCatalogRefreshState();
          return;
        }

        state = ScopedCatalogRefreshState(
          isActive: state.isActive,
        );
        if (state.isActive) {
          _schedulePolling();
          unawaited(refreshNow());
        }
      },
    );

    ref.onDispose(() {
      _timer?.cancel();
    });

    return const ScopedCatalogRefreshState();
  }

  void setActive(bool active) {
    if (state.isActive == active) {
      if (active) {
        unawaited(refreshNow());
      }
      return;
    }

    _identityGeneration += 1;
    _refreshInFlight = false;
    state = state.copyWith(
      isActive: active,
      isRefreshing: false,
    );
    _timer?.cancel();

    if (!active) {
      return;
    }

    _schedulePolling();
    unawaited(refreshNow());
  }

  Future<bool> refreshNow() async {
    final ownerId = ref.read(authControllerProvider).identity?.userId;
    if (!state.isActive || ownerId == null || _refreshInFlight) {
      return false;
    }

    final generation = _identityGeneration;
    _refreshInFlight = true;
    state = state.copyWith(
      isRefreshing: true,
      clearError: true,
    );

    try {
      final results = await Future.wait<bool>([
        ref.read(catalogSearchControllerProvider.notifier).refresh(),
        ref.read(catalogDetailControllerProvider.notifier).refresh(),
        _refreshOrder(ownerId, generation),
      ]);

      if (!_isCurrent(ownerId, generation)) {
        return false;
      }

      final success = results.every((result) => result);
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: success ? null : refreshErrorMessage,
        clearError: success,
      );
      return success;
    } finally {
      if (_isCurrent(ownerId, generation)) {
        _refreshInFlight = false;
      }
    }
  }

  OrderActionResult acceptPriceChange(String productId) {
    final latest = state.priceChanges[productId];
    final currentLine = _findCurrentLine(productId);
    if (latest == null ||
        currentLine == null ||
        latest.revision <= currentLine.productRevision) {
      _removePriceChange(productId);
      return OrderActionResult.unchanged;
    }

    final result = ref
        .read(orderControllerProvider.notifier)
        .acceptCatalogUpdate(latest);

    if (result == OrderActionResult.updated) {
      _removePriceChange(productId);
    }

    return result;
  }

  void reconcileCurrentProduct(CatalogProduct latest) {
    final currentLine = _findCurrentLine(latest.id);
    if (currentLine == null) {
      _removePriceChange(latest.id);
      return;
    }

    final nextChanges = Map<String, CatalogProduct>.from(state.priceChanges);
    _reconcileLatestProduct(
      currentLine: currentLine,
      latest: latest,
      priceChanges: nextChanges,
    );
    state = state.copyWith(priceChanges: nextChanges);
  }

  void retry() {
    unawaited(refreshNow());
  }

  void _schedulePolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      pollingInterval,
      (_) => unawaited(refreshNow()),
    );
  }

  Future<bool> _refreshOrder(
    String ownerId,
    int generation,
  ) async {
    final baseline = ref.read(orderControllerProvider);
    final currentIds = baseline.lines.map((line) => line.productId).toSet();
    final nextChanges = Map<String, CatalogProduct>.fromEntries(
      state.priceChanges.entries.where(
        (entry) => currentIds.contains(entry.key),
      ),
    );

    if (baseline.lines.isEmpty) {
      if (_isCurrent(ownerId, generation)) {
        state = state.copyWith(priceChanges: nextChanges);
      }
      return true;
    }

    final repository = ref.read(catalogRepositoryProvider);
    final results = await Future.wait(
      baseline.lines.map((line) async {
        try {
          final product = await repository.getById(line.productId);
          return _OrderProductRefresh(line: line, product: product);
        } catch (_) {
          return _OrderProductRefresh(line: line);
        }
      }),
    );

    if (!_isCurrent(ownerId, generation)) {
      return false;
    }

    var success = true;
    final orderController = ref.read(orderControllerProvider.notifier);

    for (final result in results) {
      final latest = result.product;
      if (latest == null) {
        success = false;
        continue;
      }

      final currentLine = _findCurrentLine(result.line.productId);
      if (currentLine == null ||
          currentLine.unitAmount != result.line.unitAmount ||
          currentLine.currency != result.line.currency ||
          currentLine.productRevision != result.line.productRevision) {
        continue;
      }

      if (latest.revision < currentLine.productRevision) {
        success = false;
        continue;
      }

      if (latest.revision == currentLine.productRevision &&
          (latest.sellingAmount != currentLine.unitAmount ||
              latest.currency != currentLine.currency)) {
        success = false;
        continue;
      }

      _reconcileLatestProduct(
        currentLine: currentLine,
        latest: latest,
        priceChanges: nextChanges,
        orderController: orderController,
      );
    }

    if (_isCurrent(ownerId, generation)) {
      state = state.copyWith(priceChanges: nextChanges);
    }
    return success;
  }

  void _reconcileLatestProduct({
    required OrderLine currentLine,
    required CatalogProduct latest,
    required Map<String, CatalogProduct> priceChanges,
    OrderController? orderController,
  }) {
    final priceChanged = latest.sellingAmount != currentLine.unitAmount ||
        latest.currency != currentLine.currency;

    if (latest.revision > currentLine.productRevision && priceChanged) {
      priceChanges[currentLine.productId] = latest;
      return;
    }

    priceChanges.remove(currentLine.productId);
    if (latest.revision > currentLine.productRevision && !priceChanged) {
      (orderController ?? ref.read(orderControllerProvider.notifier))
          .refreshCatalogMetadata(latest);
    }
  }

  void _removePriceChange(String productId) {
    if (!state.priceChanges.containsKey(productId)) {
      return;
    }
    final next = Map<String, CatalogProduct>.from(state.priceChanges)
      ..remove(productId);
    state = state.copyWith(priceChanges: next);
  }

  OrderLine? _findCurrentLine(String productId) {
    for (final line in ref.read(orderControllerProvider).lines) {
      if (line.productId == productId) {
        return line;
      }
    }
    return null;
  }

  bool _isCurrent(String ownerId, int generation) {
    return ref.mounted &&
        generation == _identityGeneration &&
        ref.read(authControllerProvider).identity?.userId == ownerId;
  }
}

class _OrderProductRefresh {
  const _OrderProductRefresh({
    required this.line,
    this.product,
  });

  final OrderLine line;
  final CatalogProduct? product;
}

final scopedCatalogRefreshControllerProvider = NotifierProvider<
    ScopedCatalogRefreshController, ScopedCatalogRefreshState>(
  ScopedCatalogRefreshController.new,
);
