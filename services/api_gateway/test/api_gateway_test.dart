import 'package:api_gateway/api_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('gateway config parses environment', () {
    final config = GatewayConfig.fromEnv();
    expect(config.authUrl.scheme, isNotEmpty);
    expect(config.userUrl.scheme, isNotEmpty);
    expect(config.port, greaterThan(0));
  });
}
