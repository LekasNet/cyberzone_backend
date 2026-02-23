import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:integration_tests/reporting.dart';
import 'package:integration_tests/test_scenario.dart';

Future<void> main() async {
  final config = TestConfig.fromEnv();
  final urls = ServiceUrls.fromConfig(config);
  final client = http.Client();
  final logger = TestLogger(baseUrls: {
    'auth': config.authUrl,
    'user': config.userUrl,
    'schedule': config.scheduleUrl,
    'event': config.eventUrl,
    'rating': config.ratingUrl,
    'chat': config.chatUrl,
    'notification': config.notificationUrl,
  });

  Object? error;
  StackTrace? stackTrace;

  final run = TestRun(startedAt: DateTime.now().toUtc());

  try {
    await runScenario(
      client: client,
      logger: logger,
      config: config,
      urls: urls,
      healthChecks: true,
    );

    run.services = logger.services.values.toList();
    final coverage = await calculateCoverage(run);
    if (coverage.total > 0 && coverage.covered != coverage.total) {
      throw StateError(
        'Coverage incomplete: ${coverage.covered}/${coverage.total} '
        '(successful ${coverage.successful}/${coverage.total})',
      );
    }

    print('Integration tests passed.');
  } catch (err, st) {
    error = err;
    stackTrace = st;
    stderr.writeln('Integration tests failed: $err');
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
