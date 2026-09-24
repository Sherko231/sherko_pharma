import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/catalog_detail_controller.dart';
import '../domain/catalog_product.dart';
import 'catalog_text.dart';

class CatalogDetailScreen extends ConsumerStatefulWidget {
  const CatalogDetailScreen({
    required this.productId,
    required this.fallbackName,
    super.key,
  });

  final String productId;
  final String fallbackName;

  @override
  ConsumerState<CatalogDetailScreen> createState() =>
      _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends ConsumerState<CatalogDetailScreen> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) {
        ref
            .read(catalogDetailControllerProvider.notifier)
            .load(widget.productId);
      }
    });
  }

  @override
  void didUpdateWidget(CatalogDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      ref
          .read(catalogDetailControllerProvider.notifier)
          .load(widget.productId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(catalogDetailControllerProvider);
    final currentProduct = detail.productId == widget.productId
        ? detail.product
        : null;
    final currentStatus = detail.productId == widget.productId
        ? detail.status
        : CatalogDetailStatus.loading;

    return Scaffold(
      appBar: AppBar(
        title: CatalogText(
          currentProduct?.displayName ?? widget.fallbackName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: switch (currentStatus) {
        CatalogDetailStatus.idle || CatalogDetailStatus.loading => const Center(
            key: Key('catalog-detail-loading'),
            child: CircularProgressIndicator(),
          ),
        CatalogDetailStatus.loaded => _ProductDetailBody(
            product: currentProduct!,
          ),
        CatalogDetailStatus.notFound => const _DetailMessage(
            key: Key('catalog-detail-not-found'),
            icon: Icons.search_off,
            title: 'Product not found',
            message: 'This product is no longer available in the catalog.',
          ),
        CatalogDetailStatus.error => _DetailMessage(
            key: const Key('catalog-detail-error'),
            icon: Icons.cloud_off,
            title: 'Could not load product',
            message: 'Check your connection and try again.',
            action: FilledButton.tonal(
              key: const Key('catalog-detail-retry'),
              onPressed: () {
                ref
                    .read(catalogDetailControllerProvider.notifier)
                    .retry();
              },
              child: const Text('Retry'),
            ),
          ),
      },
    );
  }
}

class _ProductDetailBody extends StatelessWidget {
  const _ProductDetailBody({
    required this.product,
  });

  final CatalogProduct product;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          key: const Key('catalog-detail-content'),
          padding: const EdgeInsets.all(20),
          children: [
            _DetailField(
              label: 'English name',
              value: product.nameEn,
            ),
            _DetailField(
              label: 'Arabic name',
              value: product.nameAr,
            ),
            _DetailField(
              label: 'Composition',
              value: product.composition,
            ),
            _DetailField(
              label: 'Manufacturer',
              value: product.manufacturer,
            ),
            _DetailField(
              label: 'Strength',
              value: product.strength,
            ),
            _DetailField(
              label: 'Dosage form',
              value: product.dosageForm,
            ),
            _DetailField(
              label: 'Package',
              value: product.packageDescription,
            ),
            _DetailField(
              label: 'Primary barcode',
              value: product.barcode,
            ),
            _DetailField(
              label: 'Secondary barcode',
              value: product.barcode2,
            ),
            _DetailField(
              label: 'Selling price',
              value: '${product.sellingAmount} ${product.currency}',
            ),
            _DetailField(
              label: 'Notes',
              value: product.notes,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final visibleValue = value?.trim().isNotEmpty ?? false
        ? value!.trim()
        : 'Not provided';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 5),
          CatalogText(
            visibleValue,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
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
      child: Padding(
        padding: const EdgeInsets.all(24),
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
    );
  }
}
