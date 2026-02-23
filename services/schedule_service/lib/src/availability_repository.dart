import 'package:postgres/postgres.dart';

import 'models.dart';

class AvailabilityRepository {
  final PostgreSQLConnection _conn;

  AvailabilityRepository(this._conn);

  Future<List<AvailabilitySlot>> listForUser(
    String userId, {
    String? fromDate,
    String? toDate,
  }) async {
    final conditions = <String>['user_id = @user_id'];
    final params = <String, dynamic>{'user_id': userId};

    if (fromDate != null) {
      conditions.add('date >= @from_date::date');
      params['from_date'] = fromDate;
    }

    if (toDate != null) {
      conditions.add('date <= @to_date::date');
      params['to_date'] = toDate;
    }

    final sql = StringBuffer(
      'SELECT id, user_id, '
      "to_char(date, 'YYYY-MM-DD') AS date, "
      "to_char(time_from, 'HH24:MI') AS time_from, "
      "to_char(time_to, 'HH24:MI') AS time_to "
      'FROM availability_slots ',
    );

    if (conditions.isNotEmpty) {
      sql.write('WHERE ${conditions.join(' AND ')} ');
    }

    sql.write('ORDER BY date, time_from');

    final rows = await _conn.query(sql.toString(), substitutionValues: params);
    return rows.map(_mapSlot).toList();
  }

  Future<AvailabilitySlot> createSlot({
    required String id,
    required String userId,
    required String date,
    required String timeFrom,
    required String timeTo,
  }) async {
    final result = await _conn.query(
      'INSERT INTO availability_slots (id, user_id, date, time_from, time_to) '
      'VALUES (@id, @user_id, @date::date, @time_from::time, @time_to::time) '
      'RETURNING id, user_id, '
      "to_char(date, 'YYYY-MM-DD') AS date, "
      "to_char(time_from, 'HH24:MI') AS time_from, "
      "to_char(time_to, 'HH24:MI') AS time_to",
      substitutionValues: {
        'id': id,
        'user_id': userId,
        'date': date,
        'time_from': timeFrom,
        'time_to': timeTo,
      },
    );

    return _mapSlot(result.first);
  }

  Future<AvailabilitySlot?> updateSlot({
    required String id,
    required String userId,
    required String date,
    required String timeFrom,
    required String timeTo,
  }) async {
    final result = await _conn.query(
      'UPDATE availability_slots '
      'SET date = @date::date, time_from = @time_from::time, '
      'time_to = @time_to::time, updated_at = NOW() '
      'WHERE id = @id AND user_id = @user_id '
      'RETURNING id, user_id, '
      "to_char(date, 'YYYY-MM-DD') AS date, "
      "to_char(time_from, 'HH24:MI') AS time_from, "
      "to_char(time_to, 'HH24:MI') AS time_to",
      substitutionValues: {
        'id': id,
        'user_id': userId,
        'date': date,
        'time_from': timeFrom,
        'time_to': timeTo,
      },
    );

    if (result.isEmpty) return null;
    return _mapSlot(result.first);
  }

  Future<bool> deleteSlot({
    required String id,
    required String userId,
  }) async {
    final result = await _conn.query(
      'DELETE FROM availability_slots WHERE id = @id AND user_id = @user_id '
      'RETURNING id',
      substitutionValues: {
        'id': id,
        'user_id': userId,
      },
    );

    return result.isNotEmpty;
  }

  Future<List<AvailabilitySlot>> searchSlots({
    required String date,
    required String fromTime,
    required String toTime,
  }) async {
    final rows = await _conn.query(
      'SELECT id, user_id, '
      "to_char(date, 'YYYY-MM-DD') AS date, "
      "to_char(time_from, 'HH24:MI') AS time_from, "
      "to_char(time_to, 'HH24:MI') AS time_to "
      'FROM availability_slots '
      'WHERE date = @date::date '
      'AND time_from <= @to_time::time '
      'AND time_to >= @from_time::time '
      'ORDER BY user_id, time_from',
      substitutionValues: {
        'date': date,
        'from_time': fromTime,
        'to_time': toTime,
      },
    );

    return rows.map(_mapSlot).toList();
  }

  AvailabilitySlot _mapSlot(List<dynamic> row) {
    return AvailabilitySlot(
      id: row[0].toString(),
      userId: row[1].toString(),
      date: row[2] as String,
      timeFrom: row[3] as String,
      timeTo: row[4] as String,
    );
  }
}
