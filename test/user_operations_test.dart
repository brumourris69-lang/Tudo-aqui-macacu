import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/content/user_operations.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown backend endpoint is rejected before any SDK/network access',
    () async {
      await expectLater(
        SecureBackend.invoke('grantAdmin', {}),
        throwsArgumentError,
      );
    },
  );
  if (!LocalSearchEnvironment.enabled) {
    test(
      'normal build has no direct-write fallback before authorized activation',
      () async {
        expect(SecureBackend.productionAuthorized, isFalse);
        await expectLater(writeUserOperation('contact', {}), throwsStateError);
        await expectLater(
          SecureBackend.invoke('listPublicContent', {}),
          throwsStateError,
        );
      },
    );
  } else {
    for (final native in [
      {'local': false, 'isolated': false},
      {'local': true, 'isolated': false},
    ]) {
      test(
        'local write refuses unsafe environment $native without fallback',
        () async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                LocalNetworkIsolation.channel,
                (_) async => native,
              );
          try {
            await expectLater(
              writeUserOperation('contact', {}),
              throwsStateError,
            );
          } finally {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(LocalNetworkIsolation.channel, null);
          }
        },
      );
    }
  }
}
