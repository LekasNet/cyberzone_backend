import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'auth_middleware.dart';
import 'availability_repository.dart';
import 'models.dart';
import 'rating_service_client.dart';
import 'user_service_client.dart';
import 'jwt_service.dart';

class ScheduleController {
  final AvailabilityRepository _availability;
  final UserServiceClient _users;
  final RatingServiceClient _ratings;
  final JwtService _jwt;
  final _uuid = const Uuid();

  ScheduleController({
    required AvailabilityRepository availability,
    required UserServiceClient users,
    required RatingServiceClient ratings,
    required JwtService jwt,
  })  : _availability = availability,
        _users = users,
        _ratings = ratings,
        _jwt = jwt;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    r.get('/availability/me', _withAuth(_getMyAvailability));
    r.post('/availability/me', _withAuth(_createMyAvailability));
    r.put('/availability/me/<id>', _withAuth(_updateMyAvailability));
    r.delete('/availability/me/<id>', _withAuth(_deleteMyAvailability));

    r.get('/availability/search', _withAdmin(_searchAvailability));

    return r;
  }

  Handler _withAuth(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addHandler(handler);

  Handler _withAdmin(Handler handler) => Pipeline()
      .addMiddleware(authMiddleware(_jwt))
      .addMiddleware(requireAdmin())
      .addHandler(handler);

  Future<Response> _health(Request request) async {
    return _json(200, {'status': 'ok'});
  }

  Future<Response> _getMyAvailability(Request request) async {
    final auth = requireAuth(request);

    final fromRaw = request.url.queryParameters['from'];
    final toRaw = request.url.queryParameters['to'];

    final fromDate = _parseDate(fromRaw);
    final toDate = _parseDate(toRaw);

    if ((fromRaw != null && fromDate == null) ||
        (toRaw != null && toDate == null)) {
      return _json(400, {'error': 'invalid_date_range'});
    }

    if (fromDate != null && toDate != null) {
      if (DateTime.parse(fromDate).isAfter(DateTime.parse(toDate))) {
        return _json(400, {'error': 'invalid_date_range'});
      }
    }

    final slots = await _availability.listForUser(
      auth.claims.userId,
      fromDate: fromDate,
      toDate: toDate,
    );

    return _json(200, {
      'slots': slots.map((s) => s.toJson()).toList(),
    });
  }

  Future<Response> _createMyAvailability(Request request) async {
    final auth = requireAuth(request);
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final date = _parseDate(body['date'] as String?);
    final fromTime = _parseTime(body['timeFrom'] as String?);
    final toTime = _parseTime(body['timeTo'] as String?);

    if (date == null || fromTime == null || toTime == null) {
      return _json(400, {'error': 'invalid_slot'});
    }

    if (fromTime.minutes >= toTime.minutes) {
      return _json(400, {'error': 'invalid_time_range'});
    }

    final slot = await _availability.createSlot(
      id: _uuid.v4(),
      userId: auth.claims.userId,
      date: date,
      timeFrom: fromTime.value,
      timeTo: toTime.value,
    );

    return _json(201, slot.toJson());
  }

  Future<Response> _updateMyAvailability(Request request) async {
    final auth = requireAuth(request);
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_slot_id'});
    }
    final body = await _tryReadJson(request);
    if (body == null) return _json(400, {'error': 'invalid_json'});

    final date = _parseDate(body['date'] as String?);
    final fromTime = _parseTime(body['timeFrom'] as String?);
    final toTime = _parseTime(body['timeTo'] as String?);

    if (date == null || fromTime == null || toTime == null) {
      return _json(400, {'error': 'invalid_slot'});
    }

    if (fromTime.minutes >= toTime.minutes) {
      return _json(400, {'error': 'invalid_time_range'});
    }

    final slot = await _availability.updateSlot(
      id: id,
      userId: auth.claims.userId,
      date: date,
      timeFrom: fromTime.value,
      timeTo: toTime.value,
    );

    if (slot == null) return _json(404, {'error': 'slot_not_found'});

    return _json(200, slot.toJson());
  }

  Future<Response> _deleteMyAvailability(Request request) async {
    final auth = requireAuth(request);
    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return _json(400, {'error': 'missing_slot_id'});
    }
    final ok = await _availability.deleteSlot(
      id: id,
      userId: auth.claims.userId,
    );

    if (!ok) return _json(404, {'error': 'slot_not_found'});
    return _json(200, {'ok': true});
  }

  Future<Response> _searchAvailability(Request request) async {
    final params = request.url.queryParameters;

    final minRatingRaw = params['minRating'];
    double? minRating;
    if (minRatingRaw != null) {
      minRating = double.tryParse(minRatingRaw);
      if (minRating == null || minRating < 0) {
        return _json(400, {'error': 'invalid_min_rating'});
      }
    }

    final date = _parseDate(params['date']);
    final fromTime = _parseTime(params['fromTime']);
    final toTime = _parseTime(params['toTime']);

    if (date == null || fromTime == null || toTime == null) {
      return _json(400, {'error': 'invalid_search_params'});
    }

    if (fromTime.minutes >= toTime.minutes) {
      return _json(400, {'error': 'invalid_time_range'});
    }

    final slots = await _availability.searchSlots(
      date: date,
      fromTime: fromTime.value,
      toTime: toTime.value,
    );

    if (slots.isEmpty) return _json(200, {'users': []});

    final roleId = params['roleId'];
    final disciplineId = params['disciplineId'];

    final userIds = slots.map((s) => s.userId).toSet().toList();

    List<Map<String, dynamic>> users;
    try {
      users = await _users.fetchUsersBulk(
        userIds: userIds,
        roleId: roleId,
        disciplineId: disciplineId,
      );
    } catch (_) {
      return _json(502, {'error': 'user_service_unavailable'});
    }

    if (users.isEmpty) return _json(200, {'users': []});

    Map<String, RatingSummary> ratings = {};
    if (minRating != null) {
      try {
        ratings = await _ratings.fetchRatingsBulk(userIds: userIds);
      } catch (_) {
        return _json(502, {'error': 'rating_service_unavailable'});
      }
    }

    final allowedIds = users.map((u) => u['id'] as String).toSet();
    final slotsByUser = <String, List<AvailabilitySlot>>{};

    for (final slot in slots) {
      if (!allowedIds.contains(slot.userId)) continue;
      slotsByUser.putIfAbsent(slot.userId, () => <AvailabilitySlot>[]).add(slot);
    }

    final items = users.where((user) {
      if (minRating == null) return true;
      final userId = user['id'] as String?;
      if (userId == null) return false;
      final rating = ratings[userId];
      final avg = rating?.averageScore ?? 0;
      return avg >= minRating!;
    }).map((user) {
      final copy = Map<String, dynamic>.from(user);
      final userSlots = slotsByUser[user['id']] ?? <AvailabilitySlot>[];
      copy['availability'] = userSlots.map((s) => s.toJson()).toList();
      if (minRating != null) {
        final userId = user['id'] as String?;
        if (userId != null) {
          final rating = ratings[userId];
          copy['rating'] = rating?.toJson() ??
              {'userId': userId, 'averageScore': 0, 'totalEvents': 0};
        }
      }
      return copy;
    }).toList();

    return _json(200, {'users': items});
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

  String? _parseDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    if (!match) return null;
    try {
      DateTime.parse(value);
      return value;
    } catch (_) {
      return null;
    }
  }

  _TimeValue? _parseTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\d{2}:\d{2}$').hasMatch(value);
    if (!match) return null;
    final parts = value.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    return _TimeValue(value, hour * 60 + minute);
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}

class _TimeValue {
  final String value;
  final int minutes;

  _TimeValue(this.value, this.minutes);
}
