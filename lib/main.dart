import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_runtime.dart';
import 'features/auth/application/auth_controller.dart';

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
    final gateway = runtime.authGateway;

    return ProviderScope(
      overrides: [
        if (gateway != null)
          authGatewayProvider.overrideWithValue(gateway),
      ],
      child: SherkoPharmaApp(runtime: runtime),
    );
  }
}
