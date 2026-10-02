import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/application/sdif_result_aggregator.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_result_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';

void main() {
  const aggregator = SdifResultAggregator();

  group('SdifResultAggregator', () {
    test('emits every unordered pair when provider reports zero hits', () {
      final result = aggregator.aggregate(
        _checked([_identityA(), _identityB(), _identityC()], const []),
      );

      expect(result.pairs, hasLength(3));
      expect(
        result.pairs
            .map(
              (pair) => (
                pair.identityA.identity.scientificIngredientId,
                pair.identityB.identity.scientificIngredientId,
              ),
            )
            .toList(),
        [(1, 2), (1, 3), (2, 3)],
      );
      for (final pair in result.pairs) {
        expect(
          pair.observationStatus,
          SdifPairObservationStatus.noProviderHitReported,
        );
        expect(pair.findings, isEmpty);
        expect(pair.maxProviderSeverityScore, isNull);
        expect(pair.topSeverityObservations, isEmpty);
      }
      expect(result.providerHitCount, 0);
      expect(result.retainedFindingCount, 0);
      expect(result.exactDuplicateHitCount, 0);
    });

    test('retains all four provider-native families without severity conversion', () {
      final result = aggregator.aggregate(
        _checked(
          [_identityA(), _identityB()],
          [
            _hit(
              family: SdifInteractionFamily.substance,
              score: 1,
              label: 'Vorsicht',
              source: 'Swissmedic FI',
            ),
            _hit(
              family: SdifInteractionFamily.classLevel,
              score: 2,
              label: 'Schwerwiegend',
              source: 'Swissmedic FI',
              keyword: 'class-keyword',
            ),
            _hit(
              family: SdifInteractionFamily.cyp,
              score: 3,
              label: 'Kontraindiziert',
              source: 'Swissmedic FI',
              keyword: 'CYP3A4',
            ),
            _hit(
              family: SdifInteractionFamily.epha,
              score: 2,
              label: 'Kombination vermeiden (D)',
              source: 'EPha',
              keyword: 'D',
            ),
          ],
        ),
      );

      final pair = result.pairs.single;
      expect(pair.observationStatus, SdifPairObservationStatus.hitsObserved);
      expect(pair.findings, hasLength(4));
      expect(pair.observedFamilies, SdifInteractionFamily.values);
      expect(pair.maxProviderSeverityScore, 3);
      expect(pair.findings.first.providerHit.family, SdifInteractionFamily.cyp);
      expect(pair.findings.first.providerHit.severityLabel, 'Kontraindiziert');
      expect(pair.findings.last.providerHit.severityScore, 1);
      expect(
        pair.findings
            .singleWhere(
              (finding) =>
                  finding.providerHit.family == SdifInteractionFamily.epha,
            )
            .isDirectionalEvidence,
        isFalse,
      );
      expect(
        pair.findings
            .singleWhere(
              (finding) =>
                  finding.providerHit.family == SdifInteractionFamily.cyp,
            )
            .isDirectionalEvidence,
        isTrue,
      );
    });

    test('collapses only exact repeated evidence in the same direction', () {
      final duplicate = _hit(
        family: SdifInteractionFamily.substance,
        score: 2,
        label: 'Schwerwiegend',
        source: 'Swissmedic FI',
      );
      final result = aggregator.aggregate(
        _checked([_identityA(), _identityB()], [duplicate, duplicate]),
      );

      final pair = result.pairs.single;
      expect(pair.providerHitCount, 2);
      expect(pair.findings, hasLength(1));
      expect(pair.exactDuplicateHitCount, 1);
      expect(result.providerHitCount, 2);
      expect(result.retainedFindingCount, 1);
      expect(result.exactDuplicateHitCount, 1);
    });

    test('preserves opposite-direction asymmetric evidence separately', () {
      final result = aggregator.aggregate(
        _checked(
          [_identityA(), _identityB()],
          [
            _hit(
              family: SdifInteractionFamily.substance,
              score: 2,
              label: 'Schwerwiegend',
              source: 'Swissmedic FI',
            ),
            _hit(
              family: SdifInteractionFamily.substance,
              score: 2,
              label: 'Schwerwiegend',
              source: 'Swissmedic FI',
              reverse: true,
            ),
          ],
        ),
      );

      final pair = result.pairs.single;
      expect(pair.findings, hasLength(2));
      expect(pair.exactDuplicateHitCount, 0);
      expect(
        pair.findings
            .map(
              (finding) =>
                  finding.drugAIdentity.identity.scientificIngredientId,
            )
            .toSet(),
        {1, 2},
      );
    });

    test('retains all distinct raw top-score label and source observations', () {
      final result = aggregator.aggregate(
        _checked(
          [_identityA(), _identityB()],
          [
            _hit(
              family: SdifInteractionFamily.substance,
              score: 3,
              label: 'Kontraindiziert',
              source: 'Swissmedic FI',
            ),
            _hit(
              family: SdifInteractionFamily.epha,
              score: 3,
              label: 'Nicht kombinieren (X)',
              source: 'EPha',
              keyword: 'X',
            ),
            _hit(
              family: SdifInteractionFamily.classLevel,
              score: 1,
              label: 'Vorsicht',
              source: 'Swissmedic FI',
              keyword: 'class-keyword',
            ),
          ],
        ),
      );

      final pair = result.pairs.single;
      expect(pair.maxProviderSeverityScore, 3);
      expect(pair.topSeverityObservations, hasLength(2));
      expect(
        pair.topSeverityObservations.map((value) => value.source).toSet(),
        {'EPha', 'Swissmedic FI'},
      );
      expect(
        pair.topSeverityObservations.map((value) => value.label).toSet(),
        {'Kontraindiziert', 'Nicht kombinieren (X)'},
      );
    });

    test('keeps hit and no-hit pair observations distinct in one result', () {
      final result = aggregator.aggregate(
        _checked(
          [_identityA(), _identityB(), _identityC()],
          [
            _hit(
              family: SdifInteractionFamily.substance,
              score: 1,
              label: 'Vorsicht',
              source: 'Swissmedic FI',
            ),
          ],
        ),
      );

      expect(
        result.pairs
            .where(
              (pair) =>
                  pair.observationStatus ==
                  SdifPairObservationStatus.hitsObserved,
            )
            .length,
        1,
      );
      expect(
        result.pairs
            .where(
              (pair) =>
                  pair.observationStatus ==
                  SdifPairObservationStatus.noProviderHitReported,
            )
            .length,
        2,
      );
    });

    test('fails closed when a hit cannot map to two resolved endpoints', () {
      final invalidHit = SdifInteractionHit(
        drugA: 'Provider A',
        drugAAtc: 'A01AA01',
        drugARoute: '',
        drugB: 'Unexpected Provider',
        drugBAtc: 'Z99ZZ99',
        drugBRoute: '',
        family: SdifInteractionFamily.substance,
        severityScore: 1,
        severityLabel: 'Vorsicht',
        severityIndicator: '#',
        keyword: 'unexpected',
        description: 'Fixture description',
        explanation: 'Fixture explanation',
        source: 'Swissmedic FI',
        comboHint: '',
      );

      expect(
        () => aggregator.aggregate(
          _checked([_identityA(), _identityB()], [invalidHit]),
        ),
        throwsA(isA<SdifResultAggregationException>()),
      );
    });
  });
}

