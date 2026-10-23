/// Runs the local Firebase startup stages in a fail-closed order.
///
/// Keeping these operations injectable lets tests prove that no Firebase
/// request starts before network isolation, demo configuration, emulator
/// routing, and local App Check policy are established.
Future<void> runLocalFirebaseBootstrap({
  required Future<void> Function() establishNetworkIsolation,
  required Future<void> Function() initializeDemoProject,
  required Future<void> Function() configureAuthEmulator,
  required Future<void> Function() configureFirestoreSettings,
  required Future<void> Function() configureFirestoreEmulator,
  required Future<void> Function() configureFunctionsEmulators,
  required Future<void> Function() prepareLocalAppCheck,
  required Future<void> Function() validateLocalAuthSession,
  required Future<void> Function() validateLocalServices,
}) async {
  await establishNetworkIsolation();
  await initializeDemoProject();
  await configureAuthEmulator();
  await configureFirestoreSettings();
  await configureFirestoreEmulator();
  await configureFunctionsEmulators();
  await prepareLocalAppCheck();
  try {
    await validateLocalAuthSession();
  } catch (error) {
    throw LocalAuthBootstrapFailure(error);
  }
  await validateLocalServices();
}

bool isInvalidLocalAuthSessionCode(String code) => const {
  'invalid-refresh-token',
  'invalid-user-token',
  'user-token-expired',
}.contains(code.toLowerCase().replaceAll('_', '-'));

/// Existing automatic guest renewal policy retained for non-searchLocal modes.
bool shouldRenewLocalAnonymousSession({
  required String code,
  required bool isAnonymous,
}) =>
    isAnonymous &&
    (isInvalidLocalAuthSessionCode(code) || code.toLowerCase() == 'unknown');

bool shouldAutomaticallyRenewAnonymousSession({
  required bool searchLocalEnabled,
  required String code,
  required bool isAnonymous,
}) =>
    !searchLocalEnabled &&
    shouldRenewLocalAnonymousSession(code: code, isAnonymous: isAnonymous);

Future<T?> renewExpiredLocalVisitor<T>({
  required bool wasAnonymous,
  required Future<void> Function() signOut,
  required Future<T?> Function() signInAnonymously,
}) async {
  if (!wasAnonymous) throw const LocalSearchSessionExpired();
  await signOut();
  final user = await signInAnonymously();
  if (user == null) throw const LocalSearchSessionExpired();
  return user;
}

bool isLocalFirestoreConfiguration({
  required String? host,
  required bool? sslEnabled,
  required bool? persistenceEnabled,
  required String expectedHost,
}) => host == expectedHost && sslEnabled != true && persistenceEnabled == false;

class LocalSearchSessionExpired implements Exception {
  const LocalSearchSessionExpired();
}

class LocalAuthBootstrapFailure implements Exception {
  const LocalAuthBootstrapFailure(this.cause);
  final Object cause;
}

String localSearchStartupMessage(Object error) =>
    error is LocalSearchSessionExpired
    ? 'A sessão local expirou. É necessário autenticar novamente no ambiente de testes. Nenhum dado foi apagado.'
    : 'O ambiente local não conseguiu iniciar. Confira a VPN e os emuladores e tente novamente. Nenhum dado foi apagado.';
