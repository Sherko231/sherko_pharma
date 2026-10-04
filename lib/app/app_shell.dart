import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/application/scoped_catalog_refresh_controller.dart';
import '../features/order/presentation/order_screen.dart';
import '../features/session/application/app_session_controller.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.onSignOut,
  });

  final VoidCallback? onSignOut;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  late final ScopedCatalogRefreshController _refreshController;

  @override
  void initState() {
    super.initState();
    _refreshController =
        ref.read(scopedCatalogRefreshControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshController.setActive(true);
      }
    });
  }

  @override
  void dispose() {
    _refreshController.setActive(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshController.setActive(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text('Sherko Pharma'),
        actions: [
          if (widget.onSignOut != null)
            IconButton(
              key: const Key('sign-out-button'),
              tooltip: 'Sign out',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout, size: 20),
            ),
        ],
      ),
      body: const _SessionAwareCart(),
    );
  }
}

class _SessionAwareCart extends ConsumerWidget {
  const _SessionAwareCart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionControllerProvider);
    final refresh = ref.watch(scopedCatalogRefreshControllerProvider);

    return Column(
      children: [
        if (session.errorMessage != null)
          _CompactStatusBanner(
            key: const Key('local-session-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            foreground: Theme.of(context).colorScheme.onErrorContainer,
            icon: Icons.warning_amber_rounded,
            message: session.errorMessage!,
            action: TextButton(
              key: const Key('local-session-retry'),
              onPressed: () {
                ref
                    .read(appSessionControllerProvider.notifier)
                    .retryPersistence();
              },
              child: const Text('Retry local save'),
            ),
          ),
        if (refresh.errorMessage != null)
          _CompactStatusBanner(
            key: const Key('catalog-refresh-error'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            foreground: Theme.of(context).colorScheme.onTertiaryContainer,
            icon: Icons.sync_problem,
            message: refresh.errorMessage!,
            action: TextButton(
              key: const Key('catalog-refresh-retry'),
              onPressed: () {
                ref
                    .read(scopedCatalogRefreshControllerProvider.notifier)
                    .retry();
              },
              child: const Text('Retry refresh'),
            ),
          ),
        const Expanded(child: OrderScreen()),
      ],
    );
  }
}

class _CompactStatusBanner extends StatelessWidget {
  const _CompactStatusBanner({
    super.key,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.message,
    required this.action,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
            const SizedBox(width: 6),
            action,
          ],
        ),
      ),
    );
  }
}
