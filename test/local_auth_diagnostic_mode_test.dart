import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';

void main() {
  test('Auth endpoint is selected only by the explicit demo debug opt-in', () {
    if (LocalSearchEnvironment.authHttpDiagnosticsEnabled) {
      expect(LocalSearchEnvironment.enabled, isTrue);
      expect(LocalSearchEnvironment.project, 'demo-universal-search');
      expect(LocalSearchEnvironment.host, '127.0.0.1');
      expect(LocalSearchEnvironment.authEmulatorPort, 9197);
    } else {
      expect(LocalSearchEnvironment.authEmulatorPort, 9097);
    }
  });
}
