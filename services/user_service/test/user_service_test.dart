import 'package:test/test.dart';
import 'package:user_service/user_service.dart';

void main() {
  test('user record constructs', () {
    final user = UserRecord(
      id: 'user-1',
      email: 'test@example.com',
      firstName: 'Test',
      lastName: 'User',
      institute: null,
      group: null,
      avatarUrl: null,
      isAdmin: false,
      isSuperAdmin: false,
      isBanned: false,
    );

    expect(user.id, 'user-1');
    expect(user.email, 'test@example.com');
  });
}
