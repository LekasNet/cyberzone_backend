library reporting;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

class ReportConfig {
  final String title;
  final String reportDirEnv;
  final String defaultReportDir;
  final Map<String, String> specPaths;
  final int specSearchDepth;

  const ReportConfig({
    required this.title,
    required this.reportDirEnv,
    required this.defaultReportDir,
    required this.specPaths,
    required this.specSearchDepth,
  });

  factory ReportConfig.defaultConfig() {
    return const ReportConfig(
      title: 'Integration Test Report',
      reportDirEnv: 'REPORT_DIR',
      defaultReportDir: '../../../test_logs',
      specPaths: {
        'auth': 'services/auth_service/specs/openapi.yaml',
        'user': 'services/user_service/specs/openapi.yaml',
        'schedule': 'services/schedule_service/specs/openapi.yaml',
        'event': 'services/event_service/specs/openapi.yaml',
        'rating': 'services/rating_service/specs/openapi.yaml',
        'chat': 'services/chat_service/specs/openapi.yaml',
        'notification': 'services/notification_service/specs/openapi.yaml',
      },
      specSearchDepth: 5,
    );
  }
}

class TestRun {
  final DateTime startedAt;
  DateTime? finishedAt;
  String? error;
  String? stackTrace;
  List<ServiceLog> services = [];

  TestRun({required this.startedAt});

  int get totalRequests =>
      services.fold(0, (sum, service) => sum + service.total);

  int get totalSuccess =>
      services.fold(0, (sum, service) => sum + service.success);

  int get totalFailed => totalRequests - totalSuccess;

  int get durationMs {
    final end = finishedAt ?? DateTime.now().toUtc();
    return end.difference(startedAt).inMilliseconds;
  }
}

class ServiceLog {
  final String name;
  final List<RequestLog> requests = [];

  ServiceLog(this.name);

  int get total => requests.length;
  int get success => requests.where((r) => r.success).length;
  int get failed => total - success;

  int get durationMs =>
      requests.fold(0, (sum, request) => sum + request.durationMs);
}

class RequestLog {
  final String method;
  final Uri url;
  final int expectedStatus;
  final int statusCode;
  final String? requestBody;
  final String? responseBody;
  final int durationMs;

  RequestLog({
    required this.method,
    required this.url,
    required this.expectedStatus,
    required this.statusCode,
    required this.requestBody,
    required this.responseBody,
    required this.durationMs,
  });

  bool get success => statusCode == expectedStatus;
}

typedef ServiceResolver = String Function(Uri url);

class TestLogger {
  final Map<String, ServiceLog> services = {};
  final Map<String, Uri> _baseUrls;
  final ServiceResolver? _resolver;

  TestLogger({
    required Map<String, Uri> baseUrls,
    ServiceResolver? resolver,
  })  : _baseUrls = baseUrls,
        _resolver = resolver;

  void add(RequestLog log) {
    final serviceName = _resolver?.call(log.url) ?? _resolveService(log.url);
    final service =
        services.putIfAbsent(serviceName, () => ServiceLog(serviceName));
    service.requests.add(log);
  }

  String _resolveService(Uri url) {
    for (final entry in _baseUrls.entries) {
      if (_sameOrigin(entry.value, url)) {
        return entry.key;
      }
    }
    return 'unknown';
  }

  bool _sameOrigin(Uri a, Uri b) {
    return a.scheme == b.scheme &&
        a.host == b.host &&
        (a.hasPort ? a.port : _defaultPort(a.scheme)) ==
            (b.hasPort ? b.port : _defaultPort(b.scheme));
  }

  int _defaultPort(String scheme) {
    return scheme == 'https' ? 443 : 80;
  }
}

