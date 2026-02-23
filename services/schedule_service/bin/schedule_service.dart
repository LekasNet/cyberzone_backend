import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:schedule_service/src/availability_repository.dart';
import 'package:schedule_service/src/db.dart';
import 'package:schedule_service/src/jwt_config.dart';
import 'package:schedule_service/src/jwt_service.dart';
import 'package:schedule_service/src/rating_service_client.dart';
import 'package:schedule_service/src/schedule_controller.dart';
import 'package:schedule_service/src/user_service_client.dart';

Future<void> main(List<String> args) async {
  try {
    final dbConfig = DbConfig.fromEnv();
    print('Resolved DB -> ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}');

    final db = Db(dbConfig);
    await db.connect();
    print('Connected to ${dbConfig.database}');

    final jwtConfig = JwtConfig.fromEnv();
    final jwtService = JwtService(jwtConfig);

    final userService = UserServiceClient(config: UserServiceConfig.fromEnv());
    final ratingService =
        RatingServiceClient(config: RatingServiceConfig.fromEnv());
    final availabilityRepo = AvailabilityRepository(db.connection);

    final controller = ScheduleController(
      availability: availabilityRepo,
      users: userService,
      ratings: ratingService,
      jwt: jwtService,
    );

    final router = controller.router
      ..mount(
        '/docs/',
        SwaggerUI(
          'specs/openapi.yaml',
          title: 'Cyberzone Schedule API',
        ).call,
      );

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

    final port = int.parse(Platform.environment['PORT'] ?? '8082');
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);

    print('Schedule service listening on http://localhost:${server.port}');
    print('Swagger UI: http://localhost:${server.port}/docs/');
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    rethrow;
  }
}
