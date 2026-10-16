import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../config/local_search_environment.dart';
import '../config/staging_environment.dart';
import '../../features/search/repositories/local_universal_search_repository.dart';

/// One contract, distinct transports. No legacy Firestore/network fallback.
/// Real activation requires a separate authorized App Check/deployment stage.
class SecureBackend {
  static bool get productionAuthorized => false;
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

  static bool get _stagingEnabled =>
      stagingEnabledOverride ?? StagingEnvironment.enabled;

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
      if (!LocalUniversalSearchRepository.localOperations.contains(function)) {
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