Future<String> writeReport(TestRun run, {ReportConfig? config}) async {
  final resolved = config ?? ReportConfig.defaultConfig();
  final dir = Directory(_reportDir(resolved));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final coverage = await _calculateCoverage(run, resolved);

  final timestamp = run.startedAt
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final file = File('${dir.path}/integration_$timestamp.html');

  final buffer = StringBuffer();
  buffer.writeln('<!doctype html>');
  buffer.writeln('<html>');
  buffer.writeln('<head>');
  buffer.writeln('<meta charset="utf-8">');
  buffer.writeln('<title>${_escape(resolved.title)}</title>');
  buffer.writeln('<style>');
  buffer.writeln('body {'
      'font-family: "Segoe UI", Arial, sans-serif;'
      'margin: 0;'
      'background: #f3f5f9;'
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
  buffer.writeln('details {'
      'margin-bottom: 12px;'
      'background: #fff;'
      'border: 1px solid #e2e6ef;'
      'border-radius: 10px;'
      'padding: 10px 12px;'
      '}');
  buffer.writeln('details > summary {'
      'cursor: pointer;'
      'font-weight: 600;'
      'list-style: none;'
      '}');
  buffer.writeln('summary::-webkit-details-marker { display: none; }');
  buffer.writeln('.meta { color: #5c6a80; font-size: 13px; }');
  buffer.writeln('.time { font-size: 12px; opacity: 0.7; }');
  buffer.writeln('.ok { color: #0a7f2e; }');
  buffer.writeln('.fail { color: #b30000; }');
  buffer.writeln('pre {'
      'background: #f6f7fb;'
      'padding: 12px;'
      'border-radius: 8px;'
      'border: 1px solid #e3e7f1;'
      'overflow-x: auto;'
      'white-space: pre-wrap;'
      'font-size: 12px;'
      '}');
  buffer.writeln('.badge {'
      'display: inline-block;'
      'padding: 2px 8px;'
      'border-radius: 999px;'
      'font-size: 12px;'
      'background: #eef2ff;'
      'color: #3b4a70;'
      '}');
  buffer.writeln('</style>');
  buffer.writeln('</head>');
  buffer.writeln('<body>');

  buffer.writeln('<div class="container">');
  buffer.writeln('<div class="card">');
  buffer.writeln('<h1>${_escape(resolved.title)}</h1>');
  buffer.writeln(
      '<p class="meta">Started: <span class="time">${run.startedAt.toIso8601String()}</span></p>');
  buffer.writeln(
      '<p class="meta">Finished: <span class="time">${run.finishedAt?.toIso8601String()}</span></p>');
  buffer.writeln('<p class="meta">Duration: ${run.durationMs} ms</p>');

  buffer.writeln('<p class="meta">Total requests: ${run.totalRequests}</p>');
  buffer.writeln('<p class="meta">Success: ${run.totalSuccess}</p>');
  buffer.writeln('<p class="meta">Failed: ${run.totalFailed}</p>');
  buffer.writeln('</div>');

  if (run.error != null) {
    buffer.writeln('<h2 class="fail">Run failed</h2>');
    buffer.writeln('<pre>${_escape(run.error!)}</pre>');
    if (run.stackTrace != null) {
      buffer.writeln('<pre>${_escape(run.stackTrace!)}</pre>');
    }
  }

  for (final service in run.services) {
    final serviceStatus = service.failed == 0 ? 'ok' : 'fail';
    buffer.writeln('<details>');
    buffer.writeln(
        '<summary class="$serviceStatus">${_escape(service.name)} '
        '<span class="badge">${service.success}/${service.total} success</span> '
        '<span class="time">${service.durationMs} ms</span></summary>');

    for (final request in service.requests) {
      final statusClass = request.success ? 'ok' : 'fail';
      buffer.writeln('<details>');
      buffer.writeln(
          '<summary class="$statusClass">${_escape(request.method)} ${_escape(request.url.toString())} -> ${request.statusCode} (${request.durationMs} ms)</summary>');
      buffer.writeln('<p class="meta">Expected: ${request.expectedStatus}</p>');
      buffer.writeln('<p class="meta">Status: ${request.statusCode}</p>');
      if (request.requestBody != null) {
        final formattedRequest = _formatBody(request.requestBody);
        buffer.writeln('<h4>Request</h4>');
        buffer.writeln('<pre>${_escape(formattedRequest)}</pre>');
      }
      buffer.writeln('<h4>Response</h4>');
      final formattedResponse = _formatBody(request.responseBody);
      buffer.writeln('<pre>${_escape(formattedResponse)}</pre>');
      buffer.writeln('</details>');
    }

    buffer.writeln('</details>');
  }

  buffer.writeln('<div class="card">');
  buffer.writeln('<h2>Coverage</h2>');
  if (coverage.total == 0) {
    buffer.writeln(
        '<p class="meta">No OpenAPI specs found to compute coverage.</p>');
  } else {
    buffer.writeln(
        '<p class="meta">Covered endpoints: ${coverage.covered} / ${coverage.total} '
        '(${_formatPercent(coverage.covered, coverage.total)})</p>');
    buffer.writeln(
        '<p class="meta">Successful endpoints: ${coverage.successful} / ${coverage.total} '
        '(${_formatPercent(coverage.successful, coverage.total)})</p>');
  }
  buffer.writeln('</div>');

  buffer.writeln('</div>');
  buffer.writeln('</body>');
  buffer.writeln('</html>');

  await file.writeAsString(buffer.toString());
  return file.path;
}

Future<CoverageSummary> calculateCoverage(
  TestRun run, {
  ReportConfig? config,
}) async {
  final resolved = config ?? ReportConfig.defaultConfig();
  return _calculateCoverage(run, resolved);
}

String _formatBody(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return raw;
  }
}

