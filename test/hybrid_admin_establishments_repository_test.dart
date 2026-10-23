import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tudo_aqui_macacu/core/content/hybrid_admin_establishments_repository.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';

class _TokenSource implements FirebaseIdTokenSource {
  _TokenSource({this.anonymous = false});

  final bool anonymous;
  final String token = 'firebase-id-token';
  int calls = 0;

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<String?> getIdToken() async {
    calls++;
    return token;
  }
}

void main() {
  final endpoint = Uri.parse(
    'http://127.0.0.1:5007/functions/v1/manage-establishments',
  );

  test(
    'create preserves a legacy ID and sends only Firebase identity',
    () async {
      final tokenSource = _TokenSource();
      Map<String, dynamic>? request;
      final client = MockClient((call) async {
        expect(call.url, endpoint);
        expect(call.headers['authorization'], 'Bearer firebase-id-token');
        expect(call.headers.containsKey('apikey'), isFalse);
        request = jsonDecode(call.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'result': 'created',
            'entityId': 'modelo-1',
            'version': 1,
            'replayed': false,
          }),
          201,
        );
      });
      final repository = FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: endpoint,
        tokenSource: tokenSource,
        client: client,
      );

      final result = await repository.create(
        requestId: _requestId,
        entityId: 'modelo-1',
        data: const {'title': 'Café', 'category': 'Onde comer?'},
      );

      expect(result.entityId, 'modelo-1');
      expect(result.version, 1);
      expect(request, {
        'operation': 'create',
        'requestId': _requestId,
        'entityId': 'modelo-1',
        'data': {'title': 'Café', 'category': 'Onde comer?'},
      });
      expect(tokenSource.calls, 1);
    },
  );

  test('client preserves valid Unicode Firestore document IDs', () async {
    final id = 'loja-café';
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: endpoint,
      tokenSource: _TokenSource(),
      client: MockClient((call) async {
        expect((jsonDecode(call.body) as Map)['entityId'], id);
        return http.Response(
          jsonEncode({
            'result': 'created',
            'entityId': id,
            'version': 1,
            'replayed': false,
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await repository.create(
      requestId: _requestId,
      entityId: id,
      data: const {'title': 'Loja', 'category': 'Comércio'},
    );

    expect(result.entityId, id);
  });

  test(
    'create rejects a server response with a different requested ID',
    () async {
      final repository = FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: endpoint,
        tokenSource: _TokenSource(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'result': 'created',
              'entityId': 'modelo-2',
              'version': 1,
              'replayed': false,
            }),
            201,
          ),
        ),
      );

      await expectLater(
        repository.create(
          requestId: _requestId,
          entityId: 'modelo-1',
          data: const {'title': 'Exemplo', 'category': 'Comércio'},
        ),
        throwsA(
          isA<HybridAdminException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'unpublish and logical delete send explicit versioned operations',
    () async {
      final requests = <Map<String, dynamic>>[];
      final repository = FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: endpoint,
        tokenSource: _TokenSource(),
        client: MockClient((call) async {
          final request = jsonDecode(call.body) as Map<String, dynamic>;
          requests.add(request);
          final isDelete = request['operation'] == 'delete';
          return http.Response(
            jsonEncode({
              'result': isDelete ? 'deleted' : 'unpublished',
              'entityId': 'modelo-1',
              'version': isDelete ? 3 : 2,
              'replayed': false,
            }),
            200,
          );
        }),
      );

      final unpublished = await repository.unpublish(
        requestId: _requestId,
        entityId: 'modelo-1',
        expectedVersion: 1,
      );
      final deleted = await repository.delete(
        requestId: _requestId,
        entityId: 'modelo-1',
        expectedVersion: 2,
      );

      expect(unpublished.version, 2);
      expect(deleted.version, 3);
      expect(requests, [
        {
          'operation': 'unpublish',
          'requestId': _requestId,
          'entityId': 'modelo-1',
          'expectedVersion': 1,
        },
        {
          'operation': 'delete',
          'requestId': _requestId,
          'entityId': 'modelo-1',
          'expectedVersion': 2,
        },
      ]);
    },
  );

  test('anonymous session fails before network access', () async {
    var calls = 0;
    final tokenSource = _TokenSource(anonymous: true);
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: endpoint,
      tokenSource: tokenSource,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      repository.create(
        requestId: _requestId,
        data: const {'title': 'Café', 'category': 'Onde comer?'},
      ),
      throwsA(
        isA<HybridAdminException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.unauthenticated,
        ),
      ),
    );
    expect(calls, 0);
    expect(tokenSource.calls, 0);
  });

  test('private fields are rejected before network access', () async {
    var calls = 0;
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: endpoint,
      tokenSource: _TokenSource(),
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      repository.create(
        requestId: _requestId,
        data: const {
          'title': 'Café',
          'category': 'Onde comer?',
          'adminNotes': 'must not leave device',
        },
      ),
      throwsA(
        isA<HybridAdminException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.invalidRequest,
        ),
      ),
    );
    expect(calls, 0);
  });

  test('service role credentials and non-approved endpoints are rejected', () {
    final tokenSource = _TokenSource();
    expect(
      () => FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: endpoint,
        tokenSource: tokenSource,
        client: MockClient((_) async => http.Response('{}', 200)),
        apiKey: 'sb_secret_never-allowed',
      ),
      throwsA(isA<HybridAdminException>()),
    );
    expect(
      () => FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: Uri.parse(
          'https://attacker.example/functions/v1/manage-establishments',
        ),
        tokenSource: tokenSource,
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      throwsA(isA<HybridAdminException>()),
    );
  });

  test(
    'transport errors are sanitized and are not retried or fallen back',
    () async {
      var calls = 0;
      final repository = FirebaseSupabaseAdminEstablishmentsRepository(
        endpoint: endpoint,
        tokenSource: _TokenSource(),
        client: MockClient((_) async {
          calls++;
          throw StateError('raw transport details with secret sentinel');
        }),
      );

      Object? observed;
      try {
        await repository.create(
          requestId: _requestId,
          data: const {'title': 'Café', 'category': 'Onde comer?'},
        );
      } on Object catch (error) {
        observed = error;
      }

      expect(observed, isA<HybridAdminException>());
      expect(observed.toString(), isNot(contains('secret sentinel')));
      expect(calls, 1);
    },
  );

  test('Firebase token retrieval failures are mapped to safe errors', () async {
    var calls = 0;
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: endpoint,
      tokenSource: _FailingTokenSource(),
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      repository.create(
        requestId: _requestId,
        data: const {'title': 'Café', 'category': 'Onde comer?'},
      ),
      throwsA(
        isA<HybridAdminException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.unavailable,
        ),
      ),
    );
    expect(calls, 0);
  });

  test(
    'editor payload drops local metadata and converts Firestore expiry values',
    () {
      final payload = hybridAdminPayloadFromEditor({
        'title': 'Café',
        'category': 'Onde comer?',
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'initial_template',
        'eventDate': 'not an establishment field',
        'contact': 'not part of the public contract',
        'expiresAt': FieldValue.delete(),
      });

      expect(payload, {
        'title': 'Café',
        'category': 'Onde comer?',
        'expiresAt': null,
      });
    },
  );

  test(
    'existing unpublished content uses explicit republish with the data patch',
    () async {
      final repository = _RecordingRepository();
      await saveHybridEstablishment(
        repository: repository,
        requestId: _requestId,
        entityId: 'modelo-1',
        expectedVersion: 3,
        wasPublished: false,
        data: const {'title': 'Atualizado', 'published': true},
      );

      expect(repository.operation, 'republish');
      expect(repository.entityId, 'modelo-1');
      expect(repository.expectedVersion, 3);
      expect(repository.data, {'title': 'Atualizado', 'published': true});
    },
  );

  test(
    'first hybrid save upgrades a legacy published record from version zero',
    () async {
      final repository = _RecordingRepository();
      await saveHybridEstablishment(
        repository: repository,
        requestId: _requestId,
        entityId: 'modelo-legado-1',
        expectedVersion: 0,
        wasPublished: true,
        data: const {'title': 'Migrado', 'published': true},
      );

      expect(repository.operation, 'update');
      expect(repository.entityId, 'modelo-legado-1');
      expect(repository.expectedVersion, 0);
      expect(repository.data, {'title': 'Migrado', 'published': true});
    },
  );

  test('republish sends the allowlisted edited data to the server', () async {
    Map<String, dynamic>? request;
    final repository = FirebaseSupabaseAdminEstablishmentsRepository(
      endpoint: endpoint,
      tokenSource: _TokenSource(),
      client: MockClient((call) async {
        request = jsonDecode(call.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'result': 'republished',
            'entityId': 'modelo-1',
            'version': 4,
            'replayed': false,
          }),
          200,
        );
      }),
    );

    await repository.republish(
      requestId: _requestId,
      entityId: 'modelo-1',
      expectedVersion: 3,
      data: const {'title': 'Atualizado', 'published': true},
    );

    expect(request, {
      'operation': 'republish',
      'requestId': _requestId,
      'entityId': 'modelo-1',
      'expectedVersion': 3,
      'data': {'title': 'Atualizado', 'published': true},
    });
  });

  test(
    'new content uses create and lets the server assign the entity ID',
    () async {
      final repository = _RecordingRepository();
      final result = await saveHybridEstablishment(
        repository: repository,
        requestId: _requestId,
        expectedVersion: null,
        wasPublished: null,
        data: const {'title': 'Novo', 'published': true},
      );

      expect(repository.operation, 'create');
      expect(repository.entityId, isNull);
      expect(result.entityId, 'server-id');
    },
  );

  test('only establishment taxonomy enters the establishments writer', () {
    expect(isHybridAdminEstablishmentCategory('Comércio'), isTrue);
    expect(isHybridAdminEstablishmentCategory('Profissionais'), isTrue);
    expect(isHybridAdminEstablishmentCategory('Turismo'), isFalse);
    expect(isHybridAdminEstablishmentCategory('Empregos'), isFalse);
  });

  test('ambiguous request reservation remains stable until explicit clear', () {
    final reservation = HybridAdminRequestReservation();
    final first = reservation.reserve(
      entityId: null,
      expectedVersion: null,
      payload: const {'title': 'Novo', 'category': 'Comércio'},
    );

    expect(
      reservation.reserve(
        entityId: null,
        expectedVersion: null,
        payload: const {'title': 'Novo', 'category': 'Comércio'},
      ),
      first,
    );
    expect(
      () => reservation.reserve(
        entityId: null,
        expectedVersion: null,
        payload: const {'title': 'Alterado', 'category': 'Comércio'},
      ),
      throwsA(
        isA<HybridAdminException>().having(
          (error) => error.failure,
          'failure',
          HybridAdminFailure.conflict,
        ),
      ),
    );
    reservation.clear('another-operation');
    expect(
      reservation.reserve(
        entityId: null,
        expectedVersion: null,
        payload: const {'title': 'Novo', 'category': 'Comércio'},
      ),
      first,
    );
    reservation.clear(first);
    expect(
      reservation.reserve(
        entityId: null,
        expectedVersion: null,
        payload: const {'title': 'Novo', 'category': 'Comércio'},
      ),
      isNot(first),
    );
  });
}

