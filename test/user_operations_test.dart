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
  test(
    'getSearchJob is not authorized by the normal secure transport',
    () async {
      expect(SecureBackend.productionAuthorized, isFalse);
      await expectLater(
        SecureBackend.invoke('getSearchJob', {'id': 'job-1'}),
        throwsArgumentError,
      );
    },
  );
  test('staging-only getPublicJob is unavailable in the normal app', () async {
    expect(SecureBackend.productionAuthorized, isFalse);
    await expectLater(
      SecureBackend.invoke('getPublicJob', {'id': 'job-1'}),
      throwsArgumentError,
    );
  });
  if (!LocalSearchEnvironment.enabled) {
    test(
      'public detail callable is recognized but production gate stays closed',
      () async {
        expect(SecureBackend.productionAuthorized, isFalse);
        await expectLater(
          SecureBackend.invoke('getPublicContentDetail', {
            'collection': 'establishments',
            'id': 'business-1',
          }),
          throwsStateError,
        );
      },
    );
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
    test(
      'public detail callable checks native isolation before any network call',
      () async {
        var isolationChecks = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LocalNetworkIsolation.channel, (_) async {
              isolationChecks++;
              return {'local': true, 'isolated': false};
            });
        try {
          await expectLater(
            SecureBackend.invoke('getPublicContentDetail', {
              'collection': 'establishments',
              'id': 'business-1',
            }),
            throwsStateError,
          );
          expect(isolationChecks, 1);
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(LocalNetworkIsolation.channel, null);
        }
      },
    );
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
