import 'dart:io';

class GatewayConfig {
  final Uri authUrl;
  final Uri userUrl;
  final Uri scheduleUrl;
  final Uri eventUrl;
  final Uri ratingUrl;
  final Uri chatUrl;
  final Uri notificationUrl;
  final int port;
  final Duration requestTimeout;
  final int specSearchDepth;
  final List<String> specPaths;

  GatewayConfig({
    required this.authUrl,
    required this.userUrl,
    required this.scheduleUrl,
    required this.eventUrl,
    required this.ratingUrl,
    required this.chatUrl,
    required this.notificationUrl,
    required this.port,
    required this.requestTimeout,
    required this.specSearchDepth,
    required this.specPaths,
  });

  factory GatewayConfig.fromEnv() {
    return GatewayConfig(
      authUrl: _parseUrl('AUTH_SERVICE_URL', 'http://localhost:8080'),
      userUrl: _parseUrl('USER_SERVICE_URL', 'http://localhost:8081'),
      scheduleUrl: _parseUrl('SCHEDULE_SERVICE_URL', 'http://localhost:8082'),
      eventUrl: _parseUrl('EVENT_SERVICE_URL', 'http://localhost:8083'),
      ratingUrl: _parseUrl('RATING_SERVICE_URL', 'http://localhost:8084'),
      chatUrl: _parseUrl('CHAT_SERVICE_URL', 'http://localhost:8085'),
      notificationUrl:
          _parseUrl('NOTIFICATION_SERVICE_URL', 'http://localhost:8086'),
      port: int.parse(Platform.environment['PORT'] ?? '8087'),
      requestTimeout: Duration(
        milliseconds:
            int.parse(Platform.environment['PROXY_TIMEOUT_MS'] ?? '10000'),
      ),
      specSearchDepth:
          int.parse(Platform.environment['SPEC_SEARCH_DEPTH'] ?? '5'),
      specPaths: _specPaths(),
    );
  }
}

Uri _parseUrl(String key, String fallback) {
  final raw = Platform.environment[key];
  return Uri.parse((raw == null || raw.isEmpty) ? fallback : raw);
}

List<String> _specPaths() {
  final raw = Platform.environment['SPEC_PATHS'];
  if (raw == null || raw.trim().isEmpty) {
    return const [
      'services/auth_service/specs/openapi.yaml',
      'services/user_service/specs/openapi.yaml',
      'services/schedule_service/specs/openapi.yaml',
      'services/event_service/specs/openapi.yaml',
      'services/rating_service/specs/openapi.yaml',
      'services/chat_service/specs/openapi.yaml',
      'services/notification_service/specs/openapi.yaml',
    ];
  }

  return raw
      .split(';')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}
