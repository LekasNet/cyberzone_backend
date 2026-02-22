import 'dart:io';

import 'package:postgres/postgres.dart';

class DbConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  DbConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  factory DbConfig.fromEnv() {
    return DbConfig(
      host: Platform.environment['DB_HOST'] ?? 'localhost',
      port: int.parse(Platform.environment['DB_PORT'] ?? '5432'),
      database: Platform.environment['DB_NAME'] ?? 'cyberzone_notification',
      username: Platform.environment['DB_USER'] ?? 'cyberzone',
      password: Platform.environment['DB_PASSWORD'] ?? 'password',
    );
  }
}

class Db {
  final DbConfig config;
  late final PostgreSQLConnection _connection;

  Db(this.config);

  Future<void> connect() async {
    _connection = PostgreSQLConnection(
      config.host,
      config.port,
      config.database,
      username: config.username,
      password: config.password,
    );
    await _connection.open();
  }

  PostgreSQLConnection get connection => _connection;

  Future<void> close() => _connection.close();
}
