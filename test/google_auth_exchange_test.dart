import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/google_auth_exchange.dart';

void main() {
  test(
    'Google tokens become a Firebase Google credential exactly once',
    () async {
      var calls = 0;
      final accepted = await authenticateGoogleTokens<bool>(
        idToken: 'synthetic-id-token',
        accessToken: 'synthetic-access-token',
        authenticate: (credential) async {
          calls++;
          expect(credential, isA<OAuthCredential>());
          expect(credential.providerId, GoogleAuthProvider.PROVIDER_ID);
          expect(
            credential.signInMethod,
            GoogleAuthProvider.GOOGLE_SIGN_IN_METHOD,
          );
          return true;
        },
      );

      expect(accepted, isTrue);
      expect(calls, 1);
    },
  );

  test('missing Google ID token fails before calling Firebase Auth', () async {
    var calls = 0;
    await expectLater(
      authenticateGoogleTokens<void>(
        idToken: null,
        accessToken: 'synthetic-access-token',
        authenticate: (_) async => calls++,
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
}
