import 'dart:io';

class JwtConfig {
  final String secret;
  final Duration accessTtl;
  final String issuer;

  JwtConfig({
    required this.secret,
    required this.accessTtl,
    required this.issuer,
  });

  factory JwtConfig.fromEnv() {
    final secret = Platform.environment['JWT_SECRET'] ?? 'dev_secret_change_me';
    final accessMinutes = int.parse(Platform.environment['ACCESS_TTL_MIN'] ?? '30');
    final issuer = Platform.environment['JWT_ISSUER'] ?? 'cyberzone';

    return JwtConfig(
      secret: secret,
      accessTtl: Duration(minutes: accessMinutes),
      issuer: issuer,
    );
  }
}
