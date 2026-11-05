import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, appFlavor;
import '../auth/google_sign_in_configuration.dart';
import 'spark_local_environment.dart';

/// Explicit platform identity for the separately provisioned Beta application.
/// iOS values are separate build settings and never come from Android resources.
class BetaEnvironment {
  static const iosBuildEnabled = bool.fromEnvironment('BETA_IOS_ENABLED');
  // Build-time attestation is enabled only after the iOS Apple provider,
  // Firebase provider and native Sign in with Apple capability are configured.
  static const iosAppleSignInEnabled = bool.fromEnvironment(
    'BETA_IOS_APPLE_SIGN_IN_ENABLED',
  );
  static const enabled =
      appFlavor == 'beta' || iosBuildEnabled || SparkLocalEnvironment.enabled;
  static const sparkLocal = SparkLocalEnvironment.enabled;
  static const firebaseEnabled = bool.fromEnvironment('BETA_FIREBASE_ENABLED');
  static const appCheckEnabled = bool.fromEnvironment('BETA_APP_CHECK_ENABLED');
  static const expectedProjectId = sparkLocal
      ? SparkLocalEnvironment.project
      : String.fromEnvironment('BETA_FIREBASE_PROJECT_ID');
  static const applicationId = 'br.com.tudoaquimacacu.tudo_aqui_macacu.beta';
  static const iosExpectedProjectId = String.fromEnvironment(
    'BETA_IOS_FIREBASE_PROJECT_ID',
  );
  static const iosBundleIdentifier = String.fromEnvironment(
    'BETA_IOS_BUNDLE_ID',
  );
  static const iosFirebaseAppId = String.fromEnvironment(
    'BETA_IOS_FIREBASE_APP_ID',
  );
  static const iosMessagingSenderId = String.fromEnvironment(
    'BETA_IOS_MESSAGING_SENDER_ID',
  );
  static const iosGoogleWebClientId = String.fromEnvironment(
    'BETA_IOS_GOOGLE_WEB_CLIENT_ID',
  );
  static const iosGoogleClientId = String.fromEnvironment(
    'BETA_IOS_GOOGLE_CLIENT_ID',
  );

  static bool _ready = false;
  static bool get ready => _ready;
  static String _googleWebClientId = '';
  static String get googleWebClientId => _googleWebClientId;

  static bool isIsolatedFirebaseProject(String value) {
    final project = value.trim().toLowerCase();
    final forbiddenMarker = <String>[
      'tudo-aqui-macacu',
      'staging',
      'homolog',
      'production',
      'prod-',
      'demo-universal-search',
    ].any(project.contains);
    final dedicatedBetaId = RegExp(
      r'^macacu-beta-[0-9]{6}-[a-f0-9]{6}$',
    ).hasMatch(project);
    return !forbiddenMarker &&
        (dedicatedBetaId ||
            project.endsWith('-beta') ||
            project.endsWith('-testing')) &&
        RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(project);
  }

  static String? validateConfiguration({
    required String flavor,
    required String expectedProjectId,
    required String nativeExpectedProjectId,
    required String applicationId,
    required bool firebaseEnabled,
    required bool appCheckEnabled,
    required bool localSearchEnabled,
    required bool android,
    bool ios = false,
    String iosBundleIdentifier = '',
    String iosGoogleClientId = '',
    required String googleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
  }) {
    final code = validateConfigurationFailureCode(
      flavor: flavor,
      expectedProjectId: expectedProjectId,
      nativeExpectedProjectId: nativeExpectedProjectId,
      applicationId: applicationId,
      firebaseEnabled: firebaseEnabled,
      appCheckEnabled: appCheckEnabled,
      localSearchEnabled: localSearchEnabled,
      android: android,
      ios: ios,
      iosBundleIdentifier: iosBundleIdentifier,
      iosGoogleClientId: iosGoogleClientId,
      googleWebClientId: googleWebClientId,
      nativeFirebaseAppId: nativeFirebaseAppId,
      nativeMessagingSenderId: nativeMessagingSenderId,
    );
    if (code == null) return null;
    return _configurationMessage(code);
  }

