import 'package:firebase_auth/firebase_auth.dart';
import '../config/spark_public_catalog_environment.dart';

bool shouldOfferAppleSignIn({
  required bool isIos,
  required bool betaBuildEnabled,
  required bool betaReady,
  required bool providerConfigured,
}) =>
    (isIos && betaBuildEnabled && betaReady && providerConfigured) ||
    shouldOfferSparkDistributionAppleSignIn(
      isIos: isIos,
      distributionEnabled: SparkPublicCatalogEnvironment.enabled,
      identityReady: SparkPublicCatalogEnvironment.ready,
      providerConfigured: SparkPublicCatalogEnvironment.iosAppleSignInEnabled,
    );

bool shouldOfferSparkDistributionAppleSignIn({
  required bool isIos,
  required bool distributionEnabled,
  required bool identityReady,
  required bool providerConfigured,
}) => isIos && distributionEnabled && identityReady && providerConfigured;

Future<T> authenticateWithAppleProvider<T>({
  required bool isIos,
  required bool betaBuildEnabled,
  required bool betaReady,
  required bool providerConfigured,
  bool sparkDistributionBuildEnabled = false,
  bool sparkDistributionReady = false,
  bool sparkProviderConfigured = false,
  required Future<T> Function(AppleAuthProvider provider) authenticate,
}) async {
  final betaCanAuthenticate = shouldOfferAppleSignIn(
    isIos: isIos,
    betaBuildEnabled: betaBuildEnabled,
    betaReady: betaReady,
    providerConfigured: providerConfigured,
  );
  final sparkCanAuthenticate = shouldOfferSparkDistributionAppleSignIn(
    isIos: isIos,
    distributionEnabled: sparkDistributionBuildEnabled,
    identityReady: sparkDistributionReady,
    providerConfigured: sparkProviderConfigured,
  );
  if (!betaCanAuthenticate && !sparkCanAuthenticate) {
    throw StateError('O início de sessão Apple não está configurado.');
  }

  final provider = AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');
  return authenticate(provider);
}

bool isAppleSignInCancellation(Object error) =>
    error is FirebaseAuthException && error.code.toLowerCase() == 'canceled';
