import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/catalog/application/catalog_search_controller.dart';
import 'package:sherko_pharma/features/catalog/application/scoped_catalog_refresh_controller.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer refreshContainer(
  FakeAuthGateway auth,
  FakeCatalogRepository catalog,
) {
  final container = ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(auth),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await auth.dispose();
  });
  return container;
}

Future<void> settleRefresh(ProviderContainer container) async {
  for (var index = 0; index < 20; index += 1) {
    await Future<void>.delayed(Duration.zero);
    if (!container.read(scopedCatalogRefreshControllerProvider).isRefreshing) {
      return;
    }
  }
}

void main() {
  test('price refresh preserves captured pair until explicit acceptance', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final catalog = FakeCatalogRepository();
    final container = refreshContainer(auth, catalog);
    final order = container.read(orderControllerProvider.notifier);

    order.addProduct(
      testProduct(
        id: 'p1',
        sellingAmount: 1000,
        currency: 'SYP',
        revision: 4,
      ),
    );
    order.increment('p1');
    order.increment('p1');

    catalog.products['p1'] = testProduct(
      id: 'p1',
      sellingAmount: 1500,
      currency: 'SYP',
      revision: 5,
    );

    final refresh =
        container.read(scopedCatalogRefreshControllerProvider.notifier);
    refresh.setActive(true);
    await settleRefresh(container);

    final beforeAccept = container.read(orderControllerProvider);
    expect(beforeAccept.lines.single.unitAmount, 1000);
    expect(beforeAccept.lines.single.currency, 'SYP');
    expect(beforeAccept.totalSyp, 3000);
    expect(
      container
          .read(scopedCatalogRefreshControllerProvider)
          .priceChanges['p1']
          ?.sellingAmount,
      1500,
    );

    expect(
      refresh.acceptPriceChange('p1'),
      OrderActionResult.updated,
    );

    final afterAccept = container.read(orderControllerProvider);
    expect(afterAccept.lines.single.unitAmount, 1500);
    expect(afterAccept.lines.single.productRevision, 5);
    expect(afterAccept.totalSyp, 4500);
    expect(
      container.read(scopedCatalogRefreshControllerProvider).priceChanges,
      isEmpty,
    );
  });

  test('currency refresh moves totals only after explicit acceptance', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final catalog = FakeCatalogRepository();
    final container = refreshContainer(auth, catalog);
    final order = container.read(orderControllerProvider.notifier);

    order.addProduct(
      testProduct(
        id: 'p1',
        sellingAmount: 1000,
        currency: 'SYP',
        revision: 4,
      ),
    );
    order.increment('p1');

    catalog.products['p1'] = testProduct(
      id: 'p1',
      sellingAmount: 5,
      currency: 'USD',
      revision: 5,
    );

    final refresh =
        container.read(scopedCatalogRefreshControllerProvider.notifier);
    refresh.setActive(true);
    await settleRefresh(container);

    expect(container.read(orderControllerProvider).totalSyp, 2000);
    expect(container.read(orderControllerProvider).totalUsd, 0);

    expect(
      refresh.acceptPriceChange('p1'),
      OrderActionResult.updated,
    );

    expect(container.read(orderControllerProvider).totalSyp, 0);
    expect(container.read(orderControllerProvider).totalUsd, 10);
  });

  test('invalid latest price remains a notice and cannot be accepted', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final catalog = FakeCatalogRepository();
    final container = refreshContainer(auth, catalog);
    final order = container.read(orderControllerProvider.notifier);

    order.addProduct(
      testProduct(
        id: 'p1',
        sellingAmount: 1000,
        currency: 'SYP',
        revision: 4,
      ),
    );
    catalog.products['p1'] = testProduct(
      id: 'p1',
      sellingAmount: 0,
      currency: 'SYP',
      revision: 5,
    );

    final refresh =
        container.read(scopedCatalogRefreshControllerProvider.notifier);
    refresh.setActive(true);
    await settleRefresh(container);

    expect(
      refresh.acceptPriceChange('p1'),
      OrderActionResult.invalidPrice,
    );
    expect(container.read(orderControllerProvider).lines.single.unitAmount, 1000);
    expect(
      container
          .read(scopedCatalogRefreshControllerProvider)
          .priceChanges
          .containsKey('p1'),
      isTrue,
    );
  });

  test('refresh failure preserves order and later success clears warning', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final catalog = FakeCatalogRepository()
      ..onGet = (_) async {
        throw const CatalogRepositoryException();
      };
    final container = refreshContainer(auth, catalog);
    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'p1',
            sellingAmount: 1000,
            currency: 'SYP',
            revision: 4,
          ),
        );

    final refresh =
        container.read(scopedCatalogRefreshControllerProvider.notifier);
    refresh.setActive(true);
    await settleRefresh(container);

    expect(
      container.read(scopedCatalogRefreshControllerProvider).errorMessage,
      ScopedCatalogRefreshController.refreshErrorMessage,
    );
    expect(container.read(orderControllerProvider).lines.single.unitAmount, 1000);

    catalog.onGet = null;
    catalog.products['p1'] = testProduct(
      id: 'p1',
      sellingAmount: 1000,
      currency: 'SYP',
      revision: 5,
      nameEn: 'Refreshed name',
    );

    expect(await refresh.refreshNow(), isTrue);

    final state = container.read(scopedCatalogRefreshControllerProvider);
    final line = container.read(orderControllerProvider).lines.single;
    expect(state.errorMessage, isNull);
    expect(line.displayName, 'Refreshed name');
    expect(line.productRevision, 5);
    expect(line.unitAmount, 1000);
  });

  test('late prior-account response cannot repopulate current refresh state', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final catalog = FakeCatalogRepository();
    final gate = Completer<dynamic>();
    var calls = 0;
    catalog.onGet = (productId) {
      calls += 1;
      if (calls == 1) {
        return gate.future.then((value) => value);
      }
      return Future.value(
        testProduct(
          id: productId,
          sellingAmount: 1000,
          currency: 'SYP',
          revision: 4,
        ),
      );
    };

    final container = refreshContainer(auth, catalog);
    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'p1',
            sellingAmount: 1000,
            currency: 'SYP',
            revision: 4,
          ),
        );

    final refresh =
        container.read(scopedCatalogRefreshControllerProvider.notifier);
    refresh.setActive(true);
    await Future<void>.delayed(Duration.zero);

    auth.emitIdentity(const AuthIdentity(userId: 'owner-b'));
    container.read(orderControllerProvider.notifier).clear();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    gate.complete(
      testProduct(
        id: 'p1',
        sellingAmount: 9999,
        currency: 'USD',
        revision: 9,
      ),
    );
    await settleRefresh(container);

    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      container.read(scopedCatalogRefreshControllerProvider).priceChanges,
      isEmpty,
    );
  });
}
