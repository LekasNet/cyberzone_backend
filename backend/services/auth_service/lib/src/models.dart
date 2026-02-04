class AuthUser {
  final String id;
  final String email;
  final String passwordHash;

  AuthUser({
    required this.id,
    required this.email,
    required this.passwordHash,
  });
}
