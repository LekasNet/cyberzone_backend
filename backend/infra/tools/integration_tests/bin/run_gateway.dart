import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:integration_tests/reporting.dart';
import 'package:integration_tests/test_scenario.dart';

Future<void> main() async {
  final config = TestConfig.fromEnv();
  final gatewayUrl =
      Uri.parse(_env('GATEWAY_URL', 'http://localhost:8087'));
  final urls = ServiceUrls.fromGateway(gatewayUrl);
  final internalUrls = InternalServiceUrls.fromConfig(config);
  final client = http.Client();

  final logger = TestLogger(
    baseUrls: {'gateway': gatewayUrl},
    resolver: _resolveServiceByPath,
  );

  Object? error;
  StackTrace? stackTrace;

  final run = TestRun(startedAt: DateTime.now().toUtc());

  try {
    await runScenario(
      client: client,
      logger: logger,
      config: config,
      urls: urls,
      internalUrls: internalUrls,
      healthChecks: false,
    );

    print('Gateway integration tests passed.');
  } catch (err, st) {
    error = err;
    stackTrace = st;
    stderr.writeln('Gateway integration tests failed: $err');
  } finally {
    run.finishedAt = DateTime.now().toUtc();
    run.error = error?.toString();
    run.stackTrace = stackTrace?.toString();
    run.services = logger.services.values.toList();

    final reportPath = await writeReport(run);
    print('Saved report: $reportPath');

    client.close();

    if (error != null) {
      exitCode = 1;
    }
  }
}

String _resolveServiceByPath(Uri url) {
  final path = url.path;

  if (path == '/health') return 'gateway';
  if (path.startsWith('/internal/events')) return 'event';
  if (path.startsWith('/auth')) return 'auth';
  if (path.startsWith('/users') ||
      path.startsWith('/admin') ||
      path.startsWith('/dictionaries')) {
    return 'user';
  }
  if (path.startsWith('/availability')) return 'schedule';
  if (RegExp(r'^/events/[^/]+/chat').hasMatch(path)) return 'chat';
  if (path.startsWith('/events')) return 'event';
  if (path.startsWith('/ratings')) return 'rating';
  if (path.startsWith('/chats')) return 'chat';
  if (path.startsWith('/notifications')) return 'notification';

  return 'gateway';
}

String _env(String key, String fallback) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return fallback;
  return value;
}