  /// Returns a stable, non-sensitive diagnostic code for each configuration
  /// guard. Values such as project IDs and OAuth clients are never included.
  static String? validateConfigurationFailureCode({
    required String flavor,
    required String expectedProjectId,
    required String nativeExpectedProjectId,
    required String applicationId,
    required bool firebaseEnabled,
    required bool appCheckEnabled,
    required bool localSearchEnabled,
    required bool android,
    bool ios = false,
    String iosBundleIdentifier = '',
    String iosGoogleClientId = '',
    required String googleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
  }) {
    if (flavor != 'beta') return 'invalid_flavor';
    if (android == ios) return 'unsupported_platform';
    if (localSearchEnabled) return 'local_search_enabled';
    if (android && applicationId != BetaEnvironment.applicationId) {
      return 'application_id_mismatch';
    }
    if (ios &&
        (!isValidIosBundleIdentifier(iosBundleIdentifier) ||
            applicationId != iosBundleIdentifier.trim())) {
      return 'ios_bundle_identifier_invalid';
    }
    if (ios && !isValidGoogleClientId(iosGoogleClientId)) {
      return 'ios_oauth_client_invalid';
    }
    if (!firebaseEnabled || !appCheckEnabled) {
      return 'firebase_or_app_check_disabled';
    }

    final project = expectedProjectId.trim();
    if (!isIsolatedFirebaseProject(project)) {
      return 'firebase_project_not_isolated';
    }
    if (nativeExpectedProjectId.trim() != project) {
      return 'native_project_mismatch';
    }
    if (!RegExp(
          r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
        ).hasMatch(googleWebClientId.trim()) ||
        googleWebClientId.trim() == productionGoogleWebClientId) {
      return 'oauth_web_client_invalid';
    }
    if (validateFirebaseAppIdentity(
          appId: nativeFirebaseAppId,
          messagingSenderId: nativeMessagingSenderId,
          ios: ios,
        ) !=
        null) {
      return 'firebase_app_identity_invalid';
    }
    return null;
  }

  static String? _configurationMessage(String code) => switch (code) {
    'invalid_flavor' => 'Variante Beta inválida.',
    'unsupported_platform' =>
      'A variante Beta exige Android ou iOS com configuração específica válida.',
    'local_search_enabled' => 'Beta e busca local não podem coexistir.',
    'application_id_mismatch' => 'Identificador Android Beta inválido.',
    'ios_bundle_identifier_invalid' =>
      'O Bundle ID configurado não corresponde ao iOS Beta.',
    'ios_oauth_client_invalid' =>
      'O cliente OAuth iOS do Beta está ausente ou inválido.',
    'firebase_or_app_check_disabled' =>
      'A configuração Firebase e App Check do Beta está incompleta.',
    'firebase_project_not_isolated' =>
      'O Beta exige um projeto Firebase isolado com nome exclusivo de Beta.',
    'native_project_mismatch' =>
      'O projeto declarado pela plataforma não corresponde ao Beta.',
    'oauth_web_client_invalid' =>
      'O cliente OAuth Google exclusivo do Beta está ausente ou inválido.',
    'firebase_app_identity_invalid' =>
      'A identidade nativa do Firebase Beta está inválida.',
    _ => 'A configuração do Beta não pôde ser validada.',
  };

  static String? validateCompiledConfiguration({
    required String nativeExpectedProjectId,
    required String applicationId,
    required String nativeGoogleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
    required bool android,
    bool ios = false,
    String iosBundleIdentifier = '',
    String iosGoogleClientId = '',
  }) => validateConfiguration(
    flavor: appFlavor ?? (iosBuildEnabled ? 'beta' : ''),
    expectedProjectId: expectedProjectId,
    nativeExpectedProjectId: nativeExpectedProjectId,
    applicationId: applicationId,
    firebaseEnabled: firebaseEnabled,
    appCheckEnabled: appCheckEnabled,
    localSearchEnabled: const bool.fromEnvironment('LOCAL_SEARCH_EMULATORS'),
    android: android,
    ios: ios,
    iosBundleIdentifier: iosBundleIdentifier,
    iosGoogleClientId: iosGoogleClientId,
    googleWebClientId: nativeGoogleWebClientId,
    nativeFirebaseAppId: nativeFirebaseAppId,
    nativeMessagingSenderId: nativeMessagingSenderId,
  );

