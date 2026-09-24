import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_identity.dart';
import 'auth_gateway.dart';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this.client);

  final SupabaseClient client;

  @override
  AuthIdentity? get currentIdentity {
    return _identityFromSession(client.auth.currentSession);
  }

  @override
  Stream<AuthIdentity?> get identityChanges {
    return client.auth.onAuthStateChange.map((data) {
      return _identityFromSession(data.session);
    }).distinct();
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (_identityFromSession(response.session) == null) {
      throw const AuthOperationException();
    }
  }

  @override
  Future<void> signOut() {
    return client.auth.signOut(scope: SignOutScope.local);
  }

  AuthIdentity? _identityFromSession(Session? session) {
    if (session == null || session.isExpired) {
      return null;
    }

    return AuthIdentity(
      userId: session.user.id,
      email: session.user.email,
    );
  }
}
