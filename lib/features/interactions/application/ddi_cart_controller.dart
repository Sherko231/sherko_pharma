import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../order/application/order_controller.dart';
import '../../order/domain/order_model.dart';
import '../../session/application/app_session_controller.dart';
import '../data/ddi_ingredient_repository.dart';
import '../data/interaction_checker_client.dart';
import '../domain/ddi_analysis_models.dart';
import 'ddi_analysis_engine.dart';

enum DdiCartStatus {
  idle,
  loading,
  ready,
  error,
  unavailable,
}

enum DdiCartFailureKind {
  ingredientData,
  timeout,
  transport,
  rateLimited,
  provider,
  malformedResponse,
  mapping,
  unknown,
}

class DdiCartState {
  const DdiCartState._({
    required this.status,
    required this.productIds,
    this.analysis,
    this.failureKind,
    this.retryAfter,
  });

  const DdiCartState.idle({
    List<String> productIds = const [],
  }) : this._(
          status: DdiCartStatus.idle,
          productIds: productIds,
        );

  const DdiCartState.loading({
    required List<String> productIds,
  }) : this._(
          status: DdiCartStatus.loading,
          productIds: productIds,
        );

  const DdiCartState.ready({
    required List<String> productIds,
    required DdiAnalysisResult analysis,
  }) : this._(
          status: DdiCartStatus.ready,
          productIds: productIds,
          analysis: analysis,
        );

  const DdiCartState.error({
    required List<String> productIds,
    required DdiCartFailureKind failureKind,
    Duration? retryAfter,
  }) : this._(
          status: DdiCartStatus.error,
          productIds: productIds,
          failureKind: failureKind,
          retryAfter: retryAfter,
        );

  const DdiCartState.unavailable({
    required List<String> productIds,
  }) : this._(
          status: DdiCartStatus.unavailable,
          productIds: productIds,
        );

  final DdiCartStatus status;
  final List<String> productIds;
  final DdiAnalysisResult? analysis;
  final DdiCartFailureKind? failureKind;
  final Duration? retryAfter;

  bool get canRetry => status == DdiCartStatus.error;
}

final ddiIngredientRepositoryProvider =
    Provider<DdiIngredientRepository?>((ref) => null);

final interactionCheckGatewayProvider =
    Provider<InteractionCheckGateway>((ref) {
  final client = InteractionCheckerClient();
  ref.onDispose(client.close);
  return client;
});

final ddiAnalysisGatewayProvider =
    Provider<DdiAnalysisGateway?>((ref) {
  final ingredientRepository = ref.watch(
    ddiIngredientRepositoryProvider,
  );
  if (ingredientRepository == null) {
    return null;
  }

  return DdiAnalysisEngine(
    ingredientRepository: ingredientRepository,
    interactionGateway: ref.watch(interactionCheckGatewayProvider),
  );
});

final ddiCartDebounceDurationProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 120),
);

class DdiCartController extends Notifier<DdiCartState> {
  int _generation = 0;
  Timer? _debounce;
  bool _disposeRegistered = false;

  @override
  DdiCartState build() {
    if (!_disposeRegistered) {
      _disposeRegistered = true;
      ref.onDispose(() {
        _generation += 1;
        _debounce?.cancel();
      });
    }

    final ownerId = ref.watch(
      authControllerProvider.select(
        (auth) => auth.identity?.userId,
      ),
    );
    final session = ref.watch(
      appSessionControllerProvider.select(
        (state) => _DdiSessionSelection(
          status: state.status,
          ownerId: state.ownerId,
        ),
      ),
    );
    final productSet = ref.watch(
      orderControllerProvider.select(_selectProductSet),
    );
    final gateway = ref.watch(ddiAnalysisGatewayProvider);
    final debounceDuration = ref.watch(
      ddiCartDebounceDurationProvider,
    );

    final generation = ++_generation;
    _debounce?.cancel();

    if (ownerId == null ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId) {
      return const DdiCartState.idle();
    }

    final productIds = productSet.ids;
    if (productIds.length < 2) {
      return DdiCartState.idle(productIds: productIds);
    }

    if (gateway == null) {
      return DdiCartState.unavailable(productIds: productIds);
    }

    _debounce = Timer(debounceDuration, () {
      unawaited(
        _runAnalysis(
          gateway: gateway,
          ownerId: ownerId,
          productIds: productIds,
          generation: generation,
        ),
      );
    });

    return DdiCartState.loading(productIds: productIds);
  }

