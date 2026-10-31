import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/spark_local_environment.dart';

void main() {
  test('Spark local runtime requires demo, native local package and VPN', () {
    expect(
      SparkLocalEnvironment.acceptsRuntime(
        enabled: true,
        nativeLocal: true,
        nativeIsolated: true,
        host: '127.0.0.1',
        projectId: 'demo-universal-search',
      ),
      isTrue,
    );
    for (final invalid in [
      (local: false, isolated: true, project: 'demo-universal-search'),
      (local: true, isolated: false, project: 'demo-universal-search'),
      (local: true, isolated: true, project: 'macacu-beta-261030-cf4a81'),
    ]) {
      expect(
        SparkLocalEnvironment.acceptsRuntime(
          enabled: true,
          nativeLocal: invalid.local,
          nativeIsolated: invalid.isolated,
          host: '127.0.0.1',
          projectId: invalid.project,
        ),
        isFalse,
      );
    }
  });

  test('Spark local HTTP policy allows only Auth and Firestore loopback', () {
    expect(
      isSparkLocalEmulatorEndpoint(
        Uri.parse('http://127.0.0.1:9097/identitytoolkit.googleapis.com'),
      ),
      isTrue,
    );
    expect(
      isSparkLocalEmulatorEndpoint(Uri.parse('http://127.0.0.1:8087/v1')),
      isTrue,
    );
    expect(
      isSparkLocalEmulatorEndpoint(Uri.parse('http://127.0.0.1:5007/')),
      isFalse,
    );
    expect(
      isSparkLocalEmulatorEndpoint(
        Uri.parse('https://firestore.googleapis.com'),
      ),
      isFalse,
    );
  });
}
