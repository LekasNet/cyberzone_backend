import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class UserServiceConfig {
  final Uri baseUri;
  final String internalApiKey;

  UserServiceConfig({
    required this.baseUri,
    required this.internalApiKey,
  });

  factory UserServiceConfig.fromEnv() {
    final base = Platform.environment['USER_SERVICE_URL'] ?? 'http://localhost:8081';
    final key = Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';
    return UserServiceConfig(
      baseUri: Uri.parse(base),
      internalApiKey: key,
    );
  }
}

class UserServiceClient {
  final http.Client _client;
  final UserServiceConfig _config;

  UserServiceClient({
    http.Client? client,
    required UserServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<List<Map<String, dynamic>>> fetchUsersBulk({
    required List<String> userIds,
  }) async {
    final uri = _config.baseUri.resolve('/internal/users/bulk');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'userIds': userIds}),
    );

    if (response.statusCode == 200) {
      final body = _decodeJson(response.body);
      final users = body['users'];
      if (users is List) {
        return users
            .whereType<Map<String, dynamic>>()
            .map((u) => Map<String, dynamic>.from(u))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }

    throw UserServiceException(
      'bulk_users_failed',
      response.statusCode,
      response.body,
    );
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'x-internal-key': _config.internalApiKey,
      };

  Map<String, dynamic> _decodeJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('invalid_json');
  }
}

class UserServiceException implements Exception {
  final String code;
  final int statusCode;
  final String body;

  UserServiceException(this.code, this.statusCode, this.body);

  @override
  String toString() => 'UserServiceException($code, $statusCode)';
}
