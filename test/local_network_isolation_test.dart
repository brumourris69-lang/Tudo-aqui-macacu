import 'dart:io';
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
    expect(
      isLocalEmulatorEndpoint(
        Uri.parse('http://${LocalSearchEnvironment.host}:9197/'),
        authPort: 9197,
      ),
      isTrue,
    );
    expect(
      isLocalEmulatorEndpoint(Uri.parse('http://127.0.0.1:9197/')),
      isFalse,
    );
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

  test('admin HTTP bridge permits only its explicit local debug route', () {
    const endpoint = 'http://127.0.0.1:5077/functions/v1/manage-establishments';
    expect(
      isLocalAdminBridgeEndpoint(
        Uri.parse(endpoint),
        localSearchEnabled: true,
        host: '127.0.0.1',
      ),
      isTrue,
    );
    expect(
      isLocalEmulatorEndpoint(
        Uri.parse(endpoint),
        localAdminBridgeEnabled: true,
        host: '127.0.0.1',
      ),
      isTrue,
    );
    expect(
      isLocalAdminBridgeEndpoint(
        Uri.parse(endpoint),
        localSearchEnabled: false,
        host: '127.0.0.1',
      ),
      isFalse,
    );
    for (final url in [
      'http://127.0.0.1:5077/other',
      'http://127.0.0.1:5078/functions/v1/manage-establishments',
      'http://127.0.0.1:5077/functions/v1/manage-establishments?debug=1',
      'http://user@127.0.0.1:5077/functions/v1/manage-establishments',
      'http://10.0.2.2:5077/functions/v1/manage-establishments',
      'https://127.0.0.1:5077/functions/v1/manage-establishments',
    ]) {
      expect(
        isLocalAdminBridgeEndpoint(
          Uri.parse(url),
          localSearchEnabled: true,
          host: '127.0.0.1',
        ),
        isFalse,
        reason: url,
      );
    }
  });

  test(
    'diagnostic proxy preflight is loopback-only and fails closed',
    () async {
      final observed = <String>[];
      await verifyLocalAuthDiagnosticProxy(
        enabled: true,
        host: '127.0.0.1',
        port: 9197,
        probe: (host, port) async => observed.add('$host:$port'),
      );
      expect(observed, ['127.0.0.1:9197']);

      await verifyLocalAuthDiagnosticProxy(
        enabled: false,
        host: 'not-used',
        port: 1,
        probe: (_, _) async => fail('disabled proxy must not be probed'),
      );

      observed.clear();
      await expectLater(
        verifyLocalAuthDiagnosticProxy(
          enabled: true,
          host: 'example.com',
          port: 9197,
          probe: (host, port) async => observed.add('$host:$port'),
        ),
        throwsStateError,
      );
      expect(observed, isEmpty);

      await expectLater(
        verifyLocalAuthDiagnosticProxy(
          enabled: true,
          host: '127.0.0.1',
          port: 9097,
          probe: (_, _) async {},
        ),
        throwsStateError,
      );
      await expectLater(
        verifyLocalAuthDiagnosticProxy(
          enabled: true,
          host: '127.0.0.1',
          port: 9197,
          probe: (_, _) async => throw const SocketException('private detail'),
        ),
        throwsStateError,
      );
    },
  );
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
