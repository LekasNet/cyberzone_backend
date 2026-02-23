import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:user_service/src/db.dart';
import 'package:user_service/src/dictionary_repository.dart';
import 'package:user_service/src/jwt_config.dart';
import 'package:user_service/src/jwt_service.dart';
import 'package:user_service/src/rating_service_client.dart';
import 'package:user_service/src/user_controller.dart';
import 'package:user_service/src/user_repository.dart';

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
    final ratingService =
        RatingServiceClient(config: RatingServiceConfig.fromEnv());

    final usersRepo = UserRepository(db.connection);
    final dictionariesRepo = DictionaryRepository(db.connection);

    final userController = UserController(
      users: usersRepo,
      dictionaries: dictionariesRepo,
      jwt: jwtService,
      internalKey: internalKey,
      ratings: ratingService,
    );

    final router = userController.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone User API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8081');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('User service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
