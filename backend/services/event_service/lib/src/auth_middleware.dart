import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'jwt_service.dart';

class AuthContext {
  final JwtClaims claims;
  AuthContext(this.claims);
}

Middleware authMiddleware(JwtService jwtService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final auth = request.headers['authorization'];
      if (auth == null || !auth.toLowerCase().startsWith('bearer ')) {
        return Response(401,
            body: jsonEncode({'error': 'missing_bearer_token'}),
            headers: {'Content-Type': 'application/json'});
      }

      final token = auth.substring('bearer '.length).trim();

      try {
        final claims = jwtService.verifyAccessToken(token);

        if (claims.isBanned) {
          return Response(403,
              body: jsonEncode({'error': 'user_banned'}),
              headers: {'Content-Type': 'application/json'});
        }

        final changed = request.change(context: {
          ...request.context,
          'auth': AuthContext(claims),
        });

        return innerHandler(changed);
      } catch (_) {
        return Response(401,
            body: jsonEncode({'error': 'invalid_token'}),
            headers: {'Content-Type': 'application/json'});
      }
    };
  };
}

Middleware requireAdmin() {
  return (Handler innerHandler) {
    return (Request request) async {
      final auth = request.context['auth'];
      if (auth is! AuthContext) {
        return Response(401,
            body: jsonEncode({'error': 'missing_auth_context'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!auth.claims.isAdmin && !auth.claims.isSuperAdmin) {
        return Response(403,
            body: jsonEncode({'error': 'admin_required'}),
            headers: {'Content-Type': 'application/json'});
      }

      return innerHandler(request);
    };
  };
}

AuthContext requireAuth(Request request) {
  final ctx = request.context['auth'];
  if (ctx is AuthContext) return ctx;
  throw StateError('AuthContext missing. Did you forget authMiddleware?');
}
