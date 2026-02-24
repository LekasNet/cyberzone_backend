import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

    _mountWebSocketRoutes(router);
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

  void _mountWebSocketRoutes(Router router) {
    router.get('/chats/ws',
        (request) => _proxyWebSocket(request, config.chatUrl));
    router.get('/chats/<chatId>/ws',
        (request) => _proxyWebSocket(request, config.chatUrl));
  }

  Future<Response> _proxyWebSocket(Request request, Uri upstream) async {
    final wsUri = _buildWsUri(request, upstream);
    final headers = _filteredHeaders(request.headers);
    _applyForwardedHeaders(headers, request);

    final handler = webSocketHandler((WebSocketChannel client) async {
      WebSocket upstreamSocket;
      try {
        upstreamSocket = await WebSocket.connect(
          wsUri.toString(),
          headers: headers,
        );
      } catch (_) {
        client.sink.close();
        return;
      }

      final upstreamChannel = IOWebSocketChannel(upstreamSocket);

      client.stream.listen(
        (data) => upstreamChannel.sink.add(data),
        onDone: () => upstreamChannel.sink.close(),
        onError: (_) => upstreamChannel.sink.close(),
      );

      upstreamChannel.stream.listen(
        (data) => client.sink.add(data),
        onDone: () => client.sink.close(),
        onError: (_) => client.sink.close(),
      );
    });

    return handler(request);
  }

  Uri _buildWsUri(Request request, Uri upstream) {
    final scheme = upstream.scheme == 'https' ? 'wss' : 'ws';
    final path = request.requestedUri.path;
    final joined = _joinPaths(upstream.path, path);
    return upstream.replace(
      scheme: scheme,
      path: joined,
      query: request.requestedUri.query,
    );
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

String _joinPaths(String basePath, String path) {
  if (basePath.isEmpty || basePath == '/') {
    return path;
  }
  if (path.isEmpty || path == '/') {
    return basePath;
  }
  if (basePath.endsWith('/') && path.startsWith('/')) {
    return basePath + path.substring(1);
  }
  if (!basePath.endsWith('/') && !path.startsWith('/')) {
    return '$basePath/$path';
  }
  return basePath + path;
}

Map<String, String> _filteredHeaders(Map<String, String> headers) {
  final result = <String, String>{};
  headers.forEach((key, value) {
    final lower = key.toLowerCase();
    if (_hopByHopHeaders.contains(lower) || lower == 'host') return;
    result[key] = value;
  });
  return result;
}

void _applyForwardedHeaders(Map<String, String> headers, Request request) {
  final connInfo = request.context['shelf.io.connection_info'];
  if (connInfo is HttpConnectionInfo) {
    final existing = headers['x-forwarded-for'];
    final address = connInfo.remoteAddress.address;
    headers['x-forwarded-for'] =
        existing == null || existing.isEmpty ? address : '$existing, $address';
  }

  headers['x-forwarded-proto'] = request.requestedUri.scheme;

  final host = request.headers['host'];
  if (host != null && host.isNotEmpty) {
    headers['x-forwarded-host'] = host;
  }
}

const Set<String> _hopByHopHeaders = {
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

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
