import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../navigation/application/app_navigation_controller.dart';
import '../../order/application/order_controller.dart';
import '../../order/domain/order_model.dart';
import '../data/app_session_store.dart';

enum AppSessionStatus {
  signedOut,
  restoring,
  ready,
}

class AppSessionViewState {
  const AppSessionViewState._({
    required this.status,
    this.ownerId,
    this.errorMessage,
  });

  const AppSessionViewState.signedOut({
    String? errorMessage,
  }) : this._(
          status: AppSessionStatus.signedOut,
          errorMessage: errorMessage,
        );

  const AppSessionViewState.restoring(String ownerId)
      : this._(
          status: AppSessionStatus.restoring,
          ownerId: ownerId,
        );

  const AppSessionViewState.ready(
    String ownerId, {
    String? errorMessage,
  }) : this._(
          status: AppSessionStatus.ready,
          ownerId: ownerId,
          errorMessage: errorMessage,
        );

  final AppSessionStatus status;
  final String? ownerId;
  final String? errorMessage;
}

class AppSessionController extends Notifier<AppSessionViewState> {
  static const String persistenceErrorMessage =
      'Local session storage failed. The current page or order may not survive a restart.';
  static const String restoreErrorMessage =
      'The saved local session could not be restored safely. An empty local session was opened instead.';

  int _identityGeneration = 0;
  String? _activeOwnerId;
  String? _lastSignedOutOwnerId;
  bool _suppressPersistence = true;
  Future<void> _writeChain = Future<void>.value();
  final Map<String, String> _ownerErrors = {};

  @override
  AppSessionViewState build() {
    final initialOwnerId =
        ref.read(authControllerProvider).identity?.userId;
    _activeOwnerId = initialOwnerId;
    _suppressPersistence = true;

    ref.listen<String?>(
      authControllerProvider.select((auth) => auth.identity?.userId),
      (previous, next) {
        _handleIdentityChange(next);
      },
    );
    ref.listen<OrderState>(
      orderControllerProvider,
      (previous, next) {
        _persistCurrentState();
      },
    );
    ref.listen<AppDestination>(
      appNavigationControllerProvider,
      (previous, next) {
        _persistCurrentState();
      },
    );

    if (initialOwnerId == null) {
      return const AppSessionViewState.signedOut();
    }

    final generation = ++_identityGeneration;
    Future<void>.microtask(
      () => _restore(initialOwnerId, generation),
    );
    return AppSessionViewState.restoring(initialOwnerId);
  }

  void prepareForSignOut() {
    final ownerId = _activeOwnerId;
    if (ownerId == null || _suppressPersistence) {
      return;
    }

    _lastSignedOutOwnerId = ownerId;
    _queueSnapshot(_snapshotFor(ownerId));
    _suppressPersistence = true;
    _clearProtectedMemory();
  }

  void retryPersistence() {
    final ownerId = _activeOwnerId;
    if (ownerId == null ||
        _suppressPersistence ||
        state.status != AppSessionStatus.ready) {
      return;
    }
    _queueSnapshot(_snapshotFor(ownerId));
  }

  Future<void> waitForPendingWrites() {
    return _writeChain;
  }

  void _handleIdentityChange(String? ownerId) {
    if (ownerId == _activeOwnerId) {
      return;
    }

    final previousOwner = _activeOwnerId;
    if (previousOwner != null && !_suppressPersistence) {
      _lastSignedOutOwnerId = previousOwner;
      _queueSnapshot(_snapshotFor(previousOwner));
    }

    final generation = ++_identityGeneration;
    _suppressPersistence = true;
    _activeOwnerId = ownerId;
    _clearProtectedMemory();

    if (ownerId == null) {
      state = AppSessionViewState.signedOut(
        errorMessage: _errorFor(_lastSignedOutOwnerId),
      );
      return;
    }

    state = AppSessionViewState.restoring(ownerId);
    unawaited(_restore(ownerId, generation));
  }

  void _clearProtectedMemory() {
    ref.read(orderControllerProvider.notifier).replaceForSession(
          const OrderState(),
        );
    ref
        .read(appNavigationControllerProvider.notifier)
        .restoreForSession(AppDestination.catalog);
  }

  Future<void> _restore(
    String ownerId,
    int generation,
  ) async {
    final store = ref.read(appSessionStoreProvider);
    AppSessionSnapshot? snapshot;
    try {
      snapshot = await store.load(ownerId: ownerId);
    } catch (_) {
      _ownerErrors[ownerId] = restoreErrorMessage;
    }

    if (!ref.mounted ||
        generation != _identityGeneration ||
        _activeOwnerId != ownerId) {
      return;
    }

    final resolved = snapshot ??
        AppSessionSnapshot(
          ownerId: ownerId,
          destination: AppDestination.catalog,
          order: const OrderState(),
        );

    ref
        .read(orderControllerProvider.notifier)
        .replaceForSession(resolved.order);
    ref
        .read(appNavigationControllerProvider.notifier)
        .restoreForSession(resolved.destination);

    _suppressPersistence = false;
    state = AppSessionViewState.ready(
      ownerId,
      errorMessage: _ownerErrors[ownerId],
    );
  }

  void _persistCurrentState() {
    final ownerId = _activeOwnerId;
    if (ownerId == null ||
        _suppressPersistence ||
        state.status != AppSessionStatus.ready) {
      return;
    }

    _queueSnapshot(_snapshotFor(ownerId));
  }

  AppSessionSnapshot _snapshotFor(String ownerId) {
    return AppSessionSnapshot(
      ownerId: ownerId,
      destination: ref.read(appNavigationControllerProvider),
      order: ref.read(orderControllerProvider),
    );
  }

  void _queueSnapshot(AppSessionSnapshot snapshot) {
    final store = ref.read(appSessionStoreProvider);
    final operation = _writeChain.then(
      (_) => store.save(snapshot),
    );
    _writeChain = operation.catchError((_) {});
    unawaited(_observeWrite(operation, snapshot.ownerId));
  }

  Future<void> _observeWrite(
    Future<void> operation,
    String ownerId,
  ) async {
    try {
      await operation;
      _ownerErrors.remove(ownerId);
    } catch (_) {
      _ownerErrors[ownerId] = persistenceErrorMessage;
    }

    if (!ref.mounted) {
      return;
    }

    if (_activeOwnerId == ownerId &&
        state.status == AppSessionStatus.ready) {
      state = AppSessionViewState.ready(
        ownerId,
        errorMessage: _ownerErrors[ownerId],
      );
      return;
    }

    if (_activeOwnerId == null && _lastSignedOutOwnerId == ownerId) {
      state = AppSessionViewState.signedOut(
        errorMessage: _ownerErrors[ownerId],
      );
    }
  }

  String? _errorFor(String? ownerId) {
    if (ownerId == null) {
      return null;
    }
    return _ownerErrors[ownerId];
  }
}

final appSessionControllerProvider =
    NotifierProvider<AppSessionController, AppSessionViewState>(
  AppSessionController.new,
);
