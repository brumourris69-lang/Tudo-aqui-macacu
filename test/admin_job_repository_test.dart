import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';

const _public = <String, dynamic>{
  'title': 'Vaga',
  'description': 'Descrição',
  'imageUrl': '',
  'artwork': 0,
  'galleryUrls': <String>[],
  'category': '',
  'location': '',
  'address': '',
  'published': false,
  'active': true,
  'expiresAt': null,
};
const _private = <String, dynamic>{
  'contact': '',
  'phone': '',
  'whatsapp': '',
  'link': '',
  'instagram': '',
  'maps': '',
  'mapsUrl': '',
  'additionalInfo': '',
};

TypeMatcher<AdminJobException> _error(String code) =>
    isA<AdminJobException>().having((error) => error.code, 'code', code);

Future<Object> _captureException<T>(Future<T> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  throw StateError('Expected the operation to fail.');
}

void main() {
  test(
    'list sends bounded page request and decodes only summary DTOs',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          expect(data, {
            'operation': 'list',
            'pageSize': 2,
            'cursor': 'opaque-cursor',
          });
          return {
            'status': 'available',
            'items': [
              {
                'id': 'job-1',
                'summary': {
                  'title': 'Vaga',
                  'published': false,
                  'active': true,
                },
              },
            ],
            'nextCursor': 'next-cursor',
          };
        },
      );
      final page = await repository.list(pageSize: 2, cursor: 'opaque-cursor');
      expect(page.items.single.id, 'job-1');
      expect(page.items.single.title, 'Vaga');
      expect(page.items.single.published, isFalse);
      expect(page.items.single.active, isTrue);
      expect(page.nextCursor, 'next-cursor');
      expect(() => page.items.clear(), throwsUnsupportedError);
    },
  );

  test('list defaults to 30 and omits absent cursor', () async {
    final repository = CallableAdminJobRepository(
      invoke: (name, data) async {
        expect(data, {'operation': 'list', 'pageSize': 30});
        return {'status': 'available', 'items': [], 'nextCursor': null};
      },
    );
    expect((await repository.list()).items, isEmpty);
  });

  test(
    'get validates the requested ID and separates immutable public/private data',
    () async {
      final public = {
        ..._public,
        'galleryUrls': ['https://example.invalid/image.jpg'],
      };
      final private = {..._private, 'contact': 'admin@example.invalid'};
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          expect(data, {'operation': 'get', 'jobId': 'job-1'});
          return {
            'status': 'available',
            'jobId': 'job-1',
            'publicData': public,
            'privateData': private,
          };
        },
      );
      final record = await repository.get('job-1');
      expect(record.jobId, 'job-1');
      expect(record.publicData, public);
      expect(record.privateData, private);
      private['contact'] = 'changed';
      expect(record.privateData['contact'], 'admin@example.invalid');
      expect(
        () => record.publicData['title'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (record.publicData['galleryUrls'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'create serializes expiration and sends exact supplied ID and split payloads',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          expect(data, {
            'operation': 'create',
            'jobId': 'reserved-id',
            'publicData': {
              'title': 'Vaga',
              'expiresAt': '2026-10-17T12:00:00.000Z',
            },
            'privateData': {'contact': 'private', 'phone': ''},
          });
          return {'status': 'created', 'jobId': 'reserved-id'};
        },
      );
      expect(
        await repository.create(
          jobId: 'reserved-id',
          publicData: {
            'title': 'Vaga',
            'expiresAt': DateTime.utc(2026, 10, 17, 12),
          },
          privateData: {'contact': 'private', 'phone': ''},
        ),
        'reserved-id',
      );
    },
  );

  test(
    'update preserves omitted private fields and explicit empty values',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          expect(data, {
            'operation': 'update',
            'jobId': 'job-1',
            'publicData': {'expiresAt': null},
            'privateData': {'phone': ''},
          });
          return {'status': 'updated', 'jobId': 'job-1'};
        },
      );
      await repository.update(
        jobId: 'job-1',
        publicData: {'expiresAt': null},
        privateData: {'phone': ''},
      );
    },
  );

  test(
    'delete sends only the operation and ID and requires positive response',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          expect(data, {'operation': 'delete', 'jobId': 'job-1'});
          return {'status': 'deleted', 'jobId': 'job-1'};
        },
      );
      await repository.delete('job-1');
    },
  );

  test(
    'create reserves securely local IDs and reuses pending ID after lost result',
    () async {
      var calls = 0;
      final ids = <String>[];
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          ids.add(data['jobId'] as String);
          if (++calls == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'private SDK details',
            );
          }
          return {'status': 'created', 'jobId': data['jobId']};
        },
      );
      final reserved = repository.reserveCreateId();
      expect(reserved, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
      expect(repository.reserveCreateId(), reserved);
      await expectLater(
        repository.create(jobId: reserved, publicData: {}, privateData: {}),
        throwsA(_error('unavailable')),
      );
      expect(repository.reserveCreateId(), reserved);
      expect(
        await repository.create(
          jobId: repository.reserveCreateId(),
          publicData: {},
          privateData: {},
        ),
        reserved,
      );
      expect(ids, [reserved, reserved]);
      expect(repository.reserveCreateId(), isNot(reserved));
    },
  );

  test(
    'create reconciles an already committed request after a lost acknowledgement',
    () async {
      var calls = 0;
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          calls++;
          if (name != 'manageAdminJob') fail('Unexpected callable: $name');
          if (calls == 1) {
            expect(data['operation'], 'create');
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'create acknowledgement was lost',
            );
          }
          if (calls == 2) {
            expect(data['operation'], 'create');
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'the first create was already committed',
            );
          }
          expect(data, {'operation': 'get', 'jobId': 'reserved-id'});
          return {
            'status': 'available',
            'jobId': 'reserved-id',
            'publicData': _public,
            'privateData': _private,
          };
        },
      );

    await expectLater(
      repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
      throwsA(_error('unavailable')),
    );
    expect(
      await repository.create(
        jobId: 'reserved-id',
        publicData: _public,
        privateData: _private,
      ),
        'reserved-id',
      );
      expect(calls, 3);
      expect(repository.reserveCreateId(), isNot('reserved-id'));
    },
  );

  test(
    'create does not release an ambiguous ID when existing data differs',
    () async {
      var calls = 0;
      final repository = CallableAdminJobRepository(
        invoke: (_, data) async {
          calls++;
          if (calls == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'the first create may have committed',
            );
          }
          if (data['operation'] == 'create') {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'existing ID',
            );
          }
          return {
            'status': 'available',
            'jobId': 'reserved-id',
            'publicData': {..._public, 'title': 'Changed after create'},
            'privateData': _private,
          };
        },
      );
      await expectLater(
        repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
        throwsA(_error('unavailable')),
      );
      final error = await _captureException(
        repository.create(
          jobId: 'reserved-id',
          publicData: {..._public, 'title': 'Changed by the user'},
          privateData: _private,
        ),
      );

      expect(error, _error('failed-precondition'));
      expect((error as AdminJobException).createPayloadConflict, isTrue);
      expect(error.createReservationReleased, isFalse);
      expect(repository.reserveCreateId(), 'reserved-id');
    },
  );

  test(
    'create keeps an ambiguous reservation when private reconciliation is incomplete',
    () async {
      var calls = 0;
      final repository = CallableAdminJobRepository(
        invoke: (_, data) async {
          calls++;
          if (calls == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'the create may have committed',
            );
          }
          if (data['operation'] == 'create') {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'existing ID',
            );
          }
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'private document is unavailable',
          );
        },
      );
      await expectLater(
        repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
        throwsA(_error('unavailable')),
      );
      final error = await _captureException(
        repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
      );

      expect(error, _error('failed-precondition'));
      expect((error as AdminJobException).createPayloadConflict, isTrue);
      expect(error.createReservationReleased, isFalse);
      expect(repository.reserveCreateId(), 'reserved-id');
    },
  );

  test(
    'create releases a colliding ID when reconciliation finds different data',
    () async {
      var calls = 0;
      final repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          calls++;
          if (calls == 1) {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'collision',
            );
          }
          return {
            'status': 'available',
            'jobId': 'reserved-id',
            'publicData': {..._public, 'title': 'Existing vacancy'},
            'privateData': _private,
          };
        },
      );
      final error = await _captureException(
        repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
      );

      expect(error, _error('failed-precondition'));
      expect((error as AdminJobException).createReservationReleased, isTrue);
      expect(repository.reserveCreateId(), isNot('reserved-id'));
    },
  );

  test(
    'create retains its reservation when collision reconciliation is unavailable',
    () async {
      var calls = 0;
      final repository = CallableAdminJobRepository(
        invoke: (_, _) async {
          calls++;
          throw FirebaseFunctionsException(
            code: calls == 1 ? 'failed-precondition' : 'unavailable',
            message: 'temporary failure',
          );
        },
      );
      final error = await _captureException(
        repository.create(
          jobId: 'reserved-id',
          publicData: _public,
          privateData: _private,
        ),
      );

      expect(error, _error('unavailable'));
      expect(repository.reserveCreateId(), 'reserved-id');
    },
  );

  test(
    'create releases reservation after definitive local validation failure',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (_, _) async {
          fail('Invalid payload must not reach the callable');
        },
      );
      final error = await _captureException(
        repository.create(
          jobId: 'reserved-id',
          publicData: {'title': 'x' * 141},
          privateData: {},
        ),
      );

      expect(error, _error('invalid-argument'));
      expect((error as AdminJobException).createReservationReleased, isTrue);
      expect(repository.reserveCreateId(), isNot('reserved-id'));
    },
  );

  test(
    'a malformed create acknowledgement preserves the pending reservation',
    () async {
      final repository = CallableAdminJobRepository(
        invoke: (_, data) async => {'status': 'created', 'jobId': 'wrong-id'},
      );
      final id = repository.reserveCreateId();
      await expectLater(
        repository.create(jobId: id, publicData: {}, privateData: {}),
        throwsA(_error('invalid-response')),
      );
      expect(repository.reserveCreateId(), id);
    },
  );

  for (final operation in ['list', 'get', 'create', 'update', 'delete']) {
    for (final response in [
      null,
      'wrong',
      <String, dynamic>{},
      {'status': 'unavailable'},
      {'status': 'available', 'jobId': 'other'},
    ]) {
      test(
        '$operation rejects missing/malformed acknowledgement $response',
        () async {
          final repository = CallableAdminJobRepository(
            invoke: (_, data) async => response,
          );
          final call = switch (operation) {
            'list' => repository.list(),
            'get' => repository.get('job-1'),
            'create' => repository.create(
              jobId: 'job-1',
              publicData: {},
              privateData: {},
            ),
            'update' => repository.update(
              jobId: 'job-1',
              publicData: {},
              privateData: {},
            ),
            _ => repository.delete('job-1'),
          };
          await expectLater(call, throwsA(_error('invalid-response')));
        },
      );
    }
  }

  for (final badPage in [
    {'status': 'available', 'items': [], 'nextCursor': 1},
    {'status': 'available', 'items': [], 'nextCursor': ''},
    {'status': 'available', 'items': []},
    {
      'status': 'available',
      'items': [],
      'nextCursor': null,
      'privateData': _private,
    },
    {
      'status': 'available',
      'items': [
        {
          'id': 'job-1',
          'summary': {
            'title': 'Vaga',
            'published': true,
            'active': true,
            'contact': 'secret',
          },
        },
      ],
      'nextCursor': null,
    },
    {
      'status': 'available',
      'items': [
        {
          'id': 'job-1',
          'summary': {'title': 'Vaga', 'published': 'true', 'active': true},
        },
      ],
      'nextCursor': null,
    },
    {
      'status': 'available',
      'items': [
        {
          'id': 'job-1',
          'summary': {'title': 'Vaga', 'published': true, 'active': true},
        },
        {
          'id': 'job-1',
          'summary': {'title': 'Vaga', 'published': true, 'active': true},
        },
      ],
      'nextCursor': null,
    },
  ]) {
    test('list rejects invalid or private-bearing response $badPage', () async {
      final repository = CallableAdminJobRepository(
        invoke: (_, data) async => badPage,
      );
      await expectLater(repository.list(), throwsA(_error('invalid-response')));
    });
  }

  test('list rejects server pages exceeding the requested size', () async {
    final repository = CallableAdminJobRepository(
      invoke: (_, data) async => {
        'status': 'available',
        'items': [
          for (var i = 0; i < 2; i++)
            {
              'id': 'job-$i',
              'summary': {'title': '', 'published': false, 'active': false},
            },
        ],
        'nextCursor': null,
      },
    );
    await expectLater(
      repository.list(pageSize: 1),
      throwsA(_error('invalid-response')),
    );
  });

  for (final badRecord in [
    {
      'status': 'available',
      'jobId': 'other',
      'publicData': _public,
      'privateData': _private,
    },
    {'status': 'available', 'jobId': 'job-1', 'publicData': _public},
    {
      'status': 'available',
      'jobId': 'job-1',
      'publicData': {..._public, 'phone': 'secret'},
      'privateData': _private,
    },
    {
      'status': 'available',
      'jobId': 'job-1',
      'publicData': _public,
      'privateData': {..._private, 'schemaVersion': 1},
    },
    {
      'status': 'available',
      'jobId': 'job-1',
      'publicData': {..._public, 'expiresAt': 1},
      'privateData': _private,
    },
    {
      'status': 'available',
      'jobId': 'job-1',
      'publicData': {},
      'privateData': _private,
    },
  ]) {
    test(
      'get rejects invalid or cross-contaminated record $badRecord',
      () async {
        final repository = CallableAdminJobRepository(
          invoke: (_, data) async => badRecord,
        );
        await expectLater(
          repository.get('job-1'),
          throwsA(_error('invalid-response')),
        );
      },
    );
  }

  for (final operation in ['create', 'update', 'delete']) {
    test(
      '$operation rejects ID mismatch and unexpected private data',
      () async {
        for (final response in [
          {'status': '${operation}d', 'jobId': 'other'},
          {
            'status': operation == 'create'
                ? 'created'
                : operation == 'update'
                ? 'updated'
                : 'deleted',
            'jobId': 'job-1',
            'privateData': _private,
          },
        ]) {
          final repository = CallableAdminJobRepository(
            invoke: (_, data) async => response,
          );
          final call = switch (operation) {
            'create' => repository.create(
              jobId: 'job-1',
              publicData: {},
              privateData: {},
            ),
            'update' => repository.update(
              jobId: 'job-1',
              publicData: {},
              privateData: {},
            ),
            _ => repository.delete('job-1'),
          };
          await expectLater(call, throwsA(_error('invalid-response')));
        }
      },
    );
  }

  for (final code in [
    'invalid-argument',
    'unauthenticated',
    'permission-denied',
    'not-found',
    'failed-precondition',
    'aborted',
    'unavailable',
    'internal',
  ]) {
    test(
      'callable error $code retains a safe code without SDK details',
      () async {
        final repository = CallableAdminJobRepository(
          invoke: (_, data) async => throw FirebaseFunctionsException(
            code: code,
            message: 'secret contact token',
            details: {'contact': 'private'},
          ),
        );
        await expectLater(
          repository.get('job-1'),
          throwsA(
            _error(code).having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
      },
    );
  }

  for (final error in [
    StateError('secret environment'),
    ArgumentError('secret gate'),
    Exception('secret unexpected'),
    FirebaseFunctionsException(code: 'unknown', message: 'secret'),
    FirebaseFunctionsException(code: 'deadline-exceeded', message: 'secret'),
  ]) {
    test(
      'unexpected/gate/timeout errors are controlled: ${error.runtimeType}',
      () async {
        final repository = CallableAdminJobRepository(
          invoke: (_, data) async => throw error,
        );
        await expectLater(
          repository.get('job-1'),
          throwsA(
            isA<AdminJobException>().having(
              (e) => e.toString(),
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
      },
    );
  }

  test('rejects invalid requests before invoking transport', () async {
    var calls = 0;
    final repository = CallableAdminJobRepository(
      invoke: (_, data) async {
        calls++;
        return null;
      },
    );
    for (final id in [
      '',
      '.',
      '..',
      'bad/id',
      'bad\n',
      '__reserved__',
      'a' * 129,
    ]) {
      await expectLater(
        repository.get(id),
        throwsA(_error('invalid-argument')),
      );
      await expectLater(
        repository.delete(id),
        throwsA(_error('invalid-argument')),
      );
      await expectLater(
        repository.create(jobId: id, publicData: {}, privateData: {}),
        throwsA(_error('invalid-argument')),
      );
      await expectLater(
        repository.update(jobId: id, publicData: {}, privateData: {}),
        throwsA(_error('invalid-argument')),
      );
    }
    for (final size in [0, 41]) {
      await expectLater(
        repository.list(pageSize: size),
        throwsA(_error('invalid-argument')),
      );
    }
    for (final cursor in ['', 'a' * 1025]) {
      await expectLater(
        repository.list(cursor: cursor),
        throwsA(_error('invalid-argument')),
      );
    }
    for (final payload in [
      {'contact': 'secret'},
      {'unknown': true},
      {'updatedAt': 'client timestamp'},
      {'published': 'true'},
      {'title': 'a' * 141},
      {'artwork': 1.2},
      {'imageUrl': 'http://example.invalid/a.jpg'},
      {
        'galleryUrls': ['bad'],
      },
      {'expiresAt': 'not a date'},
      {'expiresAt': '2026-02-30T00:00:00Z'},
    ]) {
      await expectLater(
        repository.create(jobId: 'job-1', publicData: payload, privateData: {}),
        throwsA(_error('invalid-argument')),
      );
    }
    for (final payload in [
      {'schemaVersion': 1},
      {'updatedAt': 'client timestamp'},
      {'phone': 1},
      {'phone': 'a' * 65},
    ]) {
      await expectLater(
        repository.update(jobId: 'job-1', publicData: {}, privateData: payload),
        throwsA(_error('invalid-argument')),
      );
    }
    expect(calls, 0);
  });

  test(
    'repository has no Firestore dependency or document allocation path',
    () {
      final source = File(
        'lib/features/jobs/repositories/admin_job_repository.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('cloud_firestore')));
      expect(source, isNot(contains('FirebaseFirestore')));
      expect(source, isNot(contains('.collection(')));
    },
  );
}
