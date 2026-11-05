import 'package:firebase_auth/firebase_auth.dart';

bool shouldOfferAppleSignIn({
  required bool isIos,
  required bool betaBuildEnabled,
  required bool betaReady,
  required bool providerConfigured,
}) => isIos && betaBuildEnabled && betaReady && providerConfigured;

Future<T> authenticateWithAppleProvider<T>({
  required bool isIos,
  required bool betaBuildEnabled,
  required bool betaReady,
  required bool providerConfigured,
  required Future<T> Function(AppleAuthProvider provider) authenticate,
}) async {
  if (!shouldOfferAppleSignIn(
    isIos: isIos,
    betaBuildEnabled: betaBuildEnabled,
    betaReady: betaReady,
    providerConfigured: providerConfigured,
  )) {
    throw StateError('O início de sessão Apple não está configurado.');
  }

  final provider = AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');
  return authenticate(provider);
}

bool isAppleSignInCancellation(Object error) =>
    error is FirebaseAuthException && error.code.toLowerCase() == 'canceled';
