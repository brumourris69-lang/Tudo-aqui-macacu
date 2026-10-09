import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import '../config/local_search_environment.dart';

enum AppCheckMode { disabled, emulator, debugProvider, attestation }

AppCheckMode appCheckMode({
  required bool enabled,
  required bool emulator,
  required bool debug,
}) => !enabled
    ? AppCheckMode.disabled
    : emulator
    ? AppCheckMode.emulator
    : debug
    ? AppCheckMode.debugProvider
    : AppCheckMode.attestation;

/// Provider configuration for a future authorized real-device validation.
/// Emulator mode never activates a provider or exchanges an App Check token.
class AppCheckProviderPlan {
  const AppCheckProviderPlan(this.mode);
  final AppCheckMode mode;
  bool get activatesProvider =>
      mode == AppCheckMode.debugProvider || mode == AppCheckMode.attestation;
  AndroidProvider get android => mode == AppCheckMode.debugProvider
      ? AndroidProvider.debug
      : AndroidProvider.playIntegrity;
  AppleProvider get apple => mode == AppCheckMode.debugProvider
      ? AppleProvider.debug
      : AppleProvider.appAttestWithDeviceCheckFallback;
}

/// Injectable orchestration; SDK calls in tests are fakes, not attestation.
Future<void> prepareAppCheckProviders({
  required AppCheckProviderPlan plan,
  required Future<void> Function(AppCheckProviderPlan) activate,
  required Future<void> Function(bool) setAutoRefresh,
  bool activationAuthorized = false,
}) async {
  if (!plan.activatesProvider) return;
  if (!activationAuthorized) {
    throw StateError('App Check de produção ainda não autorizado.');
  }
  try {
    await activate(plan);
    // SDK owns token caching/renewal. Do not force-refresh on every request.
    await setAutoRefresh(true);
  } catch (_) {
    // No fallback to a debug provider or unprotected backend after a failure.
    throw StateError(
      'Não foi possível validar este aplicativo. Verifique a conexão e tente novamente. '
      'Se persistir, use uma versão oficial em um dispositivo compatível.',
    );
  }
}

class AppCheckSetup {
  static const enabled = bool.fromEnvironment('LOCAL_SEARCH_APP_CHECK');
  static Future<void> prepare() async {
    final mode = appCheckMode(
      enabled: enabled,
      emulator: LocalSearchEnvironment.enabled,
      debug: kDebugMode,
    );
    await prepareAppCheckProviders(
      plan: AppCheckProviderPlan(mode),
      // Security 2D prepares the integration; no real activation is authorized.
      activationAuthorized: false,
      activate: (plan) => FirebaseAppCheck.instance.activate(
        androidProvider: plan.android,
        appleProvider: plan.apple,
      ),
      setAutoRefresh: (enabled) =>
          FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(enabled),
    );
  }
}
