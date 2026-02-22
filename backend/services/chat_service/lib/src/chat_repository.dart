import 'package:postgres/postgres.dart';

import 'models.dart';

class ChatRepository {
  final PostgreSQLConnection _conn;

  ChatRepository(this._conn);

  Future<ChatRecord?> findById(String id) async {
    final rows = await _conn.query(
      'SELECT id, event_id, is_active, created_at '
      'FROM chats WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _mapChat(rows.first);
  }

  Future<ChatRecord?> findByEventId(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, is_active, created_at '
      'FROM chats WHERE event_id = @event_id',
      substitutionValues: {'event_id': eventId},
    );
    if (rows.isEmpty) return null;
    return _mapChat(rows.first);
  }

  Future<ChatRecord> createChat({
    required String id,
    required String eventId,
  }) async {
    final rows = await _conn.query(
      'INSERT INTO chats (id, event_id, is_active) '
      'VALUES (@id, @event_id, false) '
      'RETURNING id, event_id, is_active, created_at',
      substitutionValues: {
        'id': id,
        'event_id': eventId,
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
      'RETURNING id, event_id, is_active, created_at',
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
      eventId: row[1].toString(),
      isActive: row[2] as bool,
      createdAt: row[3] as DateTime,
    );
  }
}
