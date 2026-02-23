import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class NotificationServiceConfig {
  final Uri baseUri;
  final String internalApiKey;

  NotificationServiceConfig({
    required this.baseUri,
    required this.internalApiKey,
  });

  factory NotificationServiceConfig.fromEnv() {
    final base =
        Platform.environment['NOTIFICATION_SERVICE_URL'] ?? 'http://localhost:8086';
    final key = Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';
    return NotificationServiceConfig(
      baseUri: Uri.parse(base),
      internalApiKey: key,
    );
  }
}

class NotificationDispatchSummary {
  final int requested;
  final int sent;
  final int failed;
  final bool skipped;

  NotificationDispatchSummary({
    required this.requested,
    required this.sent,
    required this.failed,
    required this.skipped,
  });

  factory NotificationDispatchSummary.fromJson(Map<String, dynamic> json) {
    return NotificationDispatchSummary(
      requested: (json['requested'] as num?)?.toInt() ?? 0,
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      skipped: json['skipped'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'requested': requested,
        'sent': sent,
        'failed': failed,
        'skipped': skipped,
      };
}

class NotificationServiceClient {
  final http.Client _client;
  final NotificationServiceConfig _config;

  NotificationServiceClient({
    http.Client? client,
    required NotificationServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<NotificationDispatchSummary> sendEventCall({
    required String eventId,
    required List<String> userIds,
    required List<String> roles,
    required String type,
    String? title,
    String? message,
  }) async {
    final uri = _config.baseUri.resolve('/notifications/event_call');
    final payload = <String, dynamic>{
      'eventId': eventId,
      'userIds': userIds,
      'roles': roles,
      'type': type,
      if (title != null) 'title': title,
      if (message != null) 'message': message,
    };

    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = _decodeJson(response.body);
      return NotificationDispatchSummary.fromJson(decoded);
    }

    throw NotificationServiceException(
      'event_call_failed',
      response.statusCode,
      response.body,
    );
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'x-internal-key': _config.internalApiKey,
      };

  Map<String, dynamic> _decodeJson(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('invalid_json');
  }
}

class NotificationServiceException implements Exception {
  final String code;
  final int statusCode;
  final String body;

  NotificationServiceException(this.code, this.statusCode, this.body);

  @override
  String toString() => 'NotificationServiceException($code, $statusCode)';
}
