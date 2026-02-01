class User {
  final String id;
  final String email;
  final String passwordHash;
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool isBanned;

  User({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.isBanned,
  });
}
