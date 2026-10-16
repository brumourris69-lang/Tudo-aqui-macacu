import '../config/local_search_environment.dart';
import 'secure_backend.dart';

typedef PublicContentDetailInvoker =
    Future<dynamic> Function(String operation, Map<String, dynamic> data);

/// Loads one public, allowlisted document through the secure backend only.
/// There is deliberately no direct Firestore fallback for public details.
class PublicContentDetailRepository {
  PublicContentDetailRepository({PublicContentDetailInvoker? invoke})
    : _invoke = invoke ?? SecureBackend.invoke;

  static const _supportedCollections = {
    'establishments',
    'routes',
    'utilities',
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
    if (!LocalSearchEnvironment.enabled &&
        !SecureBackend.productionAuthorized) {
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
