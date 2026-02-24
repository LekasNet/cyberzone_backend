import 'package:postgres/postgres.dart';

import 'models.dart';

class ChatRepository {
  final PostgreSQLConnection _conn;

  ChatRepository(this._conn);

  Future<ChatRecord?> findById(String id) async {
    final rows = await _conn.query(
      'SELECT id, event_id, is_active, created_at, type, title '
      'FROM chats WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _mapChat(rows.first);
  }

  Future<ChatRecord?> findByEventId(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, is_active, created_at, type, title '
      'FROM chats WHERE event_id = @event_id AND type = @type',
      substitutionValues: {
        'event_id': eventId,
        'type': 'event',
      },
    );
    if (rows.isEmpty) return null;
    return _mapChat(rows.first);
  }

  Future<List<ChatRecord>> listPermanentChats() async {
    final rows = await _conn.query(
      'SELECT id, event_id, is_active, created_at, type, title '
      'FROM chats WHERE type = @type '
      'ORDER BY created_at',
      substitutionValues: {'type': 'permanent'},
    );
    return rows.map(_mapChat).toList();
  }

  Future<ChatRecord> createChat({
    required String id,
    required String eventId,
  }) async {
    final rows = await _conn.query(
      'INSERT INTO chats (id, event_id, type, is_active) '
      'VALUES (@id, @event_id, @type, false) '
      'RETURNING id, event_id, is_active, created_at, type, title',
      substitutionValues: {
        'id': id,
        'event_id': eventId,
        'type': 'event',
      },
    );

    return _mapChat(rows.first);
  }

  Future<ChatRecord> createPermanentChat({
    required String id,
    required String title,
    required String createdBy,
  }) async {
    final rows = await _conn.query(
      'INSERT INTO chats (id, event_id, type, title, created_by, is_active) '
      'VALUES (@id, NULL, @type, @title, @created_by, true) '
      'RETURNING id, event_id, is_active, created_at, type, title',
      substitutionValues: {
        'id': id,
        'type': 'permanent',
        'title': title,
        'created_by': createdBy,
      },
    );

    return _mapChat(rows.first);
  }

  Future<ChatRecord?> setActive({
    required String chatId,
    required bool isActive,
  }) async {
    final rows = await _conn.query(
      'UPDATE chats SET is_active = @is_active, updated_at = NOW() '
      'WHERE id = @id '
      'RETURNING id, event_id, is_active, created_at, type, title',
      substitutionValues: {
        'id': chatId,
        'is_active': isActive,
      },
    );
    if (rows.isEmpty) return null;
    return _mapChat(rows.first);
  }

  ChatRecord _mapChat(List<dynamic> row) {
    return ChatRecord(
      id: row[0].toString(),
      eventId: row[1] == null ? null : row[1].toString(),
      isActive: row[2] as bool,
      createdAt: row[3] as DateTime,
      type: row[4] as String,
      title: row[5] as String?,
    );
  }
}
