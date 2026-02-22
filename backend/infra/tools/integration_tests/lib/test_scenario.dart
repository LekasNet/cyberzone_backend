library test_scenario;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import 'reporting.dart';

class TestConfig {
  final Uri authUrl;
  final Uri userUrl;
  final Uri scheduleUrl;
  final Uri eventUrl;
  final Uri ratingUrl;
  final Uri chatUrl;
  final Uri notificationUrl;
  final String internalApiKey;
  final String userDbHost;
  final int userDbPort;
  final String userDbName;
  final String userDbUser;
  final String userDbPassword;

  TestConfig({
    required this.authUrl,
    required this.userUrl,
    required this.scheduleUrl,
    required this.eventUrl,
    required this.ratingUrl,
    required this.chatUrl,
    required this.notificationUrl,
    required this.internalApiKey,
    required this.userDbHost,
    required this.userDbPort,
    required this.userDbName,
    required this.userDbUser,
    required this.userDbPassword,
  });

  factory TestConfig.fromEnv() {
    return TestConfig(
      authUrl: Uri.parse(_env('AUTH_URL', 'http://localhost:8080')),
      userUrl: Uri.parse(_env('USER_URL', 'http://localhost:8081')),
      scheduleUrl: Uri.parse(_env('SCHEDULE_URL', 'http://localhost:8082')),
      eventUrl: Uri.parse(_env('EVENT_URL', 'http://localhost:8083')),
      ratingUrl: Uri.parse(_env('RATING_URL', 'http://localhost:8084')),
      chatUrl: Uri.parse(_env('CHAT_URL', 'http://localhost:8085')),
      notificationUrl:
          Uri.parse(_env('NOTIFICATION_URL', 'http://localhost:8086')),
      internalApiKey: _env('INTERNAL_API_KEY', 'dev_internal_key'),
      userDbHost: _env('USER_DB_HOST', 'localhost'),
      userDbPort: int.parse(_env('USER_DB_PORT', '5432')),
      userDbName: _env('USER_DB_NAME', 'cyberzone_user'),
      userDbUser: _env('USER_DB_USER', 'cyberzone'),
      userDbPassword: _env('USER_DB_PASSWORD', 'password'),
    );
  }
}

class ServiceUrls {
  final Uri authUrl;
  final Uri userUrl;
  final Uri scheduleUrl;
  final Uri eventUrl;
  final Uri ratingUrl;
  final Uri chatUrl;
  final Uri notificationUrl;

  ServiceUrls({
    required this.authUrl,
    required this.userUrl,
    required this.scheduleUrl,
    required this.eventUrl,
    required this.ratingUrl,
    required this.chatUrl,
    required this.notificationUrl,
  });

  factory ServiceUrls.fromConfig(TestConfig config) {
    return ServiceUrls(
      authUrl: config.authUrl,
      userUrl: config.userUrl,
      scheduleUrl: config.scheduleUrl,
      eventUrl: config.eventUrl,
      ratingUrl: config.ratingUrl,
      chatUrl: config.chatUrl,
      notificationUrl: config.notificationUrl,
    );
  }

  factory ServiceUrls.fromGateway(Uri gatewayUrl) {
    return ServiceUrls(
      authUrl: gatewayUrl,
      userUrl: gatewayUrl,
      scheduleUrl: gatewayUrl,
      eventUrl: gatewayUrl,
      ratingUrl: gatewayUrl,
      chatUrl: gatewayUrl,
      notificationUrl: gatewayUrl,
    );
  }
}

class InternalServiceUrls {
  final Uri eventUrl;

  InternalServiceUrls({
    required this.eventUrl,
  });

  factory InternalServiceUrls.fromConfig(TestConfig config) {
    return InternalServiceUrls(eventUrl: config.eventUrl);
  }
}

