import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/catalog_product.dart';
import '../../order/application/order_controller.dart';

enum BarcodeScanStatus {
  added,
  incremented,
  unknown,
  ambiguous,
  invalidPrice,
  overflow,
  failed,
}

class BarcodeScanResult {
  const BarcodeScanResult(this.status, {this.product});

  final BarcodeScanStatus status;
  final CatalogProduct? product;
}

class BarcodeScanController {
  BarcodeScanController({
    required CatalogRepository catalog,
    required OrderController order,
  })  : _catalog = catalog,
        _order = order;

  final CatalogRepository _catalog;
  final OrderController _order;
  bool _busy = false;

  bool get isBusy => _busy;

  Future<BarcodeScanResult?> accept(String code) async {
    if (_busy || code.isEmpty) {
      return null;
    }
    _busy = true;
    try {
      final matches = await _catalog.lookupBarcode(code);
      if (matches.isEmpty) {
        return const BarcodeScanResult(BarcodeScanStatus.unknown);
      }
      if (matches.length != 1) {
        return const BarcodeScanResult(BarcodeScanStatus.ambiguous);
      }

      final latest = await _catalog.getById(matches.single.id);
      final orderResult = _order.addProduct(latest);
      final status = switch (orderResult) {
        OrderActionResult.added => BarcodeScanStatus.added,
        OrderActionResult.incremented => BarcodeScanStatus.incremented,
        OrderActionResult.invalidPrice => BarcodeScanStatus.invalidPrice,
        OrderActionResult.overflow => BarcodeScanStatus.overflow,
        _ => BarcodeScanStatus.failed,
      };
      return BarcodeScanResult(status, product: latest);
    } catch (_) {
      return const BarcodeScanResult(BarcodeScanStatus.failed);
    } finally {
      _busy = false;
    }
  }
}
