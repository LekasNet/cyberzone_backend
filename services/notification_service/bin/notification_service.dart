import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:notification_service/src/db.dart';
import 'package:notification_service/src/fcm_client.dart';
import 'package:notification_service/src/jwt_config.dart';
import 'package:notification_service/src/jwt_service.dart';
import 'package:notification_service/src/notification_controller.dart';
import 'package:notification_service/src/notification_repository.dart';

Future<void> main(List<String> args) async {
  try {
    final dbConfig = DbConfig.fromEnv();
    print('Resolved DB -> ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}');

    final db = Db(dbConfig);
    await db.connect();
    print('Connected to ${dbConfig.database}');

    final jwtConfig = JwtConfig.fromEnv();
    final jwtService = JwtService(jwtConfig);
    final internalKey =
        Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';

    final fcmConfig = FcmConfig.fromEnv();
    final fcmClient = FcmClient(fcmConfig);

    if (!fcmClient.isReady && fcmClient.enabled) {
      print('WARNING: FCM config missing, notifications will fail.');
    }

    final repo = NotificationRepository(db.connection);
    final controller = NotificationController(
      tokens: repo,
      jwt: jwtService,
      internalKey: internalKey,
      fcm: fcmClient,
    );

    final router = controller.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone Notification API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8086');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Notification service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
