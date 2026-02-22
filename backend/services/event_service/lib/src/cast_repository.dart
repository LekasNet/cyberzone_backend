import 'package:postgres/postgres.dart';

import 'models.dart';

class CastRepository {
  final PostgreSQLConnection _conn;

  CastRepository(this._conn);

  Future<List<EventCastRecord>> listForEvent(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, user_id, role_id '
      'FROM event_cast WHERE event_id = @event_id '
      'ORDER BY role_id',
      substitutionValues: {'event_id': eventId},
    );

    return rows.map(_mapCast).toList();
  }

  Future<void> replaceCast(String eventId, List<EventCastRecord> cast) async {
    await _conn.transaction((ctx) async {
      await ctx.query(
        'DELETE FROM event_cast WHERE event_id = @event_id',
        substitutionValues: {'event_id': eventId},
      );

      for (final entry in cast) {
        await ctx.query(
          'INSERT INTO event_cast (id, event_id, user_id, role_id) '
          'VALUES (@id, @event_id, @user_id, @role_id)',
          substitutionValues: {
            'id': entry.id,
            'event_id': entry.eventId,
            'user_id': entry.userId,
            'role_id': entry.roleId,
          },
        );
      }
    });
  }

  Future<bool> isUserInCast({
    required String eventId,
    required String userId,
  }) async {
    final rows = await _conn.query(
      'SELECT 1 FROM event_cast WHERE event_id = @event_id AND user_id = @user_id '
      'LIMIT 1',
      substitutionValues: {
        'event_id': eventId,
        'user_id': userId,
      },
    );
    return rows.isNotEmpty;
  }

  EventCastRecord _mapCast(List<dynamic> row) {
    return EventCastRecord(
      id: row[0].toString(),
      eventId: row[1].toString(),
      userId: row[2].toString(),
      roleId: row[3].toString(),
    );
  }
}
