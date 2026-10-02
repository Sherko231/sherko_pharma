import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../order/application/order_controller.dart';
import '../../order/domain/order_model.dart';
import '../../session/application/app_session_controller.dart';
import '../data/sdif_client.dart';
import '../data/sdif_scientific_identity_repository.dart';
import '../domain/sdif_cart_analysis_models.dart';
import 'ddi_cart_controller.dart';
import 'sdif_cart_analysis_engine.dart';
import 'sdif_result_aggregator.dart';
import 'sdif_reviewed_atc_bridge.dart';

enum SdifCartStatus {
  idle,
  loading,
  ready,
  error,
  unavailable,
}

enum SdifCartFailureKind {
  scientificInput,
  timeout,
  transport,
  provider,
  malformedResponse,
  mapping,
  unknown,
}

class SdifCartState {
  const SdifCartState._({
    required this.status,
    required this.productIds,
    this.analysis,
    this.failureKind,
  });

  const SdifCartState.idle({List<String> productIds = const []})
      : this._(
          status: SdifCartStatus.idle,
          productIds: productIds,
        );

  const SdifCartState.loading({required List<String> productIds})
      : this._(
          status: SdifCartStatus.loading,
          productIds: productIds,
        );

  const SdifCartState.ready({
    required List<String> productIds,
    required SdifCartAnalysisResult analysis,
  }) : this._(
          status: SdifCartStatus.ready,
          productIds: productIds,
          analysis: analysis,
        );

  const SdifCartState.error({
    required List<String> productIds,
    required SdifCartFailureKind failureKind,
  }) : this._(
          status: SdifCartStatus.error,
          productIds: productIds,
          failureKind: failureKind,
        );

  const SdifCartState.unavailable({required List<String> productIds})
      : this._(
          status: SdifCartStatus.unavailable,
          productIds: productIds,
        );

  final SdifCartStatus status;
  final List<String> productIds;
  final SdifCartAnalysisResult? analysis;
  final SdifCartFailureKind? failureKind;

  bool get canRetry => status == SdifCartStatus.error;
}

final sdifCartAnalysisGatewayProvider = Provider<SdifCartAnalysisGateway?>((ref) {
  if (!ref.watch(ddiRuntimeSelectionProvider).usesSdif) {
    return null;
  }

  final repository = ref.watch(sdifScientificIdentityRepositoryProvider);
  final bridge = ref.watch(sdifReviewedAtcBridgeProvider);
  final aggregator = ref.watch(sdifResultAggregatorProvider);
  if (repository == null || bridge == null || aggregator == null) {
    return null;
  }

  return SdifCartAnalysisEngine(
    scientificIdentityRepository: repository,
    reviewedAtcBridge: bridge,
    resultAggregator: aggregator,
  );
});

final sdifCartDebounceDurationProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 120),
);

class SdifCartController extends Notifier<SdifCartState> {
  int _generation = 0;
  Timer? _debounce;
  bool _disposeRegistered = false;

  @override
  SdifCartState build() {
    if (!_disposeRegistered) {
      _disposeRegistered = true;
      ref.onDispose(() {
        _generation += 1;
        _debounce?.cancel();
      });
    }

    final runtime = ref.watch(ddiRuntimeSelectionProvider);
    final generation = ++_generation;
    _debounce?.cancel();
    if (!runtime.usesSdif) {
      return const SdifCartState.idle();
    }

    final ownerId = ref.watch(
      authControllerProvider.select((auth) => auth.identity?.userId),
    );
    final session = ref.watch(
      appSessionControllerProvider.select(
        (state) => _SdifSessionSelection(
          status: state.status,
          ownerId: state.ownerId,
        ),
      ),
    );
    final productSet = ref.watch(
      orderControllerProvider.select(_selectSdifProductSet),
    );

    if (ownerId == null ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId) {
      return const SdifCartState.idle();
    }

    final productIds = productSet.ids;
    if (productIds.length < 2) {
      return SdifCartState.idle(productIds: productIds);
    }

    final gateway = ref.watch(sdifCartAnalysisGatewayProvider);
    if (gateway == null) {
      return SdifCartState.unavailable(productIds: productIds);
    }

    final debounce = ref.watch(sdifCartDebounceDurationProvider);
    _debounce = Timer(debounce, () {
      unawaited(
        _runAnalysis(
          gateway: gateway,
          ownerId: ownerId,
          productIds: productIds,
          generation: generation,
        ),
      );
    });

    return SdifCartState.loading(productIds: productIds);
  }

