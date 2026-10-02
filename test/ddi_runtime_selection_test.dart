import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/ddi_ingredient_repository.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_scientific_identity_repository.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_runtime_selection.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_product_scientific_models.dart';

void main() {
  group('DdiRuntimeConfig', () {
    test('defaults to Interaction Checker', () {
      const config = DdiRuntimeConfig();

      expect(config.problems, isEmpty);
      expect(
        config.selection.provider,
        DdiRuntimeProvider.interactionChecker,
      );
      expect(config.selection.sdifBaseUri, isNull);
    });

    test('accepts an explicit development SDIF HTTP base URI', () {
      const config = DdiRuntimeConfig(
        providerValue: 'sdif',
        sdifBaseUriValue: 'http://127.0.0.1:3000/',
        allowSdif: true,
      );

      expect(config.problems, isEmpty);
      expect(config.selection.provider, DdiRuntimeProvider.sdif);
      expect(
        config.selection.sdifBaseUri,
        Uri.parse('http://127.0.0.1:3000/'),
      );
    });

    test('rejects SDIF when development access is disabled', () {
      const config = DdiRuntimeConfig(
        providerValue: 'sdif',
        allowSdif: false,
      );

      expect(
        config.problems,
        contains(
          'DDI_PROVIDER=sdif is development-only and is not enabled in release mode.',
        ),
      );
    });

    test('rejects unsupported provider and unsafe SDIF base URI', () {
      const unsupported = DdiRuntimeConfig(providerValue: 'other');
      expect(
        unsupported.problems,
        contains('DDI_PROVIDER must be "interaction_checker" or "sdif".'),
      );

      const unsafeSdif = DdiRuntimeConfig(
        providerValue: 'sdif',
        sdifBaseUriValue: 'http://user:pass@127.0.0.1:3000/?x=1',
      );
      expect(
        unsafeSdif.problems,
        contains(
          'SDIF_BASE_URI must be a valid HTTP(S) base URI without credentials, query, or fragment.',
        ),
      );
    });

    test('AppRuntimeConfig includes DDI runtime validation', () {
      const config = AppRuntimeConfig(
        supabaseUrl: 'https://project.example.test',
        publishableKey: 'publishable',
        ddiRuntimeConfig: DdiRuntimeConfig(
          providerValue: 'sdif',
          allowSdif: false,
        ),
      );

      expect(
        config.problems,
        contains(
          'DDI_PROVIDER=sdif is development-only and is not enabled in release mode.',
        ),
      );
    });
  });

  group('DDI runtime provider wiring', () {
    test('Interaction Checker remains the default Cart analysis path', () {
      final container = ProviderContainer(
        overrides: [
          ddiIngredientRepositoryProvider.overrideWithValue(
            const _FakeDdiIngredientRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(ddiRuntimeSelectionProvider).provider,
        DdiRuntimeProvider.interactionChecker,
      );
      expect(container.read(ddiAnalysisGatewayProvider), isNotNull);
      expect(container.read(sdifGatewayProvider), isNull);
      expect(container.read(sdifReviewedAtcBridgeProvider), isNull);
      expect(container.read(sdifResultAggregatorProvider), isNull);
      expect(container.read(sdifScientificIdentityRepositoryProvider), isNull);
    });

    test('SDIF wiring is isolated from the current Cart analysis gateway', () {
      const scientificRepository = _FakeSdifScientificIdentityRepository();
      final container = ProviderContainer(
        overrides: [
          ddiRuntimeSelectionProvider.overrideWithValue(
            DdiRuntimeSelection.sdif(
              Uri.parse('http://127.0.0.1:3000/'),
            ),
          ),
          ddiIngredientRepositoryProvider.overrideWithValue(
            const _FakeDdiIngredientRepository(),
          ),
          sdifScientificIdentityRepositoryProvider.overrideWithValue(
            scientificRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(ddiAnalysisGatewayProvider), isNull);
      expect(container.read(sdifGatewayProvider), isA<SdifGateway>());
      expect(container.read(sdifReviewedAtcBridgeProvider), isNotNull);
      expect(container.read(sdifResultAggregatorProvider), isNotNull);
      expect(
        container.read(sdifScientificIdentityRepositoryProvider),
        same(scientificRepository),
      );
    });
  });
}

class _FakeDdiIngredientRepository implements DdiIngredientRepository {
  const _FakeDdiIngredientRepository();

  @override
  Future<List<DdiProductIngredientInput>> resolveProducts(
    List<String> productIds,
  ) async {
    return const [];
  }
}

class _FakeSdifScientificIdentityRepository
    implements SdifScientificIdentityRepository {
  const _FakeSdifScientificIdentityRepository();

  @override
  Future<List<SdifProductScientificInput>> resolveProducts(
    List<String> productIds,
  ) async {
    return const [];
  }
}
