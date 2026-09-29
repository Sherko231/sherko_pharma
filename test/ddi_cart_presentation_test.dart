import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/ddi_cart_presentation.dart';

void main() {
  test('row uses highest severity and counts every product pair', () {
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product('a'),
          _product('b'),
          _product('c'),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.minor,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'c',
            severity: InteractionSeverity.moderate,
            ingredientInteractions: [],
          ),
        ],
      ),
    );

    expect(
      presentation.rows['a']?.severity,
      InteractionSeverity.moderate,
    );
    expect(presentation.rows['a']?.pairCount, 2);
    expect(presentation.rows['b']?.severity, InteractionSeverity.minor);
    expect(presentation.rows['b']?.pairCount, 1);
    expect(
      presentation.rows['c']?.severity,
      InteractionSeverity.moderate,
    );
    expect(presentation.rows['c']?.pairCount, 1);
  });

  test('summary keeps major moderate minor unknown and none separate', () {
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product('a'),
          _product('b'),
          _product('c'),
          _product('d'),
          _product('e'),
          _product('f'),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.major,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'c',
            severity: InteractionSeverity.moderate,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'd',
            severity: InteractionSeverity.minor,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'e',
            severity: InteractionSeverity.unknown,
            ingredientInteractions: [],
          ),
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'f',
            severity: InteractionSeverity.none,
            ingredientInteractions: [],
          ),
        ],
      ),
    );

    expect(presentation.pairCount(InteractionSeverity.major), 1);
    expect(presentation.pairCount(InteractionSeverity.moderate), 1);
    expect(presentation.pairCount(InteractionSeverity.minor), 1);
    expect(presentation.pairCount(InteractionSeverity.unknown), 1);
    expect(presentation.pairCount(InteractionSeverity.none), 1);
    expect(presentation.totalPairCount, 5);
    expect(presentation.rows['a']?.severity, InteractionSeverity.major);
  });

  test('local normalization gaps remain incomplete and are not none', () {
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product(
            'review',
            status: DdiIngredientCoverageStatus.needsReview,
          ),
          _product(
            'unresolved',
            status: DdiIngredientCoverageStatus.unresolved,
          ),
          _product(
            'missing',
            status: DdiIngredientCoverageStatus.missing,
          ),
        ],
      ),
    );

    for (final productId in ['review', 'unresolved', 'missing']) {
      final row = presentation.rows[productId]!;
      expect(row.severity, isNull);
      expect(row.localCoverageComplete, isFalse);
      expect(row.incompleteCoverage, isTrue);
    }
    expect(presentation.incompleteProductCount, 3);
    expect(presentation.pairCount(InteractionSeverity.none), 0);
  });

  test('provider unresolved stays incomplete alongside known severity', () {
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product('a'),
          _product('b'),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.major,
            ingredientInteractions: [],
          ),
        ],
        providerUnresolved: const [
          DdiProviderUnresolvedIngredient(
            ingredient: DdiIngredientIdentity(
              id: 11,
              name: 'Ingredient A',
              normalizedName: 'ingredient a',
            ),
            query: 'Ingredient A',
            productIds: ['a'],
            suggestions: [],
          ),
        ],
      ),
    );

    final a = presentation.rows['a']!;
    expect(a.severity, InteractionSeverity.major);
    expect(a.providerUnresolved, isTrue);
    expect(a.incompleteCoverage, isTrue);
    expect(presentation.incompleteProductCount, 1);
  });

  test('provider notices are deduplicated for adjacent Cart attribution', () {
    final notice = _notice();
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product('a'),
          _product('b'),
        ],
        pairs: const [
          DdiProductPairInteraction(
            productAId: 'a',
            productBId: 'b',
            severity: InteractionSeverity.none,
            ingredientInteractions: [],
          ),
        ],
        providerNotices: [
          notice,
          notice,
          DdiProviderNotice(
            data: InteractionCheckData(
              labelExportDate: DateTime(2026, 9, 4),
            ),
            disclaimer: notice.disclaimer,
            attribution: notice.attribution,
          ),
        ],
      ),
    );

    expect(presentation.providerNotices, hasLength(1));
    expect(
      presentation.providerNotices.single.disclaimer,
      'Not medical advice.',
    );
    expect(
      presentation.providerNotices.single.attribution.url?.toString(),
      'https://interaction-checker.com',
    );
  });

  test('trusted product with no explicit pair result stays incomplete', () {
    final presentation = buildDdiCartPresentation(
      _analysis(
        products: [
          _product('a'),
          _product('b'),
        ],
      ),
    );

    expect(presentation.rows['a']?.severity, isNull);
    expect(presentation.rows['a']?.incompleteCoverage, isTrue);
    expect(presentation.rows['b']?.incompleteCoverage, isTrue);
    expect(presentation.incompleteProductCount, 2);
  });
}

DdiAnalysisResult _analysis({
  required List<DdiProductIngredientInput> products,
  List<DdiProductPairInteraction> pairs = const [],
  List<DdiProviderUnresolvedIngredient> providerUnresolved = const [],
  List<DdiProviderNotice> providerNotices = const [],
}) {
  return DdiAnalysisResult(
    products: products,
    providerUnresolved: providerUnresolved,
    productPairs: pairs,
    providerNotices: providerNotices,
    uniqueIngredientCount: 0,
    providerBatchCount: 0,
  );
}

DdiProviderNotice _notice() {
  return DdiProviderNotice(
    data: InteractionCheckData(
      labelExportDate: DateTime.utc(2026, 9, 3),
      generatedAt: DateTime.utc(2026, 9, 7),
    ),
    disclaimer: 'Not medical advice.',
    attribution: InteractionAttribution(
      text: 'Interaction Checker',
      url: Uri.parse('https://interaction-checker.com'),
      license: 'Free with attribution',
    ),
  );
}

DdiProductIngredientInput _product(
  String productId, {
  DdiIngredientCoverageStatus status =
      DdiIngredientCoverageStatus.trusted,
}) {
  return DdiProductIngredientInput(
    productId: productId,
    requestPosition: 1,
    coverageStatus: status,
    productExists: status != DdiIngredientCoverageStatus.missing,
    normalizationStatus: switch (status) {
      DdiIngredientCoverageStatus.trusted => 'auto_verified',
      DdiIngredientCoverageStatus.needsReview => 'needs_review',
      DdiIngredientCoverageStatus.unresolved => 'unresolved',
      DdiIngredientCoverageStatus.missing => null,
    },
    componentCount:
        status == DdiIngredientCoverageStatus.trusted ? 1 : null,
    resolvedComponentCount:
        status == DdiIngredientCoverageStatus.trusted ? 1 : null,
    ingredients: status == DdiIngredientCoverageStatus.trusted
        ? [
            DdiIngredientIdentity(
              id: productId.hashCode,
              name: 'Ingredient $productId',
              normalizedName: 'ingredient $productId',
            ),
          ]
        : const [],
  );
}