SdifReviewedIdentityCheckResult _checked(
  List<SdifResolvedScientificIdentity> identities,
  List<SdifInteractionHit> hits,
) {
  return SdifReviewedIdentityCheckResult(
    identities: identities,
    providerResult: SdifCheckResult(
      basket: [
        for (final identity in identities)
          SdifBasketDrug(
            brand: identity.providerDrug.brandName,
            atcCode: identity.providerDrug.providerAtcCode,
            substances: [identity.providerDrug.substances.toLowerCase()],
          ),
      ],
      interactions: hits,
    ),
  );
}

SdifResolvedScientificIdentity _identityA() => _resolvedIdentity(
      id: 1,
      name: 'Alpha',
      atc: 'A01AA01',
      brand: 'Provider A',
    );

SdifResolvedScientificIdentity _identityB() => _resolvedIdentity(
      id: 2,
      name: 'Beta',
      atc: 'B01BB02',
      brand: 'Provider B',
    );

SdifResolvedScientificIdentity _identityC() => _resolvedIdentity(
      id: 3,
      name: 'Gamma',
      atc: 'C01CC03',
      brand: 'Provider C',
    );

SdifResolvedScientificIdentity _resolvedIdentity({
  required int id,
  required String name,
  required String atc,
  required String brand,
}) {
  return SdifResolvedScientificIdentity(
    identity: SdifReviewedScientificIdentity(
      scientificIngredientId: id,
      preferredName: name,
      reviewedAtcCodes: [atc],
    ),
    providerDrug: SdifProviderDrugSelection(
      reviewedAtcCode: atc,
      brandName: brand,
      providerAtcCode: atc,
      substances: name,
    ),
  );
}

SdifInteractionHit _hit({
  required SdifInteractionFamily family,
  required int score,
  required String label,
  required String source,
  String keyword = 'beta',
  bool reverse = false,
}) {
  return SdifInteractionHit(
    drugA: reverse ? 'Provider B' : 'Provider A',
    drugAAtc: reverse ? 'B01BB02' : 'A01AA01',
    drugARoute: reverse ? 'p.o.' : '',
    drugB: reverse ? 'Provider A' : 'Provider B',
    drugBAtc: reverse ? 'A01AA01' : 'B01BB02',
    drugBRoute: reverse ? '' : 'p.o.',
    family: family,
    severityScore: score,
    severityLabel: label,
    severityIndicator: switch (score) {
      3 => '###',
      2 => '##',
      1 => '#',
      _ => '-',
    },
    keyword: keyword,
    description: 'Fixture description for $keyword',
    explanation: 'Fixture explanation for $keyword',
    source: source,
    comboHint: '',
  );
}
