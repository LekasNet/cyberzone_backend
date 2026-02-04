import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'dictionary_repository.dart';
import 'jwt_service.dart';
import 'models.dart';
import 'user_repository.dart';

class UserController {
  final UserRepository _users;
  final DictionaryRepository _dictionaries;
  final JwtService _jwt;
  final String _internalKey;

  UserController({
    required UserRepository users,
    required DictionaryRepository dictionaries,
    required JwtService jwt,
    required String internalKey,
  })  : _users = users,
        _dictionaries = dictionaries,
        _jwt = jwt,
        _internalKey = internalKey;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.get('/users/me', _withAuth(_getMe));
    r.put('/users/me', _withAuth(_updateMe));
    r.get('/users/me/roles', _withAuth(_getMyRoles));
    r.put('/users/me/roles', _withAuth(_setMyRoles));
    r.get('/users/me/disciplines', _withAuth(_getMyDisciplines));
    r.put('/users/me/disciplines', _withAuth(_setMyDisciplines));

    r.get('/users/<id>', _withAuth(_getUserById));

    r.get('/dictionaries/roles', _getRoles);
    r.get('/dictionaries/disciplines', _getDisciplines);

    r.get('/admin/users', _withAdmin(_listUsers));
    r.get('/admin/users/<id>', _withAdmin(_getAdminUser));

    r.put('/admin/users/<id>/make_admin', _withSuperAdmin(_makeAdmin));
    r.put('/admin/users/<id>/remove_admin', _withSuperAdmin(_removeAdmin));
    r.put('/admin/users/<id>/ban', _withSuperAdmin(_banUser));
    r.put('/admin/users/<id>/unban', _withSuperAdmin(_unbanUser));

    r.post('/internal/users', _withInternal(_createInternalUser));
    r.get('/internal/users/<id>/flags', _withInternal(_getInternalFlags));

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addHandler(handler);

