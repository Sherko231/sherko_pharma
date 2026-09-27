import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/whole_amount.dart';

import '../../catalog/application/scoped_catalog_refresh_controller.dart';
import '../../catalog/presentation/catalog_search_panel.dart';
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
        final desktopSplit = constraints.maxWidth >= 900;

        return Padding(
          key: const Key('cart-workspace'),
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  _OrderHeader(
                    order: order,
                    scannerOpen: _scannerOpen,
                    onToggleScanner: Platform.isAndroid
                        ? () => setState(
                              () => _scannerOpen = !_scannerOpen,
                            )
                        : null,
                  ),
                  SizedBox(height: compact ? 6 : 8),
                  Expanded(
                    child: desktopSplit
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 410,
                                child: _AcquisitionColumn(
                                  scannerOpen: _scannerOpen,
                                  onCloseScanner: () => setState(
                                    () => _scannerOpen = false,
                                  ),
                                  maxResultsHeight: 300,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CartLines(order: order),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              CatalogSearchPanel(
                                maxResultsHeight: compact ? 180 : 240,
                              ),
                              if (_scannerOpen && Platform.isAndroid) ...[
                                const SizedBox(height: 5),
                                AndroidBarcodeScannerPanel(
                                  onClose: () => setState(
                                    () => _scannerOpen = false,
                                  ),
                                ),
                              ],
                              SizedBox(height: compact ? 5 : 8),
                              Expanded(
                                child: _CartLines(order: order),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AcquisitionColumn extends StatelessWidget {
  const _AcquisitionColumn({
    required this.scannerOpen,
    required this.onCloseScanner,
    required this.maxResultsHeight,
  });

  final bool scannerOpen;
  final VoidCallback onCloseScanner;
  final double maxResultsHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CatalogSearchPanel(maxResultsHeight: maxResultsHeight),
        if (scannerOpen && Platform.isAndroid) ...[
          const SizedBox(height: 6),
          AndroidBarcodeScannerPanel(onClose: onCloseScanner),
        ],
      ],
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
      return const _EmptyOrder();
    }

    return ListView.separated(
      key: const Key('order-lines'),
      itemCount: order.lines.length,
      separatorBuilder: (context, index) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        return _OrderLineCard(
          line: order.lines[index],
        );
      },
    );
  }
}

class _OrderHeader extends ConsumerWidget {
  const _OrderHeader({
    required this.order,
    required this.scannerOpen,
    required this.onToggleScanner,
  });

  final OrderState order;
  final bool scannerOpen;
  final VoidCallback? onToggleScanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totals = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TotalChip(
              key: const Key('order-total-syp'),
              label: 'SYP',
              amount: order.totalSyp,
            ),
            _TotalChip(
              key: const Key('order-total-usd'),
              label: 'USD',
              amount: order.totalUsd,
            ),
          ],
        );

        final compactButtonStyle = FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        );

        final scan = onToggleScanner == null
            ? null
            : FilledButton.icon(
                key: const Key('order-scan-barcode'),
                onPressed: onToggleScanner,
                style: compactButtonStyle,
                icon: Icon(
                  scannerOpen ? Icons.close : Icons.qr_code_scanner,
                  size: 18,
                ),
                label: Text(scannerOpen ? 'Hide' : 'Scan'),
              );

        final newOrder = FilledButton.tonalIcon(
          key: const Key('order-new'),
          onPressed: () => _newOrder(context, ref),
          style: compactButtonStyle,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('New order'),
        );

        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cart',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: totals,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (scan != null) ...[
                    Expanded(child: scan),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: newOrder),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                'Cart',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            totals,
            const SizedBox(width: 12),
            if (scan != null) ...[
              scan,
              const SizedBox(width: 8),
            ],
            newOrder,
          ],
        );
      },
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
          'This clears the current order. No sale history will be created.',
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
            child: const Text('Clear order'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      controller.clear();
    }
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({
    super.key,
    required this.label,
    required this.amount,
  });

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(
        '${formatWholeAmount(amount)} $label',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _EmptyOrder extends StatelessWidget {
  const _EmptyOrder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        key: Key('order-empty'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 36),
          SizedBox(height: 8),
          Text('Cart is empty'),
          SizedBox(height: 8),
          Text('Use search or Scan above to add products.'),
        ],
      ),
    );
  }
}

class _OrderLineCard extends ConsumerWidget {
  const _OrderLineCard({
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

    final compact = MediaQuery.sizeOf(context).width < 600;
    final controlConstraints = compact
        ? const BoxConstraints.tightFor(width: 34, height: 34)
        : null;

    return Card(
      key: Key('order-line-${line.productId}'),
      margin: EdgeInsets.symmetric(vertical: compact ? 1 : 2),
      child: Padding(
        padding: EdgeInsets.all(compact ? 9 : 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.displayName,
                        style: compact
                            ? Theme.of(context).textTheme.titleSmall
                            : Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: compact ? 2 : 6),
                      Text(
                        '${formatWholeAmount(line.unitAmount)} ${line.currency} each',
                        style: compact
                            ? Theme.of(context).textTheme.bodySmall
                            : null,
                      ),
                      SizedBox(height: compact ? 1 : 4),
                      Text(
                        '${formatWholeAmount(line.lineAmount)} ${line.currency}',
                        key: Key('order-line-amount-${line.productId}'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('order-decrement-${line.productId}'),
                  tooltip: 'Decrease quantity',
                  onPressed: line.quantity <= 1
                      ? null
                      : () => controller.decrement(line.productId),
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  constraints: controlConstraints,
                  iconSize: compact ? 18 : 20,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: compact ? 30 : 44,
                  child: Text(
                    '${line.quantity}',
                    key: Key('order-quantity-${line.productId}'),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  key: Key('order-increment-${line.productId}'),
                  tooltip: 'Increase quantity',
                  onPressed: () {
                    final result = controller.increment(line.productId);
                    if (result == OrderActionResult.overflow) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Quantity is too large to calculate safely.',
                          ),
                        ),
                      );
                    }
                  },
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  constraints: controlConstraints,
                  iconSize: compact ? 18 : 20,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  key: Key('order-remove-${line.productId}'),
                  tooltip: 'Remove from order',
                  onPressed: () => controller.remove(line.productId),
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  constraints: controlConstraints,
                  iconSize: compact ? 18 : 20,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 12),
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
                      'Order price updated to the latest catalog value.',
                    OrderActionResult.invalidPrice =>
                      'The latest catalog price is not valid for an order.',
                    OrderActionResult.overflow =>
                      'The latest price would make this order too large to calculate safely.',
                    _ => 'Order price was not changed.',
                  };
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            ],
          ],
        ),
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              canAccept
                  ? 'Catalog price changed from '
                      '${formatWholeAmount(line.unitAmount)} ${line.currency} to '
                      '${formatWholeAmount(latestAmount)} $latestCurrency. '
                      'Your captured order price is unchanged.'
                  : 'The latest catalog price is invalid. '
                      'Your captured ${formatWholeAmount(line.unitAmount)} ${line.currency} '
                      'price is unchanged.',
            ),
            if (canAccept)
              FilledButton.tonal(
                key: Key('order-price-update-${line.productId}'),
                onPressed: onAccept,
                child: const Text('Use latest price'),
              ),
          ],
        ),
      ),
    );
  }
}
