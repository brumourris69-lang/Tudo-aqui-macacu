import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _pilotProjectRef = 'zzxvcunuwbhglzzklsrl';
const _endpointPath = '/functions/v1/manage-establishments';
const _requestIdPattern =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
const _maxRequestBytes = 32 * 1024;
const _maxResponseBytes = 16 * 1024;

const _dataFields = <String>{
  'name',
  'title',
  'description',
  'shortDescription',
  'category',
  'subcategory',
  'location',
  'address',
  'active',
  'published',
  'featured',
  'imageUrl',
  'logoUrl',
  'artwork',
  'galleryUrls',
  'open',
  'hours',
  'services',
  'products',
  'additionalInfo',
  'promotionTitle',
  'promotionDescription',
  'link',
  'maps',
  'mapsUrl',
  'phone',
  'whatsapp',
  'instagram',
  'publicContactApproved',
  'expiresAt',
};
const _businessCategories = <String>{
  'Comércio',
  'Onde comer?',
  'Saúde',
  'Imóveis',
  'Veículos',
  'Pets',
  'Beleza',
  'Academias',
  'Educação',
  'Hospedagem',
  'Tecnologia',
  'Serviços',
  'Profissionais',
};

bool isHybridAdminEstablishmentCategory(String category) =>
    _businessCategories.contains(category);

/// A document carrying any catalog lifecycle marker must not be edited or
/// physically deleted through the legacy Firestore path. Missing/malformed
/// markers are treated conservatively once any marker is present.
bool establishmentRequiresHybridLifecycle(Map<String, Object?>? source) =>
    source != null &&
    (source['catalogVersion'] != null ||
        source['outboxOperationId'] != null ||
        source['deletedAt'] != null);

bool shouldBlockLegacyEstablishmentWrite({
  required bool isEstablishment,
  required bool hybridEnabled,
  required Map<String, Object?>? source,
}) =>
    isEstablishment &&
    !hybridEnabled &&
    establishmentRequiresHybridLifecycle(source);

/// Converts the existing editor's mixed Firestore payload into the
/// server-owned establishment contract. Unknown and editor-only fields are
/// omitted; timestamps are represented as ISO-8601 strings.
Map<String, Object?> hybridAdminPayloadFromEditor(
  Map<String, Object?> editorData,
) {
  final result = <String, Object?>{};
  for (final entry in editorData.entries) {
    if (!_dataFields.contains(entry.key)) continue;
    final value = entry.value;
    if (entry.key != 'expiresAt' || value == null || value is String) {
      result[entry.key] = value;
      continue;
    }
    if (value is Timestamp) {
      result[entry.key] = value.toDate().toUtc().toIso8601String();
    } else if (value is DateTime) {
      result[entry.key] = value.toUtc().toIso8601String();
    } else if (value is FieldValue) {
      result[entry.key] = null;
    } else {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
  }
  return result;
}

Future<HybridAdminResult> saveHybridEstablishment({
  required AdminEstablishmentsRepository repository,
  required String requestId,
  required int? expectedVersion,
  required bool? wasPublished,
  required Map<String, Object?> data,
  String? entityId,
}) {
  final outgoing = <String, Object?>{
    ...data,
    if (data['published'] == false) 'active': false,
  };
  if (entityId == null) {
    if (expectedVersion != null || wasPublished != null) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    return repository.create(requestId: requestId, data: outgoing);
  }
  if (!_validVersion(expectedVersion) || wasPublished == null) {
    throw const HybridAdminException(HybridAdminFailure.invalidRequest);
  }
  if (!wasPublished && outgoing['published'] == true) {
    return repository.republish(
      requestId: requestId,
      entityId: entityId,
      expectedVersion: expectedVersion!,
      data: outgoing,
    );
  }
  return repository.update(
    requestId: requestId,
    entityId: entityId,
    expectedVersion: expectedVersion!,
    data: outgoing,
  );
}

bool _validVersion(int? version) =>
    version != null && version >= 0 && version < 2147483647;

enum HybridAdminFailure {
  notConfigured,
  unauthenticated,
  invalidRequest,
  permissionDenied,
  conflict,
  unavailable,
  invalidResponse,
}

class HybridAdminException implements Exception {
  const HybridAdminException(this.failure);

  final HybridAdminFailure failure;

  @override
  String toString() => 'HybridAdminException(${failure.name})';
}

class HybridAdminResult {
  const HybridAdminResult({
    required this.entityId,
    required this.version,
    required this.replayed,
  });

  final String entityId;
  final int version;
  final bool replayed;
}

abstract interface class FirebaseIdTokenSource {
  bool get isAnonymous;

  Future<String?> getIdToken();
}

class CurrentFirebaseIdTokenSource implements FirebaseIdTokenSource {
  CurrentFirebaseIdTokenSource(this.auth);

  final FirebaseAuth auth;

  User? get _user => auth.currentUser;

  @override
  bool get isAnonymous => _user?.isAnonymous ?? true;

  @override
  Future<String?> getIdToken() async => _user?.getIdToken();
}

abstract interface class AdminEstablishmentsRepository {
  Future<HybridAdminResult> create({
    required String requestId,
    String? entityId,
    required Map<String, Object?> data,
  });

  Future<HybridAdminResult> update({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  });

  Future<HybridAdminResult> unpublish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  });

  Future<HybridAdminResult> republish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  });

  Future<HybridAdminResult> delete({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  });
}

