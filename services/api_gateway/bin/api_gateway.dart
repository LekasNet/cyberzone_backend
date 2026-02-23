import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'package:api_gateway/api_gateway.dart';

Future<void> main(List<String> args) async {
  try {
    final config = GatewayConfig.fromEnv();
    final proxy = ProxyHandler(timeout: config.requestTimeout);
    final gateway = ApiGateway(config: config, proxy: proxy);

    final handler =
        Pipeline().addMiddleware(logRequests()).addHandler(gateway.handler);

    final server =
        await io.serve(handler, InternetAddress.anyIPv4, config.port);

    print('API gateway listening on http://localhost:${server.port}');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
