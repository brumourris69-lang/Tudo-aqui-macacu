import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';

// Narrow Firestore fakes: these expose only the operations the job repository
// is allowed to perform, so the tests can assert a single atomic batch.
// ignore: subtype_of_sealed_class
class _Firestore implements FirebaseFirestore {
  final Map<String, _Ref> refs = {};
  final _Batch writeBatch = _Batch();
  int reservedIds = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  WriteBatch batch() => writeBatch;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.firestore, this.path);
  @override
  final _Firestore firestore;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) {
    final documentId = id ?? 'reserved-${++firestore.reservedIds}';
    return firestore.refs.putIfAbsent(
      '$path/$documentId',
      () => _Ref(path, documentId),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Ref implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.collectionPath, this.id);
  final String collectionPath;
  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Batch implements WriteBatch {
  final writes = <String, Map<String, Object?>>{};
  final sets = <String>[];
  final updates = <String>[];
  final deletes = <String>[];
  int commits = 0;
  Object? commitError;

  @override
  WriteBatch set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {
    final path = '${(document as _Ref).collectionPath}/${document.id}';
    sets.add(path);
    writes[path] = Map<String, Object?>.from(data as Map);
    return this;
  }

  @override
  WriteBatch update(
    DocumentReference<Object?> document,
    Map<Object, Object?> data,
  ) {
    final path = '${(document as _Ref).collectionPath}/${document.id}';
    updates.add(path);
    writes[path] = Map<String, Object?>.from(data);
    return this;
  }

  @override
  WriteBatch delete(DocumentReference<Object?> document) {
    final ref = document as _Ref;
    deletes.add('${ref.collectionPath}/${ref.id}');
    return this;
  }

  @override
  Future<void> commit() async {
    commits++;
    if (commitError case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'creation reserves one ID and atomically writes public and private docs',
    () async {
      final firestore = _Firestore();
      final repository = FirestoreAdminJobRepository(firestore);

      final id = await repository.create(
        publicData: {
          'title': 'Vaga fictícia',
          'description': 'Teste',
          'instagram': 'https://example.invalid/instagram',
          'maps': 'https://example.invalid/maps',
          'mapsUrl': 'https://example.invalid/maps',
          'additionalInfo': 'Notas privadas',
          'eventDate': 'não aplicável',
          'date': 'não aplicável',
        },
        privateData: {
          'contact': 'admin@example.invalid',
          'instagram': 'https://example.invalid/instagram',
          'maps': 'https://example.invalid/maps',
          'mapsUrl': 'https://example.invalid/maps',
          'additionalInfo': 'Notas privadas',
        },
      );

      expect(id, 'reserved-1');
      expect(firestore.writeBatch.commits, 1);
      expect(firestore.writeBatch.sets, ['jobs/$id', 'job_private/$id']);
      expect(
        firestore.writeBatch.writes.keys,
        containsAll(['jobs/$id', 'job_private/$id']),
      );
      expect(firestore.writeBatch.writes['jobs/$id'], {
        'title': 'Vaga fictícia',
        'description': 'Teste',
      });
      expect(
        firestore.writeBatch.writes['job_private/$id']?['contact'],
        'admin@example.invalid',
      );
      expect(
        firestore.writeBatch.writes['job_private/$id']?['additionalInfo'],
        'Notas privadas',
      );
    },
  );

  test('public projection removes all administrative contact fields', () {
    expect(
      publicJobPayload({
        'title': 'Vaga',
        'contact': 'private',
        'phone': 'private',
        'whatsapp': 'private',
        'link': 'private',
        'instagram': 'private',
        'maps': 'private',
        'mapsUrl': 'private',
        'additionalInfo': 'private',
        'eventDate': 'not a job field',
        'date': 'not a job field',
      }),
      {'title': 'Vaga'},
    );
  });

  test(
    'update patches both documents without replacing other private fields',
    () async {
      final firestore = _Firestore();
      final repository = FirestoreAdminJobRepository(firestore);

      await repository.update(
        jobId: 'stable-id',
        publicData: {'description': 'Atualizada'},
        privateData: {'phone': '123'},
      );

      expect(firestore.writeBatch.commits, 1);
      expect(firestore.writeBatch.updates, [
        'jobs/stable-id',
        'job_private/stable-id',
      ]);
      expect(
        firestore.writeBatch.writes.keys,
        containsAll(['jobs/stable-id', 'job_private/stable-id']),
      );
      expect(
        firestore.writeBatch.writes['job_private/stable-id']?['phone'],
        '123',
      );
      expect(
        firestore.writeBatch.writes['job_private/stable-id']!.containsKey(
          'contact',
        ),
        isFalse,
      );
    },
  );

  test(
    'explicitly clearing private job fields deletes them in the batch',
    () async {
      final firestore = _Firestore();
      final repository = FirestoreAdminJobRepository(firestore);

      await repository.update(
        jobId: 'stable-id',
        publicData: {'title': 'Vaga'},
        privateData: {
          'instagram': '',
          'maps': '',
          'mapsUrl': '',
          'additionalInfo': '',
        },
      );

      final privatePatch =
          firestore.writeBatch.writes['job_private/stable-id']!;
      for (final field in ['instagram', 'maps', 'mapsUrl', 'additionalInfo']) {
        expect(privatePatch[field], isA<FieldValue>());
      }
      expect(firestore.writeBatch.commits, 1);
    },
  );

  test('delete removes both documents in one batch', () async {
    final firestore = _Firestore();
    final repository = FirestoreAdminJobRepository(firestore);

    await repository.delete('stable-id');

    expect(firestore.writeBatch.commits, 1);
    expect(firestore.writeBatch.deletes, [
      'jobs/stable-id',
      'job_private/stable-id',
    ]);
  });

  test(
    'write errors are propagated without a second commit or success',
    () async {
      final firestore = _Firestore()
        ..writeBatch.commitError = StateError('offline');
      final repository = FirestoreAdminJobRepository(firestore);

      await expectLater(
        repository.create(publicData: {'title': 'Vaga'}, privateData: {}),
        throwsA(isA<StateError>()),
      );
      expect(firestore.writeBatch.commits, 1);
    },
  );

  test('a create retry reuses its previously reserved document ID', () async {
    final firestore = _Firestore()
      ..writeBatch.commitError = StateError('temporary network failure');
    final repository = FirestoreAdminJobRepository(firestore);

    await expectLater(
      repository.create(publicData: {'title': 'Vaga'}, privateData: {}),
      throwsA(isA<StateError>()),
    );
    firestore.writeBatch.commitError = null;
    final id = await repository.create(
      publicData: {'title': 'Vaga'},
      privateData: {},
    );

    expect(id, 'reserved-1');
    expect(firestore.reservedIds, 1);
    expect(firestore.writeBatch.commits, 2);
  });
}
