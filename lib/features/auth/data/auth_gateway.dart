import '../domain/auth_identity.dart';

abstract interface class AuthGateway {
  AuthIdentity? get currentIdentity;

  Stream<AuthIdentity?> get identityChanges;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

final class AuthOperationException implements Exception {
  const AuthOperationException();
}
