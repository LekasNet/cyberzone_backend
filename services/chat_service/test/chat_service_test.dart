import 'package:chat_service/chat_service.dart';
import 'package:test/test.dart';

void main() {
  test('chat message model', () {
    final message = ChatMessageRecord(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      text: 'hi',
      createdAt: DateTime.parse('2026-02-06T00:00:00Z'),
    );

    expect(message.text, 'hi');
    expect(message.userId, 'u1');
  });
}
