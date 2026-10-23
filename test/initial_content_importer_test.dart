import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/hybrid_admin_establishments_repository.dart';
import 'package:tudo_aqui_macacu/core/content/initial_content_importer.dart';

class _Repository implements AdminEstablishmentsRepository {
  final Map<String, Map<String, Object?>> existing = {};
  final Map<String, Map<String, Object?>> submitted = {};
  final List<String> createIds = [];
  final List<String> updateIds = [];
  final List<String> republishIds = [];
  String? failCreateId;
  String? failAfterCommitId;
  bool failOnce = false;

  @override
  Future<HybridAdminResult> create({
    required String requestId,
    String? entityId,
    required Map<String, Object?> data,
  }) async {
    final id = entityId!;
    createIds.add(id);
    if (failCreateId == id) {
      if (failOnce) failCreateId = null;
      throw const HybridAdminException(HybridAdminFailure.unavailable);
    }
    if (existing.containsKey(id)) {
      throw const HybridAdminException(HybridAdminFailure.conflict);
    }
    submitted[id] = Map<String, Object?>.from(data);
    existing[id] = <String, Object?>{
      ...data,
      'catalogVersion': 1,
      'outboxOperationId': requestId,
    };
    if (failAfterCommitId == id) {
      failAfterCommitId = null;
      throw const HybridAdminException(HybridAdminFailure.unavailable);
    }
    return HybridAdminResult(entityId: id, version: 1, replayed: false);
  }

  @override
  Future<HybridAdminResult> update({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) async {
    updateIds.add(entityId);
    throw const HybridAdminException(HybridAdminFailure.conflict);
  }

  @override
  Future<HybridAdminResult> unpublish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) async => throw const HybridAdminException(HybridAdminFailure.conflict);

  @override
  Future<HybridAdminResult> republish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) async {
    republishIds.add(entityId);
    throw const HybridAdminException(HybridAdminFailure.conflict);
  }

  @override
  Future<HybridAdminResult> delete({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) async => throw const HybridAdminException(HybridAdminFailure.conflict);
}

