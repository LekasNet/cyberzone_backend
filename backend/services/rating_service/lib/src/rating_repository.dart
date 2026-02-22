import 'package:postgres/postgres.dart';

import 'models.dart';

class RatingInput {
  final String id;
  final String userId;
  final int score;
  final String? comment;

  RatingInput({
    required this.id,
    required this.userId,
    required this.score,
    required this.comment,
  });
}

class RatingRepository {
  final PostgreSQLConnection _conn;

  RatingRepository(this._conn);

  Future<List<RatingRecord>> upsertRatings({
    required String eventId,
    required String ratedBy,
    required List<RatingInput> ratings,
  }) async {
    final results = <RatingRecord>[];

    await _conn.transaction((ctx) async {
      for (final rating in ratings) {
        final rows = await ctx.query(
          'INSERT INTO ratings '
          '(id, event_id, user_id, rated_by, score, comment) '
          'VALUES (@id, @event_id, @user_id, @rated_by, @score, @comment) '
          'ON CONFLICT (event_id, user_id) DO UPDATE '
          'SET score = EXCLUDED.score, comment = EXCLUDED.comment, '
          'rated_by = EXCLUDED.rated_by, updated_at = NOW() '
          'RETURNING id, event_id, user_id, rated_by, score, comment, created_at',
          substitutionValues: {
            'id': rating.id,
            'event_id': eventId,
            'user_id': rating.userId,
            'rated_by': ratedBy,
            'score': rating.score,
            'comment': rating.comment,
          },
        );

        results.add(_mapRating(rows.first));
      }
    });

    return results;
  }

  Future<List<RatingRecord>> listByEvent(String eventId) async {
    final rows = await _conn.query(
      'SELECT id, event_id, user_id, rated_by, score, comment, created_at '
      'FROM ratings WHERE event_id = @event_id '
      'ORDER BY created_at',
      substitutionValues: {'event_id': eventId},
    );

    return rows.map(_mapRating).toList();
  }

  Future<RatingSummary?> summaryForUser(String userId) async {
    final rows = await _conn.query(
      'SELECT user_id, AVG(score)::float, COUNT(*) '
      'FROM ratings WHERE user_id = @user_id GROUP BY user_id',
      substitutionValues: {'user_id': userId},
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    return RatingSummary(
      userId: row[0].toString(),
      averageScore: (row[1] as num).toDouble(),
      totalEvents: (row[2] as num).toInt(),
    );
  }

  Future<Map<String, RatingSummary>> summaryForUsers(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final rows = await _conn.query(
      'SELECT user_id, AVG(score)::float, COUNT(*) '
      'FROM ratings WHERE user_id = ANY(@user_ids) '
      'GROUP BY user_id',
      substitutionValues: {'user_ids': userIds},
    );

    final map = <String, RatingSummary>{};
    for (final row in rows) {
      final userId = row[0].toString();
      map[userId] = RatingSummary(
        userId: userId,
        averageScore: (row[1] as num).toDouble(),
        totalEvents: (row[2] as num).toInt(),
      );
    }

    return map;
  }

  RatingRecord _mapRating(List<dynamic> row) {
    return RatingRecord(
      id: row[0].toString(),
      eventId: row[1].toString(),
      userId: row[2].toString(),
      ratedBy: row[3].toString(),
      score: row[4] as int,
      comment: row[5] as String?,
      createdAt: row[6] as DateTime,
    );
  }
}
