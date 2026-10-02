import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_scientific_identity_repository.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';

void main() {
  group('SupabaseSdifScientificIdentityRepository', () {
    test('maps complete and partial coverage in deterministic identity order', () async {
      final rpc = _FakeRpcClient([
        _row(
          requestPosition: 1,
          productId: 'p1',
          coverageStatus: 'complete',
          canonicalizationStatus: 'trusted',
          ingredientCount: 2,
          trustedComponentCount: 2,
          atcCoveredComponentCount: 2,
          eligibleIdentityCount: 2,
          identityPosition: 2,
          scientificIngredientId: 2,
          preferredName: 'Caffeine',
          reviewedAtcCodes: const ['N06BC01'],
        ),
        _row(
          requestPosition: 1,
          productId: 'p1',
          coverageStatus: 'complete',
          canonicalizationStatus: 'trusted',
          ingredientCount: 2,
          trustedComponentCount: 2,
          atcCoveredComponentCount: 2,
          eligibleIdentityCount: 2,
          identityPosition: 1,
          scientificIngredientId: 1,
          preferredName: 'Amoxicillin',
          reviewedAtcCodes: const ['J01CA04'],
        ),
        _row(
          requestPosition: 2,
          productId: 'p2',
          coverageStatus: 'partial',
          canonicalizationStatus: 'trusted',
          ingredientCount: 2,
          trustedComponentCount: 2,
          atcCoveredComponentCount: 1,
          eligibleIdentityCount: 1,
          identityPosition: 1,
          scientificIngredientId: 1,
          preferredName: 'Amoxicillin',
          reviewedAtcCodes: const ['J01CA04'],
        ),
      ]);
      final repository = SupabaseSdifScientificIdentityRepository(rpc);

      final result = await repository.resolveProducts(const ['p1', 'p2', 'p1']);

      expect(rpc.calls, 1);
      expect(rpc.functionName, 'catalog_sdif_scientific_identities');
      expect(rpc.params['requested_product_ids'], ['p1', 'p2']);
      expect(result, hasLength(2));

      final complete = result[0];
      expect(complete.coverageStatus, SdifScientificCoverageStatus.complete);
      expect(complete.hasCompleteCoverage, isTrue);
      expect(complete.ingredientCount, 2);
      expect(complete.atcCoveredComponentCount, 2);
      expect(
        complete.identities.map((identity) => identity.preferredName),
        ['Amoxicillin', 'Caffeine'],
      );
      expect(
        complete.identities.first.toReviewedIdentity().reviewedAtcCodes,
        ['J01CA04'],
      );

      final partial = result[1];
      expect(partial.coverageStatus, SdifScientificCoverageStatus.partial);
      expect(partial.hasEligibleIdentities, isTrue);
      expect(partial.ingredientCount, 2);
      expect(partial.trustedComponentCount, 2);
      expect(partial.atcCoveredComponentCount, 1);
      expect(partial.eligibleIdentityCount, 1);
      expect(partial.identities.single.preferredName, 'Amoxicillin');
    });

    test('keeps unmapped and missing products explicit without identities', () async {
      final repository = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _summaryRow(
            requestPosition: 1,
            productId: 'unmapped',
            productExists: true,
            coverageStatus: 'unmapped',
            canonicalizationStatus: 'high_confidence',
            ingredientCount: 1,
            trustedComponentCount: 0,
          ),
          _summaryRow(
            requestPosition: 2,
            productId: 'missing',
            productExists: false,
            coverageStatus: 'missing',
            canonicalizationStatus: null,
            ingredientCount: 0,
            trustedComponentCount: 0,
          ),
        ]),
      );

      final result = await repository.resolveProducts(
        const ['unmapped', 'missing'],
      );

      expect(result[0].coverageStatus, SdifScientificCoverageStatus.unmapped);
      expect(result[0].productExists, isTrue);
      expect(result[0].identities, isEmpty);
      expect(result[1].coverageStatus, SdifScientificCoverageStatus.missing);
      expect(result[1].productExists, isFalse);
      expect(result[1].canonicalizationStatus, isNull);
      expect(result[1].identities, isEmpty);
    });

    test('rejects contradictory coverage and malformed ATC metadata', () async {
      final contradictory = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _row(
            requestPosition: 1,
            productId: 'p1',
            coverageStatus: 'complete',
            canonicalizationStatus: 'trusted',
            ingredientCount: 2,
            trustedComponentCount: 2,
            atcCoveredComponentCount: 1,
            eligibleIdentityCount: 1,
            identityPosition: 1,
            scientificIngredientId: 1,
            preferredName: 'Amoxicillin',
            reviewedAtcCodes: const ['J01CA04'],
          ),
        ]),
      );
      await expectLater(
        contradictory.resolveProducts(const ['p1']),
        throwsA(isA<SdifScientificIdentityResponseException>()),
      );

      final unsortedAtc = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _row(
            requestPosition: 1,
            productId: 'p1',
            coverageStatus: 'complete',
            canonicalizationStatus: 'trusted',
            ingredientCount: 1,
            trustedComponentCount: 1,
            atcCoveredComponentCount: 1,
            eligibleIdentityCount: 1,
            identityPosition: 1,
            scientificIngredientId: 1,
            preferredName: 'Example',
            reviewedAtcCodes: const ['N06BC01', 'J01CA04'],
          ),
        ]),
      );
      await expectLater(
        unsortedAtc.resolveProducts(const ['p1']),
        throwsA(isA<SdifScientificIdentityResponseException>()),
      );
    });

    test('rejects duplicate identities, omitted products, and foreign rows', () async {
      final duplicateIdentity = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _row(
            requestPosition: 1,
            productId: 'p1',
            coverageStatus: 'complete',
            canonicalizationStatus: 'trusted',
            ingredientCount: 2,
            trustedComponentCount: 2,
            atcCoveredComponentCount: 2,
            eligibleIdentityCount: 2,
            identityPosition: 1,
            scientificIngredientId: 1,
            preferredName: 'Amoxicillin',
            reviewedAtcCodes: const ['J01CA04'],
          ),
          _row(
            requestPosition: 1,
            productId: 'p1',
            coverageStatus: 'complete',
            canonicalizationStatus: 'trusted',
            ingredientCount: 2,
            trustedComponentCount: 2,
            atcCoveredComponentCount: 2,
            eligibleIdentityCount: 2,
            identityPosition: 2,
            scientificIngredientId: 1,
            preferredName: 'Amoxicillin',
            reviewedAtcCodes: const ['J01CA04'],
          ),
        ]),
      );
      await expectLater(
        duplicateIdentity.resolveProducts(const ['p1']),
        throwsA(isA<SdifScientificIdentityResponseException>()),
      );

      final omitted = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _summaryRow(
            requestPosition: 1,
            productId: 'p1',
            productExists: true,
            coverageStatus: 'unmapped',
            canonicalizationStatus: 'unresolved',
            ingredientCount: 1,
            trustedComponentCount: 0,
          ),
        ]),
      );
      await expectLater(
        omitted.resolveProducts(const ['p1', 'p2']),
        throwsA(isA<SdifScientificIdentityResponseException>()),
      );

      final foreign = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient([
          _summaryRow(
            requestPosition: 1,
            productId: 'p1',
            productExists: true,
            coverageStatus: 'unmapped',
            canonicalizationStatus: 'unresolved',
            ingredientCount: 1,
            trustedComponentCount: 0,
          ),
          _summaryRow(
            requestPosition: 2,
            productId: 'foreign',
            productExists: true,
            coverageStatus: 'unmapped',
            canonicalizationStatus: 'unresolved',
            ingredientCount: 1,
            trustedComponentCount: 0,
          ),
        ]),
      );
      await expectLater(
        foreign.resolveProducts(const ['p1']),
        throwsA(isA<SdifScientificIdentityResponseException>()),
      );
    });

    test('rejects blank and over-bound requests before RPC use', () async {
      final rpc = _FakeRpcClient(const []);
      final repository = SupabaseSdifScientificIdentityRepository(rpc);

      await expectLater(
        repository.resolveProducts(const ['p1', '   ']),
        throwsA(isA<SdifScientificIdentityRequestException>()),
      );
      await expectLater(
        repository.resolveProducts(
          List<String>.generate(51, (index) => 'p$index'),
        ),
        throwsA(isA<SdifScientificIdentityRequestException>()),
      );
      expect(rpc.calls, 0);
    });

    test('classifies RPC failure as transport failure', () async {
      final repository = SupabaseSdifScientificIdentityRepository(
        _FakeRpcClient.error(),
      );

      await expectLater(
        repository.resolveProducts(const ['p1']),
        throwsA(isA<SdifScientificIdentityTransportException>()),
      );
    });
  });
}

