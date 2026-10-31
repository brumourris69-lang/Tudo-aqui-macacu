import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/google_sign_in_configuration.dart';

void main() {
  const beta = '123456789012-beta.apps.googleusercontent.com';

  test('Beta Google sign-in uses only its explicit isolated OAuth client', () {
    expect(
      googleSignInServerClientId(betaVariant: true, betaClientId: beta),
      beta,
    );
  });

  test(
    'Beta never falls back to production when its OAuth client is missing',
    () {
      expect(
        () => googleSignInServerClientId(betaVariant: true, betaClientId: ''),
        throwsStateError,
      );
      expect(
        () => googleSignInServerClientId(
          betaVariant: true,
          betaClientId: productionGoogleWebClientId,
        ),
        throwsStateError,
      );
    },
  );

  test('existing non-Beta build keeps its configured OAuth client', () {
    expect(
      googleSignInServerClientId(betaVariant: false, betaClientId: beta),
      productionGoogleWebClientId,
    );
  });
}