  static String? validateCompiledConfigurationFailureCode({
    required String nativeExpectedProjectId,
    required String applicationId,
    required String nativeGoogleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
    required bool android,
    bool ios = false,
    String iosBundleIdentifier = '',
    String iosGoogleClientId = '',
  }) => validateConfigurationFailureCode(
    flavor: appFlavor ?? (iosBuildEnabled ? 'beta' : ''),
    expectedProjectId: expectedProjectId,
    nativeExpectedProjectId: nativeExpectedProjectId,
    applicationId: applicationId,
    firebaseEnabled: firebaseEnabled,
    appCheckEnabled: appCheckEnabled,
    localSearchEnabled: const bool.fromEnvironment('LOCAL_SEARCH_EMULATORS'),
    android: android,
    ios: ios,
    iosBundleIdentifier: iosBundleIdentifier,
    iosGoogleClientId: iosGoogleClientId,
    googleWebClientId: nativeGoogleWebClientId,
    nativeFirebaseAppId: nativeFirebaseAppId,
    nativeMessagingSenderId: nativeMessagingSenderId,
  );

  static String? validateFirebaseAppIdentity({
    required String appId,
    required String messagingSenderId,
    bool ios = false,
  }) {
    final senderId = messagingSenderId.trim();
    if (!RegExp(r'^\d{8,15}$').hasMatch(senderId) ||
        !RegExp(
          '^1:${RegExp.escape(senderId)}:${ios ? 'ios' : 'android'}:[A-Za-z0-9_-]{8,}\$',
        ).hasMatch(appId.trim())) {
      return 'A identidade nativa do Firebase Beta está inválida.';
    }
    return null;
  }

  static String? validateFirebaseIdentity({
    required String expectedProjectId,
    required String actualProjectId,
    required String appId,
    required String messagingSenderId,
    bool ios = false,
    String? expectedAppId,
    String? expectedMessagingSenderId,
    String expectedBundleIdentifier = '',
    String actualBundleIdentifier = '',
    String expectedIosGoogleClientId = '',
    String actualIosGoogleClientId = '',
  }) {
    if (expectedAppId != null && appId.trim() != expectedAppId.trim()) {
      return 'A identidade Firebase carregada diverge da configuração da plataforma.';
    }
    if (expectedMessagingSenderId != null &&
        messagingSenderId.trim() != expectedMessagingSenderId.trim()) {
      return 'O sender ID Firebase carregado diverge da configuração da plataforma.';
    }
    if (ios &&
        (expectedBundleIdentifier.trim().isEmpty ||
            actualBundleIdentifier.trim() != expectedBundleIdentifier.trim())) {
      return 'O Bundle ID carregado diverge da configuração do Firebase iOS.';
    }
    if (ios &&
        (expectedIosGoogleClientId.trim().isEmpty ||
            actualIosGoogleClientId.trim() !=
                expectedIosGoogleClientId.trim())) {
      return 'O cliente OAuth carregado diverge da configuração do Firebase iOS.';
    }
    if (actualProjectId != expectedProjectId ||
        !isIsolatedFirebaseProject(actualProjectId)) {
      return 'A identidade Firebase do Beta diverge do projeto autorizado.';
    }
    return validateFirebaseAppIdentity(
      appId: appId,
      messagingSenderId: messagingSenderId,
      ios: ios,
    );
  }

  static void requireReady() {
    if (!_ready) {
      throw StateError('A configuração isolada do Beta não foi validada.');
    }
  }

