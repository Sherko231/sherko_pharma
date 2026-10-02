import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_cart_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_runtime_selection.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_cart_analysis_models.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';
import 'package:sherko_pharma/features/session/application/app_session_controller.dart';
import 'package:sherko_pharma/features/session/data/app_session_store.dart';

import 'support/fake_app_session_store.dart';
import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer _container({
  required FakeAuthGateway auth,
  required FakeAppSessionStore store,
  required SdifCartAnalysisGateway gateway,
  bool useSdif = true,
  Duration debounce = Duration.zero,
}) {
  final overrides = [
    authGatewayProvider.overrideWithValue(auth),
    appSessionStoreProvider.overrideWithValue(store),
    sdifCartAnalysisGatewayProvider.overrideWithValue(gateway),
    sdifCartDebounceDurationProvider.overrideWithValue(debounce),
    if (useSdif)
      ddiRuntimeSelectionProvider.overrideWithValue(
        DdiRuntimeSelection.sdif(Uri.parse('http://127.0.0.1:3000/')),
      ),
  ];
  final container = ProviderContainer(overrides: overrides);
  final subscription = container.listen<SdifCartState>(
    sdifCartControllerProvider,
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

Future<void> _settle(ProviderContainer container, {int turns = 30}) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
    if (container.read(sdifCartControllerProvider).status !=
        SdifCartStatus.loading) {
      return;
    }
  }
}

AppSessionSnapshot _savedCart(String ownerId) {
  return AppSessionSnapshot(
    ownerId: ownerId,
    destination: AppDestination.order,
    order: const OrderState(
      lines: [
        OrderLine(
          productId: 'p1',
          displayName: 'Product 1',
          quantity: 2,
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
  test('SDIF selection analyzes a restored distinct Cart product set', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = _savedCart('owner-a');
    final gateway = _FakeSdifCartGateway();
    final container = _container(auth: auth, store: store, gateway: gateway);

    await pumpEventQueue();
    await _settle(container);

    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.productIds, ['p1', 'p2']);
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.ready);
  });

  test('quantity-only changes do not rerun SDIF Cart analysis', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final gateway = _FakeSdifCartGateway();
    final container = _container(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await _settle(container);
    expect(gateway.calls, hasLength(1));

    order.increment('p1');
    order.decrement('p1');
    expect(
      order.addProduct(testProduct(id: 'p1', sellingAmount: 1000)),
      OrderActionResult.incremented,
    );
    await pumpEventQueue();

    expect(gateway.calls, hasLength(1));
  });

  test('clearing Cart invalidates an in-flight SDIF result', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final completer = Completer<SdifCartAnalysisResult>();
    final gateway = _FakeSdifCartGateway(
      handler: (productIds, isCurrent) => completer.future,
    );
    final container = _container(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await pumpEventQueue();

    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.isCurrent?.call(), isTrue);

    order.clear();
    await pumpEventQueue();
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.idle);
    expect(gateway.calls.single.isCurrent?.call(), isFalse);

    completer.complete(_analysis(const ['p1', 'p2']));
    await pumpEventQueue();
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.idle);
  });

  test('sign-out invalidates in-flight SDIF result', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final completer = Completer<SdifCartAnalysisResult>();
    final gateway = _FakeSdifCartGateway(
      handler: (productIds, isCurrent) => completer.future,
    );
    final container = _container(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    final session = container.read(appSessionControllerProvider.notifier);
    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await pumpEventQueue();
    expect(gateway.calls, hasLength(1));

    session.prepareForSignOut();
    auth.emitIdentity(null);
    await pumpEventQueue();

    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.idle);
    expect(gateway.calls.single.isCurrent?.call(), isFalse);

    completer.complete(_analysis(const ['p1', 'p2']));
    await pumpEventQueue();
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.idle);
  });

  test('transport failure is retryable while Cart identity stays current', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    var attempts = 0;
    final gateway = _FakeSdifCartGateway(
      handler: (productIds, isCurrent) async {
        attempts += 1;
        if (attempts == 1) {
          throw const SdifTransportException('offline');
        }
        return _analysis(productIds);
      },
    );
    final container = _container(
      auth: auth,
      store: FakeAppSessionStore(),
      gateway: gateway,
    );

    await pumpEventQueue();
    final order = container.read(orderControllerProvider.notifier);
    order.addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    order.addProduct(testProduct(id: 'p2', sellingAmount: 2000));
    await _settle(container);

    final failed = container.read(sdifCartControllerProvider);
    expect(failed.status, SdifCartStatus.error);
    expect(failed.failureKind, SdifCartFailureKind.transport);
    expect(failed.canRetry, isTrue);

    container.read(sdifCartControllerProvider.notifier).retry();
    await _settle(container);

    expect(attempts, 2);
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.ready);
  });

  test('Interaction Checker selection does not run SDIF Cart lifecycle', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = _savedCart('owner-a');
    final gateway = _FakeSdifCartGateway();
    final container = _container(
      auth: auth,
      store: store,
      gateway: gateway,
      useSdif: false,
    );

    await pumpEventQueue();

    expect(gateway.calls, isEmpty);
    expect(container.read(sdifCartControllerProvider).status, SdifCartStatus.idle);
  });
}

SdifCartAnalysisResult _analysis(List<String> productIds) {
  return const SdifCartAnalysisResult(
    products: [],
    providerResolutionGaps: [],
    identityPairs: [],
    productPairs: [],
    uniqueEligibleIdentityCount: 0,
    providerResolvedIdentityCount: 0,
    providerBatchCount: 0,
    providerHitCount: 0,
    retainedFindingCount: 0,
    exactDuplicateHitCount: 0,
  );
}

typedef _Handler = Future<SdifCartAnalysisResult> Function(
  List<String> productIds,
  bool Function()? isCurrent,
);

class _FakeSdifCartGateway implements SdifCartAnalysisGateway {
  _FakeSdifCartGateway({this.handler});

  final _Handler? handler;
  final List<_Call> calls = [];

  @override
  Future<SdifCartAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) async {
    final captured = List<String>.unmodifiable(productIds);
    calls.add(_Call(captured, isCurrent));
    final custom = handler;
    if (custom != null) {
      return custom(captured, isCurrent);
    }
    return _analysis(captured);
  }
}

class _Call {
  const _Call(this.productIds, this.isCurrent);

  final List<String> productIds;
  final bool Function()? isCurrent;
}
