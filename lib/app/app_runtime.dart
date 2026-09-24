import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_gateway.dart';
import '../features/auth/data/secure_supabase_local_storage.dart';
import '../features/auth/data/supabase_auth_gateway.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    required this.supabaseUrl,
    required this.publishableKey,
  });

  factory AppRuntimeConfig.fromEnvironment() {
    return const AppRuntimeConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String supabaseUrl;
  final String publishableKey;

  List<String> get problems {
    final issues = <String>[];
    final url = Uri.tryParse(supabaseUrl);

    if (supabaseUrl.isEmpty) {
      issues.add('SUPABASE_URL is missing.');
    } else if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      issues.add('SUPABASE_URL must be a valid HTTPS project URL.');
    }

    if (publishableKey.isEmpty) {
      issues.add('SUPABASE_PUBLISHABLE_KEY is missing.');
    }

    return issues;
  }
}

enum AppRuntimeStatus {
  configured,
  configurationBlocked,
  initializationFailed,
}

class AppRuntime {
  const AppRuntime.configured(this.authGateway)
      : status = AppRuntimeStatus.configured,
        problems = const [];

  const AppRuntime.configurationBlocked(this.problems)
      : status = AppRuntimeStatus.configurationBlocked,
        authGateway = null;

  const AppRuntime.initializationFailed()
      : status = AppRuntimeStatus.initializationFailed,
        authGateway = null,
        problems = const [
          'Supabase or secure session storage could not be initialized.',
        ];

  final AppRuntimeStatus status;
  final AuthGateway? authGateway;
  final List<String> problems;

  static Future<AppRuntime> initialize({
    AppRuntimeConfig? config,
    SecureKeyValueStore? secureStore,
  }) async {
    final resolved = config ?? AppRuntimeConfig.fromEnvironment();
    final problems = resolved.problems;

    if (problems.isNotEmpty) {
      return AppRuntime.configurationBlocked(problems);
    }

    final sessionStorage = SecureSupabaseLocalStorage(
      store: secureStore ?? const FlutterSecureKeyValueStore(),
      sessionKey:
          'sherko_pharma:${Uri.parse(resolved.supabaseUrl).host}:auth_session',
    );

    try {
      await Supabase.initialize(
        url: resolved.supabaseUrl,
        publishableKey: resolved.publishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: sessionStorage,
          detectSessionInUri: false,
        ),
      );

      return AppRuntime.configured(
        SupabaseAuthGateway(Supabase.instance.client),
      );
    } catch (_) {
      return const AppRuntime.initializationFailed();
    }
  }
}
