import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/interaction_checker_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> pumpDdiCart(
  WidgetTester tester, {
  required DdiAnalysisGateway gateway,
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
    ProviderScope(
      overrides: [
        ddiAnalysisGatewayProvider.overrideWithValue(gateway),
        ddiCartDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
      child: AppBootstrap(
        runtime: AppRuntime.configured(
          auth,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(AppShell));
  return ProviderScope.containerOf(context);
}

void addProducts(
  ProviderContainer container,
  Iterable<String> productIds,
) {
  final order = container.read(orderControllerProvider.notifier);
  for (final productId in productIds) {
    order.addProduct(
      testProduct(
        id: productId,
        nameEn: 'Product $productId',
        sellingAmount: 1000,
      ),
    );
  }
}

void main() {
  testWidgets('loading hides stale row severity until current result is ready', (
    tester,
  ) async {
    final gate = Completer<DdiAnalysisResult>();
    final gateway = _Gateway((productIds, isCurrent) => gate.future);
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b']);
    await tester.pump();

    expect(find.byKey(const Key('ddi-status-loading')), findsOneWidget);
    expect(find.byKey(const Key('ddi-row-severity-a')), findsNothing);

    gate.complete(
      _analysis(
        products: [
          _trustedProduct('a', 1),
          _trustedProduct('b', 2),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.major,
            ingredientInteractions: [],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ddi-status-ready')), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-major')), findsOneWidget);
    expect(find.text('Major'), findsNWidgets(2));

    final row = tester.widget<DecoratedBox>(
      find.byKey(const Key('order-line-a')),
    );
    final decoration = row.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color, isNot(Colors.transparent));
  });

  testWidgets('row uses highest severity and shows multiple pair count', (
    tester,
  ) async {
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        products: [
          _trustedProduct('a', 1),
          _trustedProduct('b', 2),
          _trustedProduct('c', 3),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.minor,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'c',
            severity: InteractionSeverity.moderate,
            ingredientInteractions: [],
          ),
        ],
      ),
    );
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b', 'c']);
    await tester.pumpAndSettle();

    expect(find.text('Moderate · 2 pairs'), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-moderate')), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-minor')), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-major')), findsNothing);

    await tester.tap(find.byKey(const Key('order-increment-a')));
    await tester.pump();

    expect(find.byKey(const Key('ddi-row-severity-a')), findsOneWidget);
    expect(find.text('Moderate · 2 pairs'), findsOneWidget);
    expect(container.read(orderControllerProvider).totalSyp, 4000);
  });

  testWidgets('unknown and none stay explicit neutral wording', (
    tester,
  ) async {
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        products: [
          _trustedProduct('a', 1),
          _trustedProduct('b', 2),
          _trustedProduct('c', 3),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.unknown,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'b',
            productBId: 'c',
            severity: InteractionSeverity.none,
            ingredientInteractions: [],
          ),
        ],
      ),
    );
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b', 'c']);
    await tester.pumpAndSettle();

    expect(find.text('Unknown'), findsNWidgets(2));
    expect(find.text('No interaction found'), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-unknown')), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-none')), findsOneWidget);
    expect(find.textContaining('Safe'), findsNothing);
  });

  testWidgets('local and provider unresolved coverage stays visibly incomplete', (
    tester,
  ) async {
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        products: [
          _product(
            'a',
            1,
            status: DdiIngredientCoverageStatus.needsReview,
          ),
          _trustedProduct('b', 2),
          _trustedProduct('c', 3),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'b',
            productBId: 'c',
            severity: InteractionSeverity.none,
            ingredientInteractions: [],
          ),
        ],
        providerUnresolved: const [
          DdiProviderUnresolvedIngredient(
            ingredient: DdiIngredientIdentity(
              id: 3,
              name: 'Ingredient c',
              normalizedName: 'ingredient c',
            ),
            query: 'Ingredient c',
            productIds: ['c'],
            suggestions: [],
          ),
        ],
      ),
    );
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b', 'c']);
    await tester.pumpAndSettle();

    expect(find.text('Unchecked'), findsOneWidget);
    expect(find.text('Provider unresolved'), findsOneWidget);
    expect(find.byKey(const Key('ddi-summary-incomplete')), findsOneWidget);
    expect(find.textContaining('safe'), findsNothing);
  });

  testWidgets('DDI failure keeps Cart usable and Retry publishes new result', (
    tester,
  ) async {
    var attempt = 0;
    final gateway = _Gateway((productIds, isCurrent) async {
      attempt += 1;
      if (attempt == 1) {
        throw const InteractionCheckerTransportException('offline');
      }
      return _analysis(
        products: [
          _trustedProduct('a', 1),
          _trustedProduct('b', 2),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.none,
            ingredientInteractions: [],
          ),
        ],
      );
    });
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ddi-status-error')), findsOneWidget);
    expect(find.byKey(const Key('ddi-retry')), findsOneWidget);
    expect(container.read(orderControllerProvider).lines, hasLength(2));
    expect(container.read(orderControllerProvider).totalSyp, 2000);

    await tester.tap(find.byKey(const Key('order-increment-a')));
    await tester.pump();
    expect(container.read(orderControllerProvider).totalSyp, 3000);

    await tester.tap(find.byKey(const Key('ddi-retry')));
    await tester.pumpAndSettle();

    expect(attempt, 2);
    expect(find.byKey(const Key('ddi-status-ready')), findsOneWidget);
    expect(find.text('No interaction found'), findsNWidgets(2));
    expect(container.read(orderControllerProvider).totalSyp, 3000);
  });

  testWidgets('long provider notice stays readable on phone width', (
    tester,
  ) async {
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        products: [
          _trustedProduct('a', 1),
          _trustedProduct('b', 2),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.moderate,
            ingredientInteractions: [],
          ),
        ],
        providerNotices: [
          DdiProviderNotice(
            data: const InteractionCheckData(),
            disclaimer:
                'Not medical advice. Severity reflects the provider data '
                'and must be interpreted with the supplied evidence.',
            attribution: InteractionAttribution(
              text:
                  'Data from Interaction Checker (https://interaction-checker.com), '
                  'based on provider-supplied interaction evidence.',
              url: Uri.parse('https://interaction-checker.com'),
              license: 'Free with attribution',
            ),
          ),
        ],
      ),
    );
    final container = await pumpDdiCart(tester, gateway: gateway);

    addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    final disclaimer = find.byKey(
      const Key('ddi-cart-provider-disclaimer-0'),
    );
    final link = find.byKey(
      const Key('ddi-cart-provider-link-0'),
    );

    expect(disclaimer, findsOneWidget);
    expect(link, findsOneWidget);
    expect(tester.getSize(disclaimer).width, greaterThan(250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable DDI is explicit and never presented as none', (
    tester,
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
    final container = ProviderScope.containerOf(context);
    addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ddi-status-unavailable')), findsOneWidget);
    expect(find.text('Interaction checking unavailable.'), findsOneWidget);
    expect(find.text('No interaction found'), findsNothing);
  });
}

