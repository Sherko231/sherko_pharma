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
    this.maxResultsHeight = 280,
    this.scannerOpen = false,
    this.onToggleScanner,
  });

  final double maxResultsHeight;
  final bool scannerOpen;
  final VoidCallback? onToggleScanner;

  @override
  ConsumerState<CatalogSearchPanel> createState() => _CatalogSearchPanelState();
}

class _CatalogSearchPanelState extends ConsumerState<CatalogSearchPanel> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _overlayController = OverlayPortalController(
    debugLabel: 'catalog-search-results',
  );
  final _layerLink = LayerLink();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(catalogSearchControllerProvider);
    _scheduleOverlaySync(search);

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayWidth = constraints.maxWidth;

        return OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (overlayContext) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _dismissResults,
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 6),
                  child: Material(
                    key: const Key('catalog-search-overlay'),
                    elevation: 8,
                    shadowColor: Colors.black26,
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: overlayWidth,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: widget.maxResultsHeight,
                        ),
                        child: _SearchResultSurface(
                          search: search,
                          onRetry: () {
                            ref
                                .read(catalogSearchControllerProvider.notifier)
                                .retry();
                          },
                          onOpenProduct: _openProduct,
                          onAddToCart: _addToCart,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: CompositedTransformTarget(
            link: _layerLink,
            child: Row(
              key: const Key('catalog-search-panel'),
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('catalog-search-field'),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search products',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('catalog-search-clear'),
                              tooltip: 'Clear search',
                              visualDensity: VisualDensity.compact,
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                    ),
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
                if (widget.onToggleScanner != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: const Key('order-scan-barcode'),
                    tooltip:
                        widget.scannerOpen ? 'Close scanner' : 'Scan barcode',
                    onPressed: widget.onToggleScanner,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: Icon(
                      widget.scannerOpen
                          ? Icons.close
                          : Icons.qr_code_scanner_rounded,
                      size: 20,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  key: const Key('catalog-new-product'),
                  tooltip: 'New product',
                  onPressed: _openCreate,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 21),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleOverlaySync(CatalogSearchState search) {
    final shouldShow = _searchController.text.trim().isNotEmpty &&
        search.status != CatalogSearchStatus.idle;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (shouldShow && !_overlayController.isShowing) {
        _overlayController.show();
      } else if (!shouldShow && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  void _dismissResults() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    _searchFocusNode.unfocus();
  }

  void _clearSearch({bool keepFocus = true}) {
    _searchController.clear();
    ref.read(catalogSearchControllerProvider.notifier).queryChanged('');
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    if (keepFocus) {
      _searchFocusNode.requestFocus();
    } else {
      _searchFocusNode.unfocus();
    }
    setState(() {});
  }

  Future<void> _openCreate() async {
    _dismissResults();
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
    _dismissResults();
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
    ref.read(catalogDetailControllerProvider.notifier).clear(product.id);
  }

  Future<void> _addToCart(CatalogProduct product) async {
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
              'Could not refresh this product. Check the connection and try again.',
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

    if (result == OrderActionResult.added ||
        result == OrderActionResult.incremented) {
      _clearSearch();
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1000),
          content: Text(message),
        ),
      );
  }
}

class _SearchResultSurface extends StatelessWidget {
  const _SearchResultSurface({
    required this.search,
    required this.onRetry,
    required this.onOpenProduct,
    required this.onAddToCart,
  });

  final CatalogSearchState search;
  final VoidCallback onRetry;
  final ValueChanged<CatalogProduct> onOpenProduct;
  final ValueChanged<CatalogProduct> onAddToCart;

  @override
  Widget build(BuildContext context) {
    return switch (search.status) {
      CatalogSearchStatus.idle => const SizedBox.shrink(),
      CatalogSearchStatus.loading => const SizedBox(
          height: 68,
          child: Center(
            key: Key('catalog-search-loading'),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      CatalogSearchStatus.empty => const _SearchMessage(
          key: Key('catalog-search-empty'),
          icon: Icons.search_off_rounded,
          title: 'No products found',
          message: 'Try another name or composition.',
        ),
      CatalogSearchStatus.error => _SearchMessage(
          key: const Key('catalog-search-error'),
          icon: Icons.cloud_off_rounded,
          title: 'Could not load products',
          message: 'Check the connection and try again.',
          action: TextButton(
            key: const Key('catalog-search-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      CatalogSearchStatus.results => ListView.separated(
          key: const Key('catalog-search-results'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: search.products.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) {
            final product = search.products[index];
            return _ProductSearchResult(
              product: product,
              onOpen: () => onOpenProduct(product),
              onAdd: () => onAddToCart(product),
            );
          },
        ),
    };
  }
}

class _ProductSearchResult extends StatelessWidget {
  const _ProductSearchResult({
    required this.product,
    required this.onOpen,
    required this.onAdd,
  });

  final CatalogProduct product;
  final VoidCallback onOpen;
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

    return InkWell(
      key: Key('catalog-result-${product.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatWholeAmount(product.sellingAmount)} ${product.currency}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 3),
                IconButton.filledTonal(
                  key: Key('catalog-add-to-order-${product.id}'),
                  tooltip: 'Add to cart',
                  onPressed: onAdd,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
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
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}
