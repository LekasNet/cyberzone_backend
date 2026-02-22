import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ChatServiceConfig {
  final Uri baseUri;
  final String internalApiKey;

  ChatServiceConfig({
    required this.baseUri,
    required this.internalApiKey,
  });

  factory ChatServiceConfig.fromEnv() {
    final base = Platform.environment['CHAT_SERVICE_URL'] ?? 'http://localhost:8085';
    final key = Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';
    return ChatServiceConfig(
      baseUri: Uri.parse(base),
      internalApiKey: key,
    );
  }
}

class ChatServiceClient {
  final http.Client _client;
  final ChatServiceConfig _config;

  ChatServiceClient({
    http.Client? client,
    required ChatServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<String?> createChat(String eventId) async {
    final uri = _config.baseUri.resolve('/chats');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'eventId': eventId}),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final chatId = decoded['chatId'] ?? decoded['id'];
          if (chatId is String && chatId.isNotEmpty) return chatId;
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    throw ChatServiceException(
      'create_chat_failed',
      response.statusCode,
      response.body,
    );
  }

  Future<void> activateChat(String chatId) async {
    final uri = _config.baseUri.resolve('/chats/$chatId/activate');
    final response = await _client.put(uri, headers: _headers());

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw ChatServiceException(
      'activate_chat_failed',
      response.statusCode,
      response.body,
    );
  }

  Future<void> deactivateChat(String chatId) async {
    final uri = _config.baseUri.resolve('/chats/$chatId/deactivate');
    final response = await _client.put(uri, headers: _headers());

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw ChatServiceException(
      'deactivate_chat_failed',
      response.statusCode,
      response.body,
    );
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'x-internal-key': _config.internalApiKey,
      };
}

class ChatServiceException implements Exception {
  final String code;
  final int statusCode;
  final String body;

  ChatServiceException(this.code, this.statusCode, this.body);

  @override
  String toString() => 'ChatServiceException($code, $statusCode)';
}
