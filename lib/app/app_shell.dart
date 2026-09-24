import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/navigation/application/app_navigation_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const double _railBreakpoint = 800;

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
    final (title, description, key) = switch (destination) {
      AppDestination.catalog => (
          'Catalog workspace',
          'Catalog features will be added in a later bounded task.',
          const Key('catalog-workspace'),
        ),
      AppDestination.order => (
          'Order workspace',
          'Order features will be added in a later bounded task.',
          const Key('order-workspace'),
        ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(description),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
