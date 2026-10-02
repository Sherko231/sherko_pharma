import 'package:flutter/material.dart';

import '../../order/domain/order_model.dart';
import '../domain/sdif_cart_analysis_models.dart';
import '../domain/sdif_models.dart';
import '../domain/sdif_product_scientific_models.dart';
import '../domain/sdif_result_models.dart';

class SdifInteractionDetailPresentation {
  const SdifInteractionDetailPresentation({
    required this.focusProductId,
    required this.focusProductName,
    required this.coverageStatus,
    required this.providerResolutionGaps,
    required this.productPairs,
  });

  final String focusProductId;
  final String focusProductName;
  final SdifScientificCoverageStatus coverageStatus;
  final List<SdifProviderResolutionGap> providerResolutionGaps;
  final List<SdifProductPairDetailPresentation> productPairs;
}

class SdifProductPairDetailPresentation {
  const SdifProductPairDetailPresentation({
    required this.productAId,
    required this.productAName,
    required this.productBId,
    required this.productBName,
    required this.identityPairs,
  });

  final String productAId;
  final String productAName;
  final String productBId;
  final String productBName;
  final List<SdifPairAssessment> identityPairs;
}

SdifInteractionDetailPresentation buildSdifInteractionDetailPresentation({
  required SdifCartAnalysisResult analysis,
  required List<OrderLine> orderLines,
  required String focusProductId,
}) {
  final names = <String, String>{
    for (final line in orderLines) line.productId: line.displayName,
  };
  final focusProduct = analysis.products
      .where((product) => product.productId == focusProductId)
      .toList(growable: false);
  if (focusProduct.length != 1) {
    throw StateError(
      'SDIF detail requires exactly one focused product input.',
    );
  }

  final pairs = analysis.productPairs
      .where(
        (pair) =>
            pair.productAId == focusProductId ||
            pair.productBId == focusProductId,
      )
      .map(
        (pair) => SdifProductPairDetailPresentation(
          productAId: pair.productAId,
          productAName: names[pair.productAId] ?? pair.productAId,
          productBId: pair.productBId,
          productBName: names[pair.productBId] ?? pair.productBId,
          identityPairs: List.unmodifiable(pair.identityPairs),
        ),
      )
      .toList(growable: false);

  return SdifInteractionDetailPresentation(
    focusProductId: focusProductId,
    focusProductName: names[focusProductId] ?? focusProductId,
    coverageStatus: focusProduct.single.coverageStatus,
    providerResolutionGaps: List.unmodifiable(
      analysis.providerResolutionGaps
          .where((gap) => gap.productIds.contains(focusProductId)),
    ),
    productPairs: List.unmodifiable(pairs),
  );
}

Future<void> showSdifInteractionDetailSheet({
  required BuildContext context,
  required SdifInteractionDetailPresentation presentation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SdifInteractionDetailSheet(
      presentation: presentation,
    ),
  );
}

class _SdifInteractionDetailSheet extends StatelessWidget {
  const _SdifInteractionDetailSheet({required this.presentation});

