import 'package:postgres/postgres.dart';

class NotificationRepository {
  final PostgreSQLConnection _conn;

  NotificationRepository(this._conn);

  Future<void> registerToken({
    required String id,
    required String userId,
    required String deviceToken,
    required String platform,
  }) async {
    await _conn.query(
      'INSERT INTO notifications_tokens (id, user_id, device_token, platform, last_used_at) '
      'VALUES (@id, @user_id, @device_token, @platform, now()) '
      'ON CONFLICT (device_token) DO UPDATE '
      'SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, last_used_at = now()',
      substitutionValues: {
        'id': id,
        'user_id': userId,
        'device_token': deviceToken,
        'platform': platform,
      },
    );
  }

  Future<int> unregisterToken({
    required String userId,
    required String deviceToken,
  }) async {
    final result = await _conn.query(
      'DELETE FROM notifications_tokens '
      'WHERE user_id = @user_id AND device_token = @device_token '
      'RETURNING id',
      substitutionValues: {
        'user_id': userId,
        'device_token': deviceToken,
      },
    );

    return result.length;
  }

  Future<List<String>> getTokensForUsers(List<String> userIds) async {
    if (userIds.isEmpty) return <String>[];

    final rows = await _conn.query(
      'SELECT device_token '
      'FROM notifications_tokens '
      'WHERE user_id = ANY(@user_ids)',
      substitutionValues: {'user_ids': userIds},
    );

    return rows.map((row) => row[0] as String).toList();
  }

  Future<void> touchTokens(List<String> deviceTokens) async {
    if (deviceTokens.isEmpty) return;

    await _conn.query(
      'UPDATE notifications_tokens '
      'SET last_used_at = now() '
      'WHERE device_token = ANY(@device_tokens)',
      substitutionValues: {'device_tokens': deviceTokens},
    );
  }
}
