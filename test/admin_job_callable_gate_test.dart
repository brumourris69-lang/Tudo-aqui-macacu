import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/local_universal_search_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    SecureBackend.stagingEnabledOverride = null;
    SecureBackend.stagingInvokerOverride = null;
  });

  test('manageAdminJob is allowlisted only for local demo transport', () {
    expect(
      LocalUniversalSearchRepository.localOperations,
      contains('manageAdminJob'),
    );
    expect(
      SecureBackend.productionOperations,
      isNot(contains('manageAdminJob')),
    );
    expect(SecureBackend.stagingOperations, isNot(contains('manageAdminJob')));
    expect(SecureBackend.productionAuthorized, isFalse);
  });

  test(
    'normal transport rejects admin jobs before Firebase initialization or network',
    () async {
      SecureBackend.stagingEnabledOverride = false;
      await expectLater(
        SecureBackend.invoke('manageAdminJob', {'operation': 'list'}),
        throwsArgumentError,
      );
      await expectLater(
        CallableAdminJobRepository().list(),
        throwsA(
          isA<AdminJobException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    },
  );

  test(
    'staging transport rejects admin jobs before its network invoker',
    () async {
      var calls = 0;
      SecureBackend.stagingEnabledOverride = true;
      SecureBackend.stagingInvokerOverride = (_, data) async {
        calls++;
        return null;
      };
      await expectLater(
        SecureBackend.invoke('manageAdminJob', {'operation': 'list'}),
        throwsArgumentError,
      );
      await expectLater(
        CallableAdminJobRepository().list(),
        throwsA(
          isA<AdminJobException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'injected repository transport works offline with production gate closed',
    () async {
      final AdminJobRepository repository = CallableAdminJobRepository(
        invoke: (name, data) async {
          expect(name, 'manageAdminJob');
          return {'status': 'available', 'items': [], 'nextCursor': null};
        },
      );
      expect(SecureBackend.productionAuthorized, isFalse);
      expect((await repository.list()).items, isEmpty);
    },
  );
}
