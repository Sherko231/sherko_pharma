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

void main() {
  testWidgets('phone layout uses NavigationBar and Riverpod selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
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
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('catalog-workspace')), findsOneWidget);

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-workspace')), findsOneWidget);

    final shellContext = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shellContext);

    expect(
      container.read(appNavigationControllerProvider),
      AppDestination.order,
    );
  });

  testWidgets('desktop layout uses NavigationRail', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
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
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('catalog-workspace')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
