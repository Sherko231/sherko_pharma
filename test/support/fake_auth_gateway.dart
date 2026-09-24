import 'dart:async';

import 'package:sherko_pharma/features/auth/data/auth_gateway.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    AuthIdentity? initialIdentity,
  }) : _identity = initialIdentity;

  AuthIdentity? _identity;
  final _changes = StreamController<AuthIdentity?>.broadcast();

  bool failSignIn = false;
  bool failSignOut = false;
  Completer<void>? signInGate;
  Completer<void>? signOutGate;
  int signInCalls = 0;
  int signOutCalls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  AuthIdentity? get currentIdentity => _identity;

  @override
  Stream<AuthIdentity?> get identityChanges => _changes.stream;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    lastEmail = email;
    lastPassword = password;

    final gate = signInGate;
    if (gate != null) {
      await gate.future;
    }
    if (failSignIn) {
      throw const AuthOperationException();
    }

    _identity = AuthIdentity(
      userId: 'owner-user-id',
      email: email,
    );
    _changes.add(_identity);
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    final gate = signOutGate;
    if (gate != null) {
      await gate.future;
    }
    if (failSignOut) {
      throw const AuthOperationException();
    }

    _identity = null;
    _changes.add(null);
  }

  void emitIdentity(AuthIdentity? identity) {
    _identity = identity;
    _changes.add(identity);
  }

  Future<void> dispose() {
    return _changes.close();
  }
}
