import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'auth_repository.dart';
import 'refresh_repository.dart';
import 'password_hasher.dart';
import 'jwt_service.dart';
import 'jwt_config.dart';
import 'token_utils.dart';
import 'auth_middleware.dart';
import 'user_service_client.dart';

class AuthController {
  final AuthRepository _users;
  final RefreshRepository _refresh;
  final PasswordHasher _hasher;
  final JwtService _jwt;
  final JwtConfig _jwtConfig;
  final UserServiceClient _userService;

  final _uuid = const Uuid();

  AuthController({
    required AuthRepository users,
    required RefreshRepository refresh,
    required PasswordHasher hasher,
    required JwtService jwt,
    required JwtConfig jwtConfig,
    required UserServiceClient userService,
  })  : _users = users,
        _refresh = refresh,
        _hasher = hasher,
        _jwt = jwt,
        _jwtConfig = jwtConfig,
        _userService = userService;

  Router get router {
    final r = Router();

    r.get('/health', (Request req) => Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    ));

    r.post('/register', _register);
    r.post('/login', _login);
    r.post('/refresh', _refreshToken);
    r.post('/logout', _logout);

    // protected
    r.get('/me', Pipeline().addMiddleware(authMiddleware(_jwt)).addHandler(_me));

    return r;
  }

  Future<Response> _register(Request request) async {
    final body = await _readJson(request);

    final email = (body['email'] as String?)?.trim();
    final password = body['password'] as String?;

    if (email == null || email.isEmpty || password == null || password.isEmpty) {
      return _json(400, {'error': 'email_and_password_required'});
    }

    final existing = await _users.findByEmail(email);
    if (existing != null) return _json(409, {'error': 'user_already_exists'});

    final userId = _uuid.v4();
    final hash = _hasher.hash(password);

    final user = await _users.createUser(id: userId, email: email, passwordHash: hash);

    late final UserFlags flags;
    try {
      flags = await _userService.createUser(userId: user.id, email: user.email);
    } catch (_) {
      await _users.deleteById(user.id);
      return _json(502, {'error': 'user_service_unavailable'});
    }

    final tokens =
        await _issueTokens(user.id, flags.isAdmin, flags.isSuperAdmin, flags.isBanned);
    return _json(201, {'userId': user.id, ...tokens});
  }

  Future<Response> _login(Request request) async {
    final body = await _readJson(request);

    final email = (body['email'] as String?)?.trim();
    final password = body['password'] as String?;

    if (email == null || email.isEmpty || password == null || password.isEmpty) {
      return _json(400, {'error': 'email_and_password_required'});
    }

    final user = await _users.findByEmail(email);
    if (user == null) return _json(401, {'error': 'invalid_credentials'});

    final ok = _hasher.verify(password, user.passwordHash);
    if (!ok) return _json(401, {'error': 'invalid_credentials'});

    late final UserFlags flags;
    try {
      flags = await _userService.getFlags(user.id);
    } catch (_) {
      return _json(502, {'error': 'user_service_unavailable'});
    }

    if (flags.isBanned) return _json(403, {'error': 'user_banned'});

    final tokens =
        await _issueTokens(user.id, flags.isAdmin, flags.isSuperAdmin, flags.isBanned);
    return _json(200, tokens);
  }

  Future<Response> _refreshToken(Request request) async {
    final body = await _readJson(request);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      return _json(400, {'error': 'refreshToken_required'});
    }

    final tokenHash = sha256Hex(refreshToken);
    final row = await _refresh.findByHash(tokenHash);
    if (row == null) return _json(401, {'error': 'invalid_refresh_token'});

    if (row.revokedAt != null) return _json(401, {'error': 'refresh_token_revoked'});
    if (DateTime.now().toUtc().isAfter(row.expiresAt.toUtc())) {
      return _json(401, {'error': 'refresh_token_expired'});
    }

    // Подтягиваем флаги пользователя (admin/banned и т.д.)
    final user = await _users.findById(row.userId);
    if (user == null) return _json(401, {'error': 'user_not_found'});

    late final UserFlags flags;
    try {
      flags = await _userService.getFlags(user.id);
    } catch (_) {
      return _json(502, {'error': 'user_service_unavailable'});
    }

    if (flags.isBanned) return _json(403, {'error': 'user_banned'});

    // rotation: старый токен помечаем revoked, выдаём новый
    await _refresh.revoke(row.id);

    final tokens =
        await _issueTokens(user.id, flags.isAdmin, flags.isSuperAdmin, flags.isBanned);
    return _json(200, tokens);
  }

  Future<Response> _logout(Request request) async {
    final body = await _readJson(request);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      return _json(400, {'error': 'refreshToken_required'});
    }

    final tokenHash = sha256Hex(refreshToken);
    final row = await _refresh.findByHash(tokenHash);
    if (row == null) return _json(200, {'ok': true}); // не палим наличие токена

    await _refresh.revoke(row.id);
    return _json(200, {'ok': true});
  }

  Future<Response> _me(Request request) async {
    final auth = requireAuth(request);
    return _json(200, {
      'userId': auth.claims.userId,
      'isAdmin': auth.claims.isAdmin,
      'isSuperAdmin': auth.claims.isSuperAdmin,
      'isBanned': auth.claims.isBanned,
    });
  }

  Future<Map<String, dynamic>> _issueTokens(
      String userId,
      bool isAdmin,
      bool isSuperAdmin,
      bool isBanned,
      ) async {
    final access = _jwt.signAccessToken(JwtClaims(
      userId: userId,
      isAdmin: isAdmin,
      isSuperAdmin: isSuperAdmin,
      isBanned: isBanned,
    ));

    final refreshToken = _uuid.v4() + _uuid.v4(); // достаточно для dev; можно усилить random bytes
    final refreshHash = sha256Hex(refreshToken);
    final expiresAt = DateTime.now().toUtc().add(_jwtConfig.refreshTtl);

    await _refresh.insert(
      id: _uuid.v4(),
      userId: userId,
      tokenHash: refreshHash,
      expiresAt: expiresAt,
    );

    return {
      'accessToken': access,
      'refreshToken': refreshToken,
      'accessExpiresInSeconds': _jwtConfig.accessTtl.inSeconds,
      'refreshExpiresInSeconds': _jwtConfig.refreshTtl.inSeconds,
    };
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final s = await request.readAsString();
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      throw const FormatException('json_not_object');
    } catch (_) {
      throw const FormatException('invalid_json');
    }
  }

  Response _json(int status, Map<String, dynamic> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );
}
