import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/interaction_checker_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';
import 'package:sherko_pharma/features/scanning/application/barcode_scan_controller.dart';
import 'package:sherko_pharma/features/session/application/app_session_controller.dart';
import 'package:sherko_pharma/features/session/data/app_session_store.dart';

import 'support/fake_app_session_store.dart';
import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer ddiContainer({
  required FakeAuthGateway auth,
  required FakeAppSessionStore store,
  required DdiAnalysisGateway gateway,
  Duration debounce = Duration.zero,
}) {
  final container = ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(auth),
      appSessionStoreProvider.overrideWithValue(store),
      ddiAnalysisGatewayProvider.overrideWithValue(gateway),
      ddiCartDebounceDurationProvider.overrideWithValue(debounce),
    ],
  );
  final subscription = container.listen<DdiCartState>(
    ddiCartControllerProvider,
    (previous, next) {},
    fireImmediately: true,
  );
  addTearDown(() async {
    subscription.close();
    container.dispose();
    await auth.dispose();
  });
  return container;
}

Future<void> settleDdi(
  ProviderContainer container, {
  int turns = 30,
}) async {
  for (var index = 0; index < turns; index += 1) {
    await Future<void>.delayed(Duration.zero);
    final status = container.read(ddiCartControllerProvider).status;
    if (status != DdiCartStatus.loading) {
      return;
    }
  }
}

