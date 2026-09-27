import 'package:flutter/material.dart';

import 'catalog_search_panel.dart';

/// Compatibility wrapper for code that still references the former catalog
/// destination. The normal application flow renders [CatalogSearchPanel]
/// inside the single Cart workspace.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('catalog-workspace'),
      padding: EdgeInsets.all(8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: CatalogSearchPanel(maxResultsHeight: 420),
        ),
      ),
    );
  }
}
