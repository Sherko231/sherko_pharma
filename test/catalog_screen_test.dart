import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<void> pumpCatalog(
  WidgetTester tester, {
  required FakeCatalogRepository catalog,
  Size size = const Size(390, 800),
}) async {
  tester.view.physicalSize = size;
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
  testWidgets('initial catalog state explains searchable fields', (tester) async {
    await pumpCatalog(
      tester,
      catalog: FakeCatalogRepository(),
    );

    expect(find.byKey(const Key('catalog-search-idle')), findsOneWidget);
    expect(find.text('Search the catalog'), findsOneWidget);
    expect(
      find.textContaining('Arabic or English product name'),
      findsOneWidget,
    );
  });

  testWidgets('phone search renders Arabic data and opens current detail', (
    tester,
  ) async {
    final product = testProduct(
      manufacturer: null,
      notes: 'Owner note',
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [product]
      ..products[product.id] = product;

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'أسبرين',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-search-results')), findsOneWidget);
    final resultCard = find.byKey(Key('catalog-result-${product.id}'));
    expect(
      find.descendant(
        of: resultCard,
        matching: find.text('Aspirin'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: resultCard,
        matching: find.text('أسبرين'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: resultCard,
        matching: find.text('15000 SYP'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(Key('catalog-result-${product.id}')));
    await tester.pumpAndSettle();

    expect(catalog.detailCalls, [product.id]);
    expect(find.byKey(const Key('catalog-detail-content')), findsOneWidget);
    expect(find.text('Acetylsalicylic acid'), findsOneWidget);
    expect(find.text('0012345'), findsOneWidget);
    expect(find.text('ALT-001'), findsOneWidget);
    expect(find.text('Not provided'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful zero-row search shows no-results state', (
    tester,
  ) async {
    await pumpCatalog(
      tester,
      catalog: FakeCatalogRepository(),
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-search-empty')), findsOneWidget);
    expect(find.text('No products found'), findsOneWidget);
    expect(find.byKey(const Key('catalog-search-error')), findsNothing);
  });

  testWidgets('repository failure shows error with retry', (tester) async {
    final catalog = FakeCatalogRepository()
      ..onSearch = (query, limit) async {
        throw const CatalogRepositoryException();
      };

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'failure',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-search-error')), findsOneWidget);
    expect(find.text('Could not load the catalog'), findsOneWidget);
    expect(find.byKey(const Key('catalog-search-retry')), findsOneWidget);
  });

  testWidgets('desktop catalog stays readable without overflow', (tester) async {
    final product = testProduct(
      nameEn: 'A long English medicine product name for layout verification',
      nameAr: 'اسم دواء عربي طويل لاختبار عرض النص بصورة مقروءة',
      composition: 'A long composition value for responsive layout verification',
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [product]
      ..products[product.id] = product;

    await pumpCatalog(
      tester,
      catalog: catalog,
      size: const Size(1280, 720),
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'دواء',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(find.textContaining('اسم دواء عربي طويل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog exposes New product and detail exposes Edit product', (
    tester,
  ) async {
    final product = testProduct();
    final catalog = FakeCatalogRepository()
      ..searchResults = [product]
      ..products[product.id] = product;

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    expect(find.byKey(const Key('catalog-new-product')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('catalog-result-${product.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-edit-product')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-edit-product')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-form')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('product-field-name-en')),
    );
    expect(field.controller?.text, 'Aspirin');
  });


  testWidgets('catalog Add to order captures product without catalog mutation', (
    tester,
  ) async {
    final product = testProduct(
      id: 'order-product',
      sellingAmount: 1250,
      currency: 'SYP',
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [product];

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-add-to-order-order-product')),
    );
    await tester.pumpAndSettle();

    final shellContext = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shellContext);
    final order = container.read(orderControllerProvider);

    expect(order.lines, hasLength(1));
    expect(order.lines.single.productId, 'order-product');
    expect(order.lines.single.unitAmount, 1250);
    expect(order.lines.single.currency, 'SYP');
    expect(catalog.createIds, isEmpty);
    expect(catalog.updateOriginals, isEmpty);
    expect(find.text('Added to order.'), findsOneWidget);
  });

  testWidgets('catalog rejects zero-price product with clear feedback', (
    tester,
  ) async {
    final product = testProduct(
      id: 'zero-price',
      sellingAmount: 0,
      currency: 'SYP',
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [product];

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-add-to-order-zero-price')),
    );
    await tester.pumpAndSettle();

    final shellContext = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shellContext);

    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      find.text(
        'Set a positive SYP or USD selling price before adding this product.',
      ),
      findsOneWidget,
    );
  });


  testWidgets('Add to order revalidates and captures latest server price', (
    tester,
  ) async {
    final searchProduct = testProduct(
      id: 'latest-price',
      sellingAmount: 1000,
      currency: 'SYP',
      revision: 4,
    );
    final latestProduct = testProduct(
      id: 'latest-price',
      sellingAmount: 1500,
      currency: 'SYP',
      revision: 5,
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [searchProduct]
      ..products[searchProduct.id] = latestProduct;

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(find.text('1000 SYP'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('catalog-add-to-order-latest-price')),
    );
    await tester.pumpAndSettle();

    final shellContext = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shellContext);
    final line = container.read(orderControllerProvider).lines.single;

    expect(catalog.detailCalls, contains('latest-price'));
    expect(line.unitAmount, 1500);
    expect(line.currency, 'SYP');
    expect(line.productRevision, 5);
  });

  testWidgets('failed revalidation does not add a stale search result', (
    tester,
  ) async {
    final product = testProduct(
      id: 'stale-product',
      sellingAmount: 1000,
      currency: 'SYP',
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [product]
      ..onGet = (_) async {
        throw const CatalogRepositoryException();
      };

    await pumpCatalog(
      tester,
      catalog: catalog,
    );

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'Aspirin',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-add-to-order-stale-product')),
    );
    await tester.pumpAndSettle();

    final shellContext = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shellContext);

    expect(container.read(orderControllerProvider).lines, isEmpty);
    expect(
      find.textContaining('Could not refresh this product before adding it'),
      findsOneWidget,
    );
  });

}
