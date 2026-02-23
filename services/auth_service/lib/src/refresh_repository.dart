import 'package:postgres/postgres.dart';

class RefreshTokenRow {
  final String id;
  final String userId;
  final String tokenHash;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  RefreshTokenRow({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.expiresAt,
    required this.revokedAt,
  });
}

class RefreshRepository {
  final PostgreSQLConnection _conn;

  RefreshRepository(this._conn);

  Future<void> insert({
    required String id,
    required String userId,
    required String tokenHash,
    required DateTime expiresAt,
  }) async {
    await _conn.query(
      'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) '
          'VALUES (@id, @user_id, @token_hash, @expires_at)',
      substitutionValues: {
        'id': id,
        'user_id': userId,
        'token_hash': tokenHash,
        'expires_at': expiresAt.toUtc(),
      },
    );
  }

  Future<RefreshTokenRow?> findByHash(String tokenHash) async {
    final r = await _conn.query(
      'SELECT id, user_id, token_hash, expires_at, revoked_at '
          'FROM refresh_tokens WHERE token_hash = @h',
      substitutionValues: {'h': tokenHash},
    );
    if (r.isEmpty) return null;
    final row = r.first;
    return RefreshTokenRow(
      id: row[0].toString(),
      userId: row[1].toString(),
      tokenHash: row[2] as String,
      expiresAt: row[3] as DateTime,
      revokedAt: row[4] as DateTime?,
    );
  }

  Future<void> revoke(String id) async {
    await _conn.query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE id = @id',
      substitutionValues: {'id': id},
    );
  }

  Future<void> revokeAllForUser(String userId) async {
    await _conn.query(
      'UPDATE refresh_tokens SET revoked_at = now() '
          'WHERE user_id = @uid AND revoked_at IS NULL',
      substitutionValues: {'uid': userId},
    );
  }
}
