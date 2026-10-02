import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/application/sdif_result_aggregator.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_result_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';

void main() {
  test('provider severity score zero is still an observed hit', () {
    final identityA = _identity(1, 'Alpha', 'A01AA01', 'Provider A');
    final identityB = _identity(2, 'Beta', 'B01BB02', 'Provider B');
    final checked = SdifReviewedIdentityCheckResult(
      identities: [identityA, identityB],
      providerResult: const SdifCheckResult(
        basket: [
          SdifBasketDrug(
            brand: 'Provider A',
            atcCode: 'A01AA01',
            substances: ['alpha'],
          ),
          SdifBasketDrug(
            brand: 'Provider B',
            atcCode: 'B01BB02',
            substances: ['beta'],
          ),
        ],
        interactions: [
          SdifInteractionHit(
            drugA: 'Provider A',
            drugAAtc: 'A01AA01',
            drugARoute: '',
            drugB: 'Provider B',
            drugBAtc: 'B01BB02',
            drugBRoute: 'p.o.',
            family: SdifInteractionFamily.substance,
            severityScore: 0,
            severityLabel: 'Keine Einstufung',
            severityIndicator: '-',
            keyword: 'beta',
            description: 'Provider emitted an interaction hit without severity keywords.',
            explanation: 'Fixture explanation.',
            source: 'Swissmedic FI',
            comboHint: '',
          ),
        ],
      ),
    );

    final result = const SdifResultAggregator().aggregate(checked);
    final pair = result.pairs.single;

    expect(pair.observationStatus, SdifPairObservationStatus.hitsObserved);
    expect(pair.findings, hasLength(1));
    expect(pair.maxProviderSeverityScore, 0);
    expect(pair.topSeverityObservations.single.score, 0);
    expect(pair.topSeverityObservations.single.label, 'Keine Einstufung');
  });
}

SdifResolvedScientificIdentity _identity(
  int id,
  String name,
  String atc,
  String brand,
) {
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
