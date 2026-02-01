import 'package:bcrypt/bcrypt.dart';

class PasswordHasher {
  const PasswordHasher();

  String hash(String password) {
    final salt = BCrypt.gensalt(); // default cost = 10
    return BCrypt.hashpw(password, salt);
  }

  bool verify(String password, String hash) {
    return BCrypt.checkpw(password, hash);
  }
}
