import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/content/secure_backend.dart';

const administrativeJobPrivateFields = <String>{
  'contact',
  'phone',
  'whatsapp',
  'link',
  'instagram',
  'maps',
  'mapsUrl',
  'additionalInfo',
};

const _publicTextLimits = <String, int>{
  'title': 140,
  'description': 3000,
  'category': 120,
  'location': 240,
  'address': 240,
};
const _publicFields = <String>{
  'title',
  'description',
  'category',
  'location',
  'address',
  'imageUrl',
  'artwork',
  'galleryUrls',
  'published',
  'active',
  'expiresAt',
};
const _privateLimits = <String, int>{
  'contact': 320,
  'phone': 64,
  'whatsapp': 2048,
  'link': 2048,
  'instagram': 2048,
  'maps': 2048,
  'mapsUrl': 2048,
  'additionalInfo': 3000,
};

typedef AdminJobCallableInvoker =
    Future<dynamic> Function(String function, Map<String, dynamic> data);

/// Only controlled codes/messages cross the repository boundary. SDK messages
/// and details may contain administrative data and are never retained.
class AdminJobException implements Exception {
  AdminJobException(
    this.code, {
    this.createReservationReleased = false,
    this.createPayloadConflict = false,
  });

  final String code;

  /// True only when a failed create is known not to have committed and the
  /// editor may safely reserve a different ID on the next attempt.
  final bool createReservationReleased;

  /// True when an earlier ambiguous create may have committed, but the
  /// existing record differs from the current editor payload.
  final bool createPayloadConflict;

  String get message => createPayloadConflict
      ? 'A tentativa anterior pode ter criado a vaga com outros dados. Confira a lista; o salvamento foi bloqueado para evitar duplicação.'
      : switch (code) {
          'invalid-argument' => 'Dados da vaga inválidos.',
          'unauthenticated' => 'Entre novamente para gerenciar vagas.',
          'permission-denied' => 'Autorização administrativa indisponível.',
          'not-found' => 'Vaga não encontrada.',
          'failed-precondition' =>
            'Recarregue a lista. A vaga requer verificação.',
          'aborted' =>
            'A vaga foi alterada. Recarregue antes de tentar novamente.',
          'unavailable' => 'Serviço de vagas indisponível. Tente novamente.',
          'invalid-response' =>
            'Não foi possível confirmar a resposta da vaga.',
          _ => 'Não foi possível concluir a operação da vaga.',
        };

  @override
  String toString() => message;
}

class AdminJobSummary {
  const AdminJobSummary({
    required this.id,
    required this.title,
    required this.published,
    required this.active,
  });

  final String id;
  final String title;
  final bool published;
  final bool active;
}

class AdminJobPage {
  AdminJobPage({required List<AdminJobSummary> items, this.nextCursor})
    : items = List.unmodifiable(items);

  final List<AdminJobSummary> items;
  final String? nextCursor;
}

class AdminJobRecord {
  AdminJobRecord({
    required this.jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) : publicData = Map.unmodifiable(
         _publicPayload(publicData, 'invalid-response'),
       ),
       privateData = Map.unmodifiable(
         _privatePayload(privateData, 'invalid-response'),
       );

  final String jobId;
  final Map<String, dynamic> publicData;
  final Map<String, dynamic> privateData;
}

abstract interface class AdminJobRepository {
  Future<AdminJobPage> list({int pageSize = 30, String? cursor});
  Future<AdminJobRecord> get(String jobId);

  /// Locally reserves a stable ID before the first create attempt. Ambiguous
  /// results keep it reserved; only confirmed completion or a definitive
  /// no-write result allows another ID to be reserved.
  String reserveCreateId();

  Future<String> create({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  });
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  });
  Future<void> delete(String jobId);
}

/// All administrative job persistence uses the gated callable transport.
/// An injected invoker supports offline tests without Firebase initialization.
class CallableAdminJobRepository implements AdminJobRepository {
  CallableAdminJobRepository({AdminJobCallableInvoker? invoke})
    : _invoke = invoke ?? SecureBackend.invoke;

