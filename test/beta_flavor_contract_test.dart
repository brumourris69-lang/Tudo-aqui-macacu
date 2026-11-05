import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Beta is a separate debug-only Android flavor with no production config fallback',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final gitignore = File('.gitignore').readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/MainActivity.kt',
      ).readAsStringSync();
      final bootstrap = File('lib/main.dart').readAsStringSync();
      final betaStart = bootstrap.indexOf(
        '    } else if (BetaEnvironment.enabled) {',
      );
      final betaEnd = bootstrap.indexOf(
        '} else if (StagingEnvironment.enabled)',
        betaStart,
      );
      expect(betaStart, greaterThanOrEqualTo(0));
      expect(betaEnd, greaterThan(betaStart));
      final betaBootstrap = bootstrap.substring(betaStart, betaEnd);
      final environment = File(
        'lib/core/config/beta_environment.dart',
      ).readAsStringSync();

      expect(gradle, contains('create("beta")'));
      expect(gradle, contains('applicationIdSuffix = ".beta"'));
      expect(gradle, contains('name.contains("Beta")'));
      expect(gradle, contains('check(!betaRequested)'));
      expect(gradle, contains('withFlavor("environment" to "beta")'));
      expect(gradle, contains('src/beta/google-services.json'));
      expect(gradle, contains('verifyBetaFirebaseConfiguration()'));
      expect(gradle, contains('isIsolatedBetaProjectId(expected)'));
      expect(gradle, contains('oauthClients.none'));
      expect(gradle, contains('!betaFirebaseConfig.isFile'));
      expect(gradle, contains('clearMissingBetaFirebaseResources'));
      expect(gradle, contains(r'startsWith("1:$projectNumber:android:")'));
      expect(manifest, contains('macacu.betaFirebaseProjectId'));
      expect(activity, contains('packageName.endsWith(".beta")'));
      expect(activity, contains('"expectedProject" to expectedProject'));
      expect(activity, contains('PackageManager.GET_META_DATA'));
      expect(activity, contains('macacu.betaFirebaseProjectId'));
      expect(activity, contains('"googleWebClientId" to googleWebClientId'));
      expect(activity, contains('"firebaseAppId" to firebaseAppId'));
      expect(activity, contains('"messagingSenderId" to messagingSenderId'));
      expect(bootstrap, contains('await Firebase.initializeApp();'));
      expect(bootstrap, contains('nativeGoogleWebClientId: googleWebClientId'));
      expect(bootstrap, contains('nativeFirebaseAppId: firebaseAppId'));
      expect(bootstrap, contains('nativeMessagingSenderId: messagingSenderId'));
      expect(environment, contains("BETA_IOS_FIREBASE_PROJECT_ID"));
      expect(environment, contains("BETA_IOS_BUNDLE_ID"));
      expect(environment, contains("BETA_IOS_FIREBASE_APP_ID"));
      expect(environment, contains("BETA_IOS_GOOGLE_CLIENT_ID"));
      expect(bootstrap, contains('BetaEnvironment.readIosBuildIdentity()'));
      expect(
        bootstrap,
        contains('Platform.isIOS && !BetaEnvironment.iosBuildEnabled'),
      );
      expect(bootstrap, contains('Firebase.app().options.iosBundleId'));
      expect(bootstrap, contains('Firebase.app().options.iosClientId'));
      expect(
        betaBootstrap.indexOf('BetaStartupStage.configuration'),
        lessThan(
          betaBootstrap.indexOf('BetaStartupStage.firebaseInitialization'),
        ),
      );
      expect(bootstrap, contains('if (BetaEnvironment.enabled)'));
      expect(bootstrap, contains('betaStartupFailed'));
      expect(bootstrap, contains('No fallback was attempted.'));
      expect(environment, isNot(contains('BETA_FIREBASE_API_KEY')));
      expect(environment, isNot(contains('firebaseOptions')));
      expect(gitignore, contains('android/app/src/beta/google-services.json'));
    },
  );
}
