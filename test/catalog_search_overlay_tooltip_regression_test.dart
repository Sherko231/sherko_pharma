import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

void main() {
  testWidgets(
    'search result action hover does not create nested tooltip overlays',
    (tester) async {
      tester.view.physicalSize = const Size(1264, 681);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = FakeAuthGateway(
        initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
      );
      addTearDown(auth.dispose);

      final product = testProduct(
        id: 'hover-target',
        nameEn: 'Hover Target',
        sellingAmount: 12000,
      );
      final catalog = FakeCatalogRepository()
        ..searchResults = [product]
        ..products[product.id] = product;

      await tester.pumpWidget(
        AppBootstrap(
          runtime: AppRuntime.configured(
            auth,
            catalogRepository: catalog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('catalog-search-field')),
        'Hover',
      );
      await tester.pump(const Duration(milliseconds: 181));
      await tester.pumpAndSettle();

      final overlay = find.byKey(const Key('catalog-search-overlay'));
      final alternatives = find.byKey(
        const Key('catalog-alternatives-hover-target'),
      );
      final addToCart = find.byKey(
        const Key('catalog-add-to-order-hover-target'),
      );

      expect(overlay, findsOneWidget);
      expect(alternatives, findsOneWidget);
      expect(addToCart, findsOneWidget);
      expect(
        find.descendant(of: overlay, matching: find.byType(Tooltip)),
        findsNothing,
      );

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Alternatives'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to cart'), findsOneWidget);
      semantics.dispose();

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);

      await mouse.moveTo(tester.getCenter(alternatives));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      await mouse.moveTo(tester.getCenter(addToCart));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      await mouse.removePointer();

      await tester.tap(addToCart);
      await tester.pumpAndSettle();

      expect(find.text('Added to cart.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
