import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_detail_repository.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/features/businesses/repositories/business_repository.dart';

void main() {
  final isLocalBuild = LocalSearchEnvironment.enabled;

  tearDown(() {
    SecureBackend.normalDebugOptInOverride = null;
    SecureBackend.normalDebugProjectIdOverride = null;
    SecureBackend.normalDebugInvokerOverride = null;
  });

  test(
    'resolves a validated public detail using the exact callable contract',
    () async {
      String? operation;
      Map<String, dynamic>? arguments;
      final repository = PublicContentDetailRepository(
        invoke: (name, data) async {
          operation = name;
          arguments = Map.of(data);
          return {
            'status': 'available',
            'id': 'business-1',
            'data': {'name': 'Mercado do Centro', 'category': 'Comércio'},
          };
        },
      );

      final result = await repository.resolve(
        collection: 'establishments',
        id: 'business-1',
      );

      expect(operation, 'getPublicContentDetail');
      expect(arguments, {'collection': 'establishments', 'id': 'business-1'});
      expect(result, {'name': 'Mercado do Centro', 'category': 'Comércio'});
    },
    skip: !isLocalBuild,
  );

  test('returns null for a well-formed unavailable detail', () async {
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async => {'status': 'unavailable'},
    );

    expect(
      await repository.resolve(collection: 'routes', id: 'route-1'),
      isNull,
    );
  }, skip: !isLocalBuild);

  test('rejects a private collection before invoking the transport', () async {
    var calls = 0;
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async {
        calls++;
        return {'status': 'unavailable'};
      },
    );

    await expectLater(
      repository.resolve(collection: 'job_private', id: 'job-1'),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('normal debug resolves public jobs through the approved detail callable', () async {
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
        'data': {'title': 'Vaga pública'},
      };
    };
    final repository = PublicContentDetailRepository();

    final result = await repository.resolve(collection: 'jobs', id: 'job-1');

    expect(operation, 'getPublicContentDetail');
    expect(arguments, {'collection': 'jobs', 'id': 'job-1'});
    expect(result, {'title': 'Vaga pública'});
  }, skip: isLocalBuild);

  test('rejects malformed IDs before invoking the transport', () async {
    var calls = 0;
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async {
        calls++;
        return {'status': 'unavailable'};
      },
    );

    await expectLater(
      repository.resolve(collection: 'utilities', id: 'utilities/u-1'),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  test('rejects an available response for a different document ID', () async {
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async => {
        'status': 'available',
        'id': 'another-id',
        'data': {'name': 'Conteúdo'},
      },
    );

    await expectLater(
      repository.resolve(collection: 'utilities', id: 'utility-1'),
      throwsFormatException,
    );
  }, skip: !isLocalBuild);

  test('propagates a transport error without attempting a fallback', () async {
    final error = StateError('backend unavailable');
    var calls = 0;
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async {
        calls++;
        throw error;
      },
    );

    await expectLater(
      repository.resolve(collection: 'routes', id: 'route-1'),
      throwsA(same(error)),
    );
    expect(calls, 1);
  }, skip: !isLocalBuild);

  test('normal app fails before calling an injected transport', () async {
    var calls = 0;
    final repository = PublicContentDetailRepository(
      invoke: (_, _) async {
        calls++;
        return {'status': 'unavailable'};
      },
    );

    await expectLater(
      repository.resolve(collection: 'establishments', id: 'business-1'),
      throwsStateError,
    );
    expect(calls, 0);
  }, skip: isLocalBuild);

  test(
    'normal business detail fails closed without initializing Firestore',
    () async {
      final repository = BusinessRepository();

      await expectLater(
        repository.getPublicBusiness('business-1'),
        throwsStateError,
      );
    },
    skip: isLocalBuild,
  );

  test(
    'business details are decoded from safe detail data without a Firestore get',
    () async {
      String? collection;
      String? id;
      final repository = BusinessRepository(
        details: PublicContentDetailRepository(
          invoke: (_, data) async {
            collection = data['collection'] as String?;
            id = data['id'] as String?;
            return {
              'status': 'available',
              'id': 'business-1',
              'data': {
                'name': 'Mercado do Centro',
                'category': 'Comércio',
                'location': 'Centro',
              },
            };
          },
        ),
      );

      final business = await repository.getPublicBusiness('business-1');

      expect(collection, 'establishments');
      expect(id, 'business-1');
      expect(business?.name, 'Mercado do Centro');
      expect(business?.location, 'Centro');
    },
    skip: !isLocalBuild,
  );

  test(
    'business detail returns null when the safe endpoint reports unavailable',
    () async {
      final repository = BusinessRepository(
        details: PublicContentDetailRepository(
          invoke: (_, _) async => {'status': 'unavailable'},
        ),
      );

      expect(await repository.getPublicBusiness('deleted-business'), isNull);
    },
    skip: !isLocalBuild,
  );
}
