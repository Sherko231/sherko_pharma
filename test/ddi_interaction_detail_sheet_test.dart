import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/application/ddi_cart_controller.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';
import 'package:sherko_pharma/features/interactions/presentation/ddi_interaction_detail_sheet.dart';
import 'package:sherko_pharma/features/order/application/order_controller.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

Future<ProviderContainer> pumpDetailApp(
  WidgetTester tester, {
  required DdiAnalysisGateway gateway,
  required DdiExternalLinkLauncher linkLauncher,
}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthGateway(
    initialIdentity: const AuthIdentity(userId: 'owner-user-id'),
  );
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ddiAnalysisGatewayProvider.overrideWithValue(gateway),
        ddiCartDebounceDurationProvider.overrideWithValue(Duration.zero),
        ddiExternalLinkLauncherProvider.overrideWithValue(linkLauncher),
      ],
      child: AppBootstrap(
        runtime: AppRuntime.configured(
          auth,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(AppShell));
  return ProviderScope.containerOf(context);
}

void addProducts(
  ProviderContainer container,
  Iterable<String> productIds,
) {
  final order = container.read(orderControllerProvider.notifier);
  var amount = 1000;
  for (final productId in productIds) {
    order.addProduct(
      testProduct(
        id: productId,
        nameEn: 'Brand ${productId.toUpperCase()}',
        sellingAmount: amount,
      ),
    );
    amount += 1000;
  }
}

void main() {
  test('provider attribution falls back to the official HTTPS homepage', () {
    expect(
      ddiProviderAttributionUri(const InteractionAttribution()).toString(),
      'https://interaction-checker.com',
    );
    expect(
      ddiProviderAttributionUri(
        InteractionAttribution(
          url: Uri.parse('mailto:example@example.com'),
        ),
      ).toString(),
      'https://interaction-checker.com',
    );
    expect(
      ddiProviderAttributionUri(
        InteractionAttribution(
          url: Uri.parse('https://interaction-checker.com/api'),
        ),
      ).toString(),
      'https://interaction-checker.com/api',
    );
  });

  testWidgets(
    'severity badge opens evidence source attribution and disclaimer details',
    (tester) async {
      final launcher = _FakeLinkLauncher();
      final gateway = _Gateway(
        (productIds, isCurrent) async => _analysis(
          productIds: productIds,
          pairs: [
            _pair(
              'a',
              'b',
              InteractionSeverity.major,
              interactions: [
                _interaction(
                  1,
                  'Alpha',
                  2,
                  'Beta',
                  severity: InteractionSeverity.major,
                  severityLabel: 'Major',
                  quote:
                      'Synthetic label evidence for Alpha and Beta.',
                ),
              ],
            ),
          ],
        ),
      );
      final container = await pumpDetailApp(
        tester,
        gateway: gateway,
        linkLauncher: launcher,
      );

      addProducts(container, ['a', 'b']);
      await tester.pumpAndSettle();

      expect(container.read(orderControllerProvider).totalSyp, 3000);
      await tester.tap(find.byKey(const Key('ddi-row-severity-a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ddi-detail-sheet')), findsOneWidget);
      expect(find.text('Brand A ↔ Brand B'), findsOneWidget);
      expect(find.text('Alpha ↔ Beta'), findsOneWidget);
      expect(
        find.text('Synthetic label evidence for Alpha and Beta.'),
        findsOneWidget,
      );
      expect(find.text('Drug interactions'), findsOneWidget);
      expect(find.text('Synthetic FDA label'), findsOneWidget);
      expect(
        find.textContaining('FDA label · Effective 2026-01-02'),
        findsOneWidget,
      );

      await tester.tap(find.text('Open source'));
      await tester.pump();
      expect(
        launcher.opened.single,
        Uri.parse('https://dailymed.nlm.nih.gov/test'),
      );

      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not medical advice.'), findsOneWidget);
      expect(find.text('Data from Interaction Checker'), findsOneWidget);
      expect(find.text('Free with attribution'), findsOneWidget);
      expect(
        find.textContaining('Label export 2026-09-03'),
        findsOneWidget,
      );

      await tester.tap(find.text('Interaction Checker').last);
      await tester.pump();
      expect(
        launcher.opened.last,
        Uri.parse('https://interaction-checker.com'),
      );

      await tester.tap(find.byKey(const Key('ddi-detail-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ddi-detail-sheet')), findsNothing);
      expect(container.read(orderControllerProvider).lines, hasLength(2));
      expect(container.read(orderControllerProvider).totalSyp, 3000);
    },
  );

  testWidgets('link launch failure keeps sheet open and shows feedback', (
    tester,
  ) async {
    final launcher = _FakeLinkLauncher(result: false);
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        productIds: productIds,
        pairs: [
          _pair(
            'a',
            'b',
            InteractionSeverity.moderate,
            interactions: [
              _interaction(
                1,
                'Alpha',
                2,
                'Beta',
                severity: InteractionSeverity.moderate,
                severityLabel: 'Moderate',
                quote: 'Synthetic evidence.',
              ),
            ],
          ),
        ],
      ),
    );
    final container = await pumpDetailApp(
      tester,
      gateway: gateway,
      linkLauncher: launcher,
    );

    addProducts(container, ['a', 'b']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ddi-row-severity-a')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(
      find.text('Could not open this source link.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ddi-detail-sheet')), findsOneWidget);
    expect(container.read(orderControllerProvider).totalSyp, 3000);
  });

  testWidgets('unknown and none details do not invent evidence or safety', (
    tester,
  ) async {
    final launcher = _FakeLinkLauncher();
    final gateway = _Gateway(
      (productIds, isCurrent) async => _analysis(
        productIds: productIds,
        pairs: [
          _pair(
            'a',
            'b',
            InteractionSeverity.unknown,
            interactions: [
              _interaction(
                1,
                'Alpha',
                2,
                'Beta',
                severity: InteractionSeverity.unknown,
                severityLabel: 'Unknown',
              ),
            ],
          ),
          _pair(
            'a',
            'c',
            InteractionSeverity.none,
            interactions: [
              _interaction(
                1,
                'Alpha',
                3,
                'Gamma',
                severity: InteractionSeverity.none,
                severityLabel: 'None',
              ),
            ],
          ),
        ],
      ),
    );
    final container = await pumpDetailApp(
      tester,
      gateway: gateway,
      linkLauncher: launcher,
    );

    addProducts(container, ['a', 'b', 'c']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ddi-row-severity-a')));
    await tester.pumpAndSettle();

    expect(find.text('Brand A ↔ Brand B'), findsOneWidget);
    expect(find.text('Brand A ↔ Brand C'), findsOneWidget);
    expect(
      find.text(
        'No label evidence was returned for this ingredient pair.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'No clinically significant interaction was reported by the provider for this ingredient pair.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('stop'), findsNothing);
    expect(find.textContaining('dose'), findsNothing);
  });
}

class _Gateway implements DdiAnalysisGateway {
  _Gateway(this.handler);

  final Future<DdiAnalysisResult> Function(
    List<String> productIds,
    bool Function()? isCurrent,
  ) handler;

  @override
  Future<DdiAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) {
    return handler(productIds, isCurrent);
  }
}