  final AdminJobCallableInvoker _invoke;
  String? _pendingCreateId;
  bool _pendingCreateMayHaveCommitted = false;

  @override
  String reserveCreateId() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return _pendingCreateId ??= (() {
      final random = Random.secure();
      return List.generate(
        20,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    })();
  }

  Future<dynamic> _call(Map<String, dynamic> data) async {
    try {
      return await _invoke('manageAdminJob', data);
    } on FirebaseFunctionsException catch (error) {
      final code = switch (error.code) {
        'invalid-argument' ||
        'unauthenticated' ||
        'permission-denied' ||
        'not-found' ||
        'failed-precondition' ||
        'aborted' ||
        'unavailable' => error.code,
        'deadline-exceeded' => 'unavailable',
        _ => 'internal',
      };
      throw AdminJobException(code);
    } on StateError {
      throw AdminJobException('unavailable');
    } on ArgumentError {
      throw AdminJobException('unavailable');
    } catch (_) {
      throw AdminJobException('internal');
    }
  }

  @override
  Future<AdminJobPage> list({int pageSize = 30, String? cursor}) async {
    if (pageSize < 1 ||
        pageSize > 40 ||
        (cursor != null && !_validCursor(cursor))) {
      throw AdminJobException('invalid-argument');
    }
    final response = _object(
      await _call({
        'operation': 'list',
        'pageSize': pageSize,
        'cursor': ?cursor,
      }),
      {'status', 'items', 'nextCursor'},
      'invalid-response',
      complete: true,
    );
    final rawItems = response['items'];
    final nextCursor = response['nextCursor'];
    if (response['status'] != 'available' ||
        rawItems is! List ||
        rawItems.length > pageSize ||
        (nextCursor != null &&
            (nextCursor is! String ||
                !_validCursor(nextCursor) ||
                nextCursor == cursor))) {
      throw AdminJobException('invalid-response');
    }
    final ids = <String>{};
    final items = rawItems.map((raw) {
      final item = _object(
        raw,
        {'id', 'summary'},
        'invalid-response',
        complete: true,
      );
      final id = item['id'];
      final summary = _object(
        item['summary'],
        {'title', 'published', 'active'},
        'invalid-response',
        complete: true,
      );
      if (!_validId(id) ||
          !ids.add(id as String) ||
          summary['title'] is! String ||
          summary['published'] is! bool ||
          summary['active'] is! bool) {
        throw AdminJobException('invalid-response');
      }
      return AdminJobSummary(
        id: id,
        title: summary['title'] as String,
        published: summary['published'] as bool,
        active: summary['active'] as bool,
      );
    }).toList();
    if (items.isEmpty && nextCursor != null) {
      throw AdminJobException('invalid-response');
    }
    return AdminJobPage(items: items, nextCursor: nextCursor as String?);
  }

  @override
  Future<AdminJobRecord> get(String jobId) async {
    _requireId(jobId);
    final response = _object(
      await _call({'operation': 'get', 'jobId': jobId}),
      {'status', 'jobId', 'publicData', 'privateData'},
      'invalid-response',
      complete: true,
    );
    if (response['status'] != 'available' || response['jobId'] != jobId) {
      throw AdminJobException('invalid-response');
    }
    final public = _object(
      response['publicData'],
      _publicFields,
      'invalid-response',
      complete: true,
    );
    final private = _object(
      response['privateData'],
      administrativeJobPrivateFields,
      'invalid-response',
      complete: true,
    );
    return AdminJobRecord(
      jobId: jobId,
      publicData: public,
      privateData: private,
    );
  }

