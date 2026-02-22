import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class FcmConfig {
  final bool enabled;
  final bool validateOnly;
  final String projectId;
  final ServiceAccountCredentials? credentials;

  FcmConfig({
    required this.enabled,
    required this.validateOnly,
    required this.projectId,
    required this.credentials,
  });

  factory FcmConfig.fromEnv() {
    final enabled = _parseBool(Platform.environment['NOTIFICATIONS_ENABLED'], false);
    final validateOnly = _parseBool(Platform.environment['FCM_VALIDATE_ONLY'], false);
    final projectId = Platform.environment['FCM_PROJECT_ID'] ?? '';
    final rawServiceAccount =
        Platform.environment['FCM_SERVICE_ACCOUNT'] ??
            Platform.environment['FCM_SERVICE_ACCOUNT_JSON'];

    ServiceAccountCredentials? credentials;
    if (rawServiceAccount != null && rawServiceAccount.trim().isNotEmpty) {
      credentials = _loadCredentials(rawServiceAccount.trim());
    }

    return FcmConfig(
      enabled: enabled,
      validateOnly: validateOnly,
      projectId: projectId,
      credentials: credentials,
    );
  }

  bool get isReady => !enabled || (projectId.isNotEmpty && credentials != null);

  static bool _parseBool(String? value, bool fallback) {
    if (value == null) return fallback;
    switch (value.toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'y':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'n':
        return false;
      default:
        return fallback;
    }
  }

  static ServiceAccountCredentials? _loadCredentials(String raw) {
    try {
      if (raw.startsWith('{')) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return ServiceAccountCredentials.fromJson(decoded);
        }
      }

      final file = File(raw);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          return ServiceAccountCredentials.fromJson(decoded);
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class FcmClient {
  final FcmConfig config;
  AuthClient? _authClient;

  FcmClient(this.config);

  bool get enabled => config.enabled;
  bool get validateOnly => config.validateOnly;
  bool get isReady => config.isReady;

  Future<FcmBatchResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (tokens.isEmpty) {
      return FcmBatchResult(
        requested: 0,
        sent: 0,
        failed: 0,
        skipped: false,
        validateOnly: config.validateOnly,
      );
    }

    if (!config.enabled) {
      return FcmBatchResult(
        requested: tokens.length,
        sent: 0,
        failed: 0,
        skipped: true,
        validateOnly: config.validateOnly,
      );
    }

    if (!config.isReady) {
      throw FcmException('fcm_not_configured');
    }

    final client = await _getAuthClient();
    final errors = <FcmSendError>[];
    var sent = 0;

    for (final token in tokens) {
      final error = await _sendSingle(
        client: client,
        token: token,
        title: title,
        body: body,
        data: data ?? const {},
      );

      if (error == null) {
        sent += 1;
      } else {
        errors.add(error);
      }
    }

    return FcmBatchResult(
      requested: tokens.length,
      sent: sent,
      failed: errors.length,
      skipped: false,
      validateOnly: config.validateOnly,
      errors: errors,
    );
  }

  Future<AuthClient> _getAuthClient() async {
    final existing = _authClient;
    if (existing != null) return existing;

    final credentials = config.credentials;
    if (credentials == null) {
      throw FcmException('missing_credentials');
    }

    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await clientViaServiceAccount(credentials, scopes);
    _authClient = client;
    return client;
  }

  Future<FcmSendError?> _sendSingle({
    required AuthClient client,
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    final uri = Uri.parse(
      'https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send',
    );

    final payload = <String, dynamic>{
      'message': {
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        if (data.isNotEmpty) 'data': data,
      },
      if (config.validateOnly) 'validate_only': true,
    };

    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }

    return FcmSendError(
      token: token,
      statusCode: response.statusCode,
      body: response.body,
    );
  }
}

class FcmBatchResult {
  final int requested;
  final int sent;
  final int failed;
  final bool skipped;
  final bool validateOnly;
  final List<FcmSendError> errors;

  FcmBatchResult({
    required this.requested,
    required this.sent,
    required this.failed,
    required this.skipped,
    required this.validateOnly,
    List<FcmSendError>? errors,
  }) : errors = errors ?? const [];

  Map<String, dynamic> toJson({int maxErrors = 10}) {
    final limited = errors.take(maxErrors).map((e) => e.toJson()).toList();
    return {
      'requested': requested,
      'sent': sent,
      'failed': failed,
      'skipped': skipped,
      'validateOnly': validateOnly,
      if (limited.isNotEmpty) 'errors': limited,
      if (errors.length > maxErrors) 'errors_truncated': true,
    };
  }
}

class FcmSendError {
  final String token;
  final int statusCode;
  final String body;

  FcmSendError({
    required this.token,
    required this.statusCode,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'statusCode': statusCode,
        'body': body,
      };
}

class FcmException implements Exception {
  final String code;
  FcmException(this.code);

  @override
  String toString() => 'FcmException($code)';
}
