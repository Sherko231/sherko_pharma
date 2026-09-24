import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/catalog/application/catalog_search_controller.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';
import 'package:sherko_pharma/features/catalog/presentation/catalog_product_form_screen.dart';

import 'support/fake_catalog_repository.dart';

class _FormHost extends StatefulWidget {
  const _FormHost({
    required this.editProduct,
  });

  final CatalogProduct? editProduct;

  @override
  State<_FormHost> createState() => _FormHostState();
}

class _FormHostState extends State<_FormHost> {
  CatalogProduct? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            key: const Key('launch-product-form'),
            onPressed: () async {
              final value = await Navigator.of(context).push<CatalogProduct>(
                MaterialPageRoute<CatalogProduct>(
                  builder: (_) => widget.editProduct == null
                      ? const CatalogProductFormScreen.create()
                      : CatalogProductFormScreen.edit(
                          product: widget.editProduct!,
                        ),
                ),
              );
              if (mounted) {
                setState(() {
                  result = value;
                });
              }
            },
            child: const Text('Launch'),
          ),
          if (result != null)
            Text(
              result!.id,
              key: const Key('form-result-id'),
            ),
        ],
      ),
    );
  }
}

Future<void> pumpForm(
  WidgetTester tester, {
  required FakeCatalogRepository catalog,
  CatalogProduct? editProduct,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(catalog),
      ],
      child: MaterialApp(
        home: _FormHost(
          editProduct: editProduct,
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('launch-product-form')));
  await tester.pumpAndSettle();
}

Future<void> enterValidCreate(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('product-field-name-en')),
    'Created Product',
  );
  await tester.enterText(
    find.byKey(const Key('product-field-selling-amount')),
    '2500',
  );
}

