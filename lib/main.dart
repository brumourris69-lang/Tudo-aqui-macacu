import 'dart:async';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'core/config/local_network_isolation.dart';
import 'core/media/device_image_source.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'core/config/local_search_environment.dart';
import 'core/auth/app_check_setup.dart';
import 'core/auth/app_auth.dart';
import 'core/auth/admin_authorization.dart';

import 'redesigned_app.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (LocalSearchEnvironment.enabled) return;
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) await LocalNetworkIsolation.prepare();
  if (LocalSearchEnvironment.enabled) {
    GoogleFonts.config.allowRuntimeFetching = false;
  }
  unawaited(DeviceImageSource.instance.primeRecovery());
  ErrorWidget.builder = (details) => const AppRuntimeErrorView();
  try {
    if (LocalSearchEnvironment.enabled) {
      LocalSearchEnvironment.requireDemo(LocalSearchEnvironment.project);
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-emulator-api-key',
          appId: '1:000000000000:android:demo',
          messagingSenderId: '000000000000',
          projectId: LocalSearchEnvironment.project,
        ),
      );
      LocalSearchEnvironment.requireDemo(Firebase.app().options.projectId);
      for (final app in Firebase.apps) {
        LocalSearchEnvironment.requireDemo(app.options.projectId);
        await app.setAutomaticDataCollectionEnabled(false);
      }
      await FirebaseAuth.instance.useAuthEmulator(
        LocalSearchEnvironment.host,
        9097,
        automaticHostMapping: false,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        LocalSearchEnvironment.host,
        8087,
        automaticHostMapping: false,
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).useFunctionsEmulator(
        LocalSearchEnvironment.host,
        5007,
        automaticHostMapping: false,
      );
      // Prevent other existing regions/instances from using production.
      FirebaseFunctions.instance.useFunctionsEmulator(
        LocalSearchEnvironment.host,
        5007,
        automaticHostMapping: false,
      );
      FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(
        LocalSearchEnvironment.host,
        5007,
        automaticHostMapping: false,
      );
      await AppAuth.ensureVisitor().timeout(const Duration(seconds: 15));
      await FirebaseFirestore.instance
          .collection('home_pages')
          .doc('published')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      final probe = HttpClient();
      try {
        final request = await probe
            .getUrl(Uri.parse('http://${LocalSearchEnvironment.host}:5007/'))
            .timeout(const Duration(seconds: 5));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode != 404) {
          throw StateError('Functions Emulator inesperado.');
        }
        await response.drain<void>();
      } finally {
        probe.close(force: true);
      }
      debugPrint(
        'LOCAL ISOLATION VALIDATED: demo-universal-search; Auth=9097 Firestore=8087 Functions=5007; FCM off; native VPN active',
      );
    } else {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    await AppCheckSetup.prepare();
    await AdminAuthorization.instance.start();
  } catch (error, stackTrace) {
    // Never fall back to the production app after a demo bootstrap failure.
    if (LocalSearchEnvironment.enabled || AppCheckSetup.enabled) rethrow;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Tudo Aqui Macacu main',
      ),
    );
  }
  runApp(const RedesignedApp());
}

class AppRuntimeErrorView extends StatelessWidget {
  const AppRuntimeErrorView({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: soft,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: ink.withValues(alpha: .08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: orange.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: orange,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Ops, algo não carregou',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Feche e abra o app novamente. Se continuar, avise a gente para corrigirmos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