  @override
  Future<String> create({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    _requireId(jobId);
    _pendingCreateId ??= jobId;
    if (_pendingCreateId != jobId) throw AdminJobException('invalid-argument');
    try {
      await _write('create', 'created', jobId, publicData, privateData);
    } on AdminJobException catch (error) {
      if (error.code == 'failed-precondition') {
        // A previous request may have committed even though its response was
        // lost. Re-read through the same callable before treating the ID as a
        // collision, and report success only when both payloads match exactly.
        late final AdminJobRecord existing;
        try {
          existing = await get(jobId);
        } on AdminJobException catch (readError) {
          if (readError.code == 'not-found') {
            _pendingCreateId = null;
            _pendingCreateMayHaveCommitted = false;
            throw AdminJobException(
              error.code,
              createReservationReleased: true,
            );
          }
          if (readError.code == 'failed-precondition') {
            if (_pendingCreateMayHaveCommitted) {
              // The public document exists but the private half is missing.
              // After an ambiguous create this may be a committed pair whose
              // private document changed later, so never reuse this ID.
              throw AdminJobException(
                error.code,
                createPayloadConflict: true,
              );
            }
            _pendingCreateId = null;
            _pendingCreateMayHaveCommitted = false;
            throw AdminJobException(
              error.code,
              createReservationReleased: true,
            );
          }
          // If the read itself is unavailable or authorization changed, keep
          // the ID reserved: the original create may have committed.
          rethrow;
        }
        if (_sameCreatePayload(existing, publicData, privateData)) {
          _pendingCreateId = null;
          _pendingCreateMayHaveCommitted = false;
          return jobId;
        }
        if (_pendingCreateMayHaveCommitted) {
          throw AdminJobException(error.code, createPayloadConflict: true);
        }
        _pendingCreateId = null;
        _pendingCreateMayHaveCommitted = false;
        throw AdminJobException(error.code, createReservationReleased: true);
      }
      if (const {
        'invalid-argument',
        'unauthenticated',
        'permission-denied',
        'not-found',
        'aborted',
      }.contains(error.code)) {
        if (!_pendingCreateMayHaveCommitted) {
          _pendingCreateId = null;
          _pendingCreateMayHaveCommitted = false;
          throw AdminJobException(error.code, createReservationReleased: true);
        }
      }
      // Network and malformed-acknowledgement failures can be ambiguous.
      if (const {
        'unavailable',
        'internal',
        'invalid-response',
      }.contains(error.code)) {
        _pendingCreateMayHaveCommitted = true;
      }
      rethrow;
    }
    _pendingCreateId = null;
    _pendingCreateMayHaveCommitted = false;
    return jobId;
  }

  @override
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    _requireId(jobId);
    await _write('update', 'updated', jobId, publicData, privateData);
  }

  Future<void> _write(
    String operation,
    String status,
    String jobId,
    Map<String, dynamic> publicData,
    Map<String, dynamic> privateData,
  ) async {
    final public = _publicPayload(publicData, 'invalid-argument');
    final private = _privatePayload(privateData, 'invalid-argument');
    _acknowledge(
      await _call({
        'operation': operation,
        'jobId': jobId,
        'publicData': public,
        'privateData': private,
      }),
      status,
      jobId,
    );
  }

  @override
  Future<void> delete(String jobId) async {
    _requireId(jobId);
    _acknowledge(
      await _call({'operation': 'delete', 'jobId': jobId}),
      'deleted',
      jobId,
    );
  }
}

bool _sameCreatePayload(
  AdminJobRecord existing,
  Map<String, dynamic> publicData,
  Map<String, dynamic> privateData,
) {
  final expectedPublic = <String, dynamic>{
    'title': '',
    'description': '',
    'imageUrl': '',
    'artwork': 0,
    'galleryUrls': const <String>[],
    'category': '',
    'location': '',
    'address': '',
    'published': false,
    'active': false,
    'expiresAt': null,
    ..._publicPayload(publicData, 'invalid-argument'),
  };
  final expectedPrivate = <String, dynamic>{
    for (final field in administrativeJobPrivateFields)
      field: privateData[field] ?? '',
  };
  return _sameJobValues(existing.publicData, expectedPublic) &&
      _sameJobValues(existing.privateData, expectedPrivate);
}

