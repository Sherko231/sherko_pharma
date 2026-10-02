import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_cart_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_runtime_selection.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_cart_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_result_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> _pumpSdifCart(
  WidgetTester tester, {
  required SdifCartAnalysisGateway gateway,
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
        sdifCartAnalysisGatewayProvider.overrideWithValue(gateway),
        sdifCartDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
      child: AppBootstrap(
        runtime: AppRuntime.configured(
          auth,
          catalogRepository: FakeCatalogRepository(),
          ddiRuntimeSelection: DdiRuntimeSelection.sdif(
            Uri.parse('http://127.0.0.1:3000/'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(AppShell));
  return ProviderScope.containerOf(context);
}

void _addProducts(
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
  testWidgets('SDIF findings use native wording without Interaction Checker severity', (
    tester,
  ) async {
    final gateway = _Gateway((productIds, isCurrent) async {
      final pair = _pair(1, 2, withFinding: true);
      return _analysis(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        productPairs: [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [pair],
          ),
        ],
        identityPairs: [pair],
      );
    });
    final container = await _pumpSdifCart(tester, gateway: gateway);

    _addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-status-ready')), findsOneWidget);
    expect(find.byKey(const Key('sdif-summary-findings')), findsOneWidget);
    expect(find.byKey(const Key('sdif-row-findings-a')), findsOneWidget);
    expect(find.text('SDIF findings · 1 pair'), findsNWidgets(2));
    expect(find.text('Major'), findsNothing);
    expect(find.text('Moderate'), findsNothing);
    expect(find.text('Minor'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
    expect(find.text('No interaction found'), findsNothing);
    expect(
      find.textContaining(RegExp(r'\bsafe\b', caseSensitive: false)),
      findsNothing,
    );
    expect(find.textContaining('compatible'), findsNothing);
    expect(container.read(orderControllerProvider).totalSyp, 2000);
  });

  testWidgets('checked no-hit stays neutral and carries safety clarification', (
    tester,
  ) async {
    final gateway = _Gateway((productIds, isCurrent) async {
      final pair = _pair(1, 2);
      return _analysis(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        productPairs: [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [pair],
          ),
        ],
        identityPairs: [pair],
      );
    });
    final container = await _pumpSdifCart(tester, gateway: gateway);

    _addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-summary-no-hit')), findsOneWidget);
    expect(find.text('No provider hit · 1 pair'), findsNWidgets(2));
    expect(
      find.text('No provider hit is not a safety classification.'),
      findsOneWidget,
    );
    expect(find.text('No interaction found'), findsNothing);
    expect(
      find.textContaining(RegExp(r'\bsafe\b', caseSensitive: false)),
      findsNothing,
    );
    expect(find.textContaining('compatible'), findsNothing);

    final row = tester.widget<DecoratedBox>(
      find.byKey(const Key('order-line-a')),
    );
    final decoration = row.decoration as BoxDecoration;
    expect(decoration.color, isNull);
  });

  testWidgets('partial coverage and unchecked product pairs stay explicit', (
    tester,
  ) async {
    final gateway = _Gateway((productIds, isCurrent) async {
      return _analysis(
        products: [
          _product('a', SdifScientificCoverageStatus.partial, 1),
          _product('b', SdifScientificCoverageStatus.unmapped, 2),
        ],
        providerResolutionGaps: [
          SdifProviderResolutionGap(
            identity: _resolved(1).identity,
            status: SdifProviderResolutionGapStatus.unmapped,
            productIds: const ['a'],
          ),
        ],
        productPairs: const [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [],
          ),
        ],
      );
    });
    final container = await _pumpSdifCart(tester, gateway: gateway);

    _addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-summary-unchecked')), findsOneWidget);
    expect(find.byKey(const Key('sdif-summary-incomplete')), findsOneWidget);
    expect(find.text('Partial scientific coverage'), findsOneWidget);
    expect(find.text('Scientific identity unmapped'), findsOneWidget);
    expect(find.text('SDIF mapping incomplete'), findsOneWidget);
    expect(find.text('Unchecked pairs · 1'), findsNWidgets(2));
    expect(find.text('No provider hit'), findsNothing);
    expect(find.text('No interaction found'), findsNothing);
  });

  testWidgets('SDIF failure keeps Cart usable and Retry publishes native result', (
    tester,
  ) async {
    var attempts = 0;
    final gateway = _Gateway((productIds, isCurrent) async {
      attempts += 1;
      if (attempts == 1) {
        throw const SdifTransportException('offline');
      }
      final pair = _pair(1, 2);
      return _analysis(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        productPairs: [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [pair],
          ),
        ],
        identityPairs: [pair],
      );
    });
    final container = await _pumpSdifCart(tester, gateway: gateway);

    _addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-status-error')), findsOneWidget);
    expect(find.byKey(const Key('sdif-retry')), findsOneWidget);
    expect(container.read(orderControllerProvider).totalSyp, 2000);

    await tester.tap(find.byKey(const Key('order-increment-a')));
    await tester.pump();
    expect(container.read(orderControllerProvider).totalSyp, 3000);

    await tester.tap(find.byKey(const Key('sdif-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(const Key('sdif-status-ready')), findsOneWidget);
    expect(find.byKey(const Key('sdif-summary-no-hit')), findsOneWidget);
    expect(container.read(orderControllerProvider).totalSyp, 3000);
  });

  testWidgets('SDIF mode does not expose the old unavailable DDI surface', (
    tester,
  ) async {
    final gateway = _Gateway((productIds, isCurrent) async {
      final pair = _pair(1, 2);
      return _analysis(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        productPairs: [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [pair],
          ),
        ],
        identityPairs: [pair],
      );
    });
    final container = await _pumpSdifCart(tester, gateway: gateway);

    _addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-cart-status')), findsOneWidget);
    expect(find.byKey(const Key('ddi-cart-status')), findsNothing);
    expect(find.text('Interaction checking unavailable.'), findsNothing);
  });
}

class _Gateway implements SdifCartAnalysisGateway {
  _Gateway(this.handler);

  final Future<SdifCartAnalysisResult> Function(
    List<String> productIds,
    bool Function()? isCurrent,
  ) handler;

  @override
  Future<SdifCartAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) {
    return handler(productIds, isCurrent);
  }
}

SdifCartAnalysisResult _analysis({
  required List<SdifProductScientificInput> products,
  List<SdifProviderResolutionGap> providerResolutionGaps = const [],
  List<SdifPairAssessment> identityPairs = const [],
  List<SdifProductPairAnalysis> productPairs = const [],
}) {
  final findings = identityPairs.fold<int>(
    0,
    (total, pair) => total + pair.findings.length,
  );
  return SdifCartAnalysisResult(
    products: products,
    providerResolutionGaps: providerResolutionGaps,
    identityPairs: identityPairs,
    productPairs: productPairs,
    uniqueEligibleIdentityCount: products.fold<int>(
      0,
      (total, product) => total + product.eligibleIdentityCount,
    ),
    providerResolvedIdentityCount: identityPairs.isEmpty ? 0 : 2,
    providerBatchCount: identityPairs.isEmpty ? 0 : 1,
    providerHitCount: findings,
    retainedFindingCount: findings,
    exactDuplicateHitCount: 0,
  );
}

SdifProductScientificInput _product(
  String productId,
  SdifScientificCoverageStatus status,
  int scientificId,
) {
  final hasIdentity = status == SdifScientificCoverageStatus.complete ||
      status == SdifScientificCoverageStatus.partial;
  return SdifProductScientificInput(
    requestPosition: scientificId,
    productId: productId,
    productExists: status != SdifScientificCoverageStatus.missing,
    coverageStatus: status,
    canonicalizationStatus: hasIdentity ? 'trusted' : 'unresolved',
    ingredientCount: status == SdifScientificCoverageStatus.partial ? 2 : 1,
    trustedComponentCount: hasIdentity ? 1 : 0,
    atcCoveredComponentCount: hasIdentity ? 1 : 0,
    eligibleIdentityCount: hasIdentity ? 1 : 0,
    identities: hasIdentity
        ? [
            SdifProductScientificIdentity(
              scientificIngredientId: scientificId,
              preferredName: 'Ingredient $scientificId',
              reviewedAtcCodes: ['A$scientificId'],
            ),
          ]
        : const [],
  );
}

SdifResolvedScientificIdentity _resolved(int id) {
  return SdifResolvedScientificIdentity(
    identity: SdifReviewedScientificIdentity(
      scientificIngredientId: id,
      preferredName: 'Ingredient $id',
      reviewedAtcCodes: ['A$id'],
    ),
    providerDrug: SdifProviderDrugSelection(
      reviewedAtcCode: 'A$id',
      brandName: 'Brand $id',
      providerAtcCode: 'A$id',
      substances: 'Substance $id',
    ),
  );
}

SdifPairAssessment _pair(
  int a,
  int b, {
  bool withFinding = false,
}) {
  final resolvedA = _resolved(a);
  final resolvedB = _resolved(b);
  final findings = withFinding
      ? [
          SdifPairFinding(
            drugAIdentity: resolvedA,
            drugBIdentity: resolvedB,
            providerHit: SdifInteractionHit(
              drugA: 'Brand $a',
              drugAAtc: 'A$a',
              drugARoute: 'oral',
              drugB: 'Brand $b',
              drugBAtc: 'A$b',
              drugBRoute: 'oral',
              family: SdifInteractionFamily.substance,
              severityScore: 2,
              severityLabel: 'Schwerwiegend',
              severityIndicator: '##',
              keyword: 'synthetic',
              description: 'Synthetic description',
              explanation: 'Synthetic explanation',
              source: 'synthetic',
              comboHint: '',
            ),
          ),
        ]
      : const <SdifPairFinding>[];
  return SdifPairAssessment(
    identityA: resolvedA,
    identityB: resolvedB,
    observationStatus: withFinding
        ? SdifPairObservationStatus.hitsObserved
        : SdifPairObservationStatus.noProviderHitReported,
    providerHitCount: findings.length,
    exactDuplicateHitCount: 0,
    findings: findings,
    observedFamilies: withFinding
        ? const [SdifInteractionFamily.substance]
        : const [],
    maxProviderSeverityScore: withFinding ? 2 : null,
    topSeverityObservations: withFinding
        ? const [
            SdifProviderSeverityObservation(
              score: 2,
              label: 'Schwerwiegend',
              indicator: '##',
              source: 'synthetic',
            ),
          ]
        : const [],
  );
}
