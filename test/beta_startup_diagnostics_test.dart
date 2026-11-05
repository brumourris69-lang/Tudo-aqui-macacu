import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/beta_startup_diagnostics.dart';

void main() {
  test('development startup diagnostics identify each failure boundary', () {
    expect(
      betaStartupFailureCode(
        BetaStartupStage.configuration,
        StateError('configuration mismatch'),
      ),
      'invalid_configuration',
    );
    expect(
      betaStartupFailureCode(
        BetaStartupStage.firebaseInitialization,
        PlatformException(code: 'firebase_core/unknown'),
      ),
      'firebase_initialization_failed',
    );
    expect(
      betaStartupFailureCode(
        BetaStartupStage.appCheck,
        PlatformException(
          code: 'unknown',
          message: 'App is not registered for App Check; token secret-123',
        ),
      ),
      'app_check_not_registered',
    );
    expect(
      betaStartupFailureCode(
        BetaStartupStage.appCheck,
        PlatformException(
          code: 'unknown',
          message: 'Play Integrity attestation unavailable',
        ),
      ),
      'app_check_attestation_failed',
    );
    expect(
      betaStartupFailureCode(
        BetaStartupStage.authentication,
        TimeoutException('private data'),
      ),
      'authentication_timeout',
    );
  });

  test('iOS Firebase initialization failure is described without fallback', () {
    final code = betaStartupFailureCode(
      BetaStartupStage.firebaseInitialization,
      PlatformException(code: 'firebase_core/unknown'),
      ios: true,
    );
    expect(code, 'ios_firebase_configuration_unavailable');
    expect(
      betaStartupFailureMessage(code),
      contains('configuração nativa Firebase do iOS está ausente'),
    );
  });

  test(
    'structured diagnostics log stage and code only, not exception text',
    () async {
      final messages = <String>[];
      await expectLater(
        runBetaStartupStep<void>(
          BetaStartupStage.appCheck,
          () => throw PlatformException(
            code: 'unknown',
            message: 'private-token-value Play Integrity unavailable',
          ),
          log: messages.add,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(messages.first, contains('stage=app_check result=started'));
      expect(messages.last, contains('code=app_check_attestation_failed'));
      expect(messages.join(' '), isNot(contains('private-token-value')));
    },
  );
}
