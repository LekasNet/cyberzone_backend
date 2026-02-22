import 'package:postgres/postgres.dart';

import 'models.dart';

class EventRepository {
  final PostgreSQLConnection _conn;

  EventRepository(this._conn);

  Future<EventRecord> createEvent({
    required String id,
    required String title,
    required String description,
    required String disciplineId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String? streamUrl,
    required String status,
    required String createdBy,
  }) async {
    final result = await _conn.query(
      'INSERT INTO events (id, title, description, discipline_id, starts_at, '
      'ends_at, stream_url, status, created_by) '
      'VALUES (@id, @title, @description, @discipline_id, @starts_at, '
      '@ends_at, @stream_url, @status, @created_by) '
      'RETURNING id, title, description, discipline_id, starts_at, ends_at, '
      'stream_url, chat_id, status, created_by',
      substitutionValues: {
        'id': id,
        'title': title,
        'description': description,
        'discipline_id': disciplineId,
        'starts_at': startsAt.toUtc(),
        'ends_at': endsAt.toUtc(),
        'stream_url': streamUrl,
        'status': status,
        'created_by': createdBy,
      },
    );

    return _mapEvent(result.first);
  }

  Future<EventRecord?> updateEvent({
    required String id,
    required String title,
    required String description,
    required String disciplineId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String? streamUrl,
  }) async {
    final result = await _conn.query(
      'UPDATE events '
      'SET title = @title, description = @description, '
      'discipline_id = @discipline_id, starts_at = @starts_at, '
      'ends_at = @ends_at, stream_url = @stream_url, updated_at = NOW() '
      'WHERE id = @id '
      'RETURNING id, title, description, discipline_id, starts_at, ends_at, '
      'stream_url, chat_id, status, created_by',
      substitutionValues: {
        'id': id,
        'title': title,
        'description': description,
        'discipline_id': disciplineId,
        'starts_at': startsAt.toUtc(),
        'ends_at': endsAt.toUtc(),
        'stream_url': streamUrl,
      },
    );

    if (result.isEmpty) return null;
    return _mapEvent(result.first);
  }

  Future<EventRecord?> findById(String id) async {
    final result = await _conn.query(
      'SELECT id, title, description, discipline_id, starts_at, ends_at, '
      'stream_url, chat_id, status, created_by '
      'FROM events WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) return null;
    return _mapEvent(result.first);
  }

  Future<List<EventRecord>> listEvents({
    DateTime? from,
    DateTime? to,
    String? disciplineId,
    String? roleId,
    String? status,
  }) async {
    final joins = <String>[];
    final conditions = <String>[];
    final params = <String, dynamic>{};

    if (from != null) {
      conditions.add('e.starts_at >= @from');
      params['from'] = from.toUtc();
    }

    if (to != null) {
      conditions.add('e.starts_at <= @to');
      params['to'] = to.toUtc();
    }

    if (disciplineId != null && disciplineId.isNotEmpty) {
      conditions.add('e.discipline_id = @discipline_id');
      params['discipline_id'] = disciplineId;
    }

    if (status != null && status.isNotEmpty) {
      conditions.add('e.status = @status');
      params['status'] = status;
    }

    if (roleId != null && roleId.isNotEmpty) {
      joins.add('JOIN event_roles er ON er.event_id = e.id');
      conditions.add('er.role_id = @role_id');
      params['role_id'] = roleId;
    }

    final buffer = StringBuffer(
      'SELECT DISTINCT e.id, e.title, e.description, e.discipline_id, '
      'e.starts_at, e.ends_at, e.stream_url, e.chat_id, e.status, e.created_by '
      'FROM events e ',
    );

    if (joins.isNotEmpty) {
      buffer.write('${joins.join(' ')} ');
    }

    if (conditions.isNotEmpty) {
      buffer.write('WHERE ${conditions.join(' AND ')} ');
    }

    buffer.write('ORDER BY e.starts_at');

    final rows = await _conn.query(buffer.toString(), substitutionValues: params);
    return rows.map(_mapEvent).toList();
  }

  Future<bool> updateStatus({
    required String id,
    required String status,
  }) async {
    final result = await _conn.query(
      'UPDATE events SET status = @status, updated_at = NOW() '
      'WHERE id = @id RETURNING id',
      substitutionValues: {'id': id, 'status': status},
    );

    return result.isNotEmpty;
  }

  Future<bool> cancelEvent(String id) async {
    final result = await _conn.query(
      'UPDATE events SET status = @status, updated_at = NOW() '
      'WHERE id = @id RETURNING id',
      substitutionValues: {'id': id, 'status': 'canceled'},
    );

    return result.isNotEmpty;
  }

  Future<void> replaceRoles(String eventId, List<EventRoleRecord> roles) async {
    await _conn.transaction((ctx) async {
      await ctx.query(
        'DELETE FROM event_roles WHERE event_id = @event_id',
        substitutionValues: {'event_id': eventId},
      );

      for (final role in roles) {
        await ctx.query(
          'INSERT INTO event_roles (id, event_id, role_id, required_count) '
          'VALUES (@id, @event_id, @role_id, @required_count)',
          substitutionValues: {
            'id': role.id,
            'event_id': role.eventId,
            'role_id': role.roleId,
            'required_count': role.requiredCount,
          },
        );
      }
    });
  }

  Future<List<EventRoleRecord>> listRoles(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, role_id, required_count '
      'FROM event_roles WHERE event_id = @event_id '
      'ORDER BY role_id',
      substitutionValues: {'event_id': eventId},
    );

    return rows.map(_mapRole).toList();
  }

  Future<bool> setChatId({required String eventId, required String chatId}) async {
    final result = await _conn.query(
      'UPDATE events SET chat_id = @chat_id, updated_at = NOW() '
      'WHERE id = @id RETURNING id',
      substitutionValues: {'id': eventId, 'chat_id': chatId},
    );
    return result.isNotEmpty;
  }

  EventRecord _mapEvent(List<dynamic> row) {
    return EventRecord(
      id: row[0].toString(),
      title: row[1] as String,
      description: row[2] as String,
      disciplineId: row[3].toString(),
      startsAt: row[4] as DateTime,
      endsAt: row[5] as DateTime,
      streamUrl: row[6] as String?,
      chatId: row[7] as String?,
      status: row[8] as String,
      createdBy: row[9].toString(),
    );
  }

  EventRoleRecord _mapRole(List<dynamic> row) {
    return EventRoleRecord(
      id: row[0].toString(),
      eventId: row[1].toString(),
      roleId: row[2].toString(),
      requiredCount: row[3] as int,
    );
  }
}
