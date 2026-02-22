import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class ApplicationRepository {
  final PostgreSQLConnection _conn;

  ApplicationRepository(this._conn);

  Future<List<EventApplicationRecord>> listForEvent(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, user_id, role_id, status, created_at '
      'FROM event_applications WHERE event_id = @event_id '
      'ORDER BY created_at',
      substitutionValues: {'event_id': eventId},
    );

    return rows.map(_mapApplication).toList();
  }

  Future<List<EventApplicationRecord>> listForUser({
    required String eventId,
    required String userId,
  }) async {
    final rows = await _conn.query(
      'SELECT id, event_id, user_id, role_id, status, created_at '
      'FROM event_applications '
      'WHERE event_id = @event_id AND user_id = @user_id '
      'ORDER BY created_at',
      substitutionValues: {'event_id': eventId, 'user_id': userId},
    );

    return rows.map(_mapApplication).toList();
  }

  Future<List<EventApplicationRecord>> createApplications({
    required String eventId,
    required String userId,
    required List<String> roleIds,
    required String status,
  }) async {
    final created = <EventApplicationRecord>[];

    await _conn.transaction((ctx) async {
      for (final roleId in roleIds) {
        final existing = await ctx.query(
          'SELECT id, event_id, user_id, role_id, status, created_at '
          'FROM event_applications '
          'WHERE event_id = @event_id AND user_id = @user_id AND role_id = @role_id',
          substitutionValues: {
            'event_id': eventId,
            'user_id': userId,
            'role_id': roleId,
          },
        );

        if (existing.isNotEmpty) {
          created.add(_mapApplication(existing.first));
          continue;
        }

        final id = const Uuid().v4();
        final rows = await ctx.query(
          'INSERT INTO event_applications (id, event_id, user_id, role_id, status) '
          'VALUES (@id, @event_id, @user_id, @role_id, @status) '
          'RETURNING id, event_id, user_id, role_id, status, created_at',
          substitutionValues: {
            'id': id,
            'event_id': eventId,
            'user_id': userId,
            'role_id': roleId,
            'status': status,
          },
        );

        created.add(_mapApplication(rows.first));
      }
    });

    return created;
  }

  Future<EventApplicationRecord?> updateStatus({
    required String eventId,
    required String applicationId,
    required String status,
  }) async {
    final rows = await _conn.query(
      'UPDATE event_applications '
      'SET status = @status, updated_at = NOW() '
      'WHERE id = @id AND event_id = @event_id '
      'RETURNING id, event_id, user_id, role_id, status, created_at',
      substitutionValues: {
        'id': applicationId,
        'event_id': eventId,
        'status': status,
      },
    );

    if (rows.isEmpty) return null;
    return _mapApplication(rows.first);
  }

  Future<bool> deleteApplication({
    required String eventId,
    required String applicationId,
    required String userId,
  }) async {
    final rows = await _conn.query(
      'DELETE FROM event_applications '
      'WHERE id = @id AND event_id = @event_id AND user_id = @user_id '
      'AND status = @status '
      'RETURNING id',
      substitutionValues: {
        'id': applicationId,
        'event_id': eventId,
        'user_id': userId,
        'status': 'pending',
      },
    );

    return rows.isNotEmpty;
  }

  EventApplicationRecord _mapApplication(List<dynamic> row) {
    return EventApplicationRecord(
      id: row[0].toString(),
      eventId: row[1].toString(),
      userId: row[2].toString(),
      roleId: row[3].toString(),
      status: row[4] as String,
      createdAt: row[5] as DateTime,
    );
  }
}
