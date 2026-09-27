import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/whole_amount.dart';
import '../../order/application/order_controller.dart';
import '../application/catalog_search_controller.dart';
import '../domain/catalog_alternative.dart';
import '../domain/catalog_product.dart';
import 'catalog_text.dart';

Future<void> showCatalogAlternativesSheet({
  required BuildContext context,
  required CatalogProduct targetProduct,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CatalogAlternativesSheet(
      targetProduct: targetProduct,
    ),
  );
}

class CatalogAlternativesSheet extends ConsumerStatefulWidget {
  const CatalogAlternativesSheet({
    required this.targetProduct,
    super.key,
  });

  final CatalogProduct targetProduct;

  @override
  ConsumerState<CatalogAlternativesSheet> createState() =>
      _CatalogAlternativesSheetState();
}

class _CatalogAlternativesSheetState
    extends ConsumerState<CatalogAlternativesSheet> {
  static const int _requestLimitPerGroup = 10;

  List<CatalogAlternative> _alternatives = const [];
  final Set<String> _addingProductIds = <String>{};
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }

    try {
      final alternatives = await ref.read(catalogRepositoryProvider).alternatives(
            widget.targetProduct.id,
            limitPerGroup: _requestLimitPerGroup,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _alternatives = alternatives;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.82;

    return SizedBox(
      key: const Key('catalog-alternatives-sheet'),
      height: sheetHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alternatives',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      CatalogText(
                        widget.targetProduct.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('catalog-alternatives-close'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              key: const Key('catalog-alternatives-disclaimer'),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Catalog grouping only. These matches do not establish clinical interchangeability or prescribing suitability.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(
        key: Key('catalog-alternatives-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (_loadFailed) {
      return _AlternativesMessage(
        key: const Key('catalog-alternatives-error'),
        icon: Icons.cloud_off_rounded,
        title: 'Could not load alternatives',
        message: 'Check the connection and try again.',
        action: FilledButton.tonal(
          key: const Key('catalog-alternatives-retry'),
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }

    if (_alternatives.isEmpty) {
      return const _AlternativesMessage(
        key: Key('catalog-alternatives-empty'),
        icon: Icons.compare_arrows_rounded,
        title: 'No catalog matches available',
        message:
            'No trusted alternatives were returned for this product classification.',
      );
    }

    final sections = <Widget>[];
    for (final group in CatalogAlternativeGroup.values) {
      final items = _alternatives
          .where((alternative) => alternative.group == group)
          .toList(growable: true)
        ..sort(
          (left, right) =>
              left.groupPosition.compareTo(right.groupPosition),
        );
      if (items.isEmpty) {
        continue;
      }

      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 10));
      }
      sections.add(
        _AlternativeSection(
          group: group,
          alternatives: items,
          addingProductIds: _addingProductIds,
          onAdd: _addToCart,
        ),
      );
    }

    return ListView(
      key: const Key('catalog-alternatives-content'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: sections,
    );
  }

  Future<void> _addToCart(CatalogAlternative alternative) async {
    final productId = alternative.product.id;
    if (_addingProductIds.contains(productId)) {
      return;
    }

    setState(() => _addingProductIds.add(productId));

    CatalogProduct latest;
    try {
      latest = await ref.read(catalogRepositoryProvider).getById(productId);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not refresh this product before adding it. Check the connection and try again.',
          seconds: 2,
        );
        setState(() => _addingProductIds.remove(productId));
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final result = ref.read(orderControllerProvider.notifier).addProduct(latest);
    final message = switch (result) {
      OrderActionResult.added => 'Added to cart.',
      OrderActionResult.incremented => 'Quantity increased.',
      OrderActionResult.invalidPrice =>
        'Set a positive SYP or USD selling price before adding this product.',
      OrderActionResult.overflow =>
        'This cart amount is too large to calculate safely.',
      _ => 'Cart was not changed.',
    };

    setState(() => _addingProductIds.remove(productId));
    _showMessage(message);
  }

  void _showMessage(String message, {int seconds = 1}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: seconds),
          content: Text(message),
        ),
      );
  }
}

class _AlternativeSection extends StatelessWidget {
  const _AlternativeSection({
    required this.group,
    required this.alternatives,
    required this.addingProductIds,
    required this.onAdd,
  });

  final CatalogAlternativeGroup group;
  final List<CatalogAlternative> alternatives;
  final Set<String> addingProductIds;
  final ValueChanged<CatalogAlternative> onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('catalog-alternatives-group-${group.rpcValue}'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _groupTitle(group),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${alternatives.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < alternatives.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 10,
                endIndent: 10,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            _AlternativeRow(
              alternative: alternatives[index],
              adding: addingProductIds.contains(
                alternatives[index].product.id,
              ),
              onAdd: () => onAdd(alternatives[index]),
            ),
          ],
        ],
      ),
    );
  }

  String _groupTitle(CatalogAlternativeGroup group) {
    return switch (group) {
      CatalogAlternativeGroup.exact => 'Same ingredients, strength & form',
      CatalogAlternativeGroup.sameIngredientsDifferentStrength =>
        'Same ingredients · different strength',
      CatalogAlternativeGroup.sameIngredientsDifferentForm =>
        'Same ingredients & strength · different form',
    };
  }
}

class _AlternativeRow extends StatelessWidget {
  const _AlternativeRow({
    required this.alternative,
    required this.adding,
    required this.onAdd,
  });

  final CatalogAlternative alternative;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final product = alternative.product;
    final company = _visibleOrFallback(product.manufacturer, 'Not provided');
    final strength = _visibleOrFallback(product.strength, 'Not provided');
    final form = _visibleOrFallback(product.dosageForm, 'Not provided');

    return Padding(
      key: Key('catalog-alternative-${product.id}'),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CatalogText(
                  product.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                _AlternativeMetadataLine(
                  label: 'Company',
                  value: company,
                ),
                const SizedBox(height: 1),
                _AlternativeMetadataLine(
                  label: 'Strength',
                  value: strength,
                  muted: true,
                ),
                const SizedBox(height: 1),
                _AlternativeMetadataLine(
                  label: 'Form',
                  value: form,
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${formatWholeAmount(product.sellingAmount)} ${product.currency}',
                key: Key('catalog-alternative-price-${product.id}'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              IconButton.filledTonal(
                key: Key('catalog-alternative-add-${product.id}'),
                tooltip: 'Add to cart',
                onPressed: adding ? null : onAdd,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_shopping_cart_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _visibleOrFallback(String? value, String fallback) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
  }
}

class _AlternativeMetadataLine extends StatelessWidget {
  const _AlternativeMetadataLine({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    final style = muted
        ? baseStyle?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )
        : baseStyle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: style,
        ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: CatalogText(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlternativesMessage extends StatelessWidget {
  const _AlternativesMessage({
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
            Icon(
              icon,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
