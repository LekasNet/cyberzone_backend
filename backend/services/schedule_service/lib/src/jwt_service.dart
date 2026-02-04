import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'jwt_config.dart';

class JwtClaims {
  final String userId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool isBanned;

  JwtClaims({
    required this.userId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.isBanned,
  });
}

class JwtService {
  final JwtConfig config;

  JwtService(this.config);

  JwtClaims verifyAccessToken(String token) {
    final jwt = JWT.verify(token, SecretKey(config.secret));

    final payload = jwt.payload as Map<String, dynamic>;
    return JwtClaims(
      userId: payload['uid'] as String,
      isAdmin: payload['adm'] as bool? ?? false,
      isSuperAdmin: payload['sadm'] as bool? ?? false,
      isBanned: payload['ban'] as bool? ?? false,
    );
  }
}
