import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_gateway.dart';
import '../domain/auth_identity.dart';

enum AuthStatus {
  signedOut,
  signedIn,
}

class AuthViewState {
  const AuthViewState._({
    required this.status,
    required this.isSubmitting,
    this.identity,
    this.errorMessage,
  });

  const AuthViewState.signedOut({
    bool isSubmitting = false,
    String? errorMessage,
  }) : this._(
          status: AuthStatus.signedOut,
          isSubmitting: isSubmitting,
          errorMessage: errorMessage,
        );

  const AuthViewState.signedIn(AuthIdentity identity)
      : this._(
          status: AuthStatus.signedIn,
          isSubmitting: false,
          identity: identity,
        );

  final AuthStatus status;
  final bool isSubmitting;
  final AuthIdentity? identity;
  final String? errorMessage;
}

final authGatewayProvider = Provider<AuthGateway>((ref) {
  throw StateError('AuthGateway was not configured for this runtime.');
});

class AuthController extends Notifier<AuthViewState> {
  static const String signInErrorMessage =
      'Sign-in failed. Check your email, password, and connection.';
  static const String sessionEndedMessage =
      'Your session ended. Sign in again to continue.';
  static const String signOutErrorMessage =
      'Sign-out could not be confirmed. Sign in again to continue.';

  bool _forceSignedOut = false;
  StreamSubscription<AuthIdentity?>? _subscription;

  @override
  AuthViewState build() {
    final gateway = ref.watch(authGatewayProvider);
    _subscription = gateway.identityChanges.listen(
      _handleIdentityChange,
      onError: (error, stackTrace) {
        _forceSignedOut = true;
        state = const AuthViewState.signedOut(
          errorMessage: sessionEndedMessage,
        );
      },
    );
    ref.onDispose(() {
      _subscription?.cancel();
    });

    final identity = gateway.currentIdentity;
    return identity == null
        ? const AuthViewState.signedOut()
        : AuthViewState.signedIn(identity);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    if (state.isSubmitting || state.status == AuthStatus.signedIn) {
      return;
    }

    state = const AuthViewState.signedOut(isSubmitting: true);
    final gateway = ref.read(authGatewayProvider);

    try {
      await gateway.signInWithPassword(
        email: email,
        password: password,
      );
      final identity = gateway.currentIdentity;
      if (identity == null) {
        throw const AuthOperationException();
      }

      _forceSignedOut = false;
      state = AuthViewState.signedIn(identity);
    } catch (_) {
      state = const AuthViewState.signedOut(
        errorMessage: signInErrorMessage,
      );
    }
  }

  Future<void> signOut() async {
    if (state.status == AuthStatus.signedOut && _forceSignedOut) {
      return;
    }

    _forceSignedOut = true;
    state = const AuthViewState.signedOut();
    final gateway = ref.read(authGatewayProvider);

    try {
      await gateway.signOut();
    } catch (_) {
      state = const AuthViewState.signedOut(
        errorMessage: signOutErrorMessage,
      );
    }
  }

  void _handleIdentityChange(AuthIdentity? identity) {
    if (_forceSignedOut) {
      return;
    }

    state = identity == null
        ? const AuthViewState.signedOut(
            errorMessage: sessionEndedMessage,
          )
        : AuthViewState.signedIn(identity);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthViewState>(
  AuthController.new,
);
