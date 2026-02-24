library ws_chat_scenario;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'test_scenario.dart';
import 'ws_reporting.dart';

Future<void> runWebSocketScenario({
  required http.Client client,
  required TestConfig config,
  required WsLogger logger,
}) async {
  logger.add('scenario.start', 'Start WebSocket chat scenario');
  final adminEmail = 'admin_ws_${DateTime.now().millisecondsSinceEpoch}@test.local';
  final adminPassword = 'Password123!';

  final adminRegister = await _postJson(
    client,
    config.authUrl.resolve('/auth/register'),
    {'email': adminEmail, 'password': adminPassword},
    expectedStatus: 201,
  );
  logger.add('auth.register', 'Admin registered', data: adminRegister);

  final adminUserId = adminRegister['userId'] as String;
  await _promoteToSuperAdmin(config, adminUserId);

  final adminLogin = await _postJson(
    client,
    config.authUrl.resolve('/auth/login'),
    {'email': adminEmail, 'password': adminPassword},
    expectedStatus: 200,
  );
  logger.add('auth.login', 'Admin logged in');

  final adminToken = adminLogin['accessToken'] as String;

  final userEmail = 'user_ws_${DateTime.now().millisecondsSinceEpoch}@test.local';
  final userPassword = 'Password123!';

  final userRegister = await _postJson(
    client,
    config.authUrl.resolve('/auth/register'),
    {'email': userEmail, 'password': userPassword},
    expectedStatus: 201,
  );
  logger.add('auth.register', 'User registered', data: userRegister);

  final userId = userRegister['userId'] as String;

  final userLogin = await _postJson(
    client,
    config.authUrl.resolve('/auth/login'),
    {'email': userEmail, 'password': userPassword},
    expectedStatus: 200,
  );
  logger.add('auth.login', 'User logged in');

  final userToken = userLogin['accessToken'] as String;

  final roleId = const Uuid().v4();
  final now = DateTime.now().toUtc();
  final startsAt = now.add(const Duration(minutes: 5));
  final endsAt = now.add(const Duration(hours: 2));

  final event = await _postJson(
    client,
    config.eventUrl.resolve('/events'),
    {
      'title': 'WS Scenario Event',
      'description': 'WebSocket scenario event',
      'disciplineId': const Uuid().v4(),
      'startsAt': startsAt.toIso8601String(),
      'endsAt': endsAt.toIso8601String(),
      'roles': [
        {'roleId': roleId, 'requiredCount': 1}
      ]
    },
    token: adminToken,
    expectedStatus: 201,
  );
  logger.add('event.create', 'Event created', data: event);

  final eventId = event['id'] as String;

  await _putJson(
    client,
    config.eventUrl.resolve('/events/$eventId/cast'),
    {
      'cast': [
        {'userId': userId, 'roleId': roleId}
      ]
    },
    token: adminToken,
    expectedStatus: 200,
  );
  logger.add('event.cast', 'Cast assigned', data: {'eventId': eventId});

  await _postJson(
    client,
    config.eventUrl.resolve('/events/$eventId/approve_cast'),
    {'createChat': true},
    token: adminToken,
    expectedStatus: 200,
  );
  logger.add('event.approve', 'Event approved', data: {'eventId': eventId});

  final chat = await _getJson(
    client,
    config.chatUrl.resolve('/events/$eventId/chat'),
    token: userToken,
    expectedStatus: 200,
  );
  logger.add('chat.get', 'Chat resolved', data: chat);

  final chatId = chat['chatId'] as String;
  final wsUri = _buildWsUri(
    base: config.chatUrl,
    path: '/chats/ws',
    token: userToken,
  );

  final channel = WebSocketChannel.connect(wsUri);
  logger.add('ws.connect', 'WebSocket connected', data: {'uri': wsUri.toString()});
  final messages = <Map<String, dynamic>>[];
  final subscribed = Completer<void>();
  final done = Completer<void>();

  channel.stream.listen((data) {
    if (data is! String) return;
    final parsed = _decodeJson(data);
    if (parsed == null) return;
    if (parsed['type'] == 'subscribed') {
      if (!subscribed.isCompleted) {
        subscribed.complete();
      }
      logger.add('ws.subscribed', 'Subscribed to chats', data: parsed);
      return;
    }
    if (parsed['text'] is String) {
      messages.add(parsed);
      logger.add('ws.message', 'Message received', data: parsed);
      if (messages.length >= 3 && !done.isCompleted) {
        done.complete();
      }
    }
  });

  final subscribePayload = {
    'type': 'subscribe',
    'chatIds': [chatId],
  };
  channel.sink.add(jsonEncode(subscribePayload));
  logger.add('ws.subscribe', 'Subscribe sent', data: subscribePayload);
  await subscribed.future.timeout(const Duration(seconds: 5));

  for (var i = 1; i <= 3; i += 1) {
    final payload = {
      'type': 'message',
      'chatId': chatId,
      'text': 'ws message $i',
    };
    channel.sink.add(jsonEncode(payload));
    logger.add('ws.send', 'Message sent', data: payload);
  }

  await done.future.timeout(const Duration(seconds: 10));
  logger.add('ws.done', 'Received 3 messages');

  await _postJson(
    client,
    config.eventUrl.resolve('/events/$eventId/finish'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );
  logger.add('event.finish', 'Event finished', data: {'eventId': eventId});

  await channel.sink.close();
  logger.add('ws.close', 'WebSocket closed');
}

Future<void> _promoteToSuperAdmin(TestConfig config, String userId) async {
  final conn = PostgreSQLConnection(
    config.userDbHost,
    config.userDbPort,
    config.userDbName,
    username: config.userDbUser,
    password: config.userDbPassword,
  );

  await conn.open();
  await conn.query(
    'UPDATE users SET is_admin = TRUE, is_super_admin = TRUE WHERE id = @id',
    substitutionValues: {'id': userId},
  );
  await conn.close();
}

Uri _buildWsUri({
  required Uri base,
  required String path,
  required String token,
}) {
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  return base.replace(
    scheme: scheme,
    path: path,
    queryParameters: {'token': token},
  );
}

Future<Map<String, dynamic>> _postJson(
  http.Client client,
  Uri url,
  Map<String, dynamic> body, {
  String? token,
  int expectedStatus = 200,
}) async {
  final response = await client.post(
    url,
    headers: _headers(token),
    body: jsonEncode(body),
  );

  _ensure(
    response.statusCode == expectedStatus,
    'POST $url failed: ${response.statusCode} ${response.body}',
  );

  return _decodeJson(response.body) ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> _putJson(
  http.Client client,
  Uri url,
  Map<String, dynamic> body, {
  String? token,
  int expectedStatus = 200,
}) async {
  final response = await client.put(
    url,
    headers: _headers(token),
    body: jsonEncode(body),
  );

  _ensure(
    response.statusCode == expectedStatus,
    'PUT $url failed: ${response.statusCode} ${response.body}',
  );

  return _decodeJson(response.body) ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> _getJson(
  http.Client client,
  Uri url, {
  String? token,
  int expectedStatus = 200,
}) async {
  final response = await client.get(
    url,
    headers: _headers(token),
  );

  _ensure(
    response.statusCode == expectedStatus,
    'GET $url failed: ${response.statusCode} ${response.body}',
  );

  return _decodeJson(response.body) ?? <String, dynamic>{};
}

Map<String, String> _headers(String? token) {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

Map<String, dynamic>? _decodeJson(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    return null;
  }
  return null;
}

void _ensure(bool condition, String message) {
  if (!condition) throw StateError(message);
}
