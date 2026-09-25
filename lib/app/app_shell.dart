import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/presentation/catalog_screen.dart';
import '../features/navigation/application/app_navigation_controller.dart';
import '../features/order/presentation/order_screen.dart';
import '../features/session/application/app_session_controller.dart';

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
                      child: _SessionAwareDestination(
                        destination: destination,
                      ),
                    ),
                  ],
                )
              : _SessionAwareDestination(
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

class _SessionAwareDestination extends ConsumerWidget {
  const _SessionAwareDestination({
    required this.destination,
  });

  final AppDestination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionControllerProvider);

    return Column(
      children: [
        if (session.errorMessage != null)
          Material(
            key: const Key('local-session-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      session.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    key: const Key('local-session-retry'),
                    onPressed: () {
                      ref
                          .read(appSessionControllerProvider.notifier)
                          .retryPersistence();
                    },
                    child: const Text('Retry local save'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _DestinationContent(
            destination: destination,
          ),
        ),
      ],
    );
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
      AppDestination.order => const OrderScreen(),
    };
  }
}
