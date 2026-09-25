import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> pumpOrderApp(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthGateway(
    initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
  );
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    AppBootstrap(
      runtime: AppRuntime.configured(
        auth,
        catalogRepository: FakeCatalogRepository(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(AppShell));
  return ProviderScope.containerOf(context);
}

void main() {
  testWidgets('order workspace shows mixed totals and quantity controls', (
    tester,
  ) async {
    final container = await pumpOrderApp(tester);
    final controller = container.read(orderControllerProvider.notifier);

    controller.addProduct(
      testProduct(
        id: 'syp',
        nameEn: 'SYP product',
        sellingAmount: 1000,
        currency: 'SYP',
      ),
    );
    controller.addProduct(
      testProduct(
        id: 'usd',
        nameEn: 'USD product',
        sellingAmount: 5,
        currency: 'USD',
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-lines')), findsOneWidget);
    expect(find.text('1000 SYP'), findsWidgets);
    expect(find.text('5 USD'), findsWidgets);

    await tester.tap(find.byKey(const Key('order-increment-syp')));
    await tester.pump();

    expect(find.byKey(const Key('order-quantity-syp')), findsOneWidget);
    final lineAmount = tester.widget<Text>(
      find.byKey(const Key('order-line-amount-syp')),
    );
    expect(lineAmount.data, '2000 SYP');
    expect(
      find.descendant(
        of: find.byKey(const Key('order-total-syp')),
        matching: find.text('2000 SYP'),
      ),
      findsOneWidget,
    );
    expect(find.text('5 USD'), findsWidgets);

    await tester.tap(find.byKey(const Key('order-remove-usd')));
    await tester.pump();

    expect(find.byKey(const Key('order-line-usd')), findsNothing);
    expect(
      container.read(orderControllerProvider).totalUsd,
      0,
    );
  });

  testWidgets('New Order cancel preserves and confirm clears', (tester) async {
    final container = await pumpOrderApp(tester);
    container
        .read(orderControllerProvider.notifier)
        .addProduct(testProduct(id: 'p1', sellingAmount: 1000));
    await tester.pump();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-order-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-order-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('order-line-p1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('order-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-order-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-empty')), findsOneWidget);
    expect(container.read(orderControllerProvider).lines, isEmpty);
  });

  testWidgets('empty New Order does not ask for confirmation', (tester) async {
    await pumpOrderApp(tester);

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-new')));
    await tester.pump();

    expect(find.byKey(const Key('new-order-dialog')), findsNothing);
    expect(find.byKey(const Key('order-empty')), findsOneWidget);
  });
}