/// Creates the debug-only adapter after an explicit compile-time opt-in.
/// Invalid opt-in configuration throws instead of falling back to Firestore.
class HybridAdminRuntime {
  const HybridAdminRuntime._();

  static final http.Client _sharedClient = http.Client();
  static AdminEstablishmentsRepository? _sharedRepository;

  static const enabled = bool.fromEnvironment(
    'HYBRID_ADMIN_ENABLED',
    defaultValue: false,
  );
  static const _endpoint = String.fromEnvironment('HYBRID_ADMIN_ENDPOINT');
  static const _anonKey = String.fromEnvironment('SUPABASE_PILOT_ANON_KEY');

  static AdminEstablishmentsRepository? createIfEnabled({
    FirebaseIdTokenSource? tokenSource,
    http.Client? client,
  }) {
    if (!enabled) return null;
    if (!kDebugMode) {
      throw const HybridAdminException(HybridAdminFailure.notConfigured);
    }
    if (tokenSource == null && client == null && _sharedRepository != null) {
      return _sharedRepository;
    }
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || !_isApprovedEndpoint(uri)) {
      throw const HybridAdminException(HybridAdminFailure.notConfigured);
    }
    final loopback = _isLoopback(uri.host);
    if (!loopback && !_isPublicAnonKey(_anonKey)) {
      throw const HybridAdminException(HybridAdminFailure.notConfigured);
    }
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: uri,
      apiKey: loopback ? null : _anonKey,
      tokenSource:
          tokenSource ?? CurrentFirebaseIdTokenSource(FirebaseAuth.instance),
      client: client ?? _sharedClient,
    );
    if (tokenSource == null && client == null) _sharedRepository = repository;
    return repository;
  }

  static bool _isApprovedEndpoint(Uri uri) {
    if (uri.path != _endpointPath ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && !_isLoopback(uri.host))) {
      return false;
    }
    if (uri.scheme == 'http') return _isLoopback(uri.host);
    return uri.scheme == 'https' && uri.host == '$_pilotProjectRef.supabase.co';
  }

  static bool _isLoopback(String host) =>
      host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';

  static bool _isPublicAnonKey(String key) {
    if (key.length < 12 || key.length > 4096 || key.contains(RegExp(r'\s'))) {
      return false;
    }
    if (key.startsWith('sb_secret_')) return false;
    if (key.startsWith('sb_publishable_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] != 'service_role';
    } on FormatException {
      return false;
    }
  }
}

