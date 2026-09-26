import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/catalog_search_controller.dart';
import '../application/scoped_catalog_refresh_controller.dart';
import '../../order/application/order_controller.dart';
import '../domain/catalog_product.dart';
import 'catalog_detail_screen.dart';
import 'catalog_product_form_screen.dart';
import 'catalog_text.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(catalogSearchControllerProvider);

    return Padding(
      key: const Key('catalog-workspace'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
              key: const Key('catalog-search-field'),
              controller: _searchController,
              hintText: 'Search name or composition',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    key: const Key('catalog-search-clear'),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      ref
                          .read(catalogSearchControllerProvider.notifier)
                          .queryChanged('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
              ],
              onChanged: (query) {
                ref
                    .read(catalogSearchControllerProvider.notifier)
                    .queryChanged(query);
                setState(() {});
              },
                    onSubmitted: (query) {
                      ref
                          .read(catalogSearchControllerProvider.notifier)
                          .submit(query);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  key: const Key('catalog-new-product'),
                  tooltip: 'New product',
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (search.refreshFailed) ...[
            Material(
              key: const Key('catalog-search-refresh-error'),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Refresh failed. Showing the last known search results.',
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (search.isRefreshing) ...[
            const LinearProgressIndicator(
              key: Key('catalog-search-refreshing'),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: _CatalogSearchBody(
                search: search,
                onRetry: () {
                  ref
                      .read(catalogSearchControllerProvider.notifier)
                      .retry();
                },
                onOpenProduct: _openProduct,
                onAddToOrder: _addToOrder,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreate() async {
    final product = await Navigator.of(context).push<CatalogProduct>(
      MaterialPageRoute<CatalogProduct>(
        builder: (_) => const CatalogProductFormScreen.create(),
      ),
    );

    if (!mounted || product == null) {
      return;
    }

    unawaited(
      ref.read(catalogSearchControllerProvider.notifier).refresh(),
    );
    _openProduct(product);
  }

  void _openProduct(CatalogProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogDetailScreen(
          productId: product.id,
          fallbackName: product.displayName,
        ),
      ),
    );
  }

  Future<void> _addToOrder(CatalogProduct product) async {
    CatalogProduct latest;
    try {
      latest = await ref.read(catalogRepositoryProvider).getById(product.id);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not refresh this product before adding it. Check the connection and try again.',
            ),
          ),
        );
      return;
    }

    if (!mounted) {
      return;
    }

    final result = ref.read(orderControllerProvider.notifier).addProduct(latest);
    ref
        .read(scopedCatalogRefreshControllerProvider.notifier)
        .reconcileCurrentProduct(latest);
    final message = switch (result) {
      OrderActionResult.added => 'Added to order.',
      OrderActionResult.incremented => 'Quantity increased in the order.',
      OrderActionResult.invalidPrice =>
        'Set a positive SYP or USD selling price before adding this product.',
      OrderActionResult.overflow =>
        'This order amount is too large to calculate safely.',
      _ => 'Order was not changed.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }
}

class _CatalogSearchBody extends StatelessWidget {
  const _CatalogSearchBody({
    required this.search,
    required this.onRetry,
    required this.onOpenProduct,
    required this.onAddToOrder,
  });

  final CatalogSearchState search;
  final VoidCallback onRetry;
  final ValueChanged<CatalogProduct> onOpenProduct;
  final ValueChanged<CatalogProduct> onAddToOrder;

  @override
  Widget build(BuildContext context) {
    return switch (search.status) {
      CatalogSearchStatus.idle => const _CenteredMessage(
          key: Key('catalog-search-idle'),
          icon: Icons.manage_search,
          title: 'Search the catalog',
          message:
              'Enter an Arabic or English product name, or a composition.',
        ),
      CatalogSearchStatus.loading => const Center(
          key: Key('catalog-search-loading'),
          child: CircularProgressIndicator(),
        ),
      CatalogSearchStatus.empty => const _CenteredMessage(
          key: Key('catalog-search-empty'),
          icon: Icons.search_off,
          title: 'No products found',
          message: 'Try a different name or composition.',
        ),
      CatalogSearchStatus.error => _CenteredMessage(
          key: const Key('catalog-search-error'),
          icon: Icons.cloud_off,
          title: 'Could not load the catalog',
          message: 'Check your connection and try again.',
          action: FilledButton.tonal(
            key: const Key('catalog-search-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      CatalogSearchStatus.results => ListView.separated(
          key: const Key('catalog-search-results'),
          itemCount: search.products.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final product = search.products[index];
            return _ProductResultCard(
              product: product,
              onTap: () => onOpenProduct(product),
              onAddToOrder: () => onAddToOrder(product),
            );
          },
        ),
    };
  }
}

class _ProductResultCard extends StatelessWidget {
  const _ProductResultCard({
    required this.product,
    required this.onTap,
    required this.onAddToOrder,
  });

  final CatalogProduct product;
  final VoidCallback onTap;
  final VoidCallback onAddToOrder;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (product.composition?.trim().isNotEmpty ?? false)
        product.composition!.trim(),
      if (product.manufacturer?.trim().isNotEmpty ?? false)
        product.manufacturer!.trim(),
      if (product.strength?.trim().isNotEmpty ?? false)
        product.strength!.trim(),
    ];

    return Card(
      child: InkWell(
        key: Key('catalog-result-${product.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CatalogText(
                      product.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (product.nameEn != null &&
                        product.nameAr != null &&
                        product.nameAr!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      CatalogText(
                        product.nameAr!.trim(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      CatalogText(
                        subtitleParts.join(' • '),
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${product.sellingAmount} ${product.currency}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  IconButton.filledTonal(
                    key: Key('catalog-add-to-order-${product.id}'),
                    tooltip: 'Add to order',
                    onPressed: onAddToOrder,
                    icon: const Icon(Icons.add_shopping_cart),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
