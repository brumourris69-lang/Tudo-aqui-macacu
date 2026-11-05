import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository_factory.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/spark_admin_job_repository.dart';

class _FirestoreStub implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Beta jobs use the Firestore-only Spark repository', () {
    final firestore = _FirestoreStub();
    final repository = createAdminJobRepository(
      sparkBeta: true,
      firestore: () => firestore,
    );

    expect(repository, isA<SparkAdminJobRepository>());
    expect(repository, isNot(isA<CallableAdminJobRepository>()));
  });

  test(
    'non-Beta variants retain the callable repository without Firestore',
    () {
      final repository = createAdminJobRepository(
        sparkBeta: false,
        firestore: () => fail('Callable variant must not initialize Firestore'),
      );

      expect(repository, isA<CallableAdminJobRepository>());
      expect(repository, isNot(isA<SparkAdminJobRepository>()));
    },
  );
}
