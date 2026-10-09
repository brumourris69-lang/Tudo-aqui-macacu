import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';

void main() {
  test('only configured emulator host and Firebase ports are allowed', () {
    for (final port in [9097, 8087, 5007]) {
      expect(
        isLocalEmulatorEndpoint(
          Uri.parse('http://${LocalSearchEnvironment.host}:$port/'),
        ),
        isTrue,
      );
    }
    for (final url in [
      'https://firestore.googleapis.com/',
      'https://api.open-meteo.com/',
      'https://upload.workers.dev/',
      'https://res.cloudinary.com/',
      'http://${LocalSearchEnvironment.host}:443/',
      'http://user@${LocalSearchEnvironment.host}:9097/',
      'http://192.168.232.1:9097/',
    ]) {
      expect(isLocalEmulatorEndpoint(Uri.parse(url)), isFalse, reason: url);
    }
  });
  test(
    'HTTP client refuses external connections before opening a socket',
    () async {
      final client = LocalNetworkIsolation().createHttpClient(null);
      try {
      await expectLater(
        client.getUrl(Uri.parse('https://example.com/')),
        throwsA(isA<StateError>()),
      );
      } finally {
        client.close(force: true);
      }
    },
  );
  test('demo project cannot be overridden with another project', () {
    expect(
      () => LocalSearchEnvironment.requireDemo('demo-other'),
      throwsStateError,
    );
    expect(
      () => LocalSearchEnvironment.requireDemo('real-project'),
      throwsStateError,
    );
  });
}