  void retry() {
    final current = state;
    if (!current.canRetry || current.productIds.length < 2) {
      return;
    }

    final ownerId = ref.read(authControllerProvider).identity?.userId;
    final session = ref.read(appSessionControllerProvider);
    final gateway = ref.read(ddiAnalysisGatewayProvider);
    if (ownerId == null ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId ||
        gateway == null) {
      return;
    }

    final selected = _selectProductSet(
      ref.read(orderControllerProvider),
    );
    if (!_sameStrings(selected.ids, current.productIds)) {
      return;
    }

    final generation = ++_generation;
    _debounce?.cancel();
    state = DdiCartState.loading(
      productIds: current.productIds,
    );
    unawaited(
      _runAnalysis(
        gateway: gateway,
        ownerId: ownerId,
        productIds: current.productIds,
        generation: generation,
      ),
    );
  }

  Future<void> _runAnalysis({
    required DdiAnalysisGateway gateway,
    required String ownerId,
    required List<String> productIds,
    required int generation,
  }) async {
    if (!_isCurrent(generation, ownerId, productIds)) {
      return;
    }

    try {
      final analysis = await gateway.analyzeProductIds(
        productIds,
        isCurrent: () =>
            _isCurrent(generation, ownerId, productIds),
      );

      if (!_isCurrent(generation, ownerId, productIds)) {
        return;
      }

      state = DdiCartState.ready(
        productIds: productIds,
        analysis: analysis,
      );
    } on DdiAnalysisSupersededException {
      return;
    } catch (error) {
      if (!_isCurrent(generation, ownerId, productIds)) {
        return;
      }

      final failure = _failureFor(error);
      state = DdiCartState.error(
        productIds: productIds,
        failureKind: failure.kind,
        retryAfter: failure.retryAfter,
      );
    }
  }

  bool _isCurrent(
    int generation,
    String ownerId,
    List<String> productIds,
  ) {
    if (!ref.mounted || generation != _generation) {
      return false;
    }

    final authOwnerId =
        ref.read(authControllerProvider).identity?.userId;
    final session = ref.read(appSessionControllerProvider);
    if (authOwnerId != ownerId ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId) {
      return false;
    }

    final current = _selectProductSet(
      ref.read(orderControllerProvider),
    );
    return _sameStrings(current.ids, productIds);
  }
}

final ddiCartControllerProvider =
    NotifierProvider<DdiCartController, DdiCartState>(
  DdiCartController.new,
);

_CartProductSetSelection _selectProductSet(OrderState order) {
  final seen = <String>{};
  final ids = <String>[];

  for (final line in order.lines) {
    if (seen.add(line.productId)) {
      ids.add(line.productId);
    }
  }

  return _CartProductSetSelection(List.unmodifiable(ids));
}

class _CartProductSetSelection {
  const _CartProductSetSelection(this.ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) {
    return other is _CartProductSetSelection &&
        _sameStrings(ids, other.ids);
  }

  @override
  int get hashCode => Object.hashAll(ids);
}

class _DdiSessionSelection {
  const _DdiSessionSelection({
    required this.status,
    required this.ownerId,
  });

  final AppSessionStatus status;
  final String? ownerId;

  @override
  bool operator ==(Object other) {
    return other is _DdiSessionSelection &&
        other.status == status &&
        other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hash(status, ownerId);
}

class _DdiFailure {
  const _DdiFailure(
    this.kind, {
    this.retryAfter,
  });

  final DdiCartFailureKind kind;
  final Duration? retryAfter;
}

_DdiFailure _failureFor(Object error) {
  if (error is InteractionCheckerTimeoutException) {
    return const _DdiFailure(DdiCartFailureKind.timeout);
  }
  if (error is InteractionCheckerTransportException) {
    return const _DdiFailure(DdiCartFailureKind.transport);
  }
  if (error is InteractionCheckerRateLimitException) {
    return _DdiFailure(
      DdiCartFailureKind.rateLimited,
      retryAfter: error.retryAfter,
    );
  }
  if (error is InteractionCheckerApiException) {
    return const _DdiFailure(DdiCartFailureKind.provider);
  }
  if (error is InteractionCheckerMalformedResponseException ||
      error is InteractionCheckerUnsupportedResponseValueException) {
    return const _DdiFailure(
      DdiCartFailureKind.malformedResponse,
    );
  }
  if (error is DdiIngredientRepositoryException) {
    return const _DdiFailure(DdiCartFailureKind.ingredientData);
  }
  if (error is DdiAnalysisMappingException ||
      error is DdiAnalysisInvalidIngredientException ||
      error is DdiAnalysisInvalidRequestException) {
    return const _DdiFailure(DdiCartFailureKind.mapping);
  }
  return const _DdiFailure(DdiCartFailureKind.unknown);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