Future<void> runScenario({
  required http.Client client,
  required TestLogger logger,
  required TestConfig config,
  required ServiceUrls urls,
  InternalServiceUrls? internalUrls,
  bool healthChecks = true,
}) async {
  final internal = internalUrls ?? InternalServiceUrls.fromConfig(config);
  final internalKey = config.internalApiKey;
  final internalHeaders = {'x-internal-key': internalKey};

  if (healthChecks) {
    await _healthChecks(client, urls, logger);
  }

  final adminEmail = 'admin_${DateTime.now().millisecondsSinceEpoch}@test.local';
  final adminPassword = 'Password123!';

  final adminRegister = await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/register'),
    {'email': adminEmail, 'password': adminPassword},
    expectedStatus: 201,
  );

  final adminUserId = adminRegister['userId'] as String;
  await _promoteToSuperAdmin(config, adminUserId);

  final adminLogin = await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/login'),
    {'email': adminEmail, 'password': adminPassword},
    expectedStatus: 200,
  );

  final adminToken = adminLogin['accessToken'] as String;
  await _getJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/me'),
    token: adminToken,
    expectedStatus: 200,
  );

  final userEmail = 'user_${DateTime.now().millisecondsSinceEpoch}@test.local';
  final userPassword = 'Password123!';

  final userRegister = await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/register'),
    {'email': userEmail, 'password': userPassword},
    expectedStatus: 201,
  );

  final userId = userRegister['userId'] as String;

  final userLogin = await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/login'),
    {'email': userEmail, 'password': userPassword},
    expectedStatus: 200,
  );

  var userToken = userLogin['accessToken'] as String;
  var refreshToken = userLogin['refreshToken'] as String;

  final refreshed = await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/refresh'),
    {'refreshToken': refreshToken},
    expectedStatus: 200,
  );

  userToken = refreshed['accessToken'] as String;
  refreshToken = refreshed['refreshToken'] as String;

  await _getJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/me'),
    token: userToken,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.authUrl.resolve('/auth/logout'),
    {'refreshToken': refreshToken},
    expectedStatus: 200,
  );

  final deviceToken = 'test-token-${DateTime.now().millisecondsSinceEpoch}';
  await _postJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/register_token'),
    {'deviceToken': deviceToken, 'platform': 'test'},
    token: userToken,
    expectedStatus: 200,
  );

  await _deleteJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/unregister_token'),
    {'deviceToken': deviceToken},
    token: userToken,
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/dictionaries/roles'),
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/dictionaries/disciplines'),
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me'),
    token: userToken,
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me'),
    {
      'firstName': 'Test',
      'lastName': 'User',
      'institute': 'Cyber Institute',
      'group': 'TG-1',
      'avatarUrl': null,
    },
    token: userToken,
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me/roles'),
    token: userToken,
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me/roles'),
    {'roleIds': <String>[]},
    token: userToken,
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me/disciplines'),
    token: userToken,
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/users/me/disciplines'),
    {'disciplineIds': <String>[]},
    token: userToken,
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/users/$userId'),
    token: adminToken,
    expectedStatus: 200,
  );

  final today = DateTime.now().toUtc();
  final date = _formatDate(today);

  final slot = await _postJson(
    client,
    logger,
    urls.scheduleUrl.resolve('/availability/me'),
    {
      'date': date,
      'timeFrom': '10:00',
      'timeTo': '12:00'
    },
    token: userToken,
    expectedStatus: 201,
  );
  final slotId = slot['id'] as String;

  await _getJson(
    client,
    logger,
    urls.scheduleUrl.resolve('/availability/me'),
    token: userToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.scheduleUrl.resolve('/availability/me/$slotId'),
    {
      'date': date,
      'timeFrom': '11:00',
      'timeTo': '13:00'
    },
    token: userToken,
    expectedStatus: 200,
  );

  final roleId = const Uuid().v4();
  final roleId2 = const Uuid().v4();
  final now = DateTime.now().toUtc();
  final startsAt = now.add(const Duration(minutes: 5));
  final endsAt = now.add(const Duration(hours: 2));

  final event = await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events'),
    {
      'title': 'Integration Test Event',
      'description': 'Integration event',
      'disciplineId': const Uuid().v4(),
      'startsAt': startsAt.toIso8601String(),
      'endsAt': endsAt.toIso8601String(),
      'roles': [
        {'roleId': roleId, 'requiredCount': 1},
        {'roleId': roleId2, 'requiredCount': 1}
      ]
    },
    token: adminToken,
    expectedStatus: 201,
  );

  final eventId = event['id'] as String;

  await _getJson(
    client,
    logger,
    urls.eventUrl.resolve('/events'),
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId'),
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId'),
    {
      'title': 'Integration Test Event Updated',
      'description': 'Integration event updated',
      'disciplineId': const Uuid().v4(),
      'startsAt': startsAt.toIso8601String(),
      'endsAt': endsAt.toIso8601String(),
      'streamUrl': null,
    },
    token: adminToken,
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/roles'),
    {
      'roles': [
        {'roleId': roleId, 'requiredCount': 1},
        {'roleId': roleId2, 'requiredCount': 1}
      ]
    },
    token: adminToken,
    expectedStatus: 200,
  );
  await _putJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/status'),
    {'status': 'recruiting'},
    token: adminToken,
    expectedStatus: 200,
  );

  final chatCreate = await _postJson(
    client,
    logger,
    urls.chatUrl.resolve('/chats'),
    {'eventId': eventId},
    headers: internalHeaders,
    expectedStatus: 201,
  );
  final chatId = chatCreate['chatId'] as String;

  await _putJson(
    client,
    logger,
    urls.chatUrl.resolve('/chats/$chatId/activate'),
    {},
    headers: internalHeaders,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/apply'),
    {
      'roleIds': [roleId, roleId2]
    },
    token: userToken,
    expectedStatus: 201,
  );

  final applications = await _getJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/my_applications'),
    token: userToken,
    expectedStatus: 200,
  );

  final appItems = applications['applications'] as List?;
  _ensure(appItems != null && appItems.length >= 2, 'applications missing');

  final applicationId = (appItems![0] as Map)['id'] as String;
  final applicationId2 = (appItems[1] as Map)['id'] as String;

  await _getJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/applications'),
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.eventUrl.resolve(
        '/events/$eventId/applications/$applicationId'),
    {'status': 'approved'},
    token: adminToken,
    expectedStatus: 200,
  );

  await _deleteJson(
    client,
    logger,
    urls.eventUrl.resolve(
        '/events/$eventId/applications/$applicationId2'),
    {},
    token: userToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/cast'),
    {
      'cast': [
        {'userId': userId, 'roleId': roleId}
      ]
    },
    token: adminToken,
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/cast'),
    token: userToken,
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    internal.eventUrl
        .resolve('/internal/events/$eventId/cast/check?userId=$userId'),
    headers: internalHeaders,
    expectedStatus: 200,
  );

  final chat = await _getJson(
    client,
    logger,
    urls.chatUrl.resolve('/events/$eventId/chat'),
    token: userToken,
    expectedStatus: 200,
  );

  final chatIdFromEvent = chat['chatId'] as String;
  _ensure(chatIdFromEvent == chatId, 'chat id mismatch');

  await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/approve_cast'),
    {'createChat': true},
    token: adminToken,
    expectedStatus: 200,
  );

  final message = await _postJson(
    client,
    logger,
    urls.chatUrl.resolve('/chats/$chatId/messages'),
    {'text': 'Hello from integration test'},
    token: userToken,
    expectedStatus: 201,
  );

  final messageId = message['id'] as String;

  final messages = await _getJson(
    client,
    logger,
    urls.chatUrl.resolve('/chats/$chatId/messages'),
    token: userToken,
    expectedStatus: 200,
  );

  final messageList = messages['messages'] as List?;
  _ensure(messageList != null && messageList.isNotEmpty, 'messages missing');

  await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/call'),
    {'userIds': [userId]},
    token: adminToken,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/call_emergency'),
    {'userIds': [userId]},
    token: adminToken,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId/finish'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.chatUrl.resolve('/chats/$chatId/deactivate'),
    {},
    headers: internalHeaders,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.ratingUrl.resolve('/events/$eventId/ratings'),
    {
      'ratings': [
        {'userId': userId, 'score': 5, 'comment': 'Great job'}
      ]
    },
    token: adminToken,
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    urls.ratingUrl.resolve('/events/$eventId/ratings'),
    token: adminToken,
    expectedStatus: 200,
  );

  final rating = await _getJson(
    client,
    logger,
    urls.ratingUrl.resolve('/ratings/users/$userId'),
    token: userToken,
    expectedStatus: 200,
  );

  await _getJson(
    client,
    logger,
    urls.ratingUrl.resolve('/ratings/users'),
    token: adminToken,
    expectedStatus: 200,
  );
  await _getJson(
    client,
    logger,
    urls.ratingUrl
        .resolve('/ratings/users?roleIds=$roleId&roleIds=$roleId2'),
    token: adminToken,
    expectedStatus: 200,
  );

  _ensure((rating['averageScore'] as num?) == 5, 'rating not applied');

  await _postJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/event_call'),
    {
      'eventId': eventId,
      'userIds': [userId],
      'type': 'normal',
    },
    headers: internalHeaders,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/event_status_changed'),
    {
      'eventId': eventId,
      'newStatus': 'finished',
      'userIds': [userId],
    },
    headers: internalHeaders,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/application_status_changed'),
    {
      'eventId': eventId,
      'userId': userId,
      'newStatus': 'approved',
    },
    headers: internalHeaders,
    expectedStatus: 200,
  );

  await _postJson(
    client,
    logger,
    urls.notificationUrl.resolve('/notifications/chat_message'),
    {
      'chatId': chatId,
      'messageId': messageId,
      'userIds': [userId],
    },
    headers: internalHeaders,
    expectedStatus: 200,
  );

  final adminUsers = await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users?minRating=4'),
    token: adminToken,
    expectedStatus: 200,
  );

  final usersList = adminUsers['users'] as List?;
  _ensure(usersList != null && usersList.isNotEmpty, 'admin users empty');

  await _getJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users/$userId'),
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users/$userId/make_admin'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users/$userId/remove_admin'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users/$userId/ban'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );

  await _putJson(
    client,
    logger,
    urls.userUrl.resolve('/admin/users/$userId/unban'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );

  final availability = await _getJson(
    client,
    logger,
    urls.scheduleUrl.resolve(
        '/availability/search?date=$date&fromTime=09:00&toTime=13:00&minRating=4'),
    token: adminToken,
    expectedStatus: 200,
  );

  final availabilityUsers = availability['users'] as List?;
  _ensure(
    availabilityUsers != null && availabilityUsers.isNotEmpty,
    'availability search empty',
  );

  await _deleteJson(
    client,
    logger,
    urls.scheduleUrl.resolve('/availability/me/$slotId'),
    {},
    token: userToken,
    expectedStatus: 200,
  );

  await _deleteJson(
    client,
    logger,
    urls.eventUrl.resolve('/events/$eventId'),
    {},
    token: adminToken,
    expectedStatus: 200,
  );
}

