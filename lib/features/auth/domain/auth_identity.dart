class AuthIdentity {
  const AuthIdentity({
    required this.userId,
    this.email,
  });

  final String userId;
  final String? email;

  @override
  bool operator ==(Object other) {
    return other is AuthIdentity &&
        other.userId == userId &&
        other.email == email;
  }

  @override
  int get hashCode => Object.hash(userId, email);
}
