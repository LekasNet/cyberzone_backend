import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:auth_service/src/auth_controller.dart';
import 'package:auth_service/src/auth_repository.dart';
import 'package:auth_service/src/db.dart';
import 'package:auth_service/src/jwt_config.dart';
import 'package:auth_service/src/jwt_service.dart';
import 'package:auth_service/src/password_hasher.dart';
import 'package:auth_service/src/refresh_repository.dart';
import 'package:auth_service/src/user_service_client.dart';

Future<void> main(List<String> args) async {
  try {
    final dbConfig = DbConfig.fromEnv();
    print('Resolved DB -> ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}');

    final db = Db(dbConfig);
    await db.connect();
    print('Connected to ${dbConfig.database}');

    final jwtConfig = JwtConfig.fromEnv();
    final jwtService = JwtService(jwtConfig);

    final usersRepo = AuthRepository(db.connection);
    final refreshRepo = RefreshRepository(db.connection);
    final hasher = const PasswordHasher();
    final userService = UserServiceClient(config: UserServiceConfig.fromEnv());

    final authController = AuthController(
      users: usersRepo,
      refresh: refreshRepo,
      hasher: hasher,
      jwt: jwtService,
      jwtConfig: jwtConfig,
      userService: userService,
    );

    final router = Router()
      ..mount('/auth/', authController.router)
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml', // берёт с /openapi.yaml (см. ниже)
          title: 'Cyberzone Auth API',
        ).call,
      );

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8080');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Auth service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
