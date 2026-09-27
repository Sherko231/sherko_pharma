import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/whole_amount.dart';
import '../../order/application/order_controller.dart';
import '../application/catalog_detail_controller.dart';
import '../application/catalog_search_controller.dart';
import '../application/scoped_catalog_refresh_controller.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_product.dart';
import 'catalog_detail_screen.dart';
import 'catalog_product_form_screen.dart';
import 'catalog_text.dart';

class CatalogSearchPanel extends ConsumerStatefulWidget {
  const CatalogSearchPanel({
    super.key,
    this.maxResultsHeight = 220,
  });

  final double maxResultsHeight;

  @override
  ConsumerState<CatalogSearchPanel> createState() => _CatalogSearchPanelState();
}

class _CatalogSearchPanelState extends ConsumerState<CatalogSearchPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(catalogSearchControllerProvider);

    return Column(
      key: const Key('catalog-search-panel'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SearchBar(
                key: const Key('catalog-search-field'),
                controller: _searchController,
                constraints: const BoxConstraints(
                  minHeight: 42,
                  maxHeight: 42,
                ),
                hintText: 'Search name or composition',
                leading: const Icon(Icons.search, size: 19),
                trailing: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      key: const Key('catalog-search-clear'),
                      tooltip: 'Clear search',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _searchController.clear();
                        ref
                            .read(catalogSearchControllerProvider.notifier)
                            .queryChanged('');
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear, size: 18),
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
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: const Key('catalog-new-product'),
              tooltip: 'New product',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: 42,
                height: 42,
              ),
              onPressed: _openCreate,
              icon: const Icon(Icons.add, size: 19),
            ),
          ],
        ),
        if (search.refreshFailed) ...[
          const SizedBox(height: 6),
          Material(
            key: const Key('catalog-search-refresh-error'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'Refresh failed. Showing last known results.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
        if (search.isRefreshing) ...[
          const SizedBox(height: 4),
          const LinearProgressIndicator(
            key: Key('catalog-search-refreshing'),
            minHeight: 2,
          ),
        ],
        _SearchResultArea(
          search: search,
          maxHeight: widget.maxResultsHeight,
          onRetry: () {
            ref.read(catalogSearchControllerProvider.notifier).retry();
          },
          onOpenProduct: _openProduct,
          onAddToOrder: _addToOrder,
        ),
      ],
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
    await _openProduct(product);
  }

  Future<void> _openProduct(CatalogProduct product) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogDetailScreen(
          productId: product.id,
          fallbackName: product.displayName,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    ref
        .read(catalogDetailControllerProvider.notifier)
        .clear(product.id);
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
            duration: Duration(seconds: 2),
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
      OrderActionResult.added => 'Added to cart.',
      OrderActionResult.incremented => 'Quantity increased.',
      OrderActionResult.invalidPrice =>
        'Set a positive SYP or USD selling price before adding this product.',
      OrderActionResult.overflow =>
        'This cart amount is too large to calculate safely.',
      _ => 'Cart was not changed.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: Text(message),
        ),
      );
  }
}

class _SearchResultArea extends StatelessWidget {
  const _SearchResultArea({
    required this.search,
    required this.maxHeight,
    required this.onRetry,
    required this.onOpenProduct,
    required this.onAddToOrder,
  });

  final CatalogSearchState search;
  final double maxHeight;
  final VoidCallback onRetry;
  final ValueChanged<CatalogProduct> onOpenProduct;
  final ValueChanged<CatalogProduct> onAddToOrder;

  @override
  Widget build(BuildContext context) {
    switch (search.status) {
      case CatalogSearchStatus.idle:
        return const SizedBox.shrink();
      case CatalogSearchStatus.loading:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(
            key: Key('catalog-search-loading'),
            minHeight: 2,
          ),
        );
      case CatalogSearchStatus.empty:
        return const _CompactMessage(
          key: Key('catalog-search-empty'),
          icon: Icons.search_off,
          text: 'No products found',
        );
      case CatalogSearchStatus.error:
        return _CompactMessage(
          key: const Key('catalog-search-error'),
          icon: Icons.cloud_off,
          text: 'Could not load the catalog',
          action: TextButton(
            key: const Key('catalog-search-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        );
      case CatalogSearchStatus.results:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.separated(
              key: const Key('catalog-search-results'),
              shrinkWrap: true,
              primary: false,
              itemCount: search.products.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final product = search.products[index];
                return _CompactProductResult(
                  product: product,
                  onTap: () => onOpenProduct(product),
                  onAdd: () => onAddToOrder(product),
                );
              },
            ),
          ),
        );
    }
  }
}

class _CompactProductResult extends StatelessWidget {
  const _CompactProductResult({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });

  final CatalogProduct product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (product.composition?.trim().isNotEmpty ?? false)
        product.composition!.trim(),
      if (product.manufacturer?.trim().isNotEmpty ?? false)
        product.manufacturer!.trim(),
      if (product.strength?.trim().isNotEmpty ?? false)
        product.strength!.trim(),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('catalog-result-${product.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CatalogText(
                      product.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (product.nameEn != null &&
                        product.nameAr != null &&
                        product.nameAr!.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      CatalogText(
                        product.nameAr!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      CatalogText(
                        details.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatWholeAmount(product.sellingAmount)} ${product.currency}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  IconButton.filledTonal(
                    key: Key('catalog-add-to-order-${product.id}'),
                    tooltip: 'Add to cart',
                    onPressed: onAdd,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 38,
                      height: 34,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 17,
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

class _CompactMessage extends StatelessWidget {
  const _CompactMessage({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      ),
    );
  }
}
