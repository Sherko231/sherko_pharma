import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/catalog_search_controller.dart';
import '../domain/catalog_product.dart';
import 'catalog_detail_screen.dart';
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
          const SizedBox(height: 16),
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
              ),
            ),
          ),
        ],
      ),
    );
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
}

class _CatalogSearchBody extends StatelessWidget {
  const _CatalogSearchBody({
    required this.search,
    required this.onRetry,
    required this.onOpenProduct,
  });

  final CatalogSearchState search;
  final VoidCallback onRetry;
  final ValueChanged<CatalogProduct> onOpenProduct;

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
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final product = search.products[index];
            return _ProductResultCard(
              product: product,
              onTap: () => onOpenProduct(product),
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
  });

  final CatalogProduct product;
  final VoidCallback onTap;

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
                  const Icon(Icons.chevron_right),
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
