import 'dart:async';
import 'dart:collection';

import '../data/ddi_ingredient_repository.dart';
import '../data/interaction_checker_client.dart';
import '../data/interaction_checker_query_resolver.dart';
import '../domain/ddi_analysis_models.dart';
import '../domain/interaction_check_models.dart';

typedef DdiNow = DateTime Function();
typedef DdiSleep = Future<void> Function(Duration duration);

abstract interface class DdiAnalysisGateway {
  Future<DdiAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  });
}

class DdiAnalysisEngine implements DdiAnalysisGateway {
  DdiAnalysisEngine({
    required this.ingredientRepository,
    required this.interactionGateway,
    this.cacheMaxEntries = 128,
    this.cacheTtl = const Duration(hours: 1),
    this.maxRequestsPerWindow = 10,
    this.rateWindow = const Duration(minutes: 1),
    DdiProviderQueryResolver? providerQueryResolver,
    DdiNow? now,
    DdiSleep? sleep,
  })  : _providerQueryResolver =
            providerQueryResolver ?? resolveInteractionCheckerQuery,
        _now = now ?? _utcNow,
        _sleep = sleep ?? _defaultSleep {
    if (cacheMaxEntries < 1) {
      throw ArgumentError.value(
        cacheMaxEntries,
        'cacheMaxEntries',
        'Must be positive.',
      );
    }
    if (cacheTtl <= Duration.zero) {
      throw ArgumentError.value(
        cacheTtl,
        'cacheTtl',
        'Must be positive.',
      );
    }
    if (maxRequestsPerWindow < 1) {
      throw ArgumentError.value(
        maxRequestsPerWindow,
        'maxRequestsPerWindow',
        'Must be positive.',
      );
    }
    if (rateWindow <= Duration.zero) {
      throw ArgumentError.value(
        rateWindow,
        'rateWindow',
        'Must be positive.',
      );
    }
  }

  final DdiIngredientRepository ingredientRepository;
  final InteractionCheckGateway interactionGateway;
  final int cacheMaxEntries;
  final Duration cacheTtl;
  final int maxRequestsPerWindow;
  final Duration rateWindow;
  final DdiProviderQueryResolver _providerQueryResolver;
  final DdiNow _now;
  final DdiSleep _sleep;

  final LinkedHashMap<String, _CachedBatch> _cache = LinkedHashMap();
  final Map<String, Future<InteractionCheckResult>> _inFlight = {};
  final Queue<DateTime> _requestTimes = Queue<DateTime>();
  Future<void> _serialTail = Future<void>.value();

