import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/application/sdif_reviewed_atc_bridge.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';

void main() {
  group('SdifReviewedAtcBridge integrity', () {
    test('rejects a reviewed ATC lookup that becomes multi-substance', () async {
      final gateway = _IntegrityGateway(
        searches: const {
          'A01AA01': [
            SdifDrugSearchResult(
              brandName: 'Combination Provider',
              atcCode: 'A01AA01',
              substances: 'Alpha, Beta',
            ),
          ],
        },
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      await expectLater(
        bridge.resolveIdentity(_identity(1, 'Alpha', 'A01AA01')),
        throwsA(isA<SdifReviewedAtcIntegrityException>()),
      );
    });

    test('rejects a forged resolved selection outside reviewed ATC metadata', () async {
      final gateway = _IntegrityGateway(
        searches: const {},
        checkResult: const SdifCheckResult(basket: [], interactions: []),
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);
      final forged = SdifResolvedScientificIdentity(
        identity: _identity(1, 'Alpha', 'A01AA01'),
        providerDrug: const SdifProviderDrugSelection(
          reviewedAtcCode: 'A01AA99',
          brandName: 'Forged Provider',
          providerAtcCode: 'A01AA99',
          substances: 'Alpha',
        ),
      );
      final valid = SdifResolvedScientificIdentity(
        identity: _identity(2, 'Beta', 'B01BB02'),
        providerDrug: const SdifProviderDrugSelection(
          reviewedAtcCode: 'B01BB02',
          brandName: 'Provider B',
          providerAtcCode: 'B01BB02',
          substances: 'Beta',
        ),
      );

      await expectLater(
        bridge.checkResolvedIdentities([forged, valid]),
        throwsA(isA<SdifReviewedAtcIntegrityException>()),
      );
      expect(gateway.checkedDrugs, isNull);
    });

    test('rejects interaction hits that reference a drug outside basket', () async {
      final gateway = _IntegrityGateway(
        searches: _searches(),
        checkResult: const SdifCheckResult(
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
              drugB: 'Outside Provider',
              drugBAtc: 'C01CC03',
              drugBRoute: '',
              family: SdifInteractionFamily.substance,
              severityScore: 1,
              severityLabel: 'Vorsicht',
              severityIndicator: '#',
              keyword: 'outside',
              description: 'Fixture',
              explanation: 'Fixture',
              source: 'Swissmedic FI',
              comboHint: '',
            ),
          ],
        ),
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);
      final resolutions = await bridge.resolveIdentities([
        _identity(1, 'Alpha', 'A01AA01'),
        _identity(2, 'Beta', 'B01BB02'),
      ]);

      await expectLater(
        bridge.checkResolvedIdentities(
          resolutions.map((item) => item.resolvedIdentity!).toList(),
        ),
        throwsA(isA<SdifReviewedAtcBasketIntegrityException>()),
      );
    });
  });
}

SdifReviewedScientificIdentity _identity(int id, String name, String atc) {
  return SdifReviewedScientificIdentity(
    scientificIngredientId: id,
    preferredName: name,
    reviewedAtcCodes: [atc],
  );
}

Map<String, List<SdifDrugSearchResult>> _searches() {
  return const {
    'A01AA01': [
      SdifDrugSearchResult(
        brandName: 'Provider A',
        atcCode: 'A01AA01',
        substances: 'Alpha',
      ),
    ],
    'B01BB02': [
      SdifDrugSearchResult(
        brandName: 'Provider B',
        atcCode: 'B01BB02',
        substances: 'Beta',
      ),
    ],
  };
}

class _IntegrityGateway implements SdifGateway {
  _IntegrityGateway({required this.searches, this.checkResult});

  final Map<String, List<SdifDrugSearchResult>> searches;
  final SdifCheckResult? checkResult;
  List<String>? checkedDrugs;

  @override
  Future<List<SdifDrugSearchResult>> searchDrugByAtc(String atcCode) async {
    return searches[atcCode] ?? const [];
  }

  @override
  Future<SdifCheckResult> checkInteractions(List<String> drugs) async {
    checkedDrugs = List.unmodifiable(drugs);
    return checkResult ??
        (throw StateError('No fake SDIF check result configured.'));
  }
}