void main() {
  late _Repository repository;
  late List<String> requestIds;
  late int requestIdIndex;
  late InitialContentImporterService importer;

  ExistingEstablishmentState existingState(String id) {
    return classifyExistingEstablishment(repository.existing[id]);
  }

  InitialContentImportItem item(
    String id, {
    String category = 'Comércio',
    Map<String, Object?>? data,
  }) => InitialContentImportItem(
    entityId: id,
    category: category,
    editorData: data ?? {'title': 'Loja $id', 'category': category},
  );

  setUp(() {
    repository = _Repository();
    requestIds = List<String>.generate(
      10,
      (index) => '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    );
    requestIdIndex = 0;
    importer = InitialContentImporterService(
      repository: repository,
      lookupOnServer: (id) async => existingState(id),
      requestIdFactory: () => requestIds[requestIdIndex++],
    );
  });

  test(
    'versioned, outbox-marked, or tombstoned records require hybrid lifecycle',
    () {
      expect(establishmentRequiresHybridLifecycle(null), isFalse);
      expect(
        establishmentRequiresHybridLifecycle({'title': 'Legacy'}),
        isFalse,
      );
      expect(
        establishmentRequiresHybridLifecycle({'catalogVersion': 1}),
        isTrue,
      );
      expect(
        establishmentRequiresHybridLifecycle({'outboxOperationId': 'op'}),
        isTrue,
      );
      expect(
        establishmentRequiresHybridLifecycle({'deletedAt': DateTime.utc(2026)}),
        isTrue,
      );
    },
  );

  test('legacy write gate blocks only lifecycle-marked establishments', () {
    expect(
      shouldBlockLegacyEstablishmentWrite(
        isEstablishment: true,
        hybridEnabled: false,
        source: {'catalogVersion': 1},
      ),
      isTrue,
    );
    expect(
      shouldBlockLegacyEstablishmentWrite(
        isEstablishment: true,
        hybridEnabled: false,
        source: {'title': 'Legacy'},
      ),
      isFalse,
    );
    expect(
      shouldBlockLegacyEstablishmentWrite(
        isEstablishment: false,
        hybridEnabled: false,
        source: {'catalogVersion': 1},
      ),
      isFalse,
    );
    expect(
      shouldBlockLegacyEstablishmentWrite(
        isEstablishment: true,
        hybridEnabled: true,
        source: {'catalogVersion': 1},
      ),
      isFalse,
    );
  });

  test(
    'imports one new template with its original modelo ID at version one',
    () async {
      final result = await importer.import([
        item('modelo-1'),
      ], authorized: true);

      expect(repository.createIds, ['modelo-1']);
      expect(repository.submitted['modelo-1']?['title'], 'Loja modelo-1');
      expect(repository.existing['modelo-1']?['catalogVersion'], 1);
      expect(result.created, 1);
    },
  );

  test(
    'imports multiple establishments and skips other content categories',
    () async {
      final result = await importer.import([
        item('modelo-1'),
        item('modelo-2'),
        item('modelo-route', category: 'Roteiros'),
      ], authorized: true);

      expect(repository.createIds, ['modelo-1', 'modelo-2']);
      expect(result.created, 2);
      expect(result.skippedOtherContent, 1);
    },
  );

  test(
    're-import recognizes committed items and creates no duplicates',
    () async {
      await importer.import([item('modelo-1')], authorized: true);

      final result = await importer.import([
        item('modelo-1'),
      ], authorized: true);

      expect(repository.createIds, ['modelo-1']);
      expect(result.alreadyPresent, 1);
      expect(repository.existing['modelo-1']?['catalogVersion'], 1);
    },
  );

  test(
    'failure stops the batch and reports only completed item counts',
    () async {
      repository.failCreateId = 'modelo-2';

      await expectLater(
        importer.import([
          item('modelo-1'),
          item('modelo-2'),
          item('modelo-3'),
        ], authorized: true),
        throwsA(
          isA<InitialContentImportException>()
              .having(
                (error) => error.failure,
                'failure',
                HybridAdminFailure.unavailable,
              )
              .having((error) => error.created, 'created', 1),
        ),
      );

      expect(repository.createIds, ['modelo-1', 'modelo-2']);
      expect(repository.existing.keys, contains('modelo-1'));
      expect(repository.existing.keys, isNot(contains('modelo-3')));
    },
  );

  test(
    'retry after partial failure skips committed items and resumes safely',
    () async {
      repository.failCreateId = 'modelo-2';
      repository.failOnce = true;
      final items = [item('modelo-1'), item('modelo-2'), item('modelo-3')];

      await expectLater(
        importer.import(items, authorized: true),
        throwsA(isA<InitialContentImportException>()),
      );
      final resumed = await importer.import(items, authorized: true);

      expect(repository.createIds, [
        'modelo-1',
        'modelo-2',
        'modelo-2',
        'modelo-3',
      ]);
      expect(resumed.created, 2);
      expect(resumed.alreadyPresent, 1);
      expect(
        repository.existing.keys,
        containsAll(['modelo-1', 'modelo-2', 'modelo-3']),
      );
    },
  );

  test('legacy document ID conflict is surfaced without overwrite', () async {
    repository.existing['modelo-1'] = {'title': 'Original'};

    await expectLater(
      importer.import([item('modelo-1')], authorized: true),
      throwsA(
        isA<InitialContentImportException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.conflict,
        ),
      ),
    );

    expect(repository.createIds, isEmpty);
    expect(repository.existing['modelo-1'], {'title': 'Original'});
    expect(repository.updateIds, isEmpty);
  });

  test(
    'outbox markers allow a completed item to be recognized on retry',
    () async {
      repository.existing['modelo-1'] = {
        'title': 'Original',
        'catalogVersion': 4,
        'outboxOperationId': '00000000-0000-4000-8000-000000000001',
      };

      final result = await importer.import([
        item('modelo-1'),
      ], authorized: true);

      expect(result.alreadyPresent, 1);
      expect(repository.createIds, isEmpty);
      expect(repository.existing['modelo-1']?['catalogVersion'], 4);
    },
  );

  test(
    'partial or malformed outbox markers block import as a conflict',
    () async {
      repository.existing['modelo-1'] = {
        'title': 'Partially marked record',
        'catalogVersion': 2,
        'outboxOperationId': 'invalid-operation-id',
      };

      await expectLater(
        importer.import([item('modelo-1')], authorized: true),
        throwsA(
          isA<InitialContentImportException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.conflict,
          ),
        ),
      );
      expect(repository.createIds, isEmpty);
      expect(repository.updateIds, isEmpty);
    },
  );

  test(
    'ambiguous response after commit is recovered without duplicate create',
    () async {
      repository.failAfterCommitId = 'modelo-1';

      await expectLater(
        importer.import([item('modelo-1')], authorized: true),
        throwsA(isA<InitialContentImportException>()),
      );
      final resumed = await importer.import([
        item('modelo-1'),
      ], authorized: true);

      expect(repository.createIds, ['modelo-1']);
      expect(resumed.alreadyPresent, 1);
      expect(repository.existing['modelo-1']?['catalogVersion'], 1);
    },
  );

  test(
    'each candidate uses one server create call, never a client outbox write',
    () async {
      await importer.import([item('modelo-1')], authorized: true);

      expect(repository.createIds, ['modelo-1']);
      expect(repository.updateIds, isEmpty);
      expect(repository.republishIds, isEmpty);
      expect(repository.existing['modelo-1']?['outboxOperationId'], isNotNull);
    },
  );

  test(
    'does not change the create version or call update on re-import',
    () async {
      await importer.import([item('modelo-1')], authorized: true);
      await importer.import([item('modelo-1')], authorized: true);

      expect(repository.existing['modelo-1']?['catalogVersion'], 1);
      expect(repository.updateIds, isEmpty);
    },
  );

  test('denies unauthorized invocation before reading or writing', () async {
    var reads = 0;
    importer = InitialContentImporterService(
      repository: repository,
      lookupOnServer: (_) async {
        reads++;
        return ExistingEstablishmentState.absent;
      },
    );

    await expectLater(
      importer.import([item('modelo-1')], authorized: false),
      throwsA(
        isA<InitialContentImportException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.permissionDenied,
        ),
      ),
    );

    expect(reads, 0);
    expect(repository.createIds, isEmpty);
  });

  test('tombstoned existing ID is never republished by the importer', () async {
    repository.existing['modelo-1'] = {
      'catalogVersion': 6,
      'deletedAt': DateTime.utc(2026),
      'published': false,
    };

    final result = await importer.import([item('modelo-1')], authorized: true);

    expect(result.tombstoned, 1);
    expect(repository.republishIds, isEmpty);
    expect(repository.existing['modelo-1']?['catalogVersion'], 6);
    expect(repository.existing['modelo-1']?['deletedAt'], DateTime.utc(2026));
  });

  test(
    'unknown private fields are omitted before the server request',
    () async {
      await importer.import([
        item(
          'modelo-1',
          data: const {
            'title': 'Loja segura',
            'category': 'Comércio',
            'adminNotes': 'private sentinel',
            'ownerEmail': 'private@example.invalid',
          },
        ),
      ], authorized: true);

      expect(repository.submitted['modelo-1'], {
        'title': 'Loja segura',
        'category': 'Comércio',
      });
      expect(
        repository.submitted.toString(),
        isNot(contains('private sentinel')),
      );
    },
  );

  test('invalid payload is rejected before any item is written', () async {
    await expectLater(
      importer.import([
        item('modelo-1'),
        item('modelo-2', data: const {'title': 'Bad expiry', 'expiresAt': 42}),
      ], authorized: true),
      throwsA(
        isA<InitialContentImportException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.invalidRequest,
        ),
      ),
    );
    expect(repository.createIds, isEmpty);
  });

  test(
    'duplicate template IDs are rejected before any item is written',
    () async {
      await expectLater(
        importer.import([item('modelo-1'), item('modelo-1')], authorized: true),
        throwsA(
          isA<InitialContentImportException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.invalidRequest,
          ),
        ),
      );
      expect(repository.createIds, isEmpty);
    },
  );

  test(
    'read failure is sanitized and does not fall back to direct Firestore writes',
    () async {
      importer = InitialContentImporterService(
        repository: repository,
        lookupOnServer: (_) async => throw StateError('private raw details'),
      );

      Object? observed;
      try {
        await importer.import([item('modelo-1')], authorized: true);
      } on Object catch (error) {
        observed = error;
      }

      expect(observed, isA<InitialContentImportException>());
      expect(observed.toString(), isNot(contains('private raw details')));
      expect(repository.createIds, isEmpty);
    },
  );
}
