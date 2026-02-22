import 'package:rating_service/rating_service.dart';
import 'package:test/test.dart';

void main() {
  test('rating summary model', () {
    final summary = RatingSummary(
      userId: 'user-1',
      averageScore: 4.5,
      totalEvents: 2,
    );

    expect(summary.averageScore, 4.5);
    expect(summary.totalEvents, 2);
  });
}
