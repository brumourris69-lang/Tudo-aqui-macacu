import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/config/spark_public_catalog_environment.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/features/jobs/models/public_job.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/public_job_details_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final isLocalBuild = LocalSearchEnvironment.enabled;

  tearDown(() {
    SecureBackend.normalDebugOptInOverride = null;
    SecureBackend.normalDebugProjectIdOverride = null;
    SecureBackend.normalDebugInvokerOverride = null;
    SparkPublicCatalogEnvironment.resetForTest();
  });

  test(
    'explicit Spark mode resolves public jobs from the catalog without callables or local fallback',
    () async {
      expect(SparkPublicCatalogEnvironment.enabled, isTrue);
      SparkPublicCatalogEnvironment.markReadyForTest();
      final resolvedIds = <String>[];
      var callableCalls = 0;
      var localCalls = 0;
      final repository = PublicJobDetailsRepository(
        requireSparkCatalogReadyForTest: () {
          SparkPublicCatalogEnvironment.requireReady(
            actualProjectId: SparkPublicCatalogEnvironment.projectId,
          );
        },
        resolveSparkProjectionForTest: (id) async {
          resolvedIds.add(id);
          return const {
            'title': 'Vaga Spark pública',
            'description': 'Resumo público',
            'category': 'Comércio',
            'company': 'Empresa sintética',
          };
        },
        invokeStaging: (_, _) async {
          callableCalls++;
          return {'status': 'unavailable'};
        },
        resolveJob: (_) async {
          localCalls++;
          return null;
        },
      );

      final job = await repository.resolveById('spark-job-1');

      expect(resolvedIds, ['spark-job-1']);
      expect(callableCalls, 0);
      expect(localCalls, 0);
      expect(job?.id, 'spark-job-1');
      expect(job?.title, 'Vaga Spark pública');
      expect(job?.description, 'Resumo público');
    },
    skip: !SparkPublicCatalogEnvironment.enabled,
  );

  test(
    'Spark job detail fails closed on an unapproved project before loading',
    () async {
      expect(SparkPublicCatalogEnvironment.enabled, isTrue);
      SparkPublicCatalogEnvironment.markReadyForTest();
      var projectionCalls = 0;
      var callableCalls = 0;
      final repository = PublicJobDetailsRepository(
        requireSparkCatalogReadyForTest: () {
          SparkPublicCatalogEnvironment.requireReady(
            actualProjectId: 'unapproved-project',
          );
        },
        resolveSparkProjectionForTest: (_) async {
          projectionCalls++;
          return const {'title': 'Não deve carregar'};
        },
        invokeStaging: (_, _) async {
          callableCalls++;
          return {'status': 'unavailable'};
        },
      );

      await expectLater(
        repository.resolveById('spark-job-2'),
        throwsStateError,
      );
      expect(projectionCalls, 0);
      expect(callableCalls, 0);
    },
    skip: !SparkPublicCatalogEnvironment.enabled,
  );

  test(
    'normal build blocks getPublicJob before invoking any resolver',
    () async {
      var calls = 0;
      final repository = PublicJobDetailsRepository(
        resolveJob: (_) async {
          calls++;
          return null;
        },
      );

      await expectLater(
        repository.resolveById('job-1'),
        throwsA(isA<StateError>()),
      );
      expect(calls, 0);
    },
    skip: isLocalBuild || SparkPublicCatalogEnvironment.enabled,
  );

  test(
    'normal debug detail uses getPublicContentDetail with the original ID',
    () async {
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      String? operation;
      Map<String, dynamic>? arguments;
      SecureBackend.normalDebugInvokerOverride = (name, data) async {
        operation = name;
        arguments = Map.of(data);
        return {
          'status': 'available',
          'id': 'job-1',
          'data': {
            'title': 'Vaga pública',
            'contact': 'valor privado que não será decodificado',
          },
        };
      };
      final repository = PublicJobDetailsRepository(
        resolveJob: (_) async => throw StateError('demo fallback proibido'),
      );

      if (BetaEnvironment.enabled || SparkPublicCatalogEnvironment.enabled) {
        await expectLater(repository.resolveById('job-1'), throwsStateError);
        expect(operation, isNull);
        expect(SecureBackend.productionAuthorized, isFalse);
        return;
      }

      final job = await repository.resolveById('job-1');

      expect(operation, 'getPublicContentDetail');
      expect(arguments, {'collection': 'jobs', 'id': 'job-1'});
      expect(job?.id, 'job-1');
      expect(job?.title, 'Vaga pública');
      expect(job?.toString(), isNot(contains('valor privado')));
    },
    skip: isLocalBuild || SparkPublicCatalogEnvironment.enabled,
  );

  test(
    'staging uses only getPublicJob after its identity gate is ready',
    () async {
      var operation = '';
      var readyChecks = 0;
      final repository = PublicJobDetailsRepository(
        stagingEnabledForTest: () => true,
        requireStagingReadyForTest: () => readyChecks++,
        invokeStaging: (name, data) async {
          operation = name;
          expect(data, {'id': 'job-stage-1'});
          return {
            'status': 'available',
            'id': 'job-stage-1',
            'data': {
              'title': 'Vaga de teste',
              'contact': 'não deve ser modelado',
            },
          };
        },
        resolveJob: (_) async => throw StateError('demo fallback proibido'),
      );

      if (BetaEnvironment.enabled ||
          LocalSearchEnvironment.enabled ||
          SparkPublicCatalogEnvironment.enabled) {
        await expectLater(
          repository.resolveById('job-stage-1'),
          throwsStateError,
        );
        expect(readyChecks, 0);
        expect(operation, isEmpty);
        return;
      }

      final job = await repository.resolveById('job-stage-1');
      expect(readyChecks, 1);
      expect(operation, 'getPublicJob');
      expect(job?.title, 'Vaga de teste');
      expect(job?.toString(), isNot(contains('não deve ser modelado')));
    },
  );

  test(
    'staging gate failure happens before invocation and never uses demo',
    () async {
      var calls = 0;
      var demoCalls = 0;
      final repository = PublicJobDetailsRepository(
        stagingEnabledForTest: () => true,
        requireStagingReadyForTest: () => throw StateError('identity mismatch'),
        invokeStaging: (_, _) async {
          calls++;
          return {'status': 'unavailable'};
        },
        resolveJob: (_) async {
          demoCalls++;
          return null;
        },
      );

      await expectLater(
        repository.resolveById('job-stage-1'),
        throwsStateError,
      );
      expect(calls, 0);
      expect(demoCalls, 0);
    },
  );

  test('decodes only the public getPublicJob projection', () {
    final job = PublicJob.fromSearchResponse({
      'status': 'available',
      'id': 'job-1',
      'data': {
        'title': 'Vaga pública',
        'description': 'Descrição pública',
        'category': 'Serviços',
        'company': 'Empresa Exemplo',
        'contact': 'contato privado',
        'phone': 'telefone privado',
        'whatsapp': 'whatsapp privado',
        'link': 'link privado',
        'instagram': 'instagram privado',
        'maps': 'maps privado',
        'mapsUrl': 'maps URL privado',
        'additionalInfo': 'informação privada',
        'salary': 'salário não aprovado',
        'eventDate': 'data não aprovada',
        'date': 'data não aprovada',
        'unknownAdminField': 'campo desconhecido',
      },
    }, requestedId: 'job-1');

    expect(
      {
        'id': job?.id,
        'title': job?.title,
        'description': job?.description,
        'category': job?.category,
        'location': job?.location,
        'company': job?.company,
        'employmentType': job?.employmentType,
      },
      {
        'id': 'job-1',
        'title': 'Vaga pública',
        'description': 'Descrição pública',
        'category': 'Serviços',
        'location': '',
        'company': 'Empresa Exemplo',
        'employmentType': '',
      },
    );
  });

  test('decodes an unavailable getPublicJob response as null', () {
    expect(
      PublicJob.fromSearchResponse({
        'status': 'unavailable',
      }, requestedId: 'job-1'),
      isNull,
    );
  });

  test('rejects a getPublicJob response for a different document ID', () {
    expect(
      () => PublicJob.fromSearchResponse({
        'status': 'available',
        'id': 'another-job',
        'data': {'title': 'Vaga pública'},
      }, requestedId: 'job-1'),
      throwsFormatException,
    );
  });

  test('delegates to the demo resolver with the requested ID', () async {
    String? resolvedId;
    final repository = PublicJobDetailsRepository(
      resolveJob: (id) async {
        resolvedId = id;
        return const PublicJob(id: 'job-1', title: 'Vaga pública');
      },
    );

    final job = await repository.resolveById('job-1');

    expect(resolvedId, 'job-1');
    expect(job?.title, 'Vaga pública');
  }, skip: !isLocalBuild);

  test('rejects malformed IDs before invoking the local resolver', () async {
    var calls = 0;
    final repository = PublicJobDetailsRepository(
      resolveJob: (_) async {
        calls++;
        return null;
      },
    );

    await expectLater(
      repository.resolveById('jobs/job-1'),
      throwsFormatException,
    );
    expect(calls, 0);
  }, skip: !isLocalBuild);

  for (final failure in [
    StateError('autenticação recusada'),
    StateError('App Check recusado'),
    StateError('backend indisponível'),
  ]) {
    test('propagates resolver failure without fallback: $failure', () async {
      var calls = 0;
      final repository = PublicJobDetailsRepository(
        resolveJob: (_) async {
          calls++;
          throw failure;
        },
      );

      await expectLater(
        repository.resolveById('job-1'),
        throwsA(same(failure)),
      );
      expect(calls, 1);
    }, skip: !isLocalBuild);
  }
}
