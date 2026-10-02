import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_gateway.dart';
import '../features/auth/data/secure_supabase_local_storage.dart';
import '../features/auth/data/supabase_auth_gateway.dart';
import '../features/catalog/data/catalog_draft_store.dart';
import '../features/catalog/data/catalog_repository.dart';
import '../features/catalog/data/supabase_catalog_repository.dart';
import '../features/interactions/data/ddi_ingredient_repository.dart';
import '../features/interactions/domain/ddi_runtime_selection.dart';
import '../features/session/data/app_session_store.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    this.ddiRuntimeConfig = const DdiRuntimeConfig(),
  });

  factory AppRuntimeConfig.fromEnvironment() {
    return AppRuntimeConfig(
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      ddiRuntimeConfig: DdiRuntimeConfig.fromEnvironment(),
    );
  }

  final String supabaseUrl;
  final String publishableKey;
  final DdiRuntimeConfig ddiRuntimeConfig;

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

    issues.addAll(ddiRuntimeConfig.problems);
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
    this.appSessionStore,
    this.ddiIngredientRepository,
    this.ddiRuntimeSelection = const DdiRuntimeSelection.interactionChecker(),
  })  : status = AppRuntimeStatus.configured,
        problems = const [];

  const AppRuntime.configurationBlocked(this.problems)
      : status = AppRuntimeStatus.configurationBlocked,
        authGateway = null,
        catalogRepository = null,
        catalogDraftStore = null,
        appSessionStore = null,
        ddiIngredientRepository = null,
        ddiRuntimeSelection = const DdiRuntimeSelection.interactionChecker();

  const AppRuntime.initializationFailed()
      : status = AppRuntimeStatus.initializationFailed,
        authGateway = null,
        catalogRepository = null,
        catalogDraftStore = null,
        appSessionStore = null,
        ddiIngredientRepository = null,
        ddiRuntimeSelection = const DdiRuntimeSelection.interactionChecker(),
        problems = const [
          'Supabase or secure session storage could not be initialized.',
        ];

  final AppRuntimeStatus status;
  final AuthGateway? authGateway;
  final CatalogRepository? catalogRepository;
  final CatalogDraftStore? catalogDraftStore;
  final AppSessionStore? appSessionStore;
  final DdiIngredientRepository? ddiIngredientRepository;
  final DdiRuntimeSelection ddiRuntimeSelection;
  final List<String> problems;

  static Future<AppRuntime> initialize({
    AppRuntimeConfig? config,
    SecureKeyValueStore? secureStore,
  }) async {
    final resolved = config ?? AppRuntimeConfig.fromEnvironment();
    final problems = [...resolved.problems];
    if (kReleaseMode && resolved.ddiRuntimeConfig.requestsSdif) {
      const releaseProblem =
          'DDI_PROVIDER=sdif is development-only and is not enabled in release mode.';
      if (!problems.contains(releaseProblem)) {
        problems.add(releaseProblem);
      }
    }

    if (problems.isNotEmpty) {
      return AppRuntime.configurationBlocked(List.unmodifiable(problems));
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
    final appSessionStore = SecureAppSessionStore(
      store: store,
      keyPrefix: '$storagePrefix:app_session:v1',
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
        appSessionStore: appSessionStore,
        ddiIngredientRepository:
            SupabaseDdiIngredientRepository.fromClient(client),
        ddiRuntimeSelection: resolved.ddiRuntimeConfig.selection,
      );
    } catch (_) {
      return const AppRuntime.initializationFailed();
    }
  }
}
