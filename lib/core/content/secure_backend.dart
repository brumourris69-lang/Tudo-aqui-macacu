import 'package:cloud_functions/cloud_functions.dart';
import '../config/local_search_environment.dart';
import '../../features/search/repositories/local_universal_search_repository.dart';

/// One contract, distinct transports. No legacy Firestore/network fallback.
/// Real activation requires a separate authorized App Check/deployment stage.
class SecureBackend {
  static bool get productionAuthorized => false;
  static Future<dynamic> invoke(
    String function,
    Map<String, dynamic> data,
  ) async {
    if (!const {
      'listPublicContent',
      'submitUserOperation',
    }.contains(function)) {
      throw ArgumentError('Operação de backend inválida.');
    }
    if (LocalSearchEnvironment.enabled) {
      return LocalUniversalSearchRepository.invokeLocal(function, data);
    }
    if (!productionAuthorized) {
      throw StateError('Backend seguro aguardando configuração e autorização.');
    }
    return (await FirebaseFunctions.instanceFor(
      region: 'southamerica-east1',
    ).httpsCallable(function).call<dynamic>(data)).data;
  }
}