Map<String, dynamic> _row({
  required int requestPosition,
  required String productId,
  required String coverageStatus,
  required String? canonicalizationStatus,
  required int ingredientCount,
  required int trustedComponentCount,
  required int atcCoveredComponentCount,
  required int eligibleIdentityCount,
  required int identityPosition,
  required int scientificIngredientId,
  required String preferredName,
  required List<String> reviewedAtcCodes,
}) {
  return {
    'request_position': requestPosition,
    'product_id': productId,
    'product_exists': true,
    'coverage_status': coverageStatus,
    'canonicalization_status': canonicalizationStatus,
    'ingredient_count': ingredientCount,
    'trusted_component_count': trustedComponentCount,
    'atc_covered_component_count': atcCoveredComponentCount,
    'eligible_identity_count': eligibleIdentityCount,
    'identity_position': identityPosition,
    'scientific_ingredient_id': scientificIngredientId,
    'preferred_name': preferredName,
    'reviewed_atc_codes': reviewedAtcCodes,
  };
}

Map<String, dynamic> _summaryRow({
  required int requestPosition,
  required String productId,
  required bool productExists,
  required String coverageStatus,
  required String? canonicalizationStatus,
  required int ingredientCount,
  required int trustedComponentCount,
}) {
  return {
    'request_position': requestPosition,
    'product_id': productId,
    'product_exists': productExists,
    'coverage_status': coverageStatus,
    'canonicalization_status': canonicalizationStatus,
    'ingredient_count': ingredientCount,
    'trusted_component_count': trustedComponentCount,
    'atc_covered_component_count': 0,
    'eligible_identity_count': 0,
    'identity_position': null,
    'scientific_ingredient_id': null,
    'preferred_name': null,
    'reviewed_atc_codes': null,
  };
}

class _FakeRpcClient implements SdifScientificIdentityRpcClient {
  _FakeRpcClient(this.response) : shouldThrow = false;

  _FakeRpcClient.error()
      : response = null,
        shouldThrow = true;

  final dynamic response;
  final bool shouldThrow;
  int calls = 0;
  String? functionName;
  Map<String, dynamic> params = const {};

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    calls += 1;
    this.functionName = functionName;
    this.params = params;
    if (shouldThrow) {
      throw StateError('synthetic transport failure');
    }
    return response;
  }
}
