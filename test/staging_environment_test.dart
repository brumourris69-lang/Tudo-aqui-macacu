import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/staging_environment.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';

void main() {
  tearDown(() {
    SecureBackend.stagingEnabledOverride = null;
    SecureBackend.stagingInvokerOverride = null;
    StagingEnvironment.resetForTest();
  });

  group('staging identity policy', () {
    test('accepts only explicitly opted-in, independent debug identity', () {
      expect(
        StagingEnvironment.validateIdentity(
          flavor: 'staging',
          expectedProjectId: 'macacu-homologacao',
          actualProjectId: 'macacu-homologacao',
          nativeExpectedProjectId: 'macacu-homologacao',
          applicationId: StagingEnvironment.applicationId,
          optIn: true,
          debugBuild: true,
          localSearchEnabled: false,
        ),
        isNull,
      );
    });

    test(
      'rejects missing opt-in, missing project and production/demo identity',
      () {
        final base = <String, Object?>{
          'flavor': 'staging',
          'expectedProjectId': 'macacu-homologacao',
          'actualProjectId': 'macacu-homologacao',
          'nativeExpectedProjectId': 'macacu-homologacao',
          'applicationId': StagingEnvironment.applicationId,
          'optIn': true,
          'debugBuild': true,
          'localSearchEnabled': false,
        };
        String? validate(Map<String, Object?> overrides) =>
            StagingEnvironment.validateIdentity(
              flavor: overrides['flavor'] as String,
              expectedProjectId: overrides['expectedProjectId'] as String,
              actualProjectId: overrides['actualProjectId'] as String,
              nativeExpectedProjectId:
                  overrides['nativeExpectedProjectId'] as String,
              applicationId: overrides['applicationId'] as String,
              optIn: overrides['optIn'] as bool,
              debugBuild: overrides['debugBuild'] as bool,
              localSearchEnabled: overrides['localSearchEnabled'] as bool,
            );

        expect(validate({...base, 'optIn': false}), isNotNull);
        expect(validate({...base, 'expectedProjectId': ''}), isNotNull);
        expect(
          validate({...base, 'expectedProjectId': 'tudo-aqui-macacu'}),
          isNotNull,
        );
        expect(
          validate({...base, 'expectedProjectId': 'demo-universal-search'}),
          isNotNull,
        );
        expect(
          validate({...base, 'expectedProjectId': 'some-other-project'}),
          isNotNull,
        );
      },
    );

    test(
      'rejects project/package mismatch, release and searchLocal overlap',
      () {
        const project = 'macacu-homologacao';
        String? validate({
          String flavor = 'staging',
          String actualProjectId = project,
          String nativeExpectedProjectId = project,
          String applicationId = StagingEnvironment.applicationId,
          bool debugBuild = true,
          bool localSearchEnabled = false,
        }) => StagingEnvironment.validateIdentity(
          flavor: flavor,
          expectedProjectId: project,
          actualProjectId: actualProjectId,
          nativeExpectedProjectId: nativeExpectedProjectId,
          applicationId: applicationId,
          optIn: true,
          debugBuild: debugBuild,
          localSearchEnabled: localSearchEnabled,
        );

        expect(validate(actualProjectId: 'tudo-aqui-macacu'), isNotNull);
        expect(validate(nativeExpectedProjectId: 'other-project'), isNotNull);
        expect(validate(applicationId: 'br.com.other.app'), isNotNull);
        expect(validate(debugBuild: false), isNotNull);
        expect(validate(flavor: 'production'), isNotNull);
        expect(validate(localSearchEnabled: true), isNotNull);
      },
    );

    test(
      'startup gate requires the verified identity before transport use',
      () {
        StagingEnvironment.resetForTest();
        expect(() => StagingEnvironment.requireReady(), throwsStateError);
        StagingEnvironment.markReadyForTest();
        expect(() => StagingEnvironment.requireReady(), returnsNormally);
        StagingEnvironment.resetForTest();
      },
    );

    test(
      'staging allowlist cannot authorize production or admin operations',
      () {
        expect(SecureBackend.productionAuthorized, isFalse);
        expect(
          SecureBackend.isStagingOperationAllowed('listPublicContent'),
          isTrue,
        );
        expect(
          SecureBackend.isStagingOperationAllowed('getPublicContentDetail'),
          isTrue,
        );
        expect(SecureBackend.isStagingOperationAllowed('getPublicJob'), isTrue);
        expect(
          SecureBackend.isStagingOperationAllowed('submitUserOperation'),
          isFalse,
        );
        expect(
          SecureBackend.isStagingOperationAllowed('getSearchJob'),
          isFalse,
        );
        expect(SecureBackend.isStagingOperationAllowed('adminWrite'), isFalse);
      },
    );

    test(
      'staging transport verifies readiness before invoking callable',
      () async {
        var calls = 0;
        SecureBackend.stagingEnabledOverride = true;
        SecureBackend.stagingInvokerOverride = (name, data) async {
          calls++;
          expect(name, 'getPublicJob');
          expect(data, {'id': 'public-job-id'});
          return {'status': 'unavailable'};
        };

        await expectLater(
          SecureBackend.invoke('getPublicJob', {'id': 'public-job-id'}),
          throwsStateError,
        );
        expect(calls, 0);

        StagingEnvironment.markReadyForTest();
        expect(
          await SecureBackend.invoke('getPublicJob', {'id': 'public-job-id'}),
          {'status': 'unavailable'},
        );
        expect(calls, 1);
        await expectLater(
          SecureBackend.invoke('submitUserOperation', const {}),
          throwsArgumentError,
        );
        expect(calls, 1);
      },
    );
  });

  test('Gradle requires a separate staged Firebase config and package', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('src/staging/google-services.json'));
    expect(gradle, contains('STAGING_FIREBASE_PROJECT_ID'));
    expect(gradle, contains('br.com.tudoaquimacacu.tudo_aqui_macacu.staging'));
  });
}
