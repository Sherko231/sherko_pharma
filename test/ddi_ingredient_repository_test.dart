import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/data/ddi_ingredient_repository.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';

void main() {
  group('SupabaseDdiIngredientRepository', () {
    test('maps trusted ingredients in component order and explicit coverage', () async {
      final rpc = _FakeRpcClient([
        {
          'request_position': 1,
          'product_id': 'p1',
          'product_exists': true,
          'coverage_status': 'trusted',
          'normalization_status': 'auto_verified',
          'component_count': 2,
          'resolved_component_count': 2,
          'component_index': 2,
          'ingredient_id': 20,
          'ingredient_name': 'Beta',
          'normalized_ingredient_name': 'beta',
        },
        {
          'request_position': 1,
          'product_id': 'p1',
          'product_exists': true,
          'coverage_status': 'trusted',
          'normalization_status': 'auto_verified',
          'component_count': 2,
          'resolved_component_count': 2,
          'component_index': 1,
          'ingredient_id': 10,
          'ingredient_name': 'Alpha',
          'normalized_ingredient_name': 'alpha',
        },
        {
          'request_position': 2,
          'product_id': 'p2',
          'product_exists': true,
          'coverage_status': 'needs_review',
          'normalization_status': 'needs_review',
          'component_count': 1,
          'resolved_component_count': 0,
          'component_index': null,
          'ingredient_id': null,
          'ingredient_name': null,
          'normalized_ingredient_name': null,
        },
        {
          'request_position': 3,
          'product_id': 'missing',
          'product_exists': false,
          'coverage_status': 'missing',
          'normalization_status': null,
          'component_count': null,
          'resolved_component_count': null,
          'component_index': null,
          'ingredient_id': null,
          'ingredient_name': null,
          'normalized_ingredient_name': null,
        },
      ]);
      final repository = SupabaseDdiIngredientRepository(rpc);

      final result = await repository.resolveProducts(
        const ['p1', 'p2', 'p1', 'missing'],
      );

      expect(rpc.calls, 1);
      expect(rpc.functionName, 'catalog_ddi_ingredients');
      expect(
        rpc.params['requested_product_ids'],
        ['p1', 'p2', 'missing'],
      );
      expect(result, hasLength(3));

      final trusted = result[0];
      expect(trusted.coverageStatus, DdiIngredientCoverageStatus.trusted);
      expect(trusted.normalizationStatus, 'auto_verified');
      expect(trusted.ingredients.map((item) => item.id), [10, 20]);
      expect(
        trusted.ingredients.map((item) => item.name),
        ['Alpha', 'Beta'],
      );

      expect(
        result[1].coverageStatus,
        DdiIngredientCoverageStatus.needsReview,
      );
      expect(result[1].ingredients, isEmpty);

      expect(
        result[2].coverageStatus,
        DdiIngredientCoverageStatus.missing,
      );
      expect(result[2].productExists, isFalse);
      expect(result[2].ingredients, isEmpty);
    });

    test('rejects blank and over-bound requests before RPC use', () async {
      final rpc = _FakeRpcClient(const []);
      final repository = SupabaseDdiIngredientRepository(rpc);

      await expectLater(
        repository.resolveProducts(const ['p1', '   ']),
        throwsA(isA<DdiIngredientRequestException>()),
      );
      await expectLater(
        repository.resolveProducts(
          List<String>.generate(51, (index) => 'p' + index.toString()),
        ),
        throwsA(isA<DdiIngredientRequestException>()),
      );

      expect(rpc.calls, 0);
    });

    test('rejects ingredient identity leakage on untrusted coverage', () async {
      final repository = SupabaseDdiIngredientRepository(
        _FakeRpcClient([
          {
            'request_position': 1,
            'product_id': 'p1',
            'product_exists': true,
            'coverage_status': 'unresolved',
            'normalization_status': 'unresolved',
            'component_count': 1,
            'resolved_component_count': 0,
            'component_index': 1,
            'ingredient_id': 10,
            'ingredient_name': 'Should not leak',
            'normalized_ingredient_name': 'should not leak',
          },
        ]),
      );

      await expectLater(
        repository.resolveProducts(const ['p1']),
        throwsA(isA<DdiIngredientResponseException>()),
      );
    });

    test('rejects malformed or omitted product rows', () async {
      final repository = SupabaseDdiIngredientRepository(
        _FakeRpcClient(const []),
      );

      await expectLater(
        repository.resolveProducts(const ['p1']),
        throwsA(isA<DdiIngredientResponseException>()),
      );
    });
  });
}

class _FakeRpcClient implements DdiIngredientRpcClient {
  _FakeRpcClient(this.response);

  final dynamic response;
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
    return response;
  }
}