  @override
  Future<DdiAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) async {
    final requestedProducts = _distinctProductIds(productIds);
    _ensureCurrent(isCurrent);

    final products = await _resolveProducts(
      requestedProducts,
      isCurrent: isCurrent,
    );
    _ensureCurrent(isCurrent);

    final providerBuild = _buildProviderInputs(products);
    final providerNodes =
        providerBuild.nodes.values.toList(growable: false)
          ..sort(
            (left, right) =>
                left.queryKey.compareTo(right.queryKey),
          );
    final mappingGaps = providerBuild.gaps.values
        .map((gap) => gap.toModel())
        .toList(growable: false)
      ..sort((left, right) {
        final ingredient =
            left.ingredient.id.compareTo(right.ingredient.id);
        return ingredient != 0
            ? ingredient
            : left.status.name.compareTo(right.status.name);
      });

    final representedProducts = <String>{
      for (final node in providerNodes) ...node.productIds,
    };
    if (providerNodes.length < 2 || representedProducts.length < 2) {
      return DdiAnalysisResult(
        products: List.unmodifiable(products),
        providerUnresolved: const [],
        providerMappingGaps: List.unmodifiable(mappingGaps),
        productPairs: const [],
        providerNotices: const [],
        uniqueIngredientCount: providerNodes.length,
        providerBatchCount: 0,
      );
    }

    _validateProviderQueries(providerNodes);

    final batches = _buildProviderBatches(providerNodes);
    final providerPairs = <String, _ProviderPairAccumulator>{};
    final providerUnresolved =
        <String, _ProviderUnresolvedAccumulator>{};
    final providerResolution = <String, _ProviderResolution>{};
    final notices = <String, DdiProviderNotice>{};

    for (final batch in batches) {
      _ensureCurrent(isCurrent);
      final result = await _checkBatch(
        batch.map((node) => node.query).toList(growable: false),
      );
      _ensureCurrent(isCurrent);

      _consumeBatch(
        batch: batch,
        result: result,
        providerPairs: providerPairs,
        providerUnresolved: providerUnresolved,
        providerResolution: providerResolution,
      );

      final notice = DdiProviderNotice(
        data: result.data,
        disclaimer: result.disclaimer,
        attribution: result.attribution,
      );
      notices[_noticeKey(notice)] = notice;
    }

    _ensureCurrent(isCurrent);

    final productPairs = _buildProductPairs(providerPairs);

    final unresolved = providerUnresolved.values
        .expand((value) => value.toModels())
        .toList(growable: false)
      ..sort(
        (left, right) => left.ingredient.id.compareTo(right.ingredient.id),
      );

    return DdiAnalysisResult(
      products: List.unmodifiable(products),
      providerUnresolved: List.unmodifiable(unresolved),
      providerMappingGaps: List.unmodifiable(mappingGaps),
      productPairs: List.unmodifiable(productPairs),
      providerNotices: List.unmodifiable(notices.values),
      uniqueIngredientCount: providerNodes.length,
      providerBatchCount: batches.length,
    );
  }

  Future<List<DdiProductIngredientInput>> _resolveProducts(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) async {
    final results = <DdiProductIngredientInput>[];

    for (var offset = 0; offset < productIds.length; offset += 50) {
      _ensureCurrent(isCurrent);
      final end = (offset + 50 < productIds.length)
          ? offset + 50
          : productIds.length;
      final chunk = productIds.sublist(offset, end);
      final resolved = await ingredientRepository.resolveProducts(chunk);
      _ensureCurrent(isCurrent);

      if (resolved.length != chunk.length) {
        throw const DdiAnalysisMappingException(
          'Ingredient repository did not return one product result per ID.',
        );
      }

      final byId = {
        for (final product in resolved) product.productId: product,
      };
      for (var index = 0; index < chunk.length; index++) {
        final product = byId[chunk[index]];
        if (product == null) {
          throw const DdiAnalysisMappingException(
            'Ingredient repository omitted a requested product.',
          );
        }
        results.add(
          DdiProductIngredientInput(
            productId: product.productId,
            requestPosition: offset + index + 1,
            coverageStatus: product.coverageStatus,
            productExists: product.productExists,
            normalizationStatus: product.normalizationStatus,
            componentCount: product.componentCount,
            resolvedComponentCount: product.resolvedComponentCount,
            ingredients: product.ingredients,
          ),
        );
      }
    }

    return results;
  }

  _ProviderInputBuild _buildProviderInputs(
    List<DdiProductIngredientInput> products,
  ) {
    final nodes = <String, _ProviderIngredientNode>{};
    final gaps = <String, _ProviderMappingGapAccumulator>{};

    for (final product in products) {
      if (!product.isTrusted) {
        continue;
      }

      for (final ingredient in product.ingredients) {
        if (ingredient.providerMappingStatus !=
            DdiProviderMappingStatus.mapped) {
          final gapKey =
              '${ingredient.id}:${ingredient.providerMappingStatus.name}';
          gaps
              .putIfAbsent(
                gapKey,
                () => _ProviderMappingGapAccumulator(
                  ingredient,
                  ingredient.providerMappingStatus,
                ),
              )
              .productIds
              .add(product.productId);
          continue;
        }

        final mappedProviderId =
            ingredient.providerSubstanceId?.trim();
        final query = mappedProviderId != null &&
                mappedProviderId.isNotEmpty
            ? mappedProviderId
            : _providerQueryResolver(ingredient);
        final queryKey = _providerQueryKey(query);

        final node = nodes.putIfAbsent(
          queryKey,
          () => _ProviderIngredientNode(
            query: query,
            queryKey: queryKey,
          ),
        );
        node.addOccurrence(product.productId, ingredient);
      }
    }

    return _ProviderInputBuild(nodes: nodes, gaps: gaps);
  }

  void _validateProviderQueries(
    List<_ProviderIngredientNode> providerNodes,
  ) {
    for (final node in providerNodes) {
      final query = node.query;
      if (query.isEmpty || query.length > 80) {
        throw DdiAnalysisInvalidIngredientException(
          ingredientId: node.firstIdentity.id,
          message:
              'Mapped provider query is outside provider input bounds.',
        );
      }
    }
  }

  List<List<_ProviderIngredientNode>> _buildProviderBatches(
    List<_ProviderIngredientNode> ingredients,
  ) {
    if (ingredients.length <= 10) {
      return [List.unmodifiable(ingredients)];
    }

    final groups = <List<_ProviderIngredientNode>>[];
    for (var offset = 0; offset < ingredients.length; offset += 5) {
      final end = (offset + 5 < ingredients.length)
          ? offset + 5
          : ingredients.length;
      groups.add(
        List.unmodifiable(ingredients.sublist(offset, end)),
      );
    }

    final batches = <List<_ProviderIngredientNode>>[];
    for (var left = 0; left < groups.length; left++) {
      for (var right = left + 1; right < groups.length; right++) {
        batches.add(
          List.unmodifiable([...groups[left], ...groups[right]]),
        );
      }
    }
    return batches;
  }

  void _consumeBatch({
    required List<_ProviderIngredientNode> batch,
    required InteractionCheckResult result,
    required Map<String, _ProviderPairAccumulator> providerPairs,
    required Map<String, _ProviderUnresolvedAccumulator>
        providerUnresolved,
    required Map<String, _ProviderResolution> providerResolution,
  }) {
    final byQuery = <String, _ProviderIngredientNode>{
      for (final node in batch) node.queryKey: node,
    };
    final seenQueries = <String>{};
    final byProviderSubstance = <String, _ProviderIngredientNode>{};

    for (final item in result.items) {
      final itemQueryKey = _providerQueryKey(item.query);
      final node = byQuery[itemQueryKey];
      if (node == null || !seenQueries.add(node.queryKey)) {
        throw const DdiAnalysisMappingException(
          'Provider resolved an unexpected or duplicate query.',
        );
      }
      if (providerResolution[node.queryKey] ==
          _ProviderResolution.unresolved) {
        throw const DdiAnalysisMappingException(
          'Provider resolution changed across overlapping batches.',
        );
      }
      providerResolution[node.queryKey] = _ProviderResolution.resolved;

      if (byProviderSubstance.containsKey(item.substance.id)) {
        throw const DdiAnalysisMappingException(
          'Distinct provider queries resolved to the same substance.',
        );
      }
      byProviderSubstance[item.substance.id] = node;
    }

    for (final item in result.unresolved) {
      final itemQueryKey = _providerQueryKey(item.query);
      final node = byQuery[itemQueryKey];
      if (node == null || !seenQueries.add(node.queryKey)) {
        throw const DdiAnalysisMappingException(
          'Provider returned an unexpected or duplicate unresolved query.',
        );
      }
      if (providerResolution[node.queryKey] ==
          _ProviderResolution.resolved) {
        throw const DdiAnalysisMappingException(
          'Provider resolution changed across overlapping batches.',
        );
      }
      providerResolution[node.queryKey] = _ProviderResolution.unresolved;

      final accumulator = providerUnresolved.putIfAbsent(
        node.queryKey,
        () => _ProviderUnresolvedAccumulator(node),
      );
      accumulator.addSuggestions(item.suggestions);
    }

    if (seenQueries.length != batch.length) {
      throw const DdiAnalysisMappingException(
        'Provider response omitted one or more submitted queries.',
      );
    }

    _validateProviderPairSet(result);

    for (final pair in result.pairs) {
      final nodeA = byProviderSubstance[pair.a.id];
      final nodeB = byProviderSubstance[pair.b.id];
      if (nodeA == null || nodeB == null) {
        throw const DdiAnalysisMappingException(
          'Provider pair could not be mapped to submitted ingredients.',
        );
      }

      final key = _providerPairKey(nodeA.queryKey, nodeB.queryKey);
      final accumulator = providerPairs.putIfAbsent(
        key,
        () => _ProviderPairAccumulator(
          nodeA.queryKey.compareTo(nodeB.queryKey) <= 0
              ? nodeA
              : nodeB,
          nodeA.queryKey.compareTo(nodeB.queryKey) <= 0
              ? nodeB
              : nodeA,
        ),
      );
      accumulator.addPair(pair);
    }
  }

  void _validateProviderPairSet(InteractionCheckResult result) {
    final expectedPairs = <String, int>{};
    for (var left = 0; left < result.items.length; left++) {
      for (var right = left + 1; right < result.items.length; right++) {
        final key = _providerPairKey(
          result.items[left].substance.id,
          result.items[right].substance.id,
        );
        expectedPairs[key] = (expectedPairs[key] ?? 0) + 1;
      }
    }

    final actualPairs = <String, int>{};
    final actualSeverityCounts = <InteractionSeverity, int>{
      for (final severity in InteractionSeverity.values) severity: 0,
    };
    for (final pair in result.pairs) {
      final key = _providerPairKey(pair.a.id, pair.b.id);
      actualPairs[key] = (actualPairs[key] ?? 0) + 1;
      actualSeverityCounts[pair.severity] =
          (actualSeverityCounts[pair.severity] ?? 0) + 1;
    }

    if (!_sameCountMap(expectedPairs, actualPairs)) {
      throw const DdiAnalysisMappingException(
        'Provider response did not return exactly every resolved pair.',
      );
    }

    for (final entry in result.summary.entries) {
      if ((actualSeverityCounts[entry.key] ?? 0) != entry.value) {
        throw const DdiAnalysisMappingException(
          'Provider summary contradicted returned pair severities.',
        );
      }
    }
  }

  List<DdiProductPairInteraction> _buildProductPairs(
    Map<String, _ProviderPairAccumulator> providerPairs,
  ) {
    final productPairs = <String, _ProductPairAccumulator>{};

    final sortedProviderPairs = providerPairs.values.toList()
      ..sort((left, right) => left.sortKey.compareTo(right.sortKey));

    for (final providerPair in sortedProviderPairs) {
      for (final productA in providerPair.a.productIds) {
        for (final productB in providerPair.b.productIds) {
          if (productA == productB) {
            continue;
          }

          final localA =
              providerPair.a.identitiesByProduct[productA] ?? const [];
          final localB =
              providerPair.b.identitiesByProduct[productB] ?? const [];
          for (final ingredientA in localA) {
            for (final ingredientB in localB) {
              if (ingredientA.id == ingredientB.id) {
                continue;
              }

              final orderedA = productA.compareTo(productB) <= 0
                  ? productA
                  : productB;
              final orderedB = productA.compareTo(productB) <= 0
                  ? productB
                  : productA;
              final key = '$orderedA\u0000$orderedB';
              final accumulator = productPairs.putIfAbsent(
                key,
                () => _ProductPairAccumulator(orderedA, orderedB),
              );
              accumulator.addInteraction(
                providerPair.toModel(ingredientA, ingredientB),
              );
            }
          }
        }
      }
    }

    final results = productPairs.values
        .map((value) => value.toModel())
        .toList(growable: false)
      ..sort((left, right) {
        final first = left.productAId.compareTo(right.productAId);
        return first != 0
            ? first
            : left.productBId.compareTo(right.productBId);
      });
    return results;
  }

  Future<InteractionCheckResult> _checkBatch(List<String> items) async {
    final keyItems = [...items]..sort();
    final key = keyItems.join('\u0000');
    final now = _now();

    final cached = _cache[key];
    if (cached != null) {
      if (cached.expiresAt.isAfter(now)) {
        _cache.remove(key);
        _cache[key] = cached;
        return cached.result;
      }
      _cache.remove(key);
    }

    final current = _inFlight[key];
    if (current != null) {
      return current;
    }

    final future = _runProviderRequest(List.unmodifiable(items));
    _inFlight[key] = future;
    try {
      final result = await future;
      _cache[key] = _CachedBatch(
        result: result,
        expiresAt: _now().add(cacheTtl),
      );
      while (_cache.length > cacheMaxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  Future<InteractionCheckResult> _runProviderRequest(
    List<String> items,
  ) {
    return _serialized(() async {
      var rateLimitRetryUsed = false;

      while (true) {
        await _acquireRateSlot();
        try {
          return await interactionGateway.checkInteractions(items);
        } on InteractionCheckerRateLimitException catch (error) {
          final retryAfter = error.retryAfter;
          if (rateLimitRetryUsed ||
              retryAfter == null ||
              retryAfter <= Duration.zero) {
            rethrow;
          }
          rateLimitRetryUsed = true;
          await _sleep(retryAfter);
        }
      }
    });
  }

  Future<void> _acquireRateSlot() async {
    while (true) {
      final now = _now();
      while (_requestTimes.isNotEmpty &&
          !_requestTimes.first.add(rateWindow).isAfter(now)) {
        _requestTimes.removeFirst();
      }

      if (_requestTimes.length < maxRequestsPerWindow) {
        _requestTimes.addLast(now);
        return;
      }

      final waitUntil = _requestTimes.first.add(rateWindow);
      final wait = waitUntil.difference(now);
      if (wait <= Duration.zero) {
        continue;
      }
      await _sleep(wait);
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _serialTail;
    final done = Completer<void>();
    _serialTail = done.future;

    return previous.then((_) => action()).whenComplete(() {
      if (!done.isCompleted) {
        done.complete();
      }
    });
  }

  List<String> _distinctProductIds(List<String> productIds) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in productIds) {
      final productId = raw.trim();
      if (productId.isEmpty) {
        throw const DdiAnalysisInvalidRequestException(
          'Product IDs must not be blank.',
        );
      }
      if (seen.add(productId)) {
        result.add(productId);
      }
    }
    return result;
  }

  void _ensureCurrent(bool Function()? isCurrent) {
    if (isCurrent != null && !isCurrent()) {
      throw const DdiAnalysisSupersededException();
    }
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  static Future<void> _defaultSleep(Duration duration) {
    return Future<void>.delayed(duration);
  }
}

sealed class DdiAnalysisException implements Exception {
  const DdiAnalysisException();
}

class DdiAnalysisInvalidRequestException extends DdiAnalysisException {
  const DdiAnalysisInvalidRequestException(this.message);

  final String message;
}

class DdiAnalysisInvalidIngredientException extends DdiAnalysisException {
  const DdiAnalysisInvalidIngredientException({
    required this.ingredientId,
    required this.message,
  });

  final int ingredientId;
  final String message;
}

class DdiAnalysisMappingException extends DdiAnalysisException {
  const DdiAnalysisMappingException(this.message);

  final String message;
}

class DdiAnalysisSupersededException extends DdiAnalysisException {
  const DdiAnalysisSupersededException();
}

enum _ProviderResolution {
  resolved,
  unresolved,
}

class _ProviderInputBuild {
  const _ProviderInputBuild({
    required this.nodes,
    required this.gaps,
  });

  final Map<String, _ProviderIngredientNode> nodes;
  final Map<String, _ProviderMappingGapAccumulator> gaps;
}

class _ProviderIngredientNode {
  _ProviderIngredientNode({
    required this.query,
    required this.queryKey,
  });

  final String query;
  final String queryKey;
  final Map<String, List<DdiIngredientIdentity>> identitiesByProduct = {};

  Iterable<String> get productIds => identitiesByProduct.keys;

  DdiIngredientIdentity get firstIdentity =>
      identitiesByProduct.values.first.first;

  void addOccurrence(
    String productId,
    DdiIngredientIdentity ingredient,
  ) {
    final identities = identitiesByProduct.putIfAbsent(
      productId,
      () => [],
    );
    if (!identities.any((item) => item.id == ingredient.id)) {
      identities.add(ingredient);
    }
  }
}

class _ProviderPairAccumulator {
  _ProviderPairAccumulator(this.a, this.b);

  final _ProviderIngredientNode a;
  final _ProviderIngredientNode b;
  InteractionSeverity? _severity;
  String? _severityLabel;
  Uri? _interactionUrl;
  Uri? _detailPage;
  final LinkedHashMap<String, InteractionEvidence> _evidence =
      LinkedHashMap();

  String get sortKey => '${a.queryKey}\u0000${b.queryKey}';

  void addPair(InteractionPair pair) {
    final currentSeverity = _severity;
    if (currentSeverity == null ||
        ddiSeverityRank(pair.severity) >
            ddiSeverityRank(currentSeverity)) {
      _severity = pair.severity;
      _severityLabel = pair.severityLabel;
      _interactionUrl = pair.url;
      _detailPage = pair.page;
    }

    for (final evidence in pair.evidence) {
      _evidence[_evidenceKey(evidence)] = evidence;
    }
  }

  DdiIngredientInteraction toModel(
    DdiIngredientIdentity ingredientA,
    DdiIngredientIdentity ingredientB,
  ) {
    return DdiIngredientInteraction(
      ingredientA: ingredientA,
      ingredientB: ingredientB,
      severity: _severity!,
      severityLabel: _severityLabel!,
      evidence: List.unmodifiable(_evidence.values),
      interactionUrl: _interactionUrl!,
      detailPage: _detailPage,
    );
  }
}

class _ProductPairAccumulator {
  _ProductPairAccumulator(this.productAId, this.productBId);

  final String productAId;
  final String productBId;
  final Map<String, DdiIngredientInteraction> _interactions = {};

  void addInteraction(DdiIngredientInteraction interaction) {
    final key = _ingredientPairKey(
      interaction.ingredientA.id,
      interaction.ingredientB.id,
    );
    _interactions[key] = interaction;
  }

  DdiProductPairInteraction toModel() {
    final interactions = _interactions.values.toList(growable: false)
      ..sort((left, right) {
        final first =
            left.ingredientA.id.compareTo(right.ingredientA.id);
        return first != 0
            ? first
            : left.ingredientB.id.compareTo(right.ingredientB.id);
      });

    var severity = InteractionSeverity.none;
    for (final interaction in interactions) {
      severity = higherDdiSeverity(severity, interaction.severity);
    }

    return DdiProductPairInteraction(
      productAId: productAId,
      productBId: productBId,
      severity: severity,
      ingredientInteractions: List.unmodifiable(interactions),
    );
  }
}

class _ProviderUnresolvedAccumulator {
  _ProviderUnresolvedAccumulator(this.node);

  final _ProviderIngredientNode node;
  final Map<String, InteractionSubstance> _suggestions = {};

  void addSuggestions(List<InteractionSubstance> suggestions) {
    for (final suggestion in suggestions) {
      _suggestions[suggestion.id] = suggestion;
    }
  }

  List<DdiProviderUnresolvedIngredient> toModels() {
    final byIngredient =
        <int, ({DdiIngredientIdentity ingredient, Set<String> products})>{};

    for (final entry in node.identitiesByProduct.entries) {
      for (final ingredient in entry.value) {
        final existing = byIngredient[ingredient.id];
        if (existing == null) {
          byIngredient[ingredient.id] = (
            ingredient: ingredient,
            products: {entry.key},
          );
        } else {
          existing.products.add(entry.key);
        }
      }
    }

    return byIngredient.values.map((entry) {
      final productIds = entry.products.toList(growable: false)..sort();
      return DdiProviderUnresolvedIngredient(
        ingredient: entry.ingredient,
        query: node.query,
        productIds: List.unmodifiable(productIds),
        suggestions: List.unmodifiable(_suggestions.values),
      );
    }).toList(growable: false);
  }
}

class _ProviderMappingGapAccumulator {
  _ProviderMappingGapAccumulator(
    this.ingredient,
    this.status,
  );

  final DdiIngredientIdentity ingredient;
  final DdiProviderMappingStatus status;
  final Set<String> productIds = {};

  DdiProviderMappingGap toModel() {
    final products = productIds.toList(growable: false)..sort();
    return DdiProviderMappingGap(
      ingredient: ingredient,
      status: status,
      productIds: List.unmodifiable(products),
    );
  }
}

class _CachedBatch {
  const _CachedBatch({
    required this.result,
    required this.expiresAt,
  });

  final InteractionCheckResult result;
  final DateTime expiresAt;
}

String _providerPairKey(String left, String right) {
  return left.compareTo(right) <= 0
      ? '$left\u0000$right'
      : '$right\u0000$left';
}

bool _sameCountMap(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

String _providerQueryKey(String query) => query.trim().toLowerCase();

String _ingredientPairKey(int left, int right) {
  final low = left < right ? left : right;
  final high = left < right ? right : left;
  return '$low:$high';
}

String _evidenceKey(InteractionEvidence evidence) {
  return [
    evidence.from,
    evidence.about,
    evidence.section.name,
    evidence.sectionLabel,
    evidence.severity.name,
    evidence.quote,
    evidence.matchedTerm,
    evidence.matchKind.name,
    evidence.source.type.name,
    evidence.source.name,
    evidence.source.url.toString(),
    evidence.source.effectiveDate?.toIso8601String() ?? '',
  ].join('\u0000');
}

String _noticeKey(DdiProviderNotice notice) {
  return [
    notice.data.labelExportDate?.toIso8601String() ?? '',
    notice.data.generatedAt?.toIso8601String() ?? '',
    notice.disclaimer,
    notice.attribution.text ?? '',
    notice.attribution.url?.toString() ?? '',
    notice.attribution.license ?? '',
  ].join('\u0000');
}
