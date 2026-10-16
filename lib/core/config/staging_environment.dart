import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, appFlavor;

/// Runtime guard for the separately provisioned Android staging project.
/// Staging is opt-in, debug-only and never derives identity from production.
class StagingEnvironment {
  static const enabled = appFlavor == 'staging';
  static const optIn = bool.fromEnvironment('STAGING_ENABLED');
  static const appCheckEnabled = bool.fromEnvironment(
    'STAGING_APP_CHECK_ENABLED',
  );
  static const expectedProjectId = String.fromEnvironment(
    'STAGING_FIREBASE_PROJECT_ID',
  );
  static const applicationId = 'br.com.tudoaquimacacu.tudo_aqui_macacu.staging';

  static bool _ready = false;

  /// Returns a safe failure reason, or null when all independently supplied
  /// identities agree. Kept pure so fail-closed cases are testable offline.
  static String? validateIdentity({
    required String flavor,
    required String expectedProjectId,
    required String actualProjectId,
    required String nativeExpectedProjectId,
    required String applicationId,
    required bool optIn,
    required bool debugBuild,
    required bool localSearchEnabled,
  }) {
    final expected = expectedProjectId.trim();
    if (flavor != 'staging') return 'Flavour de homologação inválido.';
    if (!debugBuild) return 'Homologação está disponível somente em debug.';
    if (!optIn) return 'Homologação exige habilitação explícita.';
    if (localSearchEnabled) return 'Ambientes de homologação e demo conflitam.';
    if (expected.isEmpty ||
        expected == 'tudo-aqui-macacu' ||
        expected == 'demo-universal-search' ||
        !(expected.endsWith('-staging') || expected.endsWith('-homologacao')) ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{4,62}[a-z0-9]$').hasMatch(expected)) {
      return 'Projeto de homologação ausente ou não permitido.';
    }
    if (actualProjectId != expected || nativeExpectedProjectId != expected) {
      return 'A configuração Firebase não corresponde ao projeto autorizado.';
    }
    if (applicationId != StagingEnvironment.applicationId) {
      return 'Identificador Android de homologação inválido.';
    }
    return null;
  }

  static void requireReady() {
    if (!_ready) {
      throw StateError('Ambiente de homologação não foi validado.');
    }
  }

  static void markReady({
    required String actualProjectId,
    required String nativeExpectedProjectId,
    required String applicationId,
  }) {
    final reason = validateIdentity(
      flavor: appFlavor ?? '',
      expectedProjectId: expectedProjectId,
      actualProjectId: actualProjectId,
      nativeExpectedProjectId: nativeExpectedProjectId,
      applicationId: applicationId,
      optIn: optIn,
      debugBuild: kDebugMode,
      localSearchEnabled: const bool.fromEnvironment('LOCAL_SEARCH_EMULATORS'),
    );
    if (reason != null) {
      _ready = false;
      throw StateError(reason);
    }
    _ready = true;
  }

  static void resetAfterStartupFailure() => _ready = false;

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
