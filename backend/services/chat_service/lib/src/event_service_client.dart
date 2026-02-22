import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class EventServiceConfig {
  final Uri baseUri;
  final String internalApiKey;

  EventServiceConfig({
    required this.baseUri,
    required this.internalApiKey,
  });

  factory EventServiceConfig.fromEnv() {
    final base = Platform.environment['EVENT_SERVICE_URL'] ?? 'http://localhost:8083';
    final key = Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';
    return EventServiceConfig(
      baseUri: Uri.parse(base),
      internalApiKey: key,
    );
  }
}

class EventServiceClient {
  final http.Client _client;
  final EventServiceConfig _config;

  EventServiceClient({
    http.Client? client,
    required EventServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<bool> isUserInCast({
    required String eventId,
    required String userId,
  }) async {
    final uri = _config.baseUri
        .resolve('/internal/events/$eventId/cast/check?userId=$userId');

    final response = await _client.get(uri, headers: _headers());

    if (response.statusCode == 200) {
      final body = _decodeJson(response.body);
      return body['inCast'] == true;
    }

    if (response.statusCode == 404) {
      return false;
    }

    throw EventServiceException(
      'cast_check_failed',
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

class EventServiceException implements Exception {
  final String code;
  final int statusCode;
  final String body;

  EventServiceException(this.code, this.statusCode, this.body);

  @override
  String toString() => 'EventServiceException($code, $statusCode)';
}
