import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/application/sdif_reviewed_atc_bridge.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';

void main() {
  group('SdifReviewedAtcBridge', () {
    test('resolves only through reviewed ATC and never preferred-name search', () async {
      final gateway = _FakeSdifGateway(
        searches: {
          'J01CA04': const [
            SdifDrugSearchResult(
              brandName: 'Amoxicillin Provider®',
              atcCode: 'J01CA04',
              substances: 'Amoxicillin',
            ),
          ],
        },
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      final result = await bridge.resolveIdentity(
        _identity(1, 'Local preferred name must not be queried', ['J01CA04']),
      );

      expect(result.status, SdifReviewedAtcResolutionStatus.resolved);
      expect(result.resolvedIdentity, isNotNull);
      expect(
        result.resolvedIdentity!.providerDrug.brandName,
        'Amoxicillin Provider®',
      );
      expect(gateway.atcQueries, ['J01CA04']);
    });

    test('keeps a missing reviewed ATC provider lookup explicitly unmapped', () async {
      final gateway = _FakeSdifGateway(searches: const {});
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      final result = await bridge.resolveIdentity(
        _identity(2, 'Caffeine', ['N06BC01']),
      );

      expect(result.status, SdifReviewedAtcResolutionStatus.unmapped);
      expect(result.candidates, isEmpty);
      expect(result.resolvedIdentity, isNull);
    });

    test('keeps multiple provider candidates across reviewed ATCs ambiguous', () async {
      final gateway = _FakeSdifGateway(
        searches: {
          'A01AA01': const [
            SdifDrugSearchResult(
              brandName: 'Provider One',
              atcCode: 'A01AA01',
              substances: 'Example',
            ),
          ],
          'A01AA02': const [
            SdifDrugSearchResult(
              brandName: 'Provider Two',
              atcCode: 'A01AA02',
              substances: 'Example',
            ),
          ],
        },
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      final result = await bridge.resolveIdentity(
        _identity(4, 'Example', ['A01AA01', 'A01AA02']),
      );

      expect(result.status, SdifReviewedAtcResolutionStatus.ambiguous);
      expect(result.candidates, hasLength(2));
      expect(result.resolvedIdentity, isNull);
    });

    test('fails closed when SDIF returns a different ATC than requested', () async {
      final gateway = _FakeSdifGateway(
        searches: {
          'N02BE01': const [
            SdifDrugSearchResult(
              brandName: 'Wrong ATC Provider',
              atcCode: 'N02BE02',
              substances: 'Paracetamol',
            ),
          ],
        },
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      await expectLater(
        bridge.resolveIdentity(
          _identity(3, 'Paracetamol', ['N02BE01']),
        ),
        throwsA(isA<SdifReviewedAtcIntegrityException>()),
      );
    });

    test('submits exact resolved provider brands and verifies basket identity', () async {
      final gateway = _FakeSdifGateway(
        searches: _twoSearches(),
        checkResult: const SdifCheckResult(
          basket: [
            SdifBasketDrug(
              brand: 'Provider A®',
              atcCode: 'A01AA01',
              substances: ['alpha'],
            ),
            SdifBasketDrug(
              brand: 'Provider B®',
              atcCode: 'B01BB02',
              substances: ['beta'],
            ),
          ],
          interactions: [],
        ),
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);
      final resolutions = await bridge.resolveIdentities([
        _identity(10, 'Alpha local scientific name', ['A01AA01']),
        _identity(11, 'Beta local scientific name', ['B01BB02']),
      ]);
      final resolved = resolutions
          .map((item) => item.resolvedIdentity!)
          .toList(growable: false);

      final checked = await bridge.checkResolvedIdentities(resolved);

      expect(gateway.checkedDrugs, ['Provider A®', 'Provider B®']);
      expect(checked.identities, hasLength(2));
      expect(checked.providerResult.basket, hasLength(2));
      expect(checked.providerResult.interactions, isEmpty);
    });

    test('fails closed when provider basket no longer matches selected drug', () async {
      final gateway = _FakeSdifGateway(
        searches: _twoSearches(),
        checkResult: const SdifCheckResult(
          basket: [
            SdifBasketDrug(
              brand: 'Different Provider A®',
              atcCode: 'A01AA01',
              substances: ['alpha'],
            ),
            SdifBasketDrug(
              brand: 'Provider B®',
              atcCode: 'B01BB02',
              substances: ['beta'],
            ),
          ],
          interactions: [],
        ),
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);
      final resolutions = await bridge.resolveIdentities([
        _identity(10, 'Alpha', ['A01AA01']),
        _identity(11, 'Beta', ['B01BB02']),
      ]);

      await expectLater(
        bridge.checkResolvedIdentities(
          resolutions.map((item) => item.resolvedIdentity!).toList(),
        ),
        throwsA(isA<SdifReviewedAtcBasketIntegrityException>()),
      );
    });

    test('fails closed when provider basket substance set changes', () async {
      final gateway = _FakeSdifGateway(
        searches: _twoSearches(),
        checkResult: const SdifCheckResult(
          basket: [
            SdifBasketDrug(
              brand: 'Provider A®',
              atcCode: 'A01AA01',
              substances: ['different'],
            ),
            SdifBasketDrug(
              brand: 'Provider B®',
              atcCode: 'B01BB02',
              substances: ['beta'],
            ),
          ],
          interactions: [],
        ),
      );
      final bridge = SdifReviewedAtcBridge(gateway: gateway);
      final resolutions = await bridge.resolveIdentities([
        _identity(10, 'Alpha', ['A01AA01']),
        _identity(11, 'Beta', ['B01BB02']),
      ]);

      await expectLater(
        bridge.checkResolvedIdentities(
          resolutions.map((item) => item.resolvedIdentity!).toList(),
        ),
        throwsA(isA<SdifReviewedAtcBasketIntegrityException>()),
      );
    });

    test('rejects identities with no reviewed ATC before provider access', () async {
      final gateway = _FakeSdifGateway(searches: const {});
      final bridge = SdifReviewedAtcBridge(gateway: gateway);

      await expectLater(
        bridge.resolveIdentity(_identity(12, 'No ATC', const [])),
        throwsA(isA<SdifReviewedAtcInvalidInputException>()),
      );
      expect(gateway.atcQueries, isEmpty);
    });
  });
}

SdifReviewedScientificIdentity _identity(
  int id,
  String preferredName,
  List<String> atcCodes,
) {
  return SdifReviewedScientificIdentity(
    scientificIngredientId: id,
    preferredName: preferredName,
    reviewedAtcCodes: atcCodes,
  );
}

Map<String, List<SdifDrugSearchResult>> _twoSearches() {
  return const {
    'A01AA01': [
      SdifDrugSearchResult(
        brandName: 'Provider A®',
        atcCode: 'A01AA01',
        substances: 'Alpha',
      ),
    ],
    'B01BB02': [
      SdifDrugSearchResult(
        brandName: 'Provider B®',
        atcCode: 'B01BB02',
        substances: 'Beta',
      ),
    ],
  };
}

class _FakeSdifGateway implements SdifGateway {
  _FakeSdifGateway({
    required this.searches,
    this.checkResult,
  });

  final Map<String, List<SdifDrugSearchResult>> searches;
  final SdifCheckResult? checkResult;
  final List<String> atcQueries = [];
  List<String>? checkedDrugs;

  @override
  Future<List<SdifDrugSearchResult>> searchDrugByAtc(String atcCode) async {
    atcQueries.add(atcCode);
    return searches[atcCode] ?? const [];
  }

  @override
  Future<SdifCheckResult> checkInteractions(List<String> drugs) async {
    checkedDrugs = List.unmodifiable(drugs);
    final result = checkResult;
    if (result == null) {
      throw StateError('No fake SDIF check result configured.');
    }
    return result;
  }
}
