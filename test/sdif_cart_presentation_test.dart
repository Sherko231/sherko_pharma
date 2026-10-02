import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_cart_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_result_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/sdif_cart_presentation.dart';

void main() {
  test('separates findings no-hit and unchecked product pairs', () {
    final analysis = SdifCartAnalysisResult(
      products: [
        _product('a', SdifScientificCoverageStatus.complete, 1),
        _product('b', SdifScientificCoverageStatus.complete, 2),
        _product('c', SdifScientificCoverageStatus.partial, 3),
      ],
      providerResolutionGaps: [
        SdifProviderResolutionGap(
          identity: _resolved(3).identity,
          status: SdifProviderResolutionGapStatus.unmapped,
          productIds: const ['c'],
        ),
      ],
      identityPairs: [
        _pair(1, 2, withFinding: true),
        _pair(1, 3),
      ],
      productPairs: [
        SdifProductPairAnalysis(
          productAId: 'a',
          productBId: 'b',
          identityPairs: [_pair(1, 2, withFinding: true)],
        ),
        SdifProductPairAnalysis(
          productAId: 'a',
          productBId: 'c',
          identityPairs: [_pair(1, 3)],
        ),
        const SdifProductPairAnalysis(
          productAId: 'b',
          productBId: 'c',
          identityPairs: [],
        ),
      ],
      uniqueEligibleIdentityCount: 3,
      providerResolvedIdentityCount: 2,
      providerBatchCount: 1,
      providerHitCount: 1,
      retainedFindingCount: 1,
      exactDuplicateHitCount: 0,
    );

    final presentation = buildSdifCartPresentation(analysis);

    expect(presentation.productPairsWithFindings, 1);
    expect(presentation.productPairsWithNoProviderHit, 1);
    expect(presentation.uncheckedProductPairCount, 1);
    expect(presentation.incompleteProductCount, 2);
    expect(presentation.providerResolutionGapCount, 1);

    final a = presentation.rows['a']!;
    expect(a.findingProductPairCount, 1);
    expect(a.noProviderHitProductPairCount, 1);
    expect(a.uncheckedProductPairCount, 0);
    expect(a.incompleteCoverage, isFalse);

    final b = presentation.rows['b']!;
    expect(b.findingProductPairCount, 1);
    expect(b.uncheckedProductPairCount, 1);
    expect(b.incompleteCoverage, isTrue);

    final c = presentation.rows['c']!;
    expect(c.noProviderHitProductPairCount, 1);
    expect(c.uncheckedProductPairCount, 1);
    expect(c.providerResolutionIncomplete, isTrue);
    expect(c.incompleteCoverage, isTrue);
  });

  test('complete checked no-hit row stays complete and provider neutral', () {
    final pair = _pair(1, 2);
    final presentation = buildSdifCartPresentation(
      SdifCartAnalysisResult(
        products: [
          _product('a', SdifScientificCoverageStatus.complete, 1),
          _product('b', SdifScientificCoverageStatus.complete, 2),
        ],
        providerResolutionGaps: const [],
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
        providerHitCount: 0,
        retainedFindingCount: 0,
        exactDuplicateHitCount: 0,
      ),
    );

    expect(presentation.productPairsWithFindings, 0);
    expect(presentation.productPairsWithNoProviderHit, 1);
    expect(presentation.uncheckedProductPairCount, 0);
    expect(presentation.incompleteProductCount, 0);
    expect(presentation.rows['a']!.hasProviderFindings, isFalse);
    expect(presentation.rows['a']!.hasProviderCheckedPairs, isTrue);
    expect(presentation.rows['a']!.incompleteCoverage, isFalse);
  });
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
