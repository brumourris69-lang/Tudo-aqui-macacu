import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/spark_public_catalog_environment.dart';

void main() {
  const androidAppId = '1:801555679675:android:abcdef1234567890';
  const iosAppId = '1:801555679675:ios:abcdef1234567890';

  group('Spark distribution identity gate', () {
    test('keeps public projection reads on Beta and explicit distribution', () {
      expect(
        SparkPublicCatalogEnvironment.usesProjectionReads(betaBuild: true),
        isTrue,
      );
      expect(
        SparkPublicCatalogEnvironment.usesProjectionReads(betaBuild: false),
        SparkPublicCatalogEnvironment.enabled,
      );
    });

    test(
      'accepts the candidate only for a release with its platform identity',
      () {
        expect(
          SparkPublicCatalogEnvironment.acceptsBuildConfiguration(
            enabled: true,
            releaseBuild: true,
            betaBuild: false,
            localBuild: false,
            stagingBuild: false,
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            android: true,
            ios: false,
            configuredAndroidFirebaseAppId: androidAppId,
            configuredIosFirebaseAppId: iosAppId,
            configuredIosBundleIdentifier:
                SparkPublicCatalogEnvironment.iosBundleIdentifier,
          ),
          isTrue,
        );
        expect(
          SparkPublicCatalogEnvironment.acceptsBuildConfiguration(
            enabled: true,
            releaseBuild: true,
            betaBuild: false,
            localBuild: false,
            stagingBuild: false,
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            android: false,
            ios: true,
            configuredAndroidFirebaseAppId: androidAppId,
            configuredIosFirebaseAppId: iosAppId,
            configuredIosBundleIdentifier:
                SparkPublicCatalogEnvironment.iosBundleIdentifier,
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects Beta, demo, disabled, debug and wrong platform identities',
      () {
        bool accepts({
          bool enabled = true,
          bool release = true,
          bool beta = false,
          bool local = false,
          bool staging = false,
          String project = SparkPublicCatalogEnvironment.candidateProjectId,
          String androidApp = androidAppId,
          String iosApp = iosAppId,
          String bundle = SparkPublicCatalogEnvironment.iosBundleIdentifier,
          bool android = true,
          bool ios = false,
        }) => SparkPublicCatalogEnvironment.acceptsBuildConfiguration(
          enabled: enabled,
          releaseBuild: release,
          betaBuild: beta,
          localBuild: local,
          stagingBuild: staging,
          configuredProjectId: project,
          android: android,
          ios: ios,
          configuredAndroidFirebaseAppId: androidApp,
          configuredIosFirebaseAppId: iosApp,
          configuredIosBundleIdentifier: bundle,
        );

        expect(accepts(enabled: false), isFalse);
        expect(accepts(release: false), isFalse);
        expect(accepts(beta: true), isFalse);
        expect(accepts(local: true), isFalse);
        expect(accepts(staging: true), isFalse);
        expect(accepts(project: 'macacu-beta-261030-cf4a81'), isFalse);
        expect(accepts(project: 'demo-universal-search'), isFalse);
        expect(accepts(androidApp: '1:000000000000:android:demo'), isFalse);
        expect(accepts(androidApp: iosAppId), isFalse);
        expect(accepts(android: true, ios: true), isFalse);
        expect(accepts(android: false, ios: false), isFalse);
        expect(
          accepts(android: false, ios: true, bundle: 'wrong.bundle'),
          isFalse,
        );
        expect(
          accepts(android: false, ios: true, iosApp: androidAppId),
          isFalse,
        );
      },
    );

    test(
      'runtime identity must match configured project and app registration',
      () {
        expect(
          SparkPublicCatalogEnvironment.matchesRuntimeIdentity(
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            actualProjectId: SparkPublicCatalogEnvironment.candidateProjectId,
            actualFirebaseAppId: androidAppId,
            configuredFirebaseAppId: androidAppId,
            expectedAndroidFirebaseAppId: androidAppId,
            expectedIosFirebaseAppId: iosAppId,
            android: true,
            ios: false,
          ),
          isTrue,
        );
        expect(
          SparkPublicCatalogEnvironment.matchesRuntimeIdentity(
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            actualProjectId: 'macacu-beta-261030-cf4a81',
            actualFirebaseAppId: androidAppId,
            configuredFirebaseAppId: androidAppId,
            expectedAndroidFirebaseAppId: androidAppId,
            expectedIosFirebaseAppId: iosAppId,
            android: true,
            ios: false,
          ),
          isFalse,
        );
        expect(
          SparkPublicCatalogEnvironment.matchesRuntimeIdentity(
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            actualProjectId: SparkPublicCatalogEnvironment.candidateProjectId,
            actualFirebaseAppId: '1:000000000000:android:demo',
            configuredFirebaseAppId: androidAppId,
            expectedAndroidFirebaseAppId: androidAppId,
            expectedIosFirebaseAppId: iosAppId,
            android: true,
            ios: false,
          ),
          isFalse,
        );
        expect(
          SparkPublicCatalogEnvironment.matchesRuntimeIdentity(
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            actualProjectId: SparkPublicCatalogEnvironment.candidateProjectId,
            actualFirebaseAppId: iosAppId,
            configuredFirebaseAppId: iosAppId,
            expectedAndroidFirebaseAppId: androidAppId,
            expectedIosFirebaseAppId: iosAppId,
            android: false,
            ios: true,
            actualIosBundleIdentifier:
                SparkPublicCatalogEnvironment.iosBundleIdentifier,
          ),
          isTrue,
        );
        expect(
          SparkPublicCatalogEnvironment.matchesRuntimeIdentity(
            configuredProjectId:
                SparkPublicCatalogEnvironment.candidateProjectId,
            actualProjectId: SparkPublicCatalogEnvironment.candidateProjectId,
            actualFirebaseAppId: iosAppId,
            configuredFirebaseAppId: iosAppId,
            expectedAndroidFirebaseAppId: androidAppId,
            expectedIosFirebaseAppId: iosAppId,
            android: false,
            ios: true,
            actualIosBundleIdentifier: 'wrong.bundle',
          ),
          isFalse,
        );
      },
    );

    test(
      'projection access remains denied until successful startup validation',
      () {
        SparkPublicCatalogEnvironment.resetForTest();
        expect(
          () => SparkPublicCatalogEnvironment.requireReady(
            actualProjectId: SparkPublicCatalogEnvironment.candidateProjectId,
          ),
          throwsStateError,
        );
      },
    );
  });
}
