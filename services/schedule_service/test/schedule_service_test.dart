import 'package:schedule_service/schedule_service.dart';
import 'package:test/test.dart';

void main() {
  test('availability slot model', () {
    final slot = AvailabilitySlot(
      id: 'slot-1',
      userId: 'user-1',
      date: '2026-02-04',
      timeFrom: '10:00',
      timeTo: '12:00',
    );

    expect(slot.userId, 'user-1');
    expect(slot.date, '2026-02-04');
  });
}
