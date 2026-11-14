import 'package:flutter/foundation.dart' show visibleForTesting;

/// Explicit release identity for the public Spark distribution catalog.
/// The Firebase project and platform registrations must match these build-time
/// values; demo, Beta, local, and staging identities are rejected.
class SparkPublicCatalogEnvironment {
  static const enabled = bool.fromEnvironment('SPARK_DISTRIBUTION_ENABLED');
  static const candidateProjectId = 'tudo-aqui-macacu';
  static const projectId = String.fromEnvironment(
    'SPARK_DISTRIBUTION_FIREBASE_PROJECT_ID',
  );
  static const androidFirebaseAppId = String.fromEnvironment(
    'SPARK_DISTRIBUTION_ANDROID_FIREBASE_APP_ID',
  );
  static const iosFirebaseAppId = String.fromEnvironment(
    'SPARK_DISTRIBUTION_IOS_FIREBASE_APP_ID',
  );
  static const androidApplicationId = 'br.com.tudoaquimacacu.tudo_aqui_macacu';
  static const iosBundleIdentifier = 'br.com.tudoaquimacacu.tudoaquimacacu';

  static bool usesProjectionReads({required bool betaBuild}) =>
      betaBuild || enabled;

  static bool _ready = false;

  static bool acceptsBuildConfiguration({
    required bool enabled,
    required bool releaseBuild,
    required bool betaBuild,
    required bool localBuild,
    required bool stagingBuild,
    required String configuredProjectId,
    required bool android,
    required bool ios,
    required String configuredAndroidFirebaseAppId,
    required String configuredIosFirebaseAppId,
    required String configuredIosBundleIdentifier,
  }) {
    if (!enabled ||
        !releaseBuild ||
        betaBuild ||
        localBuild ||
        stagingBuild ||
        android == ios ||
        configuredProjectId != candidateProjectId) {
      return false;
    }
    if (android) {
      return _isValidFirebaseAppId(
        configuredAndroidFirebaseAppId,
        android: true,
      );
    }
    return configuredIosBundleIdentifier == iosBundleIdentifier &&
        _isValidFirebaseAppId(configuredIosFirebaseAppId, android: false);
  }

  static bool matchesRuntimeIdentity({
    required String configuredProjectId,
    required String actualProjectId,
    required String actualFirebaseAppId,
    required String configuredFirebaseAppId,
    required String expectedAndroidFirebaseAppId,
    required String expectedIosFirebaseAppId,
    required bool android,
    required bool ios,
    String actualIosBundleIdentifier = '',
  }) {
    if (android == ios ||
        configuredProjectId != candidateProjectId ||
        actualProjectId != configuredProjectId) {
      return false;
    }
    final expectedPlatformAppId = android
        ? expectedAndroidFirebaseAppId
        : expectedIosFirebaseAppId;
    return configuredFirebaseAppId.trim().isNotEmpty &&
        configuredFirebaseAppId == expectedPlatformAppId &&
        actualFirebaseAppId == configuredFirebaseAppId &&
        _isValidFirebaseAppId(configuredFirebaseAppId, android: android) &&
        (android || actualIosBundleIdentifier == iosBundleIdentifier);
  }

  static bool _isValidFirebaseAppId(String value, {required bool android}) =>
      RegExp(
        '^1:\\d{8,15}:${android ? 'android' : 'ios'}:[A-Za-z0-9_-]{8,}\$',
      ).hasMatch(value);

  static void requireBuildConfiguration({
    required bool android,
    required bool ios,
    required bool releaseBuild,
    required bool betaBuild,
    required bool localBuild,
    required bool stagingBuild,
  }) {
    if (!acceptsBuildConfiguration(
      enabled: enabled,
      releaseBuild: releaseBuild,
      betaBuild: betaBuild,
      localBuild: localBuild,
      stagingBuild: stagingBuild,
      configuredProjectId: projectId,
      android: android,
      ios: ios,
      configuredAndroidFirebaseAppId: androidFirebaseAppId,
      configuredIosFirebaseAppId: iosFirebaseAppId,
      configuredIosBundleIdentifier: iosBundleIdentifier,
    )) {
      throw StateError(
        'A identidade de distribuição Spark não foi configurada.',
      );
    }
  }

  static void markReady({
    required bool android,
    required bool ios,
    required String actualProjectId,
    required String actualFirebaseAppId,
    required String actualIosBundleIdentifier,
  }) {
    if (!enabled ||
        !matchesRuntimeIdentity(
          configuredProjectId: projectId,
          actualProjectId: actualProjectId,
          actualFirebaseAppId: actualFirebaseAppId,
          configuredFirebaseAppId: android
              ? androidFirebaseAppId
              : iosFirebaseAppId,
          expectedAndroidFirebaseAppId: androidFirebaseAppId,
          expectedIosFirebaseAppId: iosFirebaseAppId,
          android: android,
          ios: ios,
          actualIosBundleIdentifier: actualIosBundleIdentifier,
        )) {
      resetAfterStartupFailure();
      throw StateError('A identidade de distribuição Spark não foi validada.');
    }
    _ready = true;
  }

  static void requireReady({required String actualProjectId}) {
    if (!enabled ||
        !_ready ||
        projectId != candidateProjectId ||
        actualProjectId != projectId) {
      throw StateError('O catálogo público Spark não está autorizado.');
    }
  }

  static void resetAfterStartupFailure() => _ready = false;

  @visibleForTesting
  static void markReadyForTest() => _ready = true;

  @visibleForTesting
  static void resetForTest() => resetAfterStartupFailure();
}
