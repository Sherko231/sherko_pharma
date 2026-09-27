import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  required Size size,
  FakeCatalogRepository? catalog,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final gateway = FakeAuthGateway(
    initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
  );
  addTearDown(gateway.dispose);

  await tester.pumpWidget(
    AppBootstrap(
      runtime: AppRuntime.configured(
        gateway,
        catalogRepository: catalog ?? FakeCatalogRepository(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final shell = find.byType(AppShell);
  return ProviderScope.containerOf(tester.element(shell));
}

void main() {
  testWidgets('phone opens one compact Cart workspace without navigation', (
    tester,
  ) async {
    final container = await pumpShell(
      tester,
      size: const Size(360, 800),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('cart-workspace')), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
    expect(find.byKey(const Key('catalog-search-field')), findsOneWidget);
    expect(find.byKey(const Key('order-new')), findsOneWidget);
    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.order,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps Cart and manual search on the same page', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1280, 720),
    );

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('cart-workspace')), findsOneWidget);
    expect(find.byKey(const Key('catalog-search-panel')), findsOneWidget);
    expect(find.byKey(const Key('order-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume refreshes the active embedded catalog query', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository()
      ..searchResults = [
        testProduct(id: 'p1', nameEn: 'Old result', revision: 1),
      ];

    await pumpShell(
      tester,
      size: const Size(390, 800),
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Old result'), findsOneWidget);

    catalog.searchResults = [
      testProduct(id: 'p1', nameEn: 'Fresh result', revision: 2),
    ];

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(find.text('Fresh result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
  });
}
