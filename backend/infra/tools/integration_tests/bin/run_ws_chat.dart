import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:integration_tests/test_scenario.dart';
import 'package:integration_tests/ws_chat_scenario.dart';
import 'package:integration_tests/ws_reporting.dart';

Future<void> main() async {
  final config = TestConfig.fromEnv();
  final client = http.Client();
  final logger = WsLogger();

  Object? error;
  StackTrace? stackTrace;

  try {
    await runWebSocketScenario(
      client: client,
      config: config,
      logger: logger,
    );

    print('WebSocket chat scenario passed.');
  } catch (err, st) {
    error = err;
    stackTrace = st;
    stderr.writeln('WebSocket chat scenario failed: $err');
  } finally {
    final reportPath = await writeWsReport(
      logger,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    print('Saved report: $reportPath');

    client.close();

    if (error != null) {
      if (stackTrace != null) {
        stderr.writeln(stackTrace);
      }
      exitCode = 1;
    }
  }
}
