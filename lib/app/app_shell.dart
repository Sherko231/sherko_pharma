import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/application/scoped_catalog_refresh_controller.dart';
import '../features/catalog/presentation/catalog_screen.dart';
import '../features/navigation/application/app_navigation_controller.dart';
import '../features/order/presentation/order_screen.dart';
import '../features/session/application/app_session_controller.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.onSignOut,
  });

  static const double railBreakpoint = 800;

  final VoidCallback? onSignOut;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(scopedCatalogRefreshControllerProvider.notifier)
            .setActive(true);
      }
    });
  }

  @override
  void dispose() {
    ref
        .read(scopedCatalogRefreshControllerProvider.notifier)
        .setActive(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    ref
        .read(scopedCatalogRefreshControllerProvider.notifier)
        .setActive(active);
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(appNavigationControllerProvider);
    final selectedIndex = AppDestination.values.indexOf(destination);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail =
            constraints.maxWidth >= AppShell.railBreakpoint;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Sherko Pharma'),
            actions: [
              if (widget.onSignOut != null)
                IconButton(
                  key: const Key('sign-out-button'),
                  tooltip: 'Sign out',
                  onPressed: widget.onSignOut,
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
    final refresh = ref.watch(scopedCatalogRefreshControllerProvider);

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
        if (refresh.errorMessage != null)
          Material(
            key: const Key('catalog-refresh-error'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_problem,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      refresh.errorMessage!,
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    key: const Key('catalog-refresh-retry'),
                    onPressed: () {
                      ref
                          .read(
                            scopedCatalogRefreshControllerProvider.notifier,
                          )
                          .retry();
                    },
                    child: const Text('Retry refresh'),
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
