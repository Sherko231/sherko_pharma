import '../../catalog/domain/catalog_product.dart';

const int maxOrderAmount = 9223372036854775807;

class OrderAmountOverflow implements Exception {
  const OrderAmountOverflow();
}

class OrderLine {
  const OrderLine({
    required this.productId,
    required this.displayName,
    required this.quantity,
    required this.unitAmount,
    required this.currency,
    required this.productRevision,
  });

  factory OrderLine.fromProduct(CatalogProduct product) {
    return OrderLine(
      productId: product.id,
      displayName: product.displayName,
      quantity: 1,
      unitAmount: product.sellingAmount,
      currency: product.currency,
      productRevision: product.revision,
    );
  }

  final String productId;
  final String displayName;
  final int quantity;
  final int unitAmount;
  final String currency;
  final int productRevision;

  int get lineAmount => checkedMultiply(unitAmount, quantity);

  OrderLine copyWith({
    int? quantity,
  }) {
    return OrderLine(
      productId: productId,
      displayName: displayName,
      quantity: quantity ?? this.quantity,
      unitAmount: unitAmount,
      currency: currency,
      productRevision: productRevision,
    );
  }
}

class OrderState {
  const OrderState({
    this.lines = const [],
  });

  final List<OrderLine> lines;

  bool get isEmpty => lines.isEmpty;

  int totalFor(String currency) {
    var total = 0;
    for (final line in lines) {
      if (line.currency != currency) {
        continue;
      }
      total = checkedAdd(total, line.lineAmount);
    }
    return total;
  }

  int get totalSyp => totalFor('SYP');

  int get totalUsd => totalFor('USD');
}

int checkedMultiply(int left, int right) {
  if (left < 0 || right < 0) {
    throw const OrderAmountOverflow();
  }
  if (left != 0 && right > maxOrderAmount ~/ left) {
    throw const OrderAmountOverflow();
  }
  return left * right;
}

int checkedAdd(int left, int right) {
  if (left < 0 || right < 0 || right > maxOrderAmount - left) {
    throw const OrderAmountOverflow();
  }
  return left + right;
}