class _FakeLinkLauncher implements DdiExternalLinkLauncher {
  _FakeLinkLauncher({
    this.result = true,
  });

  final bool result;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

DdiAnalysisResult _analysis({
  required List<String> productIds,
  required List<DdiProductPairInteraction> pairs,
}) {
  return DdiAnalysisResult(
    products: [
      for (var index = 0; index < productIds.length; index++)
        _trustedProduct(productIds[index], index + 1),
    ],
    providerUnresolved: const [],
    productPairs: pairs,
    providerNotices: [_notice()],
    uniqueIngredientCount: productIds.length,
    providerBatchCount: 1,
  );
}

DdiProductIngredientInput _trustedProduct(
  String productId,
  int ingredientId,
) {
  return DdiProductIngredientInput(
    productId: productId,
    requestPosition: ingredientId,
    coverageStatus: DdiIngredientCoverageStatus.trusted,
    productExists: true,
    normalizationStatus: 'auto_verified',
    componentCount: 1,
    resolvedComponentCount: 1,
    ingredients: [
      DdiIngredientIdentity(
        id: ingredientId,
        name: 'Ingredient $productId',
        normalizedName: 'ingredient $productId',
      ),
    ],
  );
}

DdiProductPairInteraction _pair(
  String a,
  String b,
  InteractionSeverity severity, {
  List<DdiIngredientInteraction> interactions = const [],
}) {
  return DdiProductPairInteraction(
    productAId: a,
    productBId: b,
    severity: severity,
    ingredientInteractions: interactions,
  );
}

DdiIngredientInteraction _interaction(
  int aId,
  String aName,
  int bId,
  String bName, {
  required InteractionSeverity severity,
  required String severityLabel,
  String? quote,
}) {
  return DdiIngredientInteraction(
    ingredientA: DdiIngredientIdentity(
      id: aId,
      name: aName,
      normalizedName: aName.toLowerCase(),
    ),
    ingredientB: DdiIngredientIdentity(
      id: bId,
      name: bName,
      normalizedName: bName.toLowerCase(),
    ),
    severity: severity,
    severityLabel: severityLabel,
    evidence: quote == null
        ? const []
        : [
            InteractionEvidence(
              from: aName,
              about: bName,
              section: InteractionEvidenceSection.drugInteractions,
              sectionLabel: 'Drug interactions',
              severity: switch (severity) {
                InteractionSeverity.major =>
                  InteractionEvidenceSeverity.major,
                InteractionSeverity.moderate =>
                  InteractionEvidenceSeverity.moderate,
                InteractionSeverity.minor =>
                  InteractionEvidenceSeverity.minor,
                InteractionSeverity.none =>
                  InteractionEvidenceSeverity.none,
                InteractionSeverity.unknown =>
                  InteractionEvidenceSeverity.none,
              },
              quote: quote,
              matchedTerm: bName.toLowerCase(),
              matchKind: InteractionMatchKind.name,
              source: InteractionEvidenceSource(
                type: InteractionSourceType.fdaLabel,
                name: 'Synthetic FDA label',
                url: Uri.parse(
                  'https://dailymed.nlm.nih.gov/test',
                ),
                effectiveDate: DateTime.utc(2026, 1, 2),
              ),
            ),
          ],
    interactionUrl: Uri.parse(
      'https://interaction-checker.com/?d=$aName,$bName',
    ),
    detailPage: Uri.parse(
      'https://interaction-checker.com/interactions/test',
    ),
  );
}

DdiProviderNotice _notice() {
  return DdiProviderNotice(
    data: InteractionCheckData(
      labelExportDate: DateTime.utc(2026, 9, 3),
      generatedAt: DateTime.utc(2026, 9, 7),
    ),
    disclaimer: 'Not medical advice.',
    attribution: InteractionAttribution(
      text: 'Data from Interaction Checker',
      url: Uri.parse('https://interaction-checker.com'),
      license: 'Free with attribution',
    ),
  );
}
