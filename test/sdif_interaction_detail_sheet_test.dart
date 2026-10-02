import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/domain/sdif_cart_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_result_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/sdif_interaction_detail_sheet.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';

void main() {
  test('detail builder keeps current Cart names coverage and provider gaps', () {
    final analysis = _analysis();
    final detail = buildSdifInteractionDetailPresentation(
      analysis: analysis,
      orderLines: const [
        OrderLine(
          productId: 'a',
          displayName: 'Product A',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'b',
          displayName: 'Product B',
          quantity: 1,
          unitAmount: 2000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'a',
    );

    expect(detail.focusProductName, 'Product A');
    expect(detail.coverageStatus, SdifScientificCoverageStatus.partial);
    expect(detail.providerResolutionGaps, hasLength(1));
    expect(detail.providerResolutionGaps.single.identity.preferredName, 'Gap');
    expect(detail.productPairs, hasLength(1));
    expect(detail.productPairs.single.productAName, 'Product A');
    expect(detail.productPairs.single.productBName, 'Product B');
  });

  testWidgets('detail renders provider-native finding metadata without IC labels', (
    tester,
  ) async {
    final detail = buildSdifInteractionDetailPresentation(
      analysis: _analysis(),
      orderLines: const [
        OrderLine(
          productId: 'a',
          displayName: 'Product A',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'b',
          displayName: 'Product B',
          quantity: 1,
          unitAmount: 2000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'a',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showSdifInteractionDetailSheet(
                context: context,
                presentation: detail,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sdif-detail-sheet')), findsOneWidget);
    expect(find.text('Product A ↔ Product B'), findsOneWidget);
    expect(find.text('Ingredient 1 ↔ Ingredient 2'), findsOneWidget);
    expect(find.text('Provider findings observed'), findsOneWidget);
    expect(find.text('Family: substance'), findsOneWidget);
    expect(
      find.text('Provider severity: Schwerwiegend (score 2, ##)'),
      findsOneWidget,
    );
    expect(find.text('Source: synthetic-source'), findsOneWidget);
    expect(find.text('Direction: Ingredient 1 → Ingredient 2'), findsOneWidget);
    expect(find.text('Keyword: synthetic-keyword'), findsOneWidget);
    expect(find.text('Synthetic description'), findsOneWidget);
    expect(find.text('Synthetic explanation'), findsOneWidget);
    expect(find.text('Combination note: synthetic-combo'), findsOneWidget);
    expect(find.textContaining('Gap:'), findsOneWidget);
    expect(
      find.textContaining('No provider hit is not a safety classification'),
      findsOneWidget,
    );

    expect(find.text('Major'), findsNothing);
    expect(find.text('Moderate'), findsNothing);
    expect(find.text('Minor'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
    expect(find.text('No interaction found'), findsNothing);
    expect(find.textContaining('stop taking'), findsNothing);
    expect(find.textContaining('dose'), findsNothing);
  });

  testWidgets('detail keeps no-hit observation explicit', (tester) async {
    final noHitPair = _pair(1, 2, withFinding: false);
    final detail = buildSdifInteractionDetailPresentation(
      analysis: SdifCartAnalysisResult(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        providerResolutionGaps: const [],
        identityPairs: [noHitPair],
        productPairs: [
          SdifProductPairAnalysis(
            productAId: 'a',
            productBId: 'b',
            identityPairs: [noHitPair],
          ),
        ],
        uniqueEligibleIdentityCount: 2,
        providerResolvedIdentityCount: 2,
        providerBatchCount: 1,
        providerHitCount: 0,
        retainedFindingCount: 0,
        exactDuplicateHitCount: 0,
      ),
      orderLines: const [
        OrderLine(
          productId: 'a',
          displayName: 'Product A',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'b',
          displayName: 'Product B',
          quantity: 1,
          unitAmount: 2000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'a',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSdifInteractionDetailSheet(
                context: context,
                presentation: detail,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('No provider hit reported'), findsOneWidget);
    expect(
      find.textContaining('not a safety classification'),
      findsWidgets,
    );
    expect(find.text('No interaction found'), findsNothing);
    expect(
      find.textContaining(RegExp(r'\bsafe\b', caseSensitive: false)),
      findsNothing,
    );
    expect(find.textContaining('compatible'), findsNothing);
  });
}

SdifCartAnalysisResult _analysis() {
  final pair = _pair(1, 2, withFinding: true);
  return SdifCartAnalysisResult(
    products: [
      _product('a', SdifScientificCoverageStatus.partial, 1),
      _product('b', SdifScientificCoverageStatus.complete, 2),
    ],
    providerResolutionGaps: [
      SdifProviderResolutionGap(
        identity: const SdifReviewedScientificIdentity(
          scientificIngredientId: 3,
          preferredName: 'Gap',
          reviewedAtcCodes: ['A3'],
        ),
        status: SdifProviderResolutionGapStatus.unmapped,
        productIds: const ['a'],
      ),
    ],
    identityPairs: [pair],
    productPairs: [
      SdifProductPairAnalysis(
        productAId: 'a',
        productBId: 'b',
        identityPairs: [pair],
      ),
    ],
    uniqueEligibleIdentityCount: 2,
    providerResolvedIdentityCount: 2,
    providerBatchCount: 1,
    providerHitCount: 1,
    retainedFindingCount: 1,
    exactDuplicateHitCount: 0,
  );
}

SdifProductScientificInput _product(
  String productId,
  SdifScientificCoverageStatus status,
  int scientificId,
) {
  return SdifProductScientificInput(
    requestPosition: scientificId,
    productId: productId,
    productExists: true,
    coverageStatus: status,
    canonicalizationStatus: 'trusted',
    ingredientCount: status == SdifScientificCoverageStatus.partial ? 2 : 1,
    trustedComponentCount: 1,
    atcCoveredComponentCount: 1,
    eligibleIdentityCount: 1,
    identities: [
      SdifProductScientificIdentity(
        scientificIngredientId: scientificId,
        preferredName: 'Ingredient $scientificId',
        reviewedAtcCodes: ['A$scientificId'],
      ),
    ],
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
  required bool withFinding,
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
              keyword: 'synthetic-keyword',
              description: 'Synthetic description',
              explanation: 'Synthetic explanation',
              source: 'synthetic-source',
              comboHint: 'synthetic-combo',
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
              source: 'synthetic-source',
            ),
          ]
        : const [],
  );
}
