import 'package:postgres/postgres.dart';

import 'models.dart';

class MessageRepository {
  final PostgreSQLConnection _conn;

  MessageRepository(this._conn);

  Future<ChatMessageRecord> createMessage({
    required String id,
    required String chatId,
    required String? userId,
    required String text,
  }) async {
    final rows = await _conn.query(
      'INSERT INTO chat_messages (id, chat_id, user_id, text) '
      'VALUES (@id, @chat_id, @user_id, @text) '
      'RETURNING id, chat_id, user_id, text, created_at',
      substitutionValues: {
        'id': id,
        'chat_id': chatId,
        'user_id': userId,
        'text': text,
      },
    );

    return _mapMessage(rows.first);
  }

  Future<List<ChatMessageRecord>> listMessages({
    required String chatId,
    required int limit,
    DateTime? cursorTime,
    String? cursorId,
  }) async {
    final conditions = <String>['chat_id = @chat_id'];
    final params = <String, dynamic>{
      'chat_id': chatId,
      'limit': limit,
    };

    if (cursorTime != null && cursorId != null) {
      conditions.add(
        '(created_at < @cursor_time OR (created_at = @cursor_time AND id < @cursor_id))',
      );
      params['cursor_time'] = cursorTime.toUtc();
      params['cursor_id'] = cursorId;
    }

    final sql = StringBuffer(
      'SELECT id, chat_id, user_id, text, created_at '
      'FROM chat_messages ',
    );

    if (conditions.isNotEmpty) {
      sql.write('WHERE ${conditions.join(' AND ')} ');
    }

    sql.write('ORDER BY created_at DESC, id DESC LIMIT @limit');

    final rows = await _conn.query(sql.toString(), substitutionValues: params);
    return rows.map(_mapMessage).toList();
  }

  ChatMessageRecord _mapMessage(List<dynamic> row) {
    return ChatMessageRecord(
      id: row[0].toString(),
      chatId: row[1].toString(),
      userId: row[2] as String?,
      text: row[3] as String,
      createdAt: row[4] as DateTime,
    );
  }
}