String _escape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _reportDir(ReportConfig config) {
  final envDir = Platform.environment[config.reportDirEnv];
  if (envDir != null && envDir.isNotEmpty) return envDir;
  return config.defaultReportDir;
}

Future<CoverageSummary> _calculateCoverage(
  TestRun run,
  ReportConfig config,
) async {
  final specs = await _loadEndpointSpecs(config);
  if (specs.total == 0) {
    return CoverageSummary(total: 0, covered: 0, successful: 0);
  }

  final covered = <String>{};
  final successful = <String>{};

  for (final service in run.services) {
    final serviceSpecs = specs.byService[service.name];
    if (serviceSpecs == null || serviceSpecs.isEmpty) continue;

    for (final request in service.requests) {
      final normalized = _normalizePath(request.url.path);
      final match = _matchEndpoint(
        serviceSpecs,
        request.method,
        normalized,
      );
      if (match == null) continue;

      final key = '${service.name}|${match.method}|${match.template}';
      covered.add(key);
      if (request.success) {
        successful.add(key);
      }
    }
  }

  return CoverageSummary(
    total: specs.total,
    covered: covered.length,
    successful: successful.length,
  );
}

String _normalizePath(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

EndpointSpec? _matchEndpoint(
  List<EndpointSpec> specs,
  String method,
  String path,
) {
  final needle = method.toLowerCase();
  for (final spec in specs) {
    if (spec.method != needle) continue;
    if (spec.regex.hasMatch(path)) return spec;
  }
  return null;
}

Future<EndpointSpecs> _loadEndpointSpecs(ReportConfig config) async {
  final byService = <String, List<EndpointSpec>>{};

  for (final entry in config.specPaths.entries) {
    final file = _findSpecFile(
      entry.value,
      maxDepth: config.specSearchDepth,
    );
    if (file == null) continue;

    final specs = _parseSpec(file);
    if (specs.isNotEmpty) {
      byService[entry.key] = specs;
    }
  }

  final total = byService.values.fold(0, (sum, list) => sum + list.length);
  return EndpointSpecs(total: total, byService: byService);
}

File? _findSpecFile(String relative, {required int maxDepth}) {
  final relativePath = relative.replaceAll('/', Platform.pathSeparator);
  final candidates = <String>[];
  var dir = Directory.current;
  for (var i = 0; i < maxDepth; i += 1) {
    candidates.add(dir.path);
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  for (final base in candidates) {
    final file = File('$base${Platform.pathSeparator}$relativePath');
    if (file.existsSync()) return file;
  }

  return null;
}

List<EndpointSpec> _parseSpec(File file) {
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return const [];
    final paths = doc['paths'];
    if (paths is! YamlMap) return const [];

    final specs = <EndpointSpec>[];
    for (final entry in paths.entries) {
      final path = entry.key.toString();
      final value = entry.value;
      if (value is! YamlMap) continue;

      for (final opEntry in value.entries) {
        final method = opEntry.key.toString().toLowerCase();
        if (!_isHttpMethod(method)) continue;
        specs.add(EndpointSpec(method: method, template: path));
      }
    }
    return specs;
  } catch (_) {
    return const [];
  }
}

bool _isHttpMethod(String method) {
  switch (method) {
    case 'get':
    case 'post':
    case 'put':
    case 'delete':
    case 'patch':
      return true;
    default:
      return false;
  }
}

String _formatPercent(int part, int total) {
  if (total == 0) return '0%';
  final value = (part / total) * 100;
  return '${value.toStringAsFixed(1)}%';
}

class EndpointSpec {
  final String method;
  final String template;
  final RegExp regex;

  EndpointSpec({
    required this.method,
    required this.template,
  }) : regex = _buildRegex(template);

  static RegExp _buildRegex(String template) {
    final escaped = RegExp.escape(template);
    final pattern = escaped.replaceAllMapped(
      RegExp(r'\\\{[^\\\}]+\\\}'),
      (_) => '[^/]+',
    );
    return RegExp('^$pattern\$');
  }
}

class EndpointSpecs {
  final int total;
  final Map<String, List<EndpointSpec>> byService;

  EndpointSpecs({
    required this.total,
    required this.byService,
  });
}

class CoverageSummary {
  final int total;
  final int covered;
  final int successful;

  CoverageSummary({
    required this.total,
    required this.covered,
    required this.successful,
  });
}
