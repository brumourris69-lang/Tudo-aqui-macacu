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

class AppCheckSetup {
  static const enabled = bool.fromEnvironment('LOCAL_SEARCH_APP_CHECK');
  static Future<void> prepare() async {
    final mode = appCheckMode(
      enabled: enabled,
      emulator: LocalSearchEnvironment.enabled,
      debug: kDebugMode,
    );
    if (mode == AppCheckMode.disabled) return;
    // Stage 4E does not activate providers on the real app/project.
    if (!LocalSearchEnvironment.enabled) {
      throw StateError('App Check de produção ainda não autorizado.');
    }
    if (mode == AppCheckMode.emulator) {
      // No App Check Emulator exists. Do not exchange debug tokens against
      // production. Local callable transport tests use an emulator-only fixture.
      return;
    }
    await FirebaseAppCheck.instance.activate(
      androidProvider: mode == AppCheckMode.debugProvider
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: mode == AppCheckMode.debugProvider
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
  }
}