  final SdifInteractionDetailPresentation presentation;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: ListView(
          key: const Key('sdif-detail-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              'SDIF interaction details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              presentation.focusProductName,
              key: const Key('sdif-detail-focus-product'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _InfoNotice(
              key: const Key('sdif-detail-safety-notice'),
              text:
                  'Provider-native SDIF evidence is informational. '
                  'No provider hit is not a safety classification or a '
                  'patient-specific recommendation.',
            ),
            const SizedBox(height: 10),
            _CoverageSection(presentation: presentation),
            const SizedBox(height: 10),
            if (presentation.productPairs.isEmpty)
              const _InfoNotice(
                key: Key('sdif-detail-no-product-pairs'),
                text: 'No Cart product pair is available for this item.',
              )
            else
              for (var index = 0;
                  index < presentation.productPairs.length;
                  index++) ...[
                if (index > 0) const SizedBox(height: 10),
                _ProductPairSection(
                  index: index,
                  pair: presentation.productPairs[index],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _CoverageSection extends StatelessWidget {
  const _CoverageSection({required this.presentation});

  final SdifInteractionDetailPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final gaps = presentation.providerResolutionGaps;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coverage',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _coverageText(presentation.coverageStatus),
              key: const Key('sdif-detail-coverage'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (gaps.isNotEmpty) ...[
              const SizedBox(height: 5),
              for (var index = 0; index < gaps.length; index++)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 3),
                  child: Text(
                    '${gaps[index].identity.preferredName}: '
                    '${_gapText(gaps[index].status)}',
                    key: Key('sdif-detail-gap-$index'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductPairSection extends StatelessWidget {
  const _ProductPairSection({
    required this.index,
    required this.pair,
  });

  final int index;
  final SdifProductPairDetailPresentation pair;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('sdif-detail-product-pair-$index'),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${pair.productAName} ↔ ${pair.productBName}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            if (pair.identityPairs.isEmpty)
              const Text(
                'No eligible reviewed scientific identity pair was checked '
                'for this product pair.',
                key: Key('sdif-detail-unchecked-pair'),
              )
            else
              for (var identityIndex = 0;
                  identityIndex < pair.identityPairs.length;
                  identityIndex++) ...[
                if (identityIndex > 0) const SizedBox(height: 8),
                _IdentityPairSection(
                  productPairIndex: index,
                  identityPairIndex: identityIndex,
                  pair: pair.identityPairs[identityIndex],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _IdentityPairSection extends StatelessWidget {
  const _IdentityPairSection({
    required this.productPairIndex,
    required this.identityPairIndex,
    required this.pair,
  });

  final int productPairIndex;
  final int identityPairIndex;
  final SdifPairAssessment pair;

  @override
  Widget build(BuildContext context) {
    final identityA = pair.identityA.identity.preferredName;
    final identityB = pair.identityB.identity.preferredName;
    final keyBase = 'sdif-detail-$productPairIndex-$identityPairIndex';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$identityA ↔ $identityB',
              key: Key('$keyBase-identities'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              pair.hasObservedHits
                  ? 'Provider findings observed'
                  : 'No provider hit reported',
              key: Key('$keyBase-observation'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (!pair.hasObservedHits) ...[
              const SizedBox(height: 3),
              Text(
                'This is an observation from the current SDIF provider '
                'snapshot, not a safety classification.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            for (var findingIndex = 0;
                findingIndex < pair.findings.length;
                findingIndex++) ...[
              const SizedBox(height: 7),
              _FindingSection(
                key: Key('$keyBase-finding-$findingIndex'),
                finding: pair.findings[findingIndex],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FindingSection extends StatelessWidget {
  const _FindingSection({
    super.key,
    required this.finding,
  });

  final SdifPairFinding finding;

  @override
  Widget build(BuildContext context) {
    final hit = finding.providerHit;
    final metadata = <String>[
      _familyText(hit.family),
      'Provider severity: ${hit.severityLabel} '
          '(score ${hit.severityScore}, ${hit.severityIndicator})',
      'Source: ${hit.source}',
      finding.isDirectionalEvidence
          ? 'Direction: '
              '${finding.drugAIdentity.identity.preferredName} → '
              '${finding.drugBIdentity.identity.preferredName}'
          : 'Direction: pair-level evidence',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < metadata.length; index++) ...[
              if (index > 0) const SizedBox(height: 2),
              Text(
                metadata[index],
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (hit.keyword.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('Keyword: ${hit.keyword}'),
            ],
            if (hit.description.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(hit.description),
            ],
            if (hit.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(hit.explanation),
            ],
            if (hit.comboHint.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Combination note: ${hit.comboHint}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _coverageText(SdifScientificCoverageStatus status) {
  return switch (status) {
    SdifScientificCoverageStatus.complete =>
      'Reviewed scientific identity and ATC coverage is complete for this product.',
    SdifScientificCoverageStatus.partial =>
      'Scientific coverage is partial. Only eligible reviewed identities were checked.',
    SdifScientificCoverageStatus.unmapped =>
      'No SDIF-eligible reviewed scientific identity is currently mapped for this product.',
    SdifScientificCoverageStatus.missing =>
      'The requested catalog product could not be resolved for SDIF input.',
  };
}

String _gapText(SdifProviderResolutionGapStatus status) {
  return switch (status) {
    SdifProviderResolutionGapStatus.unmapped =>
      'not resolved by the current SDIF provider snapshot',
    SdifProviderResolutionGapStatus.ambiguous =>
      'resolved ambiguously by the current SDIF provider snapshot',
  };
}

String _familyText(SdifInteractionFamily family) {
  return switch (family) {
    SdifInteractionFamily.substance => 'Family: substance',
    SdifInteractionFamily.classLevel => 'Family: class-level',
    SdifInteractionFamily.cyp => 'Family: CYP',
    SdifInteractionFamily.epha => 'Family: EPha',
  };
}
