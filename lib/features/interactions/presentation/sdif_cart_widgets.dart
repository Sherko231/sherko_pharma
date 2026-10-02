import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../order/domain/order_model.dart';
import '../application/sdif_cart_controller.dart';
import '../domain/sdif_product_scientific_models.dart';
import 'sdif_cart_presentation.dart';
import 'sdif_interaction_detail_sheet.dart';

class SdifCartStatusSurface extends ConsumerWidget {
  const SdifCartStatusSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sdifCartControllerProvider);
    final presentation = state.status == SdifCartStatus.ready &&
            state.analysis != null
        ? buildSdifCartPresentation(state.analysis!)
        : null;

    return Material(
      key: const Key('sdif-cart-status'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: switch (state.status) {
          SdifCartStatus.loading => const _SdifStatusMessage(
              key: Key('sdif-status-loading'),
              icon: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              message: 'Checking interactions with SDIF…',
            ),
          SdifCartStatus.error => _SdifStatusMessage(
              key: const Key('sdif-status-error'),
              icon: Icon(
                Icons.cloud_off_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: _failureMessage(state.failureKind),
              action: TextButton(
                key: const Key('sdif-retry'),
                onPressed: () => ref
                    .read(sdifCartControllerProvider.notifier)
                    .retry(),
                child: const Text('Retry'),
              ),
            ),
          SdifCartStatus.unavailable => _SdifStatusMessage(
              key: const Key('sdif-status-unavailable'),
              icon: Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: 'SDIF interaction checking unavailable.',
            ),
          SdifCartStatus.ready => _SdifReadySummary(
              presentation: presentation,
            ),
          SdifCartStatus.idle => _SdifStatusMessage(
              key: const Key('sdif-status-idle'),
              icon: Icon(
                Icons.hourglass_empty_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: 'SDIF interaction check pending.',
            ),
        },
      ),
    );
  }
}

class SdifProductRowSection extends ConsumerWidget {
  const SdifProductRowSection({
    super.key,
    required this.productId,
    required this.orderLines,
  });

  final String productId;
  final List<OrderLine> orderLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sdifCartControllerProvider);
    final analysis = state.analysis;
    if (state.status != SdifCartStatus.ready || analysis == null) {
      return const SizedBox.shrink();
    }

    final presentation = buildSdifCartPresentation(analysis);
    final row = presentation.rows[productId];
    if (row == null) {
      return const SizedBox.shrink();
    }

    final badges = <Widget>[];
    final canOpenDetails = row.relatedProductPairCount > 0;
    VoidCallback? onOpenDetails;
    if (canOpenDetails) {
      onOpenDetails = () {
        final detail = buildSdifInteractionDetailPresentation(
          analysis: analysis,
          orderLines: orderLines,
          focusProductId: productId,
        );
        showSdifInteractionDetailSheet(
          context: context,
          presentation: detail,
        );
      };
    }

    if (row.hasProviderFindings) {
      badges.add(
        _SdifRowBadge(
          key: Key('sdif-row-findings-$productId'),
          icon: Icons.science_outlined,
          label:
              'SDIF findings · ${_pairText(row.findingProductPairCount)}',
          foreground: Theme.of(context).colorScheme.onTertiaryContainer,
          background: Theme.of(context).colorScheme.tertiaryContainer,
          onTap: onOpenDetails,
        ),
      );
    } else if (row.hasProviderCheckedPairs) {
      badges.add(
        _SdifRowBadge(
          key: Key('sdif-row-no-hit-$productId'),
          icon: Icons.info_outline_rounded,
          label:
              'No provider hit · ${_pairText(row.noProviderHitProductPairCount)}',
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHigh,
          onTap: onOpenDetails,
        ),
      );
    }

    final coverage = _coverageLabel(row.coverageStatus);
    if (coverage != null) {
      badges.add(
        _SdifRowBadge(
          key: Key('sdif-row-coverage-$productId'),
          icon: Icons.warning_amber_rounded,
          label: coverage,
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
          onTap: onOpenDetails,
        ),
      );
    }

    if (row.providerResolutionIncomplete) {
      badges.add(
        _SdifRowBadge(
          key: Key('sdif-row-provider-gap-$productId'),
          icon: Icons.link_off_rounded,
          label: 'SDIF mapping incomplete',
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
          onTap: onOpenDetails,
        ),
      );
    }

    if (row.uncheckedProductPairCount > 0) {
      badges.add(
        _SdifRowBadge(
          key: Key('sdif-row-unchecked-$productId'),
          icon: Icons.help_outline_rounded,
          label: 'Unchecked pairs · ${row.uncheckedProductPairCount}',
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
          onTap: onOpenDetails,
        ),
      );
    }

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: badges,
      ),
    );
  }
}

