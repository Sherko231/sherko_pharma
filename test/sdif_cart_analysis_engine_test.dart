import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_cart_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_result_aggregator.dart';
import 'package:sherko_pharma/features/interactions/application/sdif_reviewed_atc_bridge.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_scientific_identity_repository.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';

void main() {
  test('preserves partial and unmapped product coverage without inventing checks', () async {
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.partial,
        identities: [_identity(1)],
        ingredientCount: 2,
        trustedComponentCount: 1,
        atcCoveredComponentCount: 1,
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.unmapped,
        identities: const [],
        ingredientCount: 1,
        trustedComponentCount: 0,
        atcCoveredComponentCount: 0,
      ),
    });
    final provider = _FakeSdifGateway();
    final engine = _engine(repository, provider);

    final result = await engine.analyzeProductIds(const ['p1', 'p2']);

    expect(result.products[0].coverageStatus, SdifScientificCoverageStatus.partial);
    expect(result.products[1].coverageStatus, SdifScientificCoverageStatus.unmapped);
    expect(result.uniqueEligibleIdentityCount, 1);
    expect(result.providerResolvedIdentityCount, 1);
    expect(result.providerBatchCount, 0);
    expect(provider.checkCalls, isEmpty);
    expect(result.productPairs, hasLength(1));
    expect(result.productPairs.single.identityPairs, isEmpty);
  });

  test('records provider resolution gaps with affected Cart products', () async {
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(1)],
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(2)],
      ),
    });
    final provider = _FakeSdifGateway(unmappedAtcCodes: {'A001'});
    final result = await _engine(repository, provider).analyzeProductIds(
      const ['p1', 'p2'],
    );

    expect(result.providerResolutionGaps, hasLength(1));
    expect(
      result.providerResolutionGaps.single.identity.scientificIngredientId,
      1,
    );
    expect(result.providerResolutionGaps.single.productIds, ['p1']);
    expect(result.providerResolvedIdentityCount, 1);
    expect(result.providerBatchCount, 0);
    expect(result.productPairs.single.identityPairs, isEmpty);
  });

  test('excludes same-product-only identity pairs from product analysis', () async {
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(1), _identity(2)],
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(3)],
      ),
    });
    final provider = _FakeSdifGateway();
    final result = await _engine(repository, provider).analyzeProductIds(
      const ['p1', 'p2'],
    );

    expect(provider.checkCalls, hasLength(1));
    expect(provider.checkCalls.single, hasLength(3));
    expect(result.identityPairs, hasLength(2));
    expect(
      result.identityPairs
          .map((pair) => {
                pair.identityA.identity.scientificIngredientId,
                pair.identityB.identity.scientificIngredientId,
              })
          .toList(),
      [
        {1, 3},
        {2, 3},
      ],
    );
    expect(result.productPairs.single.identityPairs, hasLength(2));
    expect(
      result.productPairs.single.identityPairs
          .every((pair) => !pair.hasObservedHits),
      isTrue,
    );
  });

  test('deduplicates one scientific identity shared by multiple products', () async {
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(1)],
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(1), _identity(2)],
      ),
    });
    final provider = _FakeSdifGateway();
    final result = await _engine(repository, provider).analyzeProductIds(
      const ['p1', 'p2'],
    );

    expect(result.uniqueEligibleIdentityCount, 2);
    expect(provider.searchCalls.where((value) => value == 'A001'), hasLength(1));
    expect(result.identityPairs, hasLength(1));
    expect(result.productPairs.single.identityPairs, hasLength(1));
  });

  test('covers all cross-product identity pairs with <=10 drugs per batch', () async {
    final odd = <SdifProductScientificIdentity>[];
    final even = <SdifProductScientificIdentity>[];
    for (var id = 1; id <= 11; id++) {
      (id.isOdd ? odd : even).add(_identity(id));
    }
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: odd,
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: even,
      ),
    });
    final provider = _FakeSdifGateway();
    final result = await _engine(repository, provider).analyzeProductIds(
      const ['p1', 'p2'],
    );

    expect(result.uniqueEligibleIdentityCount, 11);
    expect(result.providerResolvedIdentityCount, 11);
    expect(result.providerBatchCount, 3);
    expect(provider.checkCalls, hasLength(3));
    expect(provider.checkCalls.every((batch) => batch.length <= 10), isTrue);
    expect(result.identityPairs, hasLength(30));
    expect(result.productPairs.single.identityPairs, hasLength(30));
    expect(result.providerHitCount, 0);
  });

  test('fails closed when an overlapping pair changes across batches', () async {
    final p1Identities = <SdifProductScientificIdentity>[];
    final p2Identities = <SdifProductScientificIdentity>[];
    for (var id = 1; id <= 11; id++) {
      (id.isOdd ? p1Identities : p2Identities).add(_identity(id));
    }
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: p1Identities,
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: p2Identities,
      ),
    });
    final provider = _FakeSdifGateway(
      interactionsForCall: (call, drugs) {
        if (call != 2 || !drugs.contains('Brand-A001') || !drugs.contains('Brand-A002')) {
          return const [];
        }
        return [_hit('A001', 'A002')];
      },
    );

    await expectLater(
      _engine(repository, provider).analyzeProductIds(const ['p1', 'p2']),
      throwsA(isA<SdifCartAnalysisMappingException>()),
    );
  });

  test('superseded analysis stops before provider work', () async {
    final repository = _FakeScientificRepository({
      'p1': _product(
        'p1',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(1)],
      ),
      'p2': _product(
        'p2',
        SdifScientificCoverageStatus.complete,
        identities: [_identity(2)],
      ),
    });
    final provider = _FakeSdifGateway();

    await expectLater(
      _engine(repository, provider).analyzeProductIds(
        const ['p1', 'p2'],
        isCurrent: () => false,
      ),
      throwsA(isA<SdifCartAnalysisSupersededException>()),
    );
    expect(repository.calls, 0);
    expect(provider.searchCalls, isEmpty);
  });
}