class _Gateway implements DdiAnalysisGateway {
  _Gateway(this.handler);

  final Future<DdiAnalysisResult> Function(
    List<String> productIds,
    bool Function()? isCurrent,
  ) handler;

  @override
  Future<DdiAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) {
    return handler(productIds, isCurrent);
  }
}

DdiAnalysisResult _analysis({
  required List<DdiProductIngredientInput> products,
  List<DdiProductPairInteraction> pairs = const [],
  List<DdiProviderUnresolvedIngredient> providerUnresolved = const [],
  List<DdiProviderNotice> providerNotices = const [],
}) {
  return DdiAnalysisResult(
    products: products,
    providerUnresolved: providerUnresolved,
    productPairs: pairs,
    providerNotices: providerNotices,
    uniqueIngredientCount: products.length,
    providerBatchCount: pairs.isEmpty ? 0 : 1,
  );
}

DdiProductIngredientInput _trustedProduct(
  String productId,
  int ingredientId,
) {
  return _product(productId, ingredientId);
}

DdiProductIngredientInput _product(
  String productId,
  int ingredientId, {
  DdiIngredientCoverageStatus status =
      DdiIngredientCoverageStatus.trusted,
}) {
  return DdiProductIngredientInput(
    productId: productId,
    requestPosition: ingredientId,
    coverageStatus: status,
    productExists: status != DdiIngredientCoverageStatus.missing,
    normalizationStatus: switch (status) {
      DdiIngredientCoverageStatus.trusted => 'auto_verified',
      DdiIngredientCoverageStatus.needsReview => 'needs_review',
      DdiIngredientCoverageStatus.unresolved => 'unresolved',
      DdiIngredientCoverageStatus.missing => null,
    },
    componentCount:
        status == DdiIngredientCoverageStatus.trusted ? 1 : null,
    resolvedComponentCount:
        status == DdiIngredientCoverageStatus.trusted ? 1 : null,
    ingredients: status == DdiIngredientCoverageStatus.trusted
        ? [
            DdiIngredientIdentity(
              id: ingredientId,
              name: 'Ingredient $productId',
              normalizedName: 'ingredient $productId',
            ),
          ]
        : const [],
  );
}
