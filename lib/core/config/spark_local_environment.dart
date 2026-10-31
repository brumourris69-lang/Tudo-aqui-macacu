import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Debug-only harness that runs the Spark Beta code path against local emulators.
/// It is a separate Android application ID and never reads Firebase options.
class SparkLocalEnvironment {
  static const enabled =
      appFlavor == 'sparkLocal' &&
      bool.fromEnvironment('SPARK_LOCAL_EMULATORS');
  static const project = 'demo-universal-search';
  static const host = '127.0.0.1';
  static const authPort = 9097;
  static const firestorePort = 8087;

  static void requireDemo(String? projectId) {
    if (!kDebugMode ||
        !enabled ||
        projectId != project ||
        appFlavor != 'sparkLocal') {
      throw StateError('Spark local exige a variante debug e o projeto demo.');
    }
  }

  static bool acceptsRuntime({
    required bool enabled,
    required bool nativeLocal,
    required bool nativeIsolated,
    required String host,
    required String projectId,
  }) =>
      enabled &&
      nativeLocal &&
      nativeIsolated &&
      host == SparkLocalEnvironment.host &&
      projectId == SparkLocalEnvironment.project;
}
