import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/data/ddi_ingredient_repository.dart';
import 'package:sherko_pharma/features/interactions/data/interaction_checker_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/ddi_interaction_detail_sheet.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/features/scanning/application/barcode_scan_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

void main() {
  testWidgets(
    'scanner to trusted ingredients to engine to Cart and detail stays isolated',
    (tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = FakeAuthGateway(
        initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
      );
      addTearDown(auth.dispose);

      final catalog = FakeCatalogRepository()
        ..products['combo'] = testProduct(
          id: 'combo',
          nameEn: 'Brand Combo',
          barcode: '000123',
          barcode2: null,
          sellingAmount: 1000,
          currency: 'SYP',
        )
        ..products['single'] = testProduct(
          id: 'single',
          nameEn: 'Brand Gamma',
          barcode: '000456',
          barcode2: null,
          sellingAmount: 2000,
          currency: 'SYP',
        );

      final ingredientRepository = _IngredientRepository({
        'combo': _trusted(
          'combo',
          const [
            DdiIngredientIdentity(
              id: 1,
              name: 'Alpha',
              normalizedName: 'alpha',
            ),
            DdiIngredientIdentity(
              id: 2,
              name: 'Beta',
              normalizedName: 'beta',
            ),
          ],
        ),
        'single': _trusted(
          'single',
          const [
            DdiIngredientIdentity(
              id: 3,
              name: 'Gamma',
              normalizedName: 'gamma',
            ),
          ],
        ),
      });
      final provider = _ProviderGateway();
      final linkLauncher = _LinkLauncher();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ddiIngredientRepositoryProvider.overrideWithValue(
              ingredientRepository,
            ),
            interactionCheckGatewayProvider.overrideWithValue(provider),
            ddiCartDebounceDurationProvider.overrideWithValue(Duration.zero),
            ddiExternalLinkLauncherProvider.overrideWithValue(linkLauncher),
          ],
          child: AppBootstrap(
            runtime: AppRuntime.configured(
              auth,
              catalogRepository: catalog,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(AppShell));
      final container = ProviderScope.containerOf(context);
      final order = container.read(orderControllerProvider.notifier);
      final scanner = BarcodeScanController(
        catalog: catalog,
        order: order,
      );

      final scanResult = await scanner.accept('000123');
      expect(scanResult?.status, BarcodeScanStatus.added);
      expect(catalog.barcodeCalls, ['000123']);

      expect(
        order.addProduct(catalog.products['single']!),
        OrderActionResult.added,
      );
      await tester.pumpAndSettle();

      expect(ingredientRepository.calls, [
        ['combo', 'single'],
      ]);
      expect(provider.calls, hasLength(1));
      expect(provider.calls.single, ['Alpha', 'Beta', 'Gamma']);
      expect(
        provider.calls.single.any(
          (value) =>
              value.contains('Brand') ||
              value.contains('000123') ||
              value.contains('1000') ||
              value.contains('owner-user-id'),
        ),
        isFalse,
      );

      expect(
        find.byKey(const Key('ddi-summary-moderate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ddi-row-severity-combo')),
        findsOneWidget,
      );
      expect(find.text('Moderate'), findsNWidgets(2));
      expect(
        find.byKey(const Key('ddi-cart-provider-disclaimer')),
        findsOneWidget,
      );
      expect(find.text('Not medical advice.'), findsOneWidget);
      expect(
        find.byKey(const Key('ddi-cart-provider-link')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('ddi-cart-provider-link')),
      );
      await tester.pump();
      expect(
        linkLauncher.opened,
        [Uri.parse('https://interaction-checker.com')],
      );

      await tester.tap(
        find.byKey(const Key('ddi-row-severity-combo')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ddi-detail-sheet')),
        findsOneWidget,
      );
      expect(find.text('Brand Combo ↔ Brand Gamma'), findsOneWidget);
      expect(find.text('Alpha ↔ Gamma'), findsOneWidget);
      expect(find.text('Beta ↔ Gamma'), findsOneWidget);
      expect(find.text('Alpha ↔ Beta'), findsNothing);
      expect(
        find.text('Synthetic evidence Alpha / Gamma'),
        findsOneWidget,
      );
      expect(
        find.text('Synthetic evidence Beta / Gamma'),
        findsOneWidget,
      );
      expect(find.textContaining('FDA label'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('ddi-detail-close')),
      );
      await tester.pumpAndSettle();

      expect(container.read(orderControllerProvider).totalSyp, 3000);
      order.increment('combo');
      await tester.pump();
      expect(container.read(orderControllerProvider).totalSyp, 4000);
      expect(provider.calls, hasLength(1));
      expect(
        container.read(orderControllerProvider).lines
            .singleWhere((line) => line.productId == 'combo')
            .quantity,
        2,
      );
    },
  );
}

class _IngredientRepository implements DdiIngredientRepository {
  _IngredientRepository(this.products);

  final Map<String, DdiProductIngredientInput> products;
  final List<List<String>> calls = [];

  @override
  Future<List<DdiProductIngredientInput>> resolveProducts(
    List<String> productIds,
  ) async {
    calls.add(List<String>.unmodifiable(productIds));
    return [
      for (final productId in productIds) products[productId]!,
    ];
  }
}

class _ProviderGateway implements InteractionCheckGateway {
  final List<List<String>> calls = [];

  @override
  Future<InteractionCheckResult> checkInteractions(
    List<String> items,
  ) async {
    final captured = List<String>.unmodifiable(items);
    calls.add(captured);

    final severities = <String, InteractionSeverity>{
      _pairKey('Alpha', 'Beta'): InteractionSeverity.major,
      _pairKey('Alpha', 'Gamma'): InteractionSeverity.minor,
      _pairKey('Beta', 'Gamma'): InteractionSeverity.moderate,
    };
    final pairs = <InteractionPair>[];
    final summary = <InteractionSeverity, int>{
      for (final severity in InteractionSeverity.values) severity: 0,
    };

    for (var left = 0; left < captured.length; left++) {
      for (var right = left + 1; right < captured.length; right++) {
        final a = captured[left];
        final b = captured[right];
        final severity =
            severities[_pairKey(a, b)] ?? InteractionSeverity.none;
        summary[severity] = summary[severity]! + 1;
        pairs.add(
          InteractionPair(
            a: _substance(a),
            b: _substance(b),
            severity: severity,
            severityLabel: _severityLabel(severity),
            url: Uri.parse(
              'https://interaction-checker.com/?d=$a,$b',
            ),
            page: Uri.parse(
              'https://interaction-checker.com/interactions/'
              '${a.toLowerCase()}-and-${b.toLowerCase()}',
            ),
            evidence: severity == InteractionSeverity.unknown
                ? const []
                : [
                    _evidence(a, b, severity),
                  ],
          ),
        );
      }
    }

    return InteractionCheckResult(
      items: [
        for (final query in captured)
          ResolvedInteractionItem(
            substance: _substance(query),
            query: query,
          ),
      ],
      unresolved: const [],
      pairs: pairs,
      summary: summary,
      data: InteractionCheckData(
        labelExportDate: DateTime.utc(2026, 9, 3),
        generatedAt: DateTime.utc(2026, 9, 29),
      ),
      disclaimer: 'Not medical advice.',
      attribution: InteractionAttribution(
        text: 'Interaction Checker',
        url: Uri.parse('https://interaction-checker.com'),
        license: 'Free with attribution',
      ),
    );
  }
}

class _LinkLauncher implements DdiExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

DdiProductIngredientInput _trusted(
  String productId,
  List<DdiIngredientIdentity> ingredients,
) {
  return DdiProductIngredientInput(
    productId: productId,
    requestPosition: 1,
    coverageStatus: DdiIngredientCoverageStatus.trusted,
    productExists: true,
    normalizationStatus: 'auto_verified',
    componentCount: ingredients.length,
    resolvedComponentCount: ingredients.length,
    ingredients: ingredients,
  );
}

InteractionSubstance _substance(String name) {
  return InteractionSubstance(
    id: 'substance:${name.toLowerCase()}',
    name: name,
    kind: InteractionSubstanceKind.drug,
    url: Uri.parse(
      'https://interaction-checker.com/drugs/${name.toLowerCase()}',
    ),
  );
}

InteractionEvidence _evidence(
  String from,
  String about,
  InteractionSeverity severity,
) {
  final evidenceSeverity = switch (severity) {
    InteractionSeverity.major => InteractionEvidenceSeverity.major,
    InteractionSeverity.moderate =>
      InteractionEvidenceSeverity.moderate,
    InteractionSeverity.minor => InteractionEvidenceSeverity.minor,
    InteractionSeverity.none => InteractionEvidenceSeverity.none,
    InteractionSeverity.unknown => InteractionEvidenceSeverity.none,
  };

  return InteractionEvidence(
    from: from,
    about: about,
    section: InteractionEvidenceSection.drugInteractions,
    sectionLabel: 'Drug interactions',
    severity: evidenceSeverity,
    quote: 'Synthetic evidence $from / $about',
    matchedTerm: about.toLowerCase(),
    matchKind: InteractionMatchKind.name,
    source: InteractionEvidenceSource(
      type: InteractionSourceType.fdaLabel,
      name: 'Synthetic FDA label',
      url: Uri.parse('https://dailymed.nlm.nih.gov/test'),
      effectiveDate: DateTime.utc(2026, 1, 2),
    ),
  );
}

String _severityLabel(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => 'Major',
    InteractionSeverity.moderate => 'Moderate',
    InteractionSeverity.minor => 'Minor',
    InteractionSeverity.none => 'None',
    InteractionSeverity.unknown => 'Unknown',
  };
}

String _pairKey(String left, String right) {
  return left.compareTo(right) <= 0
      ? '$left|$right'
      : '$right|$left';
}
