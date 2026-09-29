import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/whole_amount.dart';
import '../../catalog/application/scoped_catalog_refresh_controller.dart';
import '../../catalog/presentation/catalog_search_panel.dart';
import '../../catalog/presentation/catalog_text.dart';
import '../../interactions/application/ddi_cart_controller.dart';
import '../../interactions/domain/interaction_check_models.dart';
import '../../interactions/presentation/ddi_cart_presentation.dart';
import '../../scanning/presentation/android_barcode_scanner_screen.dart';
import '../application/order_controller.dart';
import '../domain/order_model.dart';

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  bool _scannerOpen = false;

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final wide = constraints.maxWidth >= 960;

        return Padding(
          key: const Key('cart-workspace'),
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            8,
            compact ? 8 : 12,
            compact ? 6 : 10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 420,
                          child: _AcquisitionPane(
                            scannerOpen: _scannerOpen,
                            onToggleScanner: Platform.isAndroid
                                ? _toggleScanner
                                : null,
                            onCloseScanner: _closeScanner,
                            maxResultsHeight: 430,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CartPane(order: order),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        CatalogSearchPanel(
                          scannerOpen: _scannerOpen,
                          onToggleScanner:
                              Platform.isAndroid ? _toggleScanner : null,
                          maxResultsHeight: compact ? 340 : 400,
                        ),
                        if (_scannerOpen && Platform.isAndroid) ...[
                          const SizedBox(height: 6),
                          AndroidBarcodeScannerPanel(
                            onClose: _closeScanner,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Expanded(
                          child: _CartPane(order: order),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  void _toggleScanner() {
    setState(() => _scannerOpen = !_scannerOpen);
  }

  void _closeScanner() {
    if (_scannerOpen) {
      setState(() => _scannerOpen = false);
    }
  }
}

class _AcquisitionPane extends StatelessWidget {
  const _AcquisitionPane({
    required this.scannerOpen,
    required this.onToggleScanner,
    required this.onCloseScanner,
    required this.maxResultsHeight,
  });

  final bool scannerOpen;
  final VoidCallback? onToggleScanner;
  final VoidCallback onCloseScanner;
  final double maxResultsHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CatalogSearchPanel(
          scannerOpen: scannerOpen,
          onToggleScanner: onToggleScanner,
          maxResultsHeight: maxResultsHeight,
        ),
        if (scannerOpen && Platform.isAndroid) ...[
          const SizedBox(height: 8),
          AndroidBarcodeScannerPanel(onClose: onCloseScanner),
        ],
      ],
    );
  }
}

class _CartPane extends ConsumerWidget {
  const _CartPane({
    required this.order,
  });

  final OrderState order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ddi = ref.watch(ddiCartControllerProvider);
    final analysis = ddi.analysis;
    final presentation =
        ddi.status == DdiCartStatus.ready && analysis != null
            ? buildDdiCartPresentation(analysis)
            : null;
    final distinctProductCount = order.lines
        .map((line) => line.productId)
        .toSet()
        .length;

    return Column(
      children: [
        _CartSummaryBar(order: order),
        if (distinctProductCount >= 2) ...[
          const SizedBox(height: 4),
          _DdiCartStatusBar(
            ddi: ddi,
            presentation: presentation,
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: _CartLines(
            order: order,
            ddi: presentation,
          ),
        ),
      ],
    );
  }
}

class _CartSummaryBar extends ConsumerWidget {
  const _CartSummaryBar({
    required this.order,
  });

  final OrderState order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemCount = order.lines.fold<int>(
      0,
      (total, line) => total + line.quantity,
    );
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return Material(
      key: const Key('cart-summary'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
              key: const Key('cart-item-count'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TotalText(
                      key: const Key('order-total-syp'),
                      amount: order.totalSyp,
                      currency: 'SYP',
                    ),
                    const SizedBox(width: 12),
                    _TotalText(
                      key: const Key('order-total-usd'),
                      amount: order.totalUsd,
                      currency: 'USD',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (narrow)
              IconButton(
                key: const Key('order-new'),
                tooltip: 'New order',
                onPressed: () => _newOrder(context, ref),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                iconSize: 19,
                icon: const Icon(Icons.restart_alt_rounded),
              )
            else
              TextButton.icon(
                key: const Key('order-new'),
                onPressed: () => _newOrder(context, ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('New order'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newOrder(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(orderControllerProvider.notifier);
    if (order.isEmpty) {
      controller.clear();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('new-order-dialog'),
        title: const Text('Start a new order?'),
        content: const Text(
          'This clears the current cart. No sale history will be created.',
        ),
        actions: [
          TextButton(
            key: const Key('new-order-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('new-order-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      controller.clear();
    }
  }
}

class _TotalText extends StatelessWidget {
  const _TotalText({
    super.key,
    required this.amount,
    required this.currency,
  });

  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${formatWholeAmount(amount)} $currency',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _CartLines extends StatelessWidget {
  const _CartLines({
    required this.order,
    this.ddi,
  });

  final OrderState order;
  final DdiCartPresentation? ddi;

  @override
  Widget build(BuildContext context) {
    if (order.isEmpty) {
      return const _EmptyCart();
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        key: const Key('order-lines'),
        padding: EdgeInsets.zero,
        itemCount: order.lines.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          indent: 10,
          endIndent: 10,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (context, index) {
          final line = order.lines[index];
          return _OrderLineRow(
            line: line,
            ddi: ddi?.rows[line.productId],
          );
        },
      ),
    );
  }
}

class _DdiCartStatusBar extends ConsumerWidget {
  const _DdiCartStatusBar({
    required this.ddi,
    required this.presentation,
  });

  final DdiCartState ddi;
  final DdiCartPresentation? presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      key: const Key('ddi-cart-status'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: switch (ddi.status) {
          DdiCartStatus.loading => const _DdiStatusMessage(
              key: Key('ddi-status-loading'),
              icon: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              message: 'Checking interactions…',
            ),
          DdiCartStatus.error => _DdiStatusMessage(
              key: const Key('ddi-status-error'),
              icon: Icon(
                Icons.cloud_off_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: _ddiFailureMessage(ddi),
              action: TextButton(
                key: const Key('ddi-retry'),
                onPressed: () => ref
                    .read(ddiCartControllerProvider.notifier)
                    .retry(),
                child: const Text('Retry'),
              ),
            ),
          DdiCartStatus.unavailable => _DdiStatusMessage(
              key: const Key('ddi-status-unavailable'),
              icon: Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: 'Interaction checking unavailable.',
            ),
          DdiCartStatus.ready => _DdiReadySummary(
              presentation: presentation,
            ),
          DdiCartStatus.idle => _DdiStatusMessage(
              key: const Key('ddi-status-idle'),
              icon: Icon(
                Icons.hourglass_empty_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              message: 'Interaction check pending.',
            ),
        },
      ),
    );
  }
}

class _DdiStatusMessage extends StatelessWidget {
  const _DdiStatusMessage({
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

class _DdiReadySummary extends StatelessWidget {
  const _DdiReadySummary({
    required this.presentation,
  });

  final DdiCartPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final resolved = presentation;
    if (resolved == null) {
      return _DdiStatusMessage(
        key: const Key('ddi-status-ready-empty'),
        icon: Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        message: 'Interaction results are not available for this Cart.',
      );
    }

    final tokens = <Widget>[];
    for (final severity in InteractionSeverity.values) {
      final count = resolved.pairCount(severity);
      if (count == 0) {
        continue;
      }
      final style = _ddiSeverityStyle(context, severity);
      tokens.add(
        _DdiSummaryToken(
          key: Key('ddi-summary-${severity.name}'),
          icon: style.icon,
          label: '$count ${_ddiSummaryLabel(severity)}',
          foreground: style.foreground,
          background: style.background,
        ),
      );
    }
    if (resolved.incompleteProductCount > 0) {
      tokens.add(
        _DdiSummaryToken(
          key: const Key('ddi-summary-incomplete'),
          icon: Icons.warning_amber_rounded,
          label:
              '${resolved.incompleteProductCount} incomplete',
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      );
    }

    if (tokens.isEmpty) {
      return _DdiStatusMessage(
        key: const Key('ddi-status-ready-no-pairs'),
        icon: Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        message: 'No interaction pair results were returned.',
      );
    }

    return Row(
      key: const Key('ddi-status-ready'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.medication_outlined,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          'DDI',
          style: Theme.of(context).textTheme.labelMedium,
        ),
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
    );
  }
}

class _DdiSummaryToken extends StatelessWidget {
  const _DdiSummaryToken({
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

class _DdiRowBadges extends StatelessWidget {
  const _DdiRowBadges({
    required this.productId,
    required this.presentation,
  });

  final String productId;
  final DdiProductRowPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    final severity = presentation.severity;
    if (severity != null) {
      final style = _ddiSeverityStyle(context, severity);
      final pairSuffix = presentation.pairCount > 1
          ? ' · ${presentation.pairCount} pairs'
          : '';
      badges.add(
        _DdiRowBadge(
          key: Key('ddi-row-severity-$productId'),
          icon: style.icon,
          label: '${_ddiRowLabel(severity)}$pairSuffix',
          foreground: style.foreground,
          background: style.badgeBackground,
        ),
      );
    }

    final coverageLabel = _ddiCoverageLabel(presentation);
    if (coverageLabel != null) {
      badges.add(
        _DdiRowBadge(
          key: Key('ddi-row-coverage-$productId'),
          icon: Icons.warning_amber_rounded,
          label: coverageLabel,
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
    }

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: badges,
    );
  }
}

class _DdiRowBadge extends StatelessWidget {
  const _DdiRowBadge({
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

class _DdiSeverityStyle {
  const _DdiSeverityStyle({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.badgeBackground,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final Color badgeBackground;
}

_DdiSeverityStyle _ddiSeverityStyle(
  BuildContext context,
  InteractionSeverity severity,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (severity) {
    InteractionSeverity.major => _DdiSeverityStyle(
        icon: Icons.error_outline_rounded,
        foreground: scheme.onErrorContainer,
        background: scheme.errorContainer.withValues(alpha: 0.62),
        badgeBackground: scheme.errorContainer,
      ),
    InteractionSeverity.moderate => _DdiSeverityStyle(
        icon: Icons.warning_amber_rounded,
        foreground: Colors.orange.shade900,
        background: Colors.orange.withValues(alpha: 0.12),
        badgeBackground: Colors.orange.withValues(alpha: 0.18),
      ),
    InteractionSeverity.minor => _DdiSeverityStyle(
        icon: Icons.info_outline_rounded,
        foreground: Colors.amber.shade900,
        background: Colors.amber.withValues(alpha: 0.14),
        badgeBackground: Colors.amber.withValues(alpha: 0.20),
      ),
    InteractionSeverity.unknown => _DdiSeverityStyle(
        icon: Icons.help_outline_rounded,
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
        badgeBackground: scheme.surfaceContainerHighest,
      ),
    InteractionSeverity.none => _DdiSeverityStyle(
        icon: Icons.remove_circle_outline_rounded,
        foreground: scheme.onSurfaceVariant,
        background: Colors.transparent,
        badgeBackground: scheme.surfaceContainerHigh,
      ),
  };
}

String _ddiRowLabel(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => 'Major',
    InteractionSeverity.moderate => 'Moderate',
    InteractionSeverity.minor => 'Minor',
    InteractionSeverity.unknown => 'Unknown',
    InteractionSeverity.none => 'No interaction found',
  };
}

String _ddiSummaryLabel(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => 'major',
    InteractionSeverity.moderate => 'moderate',
    InteractionSeverity.minor => 'minor',
    InteractionSeverity.unknown => 'unknown',
    InteractionSeverity.none => 'none',
  };
}

String? _ddiCoverageLabel(DdiProductRowPresentation presentation) {
  if (!presentation.localCoverageComplete) {
    return 'Unchecked';
  }
  if (presentation.providerUnresolved) {
    return 'Provider unresolved';
  }
  if (presentation.pairCount == 0) {
    return 'No pair result';
  }
  return null;
}

String _ddiFailureMessage(DdiCartState ddi) {
  if (ddi.failureKind == DdiCartFailureKind.rateLimited) {
    final retryAfter = ddi.retryAfter;
    if (retryAfter != null && retryAfter > Duration.zero) {
      return 'Interaction check rate-limited. Retry after '
          '${retryAfter.inSeconds}s.';
    }
    return 'Interaction check rate-limited.';
  }
  return 'Interaction check failed. Cart is unchanged.';
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        key: const Key('order-empty'),
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Cart is empty',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 3),
            Text(
              'Search for a product or scan a barcode.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderLineRow extends ConsumerWidget {
  const _OrderLineRow({
    required this.line,
    this.ddi,
  });

  final OrderLine line;
  final DdiProductRowPresentation? ddi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(orderControllerProvider.notifier);
    final pending = ref.watch(
      scopedCatalogRefreshControllerProvider.select(
        (refresh) => refresh.priceChanges[line.productId],
      ),
    );
    final latest = pending != null &&
            pending.revision > line.productRevision &&
            (pending.sellingAmount != line.unitAmount ||
                pending.currency != line.currency)
        ? pending
        : null;

    final ddiStyle = ddi?.severity == null
        ? null
        : _ddiSeverityStyle(context, ddi!.severity!);

    return DecoratedBox(
      key: Key('order-line-${line.productId}'),
      decoration: BoxDecoration(
        color: ddiStyle?.background,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CatalogText(
                  line.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${formatWholeAmount(line.lineAmount)} ${line.currency}',
                key: Key('order-line-amount-${line.productId}'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatWholeAmount(line.unitAmount)} ${line.currency} each',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              _QuantityStepper(
                productId: line.productId,
                quantity: line.quantity,
                onDecrement: line.quantity <= 1
                    ? null
                    : () => controller.decrement(line.productId),
                onIncrement: () {
                  final result = controller.increment(line.productId);
                  if (result == OrderActionResult.overflow) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Quantity is too large to calculate safely.',
                          ),
                        ),
                      );
                  }
                },
              ),
              const SizedBox(width: 2),
              IconButton(
                key: Key('order-remove-${line.productId}'),
                tooltip: 'Remove',
                onPressed: () => controller.remove(line.productId),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                iconSize: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          if (ddi != null) ...[
            const SizedBox(height: 5),
            _DdiRowBadges(
              productId: line.productId,
              presentation: ddi!,
            ),
          ],
          if (latest != null) ...[
            const SizedBox(height: 6),
            _PriceChangeNotice(
              line: line,
              latestAmount: latest.sellingAmount,
              latestCurrency: latest.currency,
              onAccept: () {
                final result = ref
                    .read(scopedCatalogRefreshControllerProvider.notifier)
                    .acceptPriceChange(line.productId);
                final message = switch (result) {
                  OrderActionResult.updated =>
                    'Cart price updated to the latest catalog value.',
                  OrderActionResult.invalidPrice =>
                    'The latest catalog price is not valid for the cart.',
                  OrderActionResult.overflow =>
                    'The latest price would make this cart too large to calculate safely.',
                  _ => 'Cart price was not changed.',
                };
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(message)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.productId,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String productId;
  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('order-decrement-$productId'),
            tooltip: 'Decrease quantity',
            onPressed: onDecrement,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(
              width: 36,
              height: 36,
            ),
            padding: EdgeInsets.zero,
            iconSize: 17,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$quantity',
              key: Key('order-quantity-$productId'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            key: Key('order-increment-$productId'),
            tooltip: 'Increase quantity',
            onPressed: onIncrement,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(
              width: 36,
              height: 36,
            ),
            padding: EdgeInsets.zero,
            iconSize: 17,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _PriceChangeNotice extends StatelessWidget {
  const _PriceChangeNotice({
    required this.line,
    required this.latestAmount,
    required this.latestCurrency,
    required this.onAccept,
  });

  final OrderLine line;
  final int latestAmount;
  final String latestCurrency;
  final VoidCallback onAccept;

  bool get canAccept {
    return latestAmount > 0 &&
        (latestCurrency == 'SYP' || latestCurrency == 'USD');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('order-price-change-${line.productId}'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
        child: Row(
          children: [
            Icon(
              canAccept
                  ? Icons.sync_rounded
                  : Icons.warning_amber_rounded,
              size: 17,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                canAccept
                    ? 'Price changed: '
                        '${formatWholeAmount(line.unitAmount)} ${line.currency} → '
                        '${formatWholeAmount(latestAmount)} $latestCurrency'
                    : 'Latest catalog price is invalid; captured price is unchanged.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
              ),
            ),
            if (canAccept)
              TextButton(
                key: Key('order-price-update-${line.productId}'),
                onPressed: onAccept,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
                child: const Text('Update'),
              ),
          ],
        ),
      ),
    );
  }
}