class _SdifReadySummary extends StatelessWidget {
  const _SdifReadySummary({required this.presentation});

  final SdifCartPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final resolved = presentation;
    if (resolved == null) {
      return _SdifStatusMessage(
        key: const Key('sdif-status-ready-empty'),
        icon: Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        message: 'SDIF results are not available for this Cart.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final tokens = <Widget>[];
    if (resolved.productPairsWithFindings > 0) {
      tokens.add(
        _SdifSummaryToken(
          key: const Key('sdif-summary-findings'),
          icon: Icons.science_outlined,
          label: '${resolved.productPairsWithFindings} findings',
          foreground: scheme.onTertiaryContainer,
          background: scheme.tertiaryContainer,
        ),
      );
    }
    if (resolved.productPairsWithNoProviderHit > 0) {
      tokens.add(
        _SdifSummaryToken(
          key: const Key('sdif-summary-no-hit'),
          icon: Icons.info_outline_rounded,
          label:
              '${resolved.productPairsWithNoProviderHit} no provider hit',
          foreground: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHigh,
        ),
      );
    }
    if (resolved.uncheckedProductPairCount > 0) {
      tokens.add(
        _SdifSummaryToken(
          key: const Key('sdif-summary-unchecked'),
          icon: Icons.help_outline_rounded,
          label: '${resolved.uncheckedProductPairCount} unchecked',
          foreground: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHigh,
        ),
      );
    }
    if (resolved.incompleteProductCount > 0) {
      tokens.add(
        _SdifSummaryToken(
          key: const Key('sdif-summary-incomplete'),
          icon: Icons.warning_amber_rounded,
          label: '${resolved.incompleteProductCount} incomplete',
          foreground: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHigh,
        ),
      );
    }

    return Column(
      key: const Key('sdif-status-ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.biotech_outlined,
              size: 17,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text('SDIF', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < tokens.length; index++) ...[
                      if (index > 0) const SizedBox(width: 5),
                      tokens[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'No provider hit is not a safety classification.',
          key: const Key('sdif-no-hit-disclaimer'),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SdifStatusMessage extends StatelessWidget {
  const _SdifStatusMessage({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final Widget icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 6),
          action!,
        ],
      ],
    );
  }
}

class _SdifSummaryToken extends StatelessWidget {
  const _SdifSummaryToken({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

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
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 3),
            Text(
              label,
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

class _SdifRowBadge extends StatelessWidget {
  const _SdifRowBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right_rounded, size: 14, color: foreground),
          ],
        ],
      ),
    );

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(7),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(7),
              child: content,
            ),
    );
  }
}

String? _coverageLabel(SdifScientificCoverageStatus status) {
  return switch (status) {
    SdifScientificCoverageStatus.complete => null,
    SdifScientificCoverageStatus.partial => 'Partial scientific coverage',
    SdifScientificCoverageStatus.unmapped => 'Scientific identity unmapped',
    SdifScientificCoverageStatus.missing => 'Product mapping missing',
  };
}

String _pairText(int count) => '$count ${count == 1 ? 'pair' : 'pairs'}';

String _failureMessage(SdifCartFailureKind? failure) {
  return switch (failure) {
    SdifCartFailureKind.scientificInput =>
      'Scientific input check failed. Cart is unchanged.',
    SdifCartFailureKind.timeout =>
      'SDIF interaction check timed out. Cart is unchanged.',
    SdifCartFailureKind.transport =>
      'SDIF is unavailable. Cart is unchanged.',
    SdifCartFailureKind.provider =>
      'SDIF provider request failed. Cart is unchanged.',
    SdifCartFailureKind.malformedResponse =>
      'SDIF returned an unreadable response. Cart is unchanged.',
    SdifCartFailureKind.mapping =>
      'SDIF result could not be verified. Cart is unchanged.',
    SdifCartFailureKind.unknown =>
      'SDIF interaction check failed. Cart is unchanged.',
    null => 'SDIF interaction check failed. Cart is unchanged.',
  };
}
