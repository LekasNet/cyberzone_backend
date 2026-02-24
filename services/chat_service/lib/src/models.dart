class ChatRecord {
  final String id;
  final String? eventId;
  final bool isActive;
  final DateTime createdAt;
  final String type;
  final String? title;

  ChatRecord({
    required this.id,
    required this.eventId,
    required this.isActive,
    required this.createdAt,
    required this.type,
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'chatId': id,
        'eventId': eventId,
        'isActive': isActive,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'type': type,
        'title': title,
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
