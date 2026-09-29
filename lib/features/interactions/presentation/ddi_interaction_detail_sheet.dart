import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../order/domain/order_model.dart';
import '../domain/ddi_analysis_models.dart';
import '../domain/interaction_check_models.dart';

abstract interface class DdiExternalLinkLauncher {
  Future<bool> open(Uri uri);
}

class UrlLauncherDdiExternalLinkLauncher
    implements DdiExternalLinkLauncher {
  const UrlLauncherDdiExternalLinkLauncher();

  @override
  Future<bool> open(Uri uri) {
    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}

final ddiExternalLinkLauncherProvider =
    Provider<DdiExternalLinkLauncher>(
  (ref) => const UrlLauncherDdiExternalLinkLauncher(),
);

class DdiInteractionDetailPresentation {
  const DdiInteractionDetailPresentation({
    required this.focusProductId,
    required this.focusProductName,
    required this.pairs,
    required this.notices,
  });

  final String focusProductId;
  final String focusProductName;
  final List<DdiDetailProductPair> pairs;
  final List<DdiProviderNotice> notices;
}

class DdiDetailProductPair {
  const DdiDetailProductPair({
    required this.productAId,
    required this.productAName,
    required this.productBId,
    required this.productBName,
    required this.severity,
    required this.ingredientInteractions,
  });

  final String productAId;
  final String productAName;
  final String productBId;
  final String productBName;
  final InteractionSeverity severity;
  final List<DdiIngredientInteraction> ingredientInteractions;
}

DdiInteractionDetailPresentation
    buildDdiInteractionDetailPresentation({
  required DdiAnalysisResult analysis,
  required List<OrderLine> orderLines,
  required String focusProductId,
}) {
  final names = <String, String>{
    for (final line in orderLines)
      line.productId: line.displayName,
  };

  final pairs = analysis.productPairs
      .where(
        (pair) =>
            pair.productAId == focusProductId ||
            pair.productBId == focusProductId,
      )
      .map(
        (pair) => DdiDetailProductPair(
          productAId: pair.productAId,
          productAName:
              names[pair.productAId] ?? pair.productAId,
          productBId: pair.productBId,
          productBName:
              names[pair.productBId] ?? pair.productBId,
          severity: pair.severity,
          ingredientInteractions:
              List.unmodifiable(pair.ingredientInteractions),
        ),
      )
      .toList(growable: false)
    ..sort(
      (left, right) =>
          ddiSeverityRank(right.severity)
              .compareTo(ddiSeverityRank(left.severity)),
    );

  return DdiInteractionDetailPresentation(
    focusProductId: focusProductId,
    focusProductName: names[focusProductId] ?? focusProductId,
    pairs: List.unmodifiable(pairs),
    notices: List.unmodifiable(_deduplicateNotices(
      analysis.providerNotices,
    )),
  );
}

List<DdiProviderNotice> _deduplicateNotices(
  List<DdiProviderNotice> notices,
) {
  final seen = <String>{};
  final result = <DdiProviderNotice>[];

  for (final notice in notices) {
    final key = [
      notice.data.labelExportDate?.toIso8601String() ?? '',
      notice.data.generatedAt?.toIso8601String() ?? '',
      notice.disclaimer,
      notice.attribution.text ?? '',
      notice.attribution.url?.toString() ?? '',
      notice.attribution.license ?? '',
    ].join('|');
    if (seen.add(key)) {
      result.add(notice);
    }
  }

  return result;
}

Future<void> showDdiInteractionDetailSheet({
  required BuildContext context,
  required DdiInteractionDetailPresentation presentation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _DdiInteractionDetailSheet(
      presentation: presentation,
    ),
  );
}

class _DdiInteractionDetailSheet extends ConsumerWidget {
  const _DdiInteractionDetailSheet({
    required this.presentation,
  });

  final DdiInteractionDetailPresentation presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.86;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          key: const Key('ddi-detail-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drug interaction details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('ddi-detail-close'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  Text(
                    presentation.focusProductName,
                    key: const Key('ddi-detail-focus-product'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Informational label-derived evidence only. '
                    'This does not account for patient-specific factors.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (presentation.pairs.isEmpty)
                    _NeutralPanel(
                      key: const Key('ddi-detail-no-pairs'),
                      icon: Icons.info_outline_rounded,
                      text:
                          'No current product-pair interaction details are available.',
                    )
                  else
                    for (var index = 0;
                        index < presentation.pairs.length;
                        index++) ...[
                      if (index > 0) const SizedBox(height: 10),
                      _ProductPairSection(
                        pair: presentation.pairs[index],
                      ),
                    ],
                  if (presentation.notices.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 8),
                    for (var index = 0;
                        index < presentation.notices.length;
                        index++) ...[
                      if (index > 0) const SizedBox(height: 10),
                      _ProviderNoticeSection(
                        notice: presentation.notices[index],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPairSection extends ConsumerWidget {
  const _ProductPairSection({
    required this.pair,
  });

  final DdiDetailProductPair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = _detailSeverityStyle(context, pair.severity);

    return Material(
      key: Key(
        'ddi-detail-pair-${pair.productAId}-${pair.productBId}',
      ),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${pair.productAName} ↔ ${pair.productBName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                _DetailSeverityBadge(
                  severity: pair.severity,
                  foreground: style.foreground,
                  background: style.background,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pair.ingredientInteractions.isEmpty)
              _NeutralPanel(
                key: Key(
                  'ddi-detail-pair-empty-${pair.productAId}-${pair.productBId}',
                ),
                icon: pair.severity == InteractionSeverity.unknown
                    ? Icons.help_outline_rounded
                    : Icons.remove_circle_outline_rounded,
                text: pair.severity == InteractionSeverity.unknown
                    ? 'No label evidence was returned for this product pair.'
                    : pair.severity == InteractionSeverity.none
                        ? 'The provider returned no clinically significant interaction for this pair.'
                        : 'No ingredient-level evidence was returned for this pair.',
              )
            else
              for (var index = 0;
                  index < pair.ingredientInteractions.length;
                  index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _IngredientInteractionSection(
                  interaction: pair.ingredientInteractions[index],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _IngredientInteractionSection extends ConsumerWidget {
  const _IngredientInteractionSection({
    required this.interaction,
  });

  final DdiIngredientInteraction interaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severity = interaction.severity;
    final style = _detailSeverityStyle(context, severity);
    final link = interaction.detailPage ?? interaction.interactionUrl;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  '${interaction.ingredientA.name} ↔ '
                  '${interaction.ingredientB.name}',
                  key: Key(
                    'ddi-detail-ingredient-'
                    '${interaction.ingredientA.id}-'
                    '${interaction.ingredientB.id}',
                  ),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                _DetailSeverityBadge(
                  severity: severity,
                  label: interaction.severityLabel.trim().isEmpty
                      ? null
                      : interaction.severityLabel,
                  foreground: style.foreground,
                  background: style.background,
                ),
              ],
            ),
            const SizedBox(height: 7),
            if (interaction.evidence.isEmpty)
              _NeutralPanel(
                key: Key(
                  'ddi-detail-no-evidence-'
                  '${interaction.ingredientA.id}-'
                  '${interaction.ingredientB.id}',
                ),
                icon: severity == InteractionSeverity.unknown
                    ? Icons.help_outline_rounded
                    : Icons.info_outline_rounded,
                text: severity == InteractionSeverity.unknown
                    ? 'No label evidence was returned for this ingredient pair.'
                    : severity == InteractionSeverity.none
                        ? 'No clinically significant interaction was reported by the provider for this ingredient pair.'
                        : 'No evidence text was returned for this ingredient pair.',
              )
            else
              for (var index = 0;
                  index < interaction.evidence.length;
                  index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _EvidenceEntry(
                  evidence: interaction.evidence[index],
                ),
              ],
            if (_isHttpUri(link)) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key(
                    'ddi-detail-interaction-link-'
                    '${interaction.ingredientA.id}-'
                    '${interaction.ingredientB.id}',
                  ),
                  onPressed: () => _openLink(
                    context,
                    ref,
                    link,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Interaction Checker page'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceEntry extends ConsumerWidget {
  const _EvidenceEntry({
    required this.evidence,
  });

  final InteractionEvidence evidence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = evidence.source;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              evidence.sectionLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            SelectableText(
              evidence.quote,
              key: Key(
                'ddi-detail-evidence-'
                '${evidence.from}-${evidence.about}-'
                '${evidence.matchedTerm}',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Matched: ${evidence.matchedTerm} · '
              '${_matchKindLabel(evidence.matchKind)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              source.name,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              [
                _sourceTypeLabel(source.type),
                if (source.effectiveDate != null)
                  'Effective ${_formatDate(source.effectiveDate!)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (_isHttpUri(source.url)) ...[
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key(
                    'ddi-detail-source-link-'
                    '${evidence.from}-${evidence.about}-'
                    '${evidence.matchedTerm}',
                  ),
                  onPressed: () => _openLink(
                    context,
                    ref,
                    source.url,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open source'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderNoticeSection extends ConsumerWidget {
  const _ProviderNoticeSection({
    required this.notice,
  });

  final DdiProviderNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attribution = notice.attribution;
    final attributionText =
        attribution.text?.trim().isNotEmpty == true
            ? attribution.text!.trim()
            : 'Interaction Checker';
    final providerUrl = attribution.url;

    return Material(
      key: const Key('ddi-detail-provider-notice'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Provider notice',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 5),
            Text(
              notice.disclaimer,
              key: const Key('ddi-detail-disclaimer'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              attributionText,
              key: const Key('ddi-detail-attribution'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (attribution.license?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                attribution.license!.trim(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (notice.data.labelExportDate != null ||
                notice.data.generatedAt != null) ...[
              const SizedBox(height: 5),
              Text(
                [
                  if (notice.data.labelExportDate != null)
                    'Label export ${_formatDate(notice.data.labelExportDate!)}',
                  if (notice.data.generatedAt != null)
                    'Generated ${_formatDate(notice.data.generatedAt!)}',
                ].join(' · '),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (providerUrl != null && _isHttpUri(providerUrl)) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('ddi-detail-provider-link'),
                  onPressed: () => _openLink(
                    context,
                    ref,
                    providerUrl,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Interaction Checker'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NeutralPanel extends StatelessWidget {
  const _NeutralPanel({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
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
              icon,
              size: 17,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSeverityStyle {
  const _DetailSeverityStyle({
    required this.foreground,
    required this.background,
  });

  final Color foreground;
  final Color background;
}

_DetailSeverityStyle _detailSeverityStyle(
  BuildContext context,
  InteractionSeverity severity,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (severity) {
    InteractionSeverity.major => _DetailSeverityStyle(
        foreground: scheme.onErrorContainer,
        background: scheme.errorContainer,
      ),
    InteractionSeverity.moderate => _DetailSeverityStyle(
        foreground: Colors.orange.shade900,
        background: Colors.orange.withValues(alpha: 0.18),
      ),
    InteractionSeverity.minor => _DetailSeverityStyle(
        foreground: Colors.amber.shade900,
        background: Colors.amber.withValues(alpha: 0.20),
      ),
    InteractionSeverity.unknown => _DetailSeverityStyle(
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest,
      ),
    InteractionSeverity.none => _DetailSeverityStyle(
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
      ),
  };
}

class _DetailSeverityBadge extends StatelessWidget {
  const _DetailSeverityBadge({
    required this.severity,
    required this.foreground,
    required this.background,
    this.label,
  });

  final InteractionSeverity severity;
  final Color foreground;
  final Color background;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _severityIcon(severity),
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 3),
            Text(
              label ?? _severityLabel(severity),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _severityIcon(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => Icons.error_outline_rounded,
    InteractionSeverity.moderate => Icons.warning_amber_rounded,
    InteractionSeverity.minor => Icons.info_outline_rounded,
    InteractionSeverity.unknown => Icons.help_outline_rounded,
    InteractionSeverity.none => Icons.remove_circle_outline_rounded,
  };
}

String _severityLabel(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => 'Major',
    InteractionSeverity.moderate => 'Moderate',
    InteractionSeverity.minor => 'Minor',
    InteractionSeverity.unknown => 'Unknown',
    InteractionSeverity.none => 'No interaction found',
  };
}

String _sourceTypeLabel(InteractionSourceType type) {
  return switch (type) {
    InteractionSourceType.fdaLabel => 'FDA label',
    InteractionSourceType.curated => 'Curated source',
  };
}

String _matchKindLabel(InteractionMatchKind kind) {
  return switch (kind) {
    InteractionMatchKind.name => 'name match',
    InteractionMatchKind.classMatch => 'class match',
    InteractionMatchKind.overlay => 'curated overlay',
  };
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

bool _isHttpUri(Uri uri) {
  return uri.scheme == 'https' || uri.scheme == 'http';
}

Future<void> _openLink(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  if (!_isHttpUri(uri)) {
    _showLinkFailure(context);
    return;
  }

  var opened = false;
  try {
    opened = await ref.read(ddiExternalLinkLauncherProvider).open(uri);
  } catch (_) {
    opened = false;
  }

  if (!opened && context.mounted) {
    _showLinkFailure(context);
  }
}

void _showLinkFailure(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Could not open this source link.'),
      ),
    );
}