class FirebaseSupabaseAdminEstablishmentsRepository
    implements AdminEstablishmentsRepository {
  FirebaseSupabaseAdminEstablishmentsRepository({
    required this.endpoint,
    required this.tokenSource,
    required this.client,
    this.apiKey,
    this.timeout = const Duration(seconds: 12),
  }) {
    final loopback = HybridAdminRuntime._isLoopback(endpoint.host);
    if (!HybridAdminRuntime._isApprovedEndpoint(endpoint) ||
        (loopback && apiKey != null) ||
        (!loopback && !HybridAdminRuntime._isPublicAnonKey(apiKey ?? ''))) {
      throw const HybridAdminException(HybridAdminFailure.notConfigured);
    }
  }

  final Uri endpoint;
  final String? apiKey;
  final FirebaseIdTokenSource tokenSource;
  final http.Client client;
  final Duration timeout;

  @override
  Future<HybridAdminResult> create({
    required String requestId,
    String? entityId,
    required Map<String, Object?> data,
  }) => _send({
    'operation': 'create',
    'requestId': requestId,
    ...?(entityId == null ? null : {'entityId': entityId}),
    'data': data,
  });

  @override
  Future<HybridAdminResult> update({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) => _send({
    'operation': 'update',
    'requestId': requestId,
    'entityId': entityId,
    'expectedVersion': expectedVersion,
    'data': data,
  });

  @override
  Future<HybridAdminResult> unpublish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) => _send({
    'operation': 'unpublish',
    'requestId': requestId,
    'entityId': entityId,
    'expectedVersion': expectedVersion,
  });

  @override
  Future<HybridAdminResult> republish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) => _send({
    'operation': 'republish',
    'requestId': requestId,
    'entityId': entityId,
    'expectedVersion': expectedVersion,
    'data': data,
  });

  @override
  Future<HybridAdminResult> delete({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) => _send({
    'operation': 'delete',
    'requestId': requestId,
    'entityId': entityId,
    'expectedVersion': expectedVersion,
  });

  Future<HybridAdminResult> _send(Map<String, Object?> body) async {
    _validateBody(body);
    late final String encoded;
    try {
      encoded = jsonEncode(body);
    } on Object {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    if (utf8.encode(encoded).length > _maxRequestBytes) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    if (tokenSource.isAnonymous) {
      throw const HybridAdminException(HybridAdminFailure.unauthenticated);
    }
    String? token;
    try {
      token = await tokenSource.getIdToken();
    } on Object {
      throw const HybridAdminException(HybridAdminFailure.unavailable);
    }
    if (token == null || token.isEmpty || token.length > 16 * 1024) {
      throw const HybridAdminException(HybridAdminFailure.unauthenticated);
    }
    final configuredApiKey = apiKey;
    final headers = <String, String>{
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
      'accept': 'application/json',
      ...?(configuredApiKey == null
          ? null
          : <String, String>{'apikey': configuredApiKey}),
    };
    http.Response response;
    try {
      response = await client
          .post(endpoint, headers: headers, body: encoded)
          .timeout(timeout);
    } on Object {
      throw const HybridAdminException(HybridAdminFailure.unavailable);
    }
    if (response.bodyBytes.length > _maxResponseBytes) {
      throw const HybridAdminException(HybridAdminFailure.invalidResponse);
    }
    final decoded = _decode(response.bodyBytes);
    if (decoded == null) {
      throw const HybridAdminException(HybridAdminFailure.invalidResponse);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final code = error is Map ? error['code'] : null;
      throw HybridAdminException(switch (code) {
        'unauthenticated' => HybridAdminFailure.unauthenticated,
        'permission_denied' => HybridAdminFailure.permissionDenied,
        'invalid_request' => HybridAdminFailure.invalidRequest,
        'conflict' => HybridAdminFailure.conflict,
        'backend_unavailable' => HybridAdminFailure.unavailable,
        _ => HybridAdminFailure.unavailable,
      });
    }
    final entityId = decoded['entityId'];
    final requestedEntityId = body['entityId'];
    final version = decoded['version'];
    final result = decoded['result'];
    final operation = body['operation'];
    final allowedResults = switch (operation) {
      'create' => const {'created', 'replayed'},
      'update' => const {'updated', 'replayed'},
      'unpublish' => const {'unpublished', 'replayed'},
      'republish' => const {'republished', 'replayed'},
      'delete' => const {'deleted', 'replayed'},
      _ => const <String>{},
    };
    if (entityId is! String ||
        !_validDocumentId(entityId) ||
        (requestedEntityId is String && entityId != requestedEntityId) ||
        version is! int ||
        version < 1 ||
        result is! String ||
        !allowedResults.contains(result)) {
      throw const HybridAdminException(HybridAdminFailure.invalidResponse);
    }
    return HybridAdminResult(
      entityId: entityId,
      version: version,
      replayed: decoded['replayed'] == true || result == 'replayed',
    );
  }

  void _validateBody(Map<String, Object?> body) {
    final requestId = body['requestId'];
    if (requestId is! String ||
        !RegExp(_requestIdPattern).hasMatch(requestId)) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    final operation = body['operation'];
    if (operation == 'create') {
      final entityId = body['entityId'];
      if (entityId != null &&
          (entityId is! String || !_validDocumentId(entityId))) {
        throw const HybridAdminException(HybridAdminFailure.invalidRequest);
      }
    } else {
      final entityId = body['entityId'];
      final version = body['expectedVersion'];
      if (entityId is! String ||
          !_validDocumentId(entityId) ||
          version is! int ||
          version < 0 ||
          version >= 2147483647) {
        throw const HybridAdminException(HybridAdminFailure.invalidRequest);
      }
    }
    if (!const {
      'create',
      'update',
      'unpublish',
      'republish',
      'delete',
    }.contains(operation)) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    final data = body['data'];
    if ((operation == 'create' || operation == 'update') &&
        data is! Map<String, Object?>) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    if (operation == 'republish' &&
        data != null &&
        data is! Map<String, Object?>) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    if ((operation == 'unpublish' || operation == 'delete') && data != null) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
    if (data is Map<String, Object?> &&
        (data.isEmpty || data.keys.any((key) => !_dataFields.contains(key)))) {
      throw const HybridAdminException(HybridAdminFailure.invalidRequest);
    }
  }

  Map<String, dynamic>? _decode(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  bool _validDocumentId(String value) {
    if (value.isEmpty ||
        value.contains('/') ||
        utf8.encode(value).length > 1500) {
      return false;
    }
    if (value == '.' || value == '..') return false;
    return !value.startsWith('__') ||
        !value.endsWith('__') ||
        RegExp(r'^__id\d+__$').hasMatch(value);
  }
}

String newHybridAdminRequestId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Keeps one idempotency key stable while an editor remains open after an
/// ambiguous transport result. A changed payload cannot silently replace it.
class HybridAdminRequestReservation {
  String? _requestId;
  String? _fingerprint;

  String reserve({
    required String? entityId,
    required int? expectedVersion,
    required Map<String, Object?> payload,
  }) {
    final fingerprint = jsonEncode({
      'entityId': entityId,
      'expectedVersion': expectedVersion,
      'payload': payload,
    });
    final current = _requestId;
    if (current != null) {
      if (_fingerprint != fingerprint) {
        throw const HybridAdminException(HybridAdminFailure.conflict);
      }
      return current;
    }
    final requestId = newHybridAdminRequestId();
    _fingerprint = fingerprint;
    _requestId = requestId;
    return requestId;
  }

  void clear(String requestId) {
    if (_requestId != requestId) return;
    _requestId = null;
    _fingerprint = null;
  }
}
