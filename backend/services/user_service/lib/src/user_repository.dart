import 'package:postgres/postgres.dart';

import 'models.dart';

class UserRepository {
  final PostgreSQLConnection _conn;

  UserRepository(this._conn);

  Future<UserRecord?> findById(String id) async {
    final result = await _conn.query(
      'SELECT id, email, first_name, last_name, institute, "group", avatar_url, '
      'is_admin, is_super_admin, is_banned '
      'FROM users WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) return null;

    return _mapUser(result.first);
  }

  Future<UserRecord?> findByEmail(String email) async {
    final result = await _conn.query(
      'SELECT id, email, first_name, last_name, institute, "group", avatar_url, '
      'is_admin, is_super_admin, is_banned '
      'FROM users WHERE email = @email',
      substitutionValues: {'email': email},
    );

    if (result.isEmpty) return null;
    return _mapUser(result.first);
  }

  Future<UserRecord> createUser({
    required String id,
    required String email,
  }) async {
    final result = await _conn.query(
      'INSERT INTO users (id, email, is_admin, is_super_admin, is_banned) '
      'VALUES (@id, @email, false, false, false) '
      'RETURNING id, email, first_name, last_name, institute, "group", '
      'avatar_url, is_admin, is_super_admin, is_banned',
      substitutionValues: {
        'id': id,
        'email': email,
      },
    );

    return _mapUser(result.first);
  }

  Future<UserRecord?> updateProfile({
    required String userId,
    bool hasFirstName = false,
    String? firstName,
    bool hasLastName = false,
    String? lastName,
    bool hasInstitute = false,
    String? institute,
    bool hasGroup = false,
    String? group,
    bool hasAvatarUrl = false,
    String? avatarUrl,
  }) async {
    final updates = <String>[];
    final params = <String, dynamic>{'id': userId};

    if (hasFirstName) {
      updates.add('first_name = @first_name');
      params['first_name'] = firstName;
    }
    if (hasLastName) {
      updates.add('last_name = @last_name');
      params['last_name'] = lastName;
    }
    if (hasInstitute) {
      updates.add('institute = @institute');
      params['institute'] = institute;
    }
    if (hasGroup) {
      updates.add('"group" = @group_value');
      params['group_value'] = group;
    }
    if (hasAvatarUrl) {
      updates.add('avatar_url = @avatar_url');
      params['avatar_url'] = avatarUrl;
    }

    if (updates.isEmpty) {
      return findById(userId);
    }

    updates.add('updated_at = NOW()');

    final sql =
        'UPDATE users SET ${updates.join(', ')} WHERE id = @id '
        'RETURNING id, email, first_name, last_name, institute, "group", '
        'avatar_url, is_admin, is_super_admin, is_banned';

    final result = await _conn.query(sql, substitutionValues: params);
    if (result.isEmpty) return null;
    return _mapUser(result.first);
  }

  Future<List<DictionaryEntry>> getUserRoles(String userId) async {
    final rows = await _conn.query(
      'SELECT r.id, r.name '
      'FROM user_roles ur '
      'JOIN roles r ON r.id = ur.role_id '
      'WHERE ur.user_id = @user_id '
      'ORDER BY r.name',
      substitutionValues: {'user_id': userId},
    );

    return rows
        .map((row) => DictionaryEntry(
              id: row[0].toString(),
              name: row[1] as String,
            ))
        .toList();
  }

  Future<List<DictionaryEntry>> getUserDisciplines(String userId) async {
    final rows = await _conn.query(
      'SELECT d.id, d.name '
      'FROM user_disciplines ud '
      'JOIN disciplines d ON d.id = ud.discipline_id '
      'WHERE ud.user_id = @user_id '
      'ORDER BY d.name',
      substitutionValues: {'user_id': userId},
    );

    return rows
        .map((row) => DictionaryEntry(
              id: row[0].toString(),
              name: row[1] as String,
            ))
        .toList();
  }

  Future<Map<String, List<DictionaryEntry>>> getRolesForUsers(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final rows = await _conn.query(
      'SELECT ur.user_id, r.id, r.name '
      'FROM user_roles ur '
      'JOIN roles r ON r.id = ur.role_id '
      'WHERE ur.user_id = ANY(@user_ids) '
      'ORDER BY r.name',
      substitutionValues: {'user_ids': userIds},
    );

    final map = <String, List<DictionaryEntry>>{};
    for (final row in rows) {
      final userId = row[0].toString();
      map.putIfAbsent(userId, () => <DictionaryEntry>[]).add(
            DictionaryEntry(
              id: row[1].toString(),
              name: row[2] as String,
            ),
          );
    }

    return map;
  }

  Future<Map<String, List<DictionaryEntry>>> getDisciplinesForUsers(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final rows = await _conn.query(
      'SELECT ud.user_id, d.id, d.name '
      'FROM user_disciplines ud '
      'JOIN disciplines d ON d.id = ud.discipline_id '
      'WHERE ud.user_id = ANY(@user_ids) '
      'ORDER BY d.name',
      substitutionValues: {'user_ids': userIds},
    );

    final map = <String, List<DictionaryEntry>>{};
    for (final row in rows) {
      final userId = row[0].toString();
      map.putIfAbsent(userId, () => <DictionaryEntry>[]).add(
            DictionaryEntry(
              id: row[1].toString(),
              name: row[2] as String,
            ),
          );
    }

    return map;
  }

  Future<void> setUserRoles(String userId, List<String> roleIds) async {
    await _conn.transaction((ctx) async {
      await ctx.query(
        'DELETE FROM user_roles WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );

      for (final roleId in roleIds) {
        await ctx.query(
          'INSERT INTO user_roles (user_id, role_id) VALUES (@user_id, @role_id)',
          substitutionValues: {
            'user_id': userId,
            'role_id': roleId,
          },
        );
      }
    });
  }

  Future<void> setUserDisciplines(
      String userId, List<String> disciplineIds) async {
    await _conn.transaction((ctx) async {
      await ctx.query(
        'DELETE FROM user_disciplines WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );

      for (final disciplineId in disciplineIds) {
        await ctx.query(
          'INSERT INTO user_disciplines (user_id, discipline_id) '
          'VALUES (@user_id, @discipline_id)',
          substitutionValues: {
            'user_id': userId,
            'discipline_id': disciplineId,
          },
        );
      }
    });
  }

  Future<List<UserRecord>> listUsers({
    String? roleId,
    String? disciplineId,
    String? search,
  }) async {
    final joins = <String>[];
    final conditions = <String>[];
    final params = <String, dynamic>{};

    if (roleId != null && roleId.isNotEmpty) {
      joins.add('JOIN user_roles ur ON ur.user_id = u.id');
      conditions.add('ur.role_id = @role_id');
      params['role_id'] = roleId;
    }

    if (disciplineId != null && disciplineId.isNotEmpty) {
      joins.add('JOIN user_disciplines ud ON ud.user_id = u.id');
      conditions.add('ud.discipline_id = @discipline_id');
      params['discipline_id'] = disciplineId;
    }

    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.toLowerCase()}%';
      conditions.add(
          '(LOWER(u.first_name) LIKE @q OR LOWER(u.last_name) LIKE @q OR LOWER(u.email) LIKE @q)');
      params['q'] = q;
    }

    final buffer = StringBuffer(
      'SELECT DISTINCT u.id, u.email, u.first_name, u.last_name, u.institute, '
      'u."group", u.avatar_url, u.is_admin, u.is_super_admin, u.is_banned '
      'FROM users u ',
    );

    if (joins.isNotEmpty) {
      buffer.write('${joins.join(' ')} ');
    }

    if (conditions.isNotEmpty) {
      buffer.write('WHERE ${conditions.join(' AND ')} ');
    }

    buffer.write('ORDER BY u.id');

    final rows = await _conn.query(buffer.toString(), substitutionValues: params);
    return rows.map(_mapUser).toList();
  }

  Future<List<UserRecord>> listUsersByIds(
    List<String> userIds, {
    String? roleId,
    String? disciplineId,
  }) async {
    if (userIds.isEmpty) return <UserRecord>[];

    final joins = <String>[];
    final conditions = <String>['u.id = ANY(@user_ids)'];
    final params = <String, dynamic>{'user_ids': userIds};

    if (roleId != null && roleId.isNotEmpty) {
      joins.add('JOIN user_roles ur ON ur.user_id = u.id');
      conditions.add('ur.role_id = @role_id');
      params['role_id'] = roleId;
    }

    if (disciplineId != null && disciplineId.isNotEmpty) {
      joins.add('JOIN user_disciplines ud ON ud.user_id = u.id');
      conditions.add('ud.discipline_id = @discipline_id');
      params['discipline_id'] = disciplineId;
    }

    final buffer = StringBuffer(
      'SELECT DISTINCT u.id, u.email, u.first_name, u.last_name, u.institute, '
      'u."group", u.avatar_url, u.is_admin, u.is_super_admin, u.is_banned '
      'FROM users u ',
    );

    if (joins.isNotEmpty) {
      buffer.write('${joins.join(' ')} ');
    }

    buffer.write('WHERE ${conditions.join(' AND ')} ');
    buffer.write('ORDER BY u.id');

    final rows = await _conn.query(buffer.toString(), substitutionValues: params);
    return rows.map(_mapUser).toList();
  }

  Future<bool> setAdminStatus(String userId, bool isAdmin) async {
    final result = await _conn.query(
      'UPDATE users SET is_admin = @is_admin WHERE id = @id RETURNING id',
      substitutionValues: {'id': userId, 'is_admin': isAdmin},
    );
    return result.isNotEmpty;
  }

  Future<bool> setBannedStatus(String userId, bool isBanned) async {
    final result = await _conn.query(
      'UPDATE users SET is_banned = @is_banned WHERE id = @id RETURNING id',
      substitutionValues: {'id': userId, 'is_banned': isBanned},
    );
    return result.isNotEmpty;
  }

  UserRecord _mapUser(List<dynamic> row) {
    return UserRecord(
      id: row[0].toString(),
      email: row[1] as String,
      firstName: row[2] as String?,
      lastName: row[3] as String?,
      institute: row[4] as String?,
      group: row[5] as String?,
      avatarUrl: row[6] as String?,
      isAdmin: row[7] as bool,
      isSuperAdmin: row[8] as bool,
      isBanned: row[9] as bool,
    );
  }
}
