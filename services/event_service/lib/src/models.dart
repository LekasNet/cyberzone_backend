class EventRecord {
  final String id;
  final String title;
  final String description;
  final String disciplineId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? streamUrl;
  final String? chatId;
  final String status;
  final String createdBy;

  EventRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.disciplineId,
    required this.startsAt,
    required this.endsAt,
    required this.streamUrl,
    required this.chatId,
    required this.status,
    required this.createdBy,
  });
}

class EventRoleRecord {
  final String id;
  final String eventId;
  final String roleId;
  final int requiredCount;

  EventRoleRecord({
    required this.id,
    required this.eventId,
    required this.roleId,
    required this.requiredCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'roleId': roleId,
        'requiredCount': requiredCount,
      };
}

class EventApplicationRecord {
  final String id;
  final String eventId;
  final String userId;
  final String roleId;
  final String status;
  final DateTime createdAt;

  EventApplicationRecord({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.roleId,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'userId': userId,
        'roleId': roleId,
        'status': status,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

class EventCastRecord {
  final String id;
  final String eventId;
  final String userId;
  final String roleId;

  EventCastRecord({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.roleId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'userId': userId,
        'roleId': roleId,
      };
}
