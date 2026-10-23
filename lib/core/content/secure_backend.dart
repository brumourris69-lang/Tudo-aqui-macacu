import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../config/local_search_environment.dart';
import '../config/staging_environment.dart';
import '../../features/search/repositories/local_universal_search_repository.dart';

bool isNormalFirebaseDebugAuthorized({
  required bool debugBuild,
  required bool optIn,
  required bool localSearch,
  required bool staging,
  required String? projectId,
}) =>
    debugBuild &&
    optIn &&
    !localSearch &&
    !staging &&
    projectId == 'tudo-aqui-macacu';

/// One contract, distinct transports. No legacy Firestore/network fallback.
/// Real activation requires a separate authorized App Check/deployment stage.
class SecureBackend {
  static bool get productionAuthorized => false;
  static const normalDebugOptIn = bool.fromEnvironment(
    'NORMAL_FIREBASE_DEBUG_TEST',
  );
  static const normalDebugOperations = <String>{
    'listPublicContent',
    'getPublicContentDetail',
    'manageAdminJob',
  };
  static const localSecureOperations = <String>{
    'listPublicContent',
    'getPublicContentDetail',
    'submitUserOperation',
    'manageAdminJob',
  };
  static const productionOperations = <String>{
    'listPublicContent',
    'getPublicContentDetail',
    'submitUserOperation',
  };
  static const stagingOperations = <String>{
    'listPublicContent',
    'getPublicContentDetail',
    'getPublicJob',
  };

  @visibleForTesting
  static bool? stagingEnabledOverride;
  @visibleForTesting
  static Future<dynamic> Function(String, Map<String, dynamic>)?
  stagingInvokerOverride;
  @visibleForTesting
  static bool? normalDebugOptInOverride;
  @visibleForTesting
  static String? normalDebugProjectIdOverride;
  @visibleForTesting
  static Future<dynamic> Function(String, Map<String, dynamic>)?
  normalDebugInvokerOverride;

  static bool get _stagingEnabled =>
      stagingEnabledOverride ?? StagingEnvironment.enabled;

  static String? get _normalDebugProjectId {
    final override = normalDebugProjectIdOverride;
    if (override != null) return override;
    try {
      return Firebase.apps.isEmpty ? null : Firebase.app().options.projectId;
    } catch (_) {
      return null;
    }
  }

  static bool get normalDebugAuthorized => isNormalFirebaseDebugAuthorized(
    debugBuild: kDebugMode,
    optIn: normalDebugOptInOverride ?? normalDebugOptIn,
    localSearch: LocalSearchEnvironment.enabled,
    staging: _stagingEnabled,
    projectId: _normalDebugProjectId,
  );

  @visibleForTesting
  static bool isStagingOperationAllowed(String operation) =>
      stagingOperations.contains(operation);

  static Future<dynamic> invoke(
    String function,
    Map<String, dynamic> data,
  ) async {
    if (_stagingEnabled && LocalSearchEnvironment.enabled) {
      throw StateError('Ambientes de homologação e demo não podem coexistir.');
    }
    if (LocalSearchEnvironment.enabled) {
      if (!localSecureOperations.contains(function)) {
        throw ArgumentError('Operação de backend inválida.');
      }
      return LocalUniversalSearchRepository.invokeLocal(function, data);
    }
    if (_stagingEnabled) {
      if (!stagingOperations.contains(function)) {
        throw ArgumentError('Operação indisponível em homologação.');
      }
      StagingEnvironment.requireReady();
      final invoker = stagingInvokerOverride;
      if (invoker != null) return invoker(function, data);
      return (await FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable(function).call<dynamic>(data)).data;
    }
    if (normalDebugOperations.contains(function) && normalDebugAuthorized) {
      final invoker = normalDebugInvokerOverride;
      if (invoker != null) return invoker(function, data);
      return (await FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable(function).call<dynamic>(data)).data;
    }
    if (!productionOperations.contains(function)) {
      throw ArgumentError('Operação de backend inválida.');
    }
    if (!productionAuthorized) {
      throw StateError('Backend seguro aguardando configuração e autorização.');
    }
    return (await FirebaseFunctions.instanceFor(
      region: 'southamerica-east1',
    ).httpsCallable(function).call<dynamic>(data)).data;
  }
}
