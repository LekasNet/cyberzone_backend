import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_middleware.dart';
import 'chat_repository.dart';
import 'event_service_client.dart';
import 'message_repository.dart';
import 'models.dart';
import 'user_service_client.dart';
import 'jwt_service.dart';

class ChatController {
  final ChatRepository _chats;
  final MessageRepository _messages;
  final EventServiceClient _events;
  final UserServiceClient _users;
  final JwtService _jwt;
  final String _internalKey;
  final _uuid = const Uuid();
  final Map<String, Set<WebSocketChannel>> _channels = {};

  ChatController({
    required ChatRepository chats,
    required MessageRepository messages,
    required EventServiceClient events,
    required UserServiceClient users,
    required JwtService jwt,
    required String internalKey,
  })  : _chats = chats,
        _messages = messages,
        _events = events,
        _users = users,
        _jwt = jwt,
        _internalKey = internalKey;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.post('/chats', _withInternal(_createChat));
    r.put('/chats/<id>/activate', _withInternal(_activateChat));
    r.put('/chats/<id>/deactivate', _withInternal(_deactivateChat));

    r.get('/events/<eventId>/chat', _withAuth(_getChatByEvent));
    r.get('/chats/<chatId>/messages', _withAuth(_listMessages));
    r.post('/chats/<chatId>/messages', _withAuth(_sendMessage));
    r.get('/chats/<chatId>/ws', _handleWebSocket);

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
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

