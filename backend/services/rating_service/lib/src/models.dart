class RatingRecord {
  final String id;
  final String eventId;
  final String userId;
  final String ratedBy;
  final int score;
  final String? comment;
  final DateTime createdAt;

  RatingRecord({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.ratedBy,
    required this.score,
    required this.comment,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'userId': userId,
        'ratedBy': ratedBy,
        'score': score,
        'comment': comment,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

class RatingSummary {
  final String userId;
  final double averageScore;
  final int totalEvents;

  RatingSummary({
    required this.userId,
    required this.averageScore,
    required this.totalEvents,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'averageScore': averageScore,
        'totalEvents': totalEvents,
      };
}