AppSessionSnapshot _savedTwoProductCart(String ownerId) {
  return AppSessionSnapshot(
    ownerId: ownerId,
    destination: AppDestination.order,
    order: const OrderState(
      lines: [
        OrderLine(
          productId: 'p1',
          displayName: 'Product 1',
          quantity: 3,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'p2',
          displayName: 'Product 2',
          quantity: 1,
          unitAmount: 2000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
    ),
  );
}

void main() {
  test('same-owner restored Cart triggers fresh online DDI analysis', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = _savedTwoProductCart('owner-a');
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      return _analysis(productIds);
    });
    final container = ddiContainer(
      auth: auth,
      store: store,
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();
    await settleDdi(container);

    expect(
      container.read(appSessionControllerProvider).status,
      AppSessionStatus.ready,
    );
    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.productIds, ['p1', 'p2']);

    final ddi = container.read(ddiCartControllerProvider);
    expect(ddi.status, DdiCartStatus.ready);
    expect(ddi.productIds, ['p1', 'p2']);
    expect(ddi.analysis, isNotNull);
  });

  test('quantity-only changes and re-adding existing product do not reanalyze', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      return _analysis(productIds);
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await settleDdi(container);
    expect(gateway.calls, hasLength(1));

    order.increment('p1');
    order.decrement('p1');
    expect(
      order.addProduct(testProduct(id: 'p1', sellingAmount: 1000)),
      OrderActionResult.incremented,
    );
    await pumpEventQueue();

    expect(gateway.calls, hasLength(1));
    expect(
      container.read(orderControllerProvider).lines
          .singleWhere((line) => line.productId == 'p1')
          .quantity,
      2,
    );
  });

  test('rapid distinct additions coalesce into one latest product-set analysis', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      return _analysis(productIds);
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
      debounce: const Duration(milliseconds: 20),
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    order.addProduct(testProduct(id: 'p3', sellingAmount: 3000));

    await Future<void>.delayed(const Duration(milliseconds: 30));
    await settleDdi(container);

    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.productIds, ['p1', 'p2', 'p3']);
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.ready,
    );
  });

  test('removing a distinct product analyzes the remaining set', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      return _analysis(productIds);
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    for (final productId in ['p1', 'p2', 'p3']) {
      order.addProduct(testProduct(id: productId, sellingAmount: 1000));
    }
    await settleDdi(container);
    expect(gateway.calls.single.productIds, ['p1', 'p2', 'p3']);

    order.remove('p3');
    await settleDdi(container);

    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.last.productIds, ['p1', 'p2']);
  });

  test('New Order invalidates in-flight DDI and late result cannot repopulate state', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gate = Completer<DdiAnalysisResult>();
    final gateway = _FakeDdiGateway((productIds, isCurrent) {
      return gate.future;
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await pumpEventQueue();

    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.isCurrent?.call(), isTrue);
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.loading,
    );

    order.clear();
    await pumpEventQueue();

    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.idle,
    );
    expect(container.read(ddiCartControllerProvider).productIds, isEmpty);
    expect(gateway.calls.single.isCurrent?.call(), isFalse);

    gate.complete(_analysis(const ['p1', 'p2']));
    await pumpEventQueue();

    final ddi = container.read(ddiCartControllerProvider);
    expect(ddi.status, DdiCartStatus.idle);
    expect(ddi.analysis, isNull);
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  test('sign-out invalidates in-flight DDI and does not expose late result', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gate = Completer<DdiAnalysisResult>();
    final gateway = _FakeDdiGateway((productIds, isCurrent) => gate.future);
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    final session =
        container.read(appSessionControllerProvider.notifier);
    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await pumpEventQueue();
    expect(gateway.calls, hasLength(1));

    session.prepareForSignOut();
    auth.emitIdentity(null);
    await pumpEventQueue();

    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.idle,
    );
    expect(container.read(orderControllerProvider).lines, isEmpty);

    auth.emitIdentity(const AuthIdentity(userId: 'owner-b'));
    await pumpEventQueue();

    gate.complete(_analysis(const ['p1', 'p2']));
    await pumpEventQueue();

    final ddi = container.read(ddiCartControllerProvider);
    expect(container.read(appSessionControllerProvider).ownerId, 'owner-b');
    expect(ddi.status, DdiCartStatus.idle);
    expect(ddi.analysis, isNull);
  });

  test('session persistence schema contains no DDI result state', () {
    final json = _savedTwoProductCart('owner-a').toJson();

    expect(json.keys, isNot(contains('ddi')));
    expect(json.keys, isNot(contains('interactions')));
    expect(json.keys, isNot(contains('interaction_results')));
    expect(json['order_lines'], hasLength(2));
  });

  test('missing DDI runtime dependency is explicit only when analysis is needed', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore();
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(auth),
        appSessionStoreProvider.overrideWithValue(store),
        ddiCartDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
    );
    final subscription = container.listen<DdiCartState>(
      ddiCartControllerProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await auth.dispose();
    });

    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);

    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    await pumpEventQueue();
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.idle,
    );

    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await pumpEventQueue();
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.unavailable,
    );
  });

  test('DDI failure preserves Cart and retry can reach ready', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    var attempts = 0;
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      attempts += 1;
      if (attempts == 1) {
        throw const InteractionCheckerTransportException('offline');
      }
      return _analysis(productIds);
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await settleDdi(container);

    final failed = container.read(ddiCartControllerProvider);
    expect(failed.status, DdiCartStatus.error);
    expect(failed.failureKind, DdiCartFailureKind.transport);
    expect(failed.canRetry, isTrue);
    expect(container.read(orderControllerProvider).lines, hasLength(2));
    expect(container.read(orderControllerProvider).totalSyp, 3000);

    container.read(ddiCartControllerProvider.notifier).retry();
    await settleDdi(container);

    expect(attempts, 2);
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.ready,
    );
    expect(container.read(orderControllerProvider).totalSyp, 3000);
  });

  test('scanner add returns success without waiting for blocked DDI analysis', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gate = Completer<DdiAnalysisResult>();
    final gateway = _FakeDdiGateway((productIds, isCurrent) => gate.future);
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();

    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));

    final catalog = FakeCatalogRepository()
      ..products['p2'] = testProduct(
        id: 'p2',
        sellingAmount: 2000,
        barcode: 'SCAN-2',
        barcode2: null,
      );
    final scanner = BarcodeScanController(
      catalog: catalog,
      order: order,
    );

    final result = await scanner.accept('SCAN-2');

    expect(result?.status, BarcodeScanStatus.added);
    expect(
      container.read(orderControllerProvider).lines.map(
            (line) => line.productId,
          ),
      ['p1', 'p2'],
    );

    await pumpEventQueue();
    expect(gateway.calls, hasLength(1));
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.loading,
    );

    gate.complete(_analysis(const ['p1', 'p2']));
    await settleDdi(container);
    expect(
      container.read(ddiCartControllerProvider).status,
      DdiCartStatus.ready,
    );
  });

  test('rate-limit failure preserves Retry-After for later UI', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gateway = _FakeDdiGateway((productIds, isCurrent) async {
      throw const InteractionCheckerRateLimitException(
        retryAfter: Duration(seconds: 45),
      );
    });
    final container = ddiContainer(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    container.read(ddiCartControllerProvider);
    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await settleDdi(container);

    final ddi = container.read(ddiCartControllerProvider);
    expect(ddi.status, DdiCartStatus.error);
    expect(ddi.failureKind, DdiCartFailureKind.rateLimited);
    expect(ddi.retryAfter, const Duration(seconds: 45));
  });
}

class _DdiCall {
  const _DdiCall({
    required this.productIds,
    required this.isCurrent,
  });

  final List<String> productIds;
  final bool Function()? isCurrent;
}

class _FakeDdiGateway implements DdiAnalysisGateway {
  _FakeDdiGateway(this.handler);

  final Future<DdiAnalysisResult> Function(
    List<String> productIds,
    bool Function()? isCurrent,
  ) handler;
  final List<_DdiCall> calls = [];

  @override
  Future<DdiAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) {
    final captured = List<String>.unmodifiable(productIds);
    calls.add(
      _DdiCall(
        productIds: captured,
        isCurrent: isCurrent,
      ),
    );
    return handler(captured, isCurrent);
  }
}

DdiAnalysisResult _analysis(List<String> productIds) {
  return DdiAnalysisResult(
    products: const [],
    providerUnresolved: const [],
    productPairs: const [],
    providerNotices: const [],
    uniqueIngredientCount: productIds.length,
    providerBatchCount: productIds.length < 2 ? 0 : 1,
  );
}
