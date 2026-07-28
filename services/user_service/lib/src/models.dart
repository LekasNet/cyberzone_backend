class UserRecord {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? nickname;
  final String? phone;
  final String? institute;
  final String? group;
  final String? avatarUrl;
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool isBanned;

  UserRecord({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.nickname,
    required this.phone,
    required this.institute,
    required this.group,
    required this.avatarUrl,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.isBanned,
  });
}

class DictionaryEntry {
  final String id;
  final String name;
  final String? color;

  DictionaryEntry({
    required this.id,
    required this.name,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
      };
}
