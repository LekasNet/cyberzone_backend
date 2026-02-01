import 'package:postgres/postgres.dart';
import 'models.dart';

class AuthRepository {
  final PostgreSQLConnection _conn;

  AuthRepository(this._conn);

  Future<User?> findByEmail(String email) async {
    final result = await _conn.query(
      'SELECT id, email, password_hash, is_admin, is_super_admin, is_banned '
          'FROM users WHERE email = @email',
      substitutionValues: {'email': email},
    );

    if (result.isEmpty) return null;

    final row = result.first;

    return User(
      id: row[0].toString(),
      email: row[1] as String,
      passwordHash: row[2] as String,
      isAdmin: row[3] as bool,
      isSuperAdmin: row[4] as bool,
      isBanned: row[5] as bool,
    );
  }

  Future<User?> findById(String id) async {
    final result = await _conn.query(
      'SELECT id, email, password_hash, is_admin, is_super_admin, is_banned '
          'FROM users WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return User(
      id: row[0].toString(),
      email: row[1] as String,
      passwordHash: row[2] as String,
      isAdmin: row[3] as bool,
      isSuperAdmin: row[4] as bool,
      isBanned: row[5] as bool,
    );
  }


  Future<User> createUser({
    required String id,
    required String email,
    required String passwordHash,
  }) async {
    await _conn.query(
      'INSERT INTO users (id, email, password_hash, is_admin, is_super_admin, is_banned) '
          'VALUES (@id, @email, @password_hash, false, false, false)',
      substitutionValues: {
        'id': id,
        'email': email,
        'password_hash': passwordHash,
      },
    );

    return User(
      id: id,
      email: email,
      passwordHash: passwordHash,
      isAdmin: false,
      isSuperAdmin: false,
      isBanned: false,
    );
  }
}
