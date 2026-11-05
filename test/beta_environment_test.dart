import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/google_sign_in_configuration.dart';
import 'package:tudo_aqui_macacu/core/auth/app_auth.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';

void main() {
  const valid = <String, Object>{
    'flavor': 'beta',
    'expectedProjectId': 'macacu-isolated-beta',
    'nativeExpectedProjectId': 'macacu-isolated-beta',
    'applicationId': BetaEnvironment.applicationId,
    'firebaseEnabled': true,
    'appCheckEnabled': true,
    'localSearchEnabled': false,
    'android': true,
    'ios': false,
    'iosBundleIdentifier': 'test.invalid.macacu.beta',
    'iosGoogleClientId': '123456789012-ios.apps.googleusercontent.com',
    'googleWebClientId': '123456789012-example.apps.googleusercontent.com',
    'nativeFirebaseAppId': '1:123456789012:android:abcdef0123456789',
    'nativeMessagingSenderId': '123456789012',
  };

  String? validate([Map<String, Object>? overrides]) {
    final value = {...valid, ...?overrides};
    return BetaEnvironment.validateConfiguration(
      flavor: value['flavor']! as String,
      expectedProjectId: value['expectedProjectId']! as String,
      nativeExpectedProjectId: value['nativeExpectedProjectId']! as String,
      applicationId: value['applicationId']! as String,
      firebaseEnabled: value['firebaseEnabled']! as bool,
      appCheckEnabled: value['appCheckEnabled']! as bool,
      localSearchEnabled: value['localSearchEnabled']! as bool,
      android: value['android']! as bool,
      ios: value['ios']! as bool,
      iosBundleIdentifier: value['iosBundleIdentifier']! as String,
      iosGoogleClientId: value['iosGoogleClientId']! as String,
      googleWebClientId: value['googleWebClientId']! as String,
      nativeFirebaseAppId: value['nativeFirebaseAppId']! as String,
      nativeMessagingSenderId: value['nativeMessagingSenderId']! as String,
    );
  }

  String? validateCode([Map<String, Object>? overrides]) {
    final value = {...valid, ...?overrides};
    return BetaEnvironment.validateConfigurationFailureCode(
      flavor: value['flavor']! as String,
      expectedProjectId: value['expectedProjectId']! as String,
      nativeExpectedProjectId: value['nativeExpectedProjectId']! as String,
      applicationId: value['applicationId']! as String,
      firebaseEnabled: value['firebaseEnabled']! as bool,
      appCheckEnabled: value['appCheckEnabled']! as bool,
      localSearchEnabled: value['localSearchEnabled']! as bool,
      android: value['android']! as bool,
      ios: value['ios']! as bool,
      iosBundleIdentifier: value['iosBundleIdentifier']! as String,
      iosGoogleClientId: value['iosGoogleClientId']! as String,
      googleWebClientId: value['googleWebClientId']! as String,
      nativeFirebaseAppId: value['nativeFirebaseAppId']! as String,
      nativeMessagingSenderId: value['nativeMessagingSenderId']! as String,
    );
  }

  test('accepts only a fully configured isolated Android Beta identity', () {
    expect(validate(), isNull);
    expect(
      validate({
        'expectedProjectId': 'macacu-beta-261030-cf4a81',
        'nativeExpectedProjectId': 'macacu-beta-261030-cf4a81',
      }),
      isNull,
    );
  });

  test(
    'accepts iOS only with an explicit matching Bundle ID and iOS app ID',
    () {
      expect(
        validate({
          'android': false,
          'ios': true,
          'applicationId': 'test.invalid.macacu.beta',
          'nativeFirebaseAppId': '1:123456789012:ios:abcdef0123456789',
          'iosGoogleClientId': '123456789012-ios.apps.googleusercontent.com',
        }),
        isNull,
      );
      expect(
        validate({
          'android': false,
          'ios': true,
          'applicationId': 'test.invalid.macacu.beta',
          'iosBundleIdentifier': '',
          'nativeFirebaseAppId': '1:123456789012:ios:abcdef0123456789',
          'iosGoogleClientId': '123456789012-ios.apps.googleusercontent.com',
        }),
        isNotNull,
      );
      expect(
        validate({
          'android': false,
          'ios': true,
          'applicationId': 'test.invalid.macacu.beta',
          'iosBundleIdentifier': 'test.invalid.other',
          'nativeFirebaseAppId': '1:123456789012:ios:abcdef0123456789',
        }),
        isNotNull,
      );
      expect(
        validate({
          'android': false,
          'ios': true,
          'applicationId': 'test.invalid.macacu.beta',
          'nativeFirebaseAppId': '1:123456789012:android:abcdef0123456789',
          'iosGoogleClientId': '123456789012-ios.apps.googleusercontent.com',
        }),
        isNotNull,
      );
    },
  );

  test('iOS identity is sourced only from its explicit build settings', () {
    final identity = BetaEnvironment.readIosBuildIdentity();
    expect(identity['beta'], BetaEnvironment.iosBuildEnabled);
    expect(identity['expectedProject'], BetaEnvironment.iosExpectedProjectId);
    expect(identity['bundleIdentifier'], BetaEnvironment.iosBundleIdentifier);
    expect(identity['firebaseAppId'], BetaEnvironment.iosFirebaseAppId);
    expect(identity['iosGoogleClientId'], BetaEnvironment.iosGoogleClientId);
    expect(
      identity['appleSignInEnabled'],
      BetaEnvironment.iosAppleSignInEnabled,
    );
  });

  test('iOS fails closed when required app identity is absent', () {
    expect(
      validateCode({
        'android': false,
        'ios': true,
        'applicationId': '',
        'iosBundleIdentifier': '',
        'iosGoogleClientId': '',
        'nativeExpectedProjectId': '',
        'nativeFirebaseAppId': '',
        'nativeMessagingSenderId': '',
      }),
      'ios_bundle_identifier_invalid',
    );
  });

  test('fails closed for missing configuration and wrong flavor/package', () {
    for (final override in <Map<String, Object>>[
      {'firebaseEnabled': false},
      {'appCheckEnabled': false},
      {'flavor': 'production'},
      {'applicationId': 'br.com.tudoaquimacacu.tudo_aqui_macacu'},
      {'android': false},
      {'android': true, 'ios': true},
      {'localSearchEnabled': true},
      {'googleWebClientId': ''},
      {'nativeFirebaseAppId': ''},
      {'nativeMessagingSenderId': ''},
    ]) {
      expect(validate(override), isNotNull, reason: '$override');
    }
  });

  test('configuration failures report a specific safe check code', () {
    expect(validateCode(), isNull);
    expect(
      validateCode({'nativeExpectedProjectId': 'another-beta-project'}),
      'native_project_mismatch',
    );
    expect(validateCode({'googleWebClientId': ''}), 'oauth_web_client_invalid');
    expect(
      validateCode({'firebaseEnabled': false}),
      'firebase_or_app_check_disabled',
    );
    expect(
      validateCode({'nativeFirebaseAppId': ''}),
      'firebase_app_identity_invalid',
    );
  });

  test('rejects production, shared staging, demo and non-Beta project IDs', () {
    for (final project in [
      'tudo-aqui-macacu',
      'macacu-staging-261022',
      'demo-universal-search',
      'macacu-piloto',
      'macacu-staging-beta',
      'macacu-production-testing',
      'macacu-beta-not-a-unique-id',
    ]) {
      expect(
        validate({'expectedProjectId': project}),
        isNotNull,
        reason: project,
      );
    }
  });

  test('rejects any disagreement among independent project identities', () {
    expect(
      validate({'nativeExpectedProjectId': 'other-beta-project'}),
      isNotNull,
    );
  });

  test('Firebase app ID must belong to the explicitly configured sender', () {
    String? validateFirebase({
      String projectId = 'macacu-isolated-beta',
      String appId = '1:123456789012:android:abcdef0123456789',
      String senderId = '123456789012',
    }) => BetaEnvironment.validateFirebaseIdentity(
      expectedProjectId: 'macacu-isolated-beta',
      actualProjectId: projectId,
      appId: appId,
      messagingSenderId: senderId,
    );

    expect(validateFirebase(appId: '1:999999999999:android:abcdef'), isNotNull);
    expect(validateFirebase(appId: 'not-an-app-id'), isNotNull);
    expect(
      validateFirebase(appId: '1:123456789012:android:abcde-fghijk_123456'),
      isNull,
    );
    expect(validateFirebase(projectId: 'tudo-aqui-macacu'), isNotNull);
    expect(
      BetaEnvironment.validateFirebaseIdentity(
        expectedProjectId: 'macacu-isolated-beta',
        actualProjectId: 'macacu-isolated-beta',
        appId: '1:123456789012:ios:abcdef0123456789',
        messagingSenderId: '123456789012',
        ios: true,
        expectedAppId: '1:123456789012:ios:abcdef0123456789',
        expectedMessagingSenderId: '123456789012',
        expectedBundleIdentifier: 'test.invalid.macacu.beta',
        actualBundleIdentifier: 'test.invalid.macacu.beta',
        expectedIosGoogleClientId:
            '123456789012-ios.apps.googleusercontent.com',
        actualIosGoogleClientId: '123456789012-ios.apps.googleusercontent.com',
      ),
      isNull,
    );
    expect(
      BetaEnvironment.validateFirebaseIdentity(
        expectedProjectId: 'macacu-isolated-beta',
        actualProjectId: 'macacu-isolated-beta',
        appId: '1:123456789012:ios:abcdef0123456789',
        messagingSenderId: '123456789012',
        ios: true,
        expectedAppId: '1:123456789012:ios:expected-app',
        expectedBundleIdentifier: 'test.invalid.macacu.beta',
        actualBundleIdentifier: 'test.invalid.other',
        expectedIosGoogleClientId:
            '123456789012-ios.apps.googleusercontent.com',
        actualIosGoogleClientId:
            '123456789012-other.apps.googleusercontent.com',
      ),
      isNotNull,
    );
    expect(
      BetaEnvironment.validateFirebaseIdentity(
        expectedProjectId: 'macacu-isolated-beta',
        actualProjectId: 'macacu-isolated-beta',
        appId: '1:123456789012:android:abcdef0123456789',
        messagingSenderId: '123456789012',
        ios: true,
      ),
      isNotNull,
    );
  });

  test('native Firebase resources are validated before SDK initialization', () {
    expect(
      BetaEnvironment.validateFirebaseAppIdentity(
        appId: '',
        messagingSenderId: '',
      ),
      isNotNull,
    );
    expect(
      BetaEnvironment.validateFirebaseAppIdentity(
        appId: '1:999999999999:android:abcdef0123456789',
        messagingSenderId: '123456789012',
      ),
      isNotNull,
    );
  });

  test('Beta cannot reuse the production Google OAuth client ID', () {
    expect(
      validate({'googleWebClientId': productionGoogleWebClientId}),
      isNotNull,
    );
  });

  test('Google native OAuth client is explicit only for iOS Beta', () {
    expect(
      googleSignInNativeClientId(
        betaVariant: true,
        ios: true,
        betaIosClientId: '123456789012-ios.apps.googleusercontent.com',
      ),
      '123456789012-ios.apps.googleusercontent.com',
    );
    expect(
      googleSignInNativeClientId(
        betaVariant: true,
        ios: false,
        betaIosClientId: '',
      ),
      isNull,
    );
    expect(
      () => googleSignInNativeClientId(
        betaVariant: true,
        ios: true,
        betaIosClientId: '',
      ),
      throwsStateError,
    );
  });

  test('readiness is required and resettable for isolated tests', () {
    BetaEnvironment.resetForTest();
    expect(() => BetaEnvironment.requireReady(), throwsStateError);
    BetaEnvironment.markReadyForTest();
    expect(() => BetaEnvironment.requireReady(), returnsNormally);
    BetaEnvironment.resetForTest();
    expect(() => BetaEnvironment.requireReady(), throwsStateError);
  });

  test(
    'Beta and local public browsing do not create anonymous Auth sessions',
    () {
      expect(
        shouldCreateVisitorSession(
          localSearchEnabled: false,
          stagingEnabled: false,
          betaEnabled: true,
          productionAuthorized: false,
          normalDebugAuthorized: false,
        ),
        isFalse,
      );
      expect(
        shouldCreateVisitorSession(
          localSearchEnabled: true,
          stagingEnabled: false,
          betaEnabled: false,
          productionAuthorized: false,
          normalDebugAuthorized: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'local demo and Beta validate restored sessions without creating visitors',
    () {
      expect(
        shouldValidateRestoredSession(
          localSearchEnabled: true,
          betaEnabled: false,
          createVisitorSession: false,
        ),
        isTrue,
      );
      expect(
        shouldValidateRestoredSession(
          localSearchEnabled: false,
          betaEnabled: true,
          createVisitorSession: false,
        ),
        isTrue,
      );
      expect(
        shouldValidateRestoredSession(
          localSearchEnabled: false,
          betaEnabled: false,
          createVisitorSession: false,
        ),
        isFalse,
      );
    },
  );
}