class _FailingTokenSource implements FirebaseIdTokenSource {
  @override
  bool get isAnonymous => false;

  @override
  Future<String?> getIdToken() =>
      Future.error(StateError('private SDK details must not escape'));
}

class _RecordingRepository implements AdminEstablishmentsRepository {
  String? operation;
  String? entityId;
  int? expectedVersion;
  Map<String, Object?>? data;

  HybridAdminResult get _result => const HybridAdminResult(
    entityId: 'server-id',
    version: 1,
    replayed: false,
  );

  @override
  Future<HybridAdminResult> create({
    required String requestId,
    String? entityId,
    required Map<String, Object?> data,
  }) async {
    operation = 'create';
    this.entityId = entityId;
    this.data = data;
    return _result;
  }

  @override
  Future<HybridAdminResult> update({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) async {
    operation = 'update';
    this.entityId = entityId;
    this.expectedVersion = expectedVersion;
    this.data = data;
    return _result;
  }

  @override
  Future<HybridAdminResult> unpublish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) async {
    operation = 'unpublish';
    this.entityId = entityId;
    this.expectedVersion = expectedVersion;
    return _result;
  }

  @override
  Future<HybridAdminResult> republish({
    required String requestId,
    required String entityId,
    required int expectedVersion,
    required Map<String, Object?> data,
  }) async {
    operation = 'republish';
    this.entityId = entityId;
    this.expectedVersion = expectedVersion;
    this.data = data;
    return _result;
  }

  @override
  Future<HybridAdminResult> delete({
    required String requestId,
    required String entityId,
    required int expectedVersion,
  }) async {
    operation = 'delete';
    this.entityId = entityId;
    this.expectedVersion = expectedVersion;
    return _result;
  }
}
