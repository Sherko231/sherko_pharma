import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/scanning/application/barcode_scan_controller.dart';

import 'support/fake_catalog_repository.dart';

void main() {
  test('exact barcode uses one server lookup and preserves leading zeroes', () async {
    final catalog = FakeCatalogRepository();
    catalog.onLookupBarcode =
        (_) async => [testProduct(id: 'p1', sellingAmount: 2500, revision: 2)];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    expect((await scan.accept('0012345'))?.status, BarcodeScanStatus.added);
    expect(catalog.barcodeCalls, ['0012345']);
    expect(catalog.detailCalls, isEmpty);
    expect(container.read(orderControllerProvider).lines.single.unitAmount, 2500);
  });

  test('secondary barcode resolves and deliberate later repeat increments once', () async {
    final product = testProduct(
      id: 'p1',
      barcode: '0011111',
      barcode2: '0099999',
    );
    final catalog = FakeCatalogRepository()..products['p1'] = product;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    expect((await scan.accept('0099999'))?.status, BarcodeScanStatus.added);
    expect((await scan.accept('0099999'))?.status, BarcodeScanStatus.incremented);
    expect(container.read(orderControllerProvider).lines.single.quantity, 2);
  });

  test('same product matching both barcode fields resolves once', () async {
    final catalog = FakeCatalogRepository()
      ..products['p1'] = testProduct(
        id: 'p1',
        barcode: '0012345',
        barcode2: '0012345',
      );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    expect((await scan.accept('0012345'))?.status, BarcodeScanStatus.added);
    expect(container.read(orderControllerProvider).lines, hasLength(1));
  });

  test('unknown and ambiguous matches do not mutate order', () async {
    final catalog = FakeCatalogRepository()
      ..onLookupBarcode = (code) async => code == 'ambiguous'
          ? [testProduct(id: 'p1'), testProduct(id: 'p2')]
          : [];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    expect((await scan.accept('unknown'))?.status, BarcodeScanStatus.unknown);
    expect((await scan.accept('ambiguous'))?.status, BarcodeScanStatus.ambiguous);
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  test('invalid lookup price is blocked without a second read', () async {
    final catalog = FakeCatalogRepository();
    catalog.onLookupBarcode =
        (_) async => [testProduct(id: 'p1', sellingAmount: 0)];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    expect((await scan.accept('0012345'))?.status, BarcodeScanStatus.invalidPrice);
    expect(catalog.detailCalls, isEmpty);
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  test('late lookup is discarded after a new-order reset', () async {
    final pending = Completer<List<CatalogProduct>>();
    final catalog = FakeCatalogRepository();
    catalog.onLookupBarcode = (_) => pending.future;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final order = container.read(orderControllerProvider.notifier);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: order,
    );

    final result = scan.accept('0012345');
    order.clear();
    pending.complete([testProduct(id: 'p1')]);

    expect(await result, isNull);
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  test('concurrent duplicate frame is ignored', () async {
    final pending = Completer<List<CatalogProduct>>();
    final catalog = FakeCatalogRepository();
    catalog.onLookupBarcode = (_) => pending.future;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scan = BarcodeScanController(
      catalog: catalog,
      order: container.read(orderControllerProvider.notifier),
    );

    final first = scan.accept('0012345');
    expect(await scan.accept('0012345'), isNull);
    pending.complete([testProduct(id: 'p1')]);
    expect((await first)?.status, BarcodeScanStatus.added);
    expect(catalog.detailCalls, isEmpty);
    expect(container.read(orderControllerProvider).lines.single.quantity, 1);
  });
}
