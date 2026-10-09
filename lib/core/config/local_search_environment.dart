import 'package:flutter/foundation.dart';

/// Opt-in demo environment. Defaults keep the installed app unchanged.
class LocalSearchEnvironment {
  static const enabled = bool.fromEnvironment('LOCAL_SEARCH_EMULATORS');
  static const project = String.fromEnvironment(
    'LOCAL_SEARCH_PROJECT',
    defaultValue: 'demo-universal-search',
  );
  // 10.0.2.2 is the Android Emulator's alias for this computer's loopback.
  static const host = String.fromEnvironment(
    'LOCAL_SEARCH_HOST',
    defaultValue: '10.0.2.2',
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
