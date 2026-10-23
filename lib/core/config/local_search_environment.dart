import 'package:flutter/foundation.dart';

/// Opt-in demo environment. Defaults keep the installed app unchanged.
class LocalSearchEnvironment {
  static const enabled = bool.fromEnvironment('LOCAL_SEARCH_EMULATORS');
  static const adminBridgePort = 5077;
  static const adminBridgePath = '/functions/v1/manage-establishments';
  static const authHttpDiagnosticsEnabled = bool.fromEnvironment(
    'LOCAL_AUTH_HTTP_DIAGNOSTICS',
    defaultValue: false,
  );
  static const project = String.fromEnvironment(
    'LOCAL_SEARCH_PROJECT',
    defaultValue: 'demo-universal-search',
  );
  // 10.0.2.2 is the Android Emulator's alias for this computer's loopback.
  static const host = String.fromEnvironment(
    'LOCAL_SEARCH_HOST',
    defaultValue: '10.0.2.2',
  );

  static int get authEmulatorPort => resolveLocalAuthEmulatorPort(
    diagnosticsEnabled: authHttpDiagnosticsEnabled,
    localSearchEnabled: enabled,
    debugBuild: kDebugMode,
    projectId: project,
    host: host,
  );

  static void requireDemo(String? actualProject) {
    if (!kDebugMode ||
        project != 'demo-universal-search' ||
        actualProject != project ||
        !['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
      throw StateError('Acesso local exige projeto demo e host do emulador.');
    }
  }
}

int resolveLocalAuthEmulatorPort({
  required bool diagnosticsEnabled,
  required bool localSearchEnabled,
  required bool debugBuild,
  required String projectId,
  required String host,
}) {
  if (!diagnosticsEnabled) return 9097;
  if (!localSearchEnabled ||
      !debugBuild ||
      projectId != 'demo-universal-search' ||
      host != '127.0.0.1') {
    throw StateError(
      'Diagnóstico HTTP do Auth exige searchLocal debug no projeto demo e loopback.',
    );
  }
  return 9197;
}
