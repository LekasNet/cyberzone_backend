import 'package:event_service/event_service.dart';
import 'package:test/test.dart';

void main() {
  test('event role model', () {
    final role = EventRoleRecord(
      id: 'role-1',
      eventId: 'event-1',
      roleId: 'caster',
      requiredCount: 2,
    );

    expect(role.requiredCount, 2);
    expect(role.roleId, 'caster');
  });
}