bool _sameJobValues(
  Map<String, dynamic> actual,
  Map<String, dynamic> expected,
) {
  if (actual.length != expected.length ||
      !actual.keys.every(expected.containsKey)) {
    return false;
  }
  for (final entry in expected.entries) {
    final value = actual[entry.key];
    final expectedValue = entry.value;
    if (value is List && expectedValue is List) {
      if (value.length != expectedValue.length) return false;
      for (var index = 0; index < value.length; index++) {
        if (value[index] != expectedValue[index]) return false;
      }
    } else if (value != expectedValue) {
      return false;
    }
  }
  return true;
}

void _acknowledge(dynamic value, String status, String jobId) {
  final response = _object(
    value,
    {'status', 'jobId'},
    'invalid-response',
    complete: true,
  );
  if (response['status'] != status || response['jobId'] != jobId) {
    throw AdminJobException('invalid-response');
  }
}

bool _validId(dynamic id) =>
    id is String &&
    id.trim().isNotEmpty &&
    id.length <= 128 &&
    !RegExp(r'[/\x00-\x1f\x7f]').hasMatch(id) &&
    id != '.' &&
    id != '..' &&
    !RegExp(r'^__.*__$').hasMatch(id);

void _requireId(String id) {
  if (!_validId(id)) throw AdminJobException('invalid-argument');
}

bool _validCursor(String value) =>
    value.length <= 1024 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

Map<String, dynamic> _object(
  dynamic value,
  Set<String> allowed,
  String code, {
  bool complete = false,
}) {
  if (value is! Map ||
      value.keys.any((key) => key is! String || !allowed.contains(key)) ||
      (complete && value.length != allowed.length)) {
    throw AdminJobException(code);
  }
  return Map<String, dynamic>.from(value);
}

/// Strict public allowlist. Private values and server-owned metadata cannot be
/// sent to the public document or admitted to administrative public DTOs.
Map<String, dynamic> publicJobPayload(Map<String, dynamic> data) =>
    _publicPayload(data, 'invalid-argument');

Map<String, dynamic> _publicPayload(Map<String, dynamic> data, String code) {
  final result = _object(data, _publicFields, code);
  for (final entry in result.entries.toList()) {
    final field = entry.key, value = entry.value;
    var valid = true;
    if (_publicTextLimits.containsKey(field)) {
      valid = value is String && value.length <= _publicTextLimits[field]!;
    } else {
      switch (field) {
        case 'imageUrl':
          valid = value == '' || _httpsUrl(value);
        case 'galleryUrls':
          valid = value is List && value.length <= 20 && value.every(_httpsUrl);
          if (valid) result[field] = List<String>.unmodifiable(value);
        case 'artwork':
          valid = value is int && value.abs() <= 9007199254740991;
        case 'published' || 'active':
          valid = value is bool;
        case 'expiresAt':
          if (value != null) {
            final expiration = _expiration(value);
            valid = expiration != null;
            if (valid) result[field] = expiration;
          }
      }
    }
    if (!valid) throw AdminJobException(code);
  }
  return result;
}

bool _httpsUrl(dynamic value) {
  if (value is! String || value.length > 2048 || value.trim() != value) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

String? _expiration(dynamic value) {
  DateTime? date;
  if (value is DateTime) {
    date = value;
  } else if (value is String) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d{1,3})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$',
    ).firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match[1]!),
        month = int.parse(match[2]!),
        day = int.parse(match[3]!);
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day) {
      return null;
    }
    date = DateTime.tryParse(value);
  }
  if (date == null || date.toUtc().year < 1 || date.toUtc().year > 9999) {
    return null;
  }
  // The callable accepts millisecond precision, matching server Date/Timestamp.
  return DateTime.fromMillisecondsSinceEpoch(
    date.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

Map<String, dynamic> _privatePayload(Map<String, dynamic> data, String code) {
  final result = _object(data, administrativeJobPrivateFields, code);
  for (final entry in result.entries) {
    if (entry.value is! String ||
        (entry.value as String).length > _privateLimits[entry.key]!) {
      throw AdminJobException(code);
    }
  }
  if (utf8.encode(jsonEncode(result)).length > 16 * 1024) {
    throw AdminJobException(code);
  }
  return result;
}
