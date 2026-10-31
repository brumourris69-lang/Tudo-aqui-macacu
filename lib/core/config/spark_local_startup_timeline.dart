import 'package:flutter/foundation.dart';

import 'spark_local_environment.dart';

/// Development-only timing markers for the isolated SparkLocal startup path.
/// Values are fixed stage names and elapsed milliseconds; no user data,
/// credentials, project settings, or Firebase responses are logged.
class SparkLocalStartupTimeline {
  SparkLocalStartupTimeline._();

  static final Stopwatch _clock = Stopwatch()..start();
  static final Set<String> _seen = <String>{};

  static bool get _enabled => kDebugMode && SparkLocalEnvironment.enabled;

  static void mark(String stage) {
    if (!_enabled) return;
    debugPrint(
      'SPARK_STARTUP stage=$stage elapsed_ms=${_clock.elapsedMilliseconds}',
    );
  }

  static void markOnce(String stage) {
    if (_enabled && _seen.add(stage)) mark(stage);
  }
}
