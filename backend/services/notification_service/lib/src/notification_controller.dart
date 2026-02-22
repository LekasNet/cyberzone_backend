import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'auth_middleware.dart';
import 'fcm_client.dart';
import 'jwt_service.dart';
import 'notification_repository.dart';

class NotificationController {
  final NotificationRepository _tokens;
  final JwtService _jwt;
  final String _internalKey;
  final FcmClient _fcm;
  final _uuid = const Uuid();

  NotificationController({
    required NotificationRepository tokens,
    required JwtService jwt,
    required String internalKey,
    required FcmClient fcm,
  })  : _tokens = tokens,
        _jwt = jwt,
        _internalKey = internalKey,
        _fcm = fcm;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.post('/notifications/register_token', _withAuth(_registerToken));
    r.delete('/notifications/unregister_token', _withAuth(_unregisterToken));

    r.post('/notifications/event_call', _withInternal(_eventCall));
    r.post('/notifications/event_status_changed', _withInternal(_eventStatusChanged));
    r.post(
        '/notifications/application_status_changed', _withInternal(_applicationStatus));
    r.post('/notifications/chat_message', _withInternal(_chatMessage));

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addHandler(handler);

  Handler _withInternal(Handler handler) =>
      Pipeline().addMiddleware(_internalAuth()).addHandler(handler);

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

  Future<Response> _registerToken(Request request) async {
    final auth = requireAuth(request);
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final deviceToken = body['deviceToken'] as String?;
    final platform = body['platform'] as String?;

    if (deviceToken == null || deviceToken.isEmpty) {
      return _json(400, {'error': 'device_token_required'});
    }
    if (platform == null || platform.isEmpty) {
      return _json(400, {'error': 'platform_required'});
    }

    await _tokens.registerToken(
      id: _uuid.v4(),
      userId: auth.claims.userId,
      deviceToken: deviceToken,
      platform: platform,
    );

    return _json(200, {'ok': true});
  }

  Future<Response> _unregisterToken(Request request) async {
    final auth = requireAuth(request);
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final deviceToken = body['deviceToken'] as String?;
    if (deviceToken == null || deviceToken.isEmpty) {
      return _json(400, {'error': 'device_token_required'});
    }

    final deleted = await _tokens.unregisterToken(
      userId: auth.claims.userId,
      deviceToken: deviceToken,
    );

    return _json(200, {'ok': true, 'deleted': deleted});
  }

  Future<Response> _eventCall(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final eventId = body['eventId'] as String?;
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'event_id_required'});
    }

    final userIds = _parseIdList(body['userIds']);
    if (userIds == null || userIds.isEmpty) {
      return _json(400, {'error': 'user_ids_required'});
    }

    final type = body['type'] as String? ?? 'normal';
    final roles = _parseIdList(body['roles']) ?? <String>[];
    final title = body['title'] as String? ??
        (type == 'emergency' ? 'Emergency call' : 'Event call');
    final message = body['message'] as String? ?? 'New event call is available.';

    return _sendToUsers(
      userIds: userIds,
      title: title,
      message: message,
      data: {
        'type': type,
        'eventId': eventId,
        if (roles.isNotEmpty) 'roles': roles.join(','),
      },
    );
  }

  Future<Response> _eventStatusChanged(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final eventId = body['eventId'] as String?;
    final newStatus = body['newStatus'] as String?;
    final userIds = _parseIdList(body['userIds']);

    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'event_id_required'});
    }
    if (newStatus == null || newStatus.isEmpty) {
      return _json(400, {'error': 'new_status_required'});
    }
    if (userIds == null || userIds.isEmpty) {
      return _json(400, {'error': 'user_ids_required'});
    }

    final title =
        body['title'] as String? ?? 'Event status changed';
    final message =
        body['message'] as String? ?? 'Event status updated to $newStatus.';

    return _sendToUsers(
      userIds: userIds,
      title: title,
      message: message,
      data: {
        'type': 'event_status_changed',
        'eventId': eventId,
        'status': newStatus,
      },
    );
  }

  Future<Response> _applicationStatus(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final eventId = body['eventId'] as String?;
    final userId = body['userId'] as String?;
    final newStatus = body['newStatus'] as String?;

    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'event_id_required'});
    }
    if (userId == null || userId.isEmpty) {
      return _json(400, {'error': 'user_id_required'});
    }
    if (newStatus == null || newStatus.isEmpty) {
      return _json(400, {'error': 'new_status_required'});
    }

    final title = body['title'] as String? ?? 'Application status';
    final message = body['message'] as String? ??
        'Your application status is $newStatus.';

    return _sendToUsers(
      userIds: [userId],
      title: title,
      message: message,
      data: {
        'type': 'application_status_changed',
        'eventId': eventId,
        'status': newStatus,
      },
    );
  }

  Future<Response> _chatMessage(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final chatId = body['chatId'] as String?;
    final messageId = body['messageId'] as String?;
    final userIds = _parseIdList(body['userIds']);

    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'chat_id_required'});
    }
    if (messageId == null || messageId.isEmpty) {
      return _json(400, {'error': 'message_id_required'});
    }
    if (userIds == null || userIds.isEmpty) {
      return _json(400, {'error': 'user_ids_required'});
    }

    final title = body['title'] as String? ?? 'New message';
    final message = body['message'] as String? ??
        'You have a new message in the event chat.';

    return _sendToUsers(
      userIds: userIds,
      title: title,
      message: message,
      data: {
        'type': 'chat_message',
        'chatId': chatId,
        'messageId': messageId,
      },
    );
  }

  Future<Response> _sendToUsers({
    required List<String> userIds,
    required String title,
    required String message,
    required Map<String, String> data,
  }) async {
    final tokens = await _tokens.getTokensForUsers(userIds);
    final uniqueTokens = tokens.toSet().toList();

    if (uniqueTokens.isEmpty) {
      return _json(200, {
        'ok': true,
        'requested': 0,
        'sent': 0,
        'failed': 0,
        'skipped': false,
      });
    }

    try {
      final result = await _fcm.send(
        tokens: uniqueTokens,
        title: title,
        body: message,
        data: data,
      );

      if (result.sent > 0) {
        await _tokens.touchTokens(uniqueTokens);
      }

      return _json(200, result.toJson());
    } on FcmException catch (e) {
      return _json(500, {'error': e.code});
    } catch (_) {
      return _json(500, {'error': 'notification_failed'});
    }
  }

  Future<Map<String, dynamic>?> _tryReadJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
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

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}
