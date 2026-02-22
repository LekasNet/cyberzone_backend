class ChatRecord {
  final String id;
  final String eventId;
  final bool isActive;
  final DateTime createdAt;

  ChatRecord({
    required this.id,
    required this.eventId,
    required this.isActive,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'chatId': id,
        'eventId': eventId,
        'isActive': isActive,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

class ChatMessageRecord {
  final String id;
  final String chatId;
  final String? userId;
  final String text;
  final DateTime createdAt;

  ChatMessageRecord({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'userId': userId,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
