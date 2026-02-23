import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

class ProxyHandler {
  final http.Client _client;
  final Duration _timeout;

  ProxyHandler({
    http.Client? client,
    required Duration timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  Future<Response> forward(
    Request request,
    Uri upstream, {
    String? overridePath,
  }) async {
    final target = _buildTargetUri(request, upstream, overridePath);
    final headers = _filteredHeaders(request.headers);
    _applyForwardedHeaders(headers, request);

    final proxyRequest = http.Request(request.method, target);
    proxyRequest.headers.addAll(headers);

    final bodyBytes = await _readBodyBytes(request.read());
    if (bodyBytes.isNotEmpty) {
      proxyRequest.bodyBytes = bodyBytes;
    }

    try {
      final streamed =
          await _client.send(proxyRequest).timeout(_timeout);
      final responseBytes = await _readBodyBytes(streamed.stream);
      final responseHeaders = _filteredHeaders(streamed.headers);

      return Response(
        streamed.statusCode,
        body: request.method.toUpperCase() == 'HEAD' ? null : responseBytes,
        headers: responseHeaders,
      );
    } on TimeoutException {
      return _errorResponse(
        504,
        'upstream_timeout',
        'Upstream request to $target timed out',
      );
    } catch (err) {
      return _errorResponse(
        502,
        'upstream_error',
        'Upstream request to $target failed: $err',
      );
    }
  }

  void close() {
    _client.close();
  }
}

Uri _buildTargetUri(
  Request request,
  Uri upstream,
  String? overridePath,
) {
  final path = overridePath ?? request.requestedUri.path;
  final joined = _joinPaths(upstream.path, path);
  return upstream.replace(path: joined, query: request.requestedUri.query);
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

Response _errorResponse(int status, String code, String message) {
  return Response(
    status,
    body: '{"error":"$code","message":"$message"}',
    headers: {'Content-Type': 'application/json'},
  );
}

Future<List<int>> _readBodyBytes(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
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