  static void requireFirebaseProject(String projectId) {
    requireReady();
    if (projectId != expectedProjectId ||
        (sparkLocal && projectId != SparkLocalEnvironment.project)) {
      throw StateError('A sessão Firebase não pertence ao projeto Beta.');
    }
  }

  /// Marks readiness only after the native VPN and both local Firebase
  /// emulators have been configured. This path cannot initialize hosted SDKs.
  static void markSparkLocalReady({required String actualProjectId}) {
    SparkLocalEnvironment.requireDemo(actualProjectId);
    _googleWebClientId = '';
    _ready = true;
  }

  static void markReady({
    required String actualProjectId,
    required String actualAppId,
    required String actualMessagingSenderId,
    required String actualIosGoogleClientId,
    required String actualIosBundleIdentifier,
    required String nativeExpectedProjectId,
    required String applicationId,
    required String nativeGoogleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
    required bool android,
    bool ios = false,
    String iosBundleIdentifier = '',
    String iosGoogleClientId = '',
  }) {
    final reason = validateCompiledConfiguration(
      nativeExpectedProjectId: nativeExpectedProjectId,
      applicationId: applicationId,
      nativeGoogleWebClientId: nativeGoogleWebClientId,
      nativeFirebaseAppId: nativeFirebaseAppId,
      nativeMessagingSenderId: nativeMessagingSenderId,
      android: android,
      ios: ios,
      iosBundleIdentifier: iosBundleIdentifier,
      iosGoogleClientId: iosGoogleClientId,
    );
    final firebaseReason = validateFirebaseIdentity(
      expectedProjectId: expectedProjectId,
      actualProjectId: actualProjectId,
      appId: actualAppId,
      messagingSenderId: actualMessagingSenderId,
      ios: ios,
      expectedAppId: nativeFirebaseAppId,
      expectedMessagingSenderId: nativeMessagingSenderId,
      expectedBundleIdentifier: iosBundleIdentifier,
      actualBundleIdentifier: actualIosBundleIdentifier,
      expectedIosGoogleClientId: iosGoogleClientId,
      actualIosGoogleClientId: actualIosGoogleClientId,
    );
    if (reason != null || firebaseReason != null) {
      _ready = false;
      _googleWebClientId = '';
      throw StateError(reason ?? firebaseReason!);
    }
    _googleWebClientId = nativeGoogleWebClientId.trim();
    _ready = true;
  }

  static void resetAfterStartupFailure() {
    _ready = false;
    _googleWebClientId = '';
  }

  @visibleForTesting
  static void resetForTest() => resetAfterStartupFailure();

  @visibleForTesting
  static void markReadyForTest() => _ready = true;

  static Future<Map<String, dynamic>> readNativeIdentity() async {
    const channel = MethodChannel('macacu/local-isolation');
    final native = await channel.invokeMapMethod<String, dynamic>(
      'environment',
    );
    if (native == null) throw StateError('Identidade Android indisponível.');
    return native;
  }

  /// Compile-time iOS values are explicit and never inferred from Android
  /// resources. Startup compares these values with FirebaseOptions after the
  /// native GoogleService-Info.plist has initialized Firebase.
  static Map<String, dynamic> readIosBuildIdentity() => {
    'beta': iosBuildEnabled,
    'local': false,
    'expectedProject': iosExpectedProjectId,
    'bundleIdentifier': iosBundleIdentifier,
    'googleWebClientId': iosGoogleWebClientId,
    'firebaseAppId': iosFirebaseAppId,
    'messagingSenderId': iosMessagingSenderId,
    'iosGoogleClientId': iosGoogleClientId,
    'appleSignInEnabled': iosAppleSignInEnabled,
  };

  static bool isValidIosBundleIdentifier(String value) {
    final bundle = value.trim();
    return bundle.length <= 255 &&
        RegExp(
          r'^(?!com\.example(?:\.|$))[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){1,}$',
        ).hasMatch(bundle);
  }

  static bool isValidGoogleClientId(String value) => RegExp(
    r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
  ).hasMatch(value.trim());
}
