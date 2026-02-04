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

class UserFlags {
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool isBanned;

  UserFlags({
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.isBanned,
  });
}

class UserServiceClient {
  final http.Client _client;
  final UserServiceConfig _config;

  UserServiceClient({
    http.Client? client,
    required UserServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<UserFlags> createUser({
    required String userId,
    required String email,
  }) async {
    final uri = _config.baseUri.resolve('/internal/users');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'id': userId, 'email': email}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = _decodeJson(response.body);
      return _parseFlags(body);
    }

    throw UserServiceException(
      'create_user_failed',
      response.statusCode,
      response.body,
    );
  }

  Future<UserFlags> getFlags(String userId) async {
    final uri = _config.baseUri.resolve('/internal/users/$userId/flags');
    final response = await _client.get(
      uri,
      headers: _headers(),
    );

    if (response.statusCode == 200) {
      final body = _decodeJson(response.body);
      return _parseFlags(body);
    }

    throw UserServiceException(
      'get_flags_failed',
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

  UserFlags _parseFlags(Map<String, dynamic> body) {
    return UserFlags(
      isAdmin: body['isAdmin'] as bool? ?? false,
      isSuperAdmin: body['isSuperAdmin'] as bool? ?? false,
      isBanned: body['isBanned'] as bool? ?? false,
    );
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