Future<void> _healthChecks(
  http.Client client,
  ServiceUrls urls,
  TestLogger logger,
) async {
  final checks = [
    urls.authUrl.resolve('/auth/health'),
    urls.userUrl.resolve('/health'),
    urls.eventUrl.resolve('/health'),
    urls.chatUrl.resolve('/health'),
    urls.ratingUrl.resolve('/health'),
    urls.scheduleUrl.resolve('/health'),
    urls.notificationUrl.resolve('/health'),
  ];

  for (final url in checks) {
    await _getJson(client, logger, url, expectedStatus: 200);
  }
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

Future<Map<String, dynamic>> _postJson(
  http.Client client,
  TestLogger logger,
  Uri url,
  Map<String, dynamic> body, {
  String? token,
  Map<String, String>? headers,
  int expectedStatus = 200,
}) async {
  return _requestJson(
    client,
    logger,
    'POST',
    url,
    body: body,
    token: token,
    headers: headers,
    expectedStatus: expectedStatus,
  );
}

Future<Map<String, dynamic>> _putJson(
  http.Client client,
  TestLogger logger,
  Uri url,
  Map<String, dynamic> body, {
  String? token,
  Map<String, String>? headers,
  int expectedStatus = 200,
}) async {
  return _requestJson(
    client,
    logger,
    'PUT',
    url,
    body: body,
    token: token,
    headers: headers,
    expectedStatus: expectedStatus,
  );
}

Future<Map<String, dynamic>> _deleteJson(
  http.Client client,
  TestLogger logger,
  Uri url,
  Map<String, dynamic> body, {
  String? token,
  Map<String, String>? headers,
  int expectedStatus = 200,
}) async {
  return _requestJson(
    client,
    logger,
    'DELETE',
    url,
    body: body,
    token: token,
    headers: headers,
    expectedStatus: expectedStatus,
  );
}

Future<Map<String, dynamic>> _getJson(
  http.Client client,
  TestLogger logger,
  Uri url, {
  String? token,
  Map<String, String>? headers,
  int expectedStatus = 200,
}) async {
  return _requestJson(
    client,
    logger,
    'GET',
    url,
    token: token,
    headers: headers,
    expectedStatus: expectedStatus,
  );
}

Future<Map<String, dynamic>> _requestJson(
  http.Client client,
  TestLogger logger,
  String method,
  Uri url, {
  Map<String, dynamic>? body,
  String? token,
  Map<String, String>? headers,
  int expectedStatus = 200,
}) async {
  final stopwatch = Stopwatch()..start();
  http.Response response;

  final requestHeaders = _headers(token, headers);
  if (method == 'GET') {
    response = await client.get(url, headers: requestHeaders);
  } else if (method == 'POST') {
    response = await client.post(
      url,
      headers: requestHeaders,
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
  } else if (method == 'PUT') {
    response = await client.put(
      url,
      headers: requestHeaders,
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
  } else if (method == 'DELETE') {
    response = await client.delete(
      url,
      headers: requestHeaders,
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
  } else {
    throw StateError('unsupported method $method');
  }

  stopwatch.stop();

  final log = RequestLog(
    method: method,
    url: url,
    expectedStatus: expectedStatus,
    statusCode: response.statusCode,
    requestBody: body == null ? null : jsonEncode(body),
    responseBody: response.body,
    durationMs: stopwatch.elapsedMilliseconds,
  );

  logger.add(log);

  _ensure(
    response.statusCode == expectedStatus,
    '$method $url failed: ${response.statusCode} ${response.body}',
  );

  return _decodeJson(response.body);
}

Map<String, String> _headers(String? token, Map<String, String>? extra) {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  if (extra != null && extra.isNotEmpty) {
    headers.addAll(extra);
  }
  return headers;
}

Map<String, dynamic> _decodeJson(String raw) {
  if (raw.isEmpty) return {};
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  throw StateError('invalid json response');
}

void _ensure(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _env(String key, String fallback) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return fallback;
  return value;
}
