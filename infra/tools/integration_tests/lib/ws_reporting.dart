library ws_reporting;

import 'dart:convert';
import 'dart:io';

class WsEvent {
  final DateTime at;
  final String type;
  final String message;
  final Map<String, dynamic>? data;

  WsEvent({
    required this.at,
    required this.type,
    required this.message,
    this.data,
  });
}

class WsLogger {
  final List<WsEvent> events = [];

  void add(
    String type,
    String message, {
    Map<String, dynamic>? data,
  }) {
    events.add(WsEvent(
      at: DateTime.now().toUtc(),
      type: type,
      message: message,
      data: data,
    ));
  }
}

Future<String> writeWsReport(
  WsLogger logger, {
  String title = 'WebSocket Scenario Report',
  String? error,
  String? stackTrace,
}) async {
  final dir = Directory(_reportDir());
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final file = File('${dir.path}/ws_scenario_$timestamp.html');

  final buffer = StringBuffer();
  buffer.writeln('<!doctype html>');
  buffer.writeln('<html>');
  buffer.writeln('<head>');
  buffer.writeln('<meta charset="utf-8">');
  buffer.writeln('<title>${_escape(title)}</title>');
  buffer.writeln('<style>');
  buffer.writeln('body {'
      'font-family: "Segoe UI", Arial, sans-serif;'
      'margin: 0;'
      'background: #f4f6fb;'
      'color: #1f2a44;'
      '}');
  buffer.writeln(
      '.container { max-width: 1100px; margin: 28px auto; padding: 0 18px; }');
  buffer.writeln('.card {'
      'background: #fff;'
      'border: 1px solid #e2e6ef;'
      'border-radius: 12px;'
      'padding: 16px 18px;'
      'box-shadow: 0 6px 20px rgba(23, 34, 61, 0.08);'
      'margin-bottom: 18px;'
      '}');
  buffer.writeln('h1 { margin-top: 0; font-size: 24px; }');
  buffer.writeln('table { width: 100%; border-collapse: collapse; }');
  buffer.writeln('th, td {'
      'text-align: left;'
      'padding: 8px 10px;'
      'border-bottom: 1px solid #e6eaf3;'
      'font-size: 13px;'
      '}');
  buffer.writeln('th { background: #f0f3fa; }');
  buffer.writeln('.time { color: #5c6a80; }');
  buffer.writeln('pre {'
      'background: #f6f7fb;'
      'padding: 10px;'
      'border-radius: 8px;'
      'border: 1px solid #e3e7f1;'
      'overflow-x: auto;'
      'white-space: pre-wrap;'
      'font-size: 12px;'
      '}');
  buffer.writeln('.fail { color: #b30000; }');
  buffer.writeln('</style>');
  buffer.writeln('</head>');
  buffer.writeln('<body>');

  buffer.writeln('<div class="container">');
  buffer.writeln('<div class="card">');
  buffer.writeln('<h1>${_escape(title)}</h1>');
  buffer.writeln(
      '<p class="time">Generated: ${DateTime.now().toUtc().toIso8601String()}</p>');
  buffer.writeln('</div>');

  if (error != null) {
    buffer.writeln('<div class="card">');
    buffer.writeln('<h2 class="fail">Failure</h2>');
    buffer.writeln('<pre>${_escape(error)}</pre>');
    if (stackTrace != null) {
      buffer.writeln('<pre>${_escape(stackTrace)}</pre>');
    }
    buffer.writeln('</div>');
  }

  buffer.writeln('<div class="card">');
  buffer.writeln('<h2>Event timeline</h2>');
  buffer.writeln('<table>');
  buffer.writeln('<thead><tr>'
      '<th>Time (UTC)</th>'
      '<th>Type</th>'
      '<th>Message</th>'
      '<th>Data</th>'
      '</tr></thead>');
  buffer.writeln('<tbody>');
  for (final event in logger.events) {
    buffer.writeln('<tr>');
    buffer.writeln('<td class="time">${event.at.toIso8601String()}</td>');
    buffer.writeln('<td>${_escape(event.type)}</td>');
    buffer.writeln('<td>${_escape(event.message)}</td>');
    final data = event.data == null ? '' : _formatBody(event.data!);
    buffer.writeln('<td><pre>${_escape(data)}</pre></td>');
    buffer.writeln('</tr>');
  }
  buffer.writeln('</tbody>');
  buffer.writeln('</table>');
  buffer.writeln('</div>');

  buffer.writeln('</div>');
  buffer.writeln('</body>');
  buffer.writeln('</html>');

  await file.writeAsString(buffer.toString());
  return file.path;
}

String _formatBody(Map<String, dynamic> body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(body);
  } catch (_) {
    return body.toString();
  }
}

String _escape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _reportDir() {
  final envDir = Platform.environment['REPORT_DIR'];
  if (envDir != null && envDir.isNotEmpty) return envDir;
  return '../../../test_logs';
}
