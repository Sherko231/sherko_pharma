import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/ddi_interaction_detail_sheet.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';

void main() {
  test('detail presentation resolves Cart names and all focus product pairs', () {
    final analysis = _analysis(
      pairs: [
        _pair(
          'a',
          'b',
          InteractionSeverity.minor,
          interactions: [_interaction(1, 'Alpha', 2, 'Beta')],
        ),
        _pair(
          'a',
          'c',
          InteractionSeverity.moderate,
          interactions: [_interaction(1, 'Alpha', 3, 'Gamma')],
        ),
        _pair(
          'b',
          'c',
          InteractionSeverity.major,
          interactions: [_interaction(2, 'Beta', 3, 'Gamma')],
        ),
      ],
    );

    final detail = buildDdiInteractionDetailPresentation(
      analysis: analysis,
      orderLines: const [
        OrderLine(
          productId: 'a',
          displayName: 'Brand A',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'b',
          displayName: 'Brand B',
          quantity: 1,
          unitAmount: 2000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'c',
          displayName: 'Brand C',
          quantity: 1,
          unitAmount: 3000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'a',
    );

    expect(detail.focusProductName, 'Brand A');
    expect(detail.pairs, hasLength(2));
    expect(detail.pairs[0].severity, InteractionSeverity.moderate);
    expect(detail.pairs[0].productAName, 'Brand A');
    expect(detail.pairs[0].productBName, 'Brand C');
    expect(detail.pairs[1].severity, InteractionSeverity.minor);
    expect(detail.pairs[1].productBName, 'Brand B');
  });

  test('combination ingredient interactions remain separate', () {
    final detail = buildDdiInteractionDetailPresentation(
      analysis: _analysis(
        pairs: [
          _pair(
            'combo',
            'single',
            InteractionSeverity.moderate,
            interactions: [
              _interaction(10, 'Alpha', 30, 'Gamma'),
              _interaction(20, 'Beta', 30, 'Gamma'),
            ],
          ),
        ],
      ),
      orderLines: const [
        OrderLine(
          productId: 'combo',
          displayName: 'Combo',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'single',
          displayName: 'Single',
          quantity: 1,
          unitAmount: 1000,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'combo',
    );

    final interactions = detail.pairs.single.ingredientInteractions;
    expect(interactions, hasLength(2));
    expect(interactions[0].ingredientA.name, 'Alpha');
    expect(interactions[0].ingredientB.name, 'Gamma');
    expect(interactions[1].ingredientA.name, 'Beta');
    expect(interactions[1].ingredientB.name, 'Gamma');
  });

  test('identical provider notices are deduplicated', () {
    final notice = _notice();
    final detail = buildDdiInteractionDetailPresentation(
      analysis: DdiAnalysisResult(
        products: const [],
        providerUnresolved: const [],
        productPairs: [
          _pair('a', 'b', InteractionSeverity.none),
        ],
        providerNotices: [notice, notice],
        uniqueIngredientCount: 2,
        providerBatchCount: 2,
      ),
      orderLines: const [
        OrderLine(
          productId: 'a',
          displayName: 'A',
          quantity: 1,
          unitAmount: 1,
          currency: 'SYP',
          productRevision: 1,
        ),
        OrderLine(
          productId: 'b',
          displayName: 'B',
          quantity: 1,
          unitAmount: 1,
          currency: 'SYP',
          productRevision: 1,
        ),
      ],
      focusProductId: 'a',
    );

    expect(detail.notices, hasLength(1));
    expect(detail.notices.single.disclaimer, 'Not medical advice.');
    expect(
      detail.notices.single.attribution.url.toString(),
      'https://interaction-checker.com',
    );
  });
}

DdiAnalysisResult _analysis({
  required List<DdiProductPairInteraction> pairs,
}) {
  return DdiAnalysisResult(
    products: const [],
    providerUnresolved: const [],
    productPairs: pairs,
    providerNotices: [_notice()],
    uniqueIngredientCount: 3,
    providerBatchCount: 1,
  );
}

DdiProductPairInteraction _pair(
  String a,
  String b,
  InteractionSeverity severity, {
  List<DdiIngredientInteraction> interactions = const [],
}) {
  return DdiProductPairInteraction(
    productAId: a,
    productBId: b,
    severity: severity,
    ingredientInteractions: interactions,
  );
}

DdiIngredientInteraction _interaction(
  int aId,
  String aName,
  int bId,
  String bName,
) {
  return DdiIngredientInteraction(
    ingredientA: DdiIngredientIdentity(
      id: aId,
      name: aName,
      normalizedName: aName.toLowerCase(),
    ),
    ingredientB: DdiIngredientIdentity(
      id: bId,
      name: bName,
      normalizedName: bName.toLowerCase(),
    ),
    severity: InteractionSeverity.moderate,
    severityLabel: 'Moderate',
    evidence: [
      InteractionEvidence(
        from: aName,
        about: bName,
        section: InteractionEvidenceSection.drugInteractions,
        sectionLabel: 'Drug interactions',
        severity: InteractionEvidenceSeverity.moderate,
        quote: 'Synthetic evidence for testing.',
        matchedTerm: bName.toLowerCase(),
        matchKind: InteractionMatchKind.name,
        source: InteractionEvidenceSource(
          type: InteractionSourceType.fdaLabel,
          name: 'Synthetic FDA label',
          url: Uri.parse('https://dailymed.nlm.nih.gov/test'),
          effectiveDate: DateTime.utc(2026, 1, 2),
        ),
      ),
    ],
    interactionUrl: Uri.parse(
      'https://interaction-checker.com/?d=$aName,$bName',
    ),
    detailPage: Uri.parse(
      'https://interaction-checker.com/interactions/test',
    ),
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
      text: 'Data from Interaction Checker',
      url: Uri.parse('https://interaction-checker.com'),
      license: 'Free with attribution',
    ),
  );
}