  void retry() {
    final current = state;
    if (!current.canRetry || current.productIds.length < 2) {
      return;
    }

    if (!ref.read(ddiRuntimeSelectionProvider).usesSdif) {
      return;
    }
    final ownerId = ref.read(authControllerProvider).identity?.userId;
    final session = ref.read(appSessionControllerProvider);
    final gateway = ref.read(sdifCartAnalysisGatewayProvider);
    if (ownerId == null ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId ||
        gateway == null) {
      return;
    }

    final selected = _selectSdifProductSet(ref.read(orderControllerProvider));
    if (!_sameSdifStrings(selected.ids, current.productIds)) {
      return;
    }

    final generation = ++_generation;
    _debounce?.cancel();
    state = SdifCartState.loading(productIds: current.productIds);
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
    required SdifCartAnalysisGateway gateway,
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
        isCurrent: () => _isCurrent(generation, ownerId, productIds),
      );
      if (!_isCurrent(generation, ownerId, productIds)) {
        return;
      }
      state = SdifCartState.ready(
        productIds: productIds,
        analysis: analysis,
      );
    } on SdifCartAnalysisSupersededException {
      return;
    } catch (error) {
      if (!_isCurrent(generation, ownerId, productIds)) {
        return;
      }
      state = SdifCartState.error(
        productIds: productIds,
        failureKind: _sdifFailureFor(error),
      );
    }
  }

  bool _isCurrent(
    int generation,
    String ownerId,
    List<String> productIds,
  ) {
    if (!ref.mounted ||
        generation != _generation ||
        !ref.read(ddiRuntimeSelectionProvider).usesSdif) {
      return false;
    }

    final authOwnerId = ref.read(authControllerProvider).identity?.userId;
    final session = ref.read(appSessionControllerProvider);
    if (authOwnerId != ownerId ||
        session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId) {
      return false;
    }

    final current = _selectSdifProductSet(ref.read(orderControllerProvider));
    return _sameSdifStrings(current.ids, productIds);
  }
}

final sdifCartControllerProvider =
    NotifierProvider<SdifCartController, SdifCartState>(
  SdifCartController.new,
);

SdifCartFailureKind _sdifFailureFor(Object error) {
  if (error is SdifScientificIdentityRepositoryException) {
    return SdifCartFailureKind.scientificInput;
  }
  if (error is SdifTimeoutException) {
    return SdifCartFailureKind.timeout;
  }
  if (error is SdifTransportException) {
    return SdifCartFailureKind.transport;
  }
  if (error is SdifApiException) {
    return SdifCartFailureKind.provider;
  }
  if (error is SdifMalformedResponseException ||
      error is SdifUnsupportedResponseValueException) {
    return SdifCartFailureKind.malformedResponse;
  }
  if (error is SdifInvalidRequestException ||
      error is SdifReviewedAtcBridgeException ||
      error is SdifResultAggregationException ||
      error is SdifCartAnalysisException) {
    return SdifCartFailureKind.mapping;
  }
  return SdifCartFailureKind.unknown;
}

_SdifCartProductSetSelection _selectSdifProductSet(OrderState order) {
  final seen = <String>{};
  final ids = <String>[];
  for (final line in order.lines) {
    if (seen.add(line.productId)) {
      ids.add(line.productId);
    }
  }
  return _SdifCartProductSetSelection(List.unmodifiable(ids));
}

class _SdifCartProductSetSelection {
  const _SdifCartProductSetSelection(this.ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) {
    return other is _SdifCartProductSetSelection &&
        _sameSdifStrings(ids, other.ids);
  }

  @override
  int get hashCode => Object.hashAll(ids);
}

class _SdifSessionSelection {
  const _SdifSessionSelection({
    required this.status,
    required this.ownerId,
  });

  final AppSessionStatus status;
  final String? ownerId;

  @override
  bool operator ==(Object other) {
    return other is _SdifSessionSelection &&
        other.status == status &&
        other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hash(status, ownerId);
}

bool _sameSdifStrings(List<String> left, List<String> right) {
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
