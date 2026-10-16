import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android staging is a separate debug-only flavor with required config',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final manifest = File(
        'android/app/src/staging/AndroidManifest.xml',
      ).readAsStringSync();

      expect(gradle, contains('stagingRequested'));
      expect(gradle, contains('src/staging/google-services.json'));
      expect(gradle, contains('STAGING_FIREBASE_PROJECT_ID'));
      expect(
        gradle,
        contains('br.com.tudoaquimacacu.tudo_aqui_macacu.staging'),
      );
      expect(gradle, contains('withFlavor("environment" to "staging")'));
      expect(manifest, contains('Tudo Aqui Macacu — Homologação'));
      expect(
        gradle,
        contains(
          'beforeVariants(selector().withFlavor("environment" to "staging"))',
        ),
      );
      expect(gradle, contains('applicationIdSuffix = ".staging"'));
      expect(gradle, contains('google-services.json'));
      expect(gradle, contains('tudo-aqui-macacu'));
      expect(gradle, contains('demo-universal-search'));
    },
  );
}
