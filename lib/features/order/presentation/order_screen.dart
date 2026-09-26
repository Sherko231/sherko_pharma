import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/application/scoped_catalog_refresh_controller.dart';
import '../application/order_controller.dart';
import '../domain/order_model.dart';

class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderControllerProvider);

    return Padding(
      key: const Key('order-workspace'),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              _OrderHeader(order: order),
              const SizedBox(height: 16),
              Expanded(
                child: order.isEmpty
                    ? const _EmptyOrder()
                    : ListView.separated(
                        key: const Key('order-lines'),
                        itemCount: order.lines.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _OrderLineCard(
                            line: order.lines[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderHeader extends ConsumerWidget {
  const _OrderHeader({
    required this.order,
  });

  final OrderState order;

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

        final newOrder = FilledButton.tonalIcon(
          key: const Key('order-new'),
          onPressed: () => _newOrder(context, ref),
          icon: const Icon(Icons.restart_alt),
          label: const Text('New Order'),
        );

        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Customer order',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              totals,
              const SizedBox(height: 12),
              newOrder,
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                'Customer order',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            totals,
            const SizedBox(width: 12),
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
      label: Text('$amount $label'),
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
          Icon(Icons.shopping_basket_outlined, size: 48),
          SizedBox(height: 16),
          Text('Order is empty'),
          SizedBox(height: 8),
          Text('Add products from Catalog search results.'),
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
    final latest = ref.watch(
      scopedCatalogRefreshControllerProvider.select(
        (refresh) => refresh.priceChanges[line.productId],
      ),
    );

    return Card(
      key: Key('order-line-${line.productId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('${line.unitAmount} ${line.currency} each'),
                      const SizedBox(height: 4),
                      Text(
                        '${line.lineAmount} ${line.currency}',
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
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 44,
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
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  key: Key('order-remove-${line.productId}'),
                  tooltip: 'Remove from order',
                  onPressed: () => controller.remove(line.productId),
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
        padding: const EdgeInsets.all(12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              canAccept
                  ? 'Catalog price changed from '
                      '${line.unitAmount} ${line.currency} to '
                      '$latestAmount $latestCurrency. '
                      'Your captured order price is unchanged.'
                  : 'The latest catalog price is invalid. '
                      'Your captured ${line.unitAmount} ${line.currency} '
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
