import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/catalog/application/catalog_search_controller.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_alternative.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';
import 'package:sherko_pharma/features/catalog/presentation/catalog_alternatives_sheet.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

CatalogAlternative alternative({
  required CatalogAlternativeGroup group,
  required CatalogProduct product,
  int position = 1,
  CatalogNormalizationStatus status =
      CatalogNormalizationStatus.highConfidence,
}) {
  return CatalogAlternative(
    group: group,
    groupPosition: position,
    normalizationStatus: status,
    product: product,
  );
}

Future<ProviderContainer> pumpSheet(
  WidgetTester tester, {
  required FakeCatalogRepository catalog,
  required CatalogProduct target,
}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(catalog),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CatalogAlternativesSheet(
            targetProduct: target,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final context = tester.element(find.byType(CatalogAlternativesSheet));
  return ProviderScope.containerOf(context);
}

Future<void> pumpAlternativesApp(
  WidgetTester tester, {
  required FakeCatalogRepository catalog,
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
        catalogRepository: catalog,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('alternatives sheet separates groups and required product data', (
    tester,
  ) async {
    final target = testProduct(id: 'target');
    final exact = testProduct(
      id: 'exact',
      nameEn: 'Exact Brand',
      manufacturer: 'Asia Pharma',
      strength: '500 mg',
      dosageForm: 'Tablet',
      sellingAmount: 12000,
    );
    final differentStrength = testProduct(
      id: 'strength',
      nameEn: 'Strength Brand',
      manufacturer: 'Maker B',
      strength: '650 mg',
      dosageForm: 'Tablet',
      sellingAmount: 14000,
    );
    final differentForm = testProduct(
      id: 'form',
      nameEn: 'Form Brand',
      manufacturer: 'Maker C',
      strength: '500 mg',
      dosageForm: 'Capsule',
      sellingAmount: 16000,
    );
    final completer = Completer<List<CatalogAlternative>>();
    final catalog = FakeCatalogRepository()
      ..onAlternatives = (_, __) => completer.future;

    await pumpSheet(
      tester,
      catalog: catalog,
      target: target,
    );

    expect(
      find.byKey(const Key('catalog-alternatives-loading')),
      findsOneWidget,
    );

    completer.complete([
      alternative(
        group: CatalogAlternativeGroup.exact,
        product: exact,
      ),
      alternative(
        group: CatalogAlternativeGroup.sameIngredientsDifferentStrength,
        product: differentStrength,
      ),
      alternative(
        group: CatalogAlternativeGroup.sameIngredientsDifferentForm,
        product: differentForm,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-disclaimer')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Catalog grouping only. These matches do not establish clinical interchangeability or prescribing suitability.',
      ),
      findsOneWidget,
    );
    expect(find.text('Same ingredients, strength & form'), findsOneWidget);
    expect(find.text('Same ingredients · different strength'), findsOneWidget);
    expect(
      find.text('Same ingredients & strength · different form'),
      findsOneWidget,
    );

    expect(find.text('Exact Brand'), findsOneWidget);
    expect(find.text('Company: '), findsWidgets);
    expect(find.text('Asia Pharma'), findsOneWidget);
    expect(find.text('Strength: '), findsWidgets);
    expect(find.text('500 mg'), findsWidgets);
    expect(find.text('Form: '), findsWidgets);
    expect(find.text('Tablet'), findsWidgets);
    expect(find.text('12,000 SYP'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-alternative-add-exact')),
      findsOneWidget,
    );
  });

  testWidgets('alternatives sheet handles error retry and empty state', (
    tester,
  ) async {
    final target = testProduct(id: 'target');
    var fail = true;
    final catalog = FakeCatalogRepository()
      ..onAlternatives = (_, __) async {
        if (fail) {
          throw const CatalogRepositoryException();
        }
        return const <CatalogAlternative>[];
      };

    await pumpSheet(
      tester,
      catalog: catalog,
      target: target,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-error')),
      findsOneWidget,
    );

    fail = false;
    await tester.tap(
      find.byKey(const Key('catalog-alternatives-retry')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-empty')),
      findsOneWidget,
    );
    expect(catalog.alternativeCalls.length, 2);
  });

  testWidgets('alternative Add revalidates current product before capture', (
    tester,
  ) async {
    final target = testProduct(id: 'target');
    final stale = testProduct(
      id: 'candidate',
      nameEn: 'Candidate',
      sellingAmount: 1000,
      revision: 3,
    );
    final latest = testProduct(
      id: 'candidate',
      nameEn: 'Candidate',
      sellingAmount: 1500,
      revision: 4,
    );
    final catalog = FakeCatalogRepository()
      ..alternativeResults = [
        alternative(
          group: CatalogAlternativeGroup.exact,
          product: stale,
        ),
      ]
      ..products[latest.id] = latest;

    final container = await pumpSheet(
      tester,
      catalog: catalog,
      target: target,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-alternative-add-candidate')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final order = container.read(orderControllerProvider);
    expect(order.lines, hasLength(1));
    expect(order.lines.single.productId, 'candidate');
    expect(order.lines.single.unitAmount, 1500);
    expect(order.lines.single.productRevision, 4);
    expect(catalog.detailCalls, contains('candidate'));
    expect(find.text('Added to cart.'), findsOneWidget);
  });

  testWidgets('Cart search row opens alternatives sheet', (
    tester,
  ) async {
    final target = testProduct(id: 'cart-target');
    final catalog = FakeCatalogRepository()
      ..searchResults = [target]
      ..products[target.id] = target;

    await pumpAlternativesApp(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 181));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-cart-target')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('catalog-alternatives-cart-target')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-sheet')),
      findsOneWidget,
    );
    expect(catalog.alternativeCalls.single.query, 'cart-target');
  });

  testWidgets('Product Detail opens the same alternatives sheet', (
    tester,
  ) async {
    final target = testProduct(id: 'detail-target');
    final catalog = FakeCatalogRepository()
      ..searchResults = [target]
      ..products[target.id] = target;

    await pumpAlternativesApp(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 181));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-result-detail-target')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-detail-alternatives')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('catalog-detail-alternatives')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-alternatives-sheet')),
      findsOneWidget,
    );
    expect(catalog.alternativeCalls.single.query, 'detail-target');
  });
}
