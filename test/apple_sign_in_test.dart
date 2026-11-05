import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/apple_sign_in_configuration.dart';
import 'package:tudo_aqui_macacu/core/auth/auth_error_message.dart';

void main() {
  test('Apple sign-in is offered only for a ready configured iOS Beta', () {
    bool available({
      bool ios = true,
      bool betaBuild = true,
      bool betaReady = true,
      bool providerConfigured = true,
    }) => shouldOfferAppleSignIn(
      isIos: ios,
      betaBuildEnabled: betaBuild,
      betaReady: betaReady,
      providerConfigured: providerConfigured,
    );

    expect(available(), isTrue);
    expect(available(ios: false), isFalse);
    expect(available(betaBuild: false), isFalse);
    expect(available(betaReady: false), isFalse);
    expect(available(providerConfigured: false), isFalse);
  });

  test('unconfigured Apple sign-in fails before invoking Firebase', () async {
    var called = false;
    await expectLater(
      authenticateWithAppleProvider<void>(
        isIos: true,
        betaBuildEnabled: true,
        betaReady: false,
        providerConfigured: true,
        authenticate: (_) async {
          called = true;
        },
      ),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test(
    'configured Apple flow uses Firebase Apple provider and scopes',
    () async {
      AppleAuthProvider? received;
      final result = await authenticateWithAppleProvider<String>(
        isIos: true,
        betaBuildEnabled: true,
        betaReady: true,
        providerConfigured: true,
        authenticate: (provider) async {
          received = provider;
          return 'signed-in';
        },
      );

      expect(result, 'signed-in');
      expect(received?.providerId, AppleAuthProvider.PROVIDER_ID);
      expect(received?.scopes, containsAll(['email', 'name']));
    },
  );

  test(
    'Apple cancellation is quiet and other failures have safe messaging',
    () {
      expect(
        isAppleSignInCancellation(FirebaseAuthException(code: 'canceled')),
        isTrue,
      );
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'operation-not-allowed'),
          action: AuthErrorAction.appleSignIn,
        ),
        'Esta forma de acesso ainda não está habilitada neste ambiente.',
      );
    },
  );
}
