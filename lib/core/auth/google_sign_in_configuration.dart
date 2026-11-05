import 'package:flutter/services.dart' show appFlavor;

const productionGoogleWebClientId =
    appFlavor == 'beta' || appFlavor == 'sparkLocal'
    ? ''
    : '801555679675-qvtghgv9sa65ipgls4usukru33uk3aec.apps.googleusercontent.com';

String googleSignInServerClientId({
  required bool betaVariant,
  required String betaClientId,
}) {
  if (!betaVariant) return productionGoogleWebClientId;
  final clientId = betaClientId.trim();
  if (!RegExp(
        r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
      ).hasMatch(clientId) ||
      clientId == productionGoogleWebClientId) {
    throw StateError('O cliente OAuth Google exclusivo do Beta está ausente.');
  }
  return clientId;
}

/// Uses the explicitly registered iOS OAuth client only for iOS Beta builds.
/// Other platforms keep their existing native client selection unchanged.
String? googleSignInNativeClientId({
  required bool betaVariant,
  required bool ios,
  required String betaIosClientId,
}) {
  if (!betaVariant || !ios) return null;
  final clientId = betaIosClientId.trim();
  if (!RegExp(
    r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
  ).hasMatch(clientId)) {
    throw StateError('O cliente OAuth iOS exclusivo do Beta está ausente.');
  }
  return clientId;
}
