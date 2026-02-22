import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'application_repository.dart';
import 'auth_middleware.dart';
import 'cast_repository.dart';
import 'chat_service_client.dart';
import 'event_repository.dart';
import 'models.dart';
import 'notification_service_client.dart';
import 'user_service_client.dart';
import 'jwt_service.dart';

class EventController {
  final EventRepository _events;
  final ApplicationRepository _applications;
  final CastRepository _cast;
  final UserServiceClient _users;
  final ChatServiceClient _chat;
  final NotificationServiceClient _notifications;
  final JwtService _jwt;
  final String _internalKey;
  final _uuid = const Uuid();

  EventController({
    required EventRepository events,
    required ApplicationRepository applications,
    required CastRepository cast,
    required UserServiceClient users,
    required ChatServiceClient chat,
    required NotificationServiceClient notifications,
    required JwtService jwt,
    required String internalKey,
  })  : _events = events,
        _applications = applications,
        _cast = cast,
        _users = users,
        _chat = chat,
        _notifications = notifications,
        _jwt = jwt,
        _internalKey = internalKey;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.get('/events', _listEvents);
    r.get('/events/<id>', _getEvent);

    r.post('/events', _withAdmin(_createEvent));
    r.put('/events/<id>', _withAdmin(_updateEvent));
    r.delete('/events/<id>', _withAdmin(_cancelEvent));
    r.put('/events/<id>/roles', _withAdmin(_setRoles));
    r.put('/events/<id>/status', _withAdmin(_setStatus));

    r.post('/events/<id>/apply', _withAuth(_applyToEvent));
    r.get('/events/<id>/my_applications', _withAuth(_listMyApplications));
    r.delete('/events/<id>/applications/<applicationId>', _withAuth(_cancelApplication));

    r.get('/events/<id>/applications', _withAdmin(_listApplications));
    r.put('/events/<id>/applications/<applicationId>',
        _withAdmin(_updateApplicationStatus));

    r.get('/events/<id>/cast', _withAuth(_getCast));
    r.put('/events/<id>/cast', _withAdmin(_setCast));

    r.post('/events/<id>/approve_cast', _withAdmin(_approveCast));
    r.post('/events/<id>/finish', _withAdmin(_finishEvent));

    r.post('/events/<id>/call', _withAdmin(_callEvent));
    r.post('/events/<id>/call_emergency', _withAdmin(_callEmergency));

    r.get('/internal/events/<id>/cast/check', _withInternal(_checkCast));

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addHandler(handler);

