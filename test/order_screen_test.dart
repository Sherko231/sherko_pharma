import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/catalog/application/scoped_catalog_refresh_controller.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> pumpOrderApp(
  WidgetTester tester, {
  FakeCatalogRepository? catalog,
}) async {
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
        catalogRepository: catalog ?? FakeCatalogRepository(),
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

  testWidgets('price change notice preserves total until explicit update', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository()
      ..products['p1'] = testProduct(
        id: 'p1',
        sellingAmount: 1500,
        currency: 'SYP',
        revision: 5,
      );
    final container = await pumpOrderApp(
      tester,
      catalog: catalog,
    );
    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'p1',
            sellingAmount: 1000,
            currency: 'SYP',
            revision: 4,
          ),
        );

    await container
        .read(scopedCatalogRefreshControllerProvider.notifier)
        .refreshNow();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-price-change-p1')), findsOneWidget);
    expect(find.textContaining('1000 SYP to 1500 SYP'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('order-total-syp')),
        matching: find.text('1000 SYP'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('order-price-update-p1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-price-change-p1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('order-total-syp')),
        matching: find.text('1500 SYP'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalid latest price shows notice without update action', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository()
      ..products['p1'] = testProduct(
        id: 'p1',
        sellingAmount: 0,
        currency: 'SYP',
        revision: 5,
      );
    final container = await pumpOrderApp(
      tester,
      catalog: catalog,
    );
    container.read(orderControllerProvider.notifier).addProduct(
          testProduct(
            id: 'p1',
            sellingAmount: 1000,
            currency: 'SYP',
            revision: 4,
          ),
        );

    await container
        .read(scopedCatalogRefreshControllerProvider.notifier)
        .refreshNow();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-price-change-p1')), findsOneWidget);
    expect(find.textContaining('latest catalog price is invalid'), findsOneWidget);
    expect(find.byKey(const Key('order-price-update-p1')), findsNothing);
    expect(container.read(orderControllerProvider).lines.single.unitAmount, 1000);
  });

}
