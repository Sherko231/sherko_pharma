import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/presentation/catalog_screen.dart';
import '../features/navigation/application/app_navigation_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    this.onSignOut,
  });

  static const double _railBreakpoint = 800;

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(appNavigationControllerProvider);
    final selectedIndex = AppDestination.values.indexOf(destination);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= _railBreakpoint;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Sherko Pharma'),
            actions: [
              if (onSignOut != null)
                IconButton(
                  key: const Key('sign-out-button'),
                  tooltip: 'Sign out',
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                ),
            ],
          ),
          body: useNavigationRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (index) {
                        _selectDestination(ref, index);
                      },
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.medication_outlined),
                          selectedIcon: Icon(Icons.medication),
                          label: Text('Catalog'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long),
                          label: Text('Order'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _DestinationContent(
                        destination: destination,
                      ),
                    ),
                  ],
                )
              : _DestinationContent(
                  destination: destination,
                ),
          bottomNavigationBar: useNavigationRail
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    _selectDestination(ref, index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.medication_outlined),
                      selectedIcon: Icon(Icons.medication),
                      label: 'Catalog',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: 'Order',
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _selectDestination(WidgetRef ref, int index) {
    ref
        .read(appNavigationControllerProvider.notifier)
        .select(AppDestination.values[index]);
  }
}

class _DestinationContent extends StatelessWidget {
  const _DestinationContent({
    required this.destination,
  });

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.catalog => const CatalogScreen(),
      AppDestination.order => const _OrderPlaceholder(),
    };
  }
}

class _OrderPlaceholder extends StatelessWidget {
  const _OrderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            key: const Key('order-workspace'),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order workspace'),
                  SizedBox(height: 12),
                  Text(
                    'Order features will be added in a later bounded task.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
