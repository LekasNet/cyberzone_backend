import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:event_service/src/application_repository.dart';
import 'package:event_service/src/cast_repository.dart';
import 'package:event_service/src/chat_service_client.dart';
import 'package:event_service/src/db.dart';
import 'package:event_service/src/event_controller.dart';
import 'package:event_service/src/event_repository.dart';
import 'package:event_service/src/jwt_config.dart';
import 'package:event_service/src/jwt_service.dart';
import 'package:event_service/src/notification_service_client.dart';
import 'package:event_service/src/user_service_client.dart';

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

    final eventsRepo = EventRepository(db.connection);
    final appsRepo = ApplicationRepository(db.connection);
    final castRepo = CastRepository(db.connection);
    final userService = UserServiceClient(config: UserServiceConfig.fromEnv());
    final chatService = ChatServiceClient(config: ChatServiceConfig.fromEnv());
    final notificationService = NotificationServiceClient(
      config: NotificationServiceConfig.fromEnv(),
    );

    final controller = EventController(
      events: eventsRepo,
      applications: appsRepo,
      cast: castRepo,
      users: userService,
      chat: chatService,
      notifications: notificationService,
      jwt: jwtService,
      internalKey: internalKey,
    );

    final router = controller.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone Event API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8083');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Event service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
