import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:chat_service/src/chat_controller.dart';
import 'package:chat_service/src/chat_repository.dart';
import 'package:chat_service/src/db.dart';
import 'package:chat_service/src/event_service_client.dart';
import 'package:chat_service/src/jwt_config.dart';
import 'package:chat_service/src/jwt_service.dart';
import 'package:chat_service/src/message_repository.dart';
import 'package:chat_service/src/user_service_client.dart';

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

    final chatsRepo = ChatRepository(db.connection);
    final messagesRepo = MessageRepository(db.connection);
    final eventService = EventServiceClient(config: EventServiceConfig.fromEnv());
    final userService = UserServiceClient(config: UserServiceConfig.fromEnv());

    final controller = ChatController(
      chats: chatsRepo,
      messages: messagesRepo,
      events: eventService,
      users: userService,
      jwt: jwtService,
      internalKey: internalKey,
    );

    final router = controller.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone Chat API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8085');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Chat service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
