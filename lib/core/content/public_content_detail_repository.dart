import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/local_search_environment.dart';
import '../config/staging_environment.dart';
import '../config/beta_environment.dart';
import 'beta_public_catalog.dart';
import 'secure_backend.dart';

typedef PublicContentDetailInvoker =
    Future<dynamic> Function(String operation, Map<String, dynamic> data);

/// Loads one public, allowlisted document. Spark Beta reads its curated
/// Firestore projection; other enabled environments use their secured backend.
/// There is deliberately no unauthenticated direct-read fallback.
class PublicContentDetailRepository {
  PublicContentDetailRepository({PublicContentDetailInvoker? invoke})
    : _invoke = invoke ?? SecureBackend.invoke;

  static const _supportedCollections = {
    'establishments',
    'routes',
    'utilities',
    'jobs',
    'events',
  };

  final PublicContentDetailInvoker _invoke;

  Future<Map<String, dynamic>?> resolve({
    required String collection,
    required String id,
  }) async {
    if (!_supportedCollections.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw const FormatException('Conteúdo inválido.');
    }
    if (StagingEnvironment.enabled && LocalSearchEnvironment.enabled) {
      throw StateError('Ambientes de homologação e demo não podem coexistir.');
    }
    if (StagingEnvironment.enabled) StagingEnvironment.requireReady();
    if (BetaEnvironment.enabled) BetaEnvironment.requireReady();
    if (BetaEnvironment.enabled) {
      final database = FirebaseFirestore.instance;
      BetaEnvironment.requireFirebaseProject(database.app.options.projectId);
      return BetaPublicCatalog(database).get(collection: collection, id: id);
    }
    if (!LocalSearchEnvironment.enabled &&
        !StagingEnvironment.enabled &&
        !BetaEnvironment.enabled &&
        !SecureBackend.productionAuthorized &&
        !SecureBackend.normalDebugAuthorized) {
      throw StateError('Backend seguro aguardando configuração e autorização.');
    }

    final response = await _invoke('getPublicContentDetail', {
      'collection': collection,
      'id': id,
    });
    if (response is! Map) {
      throw const FormatException('Resposta pública inválida.');
    }
    if (response['status'] == 'unavailable' && response.length == 1) {
      return null;
    }
    if (response['status'] != 'available' ||
        response.length != 3 ||
        response['id'] != id ||
        response['data'] is! Map) {
      throw const FormatException('Resposta pública inválida.');
    }
    final data = response['data'] as Map;
    if (data.keys.any((key) => key is! String)) {
      throw const FormatException('Documento público inválido.');
    }
    return Map<String, dynamic>.from(data);
  }
}
