import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_gateway.dart';
import '../features/auth/data/secure_supabase_local_storage.dart';
import '../features/auth/data/supabase_auth_gateway.dart';
import '../features/catalog/data/catalog_draft_store.dart';
import '../features/catalog/data/catalog_repository.dart';
import '../features/catalog/data/supabase_catalog_repository.dart';

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
  const AppRuntime.configured(
    this.authGateway, {
    this.catalogRepository,
    this.catalogDraftStore,
  })  : status = AppRuntimeStatus.configured,
        problems = const [];

  const AppRuntime.configurationBlocked(this.problems)
      : status = AppRuntimeStatus.configurationBlocked,
        authGateway = null,
        catalogRepository = null,
        catalogDraftStore = null;

  const AppRuntime.initializationFailed()
      : status = AppRuntimeStatus.initializationFailed,
        authGateway = null,
        catalogRepository = null,
        catalogDraftStore = null,
        problems = const [
          'Supabase or secure session storage could not be initialized.',
        ];

  final AppRuntimeStatus status;
  final AuthGateway? authGateway;
  final CatalogRepository? catalogRepository;
  final CatalogDraftStore? catalogDraftStore;
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

    final store = secureStore ?? const FlutterSecureKeyValueStore();
    final storagePrefix =
        'sherko_pharma:${Uri.parse(resolved.supabaseUrl).host}';
    final sessionStorage = SecureSupabaseLocalStorage(
      store: store,
      sessionKey: '$storagePrefix:auth_session',
    );
    final draftStore = SecureCatalogDraftStore(
      store: store,
      keyPrefix: '$storagePrefix:catalog_draft:v1',
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

      final client = Supabase.instance.client;
      return AppRuntime.configured(
        SupabaseAuthGateway(client),
        catalogRepository: SupabaseCatalogRepository.fromClient(client),
        catalogDraftStore: draftStore,
      );
    } catch (_) {
      return const AppRuntime.initializationFailed();
    }
  }
}
