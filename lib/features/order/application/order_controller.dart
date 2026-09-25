import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../catalog/domain/catalog_product.dart';
import '../domain/order_model.dart';

enum OrderActionResult {
  added,
  incremented,
  updated,
  removed,
  invalidPrice,
  overflow,
  unchanged,
}

class OrderController extends Notifier<OrderState> {
  @override
  OrderState build() {
    ref.watch(
      authControllerProvider.select((auth) => auth.identity?.userId),
    );
    return const OrderState();
  }

  OrderActionResult addProduct(CatalogProduct product) {
    final existingIndex = state.lines.indexWhere(
      (line) => line.productId == product.id,
    );

    if (existingIndex >= 0) {
      return _changeQuantity(existingIndex, 1, OrderActionResult.incremented);
    }

    if (product.sellingAmount <= 0 ||
        (product.currency != 'SYP' && product.currency != 'USD')) {
      return OrderActionResult.invalidPrice;
    }

    final candidate = OrderLine.fromProduct(product);
    try {
      candidate.lineAmount;
      _checkedTotals([...state.lines, candidate]);
    } on OrderAmountOverflow {
      return OrderActionResult.overflow;
    }

    state = OrderState(
      lines: [...state.lines, candidate],
    );
    return OrderActionResult.added;
  }

  OrderActionResult increment(String productId) {
    final index = state.lines.indexWhere(
      (line) => line.productId == productId,
    );
    if (index < 0) {
      return OrderActionResult.unchanged;
    }
    return _changeQuantity(index, 1, OrderActionResult.updated);
  }

  OrderActionResult decrement(String productId) {
    final index = state.lines.indexWhere(
      (line) => line.productId == productId,
    );
    if (index < 0 || state.lines[index].quantity <= 1) {
      return OrderActionResult.unchanged;
    }
    return _changeQuantity(index, -1, OrderActionResult.updated);
  }

  OrderActionResult remove(String productId) {
    final next = state.lines
        .where((line) => line.productId != productId)
        .toList(growable: false);
    if (next.length == state.lines.length) {
      return OrderActionResult.unchanged;
    }
    state = OrderState(lines: next);
    return OrderActionResult.removed;
  }

  void clear() {
    state = const OrderState();
  }

  OrderActionResult _changeQuantity(
    int index,
    int delta,
    OrderActionResult success,
  ) {
    final current = state.lines[index];
    final nextQuantity = current.quantity + delta;
    if (nextQuantity < 1) {
      return OrderActionResult.unchanged;
    }

    final updated = current.copyWith(quantity: nextQuantity);
    final next = [...state.lines];
    next[index] = updated;

    try {
      updated.lineAmount;
      _checkedTotals(next);
    } on OrderAmountOverflow {
      return OrderActionResult.overflow;
    }

    state = OrderState(lines: next);
    return success;
  }

  void _checkedTotals(List<OrderLine> lines) {
    final candidate = OrderState(lines: lines);
    candidate.totalSyp;
    candidate.totalUsd;
  }
}

final orderControllerProvider =
    NotifierProvider<OrderController, OrderState>(
  OrderController.new,
);