SdifCartAnalysisEngine _engine(
  SdifScientificIdentityRepository repository,
  SdifGateway provider,
) {
  return SdifCartAnalysisEngine(
    scientificIdentityRepository: repository,
    reviewedAtcBridge: SdifReviewedAtcBridge(gateway: provider),
    resultAggregator: const SdifResultAggregator(),
  );
}

SdifProductScientificInput _product(
  String productId,
  SdifScientificCoverageStatus status, {
  required List<SdifProductScientificIdentity> identities,
  int? ingredientCount,
  int? trustedComponentCount,
  int? atcCoveredComponentCount,
}) {
  final ingredients = ingredientCount ?? identities.length;
  final trusted = trustedComponentCount ?? identities.length;
  final atc = atcCoveredComponentCount ?? identities.length;
  return SdifProductScientificInput(
    requestPosition: 1,
    productId: productId,
    productExists: true,
    coverageStatus: status,
    canonicalizationStatus: 'trusted',
    ingredientCount: ingredients,
    trustedComponentCount: trusted,
    atcCoveredComponentCount: atc,
    eligibleIdentityCount: identities.length,
    identities: identities,
  );
}

SdifProductScientificIdentity _identity(int id) {
  final atc = 'A${id.toString().padLeft(3, '0')}';
  return SdifProductScientificIdentity(
    scientificIngredientId: id,
    preferredName: 'Ingredient $id',
    reviewedAtcCodes: [atc],
  );
}

SdifInteractionHit _hit(String atcA, String atcB) {
  return SdifInteractionHit(
    drugA: 'Brand-$atcA',
    drugAAtc: atcA,
    drugARoute: 'oral',
    drugB: 'Brand-$atcB',
    drugBAtc: atcB,
    drugBRoute: 'oral',
    family: SdifInteractionFamily.substance,
    severityScore: 1,
    severityLabel: 'Vorsicht',
    severityIndicator: '#',
    keyword: 'synthetic',
    description: 'Synthetic finding',
    explanation: 'Synthetic explanation',
    source: 'synthetic',
    comboHint: '',
  );
}

class _FakeScientificRepository implements SdifScientificIdentityRepository {
  _FakeScientificRepository(this.products);

  final Map<String, SdifProductScientificInput> products;
  int calls = 0;

  @override
  Future<List<SdifProductScientificInput>> resolveProducts(
    List<String> productIds,
  ) async {
    calls += 1;
    return [for (final id in productIds) products[id]!];
  }
}

typedef _InteractionsForCall = List<SdifInteractionHit> Function(
  int call,
  List<String> drugs,
);

class _FakeSdifGateway implements SdifGateway {
  _FakeSdifGateway({
    this.unmappedAtcCodes = const {},
    this.ambiguousAtcCodes = const {},
    this.interactionsForCall,
  });

  final Set<String> unmappedAtcCodes;
  final Set<String> ambiguousAtcCodes;
  final _InteractionsForCall? interactionsForCall;
  final List<String> searchCalls = [];
  final List<List<String>> checkCalls = [];

  @override
  Future<List<SdifDrugSearchResult>> searchDrugByAtc(String atcCode) async {
    searchCalls.add(atcCode);
    if (unmappedAtcCodes.contains(atcCode)) {
      return const [];
    }
    if (ambiguousAtcCodes.contains(atcCode)) {
      return [
        SdifDrugSearchResult(
          brandName: 'Brand-$atcCode-A',
          atcCode: atcCode,
          substances: 'Substance-$atcCode',
        ),
        SdifDrugSearchResult(
          brandName: 'Brand-$atcCode-B',
          atcCode: atcCode,
          substances: 'Substance-$atcCode',
        ),
      ];
    }
    return [
      SdifDrugSearchResult(
        brandName: 'Brand-$atcCode',
        atcCode: atcCode,
        substances: 'Substance-$atcCode',
      ),
    ];
  }

  @override
  Future<SdifCheckResult> checkInteractions(List<String> drugs) async {
    final captured = List<String>.unmodifiable(drugs);
    checkCalls.add(captured);
    final interactions = interactionsForCall?.call(checkCalls.length, captured) ?? const <SdifInteractionHit>[];
    return SdifCheckResult(
      basket: [
        for (final brand in drugs)
          SdifBasketDrug(
            brand: brand,
            atcCode: brand.substring('Brand-'.length),
            substances: ['Substance-${brand.substring('Brand-'.length)}'],
          ),
      ],
      interactions: interactions,
    );
  }
}
