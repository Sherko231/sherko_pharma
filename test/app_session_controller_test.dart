import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';
import 'package:sherko_pharma/features/session/application/app_session_controller.dart';
import 'package:sherko_pharma/features/session/data/app_session_store.dart';

import 'support/fake_app_session_store.dart';
import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer sessionContainer({
  required FakeAuthGateway auth,
  required FakeAppSessionStore store,
}) {
  final container = ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(auth),
      appSessionStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await auth.dispose();
  });
  return container;
}

AppSessionSnapshot savedOrder({
  required String ownerId,
  AppDestination destination = AppDestination.order,
  String productId = 'p1',
  int quantity = 3,
  int unitAmount = 1000,
  String currency = 'SYP',
}) {
  return AppSessionSnapshot(
    ownerId: ownerId,
    destination: destination,
    order: OrderState(
      lines: [
        OrderLine(
          productId: productId,
          displayName: 'Saved product',
          quantity: quantity,
          unitAmount: unitAmount,
          currency: currency,
          productRevision: 7,
        ),
      ],
    ),
  );
}

void main() {
  test('same account restores destination and exact captured order', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = savedOrder(ownerId: 'owner-a');
    final container = sessionContainer(auth: auth, store: store);

    container.read(appSessionControllerProvider);
    await pumpEventQueue();

    final session = container.read(appSessionControllerProvider);
    final order = container.read(orderControllerProvider);

    expect(session.status, AppSessionStatus.ready);
    expect(session.ownerId, 'owner-a');
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.order,
    );
    expect(order.lines, hasLength(1));
    expect(order.lines.single.productId, 'p1');
    expect(order.lines.single.quantity, 3);
    expect(order.lines.single.unitAmount, 1000);
    expect(order.lines.single.currency, 'SYP');
    expect(order.lines.single.productRevision, 7);
  });

  test('sign-out hides state and a different account cannot receive it', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = savedOrder(ownerId: 'owner-a');
    final container = sessionContainer(auth: auth, store: store);

    final session = container.read(appSessionControllerProvider.notifier);
    await pumpEventQueue();

    session.prepareForSignOut();
    auth.emitIdentity(null);
    await pumpEventQueue();
    await session.waitForPendingWrites();

    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.catalog,
    );
    expect(
      container.read(appSessionControllerProvider).status,
      AppSessionStatus.signedOut,
    );

    auth.emitIdentity(const AuthIdentity(userId: 'owner-b'));
    await pumpEventQueue();

    expect(container.read(appSessionControllerProvider).ownerId, 'owner-b');
    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.catalog,
    );

    auth.emitIdentity(const AuthIdentity(userId: 'owner-a'));
    await pumpEventQueue();

    expect(container.read(appSessionControllerProvider).ownerId, 'owner-a');
    expect(container.read(orderControllerProvider).lines.single.productId, 'p1');
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.order,
    );
  });

  test('delayed account A write cannot overwrite account B session', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gate = Completer<void>();
    final store = FakeAppSessionStore()
      ..firstWriteGate = gate;
    final container = sessionContainer(auth: auth, store: store);

    final session = container.read(appSessionControllerProvider.notifier);
    await pumpEventQueue();

    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'product-a',
            sellingAmount: 1000,
          ),
        );
    await pumpEventQueue();

    auth.emitIdentity(const AuthIdentity(userId: 'owner-b'));
    await pumpEventQueue();

    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'product-b',
            sellingAmount: 5,
            currency: 'USD',
          ),
        );
    await pumpEventQueue();

    gate.complete();
    await session.waitForPendingWrites();
    await pumpEventQueue();

    expect(
      store.snapshots['owner-a']!.order.lines.single.productId,
      'product-a',
    );
    expect(
      store.snapshots['owner-b']!.order.lines.single.productId,
      'product-b',
    );
    expect(
      container.read(orderControllerProvider).lines.single.productId,
      'product-b',
    );
    expect(container.read(appSessionControllerProvider).ownerId, 'owner-b');
  });

  test('write failure is visible and a successful retry clears it', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()..failWrites = true;
    final container = sessionContainer(auth: auth, store: store);

    final session = container.read(appSessionControllerProvider.notifier);
    await pumpEventQueue();

    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'product-a',
            sellingAmount: 1000,
          ),
        );
    await session.waitForPendingWrites();
    await pumpEventQueue();

    expect(
      container.read(appSessionControllerProvider).errorMessage,
      AppSessionController.persistenceErrorMessage,
    );
    expect(container.read(orderControllerProvider).lines, hasLength(1));

    store.failWrites = false;
    session.retryPersistence();
    await session.waitForPendingWrites();
    await pumpEventQueue();

    expect(
      container.read(appSessionControllerProvider).errorMessage,
      isNull,
    );
    expect(
      store.snapshots['owner-a']!.order.lines.single.productId,
      'product-a',
    );
  });

  test('restore failure opens an empty recoverable session', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()..failReads = true;
    final container = sessionContainer(auth: auth, store: store);

    container.read(appSessionControllerProvider);
    await pumpEventQueue();

    final session = container.read(appSessionControllerProvider);
    expect(session.status, AppSessionStatus.ready);
    expect(session.ownerId, 'owner-a');
    expect(
      session.errorMessage,
      AppSessionController.restoreErrorMessage,
    );
    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.catalog,
    );
  });
}
