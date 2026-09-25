import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';
import 'package:sherko_pharma/features/session/data/app_session_store.dart';
import 'package:sherko_pharma/features/session/application/app_session_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_app_session_store.dart';
import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';


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

Future<ProviderContainer> pumpSessionApp(
  WidgetTester tester, {
  required FakeAuthGateway auth,
  required FakeAppSessionStore store,
}) async {
  await tester.pumpWidget(
    AppBootstrap(
      runtime: AppRuntime.configured(
        auth,
        catalogRepository: FakeCatalogRepository(),
        appSessionStore: store,
      ),
    ),
  );
  await tester.pumpAndSettle();

  final shell = find.byType(AppShell);
  if (shell.evaluate().isEmpty) {
    throw StateError('Expected a restored protected shell.');
  }
  return ProviderScope.containerOf(tester.element(shell));
}

void main() {
  testWidgets('restart-style restore opens saved page with exact order', (
    tester,
  ) async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = savedOrder(
        ownerId: 'owner-a',
        quantity: 3,
        unitAmount: 1000,
      );
    addTearDown(auth.dispose);

    await pumpSessionApp(
      tester,
      auth: auth,
      store: store,
    );

    expect(find.byKey(const Key('order-workspace')), findsOneWidget);
    expect(find.byKey(const Key('order-line-p1')), findsOneWidget);
    expect(find.text('Saved product'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('3000 SYP'), findsWidgets);
  });

  testWidgets('confirmed New Order remains empty after a fresh app restore', (
    tester,
  ) async {
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = savedOrder(ownerId: 'owner-a');
    final auth1 = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    addTearDown(auth1.dispose);

    final container = await pumpSessionApp(
      tester,
      auth: auth1,
      store: store,
    );

    await tester.tap(find.byKey(const Key('order-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-order-confirm')));
    await tester.pumpAndSettle();

    await container
        .read(appSessionControllerProvider.notifier)
        .waitForPendingWrites();

    expect(store.snapshots['owner-a']!.order.lines, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final auth2 = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    addTearDown(auth2.dispose);

    await pumpSessionApp(
      tester,
      auth: auth2,
      store: store,
    );

    expect(find.byKey(const Key('order-workspace')), findsOneWidget);
    expect(find.byKey(const Key('order-empty')), findsOneWidget);
    expect(find.byKey(const Key('order-line-p1')), findsNothing);
  });

  testWidgets('local persistence failure is visible and Retry clears it', (
    tester,
  ) async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner-a'),
    );
    final store = FakeAppSessionStore()..failWrites = true;
    addTearDown(auth.dispose);

    final container = await pumpSessionApp(
      tester,
      auth: auth,
      store: store,
    );

    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'product-a',
            sellingAmount: 1000,
          ),
        );
    await container
        .read(appSessionControllerProvider.notifier)
        .waitForPendingWrites();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-session-error')), findsOneWidget);
    expect(find.byKey(const Key('local-session-retry')), findsOneWidget);

    store.failWrites = false;
    await tester.tap(find.byKey(const Key('local-session-retry')));
    await tester.pump();
    await container
        .read(appSessionControllerProvider.notifier)
        .waitForPendingWrites();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-session-error')), findsNothing);
    expect(
      store.snapshots['owner-a']!.order.lines.single.productId,
      'product-a',
    );
  });

  testWidgets('sign-out hides A order and B does not restore it', (
    tester,
  ) async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(
        userId: 'owner-a',
        email: 'a@example.test',
      ),
    );
    final store = FakeAppSessionStore()
      ..snapshots['owner-a'] = savedOrder(ownerId: 'owner-a');
    addTearDown(auth.dispose);

    await pumpSessionApp(
      tester,
      auth: auth,
      store: store,
    );
    expect(find.text('Saved product'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-out-button')));
    await tester.pumpAndSettle();

    expect(find.text('Owner sign in'), findsOneWidget);
    expect(find.text('Saved product'), findsNothing);

    auth.signInUserId = 'owner-b';
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'b@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'temporary-secret',
    );
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(const Key('catalog-workspace')), findsOneWidget);
    expect(find.text('Saved product'), findsNothing);

    final shellContainer = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(shellContainer.read(orderControllerProvider).lines, isEmpty);
  });
}
