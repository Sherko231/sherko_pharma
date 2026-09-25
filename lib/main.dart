import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_runtime.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/catalog/application/catalog_search_controller.dart';
import 'features/catalog/data/catalog_draft_store.dart';
import 'features/session/data/app_session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await AppRuntime.initialize();
  runApp(AppBootstrap(runtime: runtime));
}

class AppBootstrap extends StatelessWidget {
  const AppBootstrap({
    super.key,
    this.runtime = const AppRuntime.configurationBlocked([
      'SUPABASE_URL is missing.',
      'SUPABASE_PUBLISHABLE_KEY is missing.',
    ]),
  });

  final AppRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final authGateway = runtime.authGateway;
    final catalogRepository = runtime.catalogRepository;
    final catalogDraftStore = runtime.catalogDraftStore;
    final appSessionStore = runtime.appSessionStore;

    return ProviderScope(
      overrides: [
        if (authGateway != null)
          authGatewayProvider.overrideWithValue(authGateway),
        if (catalogRepository != null)
          catalogRepositoryProvider.overrideWithValue(catalogRepository),
        if (catalogDraftStore != null)
          catalogDraftStoreProvider.overrideWithValue(catalogDraftStore),
        if (appSessionStore != null)
          appSessionStoreProvider.overrideWithValue(appSessionStore),
      ],
      child: SherkoPharmaApp(runtime: runtime),
    );
  }
}
