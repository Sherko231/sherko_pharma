import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/whole_amount.dart';
import '../../catalog/application/scoped_catalog_refresh_controller.dart';
import '../../catalog/presentation/catalog_search_panel.dart';
import '../../catalog/presentation/catalog_text.dart';
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

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.order,
  });

  final OrderState order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CartSummaryBar(order: order),
        const SizedBox(height: 4),
        Expanded(
          child: _CartLines(order: order),
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
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatWholeAmount(amount),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          TextSpan(
            text: ' $currency',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _CartLines extends StatelessWidget {
  const _CartLines({
    required this.order,
  });

  final OrderState order;

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
          return _OrderLineRow(line: order.lines[index]);
        },
      ),
    );
  }
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
  });

  final OrderLine line;

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

    return Padding(
      key: Key('order-line-${line.productId}'),
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
                  width: 36,
                  height: 36,
                ),
                iconSize: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
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
        ],
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
              width: 34,
              height: 32,
            ),
            padding: EdgeInsets.zero,
            iconSize: 17,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 28,
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
              width: 34,
              height: 32,
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