  Handler _withAdmin(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addMiddleware(requireAdmin())
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

  Future<Response> _listEvents(Request request) async {
    final params = request.url.queryParameters;

    final from = _parseDateTime(params['from']);
    final to = _parseDateTime(params['to']);

    if ((params['from'] != null && from == null) ||
        (params['to'] != null && to == null)) {
      return _json(400, {'error': 'invalid_date_range'});
    }

    if (from != null && to != null && from.isAfter(to)) {
      return _json(400, {'error': 'invalid_date_range'});
    }

    final events = await _events.listEvents(
      from: from,
      to: to,
      disciplineId: params['disciplineId'],
      roleId: params['roleId'],
      status: params['status'],
    );

    final items = <Map<String, dynamic>>[];
    for (final event in events) {
      final roles = await _events.listRoles(event.id);
      items.add(_eventToJson(event, roles));
    }

    return _json(200, {'events': items});
  }

  Future<Response> _getEvent(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final roles = await _events.listRoles(event.id);

    return _json(200, _eventToJson(event, roles));
  }

  Future<Response> _createEvent(Request request) async {
    final auth = requireAuth(request);
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final title = body['title'] as String?;
    final description = body['description'] as String?;
    final disciplineId = body['disciplineId'] as String?;
    final startsAt = _parseDateTime(body['startsAt'] as String?);
    final endsAt = _parseDateTime(body['endsAt'] as String?);
    final streamUrl = body['streamUrl'] as String?;

    if (title == null || title.isEmpty ||
        description == null || description.isEmpty ||
        disciplineId == null || disciplineId.isEmpty ||
        startsAt == null || endsAt == null) {
      return _json(400, {'error': 'invalid_event_fields'});
    }

    if (!startsAt.isBefore(endsAt)) {
      return _json(400, {'error': 'invalid_event_time'});
    }

    final rolesInput = body['roles'];
    final roles = _parseRolesInput(rolesInput, eventId: 'temp');
    if (roles == null) return _json(400, {'error': 'invalid_roles'});

    final eventId = _uuid.v4();
    final event = await _events.createEvent(
      id: eventId,
      title: title,
      description: description,
      disciplineId: disciplineId,
      startsAt: startsAt,
      endsAt: endsAt,
      streamUrl: streamUrl,
      status: 'recruiting',
      createdBy: auth.claims.userId,
    );

    final rolesWithId = roles
        .map((r) => EventRoleRecord(
              id: _uuid.v4(),
              eventId: eventId,
              roleId: r.roleId,
              requiredCount: r.requiredCount,
            ))
        .toList();

    if (rolesWithId.isNotEmpty) {
      await _events.replaceRoles(eventId, rolesWithId);
    }

    final storedRoles = await _events.listRoles(eventId);
    return _json(201, _eventToJson(event, storedRoles));
  }

  Future<Response> _updateEvent(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final title = body['title'] as String?;
    final description = body['description'] as String?;
    final disciplineId = body['disciplineId'] as String?;
    final startsAt = _parseDateTime(body['startsAt'] as String?);
    final endsAt = _parseDateTime(body['endsAt'] as String?);
    final streamUrl = body['streamUrl'] as String?;

    if (title == null || title.isEmpty ||
        description == null || description.isEmpty ||
        disciplineId == null || disciplineId.isEmpty ||
        startsAt == null || endsAt == null) {
      return _json(400, {'error': 'invalid_event_fields'});
    }

    if (!startsAt.isBefore(endsAt)) {
      return _json(400, {'error': 'invalid_event_time'});
    }

    final updated = await _events.updateEvent(
      id: id,
      title: title,
      description: description,
      disciplineId: disciplineId,
      startsAt: startsAt,
      endsAt: endsAt,
      streamUrl: streamUrl,
    );

    if (updated == null) return _json(404, {'error': 'event_not_found'});

    final roles = await _events.listRoles(id);
    return _json(200, _eventToJson(updated, roles));
  }

  Future<Response> _cancelEvent(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final ok = await _events.cancelEvent(id);
    if (!ok) return _json(404, {'error': 'event_not_found'});

    return _json(200, {'ok': true});
  }

  Future<Response> _setRoles(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final exists = await _events.findById(id);
    if (exists == null) return _json(404, {'error': 'event_not_found'});

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final rolesInput = body['roles'];
    final parsed = _parseRolesInput(rolesInput, eventId: id);
    if (parsed == null) return _json(400, {'error': 'invalid_roles'});

    final roles = parsed
        .map((r) => EventRoleRecord(
              id: _uuid.v4(),
              eventId: id,
              roleId: r.roleId,
              requiredCount: r.requiredCount,
            ))
        .toList();

    await _events.replaceRoles(id, roles);

    final stored = await _events.listRoles(id);
    return _json(200, {'roles': stored.map((r) => r.toJson()).toList()});
  }

  Future<Response> _setStatus(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final status = body['status'] as String?;
    if (status == null || !_allowedStatuses.contains(status)) {
      return _json(400, {'error': 'invalid_status'});
    }

    final ok = await _events.updateStatus(id: id, status: status);
    if (!ok) return _json(404, {'error': 'event_not_found'});

    return _json(200, {'ok': true});
  }

  Future<Response> _applyToEvent(Request request) async {
    final auth = requireAuth(request);
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final roleIds = _parseIdList(body['roleIds']);
    if (roleIds == null || roleIds.isEmpty) {
      return _json(400, {'error': 'roleIds_required'});
    }

    if (_hasDuplicates(roleIds)) {
      return _json(400, {'error': 'duplicate_role_ids'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    if (event.status != 'recruiting') {
      return _json(400, {'error': 'event_not_recruiting'});
    }

    final roles = await _events.listRoles(id);
    final roleSet = roles.map((r) => r.roleId).toSet();
    if (!roleIds.every(roleSet.contains)) {
      return _json(400, {'error': 'invalid_role_ids'});
    }

    final created = await _applications.createApplications(
      eventId: id,
      userId: auth.claims.userId,
      roleIds: roleIds,
      status: 'pending',
    );

    return _json(201, {
      'applications': created.map((a) => a.toJson()).toList(),
    });
  }

  Future<Response> _listMyApplications(Request request) async {
    final auth = requireAuth(request);
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final items = await _applications.listForUser(
      eventId: id,
      userId: auth.claims.userId,
    );

    return _json(200, {'applications': items.map((a) => a.toJson()).toList()});
  }

  Future<Response> _cancelApplication(Request request) async {
    final auth = requireAuth(request);
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }
    final appId = request.params['applicationId'];
    if (appId == null || appId.isEmpty) {
      return _json(400, {'error': 'missing_application_id'});
    }

    final ok = await _applications.deleteApplication(
      eventId: eventId,
      applicationId: appId,
      userId: auth.claims.userId,
    );

    if (!ok) return _json(404, {'error': 'application_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _listApplications(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final applications = await _applications.listForEvent(id);

    if (applications.isEmpty) {
      return _json(200, {'applications': []});
    }

    final userIds = applications.map((a) => a.userId).toSet().toList();
    final users = await _fetchUsers(userIds);
    if (users == null) return _json(502, {'error': 'user_service_unavailable'});

    final userMap = _mapUsersById(users);

    final items = applications.map((a) {
      return {
        'id': a.id,
        'eventId': a.eventId,
        'roleId': a.roleId,
        'status': a.status,
        'createdAt': a.createdAt.toUtc().toIso8601String(),
        'user': userMap[a.userId],
      };
    }).toList();

    return _json(200, {'applications': items});
  }

  Future<Response> _updateApplicationStatus(Request request) async {
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }
    final appId = request.params['applicationId'];
    if (appId == null || appId.isEmpty) {
      return _json(400, {'error': 'missing_application_id'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final status = body['status'] as String?;
    if (status == null || (status != 'approved' && status != 'rejected')) {
      return _json(400, {'error': 'invalid_status'});
    }

    final updated = await _applications.updateStatus(
      eventId: eventId,
      applicationId: appId,
      status: status,
    );

    if (updated == null) return _json(404, {'error': 'application_not_found'});

    return _json(200, updated.toJson());
  }

  Future<Response> _getCast(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final cast = await _cast.listForEvent(id);
    if (cast.isEmpty) return _json(200, {'cast': []});

    final userIds = cast.map((c) => c.userId).toSet().toList();
    final users = await _fetchUsers(userIds);
    if (users == null) return _json(502, {'error': 'user_service_unavailable'});

    final userMap = _mapUsersById(users);

    final items = cast.map((c) {
      return {
        'id': c.id,
        'roleId': c.roleId,
        'user': userMap[c.userId],
      };
    }).toList();

    return _json(200, {'cast': items});
  }

  Future<Response> _setCast(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final castInput = body['cast'];
    if (castInput is! List) return _json(400, {'error': 'invalid_cast'});

    final roles = await _events.listRoles(id);
    final roleSet = roles.map((r) => r.roleId).toSet();

    final cast = <EventCastRecord>[];
    for (final entry in castInput) {
      if (entry is! Map<String, dynamic>) return _json(400, {'error': 'invalid_cast'});
      final userId = entry['userId'] as String?;
      final roleId = entry['roleId'] as String?;
      if (userId == null || userId.isEmpty || roleId == null || roleId.isEmpty) {
        return _json(400, {'error': 'invalid_cast'});
      }
      if (!roleSet.contains(roleId)) {
        return _json(400, {'error': 'invalid_role_ids'});
      }
      cast.add(EventCastRecord(
        id: _uuid.v4(),
        eventId: id,
        userId: userId,
        roleId: roleId,
      ));
    }

    await _cast.replaceCast(id, cast);

    final stored = await _cast.listForEvent(id);
    return _json(200, {'cast': stored.map((c) => c.toJson()).toList()});
  }

  Future<Response> _approveCast(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final body = await _tryReadJson(request) ?? <String, dynamic>{};

    final createChat = body['createChat'] == true;

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    if (event.status != 'recruiting') {
      return _json(400, {'error': 'event_not_recruiting'});
    }

    final now = DateTime.now().toUtc();
    final start = event.startsAt.toUtc();
    final windowStart = start.subtract(const Duration(minutes: 30));
    final windowEnd = start.add(const Duration(minutes: 30));

    if (now.isBefore(windowStart) || now.isAfter(windowEnd)) {
      return _json(400, {'error': 'approve_window_closed'});
    }

    if (createChat) {
      try {
        final chatId = await _chat.createChat(event.id);
        if (chatId != null) {
          await _chat.activateChat(chatId);
          await _events.setChatId(eventId: event.id, chatId: chatId);
        }
      } catch (_) {
        return _json(502, {'error': 'chat_service_unavailable'});
      }
    }

    final ok = await _events.updateStatus(id: event.id, status: 'approved');
    if (!ok) return _json(500, {'error': 'event_status_update_failed'});

    return _json(200, {'ok': true});
  }

  Future<Response> _finishEvent(Request request) async {
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(id);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    if (event.status == 'finished' || event.status == 'canceled') {
      return _json(400, {'error': 'event_not_active'});
    }

    if (event.chatId != null) {
      try {
        await _chat.deactivateChat(event.chatId!);
      } catch (_) {
        return _json(502, {'error': 'chat_service_unavailable'});
      }
    }

    final ok = await _events.updateStatus(id: event.id, status: 'finished');
    if (!ok) return _json(500, {'error': 'event_status_update_failed'});

    return _json(200, {'ok': true});
  }

  Future<Response> _callEvent(Request request) async {
    return _callEventInternal(request, type: 'normal');
  }

  Future<Response> _callEmergency(Request request) async {
    return _callEventInternal(request, type: 'emergency');
  }

  Future<Response> _callEventInternal(Request request,
      {required String type}) async {
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final event = await _events.findById(eventId);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final roleIds =
        _parseIdList(body['roles']) ?? _parseIdList(body['roleIds']);

    final userIdsInput = _parseIdList(body['userIds']);

    if ((roleIds == null || roleIds.isEmpty) &&
        (userIdsInput == null || userIdsInput.isEmpty)) {
      return _json(400, {'error': 'roles_or_user_ids_required'});
    }

    final authHeader = _extractAuthHeader(request);
    if (authHeader == null) {
      return _json(401, {'error': 'missing_bearer_token'});
    }

    List<String> userIds;
    if (userIdsInput != null && userIdsInput.isNotEmpty) {
      userIds = userIdsInput;
    } else {
      final resolved = await _resolveUserIdsForRoles(roleIds!, authHeader);
      if (resolved == null) {
        return _json(502, {'error': 'user_service_unavailable'});
      }
      userIds = resolved;
    }

    userIds = userIds.toSet().toList();

    if (userIds.isEmpty) {
      return _json(200, {'ok': true, 'requested': 0, 'sent': 0, 'failed': 0});
    }

    final title =
        type == 'emergency' ? 'Emergency call: ${event.title}' : 'Event call: ${event.title}';
    final message = type == 'emergency'
        ? 'Urgent call for event participants.'
        : 'New event call is available.';

    try {
      final result = await _notifications.sendEventCall(
        eventId: event.id,
        userIds: userIds,
        roles: roleIds ?? const [],
        type: type,
        title: title,
        message: message,
      );

      return _json(200, {
        'ok': true,
        'notification': result.toJson(),
      });
    } catch (_) {
      return _json(502, {'error': 'notification_service_unavailable'});
    }
  }

  Future<Response> _checkCast(Request request) async {
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final userId = request.url.queryParameters['userId'];
    if (userId == null || userId.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }

    final event = await _events.findById(eventId);
    if (event == null) return _json(404, {'error': 'event_not_found'});

    final inCast = await _cast.isUserInCast(eventId: eventId, userId: userId);
    return _json(200, {'inCast': inCast});
  }

  Future<List<String>?> _resolveUserIdsForRoles(
      List<String> roleIds, String authHeader) async {
    final result = <String>{};
    try {
      for (final roleId in roleIds) {
        final userIds = await _users.fetchUserIdsByRole(
          roleId: roleId,
          authHeader: authHeader,
        );
        result.addAll(userIds);
      }
      return result.toList();
    } catch (_) {
      return null;
    }
  }

  String? _extractAuthHeader(Request request) {
    final auth = request.headers['authorization'];
    if (auth == null || auth.isEmpty) return null;
    return auth;
  }

  Future<List<Map<String, dynamic>>?> _fetchUsers(List<String> userIds) async {
    try {
      return await _users.fetchUsersBulk(userIds: userIds);
    } catch (_) {
      return null;
    }
  }

  Map<String, Map<String, dynamic>> _mapUsersById(
      List<Map<String, dynamic>> users) {
    final map = <String, Map<String, dynamic>>{};
    for (final user in users) {
      final id = user['id'];
      if (id is String) {
        map[id] = user;
      }
    }
    return map;
  }

  Map<String, dynamic> _eventToJson(EventRecord event, List<EventRoleRecord> roles) {
    return {
      'id': event.id,
      'title': event.title,
      'description': event.description,
      'disciplineId': event.disciplineId,
      'startsAt': event.startsAt.toUtc().toIso8601String(),
      'endsAt': event.endsAt.toUtc().toIso8601String(),
      'streamUrl': event.streamUrl,
      'status': event.status,
      'roles': roles.map((r) => r.toJson()).toList(),
    };
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

  DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } catch (_) {
      return null;
    }
  }

  List<EventRoleRecord>? _parseRolesInput(dynamic input, {required String eventId}) {
    if (input == null) return <EventRoleRecord>[];
    if (input is! List) return null;

    final roles = <EventRoleRecord>[];
    for (final item in input) {
      if (item is! Map<String, dynamic>) return null;
      final roleId = item['roleId'] as String?;
      final requiredCount = item['requiredCount'];
      if (roleId == null || roleId.isEmpty) return null;
      if (requiredCount is! int || requiredCount <= 0) return null;
      roles.add(EventRoleRecord(
        id: _uuid.v4(),
        eventId: eventId,
        roleId: roleId,
        requiredCount: requiredCount,
      ));
    }

    return roles;
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

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}

const List<String> _allowedStatuses = [
  'draft',
  'recruiting',
  'approved',
  'active',
  'finished',
  'canceled',
];
