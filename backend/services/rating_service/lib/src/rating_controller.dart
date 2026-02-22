import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'auth_middleware.dart';
import 'models.dart';
import 'rating_repository.dart';
import 'jwt_service.dart';
import 'user_service_client.dart';

class RatingController {
  final RatingRepository _ratings;
  final UserServiceClient _users;
  final JwtService _jwt;
  final String _internalKey;
  final _uuid = const Uuid();

  RatingController({
    required RatingRepository ratings,
    required UserServiceClient users,
    required JwtService jwt,
    required String internalKey,
  })  : _ratings = ratings,
        _users = users,
        _jwt = jwt,
        _internalKey = internalKey;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.post('/events/<id>/ratings', _withAdmin(_createRatings));
    r.get('/events/<id>/ratings', _withAdmin(_listEventRatings));

    r.get('/ratings/users', _withAdmin(_listRatingsByRole));
    r.get('/ratings/users/<id>', _withAuth(_getUserRating));

    r.post('/internal/ratings/bulk', _withInternal(_getRatingsBulk));

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addHandler(handler);

  Handler _withAdmin(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addMiddleware(requireAdmin())
      .addHandler(handler);

  Handler _withInternal(Handler handler) => Pipeline()
      .addMiddleware(_internalAuth())
      .addHandler(handler);

  Middleware _internalAuth() {
    return (Handler innerHandler) {
      return (Request request) async {
        final key = request.headers['x-internal-key'];
        if (key == null || key != _internalKey) {
          return _json(401, {'error': 'invalid_internal_key'});
        }
        return innerHandler(request);
      };
    };
  }

  Future<Response> _health(Request request) async {
    return _json(200, {'status': 'ok'});
  }

  Future<Response> _createRatings(Request request) async {
    final auth = requireAuth(request);
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final ratingsInput = body['ratings'];
    if (ratingsInput is! List) return _json(400, {'error': 'invalid_ratings'});

    final inputs = <RatingInput>[];
    final userIds = <String>{};

    for (final item in ratingsInput) {
      if (item is! Map<String, dynamic>) {
        return _json(400, {'error': 'invalid_ratings'});
      }
      final userId = item['userId'] as String?;
      final score = item['score'];
      final comment = item['comment'] as String?;

      if (userId == null || userId.isEmpty) {
        return _json(400, {'error': 'invalid_ratings'});
      }
      if (score is! int || score < 1 || score > 5) {
        return _json(400, {'error': 'invalid_score'});
      }
      if (!userIds.add(userId)) {
        return _json(400, {'error': 'duplicate_user_ids'});
      }

      inputs.add(RatingInput(
        id: _uuid.v4(),
        userId: userId,
        score: score,
        comment: comment,
      ));
    }

    if (inputs.isEmpty) {
      return _json(400, {'error': 'invalid_ratings'});
    }

    final stored = await _ratings.upsertRatings(
      eventId: eventId,
      ratedBy: auth.claims.userId,
      ratings: inputs,
    );

    return _json(200, {'ratings': stored.map((r) => r.toJson()).toList()});
  }

  Future<Response> _listEventRatings(Request request) async {
    final eventId = request.params['id'];
    if (eventId == null || eventId.isEmpty) {
      return _json(400, {'error': 'missing_event_id'});
    }

    final ratings = await _ratings.listByEvent(eventId);
    return _json(200, {'ratings': ratings.map((r) => r.toJson()).toList()});
  }

  Future<Response> _getUserRating(Request request) async {
    final userId = request.params['id'];
    if (userId == null || userId.isEmpty) {
      return _json(400, {'error': 'missing_user_id'});
    }

    final summary = await _ratings.summaryForUser(userId);
    if (summary == null) {
      return _json(200, {
        'userId': userId,
        'averageScore': 0,
        'totalEvents': 0,
      });
    }

    return _json(200, summary.toJson());
  }

  Future<Response> _listRatingsByRole(Request request) async {
    final roleIds = _parseRoleIds(request);
    if (roleIds == null) {
      return _json(400, {'error': 'invalid_role_ids'});
    }

    List<String> userIds;
    try {
      userIds = await _users.fetchUserIdsByRoles(roleIds: roleIds);
    } catch (_) {
      return _json(502, {'error': 'user_service_unavailable'});
    }

    if (userIds.isEmpty) {
      return _json(200, {'ratings': []});
    }

    final summaryMap = await _ratings.summaryForUsers(userIds);
    final items = userIds.map((id) {
      final summary = summaryMap[id];
      return (summary ??
              RatingSummary(
                userId: id,
                averageScore: 0,
                totalEvents: 0,
              ))
          .toJson();
    }).toList();

    return _json(200, {'ratings': items});
  }

  Future<Response> _getRatingsBulk(Request request) async {
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final userIds = _parseIdList(body['userIds']);
    if (userIds == null || userIds.isEmpty) {
      return _json(400, {'error': 'userIds_required'});
    }

    final summaryMap = await _ratings.summaryForUsers(userIds);
    final items = userIds.map((id) {
      final summary = summaryMap[id];
      if (summary == null) {
        return RatingSummary(userId: id, averageScore: 0, totalEvents: 0)
            .toJson();
      }
      return summary.toJson();
    }).toList();

    return _json(200, {'ratings': items});
  }

  Future<Map<String, dynamic>?> _tryReadJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
      return null;
    } catch (_) {
      return null;
    }
  }

  List<String>? _parseIdList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;

    final result = <String>[];
    for (final item in value) {
      if (item is String) {
        result.add(item);
      } else if (item is int) {
        result.add(item.toString());
      } else {
        return null;
      }
    }

    return result;
  }

  List<String>? _parseRoleIds(Request request) {
    final all = request.url.queryParametersAll['roleIds'];
    if (all != null && all.isNotEmpty) {
      final result = <String>[];
      for (final entry in all) {
        result.addAll(_splitCsv(entry));
      }
      return result;
    }

    final single = request.url.queryParameters['roleIds'];
    if (single != null && single.isNotEmpty) {
      return _splitCsv(single);
    }

    return <String>[];
  }

  List<String> _splitCsv(String value) {
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}
