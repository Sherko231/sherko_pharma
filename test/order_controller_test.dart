import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer orderContainer() {
  final auth = FakeAuthGateway(
    initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
  );
  final container = ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(auth),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await auth.dispose();
  });
  return container;
}

void main() {
  test('repeat add keeps one line and captured price', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    final first = testProduct(
      id: 'p1',
      sellingAmount: 1000,
      currency: 'SYP',
      revision: 4,
    );
    final later = testProduct(
      id: 'p1',
      sellingAmount: 5000,
      currency: 'USD',
      revision: 5,
    );

    expect(controller.addProduct(first), OrderActionResult.added);
    expect(controller.addProduct(later), OrderActionResult.incremented);

    final order = container.read(orderControllerProvider);
    expect(order.lines, hasLength(1));
    expect(order.lines.single.quantity, 2);
    expect(order.lines.single.unitAmount, 1000);
    expect(order.lines.single.currency, 'SYP');
    expect(order.lines.single.productRevision, 4);
    expect(order.totalSyp, 2000);
    expect(order.totalUsd, 0);
  });

  test('mixed currencies remain separate with exact integer totals', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    controller.addProduct(
      testProduct(
        id: 'syp',
        sellingAmount: 1000,
        currency: 'SYP',
      ),
    );
    controller.addProduct(
      testProduct(
        id: 'usd',
        sellingAmount: 5,
        currency: 'USD',
      ),
    );

    controller.increment('syp');
    controller.increment('syp');
    controller.increment('usd');

    final order = container.read(orderControllerProvider);
    expect(order.totalSyp, 3000);
    expect(order.totalUsd, 10);
    expect(order.lines, hasLength(2));
  });

  test('invalid source price and unsupported currency are rejected', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    expect(
      controller.addProduct(
        testProduct(
          id: 'zero',
          sellingAmount: 0,
          currency: 'SYP',
        ),
      ),
      OrderActionResult.invalidPrice,
    );
    expect(
      controller.addProduct(
        testProduct(
          id: 'bad-currency',
          sellingAmount: 10,
          currency: 'EUR',
        ),
      ),
      OrderActionResult.invalidPrice,
    );
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  test('quantity never drops below one and removal changes only one line', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    controller.addProduct(testProduct(id: 'a', sellingAmount: 10));
    controller.addProduct(testProduct(id: 'b', sellingAmount: 20));

    expect(controller.decrement('a'), OrderActionResult.unchanged);
    expect(
      container
          .read(orderControllerProvider)
          .lines
          .firstWhere((line) => line.productId == 'a')
          .quantity,
      1,
    );

    expect(controller.remove('a'), OrderActionResult.removed);
    final order = container.read(orderControllerProvider);
    expect(order.lines.map((line) => line.productId), ['b']);
  });

  test('overflow is rejected without mutating the current order', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    final huge = testProduct(
      id: 'huge',
      sellingAmount: maxOrderAmount,
      currency: 'SYP',
    );

    expect(controller.addProduct(huge), OrderActionResult.added);
    expect(controller.increment('huge'), OrderActionResult.overflow);

    final order = container.read(orderControllerProvider);
    expect(order.lines.single.quantity, 1);
    expect(order.totalSyp, maxOrderAmount);

    expect(
      controller.addProduct(
        testProduct(
          id: 'extra',
          sellingAmount: 1,
          currency: 'SYP',
        ),
      ),
      OrderActionResult.overflow,
    );
    expect(container.read(orderControllerProvider).lines, hasLength(1));
  });

  test('clear resets lines and both totals', () {
    final container = orderContainer();
    final controller = container.read(orderControllerProvider.notifier);

    controller.addProduct(testProduct(id: 'a', sellingAmount: 100));
    controller.addProduct(
      testProduct(
        id: 'b',
        sellingAmount: 2,
        currency: 'USD',
      ),
    );

    controller.clear();

    final order = container.read(orderControllerProvider);
    expect(order.lines, isEmpty);
    expect(order.totalSyp, 0);
    expect(order.totalUsd, 0);
  });
}
