import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class RatingServiceConfig {
  final Uri baseUri;
  final String internalApiKey;

  RatingServiceConfig({
    required this.baseUri,
    required this.internalApiKey,
  });

  factory RatingServiceConfig.fromEnv() {
    final base = Platform.environment['RATING_SERVICE_URL'] ?? 'http://localhost:8084';
    final key = Platform.environment['INTERNAL_API_KEY'] ?? 'dev_internal_key';
    return RatingServiceConfig(
      baseUri: Uri.parse(base),
      internalApiKey: key,
    );
  }
}

class RatingSummary {
  final String userId;
  final double averageScore;
  final int totalEvents;

  RatingSummary({
    required this.userId,
    required this.averageScore,
    required this.totalEvents,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'averageScore': averageScore,
        'totalEvents': totalEvents,
      };
}

class RatingServiceClient {
  final http.Client _client;
  final RatingServiceConfig _config;

  RatingServiceClient({
    http.Client? client,
    required RatingServiceConfig config,
  })  : _client = client ?? http.Client(),
        _config = config;

  Future<Map<String, RatingSummary>> fetchRatingsBulk({
    required List<String> userIds,
  }) async {
    final uri = _config.baseUri.resolve('/internal/ratings/bulk');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'userIds': userIds}),
    );

    if (response.statusCode == 200) {
      final body = _decodeJson(response.body);
      final ratings = body['ratings'];
      if (ratings is List) {
        final map = <String, RatingSummary>{};
        for (final entry in ratings) {
          if (entry is Map<String, dynamic>) {
            final userId = entry['userId'] as String?;
            final avg = entry['averageScore'] as num?;
            final total = entry['totalEvents'] as num?;
            if (userId != null) {
              map[userId] = RatingSummary(
                userId: userId,
                averageScore: (avg ?? 0).toDouble(),
                totalEvents: (total ?? 0).toInt(),
              );
            }
          }
        }
        return map;
      }
      return <String, RatingSummary>{};
    }

    throw RatingServiceException(
      'bulk_ratings_failed',
      response.statusCode,
      response.body,
    );
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'x-internal-key': _config.internalApiKey,
      };

  Map<String, dynamic> _decodeJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('invalid_json');
  }
}

class RatingServiceException implements Exception {
  final String code;
  final int statusCode;
  final String body;

  RatingServiceException(this.code, this.statusCode, this.body);

  @override
  String toString() => 'RatingServiceException($code, $statusCode)';
}
