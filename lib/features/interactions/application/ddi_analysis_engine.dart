import 'dart:async';
import 'dart:collection';

import '../data/ddi_ingredient_repository.dart';
import '../data/interaction_checker_client.dart';
import '../domain/ddi_analysis_models.dart';
import '../domain/interaction_check_models.dart';

typedef DdiNow = DateTime Function();
typedef DdiSleep = Future<void> Function(Duration duration);

abstract interface class DdiAnalysisGateway {
  @override
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
    this.maxRequestsPerWindow = 60,
    this.rateWindow = const Duration(minutes: 1),
    DdiNow? now,
    DdiSleep? sleep,
  })  : _now = now ?? _utcNow,
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
  final DdiNow _now;
  final DdiSleep _sleep;

  final LinkedHashMap<String, _CachedBatch> _cache = LinkedHashMap();
  final Map<String, Future<InteractionCheckResult>> _inFlight = {};
  final Queue<DateTime> _requestTimes = Queue<DateTime>();
  Future<void> _serialTail = Future<void>.value();

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

    final ingredientNodes = _buildIngredientNodes(products);
    final ingredients = ingredientNodes.values.toList(growable: false)
      ..sort((left, right) => left.identity.id.compareTo(right.identity.id));

    final representedProducts = <String>{
      for (final node in ingredients) ...node.productIds,
    };
    if (ingredients.length < 2 || representedProducts.length < 2) {
      return DdiAnalysisResult(
        products: List.unmodifiable(products),
        providerUnresolved: const [],
        productPairs: const [],
        providerNotices: const [],
        uniqueIngredientCount: ingredients.length,
        providerBatchCount: 0,
      );
    }

    _validateProviderQueries(ingredients);

    final batches = _buildProviderBatches(ingredients);
    final ingredientPairs = <String, _IngredientPairAccumulator>{};
    final providerUnresolved =
        <int, _ProviderUnresolvedAccumulator>{};
    final providerResolution = <int, _ProviderResolution>{};
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
        ingredientPairs: ingredientPairs,
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

    final productPairs = _buildProductPairs(
      ingredientPairs,
      ingredientNodes,
    );

    final unresolved = providerUnresolved.values
        .map((value) => value.toModel())
        .toList(growable: false)
      ..sort(
        (left, right) => left.ingredient.id.compareTo(right.ingredient.id),
      );

    return DdiAnalysisResult(
      products: List.unmodifiable(products),
      providerUnresolved: List.unmodifiable(unresolved),
      productPairs: List.unmodifiable(productPairs),
      providerNotices: List.unmodifiable(notices.values),
      uniqueIngredientCount: ingredients.length,
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

  Map<int, _IngredientNode> _buildIngredientNodes(
    List<DdiProductIngredientInput> products,
  ) {
    final nodes = <int, _IngredientNode>{};

    for (final product in products) {
      if (!product.isTrusted) {
        continue;
      }

      for (final ingredient in product.ingredients) {
        final existing = nodes[ingredient.id];
        if (existing == null) {
          nodes[ingredient.id] = _IngredientNode(
            identity: ingredient,
            productIds: {product.productId},
          );
          continue;
        }

        if (existing.identity.name != ingredient.name ||
            existing.identity.normalizedName !=
                ingredient.normalizedName) {
          throw const DdiAnalysisMappingException(
            'A stable ingredient ID mapped to inconsistent names.',
          );
        }
        existing.productIds.add(product.productId);
      }
    }

    return nodes;
  }

  void _validateProviderQueries(List<_IngredientNode> ingredients) {
    final queries = <String>{};
    for (final node in ingredients) {
      final query = node.query;
      if (query.isEmpty || query.length > 80) {
        throw DdiAnalysisInvalidIngredientException(
          ingredientId: node.identity.id,
          message:
              'Trusted ingredient name is outside provider input bounds.',
        );
      }
      if (!queries.add(query)) {
        throw const DdiAnalysisMappingException(
          'Two stable ingredient IDs share the same provider query.',
        );
      }
    }
  }

  List<List<_IngredientNode>> _buildProviderBatches(
    List<_IngredientNode> ingredients,
  ) {
    if (ingredients.length <= 10) {
      return [List.unmodifiable(ingredients)];
    }

    final groups = <List<_IngredientNode>>[];
    for (var offset = 0; offset < ingredients.length; offset += 5) {
      final end = (offset + 5 < ingredients.length)
          ? offset + 5
          : ingredients.length;
      groups.add(
        List.unmodifiable(ingredients.sublist(offset, end)),
      );
    }

    final batches = <List<_IngredientNode>>[];
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
    required List<_IngredientNode> batch,
    required InteractionCheckResult result,
    required Map<String, _IngredientPairAccumulator> ingredientPairs,
    required Map<int, _ProviderUnresolvedAccumulator> providerUnresolved,
    required Map<int, _ProviderResolution> providerResolution,
  }) {
    final byQuery = <String, _IngredientNode>{
      for (final node in batch) node.query: node,
    };
    final seenQueries = <String>{};
    final byProviderSubstance = <String, List<_IngredientNode>>{};

    for (final item in result.items) {
      final node = byQuery[item.query.trim()];
      if (node == null || !seenQueries.add(node.query)) {
        throw const DdiAnalysisMappingException(
          'Provider resolved an unexpected or duplicate query.',
        );
      }
      if (providerResolution[node.identity.id] ==
          _ProviderResolution.unresolved) {
        throw const DdiAnalysisMappingException(
          'Provider resolution changed across overlapping batches.',
        );
      }
      providerResolution[node.identity.id] = _ProviderResolution.resolved;
      byProviderSubstance
          .putIfAbsent(item.substance.id, () => [])
          .add(node);
    }

    for (final item in result.unresolved) {
      final node = byQuery[item.query.trim()];
      if (node == null || !seenQueries.add(node.query)) {
        throw const DdiAnalysisMappingException(
          'Provider returned an unexpected or duplicate unresolved query.',
        );
      }
      if (providerResolution[node.identity.id] ==
          _ProviderResolution.resolved) {
        throw const DdiAnalysisMappingException(
          'Provider resolution changed across overlapping batches.',
        );
      }
      providerResolution[node.identity.id] = _ProviderResolution.unresolved;

      final accumulator = providerUnresolved.putIfAbsent(
        node.identity.id,
        () => _ProviderUnresolvedAccumulator(node),
      );
      accumulator.addSuggestions(item.suggestions);
    }

    if (seenQueries.length != batch.length) {
      throw const DdiAnalysisMappingException(
        'Provider response omitted one or more submitted queries.',
      );
    }

    for (final pair in result.pairs) {
      final localA = byProviderSubstance[pair.a.id];
      final localB = byProviderSubstance[pair.b.id];
      if (localA == null || localB == null) {
        throw const DdiAnalysisMappingException(
          'Provider pair could not be mapped to submitted ingredients.',
        );
      }

      for (final nodeA in localA) {
        for (final nodeB in localB) {
          if (nodeA.identity.id == nodeB.identity.id) {
            continue;
          }
          final key = _ingredientPairKey(
            nodeA.identity.id,
            nodeB.identity.id,
          );
          final accumulator = ingredientPairs.putIfAbsent(
            key,
            () => _IngredientPairAccumulator(
              nodeA.identity.id < nodeB.identity.id ? nodeA : nodeB,
              nodeA.identity.id < nodeB.identity.id ? nodeB : nodeA,
            ),
          );
          accumulator.addPair(pair);
        }
      }
    }
  }

  List<DdiProductPairInteraction> _buildProductPairs(
    Map<String, _IngredientPairAccumulator> ingredientPairs,
    Map<int, _IngredientNode> ingredientNodes,
  ) {
    final productPairs = <String, _ProductPairAccumulator>{};

    final sortedIngredientPairs = ingredientPairs.values.toList()
      ..sort(
        (left, right) =>
            left.sortKey.compareTo(right.sortKey),
      );

    for (final ingredientPair in sortedIngredientPairs) {
      final interaction = ingredientPair.toModel();
      final ownersA = ingredientNodes[interaction.ingredientA.id]!.productIds;
      final ownersB = ingredientNodes[interaction.ingredientB.id]!.productIds;

      for (final productA in ownersA) {
        for (final productB in ownersB) {
          if (productA == productB) {
            continue;
          }
          final orderedA =
              productA.compareTo(productB) <= 0 ? productA : productB;
          final orderedB =
              productA.compareTo(productB) <= 0 ? productB : productA;
          final key = '$orderedA\u0000$orderedB';
          final accumulator = productPairs.putIfAbsent(
            key,
            () => _ProductPairAccumulator(orderedA, orderedB),
          );
          accumulator.addInteraction(interaction);
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

class _IngredientNode {
  _IngredientNode({
    required this.identity,
    required this.productIds,
  });

  final DdiIngredientIdentity identity;
  final Set<String> productIds;

  String get query => identity.name.trim();
}

class _IngredientPairAccumulator {
  _IngredientPairAccumulator(this.a, this.b);

  final _IngredientNode a;
  final _IngredientNode b;
  InteractionSeverity? _severity;
  String? _severityLabel;
  Uri? _interactionUrl;
  Uri? _detailPage;
  final LinkedHashMap<String, InteractionEvidence> _evidence =
      LinkedHashMap();

  String get sortKey =>
      '${a.identity.id.toString().padLeft(20, '0')}:'
      '${b.identity.id.toString().padLeft(20, '0')}';

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

  DdiIngredientInteraction toModel() {
    return DdiIngredientInteraction(
      ingredientA: a.identity,
      ingredientB: b.identity,
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

  final _IngredientNode node;
  final Map<String, InteractionSubstance> _suggestions = {};

  void addSuggestions(List<InteractionSubstance> suggestions) {
    for (final suggestion in suggestions) {
      _suggestions[suggestion.id] = suggestion;
    }
  }

  DdiProviderUnresolvedIngredient toModel() {
    final productIds = node.productIds.toList(growable: false)..sort();
    return DdiProviderUnresolvedIngredient(
      ingredient: node.identity,
      query: node.query,
      productIds: List.unmodifiable(productIds),
      suggestions: List.unmodifiable(_suggestions.values),
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
