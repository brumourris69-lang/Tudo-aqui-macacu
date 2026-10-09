import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/app_check_setup.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';

void main() {
  test(
    'disabled and emulator never activate providers even with authorization',
    () async {
      for (final mode in [AppCheckMode.disabled, AppCheckMode.emulator]) {
        var calls = 0;
        await prepareAppCheckProviders(
          plan: AppCheckProviderPlan(mode),
          activationAuthorized: true,
          activate: (_) async => calls++,
          setAutoRefresh: (_) async => calls++,
        );
        expect(calls, 0);
      }
    },
  );
  test('real provider activation remains denied by default', () async {
    var calls = 0;
    for (final mode in [AppCheckMode.debugProvider, AppCheckMode.attestation]) {
      await expectLater(
        prepareAppCheckProviders(
          plan: AppCheckProviderPlan(mode),
          activate: (_) async => calls++,
          setAutoRefresh: (_) async => calls++,
        ),
        throwsStateError,
      );
    }
    expect(calls, 0);
  });
  test(
    'official plan uses Integrity and App Attest with DeviceCheck fallback',
    () {
      const plan = AppCheckProviderPlan(AppCheckMode.attestation);
      expect(plan.android, AndroidProvider.playIntegrity);
      expect(plan.apple, AppleProvider.appAttestWithDeviceCheckFallback);
      const debug = AppCheckProviderPlan(AppCheckMode.debugProvider);
      expect(debug.android, AndroidProvider.debug);
      expect(debug.apple, AppleProvider.debug);
    },
  );
  test(
    'authorized mock activation precedes automatic refresh, without token fetch',
    () async {
      final calls = <String>[];
      await prepareAppCheckProviders(
        plan: const AppCheckProviderPlan(AppCheckMode.attestation),
        activationAuthorized: true,
        activate: (_) async => calls.add('activate'),
        setAutoRefresh: (enabled) async => calls.add('refresh:$enabled'),
      );
      expect(calls, ['activate', 'refresh:true']);
    },
  );
  test('provider failure is sanitized and never falls back to debug', () async {
    var activations = 0;
    var refresh = 0;
    await expectLater(
      prepareAppCheckProviders(
        plan: const AppCheckProviderPlan(AppCheckMode.attestation),
        activationAuthorized: true,
        activate: (_) async {
          activations++;
          throw StateError('synthetic-private-token');
        },
        setAutoRefresh: (_) async => refresh++,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message.toString(),
          'safe message',
          allOf(
            contains('dispositivo compatível'),
            isNot(contains('synthetic-private-token')),
          ),
        ),
      ),
    );
    expect(activations, 1);
    expect(refresh, 0);
  });
  test('refresh configuration failure fails closed', () async {
    await expectLater(
      prepareAppCheckProviders(
        plan: const AppCheckProviderPlan(AppCheckMode.attestation),
        activationAuthorized: true,
        activate: (_) async {},
        setAutoRefresh: (_) async => throw StateError('synthetic-token'),
      ),
      throwsStateError,
    );
  });
  test(
    'application entry point does not initialize real SDK by default',
    () async {
      if (AppCheckSetup.enabled) {
        expect(LocalSearchEnvironment.enabled, isTrue);
      }
      await AppCheckSetup.prepare();
    },
  );
}
