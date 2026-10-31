import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BetaStartupStage {
  environment,
  nativeIdentity,
  configuration,
  firebaseInitialization,
  firebaseIdentity,
  appCheck,
  authentication,
  adminAuthorization,
  unknown,
}

extension BetaStartupStageLabel on BetaStartupStage {
  String get label => switch (this) {
    BetaStartupStage.environment => 'environment',
    BetaStartupStage.nativeIdentity => 'native_identity',
    BetaStartupStage.configuration => 'configuration',
    BetaStartupStage.firebaseInitialization => 'firebase_initialization',
    BetaStartupStage.firebaseIdentity => 'firebase_identity',
    BetaStartupStage.appCheck => 'app_check',
    BetaStartupStage.authentication => 'authentication',
    BetaStartupStage.adminAuthorization => 'admin_authorization',
    BetaStartupStage.unknown => 'unknown',
  };
}

/// Sanitized startup failure that keeps the underlying cause out of UI/logs.
class BetaStartupDiagnosticException extends StateError {
  BetaStartupDiagnosticException(this.stage, this.code)
    : super(betaStartupFailureMessage(code));

  final BetaStartupStage stage;
  final String code;
}

String betaStartupFailureCode(BetaStartupStage stage, Object error) {
  if (error is BetaStartupDiagnosticException) return error.code;
  if (stage == BetaStartupStage.appCheck) {
    final details = switch (error) {
      PlatformException(:final code, :final message) => '$code $message',
      FirebaseException(:final code, :final message) => '$code $message',
      StateError(:final message) => message.toString(),
      _ => '',
    }.toLowerCase();
    if (details.contains('not registered') ||
        details.contains('register this app') ||
        details.contains('unregistered')) {
      return 'app_check_not_registered';
    }
    if (details.contains('attest') ||
        details.contains('play integrity') ||
        details.contains('integrity token')) {
      return 'app_check_attestation_failed';
    }
    return 'app_check_initialization_failed';
  }

  return switch (stage) {
    BetaStartupStage.environment => 'invalid_beta_environment',
    BetaStartupStage.nativeIdentity => 'native_identity_unavailable',
    BetaStartupStage.configuration => 'invalid_configuration',
    BetaStartupStage.firebaseInitialization => 'firebase_initialization_failed',
    BetaStartupStage.firebaseIdentity => 'firebase_identity_mismatch',
    BetaStartupStage.authentication when error is TimeoutException =>
      'authentication_timeout',
    BetaStartupStage.authentication when error is FirebaseAuthException =>
      _authenticationFailureCode(error.code),
    BetaStartupStage.authentication when error is FirebaseException =>
      'authentication_service_failed',
    BetaStartupStage.authentication when error is PlatformException =>
      'authentication_plugin_failed',
    BetaStartupStage.authentication => 'authentication_failed',
    BetaStartupStage.adminAuthorization => 'admin_authorization_failed',
    BetaStartupStage.unknown => 'unexpected_startup_failure',
    BetaStartupStage.appCheck => 'app_check_initialization_failed',
  };
}

String _authenticationFailureCode(String code) => switch (code) {
  'network-request-failed' => 'authentication_network_failed',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'authentication_credentials_rejected',
  'user-disabled' => 'authentication_account_disabled',
  _ => 'authentication_failed',
};

String betaStartupFailureMessage(String code) => switch (code) {
  'invalid_beta_environment' ||
  'invalid_configuration' ||
  'invalid_flavor' => 'A configuração isolada do Beta é inválida. ($code)',
  'unsupported_platform' =>
    'Esta versão Beta só pode iniciar no Android. ($code)',
  'local_search_enabled' =>
    'O modo local não pode ser combinado com o Beta. ($code)',
  'application_id_mismatch' =>
    'O pacote Android não corresponde ao aplicativo Beta. ($code)',
  'firebase_or_app_check_disabled' =>
    'As opções Firebase ou App Check do Beta estão ausentes. ($code)',
  'firebase_project_not_isolated' =>
    'O projeto Firebase configurado não atende ao padrão isolado de Beta. ($code)',
  'native_project_mismatch' =>
    'O projeto declarado pelo Android diverge do ID configurado no Beta. ($code)',
  'oauth_web_client_invalid' =>
    'O cliente OAuth Web do projeto Beta está ausente ou inválido. ($code)',
  'firebase_app_identity_invalid' =>
    'O app ID ou o número do projeto Firebase não corresponde ao Beta. ($code)',
  'native_identity_unavailable' =>
    'O Android não forneceu a identidade do Firebase Beta. ($code)',
  'firebase_initialization_failed' =>
    'O Firebase Beta não conseguiu inicializar. ($code)',
  'firebase_identity_mismatch' =>
    'A identidade carregada não corresponde ao projeto Beta autorizado. ($code)',
  'app_check_not_registered' =>
    'Este aplicativo ainda não está registrado no App Check do Beta. ($code)',
  'app_check_attestation_failed' =>
    'A atestação Play Integrity falhou; use uma instalação e um dispositivo compatíveis. ($code)',
  'app_check_initialization_failed' =>
    'O App Check do Beta não conseguiu inicializar. ($code)',
  'authentication_timeout' =>
    'O serviço de autenticação do Beta não respondeu a tempo. ($code)',
  'authentication_network_failed' =>
    'Não foi possível alcançar a autenticação do Beta. ($code)',
  'authentication_credentials_rejected' =>
    'A autenticação do Beta recusou as credenciais. ($code)',
  'authentication_account_disabled' =>
    'A conta de teste está desativada. ($code)',
  'authentication_plugin_failed' =>
    'O componente de autenticação do Android falhou. ($code)',
  'authentication_service_failed' ||
  'authentication_failed' => 'A autenticação do Beta falhou. ($code)',
  'admin_authorization_failed' =>
    'A verificação de autorização terminou com erro. ($code)',
  _ => 'A inicialização do Beta parou com segurança. ($code)',
};

/// Runs one bootstrap boundary and reports only stable, sanitized labels.
/// The default logger is debug-only. The original error is rethrown unchanged.
Future<T> runBetaStartupStep<T>(
  BetaStartupStage stage,
  Future<T> Function() action, {
  void Function(String message)? log,
  void Function(String code)? onFailure,
}) async {
  void emit(String message) {
    if (log != null) {
      log(message);
    } else if (kDebugMode) {
      debugPrint(message);
    }
  }

  emit('[BETA_STARTUP] stage=${stage.label} result=started');
  try {
    final result = await action();
    emit('[BETA_STARTUP] stage=${stage.label} result=ok');
    return result;
  } catch (error) {
    final code = betaStartupFailureCode(stage, error);
    onFailure?.call(code);
    emit('[BETA_STARTUP] stage=${stage.label} result=failed code=$code');
    rethrow;
  }
}
