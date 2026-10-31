import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, appFlavor;
import '../auth/google_sign_in_configuration.dart';
import 'spark_local_environment.dart';

/// Explicit identity for the separately provisioned Android Beta application.
/// It never reads the production google-services.json or production OAuth ID.
class BetaEnvironment {
  static const enabled = appFlavor == 'beta' || SparkLocalEnvironment.enabled;
  static const sparkLocal = SparkLocalEnvironment.enabled;
  static const firebaseEnabled = bool.fromEnvironment('BETA_FIREBASE_ENABLED');
  static const appCheckEnabled = bool.fromEnvironment('BETA_APP_CHECK_ENABLED');
  static const expectedProjectId = sparkLocal
      ? SparkLocalEnvironment.project
      : String.fromEnvironment('BETA_FIREBASE_PROJECT_ID');
  static const applicationId = 'br.com.tudoaquimacacu.tudo_aqui_macacu.beta';

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
    required String googleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
  }) {
    if (flavor != 'beta') return 'invalid_flavor';
    if (!android) return 'unsupported_platform';
    if (localSearchEnabled) return 'local_search_enabled';
    if (applicationId != BetaEnvironment.applicationId) {
      return 'application_id_mismatch';
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
        ) !=
        null) {
      return 'firebase_app_identity_invalid';
    }
    return null;
  }

  static String? _configurationMessage(String code) => switch (code) {
    'invalid_flavor' => 'Variante Beta inválida.',
    'unsupported_platform' =>
      'A variante Beta está preparada somente para Android.',
    'local_search_enabled' => 'Beta e busca local não podem coexistir.',
    'application_id_mismatch' => 'Identificador Android Beta inválido.',
    'firebase_or_app_check_disabled' =>
      'A configuração Firebase e App Check do Beta está incompleta.',
    'firebase_project_not_isolated' =>
      'O Beta exige um projeto Firebase isolado com nome exclusivo de Beta.',
    'native_project_mismatch' =>
      'O projeto declarado pelo Android não corresponde ao Beta.',
    'oauth_web_client_invalid' =>
      'O cliente OAuth Google exclusivo do Beta está ausente ou inválido.',
    'firebase_app_identity_invalid' =>
      'A identidade Android do Firebase Beta está inválida.',
    _ => 'A configuração do Beta não pôde ser validada.',
  };

  static String? validateCompiledConfiguration({
    required String nativeExpectedProjectId,
    required String applicationId,
    required String nativeGoogleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
    required bool android,
  }) => validateConfiguration(
    flavor: appFlavor ?? '',
    expectedProjectId: expectedProjectId,
    nativeExpectedProjectId: nativeExpectedProjectId,
    applicationId: applicationId,
    firebaseEnabled: firebaseEnabled,
    appCheckEnabled: appCheckEnabled,
    localSearchEnabled: const bool.fromEnvironment('LOCAL_SEARCH_EMULATORS'),
    android: android,
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
  }) => validateConfigurationFailureCode(
    flavor: appFlavor ?? '',
    expectedProjectId: expectedProjectId,
    nativeExpectedProjectId: nativeExpectedProjectId,
    applicationId: applicationId,
    firebaseEnabled: firebaseEnabled,
    appCheckEnabled: appCheckEnabled,
    localSearchEnabled: const bool.fromEnvironment('LOCAL_SEARCH_EMULATORS'),
    android: android,
    googleWebClientId: nativeGoogleWebClientId,
    nativeFirebaseAppId: nativeFirebaseAppId,
    nativeMessagingSenderId: nativeMessagingSenderId,
  );

  static String? validateFirebaseAppIdentity({
    required String appId,
    required String messagingSenderId,
  }) {
    final senderId = messagingSenderId.trim();
    if (!RegExp(r'^\d{8,15}$').hasMatch(senderId) ||
        !RegExp(
          '^1:${RegExp.escape(senderId)}:android:[A-Za-z0-9_-]{8,}\$',
        ).hasMatch(appId.trim())) {
      return 'A identidade Android do Firebase Beta está inválida.';
    }
    return null;
  }

  static String? validateFirebaseIdentity({
    required String expectedProjectId,
    required String actualProjectId,
    required String appId,
    required String messagingSenderId,
  }) {
    if (actualProjectId != expectedProjectId ||
        !isIsolatedFirebaseProject(actualProjectId)) {
      return 'A identidade Firebase do Beta diverge do projeto autorizado.';
    }
    return validateFirebaseAppIdentity(
      appId: appId,
      messagingSenderId: messagingSenderId,
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
    required String nativeExpectedProjectId,
    required String applicationId,
    required String nativeGoogleWebClientId,
    required String nativeFirebaseAppId,
    required String nativeMessagingSenderId,
  }) {
    final reason = validateCompiledConfiguration(
      nativeExpectedProjectId: nativeExpectedProjectId,
      applicationId: applicationId,
      nativeGoogleWebClientId: nativeGoogleWebClientId,
      nativeFirebaseAppId: nativeFirebaseAppId,
      nativeMessagingSenderId: nativeMessagingSenderId,
      android: defaultTargetPlatform == TargetPlatform.android,
    );
    final firebaseReason = validateFirebaseIdentity(
      expectedProjectId: expectedProjectId,
      actualProjectId: actualProjectId,
      appId: actualAppId,
      messagingSenderId: actualMessagingSenderId,
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
}
