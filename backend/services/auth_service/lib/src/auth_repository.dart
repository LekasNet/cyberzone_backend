import 'package:postgres/postgres.dart';
import 'models.dart';

class AuthRepository {
  final PostgreSQLConnection _conn;

  AuthRepository(this._conn);

  Future<AuthUser?> findByEmail(String email) async {
    final result = await _conn.query(
      'SELECT id, email, password_hash '
          'FROM users WHERE email = @email',
      substitutionValues: {'email': email},
    );

    if (result.isEmpty) return null;

    final row = result.first;

    return AuthUser(
      id: row[0].toString(),
      email: row[1] as String,
      passwordHash: row[2] as String,
    );
  }

  Future<AuthUser?> findById(String id) async {
    final result = await _conn.query(
      'SELECT id, email, password_hash '
          'FROM users WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return AuthUser(
      id: row[0].toString(),
      email: row[1] as String,
      passwordHash: row[2] as String,
    );
  }


  Future<AuthUser> createUser({
    required String id,
    required String email,
    required String passwordHash,
  }) async {
    await _conn.query(
      'INSERT INTO users (id, email, password_hash) '
          'VALUES (@id, @email, @password_hash)',
      substitutionValues: {
        'id': id,
        'email': email,
        'password_hash': passwordHash,
      },
    );

    return AuthUser(
      id: id,
      email: email,
      passwordHash: passwordHash,
    );
  }

  Future<void> deleteById(String id) async {
    await _conn.query(
      'DELETE FROM users WHERE id = @id',
      substitutionValues: {'id': id},
    );
  }
}
