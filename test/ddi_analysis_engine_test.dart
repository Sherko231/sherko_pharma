import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sherko_pharma/features/interactions/application/ddi_analysis_engine.dart';
import 'package:sherko_pharma/features/interactions/data/ddi_ingredient_repository.dart';
import 'package:sherko_pharma/features/interactions/data/interaction_checker_client.dart';
import 'package:sherko_pharma/features/interactions/domain/ddi_analysis_models.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';

void main() {
  group('DdiAnalysisEngine', () {
    test('does not call provider for same-product-only ingredients', () async {
      final gateway = _FakeGateway((items) async {
        return _providerResult(items);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted(
            'p1',
            [
              _ingredient(1, 'Alpha'),
              _ingredient(2, 'Beta'),
            ],
          ),
        }),
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(const ['p1']);

      expect(result.uniqueIngredientCount, 2);
      expect(result.providerBatchCount, 0);
      expect(result.productPairs, isEmpty);
      expect(gateway.calls, isEmpty);
    });

    test('maps one ingredient interaction back to the product pair', () async {
      final repository = _FakeIngredientRepository({
        'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
        'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
      });
      final gateway = _FakeGateway((items) async {
        return _providerResult(
          items,
          severities: {
            _queryPairKey('Alpha', 'Beta'):
                InteractionSeverity.moderate,
          },
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        const ['p1', 'p2'],
      );

      expect(gateway.calls, hasLength(1));
      expect(result.productPairs, hasLength(1));
      final pair = result.productPairs.single;
      expect(pair.productAId, 'p1');
      expect(pair.productBId, 'p2');
      expect(pair.severity, InteractionSeverity.moderate);
      expect(pair.ingredientInteractions, hasLength(1));
      expect(pair.ingredientInteractions.single.ingredientA.name, 'Alpha');
      expect(pair.ingredientInteractions.single.ingredientB.name, 'Beta');
      expect(pair.ingredientInteractions.single.evidence, hasLength(1));
      expect(result.providerNotices, hasLength(1));
    });

    test('combination product excludes same-product-only pairs and aggregates severity', () async {
      final repository = _FakeIngredientRepository({
        'p1': _trusted(
          'p1',
          [
            _ingredient(1, 'Alpha'),
            _ingredient(2, 'Beta'),
          ],
        ),
        'p2': _trusted('p2', [_ingredient(3, 'Gamma')]),
      });
      final gateway = _FakeGateway((items) async {
        return _providerResult(
          items,
          severities: {
            _queryPairKey('Alpha', 'Beta'):
                InteractionSeverity.major,
            _queryPairKey('Alpha', 'Gamma'):
                InteractionSeverity.minor,
            _queryPairKey('Beta', 'Gamma'):
                InteractionSeverity.moderate,
          },
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        const ['p1', 'p2'],
      );

      expect(result.productPairs, hasLength(1));
      final pair = result.productPairs.single;
      expect(pair.severity, InteractionSeverity.moderate);
      expect(pair.ingredientInteractions, hasLength(2));
      expect(
        pair.ingredientInteractions.any(
          (item) =>
              item.ingredientA.name == 'Alpha' &&
              item.ingredientB.name == 'Beta',
        ),
        isFalse,
      );
      expect(
        pair.ingredientInteractions
            .expand((item) => item.evidence)
            .length,
        2,
      );
    });

    test('deduplicates shared ingredient queries and maps to all owners', () async {
      final repository = _FakeIngredientRepository({
        'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
        'p2': _trusted(
          'p2',
          [
            _ingredient(1, 'Alpha'),
            _ingredient(2, 'Beta'),
          ],
        ),
        'p3': _trusted('p3', [_ingredient(3, 'Gamma')]),
      });
      final gateway = _FakeGateway((items) async {
        return _providerResult(items);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        const ['p1', 'p2', 'p3'],
      );

      expect(gateway.calls.single.where((item) => item == 'Alpha'), hasLength(1));
      final p2p3 = result.productPairs.singleWhere(
        (pair) => pair.productAId == 'p2' && pair.productBId == 'p3',
      );
      expect(p2p3.ingredientInteractions, hasLength(2));
    });

    test('11 ingredients get complete pair coverage with three <=10 batches', () async {
      final products = <String, DdiProductIngredientInput>{};
      for (var index = 1; index <= 11; index++) {
        products['p' + index.toString()] = _trusted(
          'p' + index.toString(),
          [_ingredient(index, 'I' + index.toString())],
        );
      }
      final gateway = _FakeGateway((items) async {
        return _providerResult(items);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository(products),
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        products.keys.toList(growable: false),
      );

      expect(gateway.calls, hasLength(3));
      expect(gateway.calls.every((batch) => batch.length <= 10), isTrue);
      expect(result.providerBatchCount, 3);
      expect(result.productPairs, hasLength(55));

      final names = List<String>.generate(
        11,
        (index) => 'I' + (index + 1).toString(),
      );
      for (var left = 0; left < names.length; left++) {
        for (var right = left + 1; right < names.length; right++) {
          final covered = gateway.calls.any(
            (batch) =>
                batch.contains(names[left]) &&
                batch.contains(names[right]),
          );
          expect(
            covered,
            isTrue,
            reason: 'Missing provider coverage for ' +
                names[left] +
                ' / ' +
                names[right],
          );
        }
      }
    });

    test('keeps normalization and provider unresolved states distinct', () async {
      final repository = _FakeIngredientRepository({
        'review': _coverage(
          'review',
          DdiIngredientCoverageStatus.needsReview,
        ),
        'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
        'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
      });
      final gateway = _FakeGateway((items) async {
        return _providerResult(
          items,
          unresolvedQueries: const {'Beta'},
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        const ['review', 'p1', 'p2'],
      );

      expect(
        result.products.first.coverageStatus,
        DdiIngredientCoverageStatus.needsReview,
      );
      expect(result.providerUnresolved, hasLength(1));
      expect(result.providerUnresolved.single.query, 'Beta');
      expect(result.providerUnresolved.single.productIds, ['p2']);
      expect(result.providerUnresolved.single.suggestions, hasLength(1));
      expect(result.productPairs, isEmpty);
    });

    test('coalesces identical in-flight batches and caches success', () async {
      final completer = Completer<InteractionCheckResult>();
      final gateway = _FakeGateway((items) => completer.future);
      final repository = _FakeIngredientRepository({
        'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
        'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final first = engine.analyzeProductIds(const ['p1', 'p2']);
      final second = engine.analyzeProductIds(const ['p1', 'p2']);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.calls, hasLength(1));
      completer.complete(_providerResult(gateway.calls.single));
      await Future.wait([first, second]);

      await engine.analyzeProductIds(const ['p1', 'p2']);
      expect(gateway.calls, hasLength(1));
    });

    test('retries one valid 429 after Retry-After and then caches', () async {
      final clock = _FakeClock();
      var attempts = 0;
      final gateway = _FakeGateway((items) async {
        attempts += 1;
        if (attempts == 1) {
          throw const InteractionCheckerRateLimitException(
            retryAfter: Duration(seconds: 30),
            providerCode: 'rate_limited',
          );
        }
        return _providerResult(items);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
        }),
        interactionGateway: gateway,
        now: clock.now,
        sleep: clock.sleep,
      );

      await engine.analyzeProductIds(const ['p1', 'p2']);

      expect(attempts, 2);
      expect(clock.sleeps, [const Duration(seconds: 30)]);
      await engine.analyzeProductIds(const ['p1', 'p2']);
      expect(attempts, 2);
    });

    test('propagates a second 429 instead of retrying repeatedly', () async {
      final clock = _FakeClock();
      final gateway = _FakeGateway((items) async {
        throw const InteractionCheckerRateLimitException(
          retryAfter: Duration(seconds: 1),
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
        }),
        interactionGateway: gateway,
        now: clock.now,
        sleep: clock.sleep,
      );

      await expectLater(
        engine.analyzeProductIds(const ['p1', 'p2']),
        throwsA(isA<InteractionCheckerRateLimitException>()),
      );

      expect(gateway.calls, hasLength(2));
      expect(clock.sleeps, [const Duration(seconds: 1)]);
    });

    test('self-throttles before exceeding the configured request window', () async {
      final clock = _FakeClock();
      final products = <String, DdiProductIngredientInput>{};
      for (var index = 1; index <= 11; index++) {
        products['p' + index.toString()] = _trusted(
          'p' + index.toString(),
          [_ingredient(index, 'I' + index.toString())],
        );
      }
      final gateway = _FakeGateway((items) async {
        return _providerResult(items);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository(products),
        interactionGateway: gateway,
        maxRequestsPerWindow: 2,
        rateWindow: const Duration(minutes: 1),
        now: clock.now,
        sleep: clock.sleep,
      );

      await engine.analyzeProductIds(
        products.keys.toList(growable: false),
      );

      expect(gateway.calls, hasLength(3));
      expect(clock.sleeps, contains(const Duration(minutes: 1)));
    });

    test('stale generation discards an in-flight response and stops later batches', () async {
      final products = <String, DdiProductIngredientInput>{};
      for (var index = 1; index <= 11; index++) {
        products['p' + index.toString()] = _trusted(
          'p' + index.toString(),
          [_ingredient(index, 'I' + index.toString())],
        );
      }

      final completer = Completer<InteractionCheckResult>();
      final gateway = _FakeGateway((items) => completer.future);
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository(products),
        interactionGateway: gateway,
      );
      var current = true;

      final analysis = engine.analyzeProductIds(
        products.keys.toList(growable: false),
        isCurrent: () => current,
      );
      await Future<void>.delayed(Duration.zero);

      expect(gateway.calls, hasLength(1));
      current = false;
      completer.complete(_providerResult(gateway.calls.single));

      await expectLater(
        analysis,
        throwsA(isA<DdiAnalysisSupersededException>()),
      );
      expect(gateway.calls, hasLength(1));
    });

    test('unknown outranks none without becoming a safe result', () async {
      final repository = _FakeIngredientRepository({
        'p1': _trusted(
          'p1',
          [
            _ingredient(1, 'Alpha'),
            _ingredient(2, 'Beta'),
          ],
        ),
        'p2': _trusted('p2', [_ingredient(3, 'Gamma')]),
      });
      final gateway = _FakeGateway((items) async {
        return _providerResult(
          items,
          severities: {
            _queryPairKey('Alpha', 'Gamma'):
                InteractionSeverity.none,
            _queryPairKey('Beta', 'Gamma'):
                InteractionSeverity.unknown,
          },
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
      );

      final result = await engine.analyzeProductIds(
        const ['p1', 'p2'],
      );

      expect(result.productPairs.single.severity, InteractionSeverity.unknown);
      expect(result.productPairs.single.ingredientInteractions, hasLength(2));
    });

    test('bounded cache evicts the least-recent successful batch', () async {
      final gateway = _FakeGateway((items) async {
        return _providerResult(items);
      });
      final repository = _FakeIngredientRepository({
        'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
        'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
        'p3': _trusted('p3', [_ingredient(3, 'Gamma')]),
        'p4': _trusted('p4', [_ingredient(4, 'Delta')]),
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: gateway,
        cacheMaxEntries: 1,
      );

      await engine.analyzeProductIds(const ['p1', 'p2']);
      await engine.analyzeProductIds(const ['p3', 'p4']);
      await engine.analyzeProductIds(const ['p1', 'p2']);

      expect(gateway.calls, hasLength(3));
    });

    test('rejects success response that omits a resolved provider pair', () async {
      final gateway = _FakeGateway((items) async {
        final complete = _providerResult(items);
        return _copyResult(
          complete,
          pairs: complete.pairs.take(2).toList(growable: false),
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
          'p3': _trusted('p3', [_ingredient(3, 'Gamma')]),
        }),
        interactionGateway: gateway,
      );

      await expectLater(
        engine.analyzeProductIds(const ['p1', 'p2', 'p3']),
        throwsA(isA<DdiAnalysisMappingException>()),
      );
    });

    test('rejects duplicate pair substituted for another resolved pair', () async {
      final gateway = _FakeGateway((items) async {
        final complete = _providerResult(items);
        return _copyResult(
          complete,
          pairs: [
            complete.pairs[0],
            complete.pairs[0],
            complete.pairs[2],
          ],
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
          'p3': _trusted('p3', [_ingredient(3, 'Gamma')]),
        }),
        interactionGateway: gateway,
      );

      await expectLater(
        engine.analyzeProductIds(const ['p1', 'p2', 'p3']),
        throwsA(isA<DdiAnalysisMappingException>()),
      );
    });

    test('rejects distinct ingredient queries resolving to one provider substance', () async {
      final gateway = _FakeGateway((items) async {
        final complete = _providerResult(items);
        return InteractionCheckResult(
          items: [
            ResolvedInteractionItem(
              substance: _substance('Shared'),
              query: 'Alpha',
            ),
            ResolvedInteractionItem(
              substance: _substance('Shared'),
              query: 'Beta',
            ),
          ],
          unresolved: const [],
          pairs: const [],
          summary: const {
            InteractionSeverity.major: 0,
            InteractionSeverity.moderate: 0,
            InteractionSeverity.minor: 0,
            InteractionSeverity.none: 0,
            InteractionSeverity.unknown: 0,
          },
          data: complete.data,
          disclaimer: complete.disclaimer,
          attribution: complete.attribution,
        );
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
        }),
        interactionGateway: gateway,
      );

      await expectLater(
        engine.analyzeProductIds(const ['p1', 'p2']),
        throwsA(isA<DdiAnalysisMappingException>()),
      );
    });

    test('rejects provider summary that contradicts returned pair severities', () async {
      final gateway = _FakeGateway((items) async {
        final complete = _providerResult(
          items,
          severities: {
            _queryPairKey('Alpha', 'Beta'):
                InteractionSeverity.major,
          },
        );
        final summary = Map<InteractionSeverity, int>.from(
          complete.summary,
        );
        summary[InteractionSeverity.major] = 0;
        return _copyResult(complete, summary: summary);
      });
      final engine = DdiAnalysisEngine(
        ingredientRepository: _FakeIngredientRepository({
          'p1': _trusted('p1', [_ingredient(1, 'Alpha')]),
          'p2': _trusted('p2', [_ingredient(2, 'Beta')]),
        }),
        interactionGateway: gateway,
      );

      await expectLater(
        engine.analyzeProductIds(const ['p1', 'p2']),
        throwsA(isA<DdiAnalysisMappingException>()),
      );
    });

    test('chunks more than 50 product IDs for the bounded ingredient RPC', () async {
      final products = <String, DdiProductIngredientInput>{};
      for (var index = 1; index <= 51; index++) {
        products['p' + index.toString()] = _coverage(
          'p' + index.toString(),
          DdiIngredientCoverageStatus.unresolved,
        );
      }
      final repository = _FakeIngredientRepository(products);
      final engine = DdiAnalysisEngine(
        ingredientRepository: repository,
        interactionGateway: _FakeGateway((items) async {
          return _providerResult(items);
        }),
      );

      final result = await engine.analyzeProductIds(
        products.keys.toList(growable: false),
      );

      expect(repository.calls.map((call) => call.length), [50, 1]);
      expect(result.products, hasLength(51));
      expect(result.uniqueIngredientCount, 0);
    });
  });
}

class _FakeIngredientRepository implements DdiIngredientRepository {
  _FakeIngredientRepository(this.products);

  final Map<String, DdiProductIngredientInput> products;
  final List<List<String>> calls = [];

  @override
  Future<List<DdiProductIngredientInput>> resolveProducts(
    List<String> productIds,
  ) async {
    calls.add(List.unmodifiable(productIds));
    return productIds
        .map((id) => products[id]!)
        .toList(growable: false);
  }
}

class _FakeGateway implements InteractionCheckGateway {
  _FakeGateway(this.handler);

  final Future<InteractionCheckResult> Function(List<String> items) handler;
  final List<List<String>> calls = [];

  @override
  Future<InteractionCheckResult> checkInteractions(
    List<String> items,
  ) {
    final captured = List<String>.unmodifiable(items);
    calls.add(captured);
    return handler(captured);
  }
}

class _FakeClock {
  DateTime current = DateTime.utc(2026, 9, 29, 12);
  final List<Duration> sleeps = [];

  DateTime now() => current;

  Future<void> sleep(Duration duration) async {
    sleeps.add(duration);
    current = current.add(duration);
  }
}

DdiIngredientIdentity _ingredient(int id, String name) {
  return DdiIngredientIdentity(
    id: id,
    name: name,
    normalizedName: name.toLowerCase(),
  );
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
    ingredients: List.unmodifiable(ingredients),
  );
}

DdiProductIngredientInput _coverage(
  String productId,
  DdiIngredientCoverageStatus status,
) {
  return DdiProductIngredientInput(
    productId: productId,
    requestPosition: 1,
    coverageStatus: status,
    productExists: status != DdiIngredientCoverageStatus.missing,
    normalizationStatus: status.name,
    componentCount: null,
    resolvedComponentCount: null,
    ingredients: const [],
  );
}

InteractionCheckResult _providerResult(
  List<String> items, {
  Map<String, InteractionSeverity> severities = const {},
  Set<String> unresolvedQueries = const {},
}) {
  final resolvedQueries = items
      .where((item) => !unresolvedQueries.contains(item))
      .toList(growable: false);

  final resolvedItems = resolvedQueries
      .map(
        (query) => ResolvedInteractionItem(
          substance: _substance(query),
          query: query,
        ),
      )
      .toList(growable: false);

  final unresolved = unresolvedQueries
      .where(items.contains)
      .map(
        (query) => UnresolvedInteractionItem(
          query: query,
          suggestions: [
            InteractionSubstance(
              id: 'suggested:' + query,
              name: query + ' suggestion',
              kind: InteractionSubstanceKind.drug,
              url: Uri.parse(
                'https://interaction-checker.com/drugs/suggestion',
              ),
            ),
          ],
        ),
      )
      .toList(growable: false);

  final summary = <InteractionSeverity, int>{
    for (final severity in InteractionSeverity.values) severity: 0,
  };
  final pairs = <InteractionPair>[];

  for (var left = 0; left < resolvedQueries.length; left++) {
    for (var right = left + 1; right < resolvedQueries.length; right++) {
      final a = resolvedQueries[left];
      final b = resolvedQueries[right];
      final severity =
          severities[_queryPairKey(a, b)] ?? InteractionSeverity.none;
      summary[severity] = summary[severity]! + 1;
      pairs.add(
        InteractionPair(
          a: _substance(a),
          b: _substance(b),
          severity: severity,
          severityLabel: severity.name,
          url: Uri.parse(
            'https://interaction-checker.com/?d=' + a + ',' + b,
          ),
          evidence: severity == InteractionSeverity.unknown
              ? const []
              : [_evidence(a, b, severity)],
        ),
      );
    }
  }

  return InteractionCheckResult(
    items: resolvedItems,
    unresolved: unresolved,
    pairs: pairs,
    summary: summary,
    data: InteractionCheckData(
      labelExportDate: DateTime.utc(2026, 9, 3),
      generatedAt: DateTime.utc(2026, 9, 7),
    ),
    disclaimer: 'Not medical advice.',
    attribution: InteractionAttribution(
      text: 'Interaction Checker',
      url: Uri.parse('https://interaction-checker.com'),
      license: 'Free with attribution',
    ),
  );
}

InteractionCheckResult _copyResult(
  InteractionCheckResult source, {
  List<InteractionPair>? pairs,
  Map<InteractionSeverity, int>? summary,
}) {
  return InteractionCheckResult(
    items: source.items,
    unresolved: source.unresolved,
    pairs: pairs ?? source.pairs,
    summary: summary ?? source.summary,
    data: source.data,
    disclaimer: source.disclaimer,
    attribution: source.attribution,
  );
}

InteractionSubstance _substance(String query) {
  return InteractionSubstance(
    id: 'substance:' + query,
    name: query,
    kind: InteractionSubstanceKind.drug,
    url: Uri.parse(
      'https://interaction-checker.com/drugs/' + query.toLowerCase(),
    ),
  );
}

InteractionEvidence _evidence(
  String from,
  String about,
  InteractionSeverity pairSeverity,
) {
  final severity = switch (pairSeverity) {
    InteractionSeverity.major => InteractionEvidenceSeverity.major,
    InteractionSeverity.moderate => InteractionEvidenceSeverity.moderate,
    InteractionSeverity.minor => InteractionEvidenceSeverity.minor,
    InteractionSeverity.none => InteractionEvidenceSeverity.none,
    InteractionSeverity.unknown => InteractionEvidenceSeverity.none,
  };

  return InteractionEvidence(
    from: from,
    about: about,
    section: InteractionEvidenceSection.drugInteractions,
    sectionLabel: 'Drug interactions',
    severity: severity,
    quote: 'Synthetic fixture evidence for ' + from + ' / ' + about,
    matchedTerm: about.toLowerCase(),
    matchKind: InteractionMatchKind.name,
    source: InteractionEvidenceSource(
      type: InteractionSourceType.fdaLabel,
      name: 'Synthetic label',
      url: Uri.parse('https://dailymed.nlm.nih.gov/dailymed/test'),
    ),
  );
}

String _queryPairKey(String left, String right) {
  return left.compareTo(right) <= 0
      ? left + '|' + right
      : right + '|' + left;
}
