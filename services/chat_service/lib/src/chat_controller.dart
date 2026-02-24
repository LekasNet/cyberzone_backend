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
  final Map<String, Set<WebSocketChannel>> _channelsByChat = {};
  final Map<WebSocketChannel, Set<String>> _subsByChannel = {};

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

    r.get('/chats/permanent', _withAuth(_listPermanentChats));
    r.post('/chats/permanent', _withAuth(_createPermanentChat));

    r.get('/events/<eventId>/chat', _withAuth(_getChatByEvent));
    r.get('/chats/<chatId>/messages', _withAuth(_listMessages));
    r.post('/chats/<chatId>/messages', _withAuth(_sendMessage));

    r.get('/chats/<chatId>/ws', _handleWebSocket);
    r.get('/chats/ws', _handleGlobalWebSocket);

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

  Future<Response> _createPermanentChat(Request request) async {
    final auth = requireAuth(request);
    if (!_isAdmin(auth)) {
      return _json(403, {'error': 'forbidden'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final title = (body['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return _json(400, {'error': 'title_required'});
    }

    final chat = await _chats.createPermanentChat(
      id: _uuid.v4(),
      title: title,
      createdBy: auth.claims.userId,
    );

    return _json(201, chat.toJson());
  }

  Future<Response> _listPermanentChats(Request request) async {
    final chats = await _chats.listPermanentChats();
    return _json(200, {
      'chats': chats.map((chat) => chat.toJson()).toList(),
    });
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

    final allowed = await _canAccessChat(chat, auth);
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

    final allowed = await _canAccessChat(chat, auth);
    if (!allowed) return _json(403, {'error': 'forbidden'});

    final isAdmin = _isAdmin(auth);
    final userInfo = await _fetchUser(auth.claims.userId);

    final handler = webSocketHandler((WebSocketChannel channel) {
      _subscribe(chatId, channel);

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

          await _processChatMessage(
            chatId: chatId,
            text: text,
            auth: auth,
            userInfo: userInfo,
            isAdmin: isAdmin,
            channel: channel,
          );
        },
        onDone: () => _cleanupChannel(channel),
        onError: (_) => _cleanupChannel(channel),
      );
    });

    return handler(request);
  }

  Future<Response> _handleGlobalWebSocket(Request request) async {
    final auth = _authFromRequest(request);
    if (auth == null) {
      return _json(401, {'error': 'missing_bearer_token'});
    }

    final isAdmin = _isAdmin(auth);
    final userInfo = await _fetchUser(auth.claims.userId);

    final handler = webSocketHandler((WebSocketChannel channel) {
      channel.stream.listen(
        (data) async {
          if (data is! String) return;
          final parsed = _decodeJson(data);
          if (parsed == null) {
            _sendWsError(channel, 'invalid_json');
            return;
          }

          final type = parsed['type'] as String?;

          if (type == 'subscribe') {
            final chatIds = _parseIdList(parsed['chatIds']) ??
                _singleId(parsed['chatId']);
            if (chatIds == null || chatIds.isEmpty) {
              _sendWsError(channel, 'chatIds_required');
              return;
            }

            final allowed = <String>[];
            final denied = <String>[];

            for (final id in chatIds) {
              final chat = await _chats.findById(id);
              if (chat == null) {
                denied.add(id);
                continue;
              }
              if (await _canAccessChat(chat, auth)) {
                _subscribe(id, channel);
                allowed.add(id);
              } else {
                denied.add(id);
              }
            }

            channel.sink.add(jsonEncode({
              'type': 'subscribed',
              'chatIds': allowed,
              if (denied.isNotEmpty) 'denied': denied,
            }));
            return;
          }

          if (type == 'unsubscribe') {
            final chatIds = _parseIdList(parsed['chatIds']) ??
                _singleId(parsed['chatId']);
            if (chatIds == null || chatIds.isEmpty) {
              _sendWsError(channel, 'chatIds_required');
              return;
            }

            for (final id in chatIds) {
              _unsubscribe(id, channel);
            }

            channel.sink.add(jsonEncode({
              'type': 'unsubscribed',
              'chatIds': chatIds,
            }));
            return;
          }

          final chatId = parsed['chatId'] as String?;
          final text = parsed['text'] as String?;
          if (chatId == null || chatId.isEmpty) {
            _sendWsError(channel, 'chatId_required');
            return;
          }
          if (text == null || text.trim().isEmpty) {
            _sendWsError(channel, 'text_required');
            return;
          }

          final subscribed = _subsByChannel[channel]?.contains(chatId) ?? false;
          if (!subscribed) {
            _sendWsError(channel, 'not_subscribed');
            return;
          }

          await _processChatMessage(
            chatId: chatId,
            text: text,
            auth: auth,
            userInfo: userInfo,
            isAdmin: isAdmin,
            channel: channel,
          );
        },
        onDone: () => _cleanupChannel(channel),
        onError: (_) => _cleanupChannel(channel),
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

    final allowed = await _canAccessChat(chat, auth);
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

    final isAdmin = _isAdmin(auth);

    if (!chat.isActive && !isAdmin) {
      return _json(403, {'error': 'chat_inactive'});
    }

    final allowed = await _canAccessChat(chat, auth);
    if (!allowed) return _json(403, {'error': 'forbidden'});

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

  bool _isAdmin(AuthContext auth) =>
      auth.claims.isAdmin || auth.claims.isSuperAdmin;

  Future<bool> _canAccessChat(ChatRecord chat, AuthContext auth) async {
    if (_isAdmin(auth)) return true;
    if (chat.type == 'permanent') return true;
    final eventId = chat.eventId;
    if (eventId == null) return false;
    try {
      return await _events.isUserInCast(
        eventId: eventId,
        userId: auth.claims.userId,
      );
    } catch (_) {
      return false;
    }
  }

  void _subscribe(String chatId, WebSocketChannel channel) {
    final set =
        _channelsByChat.putIfAbsent(chatId, () => <WebSocketChannel>{});
    set.add(channel);
    final subs = _subsByChannel.putIfAbsent(channel, () => <String>{});
    subs.add(chatId);
  }

  void _unsubscribe(String chatId, WebSocketChannel channel) {
    final subs = _subsByChannel[channel];
    subs?.remove(chatId);

    final set = _channelsByChat[chatId];
    if (set == null) return;
    set.remove(channel);
    if (set.isEmpty) {
      _channelsByChat.remove(chatId);
    }
  }

  void _cleanupChannel(WebSocketChannel channel) {
    final subs = _subsByChannel.remove(channel);
    if (subs == null) return;
    for (final chatId in subs) {
      final set = _channelsByChat[chatId];
      if (set == null) continue;
      set.remove(channel);
      if (set.isEmpty) {
        _channelsByChat.remove(chatId);
      }
    }
  }

  void _broadcast(String chatId, Map<String, dynamic> payload) {
    final set = _channelsByChat[chatId];
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

  Future<void> _processChatMessage({
    required String chatId,
    required String text,
    required AuthContext auth,
    required Map<String, dynamic>? userInfo,
    required bool isAdmin,
    required WebSocketChannel channel,
  }) async {
    final currentChat = await _chats.findById(chatId);
    if (currentChat == null) {
      _sendWsError(channel, 'chat_not_found');
      return;
    }

    if (!currentChat.isActive && !isAdmin) {
      _sendWsError(channel, 'chat_inactive');
      return;
    }

    final allowed = await _canAccessChat(currentChat, auth);
    if (!allowed) {
      _sendWsError(channel, 'forbidden');
      return;
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

  List<String>? _singleId(dynamic value) {
    if (value is String && value.isNotEmpty) return [value];
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
