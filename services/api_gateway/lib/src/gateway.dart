import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'gateway_config.dart';
import 'openapi_aggregator.dart';
import 'proxy_handler.dart';

class ApiGateway {
  final GatewayConfig config;
  final ProxyHandler proxy;
  final OpenApiAggregator aggregator;
  Map<String, dynamic>? _cachedSpec;

  ApiGateway({
    required this.config,
    required this.proxy,
  })  : aggregator = OpenApiAggregator(
          specPaths: config.specPaths,
          searchDepth: config.specSearchDepth,
        );

  Handler get handler {
    final router = Router();

    router.get('/health', _health);
    router.get('/docs/openapi.yaml', _openApiSpec);
    router.get('/openapi.yaml', _openApiSpec);
    router.mount(
      '/docs/',
      SwaggerUI(
        'openapi.yaml',
        title: 'Cyberzone API',
      ).call,
    );

    _mountProxyRoutes(router);

    return Pipeline()
        .addMiddleware(_blockInternalRoutes())
        .addHandler(router);
  }

  void _mountProxyRoutes(Router router) {
    _proxyAll(router, '/auth', config.authUrl);
    _proxyAll(router, '/users', config.userUrl);
    _proxyAll(router, '/admin', config.userUrl);
    _proxyAll(router, '/dictionaries', config.userUrl);
    _proxyAll(router, '/availability', config.scheduleUrl);

    router.all('/events/<eventId>/ratings',
        (request) => proxy.forward(request, config.ratingUrl));
    router.all('/events/<eventId>/ratings/<path|.*>',
        (request) => proxy.forward(request, config.ratingUrl));

    router.all('/events/<eventId>/chat',
        (request) => proxy.forward(request, config.chatUrl));
    router.all('/events/<eventId>/chat/<path|.*>',
        (request) => proxy.forward(request, config.chatUrl));

    _proxyAll(router, '/events', config.eventUrl);
    _proxyAll(router, '/ratings', config.ratingUrl);
    _proxyAll(router, '/chats', config.chatUrl);
    _proxyAll(router, '/notifications', config.notificationUrl);
  }

  void _proxyAll(Router router, String prefix, Uri upstream) {
    router.all(prefix, (request) => proxy.forward(request, upstream));
    router.all('$prefix/<path|.*>',
        (request) => proxy.forward(request, upstream));
  }

  Future<Response> _health(Request request) async {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _openApiSpec(Request request) async {
    final spec = _cachedSpec ?? await aggregator.build();
    _cachedSpec = spec;
    return Response.ok(
      _toYaml(spec),
      headers: {'Content-Type': 'application/yaml'},
    );
  }
}

Middleware _blockInternalRoutes() {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.requestedUri.path;
      if (path == '/internal' || path.startsWith('/internal/')) {
        return Response(404,
            body: jsonEncode({'error': 'not_found'}),
            headers: {'Content-Type': 'application/json'});
      }
      return innerHandler(request);
    };
  };
}

String _toYaml(Map<String, dynamic> data, {int indent = 0}) {
  final buffer = StringBuffer();
  data.forEach((key, value) {
    buffer.writeln('${' ' * indent}$key:${_renderValue(value, indent)}');
  });
  return buffer.toString();
}

String _renderValue(dynamic value, int indent) {
  if (value == null) return ' null';
  if (value is Map) {
    final nested = value.cast<String, dynamic>();
    final yaml = _toYaml(nested, indent: indent + 2);
    return '\n$yaml';
  }
  if (value is List) {
    if (value.isEmpty) return ' []';
    final buffer = StringBuffer('\n');
    for (final item in value) {
      if (item is Map) {
        buffer.writeln('${' ' * (indent + 2)}-');
        buffer.write(_toYaml(item.cast<String, dynamic>(), indent: indent + 4));
      } else if (item is List) {
        buffer.writeln('${' ' * (indent + 2)}-');
        buffer.write(_renderValue(item, indent + 4));
      } else {
        buffer.writeln('${' ' * (indent + 2)}- ${_formatScalar(item)}');
      }
    }
    return buffer.toString();
  }
  return ' ${_formatScalar(value)}';
}

String _formatScalar(dynamic value) {
  if (value is bool || value is num) return value.toString();
  if (value is String) {
    if (value.isEmpty) return "''";
    final needsQuotes = value.contains(':') ||
        value.contains('#') ||
        value.contains('\n') ||
        value.contains('"') ||
        value.contains('{') ||
        value.contains('[') ||
        value.contains('- ') ||
        value.trim() != value;
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '\\"')}"';
  }
  return '"${value.toString().replaceAll('"', '\\"')}"';
}
