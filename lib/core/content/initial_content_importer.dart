import 'dart:convert';

import 'hybrid_admin_establishments_repository.dart';

typedef ExistingEstablishmentLookup =
    Future<ExistingEstablishmentState> Function(String entityId);

enum ExistingEstablishmentState {
  absent,
  outboxManaged,
  legacy,
  tombstoned,
  inconsistent,
}

ExistingEstablishmentState classifyExistingEstablishment(
  Map<String, dynamic>? data,
) {
  if (data == null) return ExistingEstablishmentState.absent;
  if (data['deletedAt'] != null) return ExistingEstablishmentState.tombstoned;
  final version = data['catalogVersion'];
  final operationId = data['outboxOperationId'];
  if (version == null && operationId == null) {
    return ExistingEstablishmentState.legacy;
  }
  if (version is int &&
      version > 0 &&
      operationId is String &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(operationId)) {
    return ExistingEstablishmentState.outboxManaged;
  }
  return ExistingEstablishmentState.inconsistent;
}

class InitialContentImportItem {
  const InitialContentImportItem({
    required this.entityId,
    required this.category,
    required this.editorData,
  });

  final String entityId;
  final String category;
  final Map<String, Object?> editorData;
}

class InitialContentImportReport {
  const InitialContentImportReport({
    required this.created,
    required this.alreadyPresent,
    required this.tombstoned,
    required this.skippedOtherContent,
  });

  final int created;
  final int alreadyPresent;
  final int tombstoned;
  final int skippedOtherContent;
}

/// Contains only safe failure codes and counts; upstream exception text is
/// deliberately discarded so tokens, document data, or service details cannot
/// leak through UI messages or logs.
class InitialContentImportException implements Exception {
  const InitialContentImportException({
    required this.failure,
    required this.created,
    required this.alreadyPresent,
    required this.tombstoned,
    required this.skippedOtherContent,
  });

  final HybridAdminFailure failure;
  final int created;
  final int alreadyPresent;
  final int tombstoned;
  final int skippedOtherContent;

  @override
  String toString() => 'InitialContentImportException(${failure.name})';
}

/// Coordinates the existing debug opt-in importer. Each eligible item is
/// created through the trusted administrative endpoint, which atomically
/// writes the canonical document and outbox event. Existing IDs are never
/// updated or republished by this seed-only operation. Existing legacy or
/// partially versioned records are reported as conflicts, never successful imports.
class InitialContentImporterService {
  InitialContentImporterService({
    required AdminEstablishmentsRepository repository,
    required ExistingEstablishmentLookup lookupOnServer,
    String Function()? requestIdFactory,
  }) : _repository = repository,
       _lookupOnServer = lookupOnServer,
       _requestIdFactory =
           requestIdFactory ?? (() => newHybridAdminRequestId());

  final AdminEstablishmentsRepository _repository;
  final ExistingEstablishmentLookup _lookupOnServer;
  final String Function() _requestIdFactory;

  Future<InitialContentImportReport> import(
    Iterable<InitialContentImportItem> items, {
    required bool authorized,
  }) async {
    var alreadyPresent = 0;
    var tombstoned = 0;
    var skippedOtherContent = 0;
    var created = 0;
    if (!authorized) {
      throw const InitialContentImportException(
        failure: HybridAdminFailure.permissionDenied,
        created: 0,
        alreadyPresent: 0,
        tombstoned: 0,
        skippedOtherContent: 0,
      );
    }

    final prepared = <(String, Map<String, Object?>)>[];
    final seenIds = <String>{};
    try {
      for (final item in items) {
        if (!isHybridAdminEstablishmentCategory(item.category)) {
          skippedOtherContent++;
          continue;
        }
        if (!_validDocumentId(item.entityId) || !seenIds.add(item.entityId)) {
          throw const HybridAdminException(HybridAdminFailure.invalidRequest);
        }
        final payload = hybridAdminPayloadFromEditor(item.editorData);
        if (payload['category'] != item.category) {
          throw const HybridAdminException(HybridAdminFailure.invalidRequest);
        }
        prepared.add((item.entityId, payload));
      }
    } on Object catch (error) {
      throw InitialContentImportException(
        failure: _safeFailure(error),
        created: 0,
        alreadyPresent: 0,
        tombstoned: 0,
        skippedOtherContent: skippedOtherContent,
      );
    }

    for (final (entityId, payload) in prepared) {
      try {
        switch (await _lookupOnServer(entityId)) {
          case ExistingEstablishmentState.outboxManaged:
            alreadyPresent++;
            continue;
          case ExistingEstablishmentState.tombstoned:
            tombstoned++;
            continue;
          case ExistingEstablishmentState.legacy:
          case ExistingEstablishmentState.inconsistent:
            throw const HybridAdminException(HybridAdminFailure.conflict);
          case ExistingEstablishmentState.absent:
            break;
        }
        final result = await _repository.create(
          requestId: _requestIdFactory(),
          entityId: entityId,
          data: payload,
        );
        if (result.entityId != entityId || result.version != 1) {
          throw const HybridAdminException(HybridAdminFailure.invalidResponse);
        }
        created++;
      } on Object catch (error) {
        throw InitialContentImportException(
          failure: _safeFailure(error),
          created: created,
          alreadyPresent: alreadyPresent,
          tombstoned: tombstoned,
          skippedOtherContent: skippedOtherContent,
        );
      }
    }

    return InitialContentImportReport(
      created: created,
      alreadyPresent: alreadyPresent,
      tombstoned: tombstoned,
      skippedOtherContent: skippedOtherContent,
    );
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

  HybridAdminFailure _safeFailure(Object error) => error is HybridAdminException
      ? error.failure
      : HybridAdminFailure.unavailable;
}