  Handler _withAdmin(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addMiddleware(requireAdmin())
      .addHandler(handler);

  Handler _withSuperAdmin(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addMiddleware(requireSuperAdmin())
      .addHandler(handler);

  Handler _withInternal(Handler handler) => Pipeline()
      .addMiddleware(_internalAuth())
      .addHandler(handler);

  Middleware _internalAuth() {
    return (Handler innerHandler) {
      return (Request request) async {
        final key = request.headers['x-internal-key'];
        if (key == null || key != _internalKey) {
          return _json(401, {'error': 'invalid_internal_key'});
        }
        return innerHandler(request);
      };
    };
  }

  Future<Response> _health(Request request) async {
    return _json(200, {'status': 'ok'});
  }

  Future<Response> _getMe(Request request) async {
    final auth = requireAuth(request);

    final user = await _users.findById(auth.claims.userId);
    if (user == null) return _json(404, {'error': 'user_not_found'});

    final roles = await _users.getUserRoles(user.id);
    final disciplines = await _users.getUserDisciplines(user.id);

    return _json(200, _userToJson(user,
        includeEmail: true,
        includeFlags: true,
        roles: roles,
        disciplines: disciplines));
  }

  Future<Response> _updateMe(Request request) async {
    final auth = requireAuth(request);

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final update = _parseProfileUpdate(body);
    if (update == null) return _json(400, {'error': 'invalid_profile_fields'});
    if (!update.hasAny) return _json(400, {'error': 'no_fields_to_update'});

    final user = await _users.updateProfile(
      userId: auth.claims.userId,
      hasFirstName: update.hasFirstName,
      firstName: update.firstName,
      hasLastName: update.hasLastName,
      lastName: update.lastName,
      hasInstitute: update.hasInstitute,
      institute: update.institute,
      hasGroup: update.hasGroup,
      group: update.group,
      hasAvatarUrl: update.hasAvatarUrl,
      avatarUrl: update.avatarUrl,
    );

    if (user == null) return _json(404, {'error': 'user_not_found'});

    final roles = await _users.getUserRoles(user.id);
    final disciplines = await _users.getUserDisciplines(user.id);

    return _json(200, _userToJson(user,
        includeEmail: true,
        includeFlags: true,
        roles: roles,
        disciplines: disciplines));
  }

  Future<Response> _getMyRoles(Request request) async {
    final auth = requireAuth(request);
    final roles = await _users.getUserRoles(auth.claims.userId);
    return _json(200, {'roles': roles.map((r) => r.toJson()).toList()});
  }

  Future<Response> _setMyRoles(Request request) async {
    final auth = requireAuth(request);

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final roleIds = _parseIdList(body['roleIds']);
    if (roleIds == null) return _json(400, {'error': 'roleIds_required'});
    if (_hasDuplicates(roleIds)) {
      return _json(400, {'error': 'duplicate_role_ids'});
    }

    final rolesExist = await _dictionaries.rolesExist(roleIds);
    if (!rolesExist) return _json(400, {'error': 'invalid_role_ids'});

    await _users.setUserRoles(auth.claims.userId, roleIds);

    final roles = await _users.getUserRoles(auth.claims.userId);
    return _json(200, {'roles': roles.map((r) => r.toJson()).toList()});
  }

  Future<Response> _getMyDisciplines(Request request) async {
    final auth = requireAuth(request);
    final disciplines = await _users.getUserDisciplines(auth.claims.userId);
    return _json(200,
        {'disciplines': disciplines.map((d) => d.toJson()).toList()});
  }

  Future<Response> _setMyDisciplines(Request request) async {
    final auth = requireAuth(request);

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final disciplineIds = _parseIdList(body['disciplineIds']);
    if (disciplineIds == null) {
      return _json(400, {'error': 'disciplineIds_required'});
    }
    if (_hasDuplicates(disciplineIds)) {
      return _json(400, {'error': 'duplicate_discipline_ids'});
    }

    final disciplinesExist = await _dictionaries.disciplinesExist(disciplineIds);
    if (!disciplinesExist) {
      return _json(400, {'error': 'invalid_discipline_ids'});
    }

    await _users.setUserDisciplines(auth.claims.userId, disciplineIds);

    final disciplines = await _users.getUserDisciplines(auth.claims.userId);
    return _json(200,
        {'disciplines': disciplines.map((d) => d.toJson()).toList()});
  }

  Future<Response> _getUserById(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final user = await _users.findById(id);
    if (user == null) return _json(404, {'error': 'user_not_found'});

    final roles = await _users.getUserRoles(id);
    final disciplines = await _users.getUserDisciplines(id);

    return _json(200, _userToJson(user,
        includeEmail: false,
        includeFlags: false,
        roles: roles,
        disciplines: disciplines));
  }

  Future<Response> _getRoles(Request request) async {
    final roles = await _dictionaries.listRoles();
    return _json(200, {'roles': roles.map((r) => r.toJson()).toList()});
  }

  Future<Response> _getDisciplines(Request request) async {
    final disciplines = await _dictionaries.listDisciplines();
    return _json(200,
        {'disciplines': disciplines.map((d) => d.toJson()).toList()});
  }

  Future<Response> _listUsers(Request request) async {
    final roleId = request.url.queryParameters['roleId'];
    final disciplineId = request.url.queryParameters['disciplineId'];
    final search = request.url.queryParameters['search'];

    if (request.url.queryParameters.containsKey('minRating')) {
      return _json(400, {'error': 'minRating_not_supported'});
    }

    final users = await _users.listUsers(
      roleId: roleId,
      disciplineId: disciplineId,
      search: search,
    );

    final userIds = users.map((u) => u.id).toList();
    final rolesMap = await _users.getRolesForUsers(userIds);
    final disciplinesMap = await _users.getDisciplinesForUsers(userIds);

    final items = users
        .map((user) => _userToJson(
              user,
              includeEmail: true,
              includeFlags: true,
              roles: rolesMap[user.id] ?? <DictionaryEntry>[],
              disciplines: disciplinesMap[user.id] ?? <DictionaryEntry>[],
            ))
        .toList();

    return _json(200, {'users': items});
  }

  Future<Response> _getAdminUser(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final user = await _users.findById(id);
    if (user == null) return _json(404, {'error': 'user_not_found'});

    final roles = await _users.getUserRoles(id);
    final disciplines = await _users.getUserDisciplines(id);

    return _json(200, _userToJson(user,
        includeEmail: true,
        includeFlags: true,
        roles: roles,
        disciplines: disciplines));
  }

  Future<Response> _makeAdmin(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final ok = await _users.setAdminStatus(id, true);
    if (!ok) return _json(404, {'error': 'user_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _removeAdmin(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final ok = await _users.setAdminStatus(id, false);
    if (!ok) return _json(404, {'error': 'user_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _banUser(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final ok = await _users.setBannedStatus(id, true);
    if (!ok) return _json(404, {'error': 'user_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _unbanUser(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }
    final ok = await _users.setBannedStatus(id, false);
    if (!ok) return _json(404, {'error': 'user_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _createInternalUser(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final id = body['id'] as String?;
    final email = body['email'] as String?;

    if (id == null || id.isEmpty || email == null || email.isEmpty) {
      return _json(400, {'error': 'id_and_email_required'});
    }

    final existingById = await _users.findById(id);
    if (existingById != null) {
      return _json(200, _flagsToJson(existingById));
    }

    final existingByEmail = await _users.findByEmail(email);
    if (existingByEmail != null && existingByEmail.id != id) {
      return _json(409, {'error': 'email_already_exists'});
    }

    final created = await _users.createUser(id: id, email: email);
    return _json(201, _flagsToJson(created));
  }

  Future<Response> _getInternalFlags(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }

    final user = await _users.findById(id);
    if (user == null) return _json(404, {'error': 'user_not_found'});

    return _json(200, _flagsToJson(user));
  }

  Future<Map<String, dynamic>?> _tryReadJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
      return null;
    } catch (_) {
      return null;
    }
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );

  _ProfileUpdate? _parseProfileUpdate(Map<String, dynamic> body) {
    final update = _ProfileUpdate();

    if (body.containsKey('firstName')) {
      final value = body['firstName'];
      if (value != null && value is! String) return null;
      update.firstName = value as String?;
      update.hasFirstName = true;
    }

    if (body.containsKey('lastName')) {
      final value = body['lastName'];
      if (value != null && value is! String) return null;
      update.lastName = value as String?;
      update.hasLastName = true;
    }

    if (body.containsKey('institute')) {
      final value = body['institute'];
      if (value != null && value is! String) return null;
      update.institute = value as String?;
      update.hasInstitute = true;
    }

    if (body.containsKey('group')) {
      final value = body['group'];
      if (value != null && value is! String) return null;
      update.group = value as String?;
      update.hasGroup = true;
    }

    if (body.containsKey('avatarUrl')) {
      final value = body['avatarUrl'];
      if (value != null && value is! String) return null;
      update.avatarUrl = value as String?;
      update.hasAvatarUrl = true;
    }

    return update;
  }

  List<String>? _parseIdList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;

    final result = <String>[];
    for (final item in value) {
      if (item is String) {
        result.add(item);
      } else if (item is int) {
        result.add(item.toString());
      } else {
        return null;
      }
    }

    return result;
  }

  bool _hasDuplicates(List<String> items) {
    final set = <String>{};
    for (final item in items) {
      if (!set.add(item)) return true;
    }
    return false;
  }

  Map<String, dynamic> _userToJson(
    UserRecord user, {
    required bool includeEmail,
    required bool includeFlags,
    required List<DictionaryEntry> roles,
    required List<DictionaryEntry> disciplines,
  }) {
    final map = <String, dynamic>{
      'id': user.id,
      'firstName': user.firstName,
      'lastName': user.lastName,
      'institute': user.institute,
      'group': user.group,
      'avatarUrl': user.avatarUrl,
      'roles': roles.map((r) => r.toJson()).toList(),
      'disciplines': disciplines.map((d) => d.toJson()).toList(),
    };

    if (includeEmail) {
      map['email'] = user.email;
    }

    if (includeFlags) {
      map['isAdmin'] = user.isAdmin;
      map['isSuperAdmin'] = user.isSuperAdmin;
      map['isBanned'] = user.isBanned;
    }

    return map;
  }

  Map<String, dynamic> _flagsToJson(UserRecord user) => {
        'userId': user.id,
        'isAdmin': user.isAdmin,
        'isSuperAdmin': user.isSuperAdmin,
        'isBanned': user.isBanned,
      };
}

class _ProfileUpdate {
  bool hasFirstName = false;
  bool hasLastName = false;
  bool hasInstitute = false;
  bool hasGroup = false;
  bool hasAvatarUrl = false;

  String? firstName;
  String? lastName;
  String? institute;
  String? group;
  String? avatarUrl;

  bool get hasAny =>
      hasFirstName || hasLastName || hasInstitute || hasGroup || hasAvatarUrl;
}