  Future<Response> _createChat(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final eventId = body['eventId'] as String?;
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'eventId_required'});
    }

    final existing = await _chats.findByEventId(eventId);
    if (existing != null) {
      return _json(200, {'chatId': existing.id});
    }

    final chat = await _chats.createChat(id: _uuid.v4(), eventId: eventId);
    return _json(201, {'chatId': chat.id});
  }

  Future<Response> _activateChat(Request request) async {
    final chatId = request.params['id'];
    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'missing_chat_id'});
    }

    final chat = await _chats.setActive(chatId: chatId, isActive: true);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    return _json(200, {'ok': true});
  }

  Future<Response> _deactivateChat(Request request) async {
    final chatId = request.params['id'];
    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'missing_chat_id'});
    }

    final chat = await _chats.setActive(chatId: chatId, isActive: false);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    return _json(200, {'ok': true});
  }

  Future<Response> _getChatByEvent(Request request) async {
    final auth = requireAuth(request);
    final eventId = request.params['eventId'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final chat = await _chats.findByEventId(eventId);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    final allowed = await _isAllowed(eventId, auth);
    if (!allowed) return _json(403, {'error': 'forbidden'});

    return _json(200, chat.toJson());
  }

  Future<Response> _handleWebSocket(Request request) async {
    final chatId = request.params['chatId'];
    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'missing_chat_id'});
    }

    final auth = _authFromRequest(request);
    if (auth == null) {
      return _json(401, {'error': 'missing_bearer_token'});
    }

    final chat = await _chats.findById(chatId);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    final isAdmin = auth.claims.isAdmin || auth.claims.isSuperAdmin;
    if (!isAdmin) {
      final allowed = await _isAllowed(chat.eventId, auth);
      if (!allowed) return _json(403, {'error': 'forbidden'});
    }

    final userInfo = await _fetchUser(auth.claims.userId);

    final handler = webSocketHandler((WebSocketChannel channel) {
      _registerChannel(chatId, channel);

      channel.stream.listen(
        (data) async {
          if (data is! String) return;
          final parsed = _decodeJson(data);
          if (parsed == null) {
            _sendWsError(channel, 'invalid_json');
            return;
          }

          final text = parsed['text'] as String?;
          if (text == null || text.trim().isEmpty) {
            _sendWsError(channel, 'text_required');
            return;
          }

          final currentChat = await _chats.findById(chatId);
          if (currentChat == null) {
            _sendWsError(channel, 'chat_not_found');
            return;
          }

          if (!currentChat.isActive && !isAdmin) {
            _sendWsError(channel, 'chat_inactive');
            return;
          }

          if (!isAdmin) {
            final allowed = await _isAllowed(currentChat.eventId, auth);
            if (!allowed) {
              _sendWsError(channel, 'forbidden');
              return;
            }
          }

          final message = await _messages.createMessage(
            id: _uuid.v4(),
            chatId: chatId,
            userId: auth.claims.userId,
            text: text.trim(),
          );

          final payload = message.toJson();
          if (userInfo != null) {
            payload['user'] = userInfo;
          }

          _broadcast(chatId, payload);
        },
        onDone: () => _unregisterChannel(chatId, channel),
        onError: (_) => _unregisterChannel(chatId, channel),
      );
    });

    return handler(request);
  }

  Future<Response> _listMessages(Request request) async {
    final auth = requireAuth(request);
    final chatId = request.params['chatId'];
    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'missing_chat_id'});
    }

    final chat = await _chats.findById(chatId);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    final allowed = await _isAllowed(chat.eventId, auth);
    if (!allowed) return _json(403, {'error': 'forbidden'});

    final limit = _parseLimit(request.url.queryParameters['limit']);
    final cursor = _decodeCursor(request.url.queryParameters['cursor']);

    final messages = await _messages.listMessages(
      chatId: chatId,
      limit: limit + 1,
      cursorTime: cursor?.time,
      cursorId: cursor?.id,
    );

    final hasMore = messages.length > limit;
    final items = hasMore ? messages.take(limit).toList() : messages;

    final ordered = items.reversed.toList();

    final userIds = ordered
        .map((m) => m.userId)
        .whereType<String>()
        .toSet()
        .toList();

    Map<String, Map<String, dynamic>> usersById = {};
    if (userIds.isNotEmpty) {
      try {
        final users = await _users.fetchUsersBulk(userIds: userIds);
        usersById = _mapUsersById(users);
      } catch (_) {
        return _json(502, {'error': 'user_service_unavailable'});
      }
    }

    final payload = ordered.map((message) {
      final map = message.toJson();
      final userId = message.userId;
      if (userId != null) {
        map['user'] = usersById[userId];
      }
      return map;
    }).toList();

    final nextCursor = hasMore ? _encodeCursor(items.last) : null;

    return _json(200, {
      'messages': payload,
      'nextCursor': nextCursor,
    });
  }

  Future<Response> _sendMessage(Request request) async {
    final auth = requireAuth(request);
    final chatId = request.params['chatId'];
    if (chatId == null || chatId.isEmpty) {
      return _json(400, {'error': 'missing_chat_id'});
    }

    final chat = await _chats.findById(chatId);
    if (chat == null) return _json(404, {'error': 'chat_not_found'});

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final text = body['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      return _json(400, {'error': 'text_required'});
    }

    final isAdmin = auth.claims.isAdmin || auth.claims.isSuperAdmin;

    if (!chat.isActive && !isAdmin) {
      return _json(403, {'error': 'chat_inactive'});
    }

    if (!isAdmin) {
      final allowed = await _isAllowed(chat.eventId, auth);
      if (!allowed) return _json(403, {'error': 'forbidden'});
    }

    final message = await _messages.createMessage(
      id: _uuid.v4(),
      chatId: chatId,
      userId: auth.claims.userId,
      text: text.trim(),
    );

    final response = message.toJson();
    try {
      final users = await _users.fetchUsersBulk(userIds: [auth.claims.userId]);
      if (users.isNotEmpty) {
        response['user'] = users.first;
      }
    } catch (_) {
      // ignore user enrichment failures
    }

    return _json(201, response);
  }

  AuthContext? _authFromRequest(Request request) {
    final header = request.headers['authorization'];
    String? token;
    if (header != null && header.toLowerCase().startsWith('bearer ')) {
      token = header.substring('bearer '.length).trim();
    }
    token ??= request.url.queryParameters['token'];
    if (token == null || token.isEmpty) return null;

    try {
      final claims = _jwt.verifyAccessToken(token);
      if (claims.isBanned) return null;
      return AuthContext(claims);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isAllowed(String eventId, AuthContext auth) async {
    if (auth.claims.isAdmin || auth.claims.isSuperAdmin) return true;
    try {
      return await _events.isUserInCast(
        eventId: eventId,
        userId: auth.claims.userId,
      );
    } catch (_) {
      return false;
    }
  }

  void _registerChannel(String chatId, WebSocketChannel channel) {
    final set = _channels.putIfAbsent(chatId, () => <WebSocketChannel>{});
    set.add(channel);
  }

  void _unregisterChannel(String chatId, WebSocketChannel channel) {
    final set = _channels[chatId];
    if (set == null) return;
    set.remove(channel);
    if (set.isEmpty) {
      _channels.remove(chatId);
    }
  }

  void _broadcast(String chatId, Map<String, dynamic> payload) {
    final set = _channels[chatId];
    if (set == null || set.isEmpty) return;
    final encoded = jsonEncode(payload);
    for (final channel in set) {
      channel.sink.add(encoded);
    }
  }

  void _sendWsError(WebSocketChannel channel, String code) {
    channel.sink.add(jsonEncode({'error': code}));
  }

  int _parseLimit(String? value) {
    if (value == null) return 50;
    final parsed = int.tryParse(value);
    if (parsed == null) return 50;
    if (parsed < 1) return 1;
    if (parsed > 100) return 100;
    return parsed;
  }

  _Cursor? _decodeCursor(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('|');
    if (parts.length != 2) return null;
    final millis = int.tryParse(parts[0]);
    if (millis == null) return null;
    final id = parts[1];
    if (id.isEmpty) return null;
    return _Cursor(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true), id);
  }

  String _encodeCursor(ChatMessageRecord message) {
    final millis = message.createdAt.toUtc().millisecondsSinceEpoch;
    return '$millis|${message.id}';
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

  Map<String, dynamic>? _decodeJson(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchUser(String userId) async {
    try {
      final users = await _users.fetchUsersBulk(userIds: [userId]);
      if (users.isNotEmpty) return users.first;
    } catch (_) {
      return null;
    }
    return null;
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}

class _Cursor {
  final DateTime time;
  final String id;

  _Cursor(this.time, this.id);
}
