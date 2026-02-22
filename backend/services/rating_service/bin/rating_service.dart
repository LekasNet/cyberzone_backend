import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:rating_service/src/db.dart';
import 'package:rating_service/src/jwt_config.dart';
import 'package:rating_service/src/jwt_service.dart';
import 'package:rating_service/src/rating_controller.dart';
import 'package:rating_service/src/rating_repository.dart';
import 'package:rating_service/src/user_service_client.dart';

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

    final ratingsRepo = RatingRepository(db.connection);
    final userService = UserServiceClient(config: UserServiceConfig.fromEnv());

    final controller = RatingController(
      ratings: ratingsRepo,
      users: userService,
      jwt: jwtService,
      internalKey: internalKey,
    );

    final router = controller.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone Rating API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8084');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Rating service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