void main() {
  testWidgets('create validates names and positive whole-unit price', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository();
    await pumpForm(tester, catalog: catalog);

    await tester.enterText(
      find.byKey(const Key('product-field-selling-amount')),
      '1.5',
    );
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pump();

    expect(find.text('Enter an English or Arabic name.'), findsNWidgets(2));
    expect(
      find.text('Enter a positive whole-number selling price.'),
      findsOneWidget,
    );
    expect(catalog.createIds, isEmpty);
  });

  testWidgets('confirmed create returns server product and preserves barcode text', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository();
    await pumpForm(tester, catalog: catalog);

    await enterValidCreate(tester);
    await tester.enterText(
      find.byKey(const Key('product-field-barcode')),
      '00012-A',
    );
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(catalog.createIds, hasLength(1));
    expect(catalog.createInputs.single.barcode, '00012-A');
    expect(catalog.createInputs.single.sellingAmount, 2500);
    expect(catalog.createInputs.single.currency, 'SYP');
    expect(find.byKey(const Key('form-result-id')), findsOneWidget);
    expect(find.byKey(const Key('product-form')), findsNothing);
  });

  testWidgets('rejected create retains form input and shows retry-safe error', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository()
      ..onCreate = (productId, input) async {
        return const CatalogSaveRejected();
      };
    await pumpForm(tester, catalog: catalog);

    await enterValidCreate(tester);
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-form')), findsOneWidget);
    expect(find.byKey(const Key('product-save-error')), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const Key('product-field-name-en')),
    );
    expect(nameField.controller?.text, 'Created Product');
  });

  testWidgets('uncertain create blocks blind retry until status check', (
    tester,
  ) async {
    var createCalls = 0;
    final catalog = FakeCatalogRepository()
      ..onCreate = (productId, input) async {
        createCalls += 1;
        if (createCalls == 1) {
          return const CatalogSaveUncertain();
        }
        return CatalogSaveConfirmed(
          testProduct(
            id: productId,
            nameEn: input.nameEn,
            nameAr: null,
            sellingAmount: input.sellingAmount,
            currency: input.currency,
          ),
        );
      }
      ..onReconcileCreate = (productId, input) async {
        return const CatalogSaveRejected();
      };

    await pumpForm(tester, catalog: catalog);
    await enterValidCreate(tester);

    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-save-uncertain')), findsOneWidget);
    expect(createCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('product-field-name-en')))
          .enabled,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('product-check-save-status')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-save-uncertain')), findsNothing);
    expect(find.byKey(const Key('product-save-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(createCalls, 2);
    expect(catalog.createIds, hasLength(2));
    expect(catalog.createIds[0], catalog.createIds[1]);
    expect(find.byKey(const Key('form-result-id')), findsOneWidget);
  });

  testWidgets('dirty back navigation supports Stay then Discard Changes', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository();
    await pumpForm(tester, catalog: catalog);

    await tester.enterText(
      find.byKey(const Key('product-field-name-en')),
      'Unsaved',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unsaved-product-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-stay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-form')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-discard')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-form')), findsNothing);
    expect(catalog.createIds, isEmpty);
  });

  testWidgets('dirty navigation Save uses normal confirmed server save', (
    tester,
  ) async {
    final catalog = FakeCatalogRepository();
    await pumpForm(tester, catalog: catalog);

    await enterValidCreate(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('unsaved-save')));
    await tester.pumpAndSettle();

    expect(catalog.createIds, hasLength(1));
    expect(find.byKey(const Key('form-result-id')), findsOneWidget);
  });

  testWidgets('edit sends confirmed update and returns revised server row', (
    tester,
  ) async {
    final original = testProduct(
      id: 'edit-id',
      nameEn: 'Before',
      revision: 4,
    );
    final catalog = FakeCatalogRepository();

    await pumpForm(
      tester,
      catalog: catalog,
      editProduct: original,
    );

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('product-field-name-en')),
    );
    expect(nameField.controller?.text, 'Before');

    await tester.enterText(
      find.byKey(const Key('product-field-name-en')),
      'After',
    );
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(catalog.updateOriginals.single.revision, 4);
    expect(catalog.updateInputs.single.nameEn, 'After');
    expect(find.byKey(const Key('form-result-id')), findsOneWidget);
  });

  testWidgets('conflict can explicitly load the latest server version', (
    tester,
  ) async {
    final original = testProduct(
      id: 'conflict-id',
      nameEn: 'Original',
      revision: 1,
    );
    final latest = testProduct(
      id: 'conflict-id',
      nameEn: 'Server Latest',
      revision: 2,
    );
    final catalog = FakeCatalogRepository()
      ..onUpdate = (base, input) async {
        return CatalogSaveConflict(latest);
      };

    await pumpForm(
      tester,
      catalog: catalog,
      editProduct: original,
    );

    await tester.enterText(
      find.byKey(const Key('product-field-name-en')),
      'Local Change',
    );
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-conflict-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conflict-use-server')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('product-field-name-en')),
    );
    expect(field.controller?.text, 'Server Latest');
    expect(find.byKey(const Key('product-form')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-product-dialog')), findsNothing);
    expect(find.byKey(const Key('product-form')), findsNothing);
  });

  testWidgets('conflict overwrite retries explicitly against latest revision', (
    tester,
  ) async {
    final original = testProduct(
      id: 'conflict-id',
      nameEn: 'Original',
      revision: 1,
    );
    final latest = testProduct(
      id: 'conflict-id',
      nameEn: 'Server Latest',
      revision: 2,
    );
    var calls = 0;
    final catalog = FakeCatalogRepository()
      ..onUpdate = (base, input) async {
        calls += 1;
        if (calls == 1) {
          return CatalogSaveConflict(latest);
        }
        return CatalogSaveConfirmed(
          testProduct(
            id: base.id,
            nameEn: input.nameEn,
            nameAr: input.nameAr.isEmpty ? null : input.nameAr,
            sellingAmount: input.sellingAmount,
            currency: input.currency,
            revision: base.revision + 1,
          ),
        );
      };

    await pumpForm(
      tester,
      catalog: catalog,
      editProduct: original,
    );

    await tester.enterText(
      find.byKey(const Key('product-field-name-en')),
      'Local Change',
    );
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conflict-overwrite')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(catalog.updateOriginals[0].revision, 1);
    expect(catalog.updateOriginals[1].revision, 2);
    expect(catalog.updateInputs[1].nameEn, 'Local Change');
    expect(find.byKey(const Key('form-result-id')), findsOneWidget);
  });
}
